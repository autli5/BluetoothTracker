#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_NAME="BLTS Tracker.app"
SOURCE_APP="$DIR/$APP_NAME"

echo "🔄 Проверка обновлений на GitHub (https://github.com/autli5/BluetoothTracker.git)..."
cd "$DIR"

# Получаем свежий код с GitHub
git fetch origin main
git pull --rebase origin main

echo "🔨 Пересборка приложения..."
"$DIR/build_app.sh"

USER_APPS="$HOME/Applications"
mkdir -p "$USER_APPS" 2>/dev/null || true
rm -rf "$USER_APPS/$APP_NAME" 2>/dev/null || true
cp -R "$SOURCE_APP" "$USER_APPS/" 2>/dev/null || true
TARGET_APP="$USER_APPS/$APP_NAME"

if [ -w "/Applications" ]; then
    rm -rf "/Applications/$APP_NAME" 2>/dev/null || true
    cp -R "$SOURCE_APP" "/Applications/" 2>/dev/null || true
fi

echo "🛑 Перезапуск приложения..."
killall blts_tracker 2>/dev/null || true
sleep 1
open "$TARGET_APP"

echo "✅ Успешно обновлено до последней версии с GitHub!"
