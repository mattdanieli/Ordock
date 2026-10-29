#!/bin/bash
# Compila "Ordock" dal codice e la mette in Applicazioni.
# Builds "Ordock" with Xcode and copies it to Applications.
set -e
cd "$(dirname "$0")"

APP="Ordock.app"
BUILD="build/$APP"
DOMAIN="com.mattdanieli.ordock"

# Lingua dell'app (si può cambiare anche dopo, dal menu o dalle Impostazioni)
echo ""
echo "🌍  Lingua dell'app / App language"
echo "    1) Italiano"
echo "    2) English"
echo "    3) Automatica, come il Mac / Automatic, same as the Mac"
read -r -p "    → 1 / 2 / 3: " CHOICE
case "$CHOICE" in
  1) LANG_CODE="it" ;;
  2) LANG_CODE="en" ;;
  *) LANG_CODE="auto" ;;
esac
if [ "$LANG_CODE" = "auto" ]; then
  case "$(defaults read -g AppleLanguages 2>/dev/null | tr -d ' \n' | cut -c3-4)" in
    it) IT=1 ;; *) IT=0 ;;
  esac
else
  [ "$LANG_CODE" = "it" ] && IT=1 || IT=0
fi
say_msg() { if [ "$IT" = 1 ]; then echo -e "$1"; else echo -e "$2"; fi; }

echo ""
say_msg "🔨  Compilo Ordock... (ci vuole qualche secondo)" "🔨  Building Ordock... (this takes a few seconds)"
pkill -x Ordock 2>/dev/null || true
rm -rf build
mkdir -p "$BUILD/Contents/MacOS" "$BUILD/Contents/Resources"

xcrun swiftc -O -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macos13.0" \
  Sources/main.swift \
  -framework AppKit -framework SwiftUI -framework Carbon -framework CoreServices -framework ServiceManagement \
  -o "$BUILD/Contents/MacOS/Ordock"

cp Sources/Info.plist "$BUILD/Contents/Info.plist"
cp Sources/AppIcon.icns "$BUILD/Contents/Resources/AppIcon.icns"
xattr -cr "$BUILD"
codesign --force --deep --sign - "$BUILD" >/dev/null 2>&1

# Tolgo la vecchia versione col nome "Riordina Dock" (le sue copie di sicurezza passano a Ordock)
if [ -d "/Applications/Riordina Dock.app" ]; then
  say_msg "🧹  Tolgo la vecchia Riordina Dock..." "🧹  Removing the old Riordina Dock..."
  pkill -x RiordinaDock 2>/dev/null || true
  rm -rf "/Applications/Riordina Dock.app"
fi

say_msg "📦  La sposto in Applicazioni..." "📦  Moving it to Applications..."
rm -rf "/Applications/$APP"
cp -R "$BUILD" "/Applications/"
defaults write "$DOMAIN" lingua -string "$LANG_CODE"

say_msg "🚀  La apro!" "🚀  Launching!"
open "/Applications/$APP"
echo ""
say_msg "✅  Fatto! Cerca l'icona del Dock in alto nella barra dei menu." "✅  Done! Look for the Dock icon in the menu bar at the top of the screen."
echo ""
echo "    Made With Love ❤️ by MattDanieli  ·  paypal.me/mattdanieli"
echo ""
