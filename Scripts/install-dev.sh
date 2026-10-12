#!/bin/bash
# Pull, build a team-signed Tinycast Dev and swap it into ~/Applications. Usage: ./Scripts/install-dev.sh
#
# Team-signed because the keyboard helper's XPC check requires a team ID (docs/features/key-remap.md).
# A fixed install path keeps the Accessibility and Input Monitoring grants across updates, and the
# running helper exits by itself once its executable is replaced. TINYCAST_TEAM overrides the team
# read from the first Apple Development certificate; --no-pull builds the checkout as it is.
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
IDENTITY="Apple Development"
DERIVED="build/DevDerivedData"
APP_NAME="Tinycast Dev.app"
DEST="$HOME/Applications/$APP_NAME"
BUNDLE_ID="com.tinycast.app.dev"

team="${TINYCAST_TEAM:-$(security find-certificate -c "$IDENTITY" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p')}"
if [ -z "$team" ]; then
    echo "✗ No '$IDENTITY' certificate found — sign in to Xcode with your Apple ID (Settings ▸ Accounts)." >&2
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

echo "▸ Building ${APP_NAME} for team ${team}…"
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Debug \
    -derivedDataPath "$DERIVED" -destination "platform=macOS,arch=$(uname -m)" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$team" \
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
open "$DEST"
echo "✓ ${APP_NAME} $(git rev-parse --short HEAD) is running"
