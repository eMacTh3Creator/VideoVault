#!/bin/bash
set -euo pipefail

# Prepare a signed feed for an archive already committed to this repository.
# Publish the resulting appcast.xml to docs/ only after verifying it.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/VideoVault/Info.plist")
BUILD_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/VideoVault/Info.plist")
ARCHIVE_NAME="VideoVault-v${VERSION}-macOS.zip"
PACKAGES=${VIDEOVAULT_PACKAGES:-/tmp/VideoVault-packages}
SPARKLE="$PACKAGES/artifacts/sparkle/Sparkle/bin"
OUTPUT=${1:-"$ROOT/work/signed-update-v${VERSION}"}

# -p reads an existing public key; it never generates a replacement key.
if ! PUBLIC_KEY=$("$SPARKLE/generate_keys" --account videovault -p); then
    echo 'Restore the original videovault Sparkle key to the login Keychain before publishing updates.' >&2
    exit 1
fi
EXPECTED_KEY=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT/VideoVault/Info.plist")
if [[ "$PUBLIC_KEY" != "$EXPECTED_KEY" ]]; then
    echo 'The signing key does not match existing VideoVault installations.' >&2
    exit 1
fi
"$SPARKLE/sign_update" --account videovault --verify "$ROOT/docs/appcast.xml"

COMMIT=$(git -C "$ROOT" rev-parse HEAD)
git -C "$ROOT" cat-file -e "$COMMIT:Releases/$ARCHIVE_NAME"
PREFIX="https://raw.githubusercontent.com/eMacTh3Creator/VideoVault/$COMMIT/Releases/"
mkdir -p "$OUTPUT"
# Download the committed bytes, not a potentially modified local archive.
curl --fail --location --silent --show-error "$PREFIX$ARCHIVE_NAME" -o "$OUTPUT/$ARCHIVE_NAME"
LOCAL_HASH=$(shasum -a 256 "$ROOT/Releases/$ARCHIVE_NAME" | awk '{print $1}')
REMOTE_HASH=$(shasum -a 256 "$OUTPUT/$ARCHIVE_NAME" | awk '{print $1}')
[[ "$LOCAL_HASH" == "$REMOTE_HASH" ]] || { echo 'Published archive differs from the local release.' >&2; exit 1; }
cp "$ROOT/docs/appcast.xml" "$OUTPUT/appcast.xml"
cat > "$OUTPUT/VideoVault-v${VERSION}-macOS.html" <<EOF
<h2>VideoVault ${VERSION}</h2>
<p>First-start setup for Intel and Apple Silicon. Intel Macs use the built-in yt-dlp and ffmpeg installers. Homebrew setup instructions are available on Apple Silicon. Tool installation errors are shown beside their buttons.</p>
EOF
"$SPARKLE/generate_appcast" --account videovault --versions "$BUILD_VERSION" --maximum-deltas 0 \
    --download-url-prefix "$PREFIX" --link 'https://emacth3creator.github.io/VideoVault/' \
    --embed-release-notes "$OUTPUT"
"$SPARKLE/sign_update" --account videovault --verify "$OUTPUT/appcast.xml"
echo "Signed feed ready: $OUTPUT/appcast.xml"
echo 'Commit this verified feed as docs/appcast.xml, then verify the live GitHub Pages feed.'
