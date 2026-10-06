#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_NAME="BLTS Tracker"
APP_DIR="$DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE="$DIR/.module-cache"

echo "🔨 Building $APP_NAME..."
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE"

swiftc -parse-as-library \
  -module-cache-path "$MODULE_CACHE" \
  -O \
  -framework SwiftUI \
  -framework Cocoa \
  -framework IOBluetooth \
  -framework IOKit \
  -framework CoreAudio \
  -framework AudioToolbox \
  -framework UserNotifications \
  "$DIR/Sources/blts_tracker/Models/BluetoothDeviceModel.swift" \
  "$DIR/Sources/blts_tracker/Services/BluetoothTracker.swift" \
  "$DIR/Sources/blts_tracker/Services/UpdaterService.swift" \
  "$DIR/Sources/blts_tracker/BLTSTrackerApp.swift" \
  -o "$MACOS_DIR/blts_tracker"

cp "$DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
if [ -f "$DIR/AppIcon.icns" ]; then
  cp "$DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

chmod +x "$MACOS_DIR/blts_tracker"

echo "✅ Successfully built: $APP_DIR"
