#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_NAME="BLTS Tracker"
APP_BUNDLE="$DIR/$APP_NAME.app"
DMG_NAME="BLTS-Tracker.dmg"
OUTPUT_DMG="$DIR/$DMG_NAME"
VOL_NAME="$APP_NAME"
MOUNT_DIR="/Volumes/$VOL_NAME"
DMG_TMP="$DIR/.build/temp_rw.dmg"

echo "🚀 [1/5] Сборка актуальной версии приложения..."
"$DIR/build_app.sh"

echo "🧹 [2/5] Подготовка и очистка атрибутов бандла..."
# Убеждаемся, что приложение не скрыто и не содержит чужих атрибутов
xattr -cr "$APP_BUNDLE"
chflags -R nohidden "$APP_BUNDLE"
if command -v SetFile >/dev/null 2>&1; then
    SetFile -a B "$APP_BUNDLE" 2>/dev/null || true
    SetFile -a v "$APP_BUNDLE" 2>/dev/null || true
fi

# Отмонтируем том, если он уже был примонтирован
hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
rm -f "$DMG_TMP" "$OUTPUT_DMG"
mkdir -p "$DIR/.build"

echo "💿 [3/5] Создание временного HFS+ диска..."
hdiutil create -size 40m -fs HFS+ -volname "$VOL_NAME" -type UDIF "$DMG_TMP"
hdiutil attach "$DMG_TMP" -mountpoint "$MOUNT_DIR" -nobrowse

echo "📋 [4/5] Копирование приложения и настройка Finder..."
cp -R "$APP_BUNDLE" "$MOUNT_DIR/"
ln -s /Applications "$MOUNT_DIR/Applications"

# Сброс скрытых флагов внутри тома
xattr -cr "$MOUNT_DIR/$APP_NAME.app"
chflags -R nohidden "$MOUNT_DIR"
if command -v SetFile >/dev/null 2>&1; then
    SetFile -a B "$MOUNT_DIR/$APP_NAME.app" 2>/dev/null || true
    SetFile -a v "$MOUNT_DIR/$APP_NAME.app" 2>/dev/null || true
fi

# Установка иконки тома
if [ -f "$DIR/AppIcon.icns" ]; then
    cp "$DIR/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
    if command -v SetFile >/dev/null 2>&1; then
        SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
        SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
    fi
fi

# Настройка внешнего вида окна в Finder (AppleScript)
osascript << APPLESCRIPT
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {300, 200, 840, 500}
        set viewOptions to the icon view options of container window
        set icon size of viewOptions to 100
        set arrangement of viewOptions to not arranged
        set position of item "$APP_NAME.app" of container window to {130, 140}
        set position of item "Applications" of container window to {410, 140}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT

# Очистка кэшей Finder и корректное размонтирование
sync
hdiutil detach "$MOUNT_DIR"

echo "🗜️ [5/5] Финализация и сжатие в $DMG_NAME..."
hdiutil convert "$DMG_TMP" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT_DMG"
rm -f "$DMG_TMP"

# Проверка готового образа
hdiutil attach "$OUTPUT_DMG" -mountpoint "$MOUNT_DIR" -nobrowse
ITEMS=$(osascript -e "tell application \"Finder\" to get name of every item of disk \"$VOL_NAME\"")
hdiutil detach "$MOUNT_DIR"

if [ -f "$OUTPUT_DMG" ]; then
    DMG_SIZE=$(du -h "$OUTPUT_DMG" | cut -f1)
    echo ""
    echo "=================================================="
    echo "🎉 Успешно создан DMG файл!"
    echo "📁 Файл: $OUTPUT_DMG"
    echo "📊 Размер: $DMG_SIZE"
    echo "🔍 Элементы в Finder: $ITEMS"
    echo "=================================================="
else
    echo "❌ Ошибка при создании DMG"
    exit 1
fi
