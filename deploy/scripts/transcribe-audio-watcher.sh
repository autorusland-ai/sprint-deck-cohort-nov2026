#!/usr/bin/env bash
# Транскрибирует аудио-форматы, не поддерживаемые Groq Whisper напрямую (.amr, .3gp):
#
#  1. DeepGram nova-2 (ru, smart_format, diarize_model=latest + utterances) — OGG/opus
#     от ffmpeg. Разделяет говорящих, длинные файлы OK.
#     ВАЖНО: diarize_model нельзя вместе с diarize — API вернёт 400.
#  2. Groq Whisper Large v3 — ОТКЛЮЧЁН (ключ мёртв, 403).
#  3. faster-whisper local CPU — fallback.
#
# Результат: файл в /emmbase/inbox/ с YAML v3 + Telegram-уведомление.
# Триггер: cron каждую минуту. flock защищает от наложения.

set -u

LOCKFILE=/tmp/transcribe-audio-watcher.lock
exec 9>"$LOCKFILE"
flock -n 9 || exit 0

INBOUND=/home/clawd/.openclaw/media/inbound
PROCESSED=/home/clawd/.openclaw/media/transcribed
FAILED=/home/clawd/.openclaw/media/transcribe-failed
INBOX=/home/clawd/emmbase/inbox
LOG=/home/clawd/.openclaw/scripts/transcribe-audio.log
mkdir -p "$PROCESSED" "$FAILED" "$INBOX"

GROQ_KEY=$(python3 -c 'import json; print(json.load(open("/home/clawd/.openclaw/openclaw.json"))["env"].get("GROQ_API_KEY",""))')
DEEPGRAM_KEY=$(python3 -c 'import json; print(json.load(open("/home/clawd/.openclaw/openclaw.json"))["env"].get("DEEPGRAM_API_KEY",""))')
TG_TOKEN=$(cat /home/clawd/.openclaw/secrets/telegram.token 2>/dev/null || echo "")
CHAT_ID=215087477
WHISPER_PY=/home/clawd/browser-env/bin/python3.12

ANCHOR=$(ls /home/clawd/.openclaw/media/voice-anchor-ruslan.* 2>/dev/null | head -1 || true)

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

transcribe_audio() {
    local amr_file="$1"
    local out=""
    local tmp_opus=""

    # 0. Конвертируем AMR → OGG/opus (Deepgram принимает ogg напрямую)
    tmp_opus=$(mktemp --suffix=.ogg)
    if ! ffmpeg -y -nostdin -loglevel error -i "$amr_file" -ar 16000 -c:a libopus -application voip "$tmp_opus" 2>>"$LOG"; then
        echo "$(ts) [ffmpeg-amr-to-ogg-fail] $amr_file" >> "$LOG"
        rm -f "$tmp_opus"
        return 1
    fi

    # 1. DeepGram на OGG (быстрее и надёжнее чем Groq)
    if [ -n "$DEEPGRAM_KEY" ]; then
        local resp send_file="$tmp_opus" ctype='audio/ogg' anchor_sec=0 tmp_mix=''
        # Голосовой якорь (~30 сек речи Руслана) клеится в НАЧАЛО записи ВСТЫК,
        # без паузы: вставка тишины ослабляет связку — Deepgram считает разговор
        # новым куском и даёт голосу Руслана другой speaker id (проверено).
        # Длительность берём точную, не округлённую: эталон режется ПОСЛОВНО,
        # иначе теряется начало разговора («Алло, Ирина?»), которое Deepgram
        # склеивает с хвостом эталона в одну реплику.
        if [ -n "$ANCHOR" ] && [ -f "$ANCHOR" ]; then
            anchor_sec=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$ANCHOR" 2>/dev/null)
            tmp_mix=$(mktemp --suffix=.wav)
            if [ -n "${anchor_sec:-}" ] && ffmpeg -y -nostdin -loglevel error -i "$ANCHOR" -i "$tmp_opus" \
                    -filter_complex '[0:a][1:a]concat=n=2:v=0:a=1[a]' -map '[a]' -ar 16000 -ac 1 "$tmp_mix" 2>>"$LOG"; then
                send_file="$tmp_mix"; ctype='audio/wav'
            else
                anchor_sec=0; rm -f "$tmp_mix"; tmp_mix=''
                echo "$(ts) [anchor-concat-failed]" >> "$LOG"
            fi
        fi

        resp=$(curl -sS --max-time 600 -X POST \
            'https://api.deepgram.com/v1/listen?model=nova-2&language=ru&smart_format=true&punctuate=true&diarize_model=latest&utterances=true' \
            -H "Authorization: Token $DEEPGRAM_KEY" \
            -H "Content-Type: $ctype" \
            --data-binary @"$send_file" 2>>"$LOG")
        [ -n "$tmp_mix" ] && rm -f "$tmp_mix"

        out=$(echo "$resp" | ANCHOR_SEC="${anchor_sec:-0}" python3 -c '
import sys, json, os
anchor = float(os.environ.get("ANCHOR_SEC") or 0)
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
res = d.get("results", {})
utts = res.get("utterances") or []
flat = res.get("channels",[{}])[0].get("alternatives",[{}])[0].get("transcript","").strip()
if not utts:
    print(flat)
    sys.exit(0)

def cut_anchor(u):
    if anchor <= 0:
        t = (u.get("transcript") or "").strip()
        return (u.get("speaker"), float(u.get("start", 0)), t) if t else None
    ws = [w for w in (u.get("words") or []) if float(w.get("start", 0)) >= anchor]
    if not ws:
        return None
    t = " ".join((w.get("punctuated_word") or w.get("word") or "") for w in ws).strip()
    return (u.get("speaker"), float(ws[0].get("start", 0)) - anchor, t) if t else None

me = None
if anchor > 0:
    counts = {}
    for u in utts:
        for w in u.get("words") or []:
            if float(w.get("start", 0)) < anchor:
                s = w.get("speaker", u.get("speaker"))
                counts[s] = counts.get(s, 0) + 1
    if counts:
        me = max(counts, key=counts.get)

body = [p for p in (cut_anchor(u) for u in utts) if p]
speakers = {spk for spk, _, _ in body}
if len(speakers) < 2:
    print(" ".join(t for _, _, t in body).strip() or flat)
    sys.exit(0)

def label(s):
    if me is not None:
        return "Руслан" if s == me else "Собеседник"
    return "Спикер %d" % (int(s) + 1)

blocks = []
for spk, start, txt in body:
    if blocks and blocks[-1][0] == spk:
        blocks[-1][2] += " " + txt
    else:
        blocks.append([spk, max(0.0, start), txt])

print("\n\n".join("[%02d:%02d] %s: %s" % (int(s)//60, int(s)%60, label(k), t)
                  for k, s, t in blocks))
' 2>>"$LOG")
        if [ -n "$out" ] && [ ${#out} -gt 20 ]; then
            rm -f "$tmp_opus"
            printf 'deepgram:%s' "$out"
            return 0
        fi
        echo "$(ts) [deepgram-empty-or-fail]" >> "$LOG"
    fi

    # 2. Groq Whisper — ОТКЛЮЧЁН (403 Forbidden, ключ мёртв)

    # 3. faster-whisper local CPU — единственный резерв после отключения Groq.
    # Модель 'small': на русском заметно точнее 'base', а точность здесь важнее
    # скорости — это записи разговоров с клиентами, ошибки уезжают в базу.
    # Модель скачана заранее в ~/.cache/huggingface, чтобы отказ Deepgram не
    # упирался ещё и в загрузку полугигабайта.
    if [ -x "$WHISPER_PY" ] && $WHISPER_PY -c 'import faster_whisper' 2>/dev/null; then
        out=$($WHISPER_PY 2>>"$LOG" <<PYEOF
from faster_whisper import WhisperModel
m = WhisperModel('small', device='cpu', compute_type='int8')
segments, _ = m.transcribe('$tmp_opus', language='ru', vad_filter=True)
parts = [s.text.strip() for s in segments if s.text.strip()]
print(' '.join(parts))
PYEOF
)
        if [ -n "$out" ] && [ ${#out} -gt 20 ]; then
            rm -f "$tmp_opus"
            printf 'whisper-local:%s' "$out"
            return 0
        fi
        echo "$(ts) [whisper-local-empty]" >> "$LOG"
    fi

    rm -f "$tmp_opus"
    return 1
}

shopt -s nullglob
for f in "$INBOUND"/*.amr "$INBOUND"/*.3gp "$INBOUND"/*.AMR; do
    [ -e "$f" ] || continue
    name=$(basename "$f")

    result=$(transcribe_audio "$f")
    if [ -z "$result" ]; then
        echo "$(ts) [transcribe-fail-all-engines] $name" >> "$LOG"
        mv "$f" "$FAILED/"
        continue
    fi

    engine="${result%%:*}"
    text="${result#*:}"

    event_ts=$(echo "$name" | grep -oE '[0-9]{14}' | head -1)
    if [ -n "$event_ts" ]; then
        event_date="${event_ts:0:4}-${event_ts:4:2}-${event_ts:6:2}"
        event_hhmm="${event_ts:8:2}${event_ts:10:2}"
        event_full="${event_date} ${event_ts:8:2}:${event_ts:10:2}"
    else
        event_full=$(date -d "@$(stat -c%Y "$f")" '+%Y-%m-%d %H:%M')
        event_date=$(date -d "@$(stat -c%Y "$f")" '+%Y-%m-%d')
        event_hhmm=$(date -d "@$(stat -c%Y "$f")" '+%H%M')
    fi

    phone_raw=$(echo "$name" | grep -oE '[78]_[0-9]{3}_[0-9]{3}[-_][0-9]{2}[-_][0-9]{2}' | head -1)
    if [ -n "$phone_raw" ]; then
        phone_fmt="+$(echo "$phone_raw" | sed -E 's/_/ /g; s/^([78]) ([0-9]{3}) ([0-9]{3}) ([0-9]{2}) ([0-9]{2})$/\1 \2 \3-\4-\5/')"
    else
        phone_fmt="не определён"
    fi

    client_prefix=$(echo "$name" | sed -E 's/_[78]_[0-9]{3}_.*$//; s/_/ /g' | sed 's/  */ /g; s/^ //; s/ $//')
    if [ -n "$client_prefix" ] && [ "$client_prefix" != "${name%.amr}" ] && [ "$client_prefix" != "${name%.AMR}" ]; then
        relates="клиент: $client_prefix"
        link_entity="$client_prefix"
    else
        relates="новый-клиент?"
        link_entity="неизвестный-номер ($phone_fmt)"
    fi

    slug="voice-$(printf '%s' "$client_prefix" | python3 -c '
import sys, re
s = re.sub(r"[^0-9A-Za-zА-Яа-яЁё]+", "-", sys.stdin.read()).strip("-")
print(s[:40])
')"

    inbox_file="$INBOX/${event_date}_${event_hhmm}_${slug}.md"
    n=2
    while [ -e "$inbox_file" ]; do
        inbox_file="$INBOX/${event_date}_${event_hhmm}_${slug}_${n}.md"
        n=$((n+1))
    done

    {
        printf '# Тип: голосовое\n'
        printf '# Дата события: %s\n' "$event_full"
        printf '# Относится к: %s\n' "$relates"
        printf '# Телефон: %s\n' "$phone_fmt"
        printf '# Связать с: [[%s]]\n' "$link_entity"
        printf '# Источник: бот\n'
        printf '# Срочность: 🟡 обычно\n\n'
        printf '**Источник:** %s, %s\n' "$client_prefix" "$phone_fmt"
        printf '**Оригинал AMR:** `~/.openclaw/media/transcribed/%s`\n\n' "$name"
        printf '**Транскрипт (%s):**\n\n%s\n' "$engine" "$text"
    } > "$inbox_file"

    msg=$(printf '📝 Транскрипт (%s, %d chars)\n%s\n%s\n→ %s' \
        "$engine" "${#text}" "$client_prefix" "$event_full" "$(basename "$inbox_file")")
    [ -n "$TG_TOKEN" ] && curl -sS --max-time 30 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
        -d "chat_id=$CHAT_ID" \
        --data-urlencode "text=$msg" \
        -d 'disable_notification=true' > /dev/null 2>&1 || true

    echo "$(ts) [ok:$engine] $name chars=${#text} inbox=$(basename "$inbox_file")" >> "$LOG"
    mv "$f" "$PROCESSED/"
done
