#!/bin/bash
# Daily digest — 07:30 МСК будние дни
# Собирает: Gmail → календарь → погода → Telegram

TELEGRAM_TOKEN=$(cat ~/.openclaw/secrets/telegram.token)
CHAT_ID="215087477"
GWS="/home/clawd/.openclaw/scripts/gws-cli.py"
YACAL="/home/clawd/.openclaw/scripts/yacal-cli.py"

cd /home/clawd/.openclaw/scripts

# Gmail — важные непрочитанные
GMAIL_UNREAD=$(python3 "$GWS" gmail search "is:unread is:important" --limit 5 2>/dev/null)
GMAIL_BLOCK=$(echo "$GMAIL_UNREAD" | python3 -c "
import json, sys
try:
    msgs = json.load(sys.stdin)
    if not msgs:
        print('📬 Входящие чисто')
        sys.exit()
    lines = [f'📬 Важных писем: {len(msgs)}']
    for m in msgs[:5]:
        subj = (m.get('subject') or '(без темы)')[:60]
        sender = (m.get('from') or '')[:30]
        lines.append(f'  • {sender}: {subj}')
    print('\n'.join(lines))
except: print('📬 Gmail: ошибка чтения')
" 2>/dev/null)

# Google Calendar today
GCAL_EVENTS=$(python3 "$GWS" calendar today 2>/dev/null)
GCAL_BLOCK=$(echo "$GCAL_EVENTS" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    events = d.get('events', [])
    if not events:
        print('📅 Google: нет событий')
    else:
        print('📅 Google Calendar:')
        for e in events[:5]:
            t = e.get('start', e.get('dateTime',''))
            t = t[-5:] if len(t) >= 5 else t
            print(f'  {t} — {e.get(\"summary\",\"Без названия\")[:50]}')
except: print('📅 Google Calendar: ошибка')
" 2>/dev/null)

# Yandex Calendar — Консультации Созвоны (primary calendar)
YACAL_TMP=$(python3 "$YACAL" today --calendar "Консультации Созвоны" 2>/dev/null)
YCAL_BLOCK=$(echo "$YACAL_TMP" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    events = d.get('events', [])
    if not events:
        sys.exit()
    print('📅 Yandex (консультации):')
    for e in events[:5]:
        if isinstance(e, dict):
            t = e.get('start','')[-5:]
            print(f'  {t} — {e.get(\"summary\",\"\")[:50]}')
except: pass
" 2>/dev/null)
[ -z "$YCAL_BLOCK" ] && YCAL_BLOCK="📅 Yandex: нет данных"

# Weather
WEATHER=$(curl -s --max-time 8 "https://wttr.in/Moscow?format=j1" 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    c = d['current_condition'][0]
    temp = c['temp_C']
    desc = c['weatherDesc'][0]['value']
    wind = c['windspeedKmph']
    print(f'🌤 Москва: {temp}°C, {desc}, ветер {wind} км/ч')
except: print('🌤 Погода: недоступна')
" 2>/dev/null || echo "🌤 Погода: недоступна")

# Today's date
TODAY=$(date '+%d.%m.%Y')

# Message
MSG="━━━━━━━━━━━━━━━━━━
📋 Дайджест на $TODAY
━━━━━━━━━━━━━━━━━━

$GMAIL_BLOCK

$GCAL_BLOCK
$YCAL_BLOCK

$WEATHER"

# Send to Telegram
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="$MSG" \
    -d parse_mode="HTML" > /dev/null 2>&1

echo "Digest sent $(date)"
