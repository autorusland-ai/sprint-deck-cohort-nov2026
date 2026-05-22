#!/usr/bin/env python3
# ============================================================================
# snapshot-config.py — превратить ЖИВОЙ openclaw.json (с литеральными
# секретами) в безопасный ШАБЛОН config/openclaw.json (секреты → ${VAR}).
# ============================================================================
# Зачем: бот/мастер мог менять конфиг прямо на VPS. Чтобы держать в git
# актуальный, но БЕЗ секретов шаблон для disaster-recovery (deploy.sh
# подставит значения обратно через envsubst из .env).
#
# Использование:
#   python scripts/snapshot-config.py <живой-конфиг.json> [.env] [out.json]
# По умолчанию: .env и config/openclaw.json в корне репо.
#
# ВАЖНО: на выходе выполняется leak-scan. Если в шаблоне остался хоть один
# секретоподобный литерал — скрипт завершится с кодом 2 и НИЧЕГО не запишет.
# ============================================================================
import json, re, sys, io, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else None
ENV = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, ".env")
OUT = sys.argv[3] if len(sys.argv) > 3 else os.path.join(ROOT, "config", "openclaw.json")

if not SRC:
    print("usage: snapshot-config.py <live-config.json> [.env] [out.json]")
    sys.exit(1)

# Ключи, чьи ЗНАЧЕНИЯ являются учётными данными и должны стать ${VAR}.
SECRET_KEYS = [
    "MINIMAX_API_KEY", "DEEPSEEK_API_KEY", "OPENROUTER_API_KEY", "GROQ_API_KEY",
    "OPENAI_API_KEY", "TELEGRAM_BOT_TOKEN", "GATEWAY_AUTH_TOKEN", "GONKA_API_KEY",
    "BRAVE_API_KEY", "TAVILY_API_KEY", "OPENAI_SOCKS_PROXY",
    "GOOGLE_OAUTH_CLIENT_ID", "GOOGLE_OAUTH_CLIENT_SECRET",
    "GOOGLE_WORKSPACE_CLIENT_ID", "GOOGLE_WORKSPACE_CLIENT_SECRET",
    "GOOGLE_WORKSPACE_REFRESH_TOKEN",
]

# читаем .env -> {key: value}
env = {}
for ln in io.open(ENV, encoding="utf-8"):
    m = re.match(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$", ln)
    if m:
        env[m.group(1)] = m.group(2).split("#")[0].strip()

d = json.load(open(SRC, encoding="utf-8"))

# 1) env-блок целиком: каждое значение -> ${KEY}
if isinstance(d.get("env"), dict):
    for k in list(d["env"].keys()):
        d["env"][k] = "${%s}" % k

raw = json.dumps(d, ensure_ascii=False, indent=2)

# 2) подмена литералов секретов в остальном тексте (длинные -> первыми)
pairs = sorted(
    [(env[k], k) for k in SECRET_KEYS if env.get(k) and len(env[k]) >= 8],
    key=lambda x: -len(x[0]),
)
replaced = {}
for val, key in pairs:
    c = raw.count(val)
    if c:
        raw = raw.replace(val, "${%s}" % key)
        replaced[key] = c

# 3) LEAK-SCAN: ничего секретоподобного не должно остаться
leak_rx = re.compile(
    r'(sk-[A-Za-z0-9_\-]{12,}|gsk_[A-Za-z0-9]{15,}|tvly-[A-Za-z0-9_\-]{8,}'
    r'|GOCSPX-[\w\-]{6,}|ya29\.[\w\-]{15,}|1//[\w\-]{15,}'
    r'|AIza[\w\-]{20,}|xox[baprs]-[\w\-]{10,}|[A-Za-z0-9]{40,})'
)
# убираем уже подставленные ${...} из рассмотрения
scan = re.sub(r"\$\{[A-Z0-9_]+\}", "", raw)
leaks = sorted(set(leak_rx.findall(scan)))

print("=== replaced (key: count) ===")
for k, c in replaced.items():
    print("  %-32s %d" % (k, c))
print("=== leak-scan ===")
if leaks:
    print("  [LEAK] остались секретоподобные литералы (%d): НЕ ЗАПИСЫВАЮ" % len(leaks))
    for s in leaks:
        print("     ", s[:12] + "...(%dch)" % len(s))
    sys.exit(2)
print("  [OK] чисто — секретов в шаблоне нет")

# финальная проверка: валидный JSON
json.loads(raw)
io.open(OUT, "w", encoding="utf-8", newline="\n").write(raw + "\n")
print("=== written:", OUT, "(%d bytes) ===" % len(raw))
