#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_NAME="BLTS Tracker.app"
SOURCE_APP="$DIR/$APP_NAME"

echo "🛑 Завершение всех запущенных копий..."
killall -9 blts_tracker 2>/dev/null || true
pkill -9 -f "BLTS Tracker" 2>/dev/null || true
pkill -9 -f "blts_tracker" 2>/dev/null || true
sleep 1

echo "🔨 Сборка приложения..."
"$DIR/build_app.sh"

USER_APPS="$HOME/Applications"
mkdir -p "$USER_APPS" 2>/dev/null || true
rm -rf "$USER_APPS/$APP_NAME" 2>/dev/null || true
cp -R "$SOURCE_APP" "$USER_APPS/" 2>/dev/null || true
TARGET_APP="$USER_APPS/$APP_NAME"

if [ ! -d "$TARGET_APP" ]; then
    TARGET_APP="$SOURCE_APP"
fi

echo "⚙️ Настройка автозапуска при входе..."
osascript -e "tell application \"System Events\" to delete (login items whose name is \"BLTS Tracker\")" 2>/dev/null || true
osascript -e "tell application \"System Events\" to make login item at end with properties {name:\"BLTS Tracker\", path:\"$TARGET_APP\", hidden:true}" 2>/dev/null || true

echo "🚀 Запуск $TARGET_APP..."
open "$TARGET_APP"

echo "✅ Готово! BLTS Tracker обновлен и запущен."
