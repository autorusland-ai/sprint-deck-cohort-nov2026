#!/usr/bin/env bash
# Страховка: если бот ошибочно положит файл в ~/.openclaw/workspace/inbox/
# (его рабочая папка, не Obsidian vault) — перенесёт в правильное место.
#
# Триггер: cron каждую минуту. flock от наложений.
#
# Правильный путь: /home/clawd/emmbase/inbox/  (синхронизируется Syncthing в Obsidian vault).
# Неправильный (но бот иногда попадает): /home/clawd/.openclaw/workspace/inbox/

set -u

LOCKFILE=/tmp/inbox-relocator.lock
exec 9>"$LOCKFILE"
flock -n 9 || exit 0

WRONG=/home/clawd/.openclaw/workspace/inbox
RIGHT=/home/clawd/emmbase/inbox
LOG=/home/clawd/.openclaw/scripts/inbox-relocator.log
ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

[ -d "$WRONG" ] || exit 0
mkdir -p "$RIGHT"

shopt -s nullglob
moved=0
collided=0
for f in "$WRONG"/*.md; do
    name=$(basename "$f")
    # Защитный README — оставляем (мы его сами туда положили как памятку)
    if [[ "$name" == README* ]]; then continue; fi

    if [ -e "$RIGHT/$name" ]; then
        # Уже есть в правильном месте — сравниваем
        if diff -q "$f" "$RIGHT/$name" > /dev/null 2>&1; then
            rm "$f"
            echo "$(ts) [dedup] removed identical: $name" >> "$LOG"
        else
            # Разные — переименуем с timestamp
            ts_suffix=$(date '+%H%M%S')
            new_name="${name%.md}_relocated_${ts_suffix}.md"
            mv "$f" "$RIGHT/$new_name"
            echo "$(ts) [collision] $name → $new_name" >> "$LOG"
            collided=$((collided+1))
        fi
    else
        mv "$f" "$RIGHT/"
        echo "$(ts) [moved] $name → $RIGHT/" >> "$LOG"
        moved=$((moved+1))
    fi
done

# Если что-то перенесли — алерт в Telegram, чтобы было видно что бот опять промахнулся
if [ "$moved" -gt 0 ] || [ "$collided" -gt 0 ]; then
    TG_TOKEN=$(cat /home/clawd/.openclaw/secrets/telegram.token 2>/dev/null)
    if [ -n "$TG_TOKEN" ]; then
        msg="🔄 inbox-relocator: бот опять записал в workspace/inbox вместо /emmbase/inbox/. Перенесено: ${moved}, конфликтов: ${collided}."
        curl -sS --max-time 15 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
            -d "chat_id=215087477" \
            --data-urlencode "text=$msg" \
            -d 'disable_notification=true' > /dev/null 2>&1
    fi
fi
