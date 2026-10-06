#!/bin/bash
set -euo pipefail
# Isolated end-to-end Sparkle fixture. Never touches /Applications or user app data.
APP=${1:?Pass a signed VideoVault.app path}
TEST_ROOT=${2:-/tmp/VideoVault-update-test}
PORT=${3:-18763}
SPARKLE=${VIDEOVAULT_PACKAGES:-/tmp/VideoVault-packages}/artifacts/sparkle/Sparkle/bin
ACCOUNT=${VIDEOVAULT_SIGNING_ACCOUNT:-videovault-v2}
[[ ! -e "$TEST_ROOT" ]] || { echo 'Use a new test directory.' >&2; exit 1; }
mkdir -p "$TEST_ROOT/installed" "$TEST_ROOT/server"
for LOCATION in installed server; do
    COPY="$TEST_ROOT/$LOCATION/VideoVault.app"
    ditto --norsrc --noextattr "$APP" "$COPY"
    chmod -R u+w "$COPY"
    plutil -replace CFBundleIdentifier -string com.videovault.updatetest.v2 "$COPY/Contents/Info.plist"
    plutil -replace SUFeedURL -string "http://127.0.0.1:$PORT/appcast-v2.xml" "$COPY/Contents/Info.plist"
    if [[ "$LOCATION" == installed ]]; then
        plutil -replace CFBundleVersion -string 7 "$COPY/Contents/Info.plist"
        plutil -replace CFBundleShortVersionString -string 1.3.99 "$COPY/Contents/Info.plist"
    fi
    xattr -cr "$COPY"
    codesign --force --sign - "$COPY"
    codesign --verify --deep --strict "$COPY"
done
ditto -c -k --norsrc --noextattr --keepParent "$TEST_ROOT/server/VideoVault.app" "$TEST_ROOT/server/VideoVault-update.zip"
"$SPARKLE/generate_appcast" --account "$ACCOUNT" --maximum-deltas 0 \
    --download-url-prefix "http://127.0.0.1:$PORT/" -o "$TEST_ROOT/server/appcast-v2.xml" "$TEST_ROOT/server"
"$SPARKLE/sign_update" --account "$ACCOUNT" --verify "$TEST_ROOT/server/appcast-v2.xml"
echo "Serve $TEST_ROOT/server on 127.0.0.1:$PORT and use Sparkle's test CLI or the isolated installed copy."
echo 'Confirm its build number increases to the release build and its signature remains valid.'
