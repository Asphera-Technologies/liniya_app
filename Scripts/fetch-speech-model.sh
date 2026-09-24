#!/usr/bin/env bash
# Кладёт модель распознавания речи GigaAM-v3 внутрь приложения.
#
# Модель (≈ 233 МБ) не хранится в git: GitHub не принимает файлы больше
# 100 МБ, а LFS съел бы месячный лимит трафика за пару сборок CI. Поэтому её
# кладёт сама сборка — фаза «Speech model» цели Linea в Xcode. Файлы
# скачиваются один раз на машину в кэш, сверяются по SHA-256 и копируются в
# `Linea.app/GigaAM/`. Пользователь ничего не качает: модель приходит вместе
# с приложением.
#
# Кэш живёт вне папки сборки, чтобы чистая сборка не качала модель заново.
# Поэтому у цели Linea выключена песочница скриптов сборки
# (ENABLE_USER_SCRIPT_SANDBOXING = NO): в песочнице фаза может писать только
# в объявленные выходные файлы.
#
# Версия закреплена коммитом Hugging Face; сменить модель — сменить REV,
# размеры и отпечатки ниже. Официальная конвертация автора sherpa-onnx из
# весов Сбера (MIT), подробности — Docs/check-in.md.
#
#   Scripts/fetch-speech-model.sh           из фазы сборки Xcode: кладёт в .app
#   Scripts/fetch-speech-model.sh <папка>   положить модель в указанную папку
#
# LINEA_MODEL_CACHE — другая папка кэша (по умолчанию ~/Library/Caches/Linea).
set -euo pipefail

REV="a6039be7cee829a9044a69ac0ebaf1c191217c97"
BASE="https://huggingface.co/csukuangfj/sherpa-onnx-nemo-transducer-punct-giga-am-v3-russian-2025-12-16/resolve/$REV"
VAD="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx"

# имя | адрес | байты | SHA-256
FILES=(
  "tokens.txt|$BASE/tokens.txt|13354|39abae20e692998290c574e606f11a9edef2902a1995463fcff63d1490cf22b7"
  "decoder.onnx|$BASE/decoder.onnx|4600132|38fc7475443ea2a26f63211ca350f73ac50fff824ab7a3876ee2bd610c53bbc4"
  "joiner.onnx|$BASE/joiner.onnx|2712896|602ff7017a93311aad34df1437c8d7f49911353c13d6eae7a6ee7b041339465c"
  "silero_vad.onnx|$VAD|643854|9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6"
  "encoder.int8.onnx|$BASE/encoder.int8.onnx|224570820|369f35a71bf288d3b8e0391fabd8dba5f2314088d440bca474056b7b4b6e66bf"
)

if [ $# -ge 1 ]; then
  DEST="$1"
elif [ -n "${TARGET_BUILD_DIR:-}" ] && [ -n "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]; then
  DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/GigaAM"
else
  echo "usage: $0 <destination folder>" >&2
  exit 64
fi

if [ -d "$HOME/Library/Caches" ]; then
  CACHE_ROOT="$HOME/Library/Caches/Linea"
else
  CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/linea"
fi
CACHE="${LINEA_MODEL_CACHE:-$CACHE_ROOT}/gigaam-v3-punct-${REV:0:12}"

sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else sha256sum "$1" | cut -d' ' -f1; fi
}
size() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1"; }

mkdir -p "$CACHE" "$DEST"
for entry in "${FILES[@]}"; do
  IFS='|' read -r name url bytes sha <<< "$entry"
  cached="$CACHE/$name"
  # В кэш файл попадает только после сверки отпечатка, поэтому целый по
  # размеру файл повторно не проверяется.
  if [ ! -f "$cached" ] || [ "$(size "$cached")" != "$bytes" ]; then
    echo "Скачиваю $name ($bytes байт)…"
    if ! curl --fail --location --retry 3 --silent --show-error -o "$cached.part" "$url"; then
      rm -f "$cached.part"
      echo "error: модель распознавания не скачалась ($name). Нужен интернет при первой сборке." >&2
      exit 1
    fi
    actual="$(sha256 "$cached.part")"
    if [ "$actual" != "$sha" ]; then
      rm -f "$cached.part"
      echo "error: $name скачался с другим отпечатком ($actual) — модель не встроена." >&2
      exit 1
    fi
    mv "$cached.part" "$cached"
  fi
  # На APFS копия мгновенная и не занимает места (clonefile), иначе обычная.
  cp -c "$cached" "$DEST/$name" 2>/dev/null || cp "$cached" "$DEST/$name"
done
echo "Модель GigaAM-v3 → $DEST"
