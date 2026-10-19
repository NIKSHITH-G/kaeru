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
# A short note beside the app, for people who don't read the website first.
cat > "$STAGE/How to open Kaeru.txt" <<'NOTE'
HOW TO INSTALL AND OPEN KAERU
============================

1. Drag the Kaeru icon onto the Applications folder in this window.

2. Open your Applications folder (in Finder press Shift-Command-A) and double-click Kaeru.
   macOS says "Kaeru" Not Opened. Click DONE (not Move to Trash).
   This happens because Kaeru isn't signed with a paid Apple certificate yet.

3. Click the Apple menu (top-left)  >  System Settings...  >  Privacy & Security.
   Scroll down to the "Security" section.

4. Next to '"Kaeru" was blocked to protect your Mac.' click OPEN ANYWAY.

5. Click OPEN ANYWAY again and enter your password (or use Touch ID).
   Kaeru opens and a frog appears in your menu bar. You only do this once.

6. For "Return in Finder": in the tutorial click "Allow Keyboard Access...", then
   in System Settings > Privacy & Security > Accessibility, switch Kaeru ON.

macOS 13 or 14: you can instead right-click Kaeru > Open > Open.

"Kaeru is damaged and can't be opened"? Open Terminal (Applications > Utilities),
paste this line and press Return:

    xattr -dr com.apple.quarantine /Applications/Kaeru.app

Guide with pictures: https://getkaeru.vercel.app/install
NOTE

rm -f build/Kaeru.dmg build/Kaeru-rw.dmg
hdiutil create -volname "Kaeru" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov build/Kaeru-rw.dmg >/dev/null
# Mark the volume as having a custom icon so Finder shows the frog.
MOUNT=$(hdiutil attach build/Kaeru-rw.dmg -nobrowse -noautoopen | awk -F'\t' '/\/Volumes\// {print $NF}')
if command -v SetFile >/dev/null; then SetFile -a C "$MOUNT"; fi
hdiutil detach "$MOUNT" -quiet
hdiutil convert build/Kaeru-rw.dmg -format UDZO -imagekey zlib-level=9 -o build/Kaeru.dmg >/dev/null
rm build/Kaeru-rw.dmg
echo "Built build/Kaeru.dmg (Kaeru $VERSION, $(du -h build/Kaeru.dmg | cut -f1))"
