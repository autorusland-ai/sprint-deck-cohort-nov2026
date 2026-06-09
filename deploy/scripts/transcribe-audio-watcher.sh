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
INBOX=/home/clawd/emmbase/inbox
LOG=/home/clawd/.openclaw/scripts/transcribe-audio.log
mkdir -p "$PROCESSED" "$FAILED" "$INBOX"

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

    # Дополнительно — кладём в /emmbase/inbox/ как файл типа "голосовое"
    # Формат по системному промту v3 (06.06.2026):
    # - имя: ГГГГ-ММ-ДД_ЧЧММ_voice-<источник>.md, ДАТА = дата ЗВОНКА из PBX-имени
    # - YAML: # Дата события (когда звонок), # Телефон, # Связать с
    #
    # PBX-формат имени файла: <phone>_YYYYMMDDHHMMSS---<uuid>.amr
    # либо: <name>_<phone>_YYYYMMDDHHMMSS---<uuid>.amr (с ФИО префиксом)

    # Извлекаем timestamp звонка
    event_ts=$(echo "$name" | grep -oE '[0-9]{14}' | head -1)
    if [ -n "$event_ts" ]; then
        event_date="${event_ts:0:4}-${event_ts:4:2}-${event_ts:6:2}"
        event_hhmm="${event_ts:8:2}${event_ts:10:2}"
        event_full="${event_date} ${event_ts:8:2}:${event_ts:10:2}"
    else
        event_date=$(date '+%Y-%m-%d')
        event_hhmm=$(date '+%H%M')
        event_full=$(date '+%Y-%m-%d %H:%M')
    fi

    # Извлекаем номер телефона из PBX-имени (формат: 7_NNN_NNN[-_]NN[-_]NN, разделители _ или -)
    phone_raw=$(echo "$name" | grep -oE '[78]_[0-9]{3}_[0-9]{3}[-_][0-9]{2}[-_][0-9]{2}' | head -1)
    if [ -n "$phone_raw" ]; then
        # Нормализуем: подчёркивания → пробелы, дефисы оставляем как разделители блоков
        phone_fmt="+$(echo "$phone_raw" | sed -E 's/_/ /g; s/^([78]) ([0-9]{3}) ([0-9]{3}) ([0-9]{2}) ([0-9]{2})$/\1 \2 \3-\4-\5/')"
    else
        phone_fmt="не определён"
    fi

    # Извлекаем имя клиента (префикс перед телефоном, если есть)
    client_prefix=$(echo "$name" | sed -E 's/_[78]_[0-9]{3}_.*$//; s/_/ /g')
    if [ -n "$client_prefix" ] && [ "$client_prefix" != "$name" ]; then
        relates="клиент: $client_prefix"
        link_entity="$client_prefix"
    else
        relates="новый-клиент?"
        link_entity="неизвестный-номер ($phone_fmt)"
    fi

    # Slug для имени файла (короткая тема)
    if [ -n "$client_prefix" ] && [ "$client_prefix" != "$name" ]; then
        slug=$(echo "$client_prefix" | sed -E 's/[^A-Za-zА-Яа-я0-9]/-/g; s/-+/-/g; s/^-|-$//g' | cut -c1-40)
        slug="voice-$slug"
    else
        slug="voice-$(echo "$phone_raw" | tr -d '_-' | cut -c1-12)"
    fi

    inbox_file="$INBOX/${event_date}_${event_hhmm}_${slug}.md"

    {
        printf '# Тип: голосовое\n'
        printf '# Дата события: %s\n' "$event_full"
        printf '# Относится к: %s\n' "$relates"
        printf '# Телефон: %s\n' "$phone_fmt"
        printf '# Связать с: [[%s]]\n' "$link_entity"
        printf '# Источник: бот\n'
        printf '# Срочность: 🟡 обычно\n\n'
        printf '**Источник звонка:** %s\n' "$meta"
        printf '**Оригинал AMR:** `~/.openclaw/media/transcribed/%s`\n\n' "$name"
        printf '**Транскрипт (Whisper Large v3 через Groq, ffmpeg → opus):**\n\n%s\n' "$text"
    } > "$inbox_file"

    echo "$(ts) [ok] $name chars=${#text} inbox=$(basename "$inbox_file")" >> "$LOG"
    mv "$f" "$PROCESSED/"
    rm -f "$tmp"
done
