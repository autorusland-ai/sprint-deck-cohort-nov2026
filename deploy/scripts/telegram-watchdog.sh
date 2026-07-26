#!/usr/bin/env bash
# telegram-watchdog.sh — сторож Telegram-канала openclaw-gateway.
#
# Проблема: после обрыва Tor-циркуита долгоживущий процесс gateway остаётся
# с мёртвым пулом соединений к api.telegram.org и не восстанавливается сам
# (встроенный health-monitor рестартует провайдер внутри того же процесса).
# Инциденты: 27.06 (RKN-блокировка), 02-03.07 (стухший пул, бот молчал сутки).
#
# Логика: cron каждые 5 минут. Четыре триггера рестарта:
#   1. gateway не active.
#   2. входящие висят в ingress-spool >15 мин (прямой признак «бот не отвечает»,
#      ловит любую причину зависания обработчика — добавлено после инцидента 24-26.07).
#   3. ≥3 таймаутов getMe за 15 мин без успешного трафика (сетевой сбой, 02-03.07).
#   4. health-monitor ≥4 раз за 30 мин рестартовал провайдер вхолостую (проактивно,
#      срабатывает до того, как Руслан упрётся в молчание).
# Рестарт не чаще раза в 30 минут (state-файл). После рестарта проверяет, что канал
# жив И очередь разошлась, затем шлёт Руслану отчёт. Если 3 рестарта подряд не
# помогли — алерт «нужно вмешательство».
set -u
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

LOG=/home/clawd/.openclaw/logs/telegram-watchdog.log
SPOOL=/home/clawd/.openclaw/telegram/ingress-spool-default
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
  # Мало проверить getMe: при зависании обработчика (инцидент 24-26.07) API отвечал
  # ok, а бот при этом молчал. Поэтому дополнительно требуем, чтобы очередь
  # входящих разошлась — это доказывает, что сообщения реально обрабатываются.
  curl -s --max-time 15 \
    "https://api.telegram.org/bot$(cat "$TOKEN_FILE")/getMe" 2>/dev/null \
    | grep -q '"ok":true' || return 1
  [ "$(find "$SPOOL" -maxdepth 1 -type f -name '*.json' -mmin +5 2>/dev/null | wc -l)" -eq 0 ]
}

# --- Детект проблемы -------------------------------------------------------
# Три независимых сигнала. Порядок = от самого прямого к косвенным.
reason=""
if ! systemctl --user is-active --quiet openclaw-gateway; then
  reason="сервис openclaw-gateway не запущен"
else
  # [1] ПРЯМОЙ признак: входящие сообщения лежат в spool необработанными.
  # В норме файл живёт там секунды. Ловит ЛЮБУЮ причину зависания обработчика.
  # Инцидент 24-26.07: опрос складывал апдейты в spool, потребитель был мёртв,
  # бот молчал 2 суток — таймаутов getMe при этом почти не было.
  stuck=$(find "$SPOOL" -maxdepth 1 -type f -name '*.json' -mmin +15 2>/dev/null | wc -l)
  if [ "${stuck:-0}" -gt 0 ]; then
    reason="${stuck} входящих сообщений висят в очереди >15 мин — обработчик не забирает их"
  fi

  ok_traffic=$(journalctl --user -u openclaw-gateway --since "-15 minutes" --no-pager 2>/dev/null \
    | grep -cE "sendMessage ok|outbound send ok|Inbound message" || true)

  # [2] Сетевой признак: серия таймаутов getMe без успешного трафика (инцидент 02-03.07).
  if [ -z "$reason" ]; then
    timeouts=$(journalctl --user -u openclaw-gateway --since "-15 minutes" --no-pager 2>/dev/null \
      | grep -c "fetch timeout.*getMe" || true)
    if [ "${timeouts:-0}" -ge 3 ] && [ "${ok_traffic:-0}" -eq 0 ]; then
      reason="канал Telegram мёртв: ${timeouts} таймаутов getMe за 15 мин, успешного трафика нет"
    fi
  fi

  # [3] ПРОАКТИВНЫЙ признак: встроенный health-monitor молотит рестарты провайдера
  # вхолостую. Срабатывает ДО того, как Руслан напишет и упрётся в молчание.
  if [ -z "$reason" ]; then
    hm=$(journalctl --user -u openclaw-gateway --since "-30 minutes" --no-pager 2>/dev/null \
      | grep -c "health-monitor: restarting" || true)
    if [ "${hm:-0}" -ge 4 ] && [ "${ok_traffic:-0}" -eq 0 ]; then
      reason="канал завис: health-monitor перезапускал провайдер ${hm} раз за 30 мин без результата"
    fi
  fi
fi

if [ -z "$reason" ]; then
  # Счётчик неудач сбрасываем не при первой же удачной проверке, а после
  # получаса без сбоев: иначе мигающий канал обнулял его каждые 5 минут,
  # эскалация не накапливалась и владелец не узнавал о повторных отказах.
  if [ -f "$FAIL_COUNT" ] && [ -n "$(find "$FAIL_COUNT" -mmin +30 2>/dev/null)" ]; then
    rm -f "$FAIL_COUNT"
    log "тихо 30 мин — счётчик неудач сброшен"
  fi
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
  # Сообщаем сразу, с первой неудачи. Раньше порог был 3 неудачи подряд, а между
  # рестартами стоит пауза 30 мин — то есть алерт требовал 1.5 часа простоя и за
  # всю историю не сработал ни разу при шести реальных провалах.
  if [ "$fails" -eq 1 ]; then
    notify "⚠️ Сторож: Иваныч молчит ($reason). Перезапустил gateway — не помогло, пробую дальше. Если через полчаса тишина, нужно смотреть Tor/redsocks на VPS."
  else
    notify "🚨 Сторож: ${fails} перезапуска подряд не помогли ($reason). Автолечение не справляется — нужно вмешательство: проверить Tor/redsocks на VPS."
  fi
fi
