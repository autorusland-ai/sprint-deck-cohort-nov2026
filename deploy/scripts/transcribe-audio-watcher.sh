#!/usr/bin/env bash
# Транскрибирует аудио-форматы, не поддерживаемые Groq Whisper напрямую (.amr, .3gp):
#
#  1. DeepGram nova-2 (ru, smart_format, diarize_model=latest + utterances) — принимает AMR
#     напрямую, длинные файлы OK. Разделяет говорящих: транскрипт приходит репликами
#     «[MM:SS] Руслан: …» / «[MM:SS] Собеседник: …», а не одним слитным полотном.
#     ВАЖНО: diarize_model нельзя передавать вместе с diarize — API вернёт 400.
#     Со старым diarize=true на телефонном моно Deepgram видел только одного спикера.
#  2. Groq Whisper Large v3 (fallback) — нужен ffmpeg → opus/ogg.
#  3. faster-whisper local CPU (fallback fallback) — если облачные API лежат.
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
DEEPGRAM_KEY=$(cat /home/clawd/.openclaw/secrets/deepgram.token 2>/dev/null || python3 -c 'import json; print(json.load(open("/home/clawd/.openclaw/openclaw.json"))["env"].get("DEEPGRAM_API_KEY",""))')
TG_TOKEN=$(cat /home/clawd/.openclaw/secrets/telegram.token)
CHAT_ID=215087477
WHISPER_PY=/home/clawd/browser-env/bin/python3.12

# Эталон голоса Руслана (~30 сек чистой речи). Если файл есть — клеится в начало
# записи перед отправкой в Deepgram: модель получает опорную точку и мы понимаем,
# какой из говорящих Руслан. Нет файла — реплики просто помечаются «Спикер 1/2».
ANCHOR=$(ls /home/clawd/.openclaw/media/voice-anchor-ruslan.* 2>/dev/null | head -1 || true)

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

# Транскрибация с цепочкой fallback.
# Принимает: путь к AMR-оригиналу
# Возвращает в stdout: "engine:text" (engine = deepgram/groq/whisper-local)
transcribe_audio() {
    local amr_file="$1"
    local out=""

    # 1. DeepGram прямо на AMR
    if [ -n "$DEEPGRAM_KEY" ]; then
        local resp send_file="$amr_file" ctype='audio/amr' anchor_sec=0 tmp_mix=''
        if [ -n "$ANCHOR" ] && [ -f "$ANCHOR" ]; then
            anchor_sec=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$ANCHOR" 2>/dev/null | cut -d. -f1)
            tmp_mix=$(mktemp --suffix=.wav)
            if [ -n "${anchor_sec:-}" ] && ffmpeg -y -nostdin -loglevel error -i "$ANCHOR" -i "$amr_file" \
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

# Реплики внутри эталона — это голос Руслана, по ним опознаём его speaker id.
me = None
if anchor > 0:
    for u in utts:
        if u.get("end", 0) <= anchor + 0.5:
            me = u.get("speaker")
            break

body = [u for u in utts if not (anchor > 0 and u.get("end", 0) <= anchor + 0.5)]
speakers = {u.get("speaker") for u in body}
# Монолог (диктофонная заметка, а не звонок) — метки только зашумят текст.
if len(speakers) < 2:
    print(" ".join((u.get("transcript") or "").strip() for u in body).strip() or flat)
    sys.exit(0)

def label(s):
    if me is not None:
        return "Руслан" if s == me else "Собеседник"
    return "Спикер %d" % (int(s) + 1)

# Deepgram дробит речь на короткие куски — склеиваем подряд идущие реплики одного
# говорящего, иначе на 20-минутном звонке получается 500 обрывков по два слова.
blocks = []
for u in body:
    txt = (u.get("transcript") or "").strip()
    if not txt:
        continue
    spk = u.get("speaker")
    start = max(0.0, float(u.get("start", 0)) - anchor)
    if blocks and blocks[-1][0] == spk:
        blocks[-1][2] += " " + txt
    else:
        blocks.append([spk, start, txt])

print("\n\n".join("[%02d:%02d] %s: %s" % (int(s)//60, int(s)%60, label(k), t)
                  for k, s, t in blocks))
' 2>>"$LOG")
        if [ -n "$out" ] && [ ${#out} -gt 20 ]; then
            printf 'deepgram:%s' "$out"
            return 0
        fi
        echo "$(ts) [deepgram-empty-or-fail]" >> "$LOG"
    fi

    # 2. ffmpeg → opus → Groq Whisper
    local tmp_opus
    tmp_opus=$(mktemp --suffix=.ogg)
    if ffmpeg -y -nostdin -loglevel error -i "$amr_file" -ar 16000 -c:a libopus -application voip "$tmp_opus" 2>>"$LOG"; then
        local resp
        resp=$(curl -sS --max-time 120 -X POST 'https://api.groq.com/openai/v1/audio/transcriptions' \
            -H "Authorization: Bearer $GROQ_KEY" \
            -F "file=@$tmp_opus" \
            -F "model=whisper-large-v3" \
            -F "language=ru" \
            -F "response_format=json" 2>>"$LOG")
        out=$(echo "$resp" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get("text","").strip())
except Exception:
    pass
' 2>>"$LOG")
        if [ -n "$out" ] && [ ${#out} -gt 20 ]; then
            rm -f "$tmp_opus"
            printf 'groq:%s' "$out"
            return 0
        fi
        echo "$(ts) [groq-empty-or-fail]" >> "$LOG"
    else
        echo "$(ts) [ffmpeg-fail-for-groq]" >> "$LOG"
    fi

    # 3. faster-whisper local (CPU, медленно но работает offline)
    if [ -x "$WHISPER_PY" ] && $WHISPER_PY -c 'import faster_whisper' 2>/dev/null; then
        # Используем converted opus если есть, иначе сам файл
        local audio_for_whisper="$tmp_opus"
        [ -s "$audio_for_whisper" ] || audio_for_whisper="$amr_file"

        out=$($WHISPER_PY <<PYEOF 2>>"$LOG"
from faster_whisper import WhisperModel
m = WhisperModel('base', device='cpu', compute_type='int8')
segments, _ = m.transcribe('$audio_for_whisper', language='ru', vad_filter=True)
parts = [s.text.strip() for s in segments if s.text.strip()]
print(' '.join(parts))
PYEOF
)
        if [ -n "$out" ] && [ ${#out} -gt 20 ]; then
            rm -f "$tmp_opus"
            printf 'whisper-local:%s' "$out"
            return 0
        fi
        echo "$(ts) [whisper-local-empty-or-fail]" >> "$LOG"
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

    # PBX-формат имени: <prefix>_<phone>_YYYYMMDDHHMMSS---uuid.amr
    event_ts=$(echo "$name" | grep -oE '[0-9]{14}' | head -1)
    if [ -n "$event_ts" ]; then
        event_date="${event_ts:0:4}-${event_ts:4:2}-${event_ts:6:2}"
        event_hhmm="${event_ts:8:2}${event_ts:10:2}"
        event_full="${event_date} ${event_ts:8:2}:${event_ts:10:2}"
    else
        # Если в имени нет 14-значного timestamp — берём mtime файла
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

    if [ -n "$client_prefix" ] && [ "$client_prefix" != "${name%.amr}" ]; then
        slug="voice-$(echo "$client_prefix" | sed -E 's/[^A-Za-zА-Яа-я0-9]/-/g; s/-+/-/g; s/^-|-$//g' | cut -c1-40)"
    else
        slug="voice-$(echo "$phone_raw" | tr -d '_-' | cut -c1-12)"
    fi

    # Collision-safe имя: если файл существует — добавить суффикс _2, _3 ...
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
    curl -sS --max-time 30 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
        -d "chat_id=$CHAT_ID" \
        --data-urlencode "text=$msg" \
        -d 'disable_notification=true' > /dev/null 2>>"$LOG" || true

    echo "$(ts) [ok:$engine] $name chars=${#text} inbox=$(basename "$inbox_file")" >> "$LOG"
    mv "$f" "$PROCESSED/"
done
