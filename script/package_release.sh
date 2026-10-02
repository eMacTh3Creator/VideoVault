#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUTPUT=${1:-/tmp/VideoVault-release-artifacts}
PACKAGES=${VIDEOVAULT_PACKAGES:-/tmp/VideoVault-packages}
BUILD=${VIDEOVAULT_BUILD:-/tmp/VideoVault-release}
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/VideoVault/Info.plist")
BUILD_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/VideoVault/Info.plist")

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

xcodebuild -quiet -project "$ROOT/VideoVault.xcodeproj" -scheme VideoVault \
    -configuration Release -destination 'generic/platform=macOS' \
    -clonedSourcePackagesDirPath "$PACKAGES" -derivedDataPath "$BUILD" \
    'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGN_IDENTITY=- build

APP="$BUILD/Build/Products/Release/VideoVault.app"
codesign --verify --deep --strict "$APP"
ARCHITECTURES=" $(lipo -archs "$APP/Contents/MacOS/VideoVault") "
[[ "$ARCHITECTURES" == *" arm64 "* && "$ARCHITECTURES" == *" x86_64 "* ]]
SPARKLE="$PACKAGES/artifacts/sparkle/Sparkle/bin"
PUBLIC_KEY=$("$SPARKLE/generate_keys" --account videovault -p)
EXPECTED_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")
if [[ "$PUBLIC_KEY" != "$EXPECTED_KEY" ]]; then
    echo 'The VideoVault Sparkle signing key is missing or does not match the app.' >&2
    exit 1
fi

mkdir -p "$OUTPUT"
ARCHIVE="$OUTPUT/VideoVault-v${VERSION}-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
if [[ -f "$ROOT/docs/appcast.xml" ]]; then cp "$ROOT/docs/appcast.xml" "$OUTPUT/appcast.xml"; fi
cp "$ROOT/docs/release-notes.html" "$OUTPUT/VideoVault-v${VERSION}-macOS.html"
"$SPARKLE/generate_appcast" --account videovault --versions "$BUILD_VERSION" --maximum-deltas 0 \
    --download-url-prefix "https://github.com/eMacTh3Creator/VideoVault/releases/download/v${VERSION}/" \
    --link "https://emacth3creator.github.io/VideoVault/" --embed-release-notes "$OUTPUT"
"$SPARKLE/sign_update" --account videovault --verify "$OUTPUT/appcast.xml"
cp "$OUTPUT/appcast.xml" "$ROOT/docs/appcast.xml"
(cd "$OUTPUT" && shasum -a 256 "$(basename "$ARCHIVE")") > "$OUTPUT/SHA256SUMS.txt"
echo "Release archive: $ARCHIVE"
echo "Signed update feed: $ROOT/docs/appcast.xml"
echo 'Upload the archive to the matching GitHub release before publishing the update feed.'
