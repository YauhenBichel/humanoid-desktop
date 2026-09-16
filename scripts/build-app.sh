#!/usr/bin/env bash
# Build HumanoidDesktop.app from this package, and optionally install it.
#
#   scripts/build-app.sh              # -> build/HumanoidDesktop.app
#   scripts/build-app.sh --install    # and copy it to ~/Applications (quit a running copy first)
#
# The app is signed ad hoc for this Mac: it runs here without a developer account, and macOS asks once
# for the microphone. To give it to someone else, sign and notarise it with a Developer ID instead.
set -euo pipefail
cd "$(dirname "$0")/.."

readonly APP=build/HumanoidDesktop.app
readonly VERSION=${VERSION:-0.1.0}

swift build -c release --product HumanoidDesktop
binary="$(swift build -c release --show-bin-path)/HumanoidDesktop"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$binary" "$APP/Contents/MacOS/HumanoidDesktop"
cat >"$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>io.github.yauhenbichel.humanoid-desktop</string>
  <key>CFBundleName</key><string>Humanoid Desktop</string>
  <key>CFBundleDisplayName</key><string>Humanoid Desktop</string>
  <key>CFBundleExecutable</key><string>HumanoidDesktop</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <!-- A menu bar app: no Dock icon, no app switcher entry. -->
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>While you hold Option-Space, your teammate listens so you can talk instead of typing. The recording goes only to the transcription server in your settings.</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "built $APP"

if [ "${1:-}" = "--install" ]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/HumanoidDesktop.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "installed $HOME/Applications/HumanoidDesktop.app"
fi
