#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="OneTapVPN"
BUNDLE_ID="com.erendt.onetapvpn"
APP_DIR="build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
EXECUTABLE="$MACOS_DIR/$APP_NAME"

FILES=()
while IFS= read -r file; do
    FILES+=("$file")
done < <(find Sources -name '*.swift' -print | sort)

if [ "${#FILES[@]}" -eq 0 ]; then
    echo "No Swift source files found under $ROOT/Sources." >&2
    exit 1
fi

if [ ! -f Resources/Info.plist ]; then
    echo "Missing $ROOT/Resources/Info.plist." >&2
    exit 1
fi

if [ ! -f Resources/AppIcon.icns ]; then
    bash "$ROOT/scripts/make-icon.sh"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$CONTENTS_DIR/Resources"

swiftc -O -swift-version 5 \
    -target "$(uname -m)-apple-macosx13.0" \
    -framework AppKit \
    -framework AVFoundation \
    -framework SwiftUI \
    -framework Combine \
    -framework Security \
    -framework CryptoKit \
    -o "$EXECUTABLE" \
    "${FILES[@]}"

cp Resources/Info.plist "$CONTENTS_DIR/Info.plist"
cp Resources/AppIcon.icns "$CONTENTS_DIR/Resources/AppIcon.icns"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

xattr -cr "$APP_DIR"

SIGNING_DIR="$HOME/.config/onetapvpn/signing"
SIGNING_KEYCHAIN="$HOME/Library/Keychains/onetapvpn-signing.keychain-db"
SIGNING_IDENTITY="OneTapVPN Local Signing"
SIGNING_READY=false

if [ -f "$SIGNING_KEYCHAIN" ] && [ -f "$SIGNING_DIR/keychain-password.txt" ]; then
    KEYCHAIN_PASSWORD="$(cat "$SIGNING_DIR/keychain-password.txt")"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN" >/dev/null 2>&1 || true
    if security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" 2>/dev/null | grep -q "$SIGNING_IDENTITY"; then
        SIGNING_READY=true
    fi
fi

if [ "$SIGNING_READY" = true ]; then
    codesign --force --deep --sign "$SIGNING_IDENTITY" --identifier "$BUNDLE_ID" "$APP_DIR"
else
    echo "Warning: stable signing identity not found. Using ad-hoc signature." >&2
    echo "Run bash scripts/setup-signing.sh to keep Accessibility permission across rebuilds." >&2
    codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_DIR"
fi

echo "Built $ROOT/$APP_DIR"
