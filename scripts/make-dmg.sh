#!/bin/bash
# Packages build/Kaeru.app into build/Kaeru.dmg with an Applications shortcut for drag-to-install.
# Usage: scripts/make-dmg.sh   (run scripts/build-app.sh --bundle-helpers first)
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Kaeru.app
[ -d "$APP" ] || { echo "Build the app first: scripts/build-app.sh --bundle-helpers"; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"

rm -f build/Kaeru.dmg build/Kaeru-rw.dmg
hdiutil create -volname "Kaeru" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov build/Kaeru-rw.dmg >/dev/null
# Mark the volume as having a custom icon so Finder shows the frog.
MOUNT=$(hdiutil attach build/Kaeru-rw.dmg -nobrowse -noautoopen | awk -F'\t' '/\/Volumes\// {print $NF}')
if command -v SetFile >/dev/null; then SetFile -a C "$MOUNT"; fi
hdiutil detach "$MOUNT" -quiet
hdiutil convert build/Kaeru-rw.dmg -format UDZO -imagekey zlib-level=9 -o build/Kaeru.dmg >/dev/null
rm build/Kaeru-rw.dmg
echo "Built build/Kaeru.dmg (Kaeru $VERSION, $(du -h build/Kaeru.dmg | cut -f1))"
