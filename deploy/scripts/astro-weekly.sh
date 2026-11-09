#!/usr/bin/env bash
# Семь дней от ближайшего понедельника; публикация только полного расчёта.
set -euo pipefail
export TZ=Europe/Moscow

OUT=/home/clawd/emmbase/life/прогнозы/_астро-данные-неделя.md
CLI=/home/clawd/.openclaw/scripts/astro-cli.py
LOG=/home/clawd/.openclaw/logs/astro-weekly.log
mkdir -p "$(dirname "$OUT")" "$(dirname "$LOG")"
TMP=$(mktemp "${OUT}.tmp.XXXXXX")
cleanup() {
  rc=$?
  rm -f -- "$TMP"
  if (( rc != 0 )); then
    printf '%s [fail] расчёт недели не опубликован\n' "$(date -u +%FT%TZ)" >> "$LOG"
  fi
  exit "$rc"
}
trap cleanup EXIT

dow=$(date +%u)
if [ "$dow" = 1 ]; then off=0; else off=$((8 - dow)); fi
MON=$(date -d "+${off} day" +%F)
SUN=$(date -d "$MON +6 day" +%F)

# Отдельный блок, без &&/||: ошибка любого CLI прерывает публикацию.
{
  echo "# Астро-данные на неделю $MON – $SUN — локальный расчёт"
  echo
  echo "> Сформировано: $(date --iso-8601=seconds). Часовой пояс: Europe/Moscow."
  echo '> Транзиты и дневные столпы на 08:00 МСК каждого дня; натальные — на момент рождения.'
  echo '> Swiss Ephemeris/Moshier; транзиты наложены на натальные дома Плацидуса.'
  echo '> Узел mean выбран для аспектов, true справочно; Хирон только при доступных эфемеридах.'
  echo '> Орб аспекта >3° — слабый сигнал; такт удачи справочный, не вычисленный.'
  for i in 0 1 2 3 4 5 6; do
    D=$(date -d "$MON +$i day" +%F)
    echo
    echo "## $D"
    echo
    echo '```'
    "$CLI" all "$D"
    echo '```'
  done
} > "$TMP"
mv -- "$TMP" "$OUT"
printf '%s [ok] неделя %s..%s -> %s (%s байт)\n' \
  "$(date -u +%FT%TZ)" "$MON" "$SUN" "$OUT" "$(wc -c < "$OUT")" >> "$LOG"
