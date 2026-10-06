#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MODULE_CACHE="$DIR/.module-cache"
TEST_BIN="$DIR/.test_runner"

echo "🧪 Compiling and executing BLTS Tracker test suite..."
mkdir -p "$MODULE_CACHE"

swiftc -parse-as-library \
  -module-cache-path "$MODULE_CACHE" \
  -O \
  -framework Foundation \
  -framework Cocoa \
  -framework IOBluetooth \
  -framework IOKit \
  -framework CoreAudio \
  -framework AudioToolbox \
  -framework UserNotifications \
  "$DIR/Sources/blts_tracker/Models/BluetoothDeviceModel.swift" \
  "$DIR/Sources/blts_tracker/Services/BluetoothTracker.swift" \
  "$DIR/Tests/blts_trackerTests/BluetoothDeviceModelTests.swift" \
  "$DIR/Tests/blts_trackerTests/BluetoothTrackerTests.swift" \
  "$DIR/Tests/blts_trackerTests/main.swift" \
  -o "$TEST_BIN"

"$TEST_BIN"
rm -f "$TEST_BIN"
