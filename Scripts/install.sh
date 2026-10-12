#!/bin/bash
# Install or update Tinycast from this repo's latest release, or from <tag>. Usage: install.sh [tag]
#
# Needs only `gh`, logged in to an account that can read the repo. On a Mac without a checkout:
#   gh api repos/okbytes/tinycast/contents/Scripts/install.sh \
#     -H "Accept: application/vnd.github.raw" | bash -s [tag]
# The install path is fixed because the Accessibility and Input Monitoring grants follow it.
set -euo pipefail

REPO="okbytes/tinycast"
DEST="$HOME/Applications/Tinycast.app"
BUNDLE_ID="com.tinycast.app"

fail() {
    echo "✗ $1" >&2
    exit 1
}

command -v gh >/dev/null || fail "Install the GitHub CLI (brew install gh), then run: gh auth login"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "▸ Downloading ${1:-the latest release}…"
gh release download ${1:+"$1"} --repo "$REPO" --pattern 'Tinycast-*.zip' --dir "$WORK"
ditto -x -k "$WORK"/Tinycast-*.zip "$WORK"
APP="$WORK/Tinycast.app"
spctl --assess --type execute "$APP" || fail "The download is not a notarized build."
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$APP/Contents/Info.plist")"

if pgrep -qf "$DEST/Contents/MacOS/"; then
    echo "▸ Quitting the running copy…"
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 50); do
        pgrep -qf "$DEST/Contents/MacOS/" || break
        sleep 0.1
    done
    pkill -f "$DEST/Contents/MacOS/" 2>/dev/null || true
fi

echo "▸ Installing $DEST"
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$APP" "$DEST"
open "$DEST"
echo "✓ Tinycast $VERSION is running"
