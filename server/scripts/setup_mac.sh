#!/bin/bash
# Разовая подготовка Mac для Clipora. Запуск: bash scripts/setup_mac.sh
set -e

echo "1/4 Ставлю FFmpeg, whisper.cpp и chromaprint..."
# ffmpeg-full: в обычном ffmpeg нет libass, без неё не рисуются субтитры
brew install ffmpeg-full whisper-cpp chromaprint

echo "2/4 Скачиваю модель распознавания речи (~550 МБ)..."
mkdir -p "$HOME/clipora-models"
MODEL="$HOME/clipora-models/ggml-large-v3-turbo-q5_0.bin"
if [ ! -f "$MODEL" ]; then
  curl -L -o "$MODEL" https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin
fi

echo "3/4 Создаю базу данных clipora..."
createdb clipora 2>/dev/null || echo "База clipora уже есть"

echo "4/4 Готовлю .env..."
if [ ! -f .env ]; then
  cp .env.example .env
  sed -i '' "s|^DB_USER=.*|DB_USER=$USER|" .env
  sed -i '' "s|^WHISPER_MODEL=.*|WHISPER_MODEL=$MODEL|" .env
fi

echo ""
echo "Готово. Открой server/.env и вставь GEMINI_API_KEY."

# Шрифты для заголовков и субтитров (уже скачанные пропускаются).
bash "$(dirname "$0")/get_fonts.sh"
