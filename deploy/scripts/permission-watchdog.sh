#!/usr/bin/env bash
# permission-watchdog.sh — держит права на секреты закрытыми.
# Файлы: 600. Каталоги секретов: 700 (аудит 07.09.2026 нашёл secrets/ с 775 —
# старая версия проверяла только файлы и каталог не трогала).
# Уведомление — через файл токена, как в telegram-watchdog.sh: прежний вариант
# делал source .env, а .env не является shell-файлом, и уведомление никогда не
# уходило. PW_DRY_RUN=1 — только лог, без отправки.
cd ~/.openclaw || exit 1
TOKEN_FILE=~/.openclaw/secrets/telegram.token
CHAT_ID=215087477
LOG=~/.openclaw/logs/permission-watchdog.log
changed=""
for dir in secrets credentials; do
  if [ -d "$dir" ] && [ "$(stat -c %a "$dir")" != "700" ]; then
    chmod 700 "$dir" && changed="$changed $dir/(700)"
  fi
done
for file in openclaw.json workspace/SOUL.md auth-profiles.json secrets/* credentials/*; do
  if [ -f "$file" ] && [ "$(stat -c %a "$file")" != "600" ]; then
    chmod 600 "$file" && changed="$changed $file(600)"
  fi
done
[ -z "$changed" ] && exit 0
echo "$(date -u +%FT%TZ) исправлены права:$changed" >> "$LOG"
if [ "${PW_DRY_RUN:-0}" = "1" ]; then
  echo "$(date -u +%FT%TZ) [dry-run] уведомление не отправлено" >> "$LOG"; exit 0
fi
[ -r "$TOKEN_FILE" ] && curl -s --max-time 20 -X POST \
  "https://api.telegram.org/bot$(cat "$TOKEN_FILE")/sendMessage" \
  -d chat_id="$CHAT_ID" --data-urlencode "text=🔒 Сторож прав: исправлено$changed" > /dev/null 2>&1 \
  || echo "$(date -u +%FT%TZ) уведомление НЕ доставлено" >> "$LOG"
