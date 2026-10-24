#!/bin/bash
# Compila "Riordina Dock" con Xcode e la mette in Applicazioni.
set -e
cd "$(dirname "$0")"

APP="Riordina Dock.app"
BUILD="build/$APP"

echo ""
echo "🔨  Compilo Riordina Dock... / Building Riordina Dock..."
pkill -x RiordinaDock 2>/dev/null || true
rm -rf build
mkdir -p "$BUILD/Contents/MacOS" "$BUILD/Contents/Resources"

xcrun swiftc -O -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macos13.0" \
  sorgenti/main.swift \
  -framework AppKit -framework ServiceManagement \
  -o "$BUILD/Contents/MacOS/RiordinaDock"

cp sorgenti/Info.plist "$BUILD/Contents/Info.plist"
cp sorgenti/AppIcon.icns "$BUILD/Contents/Resources/AppIcon.icns"
xattr -cr "$BUILD"
codesign --force --deep --sign - "$BUILD" >/dev/null 2>&1

echo "📦  La sposto in Applicazioni... / Moving it to Applications..."
rm -rf "/Applications/$APP"
cp -R "$BUILD" "/Applications/"

echo "🚀  La apro! / Launching!"
open "/Applications/$APP"
echo ""
echo -e "✅  Fatto! Cerca l'icona del Dock in alto nella barra dei menu.\n✅  Done! Look for the Dock icon in the menu bar at the top of the screen."
echo ""
