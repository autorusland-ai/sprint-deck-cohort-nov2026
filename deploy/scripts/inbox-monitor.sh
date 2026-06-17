#!/usr/bin/env bash
# Мониторинг inbox: раз в день в 10:00 МСК (07:00 UTC) шлёт Руслану в Telegram
# отчёт по содержимому /emmbase/inbox/ + что разобрал Claude за сутки.
#
# Также ловит "тихие пропажи": если файл был в snapshot вчера, но его нет ни в
# inbox, ни в КЛИЕНТЫ/, ни в _archive — алерт.

set -u

INBOX=/home/clawd/emmbase/inbox
EMMBASE=/home/clawd/emmbase
SNAPSHOTS=/home/clawd/.openclaw/backups/inbox-snapshot
LOG=/home/clawd/.openclaw/scripts/inbox-monitor.log
TG_TOKEN=$(cat /home/clawd/.openclaw/secrets/telegram.token)
CHAT_ID=215087477

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

# Текущее состояние inbox (только корень, без _archive/ruslan-actions/claude-инструкции)
CURRENT_FILES=$(find "$INBOX" -maxdepth 1 -type f -name '*.md' ! -name 'README*' 2>/dev/null | sort)
CURRENT_COUNT=$(echo "$CURRENT_FILES" | grep -c '^/' || echo 0)

# Что разобрал Claude за последние 24 часа (новые файлы в карточках клиентов)
RECENT_IN_CLIENTS=$(find "$EMMBASE/КЛИЕНТЫ" "$EMMBASE/КЛИЕНТЫ-АН" -type f -mtime -1 -name '*.md' 2>/dev/null | wc -l)
RECENT_IN_LIFE=$(find "$EMMBASE/life" -type f -mtime -1 -name '*.md' 2>/dev/null | wc -l)
RECENT_IN_PROJECTS=$(find "$EMMBASE/projects" -type f -mtime -1 -name '*.md' 2>/dev/null | wc -l)

# Сверить вчерашний snapshot с текущим — что пропало без следа
ALERT_DISAPPEARED=""
YESTERDAY_HOUR=$(date -u -d 'yesterday 10:00' '+%Y-%m-%d_%H')
YESTERDAY_SNAPSHOT="$SNAPSHOTS/snapshot-$YESTERDAY_HOUR"
# Ближайший к нему
NEAR_SNAPSHOT=$(ls -1d "$SNAPSHOTS"/snapshot-* 2>/dev/null | grep -E "$(date -u -d 'yesterday' '+%Y-%m-%d')" | sort | tail -1)

if [ -n "$NEAR_SNAPSHOT" ] && [ -d "$NEAR_SNAPSHOT" ]; then
    DISAPPEARED=$(
        for snap_file in "$NEAR_SNAPSHOT"/*.md; do
            [ -e "$snap_file" ] || continue
            name=$(basename "$snap_file")
            [[ "$name" == README* ]] && continue
            # есть ли он в inbox?
            [ -e "$INBOX/$name" ] && continue
            # есть ли он где-то в emmbase (по точному имени)?
            if ! find "$EMMBASE" -name "$name" -print -quit | grep -q .; then
                # есть ли он в _archive?
                if ! find "$INBOX/_archive" -name "$name" -print -quit 2>/dev/null | grep -q .; then
                    echo "$name"
                fi
            fi
        done
    )
    if [ -n "$DISAPPEARED" ]; then
        ALERT_DISAPPEARED=$(printf '\n\n⚠️ Пропали без следа (были вчера, нет сегодня):\n%s' "$DISAPPEARED" | head -c 1500)
    fi
fi

# Собираем сообщение
{
    printf '📊 Inbox-дайджест (%s)\n\n' "$(date '+%Y-%m-%d %H:%M')"
    printf 'В inbox сейчас: %d файлов\n' "$CURRENT_COUNT"
    if [ "$CURRENT_COUNT" -gt 0 ]; then
        echo "$CURRENT_FILES" | while read -r f; do
            [ -n "$f" ] || continue
            printf '  • %s\n' "$(basename "$f")"
        done | head -20
    fi
    printf '\nClaude разобрал за 24ч:\n'
    printf '  → КЛИЕНТЫ: %d файлов\n' "$RECENT_IN_CLIENTS"
    printf '  → life: %d\n' "$RECENT_IN_LIFE"
    printf '  → projects: %d\n' "$RECENT_IN_PROJECTS"
    if [ -n "$ALERT_DISAPPEARED" ]; then
        printf '%s' "$ALERT_DISAPPEARED"
    fi
    printf '\n\nСнапшоты: %s' "$(ls -1d $SNAPSHOTS/snapshot-* 2>/dev/null | wc -l) шт., LATEST=$(readlink $SNAPSHOTS/LATEST 2>/dev/null | xargs -I{} basename {})"
} > /tmp/inbox-digest.txt

curl -sS --max-time 30 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    -d "chat_id=$CHAT_ID" \
    --data-urlencode "text=$(cat /tmp/inbox-digest.txt)" \
    -d 'disable_notification=true' > /dev/null 2>>"$LOG"

echo "$(ts) [digest-sent] current=$CURRENT_COUNT clients=$RECENT_IN_CLIENTS disappeared=$(echo -n "$ALERT_DISAPPEARED" | wc -l)" >> "$LOG"
rm -f /tmp/inbox-digest.txt
