#!/bin/bash
# Builds "build/Desk Agents.app" (menu-bar only, no Dock icon).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Desk Agents.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DeskAgents "$APP/Contents/MacOS/DeskAgents"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Desk Agents</string>
  <key>CFBundleDisplayName</key><string>Desk Agents</string>
  <key>CFBundleIdentifier</key><string>local.desk-agents</string>
  <key>CFBundleExecutable</key><string>DeskAgents</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "$APP"
