#!/usr/bin/env bash
# Daily digest — 07:30 МСК будние дни (cron: 30 4 * * 1-5)
# Собирает: Gmail важные → Google Calendar → Yandex Calendar (все 7) → сверка с Tasks Board → погода → Telegram.

set -u

TELEGRAM_TOKEN=$(cat /home/clawd/.openclaw/secrets/telegram.token)
CHAT_ID="215087477"
GWS="/home/clawd/.openclaw/scripts/gws-cli.py"
YACAL="/home/clawd/.openclaw/scripts/yacal-cli.py"
TASKS_BOARD="/home/clawd/emmbase/Tasks Board.md"
LOG="/home/clawd/.openclaw/scripts/daily-digest.log"

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
echo "$(ts) digest start" >> "$LOG"

# ===== Gmail =====
GMAIL_RAW=$("$GWS" gmail search "is:unread is:important" --limit 5 2>>"$LOG" || echo '[]')
GMAIL_BLOCK=$(echo "$GMAIL_RAW" | python3 -c '
import json, sys
try:
    d = json.loads(sys.stdin.read() or "[]")
    if isinstance(d, dict) and d.get("error"):
        print(f"📬 Gmail: {d.get(\"exception\",\"ошибка\")[:80]}")
        sys.exit()
    msgs = d if isinstance(d, list) else d.get("messages", [])
    if not msgs:
        print("📬 Важных непрочитанных писем нет")
    else:
        lines = [f"📬 Важных писем: {len(msgs)}"]
        for m in msgs[:5]:
            subj = (m.get("subject") or "(без темы)")[:60]
            sender = (m.get("from") or m.get("sender") or "")[:30]
            lines.append(f"  • {sender}: {subj}")
        print("\n".join(lines))
except Exception as e:
    print(f"📬 Gmail: парсинг fail: {e}")
' 2>>"$LOG")

# ===== Google Calendar today =====
GCAL_RAW=$("$GWS" calendar today 2>>"$LOG" || echo '[]')
GCAL_BLOCK=$(echo "$GCAL_RAW" | python3 -c '
import json, sys
from datetime import datetime, timezone, timedelta
MSK = timezone(timedelta(hours=3))

def parse_time(s):
    """Принимает ISO string (с Z или с offset), возвращает HH:MM в МСК."""
    if not s: return ""
    s = s.replace("Z", "+00:00")
    try:
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=MSK)
        return dt.astimezone(MSK).strftime("%H:%M")
    except Exception:
        return s[11:16] if len(s) > 16 else ""

try:
    d = json.loads(sys.stdin.read() or "[]")
    if isinstance(d, dict) and d.get("error"):
        print(f"📅 Google: {d.get(\"exception\",\"ошибка\")[:80]}")
        sys.exit()
    events = d if isinstance(d, list) else d.get("events", [])
    if not events:
        print("📅 Google: нет событий")
    else:
        lines = ["📅 Google Calendar:"]
        for e in events[:6]:
            start_raw = e.get("start")
            if isinstance(start_raw, dict):
                start_str = start_raw.get("dateTime") or start_raw.get("date") or ""
            else:
                start_str = start_raw or ""
            t = parse_time(start_str)
            lines.append(f"  {t} — {e.get(\"summary\",\"(без названия)\")[:55]}")
        print("\n".join(lines))
except Exception as e:
    print(f"📅 Google: парсинг fail: {e}")
' 2>>"$LOG")

# ===== Yandex Calendar today (все 6 events-календарей) =====
YCAL_BLOCK=$(python3 - <<'PYEOF' 2>>"$LOG"
import json, subprocess
from datetime import datetime, timezone, timedelta
MSK = timezone(timedelta(hours=3))

def parse_time(s):
    if not s: return ""
    s = s.replace("Z", "+00:00")
    try:
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None: dt = dt.replace(tzinfo=MSK)
        return dt.astimezone(MSK).strftime("%H:%M")
    except: return s[11:16] if len(s) > 16 else ""

YACAL = "/home/clawd/.openclaw/scripts/yacal-cli.py"
CALENDARS = ["Консультации", "Личное", "Семья", "Буддийские", "Оплат", "Ремон"]

all_events = []
seen = set()
for cal in CALENDARS:
    try:
        r = subprocess.run([YACAL, "today", "--calendar", cal], capture_output=True, text=True, timeout=20)
        events = json.loads(r.stdout) if r.stdout.strip() else []
        if isinstance(events, list):
            for e in events:
                uid = e.get("uid","")
                if uid and uid in seen: continue
                seen.add(uid)
                e["_calendar"] = cal
                all_events.append(e)
    except Exception:
        continue

all_events.sort(key=lambda e: e.get("start",""))

if not all_events:
    print("📅 Yandex: нет событий")
else:
    print("📅 Yandex Calendar:")
    for e in all_events[:8]:
        t = parse_time(e.get("start",""))
        cal = e.get("_calendar", "")[:12]
        print(f"  {t} [{cal}] — {e.get('summary','(без названия)')[:50]}")
PYEOF
)

# ===== Tasks Board — сегодняшние задачи и календарь =====
TASKS_BLOCK=$(python3 - <<'PYEOF' 2>>"$LOG"
import re, os
from datetime import datetime

path = "/home/clawd/emmbase/Tasks Board.md"
if not os.path.exists(path):
    print("📋 Tasks Board: файл не найден")
    raise SystemExit

src = open(path).read()

# Секция "Сегодня"
today_section = re.search(r"##\s*Сегодня[^\n]*\n(.*?)(?=\n##\s|\Z)", src, re.DOTALL)
today_tasks = []
if today_section:
    for line in today_section.group(1).split("\n"):
        m = re.match(r"\s*-\s*\[\s\]\s*(.+)$", line)
        if m: today_tasks.append(m.group(1).strip())

# Секция "📅 Календарь" — строки на сегодняшнюю дату
cal_section = re.search(r"##\s*📅?\s*Календарь.*?\n(.*?)(?=\n##\s|\Z)", src, re.DOTALL)
cal_today = []
today_str = datetime.now().strftime("%d.%m")
if cal_section:
    for line in cal_section.group(1).split("\n"):
        if today_str in line:
            cal_today.append(line.strip())

lines = []
if today_tasks:
    lines.append(f"📋 Tasks Board — сегодня ({len(today_tasks)}):")
    for t in today_tasks[:8]:
        clean = re.sub(r"\*\*|\[\[|\]\]|🔴|🟡|🟢|💰|📱|📞|📊|ℹ️|⏳|❄️|🔄", "", t).strip()
        lines.append(f"  • {clean[:80]}")
if cal_today:
    lines.append(f"📋 Tasks Board → Календарь:")
    for c in cal_today[:5]:
        clean = re.sub(r"\|", " | ", c).strip(" |")
        clean = re.sub(r"\*\*|\[\[|\]\]", "", clean)
        lines.append(f"  • {clean[:90]}")

if not lines:
    lines = ["📋 Tasks Board: на сегодня записей нет"]

print("\n".join(lines))
PYEOF
)

# ===== Weather =====
WEATHER=$(curl -s --max-time 8 "https://wttr.in/Moscow?format=j1" 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    c = d["current_condition"][0]
    print(f"🌤 Москва: {c[\"temp_C\"]}°C, {c[\"weatherDesc\"][0][\"value\"]}, ветер {c[\"windspeedKmph\"]} км/ч")
except: print("🌤 Погода: недоступна")
' 2>/dev/null || echo "🌤 Погода: недоступна")

# ===== Compose & Send =====
TODAY=$(date '+%d.%m.%Y, %A')

MSG="━━━━━━━━━━━━━━━━━━
📋 Дайджест на $TODAY
━━━━━━━━━━━━━━━━━━

$GMAIL_BLOCK

$GCAL_BLOCK

$YCAL_BLOCK

$TASKS_BLOCK

$WEATHER

ℹ️ Если есть расхождения между календарями и Tasks Board — спроси меня уточнить, я положу инструкцию в /emmbase/inbox/ для Claude."

curl -s --max-time 15 -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=$CHAT_ID" \
    --data-urlencode "text=$MSG" \
    -d 'disable_notification=false' > /dev/null

echo "$(ts) digest sent (${#MSG} chars)" >> "$LOG"
