#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_NAME="BLTS Tracker"
APP_BUNDLE="$DIR/$APP_NAME.app"
DMG_NAME="BLTS-Tracker.dmg"
OUTPUT_DMG="$DIR/$DMG_NAME"
STAGING_DIR="$DIR/.build/dmg_staging"

echo "🚀 [1/4] Компиляция актуальной версии приложения..."
"$DIR/build_app.sh"

echo "📦 [2/4] Подготовка структуры DMG диска..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Копируем .app в папку сборки
cp -R "$APP_BUNDLE" "$STAGING_DIR/"

# Создаем символическую ссылку на /Applications для Drag-and-Drop
ln -s /Applications "$STAGING_DIR/Applications"

# Устанавливаем иконку тома, если доступна
if [ -f "$DIR/AppIcon.icns" ]; then
    cp "$DIR/AppIcon.icns" "$STAGING_DIR/.VolumeIcon.icns"
    if command -v SetFile >/dev/null 2>&1; then
        SetFile -c icnC "$STAGING_DIR/.VolumeIcon.icns" 2>/dev/null || true
        SetFile -a C "$STAGING_DIR" 2>/dev/null || true
    fi
fi

echo "💿 [3/4] Создание сжатого DMG образа ($DMG_NAME)..."
rm -f "$OUTPUT_DMG"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$OUTPUT_DMG"

echo "🧹 [4/4] Очистка временных файлов..."
rm -rf "$STAGING_DIR"

if [ -f "$OUTPUT_DMG" ]; then
    DMG_SIZE=$(du -h "$OUTPUT_DMG" | cut -f1)
    echo ""
    echo "=================================================="
    echo "🎉 Успешно создан DMG файл для установки!"
    echo "📁 Путь: $OUTPUT_DMG"
    echo "📊 Размер: $DMG_SIZE"
    echo "=================================================="
else
    echo "❌ Ошибка: не удалось создать $OUTPUT_DMG"
    exit 1
fi
