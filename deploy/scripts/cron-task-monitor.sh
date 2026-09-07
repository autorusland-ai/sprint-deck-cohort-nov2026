#!/usr/bin/env bash
# cron-task-monitor.sh — замечает задачи планировщика openclaw, застрявшие в ошибке.
#
# Зачем: 07.09.2026 аудит нашёл "Недельный прогноз" в статусе error семь недель
# подряд — никто не заметил. У openclaw есть своё уведомление о сбое, но у всех
# упавших задач lastFailureNotificationDeliveryStatus=not-delivered: когда модели
# лежат, доставить сообщение тем же каналом не получается.
#
# Логика: раз в час читаем cron list --json. Задача попадает в отчёт, если
# status=error. Уведомляем только при ИЗМЕНЕНИИ (новая упавшая задача или выросло
# число подряд идущих ошибок) — иначе молчим, чтобы не спамить.
# Отправка идёт прямым вызовом Bot API с хоста, как в telegram-watchdog.sh.
set -u
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

OC=/home/clawd/.npm-global/bin/openclaw
LOG=/home/clawd/.openclaw/logs/cron-task-monitor.log
STATE=/home/clawd/.openclaw/state/cron-task-monitor.state
TOKEN_FILE=${TG_TOKEN_FILE:-/home/clawd/.openclaw/secrets/telegram.token}
CHAT_ID=${TG_CHAT_ID:-215087477}

mkdir -p "$(dirname "$LOG")" "$(dirname "$STATE")"
ts() { date -u "+%Y-%m-%dT%H:%M:%SZ"; }
log() { echo "$(ts) $*" >> "$LOG"; }

notify() {
  local text="$1"
  if [ "${TG_TOKEN:-}" = "TEST_INVALID_NO_SEND" ]; then
    log "[dry-run] отправил бы: $text"; return 0
  fi
  curl -s --max-time 20 -X POST \
    "https://api.telegram.org/bot$(cat "$TOKEN_FILE")/sendMessage" \
    -d "chat_id=$CHAT_ID" --data-urlencode "text=$text" > /dev/null 2>&1 \
    || log "уведомление НЕ доставлено: $text"
}

JSON=$(timeout 120 "$OC" cron list --json 2>/dev/null)
if [ -z "$JSON" ]; then
  log "[skip] планировщик не ответил — пропуск"; exit 0
fi

CUR=$(printf "%s" "$JSON" | python3 -c "
import sys, json
try: jobs = json.load(sys.stdin).get(\"jobs\", [])
except Exception: sys.exit(0)
for j in jobs:
    if j.get(\"status\") != \"error\": continue
    st = j.get(\"state\") or {}
    name = (j.get(\"displayName\") or j.get(\"name\") or j.get(\"id\"))
    print(f\"{j.get(\"id\")}\t{st.get(\"consecutiveErrors\", 1)}\t{name}\")
" 2>/dev/null)

if [ -z "$CUR" ]; then
  [ -s "$STATE" ] && { log "[ok] все задачи вышли из ошибки"; notify "✅ Задачи планировщика: все восстановились."; }
  : > "$STATE"
  exit 0
fi

CHANGED=""
while IFS=$'\t' read -r id errs name; do
  [ -z "$id" ] && continue
  prev=$(grep -F "$id" "$STATE" 2>/dev/null | cut -f2)
  if [ "$prev" != "$errs" ]; then
    CHANGED="${CHANGED}• ${name} — подряд ошибок: ${errs}"$'\n'
  fi
done <<< "$CUR"

printf "%s" "$CUR" | cut -f1,2 > "$STATE"

if [ -n "$CHANGED" ]; then
  log "изменения: $(echo "$CHANGED" | tr "\n" " ")"
  notify "⚠️ Задачи планировщика в ошибке:
${CHANGED}
Проверить: openclaw cron list"
else
  log "[тихо] состав упавших задач не изменился"
fi
