#!/usr/bin/env bash
# configure.sh — интерактивная настройка после bootstrap.sh.
# Запускать ОТ ИМЕНИ clawd (не root): sudo -u clawd bash configure.sh
#
# Что делает:
#   1) Спрашивает все ключи провайдеров (можно skip — поставит placeholder, потом отредактируешь руками).
#   2) Проводит Google OAuth flow (нужен браузер).
#   3) Опционально: Codex OAuth (через Tor, ChatGPT-Plus).
#   4) Заполняет ~/.openclaw/openclaw.json из template.
#   5) Регистрирует crontab + проверяет валидность.
#   6) Стартует openclaw-gateway + smoke-test.

set -euo pipefail

# ---------- preflight ----------
[ "$USER" = "clawd" ] || { echo "Запусти ОТ ИМЕНИ clawd: sudo -u clawd bash $0"; exit 1; }

DEPLOY_DIR=$(cd "$(dirname "$0")" && pwd)
OPENCLAW=$HOME/.npm-global/bin/openclaw
[ -x "$OPENCLAW" ] || { echo "openclaw CLI не найден в $OPENCLAW — bootstrap.sh не отработал?"; exit 1; }

# ---------- helpers ----------
log() { echo -e "\n\033[1;36m==>\033[0m $*"; }
ask() {
    local prompt=$1 default=${2:-} value
    if [ -n "$default" ]; then
        read -r -p "$prompt [$default]: " value
        echo "${value:-$default}"
    else
        read -r -p "$prompt: " value
        echo "$value"
    fi
}
ask_secret() {
    local prompt=$1 value
    read -r -s -p "$prompt: " value; echo >&2
    echo "$value"
}

# ---------- 1. Telegram ----------
log "Шаг 1: Telegram bot"
echo "Если нет бота — создай через @BotFather в Telegram, получишь токен формата 1234:ABC..."
TELEGRAM_BOT_TOKEN=$(ask_secret "Telegram bot token")
TELEGRAM_USER_ID=$(ask "Твой Telegram user ID (узнаёшь через @userinfobot)")

# Сохраним токен в secrets для shell-скриптов
echo -n "$TELEGRAM_BOT_TOKEN" > $HOME/.openclaw/secrets/telegram.token
chmod 600 $HOME/.openclaw/secrets/telegram.token

# ---------- 2. API ключи провайдеров ----------
log "Шаг 2: API ключи провайдеров. Каждый можно skip (Enter) — поставит placeholder, отредактируешь потом."
GROQ_API_KEY=$(ask "Groq API key (для voice транскрипции, https://console.groq.com)" "GROQ_PLACEHOLDER")
OPENROUTER_API_KEY=$(ask "OpenRouter API key (https://openrouter.ai)" "OPENROUTER_PLACEHOLDER")
BRAVE_API_KEY=$(ask "Brave Search API key (опц., https://brave.com/search/api/)" "BRAVE_PLACEHOLDER")
TAVILY_API_KEY=$(ask "Tavily API key (опц., https://tavily.com)" "TAVILY_PLACEHOLDER")
DEEPSEEK_KEY=$(ask "DeepSeek API key (https://platform.deepseek.com)" "DEEPSEEK_PLACEHOLDER")
MINIMAX_KEY=$(ask "MiniMax API key (формат sk-cp-... или sk-api-..., нужен API balance!)" "MINIMAX_PLACEHOLDER")

# ---------- 3. Google OAuth ----------
log "Шаг 3: Google OAuth (Gmail + Calendar + Drive)"
echo "Тебе нужен зарегистрированный OAuth Desktop Client в Google Cloud Console."
echo "Если нет — создай проект на console.cloud.google.com → APIs & Services → Credentials → OAuth Client → Desktop application → redirect_uri: http://localhost"
echo "Enable APIs: Gmail, Google Calendar, Google Drive."
GOOGLE_OAUTH_CLIENT_ID=$(ask "Google OAuth client_id (формат NNN-XXX.apps.googleusercontent.com)" "")
GOOGLE_OAUTH_CLIENT_SECRET=$(ask_secret "Google OAuth client_secret")
GOOGLE_EMAIL=$(ask "Google email (login_hint, например yourname@gmail.com)" "")

if [ -n "$GOOGLE_OAUTH_CLIENT_ID" ] && [ -n "$GOOGLE_OAUTH_CLIENT_SECRET" ]; then
    OAUTH_URL="https://accounts.google.com/o/oauth2/auth?$(python3 -c "
from urllib.parse import urlencode
print(urlencode({
    'client_id': '$GOOGLE_OAUTH_CLIENT_ID',
    'redirect_uri': 'http://localhost',
    'response_type': 'code',
    'access_type': 'offline',
    'prompt': 'consent',
    'scope': 'https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/drive.file',
    'login_hint': '$GOOGLE_EMAIL',
}))
")"
    cat <<EOF

------------------------------------------------------------
Открой URL в браузере (на своей машине), залогинься, нажми
«Дополнительно → Перейти на (небезопасно)» если предупредит,
потом «Разрешить» все scopes. Браузер редиректит на
http://localhost/?code=... → ERR_CONNECTION_REFUSED (нормально).
Скопируй ПОЛНЫЙ URL из адресной строки (Ctrl+L, Ctrl+C → через
Notepad чтобы убрать переносы строк) и вставь сюда.

URL:
$OAUTH_URL
------------------------------------------------------------
EOF
    REDIRECT_URL=$(ask "Полный redirect URL с code=...")
    CODE=$(echo "$REDIRECT_URL" | grep -oP 'code=\K[^&]+')
    if [ -z "$CODE" ]; then
        echo "ERROR: не нашёл code= в URL"; exit 1
    fi
    log "Обмениваю code на refresh_token..."
    TOKEN_RESPONSE=$(curl -sS --max-time 15 -X POST https://oauth2.googleapis.com/token \
        -d "client_id=$GOOGLE_OAUTH_CLIENT_ID" \
        -d "client_secret=$GOOGLE_OAUTH_CLIENT_SECRET" \
        -d "code=$CODE" \
        -d "redirect_uri=http://localhost" \
        -d "grant_type=authorization_code")
    GOOGLE_WORKSPACE_REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('refresh_token',''))")
    if [ -z "$GOOGLE_WORKSPACE_REFRESH_TOKEN" ]; then
        echo "ERROR при обмене:"; echo "$TOKEN_RESPONSE" | head -c 500; exit 1
    fi
    log "  ✓ refresh_token получен: ${GOOGLE_WORKSPACE_REFRESH_TOKEN:0:20}..."
else
    GOOGLE_OAUTH_CLIENT_ID=GOOGLE_PLACEHOLDER
    GOOGLE_OAUTH_CLIENT_SECRET=GOOGLE_PLACEHOLDER
    GOOGLE_WORKSPACE_REFRESH_TOKEN=GOOGLE_PLACEHOLDER
    echo "  Skipped Google OAuth — заполни плейсхолдеры в openclaw.json позже"
fi

# ---------- 3b. Yandex CalDAV (опционально) ----------
log "Шаг 3b: Yandex Calendar (опционально, для бизнес-календарей через CalDAV)"
echo "Нужен пароль приложения с id.yandex.ru/security/app-passwords → тип «Календарь»."
echo "Формат: 16 lowercase символов без пробелов (типа abcdefghijklmnop)."
echo "Если не нужно — нажми Enter."
YANDEX_EMAIL=$(ask "Yandex email (например you@yandex.ru)" "")
if [ -n "$YANDEX_EMAIL" ]; then
    YANDEX_APP_PASSWORD=$(ask_secret "Yandex app password (16 lowercase chars)")
    if [ -n "$YANDEX_APP_PASSWORD" ]; then
        log "Сохраняю Yandex CalDAV creds + проверяю подключение..."
        python3 -c "
import json, os
p = '$HOME/.openclaw/secrets/yandex-caldav.json'
json.dump({
    'url': 'https://caldav.yandex.ru/',
    'username': '$YANDEX_EMAIL',
    'password': '$YANDEX_APP_PASSWORD',
    'note': 'App password from id.yandex.ru/security/app-passwords'
}, open(p, 'w'), indent=2)
os.chmod(p, 0o600)
print(' →', p)
"
        # smoke-test
        code=$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' \
            -u "$YANDEX_EMAIL:$YANDEX_APP_PASSWORD" \
            -X PROPFIND -H 'Depth: 0' https://caldav.yandex.ru/)
        if [ "$code" = "207" ]; then
            echo "  ✓ Yandex CalDAV auth OK"
        else
            echo "  ⚠ Yandex CalDAV вернул HTTP $code (ожидался 207). Проверь email/password."
        fi
    fi
fi

# ---------- 4. Заполняем openclaw.json ----------
log "Шаг 4: Генерирую ~/.openclaw/openclaw.json"
GATEWAY_TOKEN=$(openssl rand -hex 32)
ANONYMOUS_ID=$(openssl rand -hex 16)

python3 <<PY
import json, os
with open('$DEPLOY_DIR/openclaw-template.json') as f:
    src = f.read()
subs = {
    'GATEWAY_TOKEN': '$GATEWAY_TOKEN',
    'GROQ_API_KEY': '$GROQ_API_KEY',
    'OPENROUTER_API_KEY': '$OPENROUTER_API_KEY',
    'BRAVE_API_KEY': '$BRAVE_API_KEY',
    'TAVILY_API_KEY': '$TAVILY_API_KEY',
    'GOOGLE_OAUTH_CLIENT_ID': '$GOOGLE_OAUTH_CLIENT_ID',
    'GOOGLE_OAUTH_CLIENT_SECRET': '$GOOGLE_OAUTH_CLIENT_SECRET',
    'GOOGLE_WORKSPACE_REFRESH_TOKEN': '$GOOGLE_WORKSPACE_REFRESH_TOKEN',
    'TELEGRAM_USER_ID': '$TELEGRAM_USER_ID',
    'TELEGRAM_BOT_TOKEN': '$TELEGRAM_BOT_TOKEN',
    'ANONYMOUS_ID': '$ANONYMOUS_ID',
}
for k, v in subs.items():
    src = src.replace('\${' + k + '}', v)
# убираем _comment
d = json.loads(src)
d.pop('_comment', None)
open(os.path.expanduser('~/.openclaw/openclaw.json'), 'w').write(json.dumps(d, indent=2, ensure_ascii=False))
print('  → ~/.openclaw/openclaw.json записан')
PY

# Записываем по отдельности ключи провайдеров в auth-profiles.json + models.json
log "Заполняю auth-profiles.json + models.json"
python3 <<PY
import json, os
profiles_path = os.path.expanduser('~/.openclaw/agents/main/agent/auth-profiles.json')
os.makedirs(os.path.dirname(profiles_path), exist_ok=True)
profiles = {
    "version": 1,
    "profiles": {
        "minimax:global": {"type": "api_key", "provider": "minimax", "key": "$MINIMAX_KEY"},
        "deepseek:global": {"type": "api_key", "provider": "deepseek", "key": "$DEEPSEEK_KEY"},
        "groq:global": {"type": "api_key", "provider": "groq", "key": "$GROQ_API_KEY"},
        "openrouter:global": {"type": "api_key", "provider": "openrouter", "key": "$OPENROUTER_API_KEY"},
    }
}
open(profiles_path, 'w').write(json.dumps(profiles, indent=2))
os.chmod(profiles_path, 0o600)
print('  → auth-profiles.json')

# Минимальный models.json (openclaw сам подтянет detalies при первом запуске)
models_path = os.path.expanduser('~/.openclaw/agents/main/agent/models.json')
models = {
    "providers": {
        "minimax": {
            "baseUrl": "https://api.minimax.io/anthropic",
            "api": "anthropic-messages",
            "authHeader": True,
            "apiKey": "$MINIMAX_KEY",
            "timeoutSeconds": 120
        },
        "deepseek": {
            "baseUrl": "https://api.deepseek.com",
            "api": "openai-completions",
            "apiKey": "$DEEPSEEK_KEY"
        },
        "openrouter": {
            "baseUrl": "https://openrouter.ai/api/v1",
            "api": "openai-completions",
            "apiKey": "$OPENROUTER_API_KEY"
        }
    }
}
open(models_path, 'w').write(json.dumps(models, indent=2))
os.chmod(models_path, 0o600)
print('  → models.json')
PY

# ---------- 5. Валидация ----------
log "Валидация config"
"$OPENCLAW" config validate

# ---------- 6. Crontab ----------
log "Регистрирую crontab"
(crontab -l 2>/dev/null | grep -v "openclaw/scripts/" ; cat <<'CRON'
* * * * * ~/.openclaw/scripts/transcribe-audio-watcher.sh
*/15 * * * * ~/.openclaw/scripts/permission-watchdog.sh
0 * * * * ~/.openclaw/scripts/openclaw-autocommit.sh
0 10 * * 1 ~/.openclaw/scripts/weekly-digest.sh
0 15 * * 5 ~/.openclaw/scripts/reminder-weekly-digest.sh
0 23 * * * cd ~/.openclaw && git checkout main && git merge auto/cron --squash && git commit -m "Daily Squash"
0 3 * * 0 ~/.openclaw/scripts/archive-memory.sh
0 4 * * * ~/.openclaw/scripts/media-cleanup.sh
30 6 * * 1-5 ~/.openclaw/scripts/reminder-operacionka.sh
CRON
) | sort -u | crontab -

# ---------- 7. Запуск gateway ----------
log "Стартую openclaw-gateway"
systemctl --user daemon-reload
systemctl --user enable openclaw-gateway
systemctl --user start openclaw-gateway
sleep 6
systemctl --user is-active openclaw-gateway || { echo "Gateway не стартовал. journalctl --user -u openclaw-gateway"; exit 1; }

# ---------- 8. Smoke tests ----------
log "Smoke tests"
echo "models:"; "$OPENCLAW" models status | head -5
echo
echo "sandbox:"; "$OPENCLAW" sandbox explain | grep -E "runtime|workspaceAccess|allow|deny" | head -5

if [ "$GOOGLE_WORKSPACE_REFRESH_TOKEN" != "GOOGLE_PLACEHOLDER" ]; then
    echo
    echo "Google smoke:"; ~/.openclaw/scripts/gws-cli.py gmail unread-count 2>&1 | head -3
fi

cat <<EOF

============================================================
✓ Setup завершён

Что ещё стоит сделать вручную:
  1) Codex OAuth (опционально, для gpt-5.5) через ChatGPT-Plus:
     HTTPS_PROXY=http://127.0.0.1:8118 ALL_PROXY=socks5h://127.0.0.1:9050 \\
       $OPENCLAW models auth login --provider openai-codex
  2) Добавить бота в Telegram канал как admin (если планируешь публиковать).
  3) Заполнить пустые ключи провайдеров в ~/.openclaw/openclaw.json если что-то пропускал.
  4) Адаптировать ~/.openclaw/workspace/ (SOUL.md, IDENTITY.md, USER.md) под себя.

Логи: journalctl --user -u openclaw-gateway -f
Проверки: $OPENCLAW status; $OPENCLAW doctor --deep
============================================================
EOF
