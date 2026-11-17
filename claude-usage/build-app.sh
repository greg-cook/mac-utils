#!/bin/sh
# Builds a release binary and wraps it in ClaudeUsage.app, signed ad hoc for local use.
set -eu
cd "$(dirname "$0")"

swift build -c release
app=build/ClaudeUsage.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/ClaudeUsage "$app/Contents/MacOS/"
cp Info.plist "$app/Contents/"
mkdir -p "$app/Contents/Resources"
swift ../scripts/make-icon.swift gauge.with.dots.needle.50percent E8956F B5522E build/AppIcon.iconset
iconutil -c icns -o "$app/Contents/Resources/AppIcon.icns" build/AppIcon.iconset
codesign --force --sign - "$app"
echo "Built $app"
