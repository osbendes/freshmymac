#!/bin/zsh
# README ve tanıtım görselleri için ham ekran görüntülerini örnek içerikle (-demo) iki dilde ve iki temada alır.
#   ./scripts/screenshots.sh <çıktı-klasörü>
# build/FreshMyMac.app gerekir (./scripts/build-app.sh). Ayarlarına dokunulmaz: dil ve tema başlatma
# argümanıyla verilir, demo seçimi çıkarken geri alınır. Görseller: swift scripts/make_promo.swift
set -euo pipefail
OUT=${1:?kullanım: screenshots.sh <çıktı-klasörü>}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/build/FreshMyMac.app/Contents/MacOS/FreshMyMac"
[[ -x $BIN ]] || { echo "Önce ./scripts/build-app.sh çalıştırın."; exit 1; }
mkdir -p "$OUT"

for lang in tr en; do
  locale=$([[ $lang = tr ]] && echo tr_TR || echo en_US)
  for theme in dark light; do
    shot() {  # ad, ekran, ek argümanlar…
      local name=$1 screen=$2; shift 2
      "$BIN" -demo YES -screen $screen -appLanguage $lang -appearanceMode $theme \
        -AppleLanguages "($lang)" -AppleLocale $locale \
        -snapshot "$OUT/$name-$lang-$theme.png" "$@" >/dev/null 2>&1
    }
    shot overview overview -snapshotMenu "$OUT/menu-$lang-$theme.png"
    shot cleanup cleanup
    shot cleaned cleanup -demoScene cleaned
    shot largefiles largeFiles
    shot leftovers leftovers
    shot launchitems launchItems
    shot settings settings
  done
done
echo "Ekran görüntüleri: $OUT"
