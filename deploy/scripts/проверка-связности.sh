#!/usr/bin/env bash
# Ежедневный детектор связности базы EMMBASE. Считает три числа и кладёт отчёт
# в inbox. НИЧЕГО не чинит и в базу, кроме отчёта, не пишет — массовая правка
# только руками сессии, по регламенту массовых операций.
#
# ТЗ: agents/тз-скрипт-проверки-связности-базы.md (v1, 05.09.2026).
# База отсчёта на 05.09.2026: вне индекса 190/1011, битых 2474, неоднозначных 6066.
#
# Реализация на Python 3, а не на grep: кириллические диапазоны в grep -E дают
# на этой машине «Invalid collation character» (локаль C.UTF-8).
set -u

LOCKFILE=/tmp/проверка-связности.lock
exec 9>"$LOCKFILE"
flock -n 9 || exit 0

VAULT=/home/clawd/emmbase
STATE=/home/clawd/.openclaw/state/connectivity-check.json
LOG=/home/clawd/.openclaw/logs/проверка-связности.log
mkdir -p "$(dirname "$STATE")" "$(dirname "$LOG")"

VAULT="$VAULT" STATE="$STATE" LOG="$LOG" DRY="${1:-}" python3 <<'PYEOF'
import json, os, re, sys, time
from datetime import datetime, timedelta, timezone

VAULT = os.environ["VAULT"]
STATE = os.environ["STATE"]
LOG = os.environ["LOG"]
DRY = os.environ.get("DRY", "") in ("--dry-run", "-n")
MSK = timezone(timedelta(hours=3))

# Папки и имена, которые не считаются живыми файлами базы.
SKIP_DIRS = (
    "_archive", "agents/_versions", "АРХИВ", "inbox/_archive", "life/чекины",
    ".obsidian", ".smart-env", ".stfolder", ".git", "_to_delete",
)
SKIP_RE = re.compile(r"(^|/)(_backup[^/]*)(/|$)")


def is_skipped(rel):
    parts = rel.split("/")
    for d in SKIP_DIRS:
        seg = d.split("/")
        if parts[:len(seg)] == seg or d in parts:
            return True
    if SKIP_RE.search(rel):
        return True
    base = parts[-1]
    return ".bak-" in base or base.startswith("_backup")


# --- обход базы -------------------------------------------------------------
all_files = []          # относительные пути ВСЕХ .md и не-.md целей ссылок
live_md = []            # живые .md, которые обязаны быть в индексе
by_name = {}            # basename (и без .md) -> [rel, ...]

for root, dirs, files in os.walk(VAULT):
    dirs[:] = [d for d in dirs if d not in (".git", ".obsidian", ".smart-env", ".stfolder")]
    for fn in files:
        rel = os.path.relpath(os.path.join(root, fn), VAULT).replace("\\", "/")
        all_files.append(rel)
        base = os.path.basename(rel)
        by_name.setdefault(base, []).append(rel)
        if base.lower().endswith(".md"):
            by_name.setdefault(base[:-3], []).append(rel)
            if not is_skipped(rel):
                live_md.append(rel)

paths_exact = set(all_files)
paths_noext = {p[:-3] for p in all_files if p.lower().endswith(".md")}

# --- регулярки для ссылок ---------------------------------------------------
FENCE = re.compile(r"```.*?```", re.DOTALL)
INLINE = re.compile(r"`[^`\n]*`")
LINK = re.compile(r"\[\[([^\]\n]+)\]\]")


def link_target(raw):
    """Цель ссылки без алиаса и якорей."""
    t = raw.split("\\|")[0].split("|")[0]
    return t.split("#")[0].split("^")[0].strip()


# --- метрика 1: вне индекса -------------------------------------------------
index_path = os.path.join(VAULT, "ПОЛНЫЙ_ИНДЕКС.md")
index_text = ""
if os.path.exists(index_path):
    index_text = open(index_path, encoding="utf-8", errors="replace").read()

# Индекс — это список ССЫЛОК, поэтому учтённость проверяется по целям [[...]],
# а не по вхождению строки: подстрока «index» или «Кадуцей» встречается в тексте
# индекса и считала бы учтёнными файлы, ссылки на которые там нет.
index_targets = set()
for raw in LINK.findall(index_text):
    g = link_target(raw)
    if not g:
        continue
    for v in (g, g + ".md", os.path.basename(g), os.path.basename(g) + ".md"):
        index_targets.add(v)

out_of_index = []
for rel in live_md:
    base = os.path.basename(rel)
    stem = base[:-3] if base.lower().endswith(".md") else base
    if rel in index_targets or rel[:-3] in index_targets or base in index_targets or stem in index_targets:
        continue
    out_of_index.append(rel)

# --- разбор ссылок ----------------------------------------------------------
broken = 0
ambiguous = 0
broken_samples = []

for rel in live_md:
    try:
        text = open(os.path.join(VAULT, rel), encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    # Obsidian не резолвит ссылки внутри кода — и мы не парсим.
    text = INLINE.sub(" ", FENCE.sub(" ", text))
    for raw in LINK.findall(text):
        t = raw.split("\\|")[0].split("|")[0]
        t = t.split("#")[0].split("^")[0].strip()
        if not t:
            continue
        if "/" in t:
            # Цель с путём резолвится ТОЛЬКО точным путём от корня волта.
            if t in paths_exact or t in paths_noext or (t + ".md") in paths_exact:
                continue
            broken += 1
            if len(broken_samples) < 40:
                broken_samples.append((rel, t))
        else:
            hits = by_name.get(t) or by_name.get(t + ".md") or []
            hits = list(dict.fromkeys(hits))
            if len(hits) == 1:
                continue
            if len(hits) >= 2:
                ambiguous += 1
            else:
                broken += 1
                if len(broken_samples) < 40:
                    broken_samples.append((rel, t))

# --- дельта к прошлому прогону ---------------------------------------------
prev = {}
if os.path.exists(STATE):
    try:
        prev = json.load(open(STATE, encoding="utf-8"))
    except Exception:
        prev = {}


def delta(now, key):
    was = prev.get(key)
    if was is None:
        return "%d (первый прогон)" % now
    d = now - was
    sign = "±0" if d == 0 else ("+%d" % d if d > 0 else str(d))
    return "%d (было %d, %s)" % (now, was, sign)


n_out, n_broken, n_amb = len(out_of_index), broken, ambiguous
total_live = len(live_md)
pct = (n_out * 100.0 / total_live) if total_live else 0

body = [
    "🗂 Вне индекса: %s — из %d живых файлов (%.0f %%)" % (delta(n_out, "out_of_index"), total_live, pct),
    "🔗 Битых ссылок: %s" % delta(n_broken, "broken"),
    "❓ Неоднозначных: %s" % delta(n_amb, "ambiguous"),
]

grew = n_out - prev.get("out_of_index", n_out)
if grew >= 3:
    body.append("")
    body.append("⚠️ **Вне индекса выросло на %d за сутки.** Признак `🗂 Индекс` "
                "ставился, а каскад не исполнялся — иначе файл попал бы в индекс "
                "той же сессией." % grew)

# До 10 свежайших файлов вне индекса — чтобы разбор был исполним без пересканирования.
if out_of_index:
    newest = sorted(out_of_index,
                    key=lambda r: os.path.getmtime(os.path.join(VAULT, r)),
                    reverse=True)[:10]
    body.append("")
    body.append("**Свежайшие вне индекса:**")
    for r in newest:
        ts = datetime.fromtimestamp(os.path.getmtime(os.path.join(VAULT, r)), MSK)
        body.append("- `%s` · %s" % (r, ts.strftime("%d.%m %H:%M")))

if broken_samples:
    body.append("")
    body.append("**Примеры битых ссылок:**")
    for src, target in broken_samples[:10]:
        body.append("- `[[%s]]` — в `%s`" % (target, src))

report = "\n".join(body)
now = datetime.now(MSK)

if DRY:
    print(report)
    sys.exit(0)

fname = "%s_проверка-связности.md" % now.strftime("%Y-%m-%d_%H%M")
out = os.path.join(VAULT, "inbox", fname)
with open(out, "w", encoding="utf-8") as f:
    # Тип «вопрос», а не «действие-задача»: это отчёт, автоматически по нему
    # ничего не делается — правило белого списка ЯДРА.
    f.write("# Тип: вопрос\n")
    f.write("# Дата события: %s\n" % now.strftime("%Y-%m-%d %H:%M"))
    f.write("# Относится к: бизнес\n")
    f.write("# Источник: бот\n")
    f.write("# Срочность: 🟢 не срочно\n\n")
    f.write("# Связность базы на %s\n\n" % now.strftime("%d.%m.%Y"))
    f.write(report + "\n\n")
    f.write("> Считает `проверка-связности.sh` на VPS. Скрипт ничего не чинит: "
            "массовая правка — руками сессии, по регламенту массовых операций.\n")

json.dump({"out_of_index": n_out, "broken": n_broken, "ambiguous": n_amb,
           "at": now.isoformat()}, open(STATE, "w", encoding="utf-8"), ensure_ascii=False)

with open(LOG, "a", encoding="utf-8") as f:
    f.write("%s вне_индекса=%d битых=%d неоднозначных=%d живых=%d -> %s\n"
            % (time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
               n_out, n_broken, n_amb, total_live, fname))
print("отчёт: inbox/%s" % fname)
PYEOF
