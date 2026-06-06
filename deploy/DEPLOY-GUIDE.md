# OpenClaw VPS Deploy Guide

Полная инструкция по развёртыванию бота-агента `@Ivanichsila_bot` на чистом VPS. Документ собран из истории работы над текущим инстансом (TimeWeb Cloud, Ubuntu 24.04 LTS, май–июнь 2026).

**Цели:**
- Поднять идентичную конфигурацию на другом VPS с минимальной ручной работой.
- Объяснить КАЖДУЮ известную ловушку, на которую я уже наступил — чтобы повторно не тратить время.

**Что в этой папке:**

```
deploy/
├── DEPLOY-GUIDE.md         ← этот файл, главный
├── bootstrap.sh            ← Шаг 1: системные пакеты + сервисы + openclaw CLI
├── configure.sh            ← Шаг 2: интерактивная настройка (OAuth, ключи, cron)
├── openclaw-template.json  ← шаблон openclaw.json с плейсхолдерами
├── systemd/                ← systemd user units (gateway, xvfb, proxy drop-in)
├── scripts/                ← все host-side helper-скрипты (gws-cli.py, cron-watchers и т.д.)
└── workspace/              ← правила бота (SOUL, TOOLS, IDENTITY, skills, шаблоны постов)
```

---

## 1. Архитектура — что мы поднимаем

| Слой | Компонент | Зачем |
|------|-----------|-------|
| **OS** | Ubuntu 24.04 LTS (Noble) | Базовая система. Тестировался только на ней. |
| **Network proxy** | `tor` + `privoxy` | OpenAI/ChatGPT/Codex блокируют RU IP. Tor → exit node вне санкций. Privoxy — HTTP-фронт для SOCKS5 tor. |
| **Container runtime** | `docker` | Sandbox-изоляция кода которое запускает openclaw |
| **Sandbox image** | `comandos-openclaw-sandbox:bookworm-slim` (локальный) | Изолированный Python окружение для агентских задач |
| **Audio tooling** | `ffmpeg` | Конвертация .amr → .ogg перед отправкой в Groq Whisper |
| **Vector store** | Qdrant (через apt или binary) на `:6333` | Mem0 long-term memory |
| **Embeddings** | Ollama + `nomic-embed-text` model на `:11434` | Локальные эмбеддинги для Mem0 (768-dim) |
| **Browser automation** | Xvfb + Chromium (через `browser-use`) | Веб-навигация для агента (отдельный MCP) |
| **Headless display** | Xvfb на `:99` | Для browser-use, иначе chrome падает |
| **Node runtime** | Node.js 24 LTS (nodesource) | OpenClaw CLI — Node-based |
| **OpenClaw CLI** | `openclaw@2026.5.19` через npm global | Сам ядро бота |
| **Python venv** | `/home/clawd/browser-env` (3.12) | MCP-серверы (`google-workspace-mcp`, `browser-use`) |
| **Cron jobs** | crontab пользователя `clawd` | Утренний прогноз, weekly analysis, audio watcher, media cleanup, reminders |

**Юзер:** всё работает под непривилегированным `clawd` (UID 1000, группы: `sudo`, `users`, `docker`, `ollama`).

**Сетевые порты (loopback):**
- `9050` — Tor SOCKS5
- `8118` — Privoxy HTTP→SOCKS
- `6333` — Qdrant HTTP API
- `11434` — Ollama HTTP API
- `18789` — OpenClaw gateway (localhost only)

Внешние порты НЕ открыты — взаимодействие только через Telegram-бота.

---

## 2. Prerequisites (на чистом VPS)

- **Hardware:** ≥4 GB RAM, ≥2 vCPU, ≥40 GB disk. На меньшем будут OOM (см. MemoryMax=2G в service unit).
- **OS:** Ubuntu 24.04 LTS, чистая.
- **Доступ:** SSH с правами sudo. Лучше уже создать пользователя `clawd` отдельно и не работать под root.
- **DNS:** работающий outbound к telegram.org, api.deepseek.com, api.minimax.io, api.groq.com, oauth2.googleapis.com (через Tor) и т.д.
- **Tor exit nodes:** Если VPS в санкционной юрисдикции (RU/CN/IR/CU/SY/KP), Tor — обязателен для OpenAI/Codex.

---

## 3. Установка — пошагово

Все шаги рассчитаны на пользователя `clawd`. Если его нет — создай (`sudo useradd -m -s /bin/bash clawd && sudo usermod -aG sudo,docker clawd`).

### Шаг 1: Bootstrap (системные пакеты, сервисы, openclaw CLI)

```bash
cd ~
git clone <your-repo-url> comandos       # или scp всю папку deploy/
cd comandos/deploy
sudo bash bootstrap.sh
```

`bootstrap.sh` ставит:
1. apt-пакеты: `tor privoxy docker.io docker-compose-plugin ffmpeg python3.12-venv git curl jq inotify-tools`
2. Node.js 24 LTS из nodesource
3. Configures privoxy → tor (правит `/etc/privoxy/config`)
4. Поднимает Tor + Privoxy + Docker + enables linger для clawd
5. Создаёт Python venv `/home/clawd/browser-env`, ставит `google-workspace-mcp`, `browser-use`
6. Ставит Ollama (curl-скрипт) + тянет `nomic-embed-text` модель
7. Ставит Qdrant (через docker или standalone binary)
8. Создаёт пустую структуру `/home/clawd/.openclaw/` с подкаталогами
9. `npm install -g openclaw@2026.5.19 @mem0/openclaw-mem0`
10. Копирует systemd units → `~/.config/systemd/user/`, `daemon-reload`, enables linger

После bootstrap.sh — gateway ещё **НЕ стартует** (нет config). Идём в шаг 2.

### Шаг 2: Configure (интерактивный — нужны OAuth-флоу + ключи)

```bash
bash configure.sh
```

`configure.sh` спросит и сделает:

1. **Telegram bot token** — создаёшь нового бота через `@BotFather` или вводишь существующий. Сохраняется в `~/.openclaw/secrets/telegram.token` (0600).
2. **Telegram user_id** — твой ID (узнаёшь через `@userinfobot`).
3. **API ключи провайдеров** (любые из):
   - DeepSeek (https://platform.deepseek.com)
   - MiniMax (https://api.minimax.io — нужен **API balance**, не Chat Plus подписка)
   - Gonka (https://gonka.ai)
   - OpenRouter (https://openrouter.ai)
   - Groq (https://console.groq.com — для voice транскрипции)
   - Brave Search (https://brave.com/search/api/)
   - Tavily (https://tavily.com)
4. **Google OAuth flow** для Gmail + Calendar + Drive — открывает браузер с auth URL, ждёт код. Подробности — раздел «Google OAuth» ниже.
5. **OpenAI Codex OAuth** — аналогично, через ChatGPT-Plus аккаунт. Опционально (можно жить без gpt-5.5).
6. **Sandbox Docker image** — собирает `comandos-openclaw-sandbox:bookworm-slim` из локального Dockerfile.
7. Финализирует `~/.openclaw/openclaw.json` из шаблона + заполненные значения.
8. Устанавливает crontab + копирует helper-скрипты в `~/.openclaw/scripts/`.
9. Стартует gateway: `systemctl --user start openclaw-gateway`.

### Шаг 3: Smoke-test

```bash
systemctl --user status openclaw-gateway
/home/clawd/.npm-global/bin/openclaw models status
/home/clawd/.npm-global/bin/openclaw sandbox explain
~/.openclaw/scripts/gws-cli.py gmail unread-count   # должен вернуть JSON, не ошибку
```

В Telegram написать боту любое сообщение — должен ответить.

---

## 4. Ключевые компоненты — что и зачем

### 4.1. Tor + Privoxy (обход RU блокировки OpenAI)

**Проблема:** OpenAI на любой запрос с RU/санкционных IP отвечает `403 unsupported_country_region_territory`. Касается всего — Codex auth, ChatGPT API, Whisper.

**Решение:** outbound через Tor. Privoxy — HTTP-прокси-фронт для Tor SOCKS5 (потому что openclaw env использует `HTTPS_PROXY=http://...` формат, а не SOCKS).

**Конфиг `/etc/privoxy/config`** (одна строка добавляется в конец):
```
forward-socks5t / 127.0.0.1:9050 .
```

**Проверка:** `curl -x http://127.0.0.1:8118 https://api.openai.com/v1/models` должен вернуть `401` (auth required, не region block).

**Применение в gateway:** systemd drop-in `~/.config/systemd/user/openclaw-gateway.service.d/proxy.conf` (см. файл) — `HTTPS_PROXY=http://127.0.0.1:8118` + `NO_PROXY` со списком всех не-OpenAI хостов (DeepSeek, MiniMax, Telegram, Groq, OpenRouter — иначе они тоже пойдут через Tor и потеряют скорость или сломаются).

⚠️ Если забыть `api.groq.com` в `NO_PROXY` — Groq отвечает 404 (Tor exit nodes отвергаются Groq), voice-транскрипция перестаёт работать. Полный NO_PROXY-лист уже в drop-in файле.

### 4.2. OpenAI Codex auth (опционально, для gpt-5.5)

**Что есть:** GPT-5.5 через ChatGPT-Plus subscription (НЕ через прямой OpenAI API key).

**Что НЕ есть:** прямой `openai/gpt-5` через ChatGPT — вернёт `400 invalid_request_error: 'gpt-5' model is not supported when using Codex with a ChatGPT account.`. Используется `openai/gpt-5.5` или другие Codex-доступные модели.

**Flow:**
```bash
HTTPS_PROXY=http://127.0.0.1:8118 ALL_PROXY=socks5h://127.0.0.1:9050 \
  /home/clawd/.npm-global/bin/openclaw models auth login --provider openai-codex
```
1. Выведет `https://auth.openai.com/oauth/authorize?...`.
2. Открыть в браузере, залогиниться в свой ChatGPT-Plus аккаунт, нажать **Authorize**.
3. Браузер редиректит на `http://localhost:1455/auth/callback?code=...` → ERR_CONNECTION_REFUSED (нормально).
4. **Скопировать полный URL из адресной строки** (Ctrl+L → Ctrl+C, **через Notepad** чтобы убрать переносы — иначе State mismatch).
5. Вставить обратно в SSH-prompt.

Refresh token сохраняется в `~/.openclaw/agents/main/agent/auth-profiles.json`, обновляется автоматически.

### 4.3a. Yandex Calendar (CalDAV) — read+write через app password

Альтернативный календарь (бизнес-консультации, бытовые) через стандартный CalDAV-протокол.

**Шаги:**
1. На id.yandex.ru → Безопасность → **Пароли приложений** → создать «Календарь» / «CalDAV». Получить 16-символьный пароль (`xxxx xxxx xxxx xxxx`).
2. Сохранить creds в `~/.openclaw/secrets/yandex-caldav.json` (chmod 600):
   ```json
   {"url": "https://caldav.yandex.ru/", "username": "you@yandex.ru", "password": "xxxxxxxxxxxxxxxx"}
   ```
3. Smoke-test:
   ```bash
   ~/.openclaw/scripts/yacal-cli.py list-calendars
   ~/.openclaw/scripts/yacal-cli.py today
   ```

⚠️ Если включена 2FA (а она обычно есть), пароль приложения — единственный путь. Если 2FA не включена — Яндекс не даст создать app password, надо сначала включить 2FA в `id.yandex.ru/security/two-factor`.

⚠️ App password не виден после закрытия окна создания. Если потерял — пересоздать.

### 4.3. Google Workspace (Gmail + Calendar + Drive)

**OAuth Client app** уже зарегистрирован в Google Cloud Console (project `ivanichclawbot`, client_id `130111462890-...`). Если хочешь свой — создай новый проект → APIs & Services → Credentials → OAuth client → **Desktop application** → redirect_uri `http://localhost`. Enable APIs: Gmail, Calendar, Drive.

**Flow получения refresh_token:**

```bash
# 1. Сгенерировать auth URL
python3 -c "
from urllib.parse import urlencode
print('https://accounts.google.com/o/oauth2/auth?' + urlencode({
    'client_id': 'YOUR_CLIENT_ID.apps.googleusercontent.com',
    'redirect_uri': 'http://localhost',
    'response_type': 'code',
    'access_type': 'offline',
    'prompt': 'consent',
    'scope': 'https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/drive.file',
    'login_hint': 'YOUR_EMAIL@gmail.com',
}))
"
# 2. Открыть в браузере, Authorize, скопировать redirect URL с code=...
# 3. Обменять code на refresh_token:
curl -X POST https://oauth2.googleapis.com/token \
  -d "client_id=YOUR_CLIENT_ID.apps.googleusercontent.com" \
  -d "client_secret=YOUR_CLIENT_SECRET" \
  -d "code=4/0AeoWuM9..." \
  -d "redirect_uri=http://localhost" \
  -d "grant_type=authorization_code"
# 4. Сохранить refresh_token в openclaw.json env.GOOGLE_WORKSPACE_REFRESH_TOKEN
```

`configure.sh` делает это интерактивно.

⚠️ Refresh_token хранится **только в env.GOOGLE_WORKSPACE_REFRESH_TOKEN** (и зеркалится в mcp.servers.google-workspace.env). При смене менять в обоих местах.

### 4.4. MCP-серверы — ловушка

**Установлены через Python venv `/home/clawd/browser-env`:**
- `google-workspace-mcp` (pip) — Gmail/Calendar/Drive/Docs/Sheets/Slides API
- `browser-use` (форк) — web automation через Playwright
- `caldav` + `icalendar` (pip) — для Yandex Calendar через `yacal-cli.py` (CalDAV-based, не MCP)

**В openclaw.json** прописаны в `mcp.servers.google-workspace` и `mcp.servers.browser-use` с env-vars (refresh_token + client_id+secret).

**Известная проблема:** MCP-tools НЕ передаются в isolated Telegram-session боту. Прямой stdio-тест к MCP-серверу работает (отдаёт 44 tools для Google Workspace), child-процесс gateway виден в `pstree`. Но бот в sandbox видит «MCP не подключён». Это архитектурное ограничение openclaw 2026.5.19.

**Обход:** host-script `~/.openclaw/scripts/gws-cli.py` — Python-обёртка над Google REST API с auto-refresh access_token из env. Бот вызывает через `exec` (этот tool разрешён в sandbox). Skills `calendar-keeper` и `mail-handler` явно говорят боту использовать gws-cli.py, не пытаться MCP.

Аналогичный обход для `.amr` audio: `transcribe-audio-watcher.sh` (cron каждую минуту) — ffmpeg → Groq Whisper → Telegram.

### 4.5. Sandbox (Docker isolation)

**Что:** каждая агентская задача исполняется в Docker-контейнере (image `comandos-openclaw-sandbox:bookworm-slim`).

**Dockerfile** (упрощённо):
```dockerfile
FROM python:3.12-slim-bookworm
# минимум — openclaw сам запускает там Python код
```

Image собирается локально:
```bash
cd ~/.openclaw/sandbox-image
docker build -t comandos-openclaw-sandbox:bookworm-slim .
```

**В `openclaw.json`** (секция `agents.defaults.sandbox`):
```json
{
  "mode": "all",
  "backend": "docker",
  "scope": "agent",
  "workspaceAccess": "rw",
  "docker": {
    "image": "comandos-openclaw-sandbox:bookworm-slim",
    "binds": [
      "/home/clawd/emmbase:/emmbase:ro",
      "/home/clawd/emmbase/inbox:/emmbase/inbox:rw"
    ],
    "dangerouslyAllowExternalBindSources": true
  }
}
```

⚠️ `dangerouslyAllowExternalBindSources: true` нужно потому что openclaw по умолчанию запрещает bind mount из путей вне `~/.openclaw/workspace`. Без этого emmbase не примонтируется.

⚠️ `workspaceAccess: "rw"` (не `"read-write"` — schema принимает только `"none"/"ro"/"rw"`).

⚠️ Юзер `clawd` ДОЛЖЕН быть в группе `docker` **до** старта `user@1000.service`. Если добавили позже — `sudo systemctl restart user@1000.service` (это пересоздаст PAM-сессию).

### 4.6. Sandbox tool policy + elevated

**Default deny** в sandbox: `telegram`, `slack`, `discord`, `whatsapp`, `signal`, `slack`, `cron`, `gateway`, `browser` и др. Для бота нужно явно разрешить.

**В `openclaw.json`:**
```json
{
  "tools": {
    "sandbox": {
      "tools": {
        "alsoAllow": ["telegram", "google-workspace", "browser-use"]
      }
    },
    "elevated": {
      "enabled": true,
      "allowFrom": {
        "telegram": ["YOUR_USER_ID"]
      }
    }
  }
}
```

`tools.elevated.allowFrom.telegram` — критично для `exec` команд из бота (включая `gws-cli.py`).

### 4.7. Workspace (правила бота)

`/home/clawd/.openclaw/workspace/` грузится в каждую сессию агента:

- **SOUL.md** — имя/характер/anti-verbosity правила
- **IDENTITY.md** — кто я (имя/аватар)
- **TOOLS.md** — описание интеграций (SSH, Telegram, Google Workspace, voice, image gen, MCP, vector memory)
- **USER.md** — кто пользователь (Руслан, профиль)
- **AGENTS.md** — внешний контекст про owner
- **HEARTBEAT.md** — правила фоновых проверок
- **BOOT.md** — bootstrap-инструкции для сессии
- **EMMBASE_OPS.md** — операции с базой знаний `~/emmbase/`
- **MEMORY.md** — долгосрочные факты
- **трекер-активных-задач.md** — pattern tracking
- **утренний-прогноз.md** — шаблон астро-прогноза
- **нейрорайтер-промпт.md** — стиль постов для @investing_in_your_self
- **skills/calendar-keeper/SKILL.md**, **skills/mail-handler/SKILL.md** — Google Workspace через gws-cli.py

Все файлы — в `deploy/workspace/`. Скопируй в `~/.openclaw/workspace/` после bootstrap.sh.

### 4.8. Cron jobs (crontab пользователя clawd)

```
* * * * * ~/.openclaw/scripts/transcribe-audio-watcher.sh
*/15 * * * * ~/.openclaw/scripts/permission-watchdog.sh
0 * * * * ~/.openclaw/scripts/openclaw-autocommit.sh
0 10 * * 1 ~/.openclaw/scripts/weekly-digest.sh
0 15 * * 5 /home/clawd/.openclaw/scripts/reminder-weekly-digest.sh
0 23 * * * cd ~/.openclaw && git checkout main && git merge auto/cron --squash && git commit -m "Daily Squash"
0 3 * * 0 ~/.openclaw/scripts/archive-memory.sh
0 4 * * * ~/.openclaw/scripts/media-cleanup.sh
30 6 * * 1-5 /home/clawd/.openclaw/scripts/reminder-operacionka.sh
```

Назначение:

- **transcribe-audio-watcher.sh** (1м): подбирает `.amr/.3gp` из `~/.openclaw/media/inbound/`, ffmpeg → opus → Groq Whisper → Telegram-сообщение пользователю. Архитектурный обход Groq's отказа на .amr.
- **media-cleanup.sh** (1д, 04:00 UTC): чистит `media/inbound` >3д, `media/transcribed` >1д, `media/transcribe-failed` >14д, `media/outbound` >3д, `media/tool-image-generation` >7д, `/tmp/openclaw` >7д. Ротирует свои же логи >5MB.
- **reminder-operacionka.sh** (Пн-Пт 09:30 МСК): «🔔 Каждый день — чат Операционка» в Telegram.
- **reminder-weekly-digest.sh** (Пт 18:00 МСК): «📋 Пятница — время подвести итоги недели».
- **weekly-digest.sh** (Пн 13:00 МСК): собирает memory за неделю, дайджест от Kimi через openrouter, дописывает в `workspace/MEMORY.md`.
- **archive-memory.sh** (Вс 06:00 МСК): архивирует старые memory.
- **openclaw-autocommit.sh** (ежечасно): автокоммит `workspace/` в git auto/cron бранч.
- **Daily Squash** (23:00 МСК): merge auto/cron → main с squash.
- **permission-watchdog.sh** (15м): проверяет права на ключевые файлы.

### 4.9. OpenClaw cron-задачи (внутри openclaw, не системный cron)

В дополнение к системному cron, у openclaw свой cron-планировщик. См. `~/.openclaw/cron/jobs.json`. Сейчас там:

- `f556c692-...` **Утренний-прогноз** — каждый день 08:00 МСК. Читает `/emmbase/life/прогнозирование.md`, делает астропрогноз через gpt-5.5, шлёт в Telegram. ⚠️ Путь к emmbase **в payload должен быть `/emmbase/...`**, не `/home/clawd/emmbase/...` — sandbox использует mount.
- `380a8653-...` **pattern-analysis-weekly** — Вс 09:00 МСК. Анализирует `active-tasks.json` за неделю, ищет повторяющиеся типы задач, шлёт отчёт.

Создание: `openclaw cron add --name X --cron "..." --tz Europe/Moscow --session isolated --announce --channel telegram --to 215087477 --model openai/gpt-5.5 --timeout-seconds 300 --message "..."`.

### 4.10. Auth-profiles (где хранятся ключи)

Ключи дублируются в нескольких местах:

1. **`~/.openclaw/openclaw.json` → `env.*`** — для CLI и плагинов чтения через env.
2. **`~/.openclaw/agents/main/agent/auth-profiles.json`** — структурированные профили (provider → key). Используется runtime'ом для inference.
3. **`~/.openclaw/agents/main/agent/models.json` → `providers.*.apiKey`** (legacy дубль) — некоторые провайдеры (minimax) читают именно отсюда, и **этот файл перевешивает auth-profiles**.

⚠️ При смене ключа MiniMax / Groq — править оба места одновременно (см. `configure.sh` `update_provider_key()`).

---

## 4.X. EMMBASE inbox-only architecture (КЛЮЧЕВОЕ архитектурное правило)

Бот **не маршрутизирует данные в базу EMMBASE сам**. При любой команде типа «сохрани X / отметь в календаре / запиши инструкцию / добавь задачу» — он **только кладёт файл в `/emmbase/inbox/ГГГГ-ММ-ДД_тема.md`** с YAML-разметкой, а Claude в отдельной сессии разбирает inbox и реально выполняет.

### Что бот делает САМ vs через inbox

| САМ (READ + служебное) | Через inbox (любые WRITE в emmbase) |
|---|---|
| READ Gmail / Calendar / EMMBASE files | Создание/редактирование/удаление событий Google и Yandex Calendar |
| Запись в `~/.openclaw/state/active-tasks.json` (служебный трекер) | Отправка / черновики / ответы Gmail |
| Транскрипция голосовых (ffmpeg+Groq) | Обновление карточек клиентов (`/emmbase/КЛИЕНТЫ/`, `КЛИЕНТЫ-АН/`, `life/`) |
| Ответы в Telegram-чате | Изменение `Tasks Board.md`, `MISSION_CONTROL.md`, `LIFE_CONTROL.md` |
| Чтение workspace правил | Запись прогнозов / идей / решений / промтов |

### Шаблон файла в `/emmbase/inbox/`

```
# Тип: [задача / лид / обновление-клиента / идея / решение / голосовое / промт / личное / контент / прогноз / инструкция]
# Относится к: [клиент: Имя / проект: название / личное: сфера / бизнес / нет привязки]
# Дата: ГГГГ-ММ-ДД ЧЧ:ММ
# Источник: бот
# Срочность: [🔴 срочно / 🟡 обычно / 🟢 не срочно]

[тело]
```

### Сверка календарей с Tasks Board.md (обязательная)

При ЛЮБОМ вопросе про встречи/даты/расписание `calendar-keeper` skill заставляет бота параллельно с чтением календаря (Google + Yandex) **читать `/emmbase/Tasks Board.md`** (секция «📅 Календарь») и сверять поля:
- дата (число + месяц)
- день недели (если указан в Tasks Board — должен совпадать с фактическим)
- время
- клиент/компания

При расхождении — бот спрашивает пользователя, какое значение правильно, и кладёт в inbox инструкцию для Claude с описанием конкретного расхождения и решения.

### Где это правило прописано

- `workspace/SOUL.md` — критический блок до Anti-verbosity (грузится во все сессии).
- `workspace/skills/inbox-saver/SKILL.md` — полный регламент, шаблоны, ❌-список путей.
- `workspace/skills/calendar-keeper/SKILL.md` — WRITE команды через inbox + сверка с Tasks Board.
- `workspace/skills/mail-handler/SKILL.md` — WRITE через inbox.
- `workspace/TOOLS.md` — сводная секция «Архитектура EMMBASE» как ссылка для бота.

### Что НЕ делать (при адаптации под другого пользователя)

- Не удалять ❌-список путей в skills (`КЛИЕНТЫ/`, `life/`, `knowledge-base/`, `WIKI/`, `agents/`, `content/`, `cowork_outputs/`, `RAW/`).
- Не разрешать боту прямую запись в `Tasks Board.md` / `MISSION_CONTROL.md` / `LIFE_CONTROL.md`.
- Не убирать обязательную сверку с Tasks Board в calendar-keeper — иначе бот будет создавать события календаря в обход планёрки.

---

## 5. Известные ловушки (повторно не наступать)

| Симптом | Причина | Лекарство |
|---|---|---|
| Бот: «Something went wrong» на каждый запрос | docker группа не в живом процессе openclaw-gateway (юзера добавили в группу после старта user manager) | `sudo systemctl restart user@1000.service` (linger=yes сам восстановит сервисы) |
| `media-understanding: HTTP 403` на voice | `api.groq.com` не в `NO_PROXY`, Tor exit ноды отвергаются Groq | Добавить в `NO_PROXY` в systemd drop-in |
| `media-understanding: HTTP 401` на voice | В `auth-profiles.json` другой Groq ключ чем в `env` | Синхронизировать ключи между env+auth-profiles |
| `media-understanding: HTTP 400` на .amr | Groq Whisper не принимает .amr формат, ffmpeg pre-process не встроен | `transcribe-audio-watcher.sh` (host cron) — ffmpeg + curl напрямую |
| MiniMax: `insufficient balance (1008)` несмотря на оплату | Куплена Chat Plus subscription, она не пополняет API balance | Top-up именно API balance, либо ключ от другого тарифа (формат `sk-cp-...` вместо `sk-api-1...`) |
| `openai/gpt-5: 400 invalid_request_error` | ChatGPT-Plus Codex не даёт `gpt-5` (только `gpt-5.5`) | Primary должен быть `openai/gpt-5.5` |
| Google OAuth: `Token has been expired or revoked` | refresh_token истёк (обычно через несколько месяцев неиспользования) | Заново OAuth flow, обновить env.GOOGLE_WORKSPACE_REFRESH_TOKEN |
| OAuth: State mismatch | Браузер на странице ошибки `localhost` показывает URL с переносами, при copy-paste обрезается state | Копировать ТОЛЬКО из адресной строки (Ctrl+L → Ctrl+C), пропускать через Notepad для проверки целостности |
| Codex OAuth: `unsupported_region` | OAuth token exchange шёл напрямую (без прокси) | `HTTPS_PROXY=http://127.0.0.1:8118` перед командой |
| Бот: «MCP не подключён» при наличии всего настроенного | MCP не пробрасываются в isolated Telegram-session (openclaw limitation) | Host-script `gws-cli.py` через `exec` + явное правило в TOOLS.md «не говорить MCP не подключён» |
| Залипший контекст бота («MCP не работает» повторяется) | Conversation history в Telegram сессии содержит старые ответы бота | Пользователь делает `/new` в Telegram — пустая сессия |
| Бот тратит ~1 мин на простой запрос | Cold start sandbox + tavily MCP fail (5-7 сек) + mem0 recall (15 memories) | Удалить сломанный MCP, уменьшить `mem0.recall.tokenBudget` |
| `OAuth: redirect_uri_mismatch` | OAuth Client конфиг в Google Cloud имеет другой redirect_uri чем в запросе | Сверить с `client_secret_*.json` поле `redirect_uris` — обычно `http://localhost` для Desktop client'ов |

---

## 6. Recovery — что сломалось, как чинить

### Бот в Telegram отвечает «Something went wrong»

```bash
ssh clawd@VPS
journalctl --user -u openclaw-gateway --since "10 min ago" | grep -iE "error|fail" | tail -20
```

Типичные причины:
1. **`Failed to inspect sandbox image: permission denied`** → юзер не в группе docker, см. таблицу выше.
2. **`invalid_grant`** на Google/Codex → refresh_token истёк, перепройти OAuth.
3. **`insufficient balance`** → нет денег у провайдера, проверить какой именно (`provider=...` в логе fallback-decision).
4. **`unsupported_country_region_territory`** → прокси (Tor) сломался / `sudo systemctl restart tor`.

### Утренний прогноз не пришёл в 08:00 МСК

```bash
ssh clawd@VPS
/home/clawd/.npm-global/bin/openclaw cron runs --id f556c692-5681-4661-8aa0-567c2417fd4d --limit 3
```

В `lastError` ищи строку. Запуск вручную:
```bash
/home/clawd/.npm-global/bin/openclaw cron run f556c692-5681-4661-8aa0-567c2417fd4d
```

### Voice не транскрибируются

```bash
tail -50 ~/.openclaw/scripts/transcribe-audio.log
# проверить Groq ключ (env + auth-profile должны совпадать)
curl -H "Authorization: Bearer $GROQ_KEY" https://api.groq.com/openai/v1/models | head -c 200
# должно вернуть JSON со списком моделей. Если 401 — ключ невалиден. Если 403/404 — прокси проблема.
```

### Gmail/Calendar — бот говорит «MCP не подключён»

1. Прямой тест host-скрипта: `~/.openclaw/scripts/gws-cli.py gmail unread-count`. Если работает — проблема в боте.
2. В Telegram — `/new` (свежая session).
3. Если всё равно — `tools.elevated.allowFrom.telegram` должен содержать user_id; `tools.sandbox.tools.alsoAllow` — содержать `google-workspace`.
4. Перезапуск + recreate: `systemctl --user restart openclaw-gateway && openclaw sandbox recreate --all --force`.

### refresh_token Google истёк

Запустить блок «Google OAuth flow» из раздела 4.3. Обменять code → обновить `env.GOOGLE_WORKSPACE_REFRESH_TOKEN` в `openclaw.json` + restart gateway + recreate sandbox.

---

## 7. История изменений (что было сделано)

См. `WORK-HISTORY.md` в корне (`c:\PROJECTS\COMANDOS\`). Кратко по сессиям:

- **2026-05-29..30** (Codex auto-session): включил sandbox с docker — сломалась группа.
- **2026-05-30 вечер**: docker group fix, MiniMax key + cooldown, Codex re-auth через Tor (gpt-5.5), workspaceAccess: rw, прокси-env для gateway service, recovery-документ.
- **2026-05-31 утро**: cron утреннего прогноза, primary deepseek+gpt-5.5 fallback, sandbox bind emmbase, MiniMax key #2 (Chat Plus vs API balance), trackpattern weekly cron, sandbox-mounts в TOOLS.md.
- **2026-05-31 день**: voice транскрипция (`api.groq.com` в NO_PROXY + sync Groq key), AMR cron-watcher, media-cleanup, Telegram channel publish, VC.RU удалён.
- **2026-06-01 утро**: Google OAuth re-auth (rusfeodor@gmail.com), MCP не проходит в isolated session → host-script gws-cli.py, MiniMax primary с новым `sk-cp-...` ключом.

---

## 8. Дальнейшие шаги (что НЕ автоматизируется)

Эти задачи требуют ручного действия каждый раз:

1. **Telegram bot setup** — создание бота через @BotFather (нельзя автоматизировать).
2. **OAuth flows** (Google, Codex) — браузерный шаг с подтверждением, нельзя headless.
3. **API top-ups** — пополнение балансов у провайдеров.
4. **Domain-specific workspace** — IDENTITY/SOUL/USER/EMMBASE_OPS, нужно адаптировать под конкретного пользователя.
5. **Telegram channel publish** — бот должен быть admin в канале (ручная настройка через Telegram UI).

Всё остальное автоматизируется `bootstrap.sh` + `configure.sh`.

---

**Поддержка:**
- Логи: `journalctl --user -u openclaw-gateway --since "1 hour ago"`
- Состояние: `openclaw status` или `openclaw doctor --deep`
- Recovery памятки: `c:\PROJECTS\COMANDOS\WORK-SUMMARY-2026-05-30.md` и память Claude в `C:\Users\rus-f\.claude\projects\c--PROJECTS-COMANDOS\memory\`
