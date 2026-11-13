#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit source changes before publishing.' >&2; exit 1; }
[[ "$(git branch --show-current)" == main ]] || { echo 'Publish from main.' >&2; exit 1; }
git fetch origin main
git merge --ff-only origin/main
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' VideoVault/Info.plist)
[[ ! -e "Releases/VideoVault-v${VERSION}-macOS.dmg" && ! -e "Releases/VideoVault-v${VERSION}-macOS-notarized.dmg" ]] || { echo 'This version is already released. Increment both app version and build number.' >&2; exit 1; }
PROFILE=${VIDEOVAULT_NOTARY_PROFILE:-}
if [[ -n "$PROFILE" ]]; then
    [[ -n "${VIDEOVAULT_SIGN_IDENTITY:-}" && "$VIDEOVAULT_SIGN_IDENTITY" != '-' ]] || { echo 'Set a Developer ID signing identity for notarization.' >&2; exit 1; }
    xcrun notarytool history --keychain-profile "$PROFILE" --output-format json >/dev/null
fi
OUTPUT=$(mktemp -d /tmp/VideoVault-publish.XXXXXX)
MOUNT="$OUTPUT/mount"
cleanup() { if mount | grep -Fq " on $MOUNT "; then hdiutil detach "$MOUNT"; fi; }
trap cleanup EXIT
bash script/package_release.sh "$OUTPUT"
SUFFIX=''
if [[ -n "$PROFILE" ]]; then
    VIDEOVAULT_NOTARY_ARCHIVE="$OUTPUT/VideoVault-v${VERSION}-macOS.zip" bash script/notarize_release.sh "$OUTPUT/notarized" "$PROFILE"
    OUTPUT="$OUTPUT/notarized"
    SUFFIX='-notarized'
fi
mkdir -p "$MOUNT"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$OUTPUT/VideoVault-v${VERSION}-macOS${SUFFIX}.dmg"
codesign --verify --deep --strict "$MOUNT/VideoVault.app"
ditto --norsrc --noextattr "$MOUNT/VideoVault.app" Releases/VideoVault.app
xattr -cr Releases/VideoVault.app
codesign --verify --deep --strict Releases/VideoVault.app
if [[ "$SUFFIX" == '-notarized' ]]; then xcrun stapler validate Releases/VideoVault.app; fi
hdiutil detach "$MOUNT"
cp "$OUTPUT/VideoVault-v${VERSION}-macOS${SUFFIX}.dmg" Releases/
cp "$OUTPUT/VideoVault-v${VERSION}-macOS${SUFFIX}.zip" Releases/
cp "$OUTPUT/SHA256SUMS-v${VERSION}${SUFFIX}.txt" Releases/
cp "$OUTPUT/appcast-v3.xml" docs/appcast-v3.xml
python3 - "$VERSION" "$SUFFIX" <<'PY'
import re, sys
from pathlib import Path
for filename in ['README.md', 'docs/index.html']:
    p = Path(filename)
    text = p.read_text()
    base = 'https://github.com/eMacTh3Creator/VideoVault/releases/download/v' + sys.argv[1] + '/'
    text = re.sub(r'https://github.com/eMacTh3Creator/VideoVault/releases/download/v[0-9.]+/VideoVault-v[0-9.]+-macOS(?:-notarized)?\.(dmg|zip)', lambda m: base + 'VideoVault-v' + sys.argv[1] + '-macOS' + sys.argv[2] + '.' + m[1], text)
    text = re.sub(r'VideoVault-v[0-9.]+-macOS(?:-notarized)?\.(dmg|zip)', lambda m: 'VideoVault-v' + sys.argv[1] + '-macOS' + sys.argv[2] + '.' + m[1], text)
    text = re.sub(r'https://github.com/eMacTh3Creator/VideoVault/releases/download/v[0-9.]+/SHA256SUMS-v[0-9.]+(?:-notarized)?\.txt', base + 'SHA256SUMS-v' + sys.argv[1] + sys.argv[2] + '.txt', text)
    p.write_text(text)
PY
git add Releases/VideoVault.app "Releases/VideoVault-v${VERSION}-macOS${SUFFIX}.dmg" "Releases/VideoVault-v${VERSION}-macOS${SUFFIX}.zip" "Releases/SHA256SUMS-v${VERSION}${SUFFIX}.txt" docs/appcast-v3.xml README.md docs/index.html
git commit -m "Publish VideoVault v${VERSION} installer and signed update feed"
git push origin main
echo "Published v$VERSION. Versions before 1.5 need one manual install to join the v3 update channel."
