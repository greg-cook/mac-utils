#!/bin/sh
# Builds a release binary and wraps it in ExternalDisplayController.app, signed ad hoc for local use.
set -eu
cd "$(dirname "$0")"

swift build -c release
app=build/ExternalDisplayController.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/ExternalDisplayController "$app/Contents/MacOS/"
cp Info.plist "$app/Contents/"
mkdir -p "$app/Contents/Resources"
swift ../scripts/make-icon.swift sun.max F2C14E D9822B build/AppIcon.iconset
iconutil -c icns -o "$app/Contents/Resources/AppIcon.icns" build/AppIcon.iconset
codesign --force --sign - "$app"
echo "Built $app"
