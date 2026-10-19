#!/bin/bash
# Builds a release Kaeru.app into ./build.
# Usage: scripts/build-app.sh [--bundle-helpers] [--install]
#   --bundle-helpers  copy ffmpeg/ffprobe/cwebp and their libraries into the app (for sharing it)
#   --install         copy to /Applications and launch
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64

APP=build/Kaeru.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Kaeru "$APP/Contents/MacOS/Kaeru"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# VERSION=1.2.0 overrides the version in Info.plist (the release workflow passes the git tag).
# The build number is the commit count, so every release build is unique.
if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

# The icon is drawn by Kaeru itself (same artwork as in the app) and packed into .icns by it too.
if [ ! -f Resources/AppIcon.icns ]; then
    TMP=$(mktemp -d)
    .build/release/Kaeru --make-icon "$TMP/AppIcon.png"
    .build/release/Kaeru --run image.icns "$TMP/AppIcon.png" >/dev/null
    mv "$TMP/AppIcon.icns" Resources/AppIcon.icns
    rm -rf "$TMP"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [[ " $* " == *" --bundle-helpers "* ]]; then
    python3 scripts/bundle_helpers.py "$APP"
fi

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ " $* " == *" --install "* ]]; then
    pkill -x Kaeru 2>/dev/null || true
    rm -rf /Applications/Kaeru.app
    cp -R "$APP" /Applications/
    open /Applications/Kaeru.app
    echo "Installed to /Applications/Kaeru.app"
fi
