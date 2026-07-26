#!/usr/bin/env bash
# Ежедневная проверка живости Google OAuth: пробует обновить access-токен и при
# отказе сразу шлёт Руслану алерт с кодом ошибки.
#
# Зачем: 26.07.2026 refresh_token оказался недействительным (invalid_grant), и
# узнали об этом случайно, разбирая другую поломку. Дайджест к тому моменту
# месяцами падал раньше обращения к API, поэтому в логах не осталось ни одной
# записи об отказе — причина сбоя так и не установлена. Эта проверка гарантирует,
# что следующий отказ будет замечен в тот же день и с текстом ошибки на руках.
set -u

LOG=/home/clawd/.openclaw/logs/google-token-check.log
STATE=/home/clawd/.openclaw/state/google-token-check.last-alert
TOKEN_FILE=/home/clawd/.openclaw/secrets/telegram.token
CHAT_ID=215087477
mkdir -p "$(dirname "$LOG")" "$(dirname "$STATE")"
ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

result=$(python3 - <<'PY'
import json, re, urllib.request, urllib.parse, urllib.error
try:
    s = open("/home/clawd/.openclaw/openclaw.json").read()
    g = lambda k: re.search(r'"%s"\s*:\s*"([^"]+)"' % k, s).group(1)
    data = urllib.parse.urlencode({
        "client_id": g("GOOGLE_WORKSPACE_CLIENT_ID"),
        "client_secret": g("GOOGLE_WORKSPACE_CLIENT_SECRET"),
        "refresh_token": g("GOOGLE_WORKSPACE_REFRESH_TOKEN"),
        "grant_type": "refresh_token",
    }).encode()
    urllib.request.urlopen("https://oauth2.googleapis.com/token", data, timeout=45)
    print("OK")
except urllib.error.HTTPError as e:
    body = e.read().decode()[:200].replace("\n", " ")
    print("FAIL HTTP %s %s" % (e.code, body))
except Exception as e:
    print("FAIL %s" % str(e)[:200].replace("\n", " "))
PY
)

if [ "${result:0:2}" = "OK" ]; then
  echo "$(ts) ok" >> "$LOG"
  [ -f "$STATE" ] && {
    rm -f "$STATE"
    curl -s --max-time 20 -X POST "https://api.telegram.org/bot$(cat "$TOKEN_FILE")/sendMessage" \
      -d "chat_id=$CHAT_ID" --data-urlencode "text=✅ Доступ к Google восстановлен — календарь и почта снова читаются." >/dev/null 2>&1
  }
  exit 0
fi

echo "$(ts) $result" >> "$LOG"

# Алерт не чаще раза в сутки, чтобы не превратить поломку в спам.
if [ -n "$(find "$STATE" -mmin -1440 2>/dev/null)" ]; then exit 0; fi
date -u '+%s' > "$STATE"

curl -s --max-time 20 -X POST "https://api.telegram.org/bot$(cat "$TOKEN_FILE")/sendMessage" \
  -d "chat_id=$CHAT_ID" \
  --data-urlencode "text=⚠️ Доступ к Google отвалился: ${result#FAIL }

Пока не восстановишь — в утреннем дайджесте не будет писем и событий календаря. Нужен разовый перевыпуск токена." >/dev/null 2>&1
