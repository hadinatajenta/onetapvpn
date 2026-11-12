#!/usr/bin/env bash
set -euo pipefail

APP_NAME="OneTapVPN"
BUNDLE_ID="com.erendt.onetapvpn"
USER_APP="$HOME/Applications/$APP_NAME.app"
SYSTEM_APP="/Applications/$APP_NAME.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
PURGE=false
REMOVAL_FAILED=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --purge)
            PURGE=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--purge]" >&2
            exit 1
            ;;
    esac
done

remove_bundle() {
    local bundle_path="$1"
    if [ ! -e "$bundle_path" ]; then
        return
    fi
    if rm -rf "$bundle_path"; then
        echo "Removed $bundle_path"
    else
        echo "Could not remove $bundle_path. Re-run with sudo if it is owned by root." >&2
        REMOVAL_FAILED=true
    fi
}

pkill -x "$APP_NAME" 2>/dev/null || true

remove_bundle "$USER_APP"
remove_bundle "$SYSTEM_APP"

launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true

if [ -e "$LAUNCH_AGENT" ]; then
    rm -f "$LAUNCH_AGENT"
    echo "Removed $LAUNCH_AGENT"
fi

if [ "$PURGE" = true ]; then
    if security delete-generic-password -s "$BUNDLE_ID" -a credentials >/dev/null 2>&1; then
        echo "Removed Keychain item $BUNDLE_ID"
    else
        echo "No Keychain item found for $BUNDLE_ID"
    fi
fi

if [ "$REMOVAL_FAILED" = true ]; then
    echo "Uninstall finished with errors." >&2
    exit 1
fi

echo "Uninstall complete."
