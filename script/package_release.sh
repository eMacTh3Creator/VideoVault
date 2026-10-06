#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTPUT=${1:-/tmp/VideoVault-release-artifacts}
PACKAGES=${VIDEOVAULT_PACKAGES:-/tmp/VideoVault-packages}
BUILD=${VIDEOVAULT_BUILD:-/tmp/VideoVault-release}
ACCOUNT=${VIDEOVAULT_SIGNING_ACCOUNT:-videovault-v2}
SPARKLE="$PACKAGES/artifacts/sparkle/Sparkle/bin"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/VideoVault/Info.plist")
BUILD_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/VideoVault/Info.plist")
EXPECTED_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT/VideoVault/Info.plist")
PREFIX=${VIDEOVAULT_DOWNLOAD_PREFIX:-https://raw.githubusercontent.com/eMacTh3Creator/VideoVault/main/Releases/}
[[ "$PREFIX" == https://*/ ]] || { echo 'Download prefix must be HTTPS and end with /.' >&2; exit 1; }

if [[ ! -x "$SPARKLE/generate_keys" ]]; then
    xcodebuild -resolvePackageDependencies -project "$ROOT/VideoVault.xcodeproj" -clonedSourcePackagesDirPath "$PACKAGES"
fi
PUBLIC_KEY=$("$SPARKLE/generate_keys" --account "$ACCOUNT" -p) || {
    echo "Missing publisher key: $ACCOUNT. Restore it on the publishing Mac; customers never need this key." >&2
    exit 1
}
[[ "$PUBLIC_KEY" == "$EXPECTED_KEY" ]] || { echo 'Publisher key does not match the app.' >&2; exit 1; }

if [[ -z "${VIDEOVAULT_APP:-}" ]]; then
    xcodebuild -quiet -project "$ROOT/VideoVault.xcodeproj" -scheme VideoVault \
        -configuration Release -destination 'generic/platform=macOS' \
        -clonedSourcePackagesDirPath "$PACKAGES" -derivedDataPath "$BUILD" \
        'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
fi
STAGE=$(mktemp -d /tmp/VideoVault-package.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/VideoVault.app"
ditto --norsrc --noextattr "${VIDEOVAULT_APP:-$BUILD/Build/Products/Release/VideoVault.app}" "$APP"
cp "$PACKAGES/checkouts/Sparkle/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
chmod -R u+w "$APP"
xattr -cr "$APP"
codesign --force --deep --sign "${VIDEOVAULT_SIGN_IDENTITY:--}" "$APP"
codesign --verify --deep --strict "$APP"
lipo "$APP/Contents/MacOS/VideoVault" -verify_arch arm64 x86_64
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" == "$BUILD_VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")" == "$EXPECTED_KEY" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP/Contents/Info.plist")" == 'https://raw.githubusercontent.com/eMacTh3Creator/VideoVault/main/docs/appcast-v2.xml' ]]

DMGBUILD=${VIDEOVAULT_DMGBUILD:-$BUILD/dmg-venv/bin/dmgbuild}
if [[ ! -x "$DMGBUILD" ]]; then
    python3 -m venv "$BUILD/dmg-venv"
    "$BUILD/dmg-venv/bin/pip" install 'dmgbuild==1.6.5'
fi
swift "$ROOT/script/dmg_background.swift" "$STAGE/background.png"
mkdir -p "$OUTPUT"
DMG="$OUTPUT/VideoVault-v${VERSION}-macOS.dmg"
"$DMGBUILD" -s "$ROOT/script/dmg_settings.py" -D app="$APP" -D background="$STAGE/background.png" 'Install VideoVault' "$DMG"
hdiutil verify "$DMG"

# Keep only this release in the generation directory; do not sign test builds.
FEED="$STAGE/feed"
mkdir -p "$FEED"
cp "$DMG" "$FEED/"
if [[ -f "$ROOT/docs/appcast-v2.xml" ]]; then cp "$ROOT/docs/appcast-v2.xml" "$FEED/appcast-v2.xml"; fi
cp "$ROOT/docs/release-notes.html" "$FEED/VideoVault-v${VERSION}-macOS.html"
"$SPARKLE/generate_appcast" --account "$ACCOUNT" --versions "$BUILD_VERSION" --maximum-deltas 0 \
    --download-url-prefix "$PREFIX" --link 'https://emacth3creator.github.io/VideoVault/' \
    --embed-release-notes -o "$FEED/appcast-v2.xml" "$FEED"
"$SPARKLE/sign_update" --account "$ACCOUNT" --verify "$FEED/appcast-v2.xml"
cp "$FEED/appcast-v2.xml" "$OUTPUT/appcast-v2.xml"
swift "$ROOT/script/verify_release.swift" "$ROOT/VideoVault/Info.plist" "$OUTPUT/appcast-v2.xml" "$DMG"
(cd "$OUTPUT" && shasum -a 256 "$(basename "$DMG")") > "$OUTPUT/SHA256SUMS-v${VERSION}.txt"
echo "Release ready: $DMG"
echo "Verified signed feed: $OUTPUT/appcast-v2.xml"
echo 'Publish the DMG to Releases/ and the signed feed to docs/ in the same commit.'
