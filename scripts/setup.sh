#!/bin/zsh
# Command-line alternative to the in-app Setup window: Python packages for the
# Canvas sync and the whisper speech model.
set -e
cd "$(dirname "$0")/.."

DATA="$HOME/Documents/DictateBar"
mkdir -p "$DATA"
echo "→ Python environment for Canvas sync"
# Kept outside Documents so iCloud can't evict the packages mid-sync.
VENV="$HOME/Library/Application Support/DictateBar/venv"
mkdir -p "$(dirname "$VENV")"
[ -d "$VENV" ] || python3 -m venv "$VENV"
"$VENV/bin/pip" install -q --upgrade pip requests pypdf

MODEL=${1:-base.en}
# Kept outside Documents so iCloud can't evict it.
MODELS="$HOME/Library/Application Support/DictateBar/models"
mkdir -p "$MODELS"
FILE="$MODELS/ggml-$MODEL.bin"
if [ -f "$FILE" ]; then
  echo "→ Whisper model already present: $FILE"
else
  echo "→ Downloading whisper model '$MODEL' (~150MB for base.en, ~500MB for small.en)"
  curl -L --progress-bar -o "$FILE" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$MODEL.bin"
fi

[ -f "$DATA/.env" ] || { cp .env.example "$DATA/.env"; echo "→ Created $DATA/.env — open it and paste your Canvas token, or use Setup… in the app."; }
echo "Done."
