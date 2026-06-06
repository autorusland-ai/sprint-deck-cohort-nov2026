#!/usr/bin/env bash
# Транскрибирует аудио-форматы, не поддерживаемые Groq Whisper напрямую (.amr, .3gp и т.п.):
# ffmpeg → .ogg/opus 16k → Groq Whisper Large v3 → Telegram сообщение.
#
# Триггер: cron каждую минуту. flock защищает от наложения.

set -euo pipefail

LOCKFILE=/tmp/transcribe-audio-watcher.lock
exec 9>"$LOCKFILE"
flock -n 9 || exit 0  # уже бежит другой инстанс — выходим тихо

INBOUND=/home/clawd/.openclaw/media/inbound
PROCESSED=/home/clawd/.openclaw/media/transcribed
FAILED=/home/clawd/.openclaw/media/transcribe-failed
LOG=/home/clawd/.openclaw/scripts/transcribe-audio.log
mkdir -p "$PROCESSED" "$FAILED"

GROQ_KEY=$(python3 -c 'import json; print(json.load(open("/home/clawd/.openclaw/openclaw.json"))["env"]["GROQ_API_KEY"])')
TG_TOKEN=$(cat /home/clawd/.openclaw/secrets/telegram.token)
CHAT_ID=215087477

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

# Принимаем .amr и .3gp — Groq не поддерживает; .ogg/.mp3/.wav openclaw отправляет сам.
shopt -s nullglob
for f in "$INBOUND"/*.amr "$INBOUND"/*.3gp "$INBOUND"/*.AMR; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    tmp=$(mktemp --suffix=.ogg)

    if ! ffmpeg -y -i "$f" -ar 16000 -c:a libopus -application voip "$tmp" 2>>"$LOG"; then
        echo "$(ts) [ffmpeg-fail] $name" >> "$LOG"
        mv "$f" "$FAILED/"
        rm -f "$tmp"
        continue
    fi

    response=$(curl -sS --max-time 60 -X POST 'https://api.groq.com/openai/v1/audio/transcriptions'         -H "Authorization: Bearer $GROQ_KEY"         -F "file=@$tmp"         -F "model=whisper-large-v3"         -F "language=ru"         -F "response_format=json" 2>>"$LOG") || {
        echo "$(ts) [curl-fail] $name" >> "$LOG"
        rm -f "$tmp"
        continue  # не двигаем — попробуем в следующий tick
    }

    text=$(echo "$response" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("text","").strip())' 2>>"$LOG")

    if [ -z "$text" ]; then
        echo "$(ts) [no-text] $name response=$response" >> "$LOG"
        rm -f "$tmp"
        continue
    fi

    # Извлекаем телефон/дату из имени для контекста (PBX-формат: 7_NNN_NNN-NN-NN_YYYYMMDDHHMMSS---uuid.amr)
    meta=$(echo "$name" | sed -E 's/_/ /g; s/---.*//; s/^7 /+7 /')

    msg=$(printf '📝 Транскрипт (.amr через ffmpeg)\nИсточник: %s\n\n%s' "$meta" "$text")

    curl -sS --max-time 15 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage"         -d "chat_id=$CHAT_ID"         --data-urlencode "text=$msg"         -d 'disable_notification=true' > /dev/null 2>>"$LOG"

    echo "$(ts) [ok] $name chars=${#text}" >> "$LOG"
    mv "$f" "$PROCESSED/"
    rm -f "$tmp"
done
