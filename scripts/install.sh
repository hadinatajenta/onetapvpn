#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="OneTapVPN"
DESTINATION_DIR="$HOME/Applications"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --system)
            DESTINATION_DIR="/Applications"
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--system]" >&2
            exit 1
            ;;
    esac
done

TARGET="$DESTINATION_DIR/$APP_NAME.app"

bash "$ROOT/scripts/build.sh"

mkdir -p "$DESTINATION_DIR"
rm -rf "$TARGET"
ditto "$ROOT/build/$APP_NAME.app" "$TARGET"
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
open "$TARGET"

echo "Installed $TARGET"
echo
echo "First run:"
echo "1. Open OneTapVPN from the menu bar and choose Settings."
echo "2. Enter your portal, username, password, and TOTP secret or otpauth URI."
echo "3. Confirm the live code matches your authenticator app, then save."
echo "4. Grant Accessibility access in System Settings > Privacy & Security > Accessibility."
echo "5. Click Test Connection and approve the GlobalProtect login if prompted."
