#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit source changes before publishing.' >&2; exit 1; }
[[ "$(git branch --show-current)" == main ]] || { echo 'Publish from main.' >&2; exit 1; }
git fetch origin main
git merge --ff-only origin/main
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' VideoVault/Info.plist)
[[ ! -e "Releases/VideoVault-v${VERSION}-macOS.dmg" ]] || { echo 'This version is already released. Increment both app version and build number.' >&2; exit 1; }
OUTPUT=$(mktemp -d /tmp/VideoVault-publish.XXXXXX)
MOUNT="$OUTPUT/mount"
cleanup() { if mount | grep -Fq " on $MOUNT "; then hdiutil detach "$MOUNT"; fi; }
trap cleanup EXIT
bash script/package_release.sh "$OUTPUT"
mkdir -p "$MOUNT"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$OUTPUT/VideoVault-v${VERSION}-macOS.dmg"
codesign --verify --deep --strict "$MOUNT/VideoVault.app"
ditto --norsrc --noextattr "$MOUNT/VideoVault.app" Releases/VideoVault.app
hdiutil detach "$MOUNT"
cp "$OUTPUT/VideoVault-v${VERSION}-macOS.dmg" Releases/
cp "$OUTPUT/SHA256SUMS-v${VERSION}.txt" Releases/
cp "$OUTPUT/appcast-v2.xml" docs/appcast-v2.xml
python3 - "$VERSION" <<'PY'
import re, sys
from pathlib import Path
for filename in ['README.md', 'docs/index.html']:
    p = Path(filename)
    p.write_text(re.sub(r'VideoVault-v[0-9.]+-macOS\.dmg', 'VideoVault-v' + sys.argv[1] + '-macOS.dmg', p.read_text()))
PY
git add Releases/VideoVault.app "Releases/VideoVault-v${VERSION}-macOS.dmg" "Releases/SHA256SUMS-v${VERSION}.txt" docs/appcast-v2.xml README.md docs/index.html
git commit -m "Publish VideoVault v${VERSION} installer and signed update feed"
git push origin main
echo "Published v$VERSION. Verify a Check for Updates from an older v2-channel installation."
