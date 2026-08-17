#!/usr/bin/env bash
# Раз в день сверяет Google + Yandex календари с разделом «📅 Календарь» в Tasks Board.md.
# При расхождении:
#   1. Шлёт Руслану Telegram-уведомление с конкретикой
#   2. Кладёт инструкцию в /emmbase/inbox/ для Claude
#
# Логика:
#   - События в календарях на этой неделе, которых нет в Tasks Board
#     → «Руслан добавил руками в календарь, нужно перенести в Tasks Board»
#   - Записи в Tasks Board, которых нет в календарях
#     → «Возможно, дата изменилась или встреча отменена»
#
# Триггер: cron раз в день в 04:30 UTC (07:30 МСК — перед утренним прогнозом).

set -u

LOCKFILE=/tmp/calendar-board-sync.lock
exec 9>"$LOCKFILE"
flock -n 9 || exit 0

LOG=/home/clawd/.openclaw/scripts/calendar-board-sync.log
TG_TOKEN=$(cat /home/clawd/.openclaw/secrets/telegram.token)
CHAT_ID=215087477
TASKS_BOARD="/home/clawd/emmbase/Tasks Board.md"
INBOX=/home/clawd/emmbase/inbox
GWS=/home/clawd/.openclaw/scripts/gws-cli.py
YACAL=/home/clawd/.openclaw/scripts/yacal-cli.py

ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

# Сегодня + 7 дней (ISO 8601 МСК)
RANGE_START=$(date '+%Y-%m-%dT00:00:00+03:00')
RANGE_END=$(date -d '+7 days' '+%Y-%m-%dT23:59:59+03:00')

# Собираем события из обоих календарей в общий JSON массив
python3 - "$RANGE_START" "$RANGE_END" > /tmp/cal-board-sync-events.json 2>>"$LOG" <<'PYEOF'
import sys, json, subprocess
from datetime import datetime, timezone, timedelta

MSK = timezone(timedelta(hours=3))
start, end = sys.argv[1], sys.argv[2]

def parse_dt(s):
    if not s: return None
    s = s.replace("Z", "+00:00")
    try: return datetime.fromisoformat(s).astimezone(MSK)
    except: return None

events = []

# Google
try:
    r = subprocess.run([
        "/home/clawd/.openclaw/scripts/gws-cli.py", "calendar", "range", start, end
    ], capture_output=True, text=True, timeout=30)
    raw = json.loads(r.stdout) if r.stdout.strip() else []
    if isinstance(raw, list):
        for e in raw:
            s = e.get("start", {})
            s_iso = s.get("dateTime") if isinstance(s, dict) else (s or "")
            dt = parse_dt(s_iso)
            if dt:
                events.append({
                    "source": "google",
                    "calendar": "primary",
                    "summary": e.get("summary", "")[:80],
                    "date": dt.strftime("%Y-%m-%d"),
                    "time": dt.strftime("%H:%M"),
                    "dow": dt.strftime("%a"),  # день недели
                })
except Exception as ex:
    print(f"google-fail: {ex}", file=sys.stderr)

# Yandex — обходим основные календари
YANDEX_CALENDARS = ["Консультации", "Личное", "Семья", "Буддийские", "Оплат", "Ремон"]
seen_uids = set()
for cal in YANDEX_CALENDARS:
    try:
        r = subprocess.run([
            "/home/clawd/.openclaw/scripts/yacal-cli.py", "range", start, end, "--calendar", cal
        ], capture_output=True, text=True, timeout=20)
        raw = json.loads(r.stdout) if r.stdout.strip() else []
        if isinstance(raw, list):
            for e in raw:
                uid = e.get("uid", "")
                if uid and uid in seen_uids: continue
                seen_uids.add(uid)
                dt = parse_dt(e.get("start", ""))
                if dt:
                    events.append({
                        "source": "yandex",
                        "calendar": cal,
                        "summary": e.get("summary", "")[:80],
                        "date": dt.strftime("%Y-%m-%d"),
                        "time": dt.strftime("%H:%M"),
                        "dow": dt.strftime("%a"),
                    })
    except Exception as ex:
        print(f"yandex-{cal}-fail: {ex}", file=sys.stderr)

events.sort(key=lambda x: (x["date"], x["time"]))
print(json.dumps(events, ensure_ascii=False, indent=2))
PYEOF

EVENTS_COUNT=$(python3 -c 'import json; print(len(json.load(open("/tmp/cal-board-sync-events.json"))))' 2>>"$LOG")
echo "$(ts) [collected] $EVENTS_COUNT events from calendars" >> "$LOG"

# Парсим Tasks Board, секция «📅 Календарь»
python3 - > /tmp/cal-board-sync-board.json 2>>"$LOG" <<'PYEOF'
import re, json
from datetime import date, timedelta

src = open("/home/clawd/emmbase/Tasks Board.md").read()
# Достаём секцию между "## 📅 Календарь" и следующим "## "
m = re.search(r"## 📅 Календарь\s*\n(.*?)(?=\n## |\Z)", src, re.DOTALL)

# Свёрнутые блоки «▸ Прошедшее» — обычный markdown внутри html-тегов. Убираем
# сами теги, чтобы строки внутри разбирались наравне с остальными: раньше
# события из свёртки считались отсутствующими и попадали в отчёт.
def strip_html(t):
    t = re.sub(r"</?details[^>]*>", "", t)
    return re.sub(r"<summary[^>]*>.*?</summary>", "", t, flags=re.DOTALL)


def dates_in(line):
    """Все даты ДД.ММ, которые покрывает строка карточки.

    Календарь ведётся не только точечными датами, но и диапазонами:
    «14–16.08», «30.08–02.09». Прежняя регулярка вытаскивала из «14–16.08»
    только «16.08», поэтому события 14 и 15 числа считались отсутствующими —
    отсюда 21 одинаковый пустой отчёт с 31.07.2026.
    """
    seg = re.search(r"\*\*([^*]+)\*\*", line)
    if not seg:
        return []
    s = seg.group(1)
    out = []

    # Диапазон через границу месяца: 30.08–02.09
    r2 = re.search(r"(\d{1,2})\.(\d{1,2})\s*[–—-]\s*(\d{1,2})\.(\d{1,2})", s)
    if r2:
        d1, m1, d2, m2 = (int(g) for g in r2.groups())
        y = date.today().year
        try:
            cur, end = date(y, m1, d1), date(y, m2, d2)
            if end < cur:
                end = date(y + 1, m2, d2)
            while cur <= end and len(out) < 62:
                out.append(cur.strftime("%d.%m"))
                cur += timedelta(days=1)
            return out
        except ValueError:
            pass

    # Диапазон внутри месяца: 14–16.08
    r1 = re.search(r"(\d{1,2})\s*[–—-]\s*(\d{1,2})\.(\d{1,2})", s)
    if r1:
        d1, d2, mo = (int(g) for g in r1.groups())
        if d1 <= d2:
            return ["%02d.%02d" % (d, mo) for d in range(d1, d2 + 1)]

    # Одиночная дата
    for d, mo in re.findall(r"(\d{1,2})\.(\d{1,2})", s):
        out.append("%02d.%02d" % (int(d), int(mo)))
    return out


entries = []
if m:
    for line in strip_html(m.group(1)).split("\n"):
        # Цитаты и служебные пометки («> ⚠️ Формат сменён на карточки 06.08»)
        # событиями не являются — иначе попадают в отчёт как расхождение.
        if line.lstrip().startswith(">"):
            continue
        dates = dates_in(line)
        if not dates:
            continue
        tm = re.search(r"(\d{1,2}):(\d{2})", line)
        cols = [c.strip() for c in line.strip().strip("|").split("|")]
        summary = (cols[-1] if cols else line)[:80]
        entries.append({
            "dates_md": dates,
            "date_md": dates[0],          # для обратной совместимости отчёта
            "time": tm.group(0) if tm else "",
            "summary": summary,
            "raw_line": line.strip()[:120],
        })
print(json.dumps(entries, ensure_ascii=False, indent=2))
PYEOF

# Сверка
python3 - > /tmp/cal-board-sync-diff.txt 2>>"$LOG" <<'PYEOF'
import json, re
events = json.load(open("/tmp/cal-board-sync-events.json"))
board = json.load(open("/tmp/cal-board-sync-board.json"))

def norm(s):
    return re.sub(r"[^\wа-яА-Я]+", "", s.lower())[:30]

STOP = {"календарь", "google", "yandex", "период", "благоприятный", "конфликт"}


def words(s):
    """Значимые слова строки — для сравнения формулировок, а не подстрок."""
    return {w for w in re.findall(r"[\wа-яА-Я]{4,}", s.lower()) if w not in STOP}


def same_event(a, b):
    """Одно ли это событие. Формулировки в календаре и в карточке различаются:
    «Завершение сделок/показы недвижимости» против «АН: благоприятный период —
    завершение сделок / показы». Сравнение по вхождению подстроки такие пары
    не ловило, поэтому событие считалось отсутствующим при каждой сверке."""
    if norm(a) in norm(b) or norm(b) in norm(a):
        return True
    wa, wb = words(a), words(b)
    return bool(wa and wb and len(wa & wb) >= 2)

# Одна встреча, заведённая и в Google, и в Яндексе, приходит двумя событиями.
# Раньше это считалось за два расхождения. Схлопываем до сравнения, источники
# перечисляем через запятую — чтобы в отчёте было видно, где событие лежит.
deduped = {}
for e in events:
    key = (e["date"], e["time"], norm(e["summary"]))
    if key in deduped:
        src = deduped[key]["source"]
        if e["source"] not in src:
            deduped[key]["source"] = f"{src}+{e['source']}"
    else:
        deduped[key] = dict(e)
events = list(deduped.values())

def board_covers(b, cal_md):
    return cal_md in b.get("dates_md", [b.get("date_md")])

# События в календаре → проверяем что есть в Tasks Board
missing_in_board = []
for e in events:
    d, m = e["date"].split("-")[2], e["date"].split("-")[1]
    cal_md = f"{d}.{m}"
    matched = False
    for b in board:
        if board_covers(b, cal_md):
            # И summary похож
            if same_event(e["summary"], b["summary"]):
                matched = True
                break
            # Или просто событие в этот день
            if e["time"] and b["time"] and e["time"] == b["time"]:
                matched = True
                break
    if not matched:
        missing_in_board.append(e)

# Записи в Tasks Board → проверяем что есть в календарях
# Обратная сверка — только по карточкам с конкретным временем: это реальные
# встречи, которые опасно потерять. Карточки без времени — заметки и периоды
# (бизнес-завтраки, «благоприятный период»), их в календарь никто не заводит,
# и раньше они шумели в каждом отчёте.
# Окно сверки — то же, что запрашивалось у календарей (сегодня + 7 дней).
# Карточки вне окна проверить нечем: событий за эти даты просто не запрашивали,
# поэтому раньше они попадали в отчёт как «отсутствующие» — навсегда.
from datetime import date, timedelta
today = date.today()
window = {(today + timedelta(days=i)).strftime("%d.%m") for i in range(0, 8)}

missing_in_calendar = []
for b in board:
    if not b.get("time"):
        continue
    if not (set(b.get("dates_md", [])) & window):
        continue
    raw = b.get("raw_line", "")
    # Выполненные и отменённые карточки сверять не нужно.
    if raw.lstrip().startswith("- [x]") or "ОТМЕН" in raw.upper():
        continue
    # Обрывки перенесённых строк («ТЗ]]») — не события.
    if len(re.sub(r"[^\wа-яА-Я]+", "", b.get("summary", ""))) < 8:
        continue
    matched = False
    for e in events:
        d, m = e["date"].split("-")[2], e["date"].split("-")[1]
        cal_md = f"{d}.{m}"
        if board_covers(b, cal_md) and same_event(e["summary"], b["summary"]):
            matched = True
            break
    if not matched:
        missing_in_calendar.append(b)

# Формируем отчёт
report = []
if missing_in_board:
    report.append("🆕 В календарях, нет в Tasks Board:")
    for e in missing_in_board:
        report.append(f"  • [{e['source']}/{e['calendar'][:12]}] {e['date']} {e['time']} — {e['summary']}")

if missing_in_calendar:
    report.append("")
    report.append("⚠️ В Tasks Board, нет в календарях:")
    for b in missing_in_calendar[:10]:
        report.append(f"  • {b['date_md']} {b['time']} — {b['summary']}")

if not report:
    report.append("✅ Календари ↔ Tasks Board: расхождений нет")

print("\n".join(report))
PYEOF

REPORT=$(cat /tmp/cal-board-sync-diff.txt)
HAS_DIFF=$(echo "$REPORT" | grep -cE "^(🆕|⚠️)" || true)

if [ "$HAS_DIFF" -eq 0 ]; then
    echo "$(ts) [no-diff] calendars and Tasks Board are in sync" >> "$LOG"
    rm -f /tmp/cal-board-sync-*.json /tmp/cal-board-sync-*.txt
    exit 0
fi

# 1. Telegram-уведомление Руслану
TG_MSG=$(printf "📅 Calendar ↔ Tasks Board (сверка)\n\n%s" "$REPORT" | head -c 3500)
curl -sS --max-time 30 -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    -d "chat_id=$CHAT_ID" \
    --data-urlencode "text=$TG_MSG" \
    -d 'disable_notification=true' > /dev/null 2>>"$LOG"

# 2. Инструкция для Claude в inbox
TS_DATE=$(date '+%Y-%m-%d')
TS_HHMM=$(date '+%H%M')
INBOX_FILE="$INBOX/${TS_DATE}_${TS_HHMM}_sync-calendar-tasks-board.md"
{
    # Тип «инструкция» отменён системным промтом v5 (31.07.2026) и в белый
    # список не входит — файлы с ним не исполняются НИ ОДНОЙ сессией. Отчёты
    # копились в inbox мёртвым грузом: 21 штука с 31.07 по 11.08. Сверка требует
    # решения человека (событие отменено? дата сдвинулась?), поэтому «вопрос».
    echo '# Тип: вопрос'
    echo "# Дата события: $(date '+%Y-%m-%d %H:%M')"
    echo '# Относится к: бизнес'
    echo '# Связать с: [[Tasks Board]], [[Google Calendar]], [[Yandex Calendar]]'
    echo '# Источник: бот'
    echo '# Срочность: 🟡 обычно'
    echo
    echo 'Сверка календарей и Tasks Board выявила расхождения. Нужно решение Руслана —'
    echo 'автоматически ничего не применять.'
    echo
    echo 'Действия:'
    echo '1. Для событий из «🆕 В календарях, нет в Tasks Board» — добавь строки в `Tasks Board.md` → раздел «📅 Календарь».'
    echo '2. Для записей из «⚠️ В Tasks Board, нет в календарях» — спроси Руслана: дата актуальна? событие отменено? Или это просто заметка, которую не надо синхронизировать?'
    echo '3. После применения — отметь в DECISIONS_LOG.md что сделано.'
    echo
    echo 'Детали расхождения:'
    echo
    echo '```'
    echo "$REPORT"
    echo '```'
    echo
    echo "Сырые данные на момент сверки:"
    echo "- События из календарей: \`/tmp/cal-board-sync-events.json\` (на момент $(date -u '+%Y-%m-%dT%H:%M:%SZ'))"
    echo "- Записи Tasks Board: \`/tmp/cal-board-sync-board.json\`"
} > "$INBOX_FILE"

echo "$(ts) [diff-found] events_new=$(echo "$REPORT" | grep -c '^  •  *' || true) inbox=$(basename "$INBOX_FILE")" >> "$LOG"

# Чистка временных
rm -f /tmp/cal-board-sync-events.json /tmp/cal-board-sync-board.json /tmp/cal-board-sync-diff.txt
