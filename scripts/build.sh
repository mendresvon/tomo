#!/bin/zsh
# Builds Tomo.app with swiftc. Works with only the Command Line Tools (no Xcode needed).
#
#   ./scripts/build.sh            Build build/Tomo.app
#   ./scripts/build.sh --install  Also copy it to ~/Applications
set -euo pipefail

ROOT="${0:A:h:h}"
OBJ="$ROOT/.build/app"
APP="$ROOT/build/Tomo.app"
TARGET="$(uname -m)-apple-macos14.0"

mkdir -p "$OBJ"

echo "Compiling…"
swiftc -swift-version 5 -O -target "$TARGET" -parse-as-library \
  -emit-module -emit-library -static -module-name TomoCore \
  -emit-module-path "$OBJ/TomoCore.swiftmodule" -o "$OBJ/libTomoCore.a" \
  "$ROOT"/Sources/TomoCore/*.swift
swiftc -swift-version 5 -O -target "$TARGET" \
  -I "$OBJ" -L "$OBJ" -lTomoCore -module-name Tomo -o "$OBJ/Tomo" \
  "$ROOT"/Sources/Tomo/*.swift

echo "Drawing the app icon…"
ICONSET="$OBJ/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
"$OBJ/Tomo" --export-icon "$OBJ/icon-1024.png" >/dev/null
for size in 16 32 128 256 512; do
  sips -z $size $size "$OBJ/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$OBJ/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$OBJ/AppIcon.icns"

echo "Making Tomo.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OBJ/Tomo" "$APP/Contents/MacOS/Tomo"
cp "$OBJ/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Tomo</string>
  <key>CFBundleDisplayName</key><string>Tomo</string>
  <key>CFBundleIdentifier</key><string>local.tomo.pomodoro</string>
  <key>CFBundleExecutable</key><string>Tomo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run on this Mac, no developer account needed.
codesign --force --sign - "$APP" >/dev/null 2>&1

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Tomo.app"
  cp -R "$APP" "$HOME/Applications/Tomo.app"
  echo "Installed to ~/Applications/Tomo.app"
fi

echo "Done: $APP"
