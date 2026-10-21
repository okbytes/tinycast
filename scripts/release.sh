#!/bin/bash
# Build, notarize and publish a Tinycast release on this repo. Usage: ./scripts/release.sh [version]
# With no version it bumps the latest release's minor: after v0.18.0 comes 0.19.0.
#
# Needs a Developer ID Application certificate and the `tinycast` notarytool profile, both made once
# (docs/signing.md). The release is tagged v<version> at HEAD; scripts/install.sh puts it on a Mac.
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
REPO="okbytes/tinycast"
PROFILE="tinycast"
DERIVED="build/ReleaseDerivedData.noindex"
APP="$DERIVED/Build/Products/Release/Tinycast.app"

fail() {
    echo "✗ $1" >&2
    exit 1
}

latest="$(gh release view --repo "$REPO" --json tagName -q .tagName 2>/dev/null || echo none)"
if [ $# -gt 0 ]; then
    VERSION="$1"
elif [[ "$latest" =~ ^v([0-9]+)\.([0-9]+)\.[0-9]+$ ]]; then
    VERSION="${BASH_REMATCH[1]}.$((BASH_REMATCH[2] + 1)).0"
else
    fail "No release to bump from (latest: $latest); pass a version: release.sh <version>"
fi
TAG="v$VERSION"
ZIP="build/Tinycast-$VERSION.zip"

security find-identity -p codesigning -v | grep -q '"Developer ID Application' ||
    fail "No Developer ID Application certificate in the keychain (docs/signing.md)."
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 ||
    fail "No notarytool profile named '$PROFILE' (docs/signing.md)."
[ -z "$(git status --porcelain)" ] || fail "Commit or discard local changes first."
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || fail "$TAG already exists."
! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 || fail "Release $TAG already exists."

echo "▸ Building Tinycast $VERSION ($(git rev-parse --short HEAD))…"
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
    -derivedDataPath "$DERIVED" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$(git rev-list --count HEAD)" \
    clean build -quiet
./scripts/verify-signature.sh "$APP"

echo "▸ Notarizing…"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
result="$(xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait --output-format json)"
if [ "$(plutil -extract status raw -o - - <<<"$result")" != "Accepted" ]; then
    id="$(plutil -extract id raw -o - - <<<"$result" 2>/dev/null || true)"
    [ -n "$id" ] && xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2
    fail "Notarization was not accepted."
fi
xcrun stapler staple -q "$APP"
spctl --assess --type execute "$APP" || fail "Gatekeeper rejects the stapled app."
# Re-zipped so the copy that ships carries its ticket and opens offline.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ Publishing ${TAG}…"
git tag -a "$TAG" -m "Tinycast $VERSION"
git push -q origin "$TAG"
if [ "$latest" = none ]; then
    notes="First release."
else
    notes="$(git log --format='- %s' "$latest..$TAG")"
fi
gh release create "$TAG" "$ZIP" --repo "$REPO" --title "Tinycast $VERSION" --notes "$notes"
echo "✓ Tinycast $VERSION is released; ./scripts/install.sh installs it"
