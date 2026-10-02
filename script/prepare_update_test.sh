#!/bin/bash
set -euo pipefail

# Build two isolated copies to exercise Sparkle installation without touching Applications.
APP=${1:-/tmp/VideoVault-release/Build/Products/Release/VideoVault.app}
TEST_ROOT=${2:-/tmp/VideoVault-update-test}
PORT=${3:-18763}
SPARKLE=${VIDEOVAULT_PACKAGES:-/tmp/VideoVault-packages}/artifacts/sparkle/Sparkle/bin
mkdir -p "$TEST_ROOT/installed" "$TEST_ROOT/server"
for LOCATION in installed server; do
    COPY="$TEST_ROOT/$LOCATION/VideoVault.app"
    ditto "$APP" "$COPY"
    plutil -replace CFBundleIdentifier -string com.videovault.updatetest "$COPY/Contents/Info.plist"
    plutil -replace SUFeedURL -string "http://127.0.0.1:$PORT/appcast.xml" "$COPY/Contents/Info.plist"
    if [[ "$LOCATION" == installed ]]; then
        plutil -replace CFBundleVersion -string 2 "$COPY/Contents/Info.plist"
        plutil -replace CFBundleShortVersionString -string 1.2 "$COPY/Contents/Info.plist"
    fi
    codesign --force --sign - "$COPY"
done
ditto -c -k --sequesterRsrc --keepParent "$TEST_ROOT/server/VideoVault.app" "$TEST_ROOT/server/VideoVault-update.zip"
"$SPARKLE/generate_appcast" --account videovault --maximum-deltas 0 \
    --download-url-prefix "http://127.0.0.1:$PORT/" "$TEST_ROOT/server"
"$SPARKLE/sign_update" --account videovault --verify "$TEST_ROOT/server/appcast.xml"
echo "Serve $TEST_ROOT/server on 127.0.0.1:$PORT, then launch the installed copy and choose Check for Updates."
BUILD_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
echo "After Install and Relaunch, confirm the installed copy has CFBundleVersion $BUILD_VERSION."
