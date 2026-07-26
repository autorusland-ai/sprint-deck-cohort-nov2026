#!/usr/bin/env bash
# Чистит обработанные media-артефакты openclaw.
# Cron: ежедневно 04:00 UTC (07:00 МСК).
set -u
LOG=/home/clawd/.openclaw/scripts/media-cleanup.log
ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

cleanup() {
    local dir=$1 days=$2 label=$3
    [ -d "$dir" ] || return 0
    local before=$(find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
    local size_before=$(du -sb "$dir" 2>/dev/null | cut -f1)
    find "$dir" -maxdepth 1 -type f -mtime +$days -delete 2>/dev/null
    local after=$(find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
    local size_after=$(du -sb "$dir" 2>/dev/null | cut -f1)
    local removed=$((before - after))
    local saved=$(( (size_before - size_after) / 1024 ))
    echo "$(ts) [$label] removed=$removed files (>${days}d), freed=${saved}KB, remaining=$after" >> "$LOG"
}

# Чистка по маске имени — для каталогов, где рядом лежат файлы,
# которые удалять НЕЛЬЗЯ (например активные сессии агента).
cleanup_glob() {
    local dir=$1 pattern=$2 days=$3 label=$4
    [ -d "$dir" ] || return 0
    local before size_before after size_after removed saved
    before=$(find "$dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | wc -l)
    size_before=$(find "$dir" -maxdepth 1 -type f -name "$pattern" -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')
    find "$dir" -maxdepth 1 -type f -name "$pattern" -mtime +$days -delete 2>/dev/null
    after=$(find "$dir" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | wc -l)
    size_after=$(find "$dir" -maxdepth 1 -type f -name "$pattern" -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {print s+0}')
    removed=$((before - after))
    saved=$(( (size_before - size_after) / 1024 ))
    echo "$(ts) [$label] removed=$removed files (>${days}d), freed=${saved}KB, remaining=$after" >> "$LOG"
}

cleanup /home/clawd/.openclaw/media/inbound 3 media-inbound
cleanup /home/clawd/.openclaw/media/transcribed 1 media-transcribed
cleanup /home/clawd/.openclaw/media/transcribe-failed 14 media-transcribe-failed
cleanup /home/clawd/.openclaw/media/outbound 3 media-outbound
cleanup /home/clawd/.openclaw/media/tool-image-generation 7 media-images
cleanup /tmp/openclaw 7 tmp-openclaw

# ---------- Ротация старых сессий агента ----------
# 26.07.2026: каталог sessions распух до 451 МБ (405 МБ — trajectory-дампы).
# ВНИМАНИЕ: активные сессии — это <uuid>.jsonl, их удалять НЕЛЬЗЯ.
# Чистим только производные файлы:
#   *.trajectory.jsonl — пошаговые дампы рассуждений, нужны лишь для отладки свежих сессий
#   *.jsonl.bak-*      — авто-бэкапы runtime (копились с 9 мая)
SESSIONS=/home/clawd/.openclaw/agents/main/sessions
cleanup_glob "$SESSIONS" '*.trajectory.jsonl' 30 sessions-trajectory
cleanup_glob "$SESSIONS" '*.jsonl.bak-*'      30 sessions-bak

# Ротация наших же логов
for log in /home/clawd/.openclaw/scripts/transcribe-audio.log /home/clawd/.openclaw/scripts/media-cleanup.log; do
    if [ -f "$log" ] && [ $(stat -c%s "$log") -gt 5242880 ]; then  # >5MB
        tail -1000 "$log" > "$log.tmp" && mv "$log.tmp" "$log"
        echo "$(ts) [log-rotation] truncated $log to last 1000 lines" >> "$LOG"
    fi
done
