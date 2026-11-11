#!/usr/bin/env bash
# Ставит Godot 4.7 (и при --templates шаблоны экспорта) на раннер GitHub Actions. Печатает путь к бинарю в $GITHUB_ENV как GODOT.
set -euo pipefail
VER=4.7
TAG="$VER-stable"
BASE="https://github.com/godotengine/godot/releases/download/$TAG"
DIR="$RUNNER_TEMP/godot"
mkdir -p "$DIR"
unz() { if command -v unzip >/dev/null; then unzip -q -o "$1" -d "$2"; else 7z x -y -o"$2" "$1" >/dev/null; fi; }
case "$(uname -s)" in
  Linux*)
    curl -fsSL -o "$DIR/g.zip" "$BASE/Godot_v${TAG}_linux.x86_64.zip"
    unz "$DIR/g.zip" "$DIR"
    BIN="$DIR/Godot_v${TAG}_linux.x86_64"
    TPL_DIR="$HOME/.local/share/godot/export_templates/$VER.stable"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    curl -fsSL -o "$DIR/g.zip" "$BASE/Godot_v${TAG}_win64.exe.zip"
    unz "$DIR/g.zip" "$DIR"
    BIN="$DIR/Godot_v${TAG}_win64_console.exe"
    [ -f "$BIN" ] || BIN="$DIR/Godot_v${TAG}_win64.exe"
    TPL_DIR="$APPDATA/Godot/export_templates/$VER.stable"
    ;;
  *) echo "неизвестная ОС"; exit 1 ;;
esac
chmod +x "$BIN" || true
if [ "${1:-}" = "--templates" ]; then
  curl -fsSL -o "$DIR/t.tpz" "$BASE/Godot_v${TAG}_export_templates.tpz"
  unz "$DIR/t.tpz" "$DIR/t"
  mkdir -p "$TPL_DIR"
  cp -r "$DIR/t/templates/." "$TPL_DIR/"
fi
"$BIN" --version
echo "GODOT=$BIN" >> "$GITHUB_ENV"
