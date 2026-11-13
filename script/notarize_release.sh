#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [[ "${1:-}" == '--help' ]]; then
    echo 'Usage: bash script/notarize_release.sh OUTPUT_DIRECTORY [KEYCHAIN_PROFILE]'
    echo 'Notarizes an existing signed Mac release without launching the app.'
    echo 'Uses new -notarized filenames so existing signed downloads remain valid.'
    exit 0
fi
OUTPUT=${1:?Pass a new output directory}
PROFILE=${2:-${VIDEOVAULT_NOTARY_PROFILE:-VideoVaultNotary}}
PACKAGES=${VIDEOVAULT_PACKAGES:-/tmp/VideoVault-packages}
BUILD=${VIDEOVAULT_BUILD:-/tmp/VideoVault-release}
ACCOUNT=${VIDEOVAULT_SIGNING_ACCOUNT:-videovault-v3}
SPARKLE="$PACKAGES/artifacts/sparkle/Sparkle/bin"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/VideoVault/Info.plist")
BUILD_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/VideoVault/Info.plist")
SOURCE=${VIDEOVAULT_NOTARY_ARCHIVE:-$ROOT/Releases/VideoVault-v${VERSION}-macOS.zip}
PREFIX=${VIDEOVAULT_DOWNLOAD_PREFIX:-https://raw.githubusercontent.com/eMacTh3Creator/VideoVault/main/Releases/}
DMGBUILD=${VIDEOVAULT_DMGBUILD:-$BUILD/dmg-venv/bin/dmgbuild}

[[ "$PREFIX" == https://*/ ]] || { echo 'Download prefix must be HTTPS and end with /.' >&2; exit 1; }
[[ -f "$SOURCE" && -x "$DMGBUILD" && -x "$SPARKLE/generate_appcast" ]] || {
    echo 'Prepare the signed release, dmgbuild environment, and Sparkle tools first.' >&2; exit 1;
}
[[ ! -e "$OUTPUT" ]] || { echo 'Use a new output directory to preserve submission evidence.' >&2; exit 1; }
xcrun notarytool history --keychain-profile "$PROFILE" --output-format json >/dev/null
mkdir -p "$OUTPUT"
OUTPUT=$(cd "$OUTPUT" && pwd)
STAGE=$(mktemp -d /tmp/VideoVault-notarize.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT

check_submission() {
    local archive=$1 result=$2 log=$3 id expected actual
    [[ "$(plutil -extract status raw -o - "$result")" == 'Accepted' ]] || {
        echo "Apple did not accept the submission. See $result; no release was changed." >&2; exit 1;
    }
    id=$(plutil -extract id raw -o - "$result")
    xcrun notarytool log "$id" --keychain-profile "$PROFILE" "$log"
    [[ "$(plutil -extract status raw -o - "$log")" == 'Accepted' ]]
    expected=$(plutil -extract sha256 raw -o - "$log" | tr '[:upper:]' '[:lower:]')
    actual=$(shasum -a 256 "$archive" | awk '{print $1}')
    [[ "$expected" == "$actual" ]] || { echo 'Submission archive checksum mismatch.' >&2; exit 1; }
}

# A completed background submission can be reused only for the exact archive.
if [[ -n "${VIDEOVAULT_APP_NOTARY_RESULT:-}" ]]; then
    cp "$VIDEOVAULT_APP_NOTARY_RESULT" "$OUTPUT/app-notary-result.json"
else
    xcrun notarytool submit "$SOURCE" --keychain-profile "$PROFILE" --wait \
        --timeout 20m --output-format json > "$OUTPUT/app-notary-result.json"
fi
check_submission "$SOURCE" "$OUTPUT/app-notary-result.json" "$OUTPUT/app-notary-log.json"
ditto -x -k "$SOURCE" "$STAGE"
APP="$STAGE/VideoVault.app"
codesign --verify --deep --strict "$APP"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")" == "$BUILD_VERSION" ]]
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

ZIP="$OUTPUT/VideoVault-v${VERSION}-macOS-notarized.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
swift "$ROOT/script/dmg_background.swift" "$STAGE/background.png"
DMG="$OUTPUT/VideoVault-v${VERSION}-macOS-notarized.dmg"
"$DMGBUILD" -s "$ROOT/script/dmg_settings.py" -D app="$APP" -D background="$STAGE/background.png" 'Install VideoVault' "$DMG"
IDENTITY=${VIDEOVAULT_SIGN_IDENTITY:-$(codesign -dv --verbose=4 "$APP" 2>&1 | sed -n 's/^Authority=\(Developer ID Application:.*\)$/\1/p')}
[[ -n "$IDENTITY" ]] || { echo 'A Developer ID identity is required for the disk image.' >&2; exit 1; }
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait \
    --timeout 20m --output-format json > "$OUTPUT/dmg-notary-result.json"
check_submission "$DMG" "$OUTPUT/dmg-notary-result.json" "$OUTPUT/dmg-notary-log.json"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
codesign --verify --strict "$DMG"
hdiutil verify "$DMG"

mkdir -p "$STAGE/feed"
cp "$DMG" "$STAGE/feed/"
cp "$ROOT/docs/appcast-v3.xml" "$STAGE/feed/appcast-v3.xml"
sed 's/Developer ID-signed but not Apple-notarized/Developer ID-signed and Apple-notarized/g' \
    "$ROOT/docs/release-notes.html" > "$STAGE/feed/VideoVault-v${VERSION}-macOS-notarized.html"
"$SPARKLE/generate_appcast" --account "$ACCOUNT" --versions "$BUILD_VERSION" --maximum-deltas 0 \
    --download-url-prefix "$PREFIX" --link 'https://emacth3creator.github.io/VideoVault/' \
    --embed-release-notes -o "$STAGE/feed/appcast-v3.xml" "$STAGE/feed"
cp "$STAGE/feed/appcast-v3.xml" "$OUTPUT/appcast-v3.xml"
swift "$ROOT/script/verify_release.swift" "$ROOT/VideoVault/Info.plist" "$OUTPUT/appcast-v3.xml" "$DMG"
(cd "$OUTPUT" && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")") > "$OUTPUT/SHA256SUMS-v${VERSION}-notarized.txt"
ditto "$APP" "$OUTPUT/VideoVault.app"
echo "Notarized app, ZIP, DMG, receipts, checksums, and signed feed ready in $OUTPUT"
echo 'Original release downloads were not changed. Review both notarization logs before publishing.'
