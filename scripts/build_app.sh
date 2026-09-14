#!/bin/zsh
# Builds DictateBar, wraps it into ~/Applications/DictateBar.app, and launches it.
# Usage: scripts/build_app.sh          (build + launch)
#        scripts/build_app.sh --no-run (build only)
set -e -o pipefail
cd "$(dirname "$0")/.."

# ".nosync" keeps the build cache out of iCloud Drive (Documents is synced).
swift build -c release --scratch-path .build.nosync || { echo "Build failed"; exit 1; }
BIN=.build.nosync/release/DictateBar

# Assemble outside iCloud: synced folders carry attributes that codesign rejects.
STAGE=$(mktemp -d)
APP="$STAGE/DictateBar.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DictateBar"
cp -R prompts sync "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DictateBar</string>
    <key>CFBundleDisplayName</key><string>DictateBar</string>
    <key>CFBundleIdentifier</key><string>app.dictatebar.menubar</string>
    <key>CFBundleExecutable</key><string>DictateBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSCalendarsFullAccessUsageDescription</key><string>DictateBar adds your assignments, class sessions and to-dos to a DictateBar calendar.</string>
    <key>NSMicrophoneUsageDescription</key><string>DictateBar records your voice so it can be transcribed on this Mac.</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Sign with your own Apple Development certificate if you have one (keeps macOS
# permissions across rebuilds); otherwise an ad-hoc signature, which is fine locally.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
INSTALLED="$HOME/Applications/DictateBar.app"
mkdir -p "$HOME/Applications"
pkill -x DictateBar 2>/dev/null || true
rm -rf "$INSTALLED"
cp -R "$APP" "$INSTALLED"
rm -rf "$STAGE"
echo "Installed $INSTALLED"

if [ "$1" != "--no-run" ]; then
  sleep 0.5
  open "$INSTALLED"
  echo "Launched. Look for the mic icon in your menu bar."
fi
