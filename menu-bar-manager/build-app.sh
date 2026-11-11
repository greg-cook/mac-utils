#!/bin/sh
# Builds a release binary and wraps it in MenuBarManager.app, signed ad hoc for local use.
set -eu
cd "$(dirname "$0")"

swift build -c release
app=build/MenuBarManager.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/MenuBarManager "$app/Contents/MacOS/"
cp Info.plist "$app/Contents/"
mkdir -p "$app/Contents/Resources"
swift ../scripts/make-icon.swift eye.slash 8B6CF6 4C2BB8 build/AppIcon.iconset
iconutil -c icns -o "$app/Contents/Resources/AppIcon.icns" build/AppIcon.iconset
codesign --force --sign - "$app"
echo "Built $app"
