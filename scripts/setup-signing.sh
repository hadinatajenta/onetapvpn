#!/usr/bin/env bash
set -euo pipefail

SIGNING_DIR="$HOME/.config/onetapvpn/signing"
KEYCHAIN="$HOME/Library/Keychains/onetapvpn-signing.keychain-db"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
IDENTITY="OneTapVPN Local Signing"

mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"

if [ ! -f "$SIGNING_DIR/identity.p12" ]; then
    if [ ! -f "$SIGNING_DIR/key.pem" ] || [ ! -f "$SIGNING_DIR/cert.pem" ]; then
        cat > "$SIGNING_DIR/openssl.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3_req
prompt = no

[dn]
CN = OneTapVPN Local Signing

[v3_req]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF
        openssl req -x509 -newkey rsa:2048 \
            -keyout "$SIGNING_DIR/key.pem" \
            -out "$SIGNING_DIR/cert.pem" \
            -days 3650 \
            -nodes \
            -config "$SIGNING_DIR/openssl.cnf" >/dev/null 2>&1
    fi

    P12_PASSWORD="$(openssl rand -base64 24)"
    printf '%s' "$P12_PASSWORD" > "$SIGNING_DIR/p12-password.txt"
    chmod 600 "$SIGNING_DIR/p12-password.txt"
    openssl pkcs12 -export -legacy \
        -out "$SIGNING_DIR/identity.p12" \
        -inkey "$SIGNING_DIR/key.pem" \
        -in "$SIGNING_DIR/cert.pem" \
        -name "$IDENTITY" \
        -passout "pass:$P12_PASSWORD" >/dev/null 2>&1
fi

if [ ! -f "$SIGNING_DIR/keychain-password.txt" ]; then
    openssl rand -base64 24 > "$SIGNING_DIR/keychain-password.txt"
    chmod 600 "$SIGNING_DIR/keychain-password.txt"
fi

KEYCHAIN_PASSWORD="$(cat "$SIGNING_DIR/keychain-password.txt")"
P12_PASSWORD="$(cat "$SIGNING_DIR/p12-password.txt")"

if [ ! -f "$KEYCHAIN" ]; then
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
fi

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

if ! security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
    security import "$SIGNING_DIR/identity.p12" \
        -k "$KEYCHAIN" \
        -P "$P12_PASSWORD" \
        -T /usr/bin/codesign \
        -T /usr/bin/security >/dev/null
fi

security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$KEYCHAIN_PASSWORD" \
    "$KEYCHAIN" >/dev/null

if ! security find-identity -v -p codesigning "$KEYCHAIN" | grep -q "$IDENTITY"; then
    security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$SIGNING_DIR/cert.pem" >/dev/null
fi

CURRENT_KEYCHAINS=()
while IFS= read -r keychain; do
    keychain="${keychain//\"/}"
    keychain="${keychain#"${keychain%%[![:space:]]*}"}"
    if [ -n "$keychain" ]; then
        CURRENT_KEYCHAINS+=("$keychain")
    fi
done < <(security list-keychains -d user)

HAS_KEYCHAIN=false
for keychain in "${CURRENT_KEYCHAINS[@]:-}"; do
    if [ "$keychain" = "$KEYCHAIN" ]; then
        HAS_KEYCHAIN=true
    fi
done

if [ "$HAS_KEYCHAIN" = false ]; then
    security list-keychains -d user -s "$KEYCHAIN" "${CURRENT_KEYCHAINS[@]}"
fi

printf 'Signing identity ready: %s\n' "$IDENTITY"
printf 'Keychain: %s\n' "$KEYCHAIN"
security find-identity -v -p codesigning "$KEYCHAIN"
