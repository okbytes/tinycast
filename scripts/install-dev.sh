#!/bin/bash
# Pull, build a team-signed Tinycast Dev and swap it into ~/Applications. Usage: ./scripts/install-dev.sh
#
# Team-signed because the keyboard helper's XPC check requires a team ID (docs/features/key-remap.md).
# A fixed install path keeps the Accessibility and Input Monitoring grants across updates, and the
# running helper exits by itself once its executable is replaced. The build folder ends in .noindex
# so Spotlight, and every launcher reading it, lists only the installed copy. --no-pull builds the
# checkout as it is.
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
DERIVED="build/DevDerivedData.noindex"
APP_NAME="Tinycast Dev.app"
DEST="$HOME/Applications/$APP_NAME"
BUNDLE_ID="com.tinycast.app.dev"

if ! security find-identity -p codesigning -v | grep -q '"Apple Development'; then
    echo "✗ No Apple Development certificate — sign in to Xcode (Settings ▸ Accounts)." >&2
    exit 1
fi

if [ "${1:-}" != "--no-pull" ] && git rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
    if [ -z "$(git status --porcelain)" ]; then
        echo "▸ Pulling $(git rev-parse --abbrev-ref HEAD)…"
        git pull --ff-only
    else
        echo "▸ Local changes present; building the checkout as it is."
    fi
fi

echo "▸ Building ${APP_NAME}…"
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug \
    -derivedDataPath "$DERIVED" -destination platform=macOS \
    build -quiet

if pgrep -qf "$DEST/Contents/MacOS/"; then
    echo "▸ Quitting the running copy…"
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 50); do
        pgrep -qf "$DEST/Contents/MacOS/" || break
        sleep 0.1
    done
    pkill -f "$DEST/Contents/MacOS/" 2>/dev/null || true
fi

echo "▸ Installing ${DEST}"
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$DERIVED/Build/Products/Debug/$APP_NAME" "$DEST"
# A Shortcut running this script passes its temp-folder suffix down; the app must not inherit it.
env -u DIRHELPER_USER_DIR_SUFFIX TMPDIR="$(getconf DARWIN_USER_TEMP_DIR)" open "$DEST"
echo "✓ ${APP_NAME} $(git rev-parse --short HEAD) is running"
