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

cleanup /home/clawd/.openclaw/media/inbound 3 media-inbound
cleanup /home/clawd/.openclaw/media/transcribed 1 media-transcribed
cleanup /home/clawd/.openclaw/media/transcribe-failed 14 media-transcribe-failed
cleanup /home/clawd/.openclaw/media/outbound 3 media-outbound
cleanup /home/clawd/.openclaw/media/tool-image-generation 7 media-images
cleanup /tmp/openclaw 7 tmp-openclaw

# Ротация наших же логов
for log in /home/clawd/.openclaw/scripts/transcribe-audio.log /home/clawd/.openclaw/scripts/media-cleanup.log; do
    if [ -f "$log" ] && [ $(stat -c%s "$log") -gt 5242880 ]; then  # >5MB
        tail -1000 "$log" > "$log.tmp" && mv "$log.tmp" "$log"
        echo "$(ts) [log-rotation] truncated $log to last 1000 lines" >> "$LOG"
    fi
done
