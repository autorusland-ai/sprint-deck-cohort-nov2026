#!/usr/bin/env bash
# telegram-watchdog.sh — сторож Telegram-канала openclaw-gateway.
#
# Проблема: после обрыва Tor-циркуита долгоживущий процесс gateway остаётся
# с мёртвым пулом соединений к api.telegram.org и не восстанавливается сам
# (встроенный health-monitor рестартует провайдер внутри того же процесса).
# Инциденты: 27.06 (RKN-блокировка), 02-03.07 (стухший пул, бот молчал сутки).
#
# Логика: cron каждые 5 минут.
#   1. gateway не active → рестарт.
#   2. ≥3 таймаутов getMe за 15 мин И ни одной успешной telegram-операции → рестарт.
#   3. Рестарт не чаще раза в 30 минут (state-файл).
#   4. Проактивность: после рестарта проверяет канал прямым getMe и шлёт Руслану
#      в Telegram отчёт (что сломалось, что сделано, восстановлен ли канал).
#      Если 3 рестарта подряд не помогли — алерт «нужно вмешательство».
set -u
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

LOG=/home/clawd/.openclaw/logs/telegram-watchdog.log
STATE_DIR=/home/clawd/.openclaw/state
LAST_RESTART="$STATE_DIR/telegram-watchdog.last-restart"
FAIL_COUNT="$STATE_DIR/telegram-watchdog.fail-count"
TOKEN_FILE=/home/clawd/.openclaw/secrets/telegram.token
CHAT_ID=215087477

mkdir -p "$(dirname "$LOG")" "$STATE_DIR"
ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { echo "$(ts) $*" >> "$LOG"; }

notify() {
  # Прямой вызов Bot API с хоста (идёт через redsocks/Tor, работает даже когда
  # пул соединений внутри gateway протух). При недоставке — только лог.
  local text="$1"
  curl -s --max-time 20 -X POST \
    "https://api.telegram.org/bot$(cat "$TOKEN_FILE")/sendMessage" \
    -d "chat_id=$CHAT_ID" --data-urlencode "text=$text" > /dev/null 2>&1 \
    || log "notify FAILED: $text"
}

channel_ok() {
  curl -s --max-time 15 \
    "https://api.telegram.org/bot$(cat "$TOKEN_FILE")/getMe" 2>/dev/null \
    | grep -q '"ok":true'
}

# --- Детект проблемы -------------------------------------------------------
reason=""
if ! systemctl --user is-active --quiet openclaw-gateway; then
  reason="сервис openclaw-gateway не запущен"
else
  timeouts=$(journalctl --user -u openclaw-gateway --since "-15 minutes" --no-pager 2>/dev/null \
    | grep -c "fetch timeout.*getMe" || true)
  ok_traffic=$(journalctl --user -u openclaw-gateway --since "-15 minutes" --no-pager 2>/dev/null \
    | grep -cE "sendMessage ok|outbound send ok|Inbound message" || true)
  if [ "${timeouts:-0}" -ge 3 ] && [ "${ok_traffic:-0}" -eq 0 ]; then
    reason="канал Telegram мёртв: ${timeouts} таймаутов getMe за 15 мин, успешного трафика нет"
  fi
fi

if [ -z "$reason" ]; then
  # всё хорошо — сбрасываем счётчик неудачных рестартов
  [ -f "$FAIL_COUNT" ] && rm -f "$FAIL_COUNT"
  exit 0
fi

# --- Rate-limit -------------------------------------------------------------
now=$(date +%s)
last=$(cat "$LAST_RESTART" 2>/dev/null || echo 0)
if [ $((now - last)) -lt 1800 ]; then
  log "SKIP (rate-limit 30m): $reason"
  exit 0
fi

# --- Рестарт ----------------------------------------------------------------
log "RESTART: $reason"
echo "$now" > "$LAST_RESTART"
systemctl --user restart openclaw-gateway
sleep 30

if channel_ok && systemctl --user is-active --quiet openclaw-gateway; then
  rm -f "$FAIL_COUNT"
  log "RECOVERED after restart"
  notify "🛠 Сторож: обнаружил, что Иваныч молчит ($reason). Перезапустил gateway — связь восстановлена. Сообщения за время простоя должны прийти сейчас."
else
  fails=$(( $(cat "$FAIL_COUNT" 2>/dev/null || echo 0) + 1 ))
  echo "$fails" > "$FAIL_COUNT"
  log "NOT RECOVERED after restart (attempt $fails)"
  if [ "$fails" -ge 3 ]; then
    notify "🚨 Сторож: gateway перезапущен ${fails} раза, но Telegram-канал НЕ восстановился ($reason). Нужно вмешательство: проверить Tor/redsocks на VPS."
  fi
fi
