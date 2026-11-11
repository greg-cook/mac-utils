#!/bin/sh
# Builds a release binary and wraps it in MenuBarStats.app, signed ad hoc for local use.
set -eu
cd "$(dirname "$0")"

swift build -c release
app=build/MenuBarStats.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/MenuBarStats "$app/Contents/MacOS/"
cp Info.plist "$app/Contents/"
mkdir -p "$app/Contents/Resources"
swift ../scripts/make-icon.swift gauge.with.dots.needle.67percent 34D3A0 0E8C74 build/AppIcon.iconset
iconutil -c icns -o "$app/Contents/Resources/AppIcon.icns" build/AppIcon.iconset
codesign --force --sign - "$app"
echo "Built $app"
