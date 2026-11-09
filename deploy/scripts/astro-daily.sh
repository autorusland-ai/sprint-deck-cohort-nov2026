#!/usr/bin/env bash
# Публикует только полный успешный расчёт, атомарно в пределах каталога.
set -euo pipefail
export TZ=Europe/Moscow

OUT=/home/clawd/emmbase/life/прогнозы/_астро-данные-сегодня.md
CLI=/home/clawd/.openclaw/scripts/astro-cli.py
mkdir -p "$(dirname "$OUT")"
TMP=$(mktemp "${OUT}.tmp.XXXXXX")
trap 'rm -f -- "$TMP"' EXIT
DAY=$(date +%F)

# Не помещать блок в &&/||/if: это подавляет errexit внутри него.
{
  echo "# Астро-данные на $(date -d "$DAY" +%d.%m.%Y) — локальный расчёт"
  echo
  echo "> Сформировано: $(date --iso-8601=seconds). Часовой пояс: Europe/Moscow."
  echo '> Транзиты и дневные столпы на 08:00 МСК; натальные — на момент рождения.'
  echo '> Swiss Ephemeris/Moshier; транзиты наложены на натальные дома Плацидуса.'
  echo '> Узел mean выбран для аспектов, true справочно; Хирон только при доступных эфемеридах.'
  echo '> Орб аспекта >3° — слабый сигнал; такт удачи справочный, не вычисленный.'
  echo
  echo '```'
  "$CLI" all "$DAY"
  echo '```'
} > "$TMP"
mv -- "$TMP" "$OUT"
