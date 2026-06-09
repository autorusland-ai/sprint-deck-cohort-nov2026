# TOOLS.md — Локальные особенности инфраструктуры

> Файл на VPS: `~/.openclaw/workspace/TOOLS.md`. Грузится в main + sub-agent сессии.
> Skills определяют **как** инструменты работают. Этот файл — **твоя конкретика** (хосты, голоса, IDs).
> Источник: блок-07-tools.md, блок-09-mcp-серверы.md.

---

## SSH

- `clawd-vps-tail` → `100.76.223.48` — продакшн VPS через Tailscale, пользователь `clawd`.

Используй `ssh clawd-vps-tail "команда"` или ключ `~/.ssh/clawd_ed25519` с `clawd@100.76.223.48`.

---

## Telegram

- **Bot token:** в `~/.openclaw/secrets/telegram.token` (не читать наружу).
- **Owner user ID:** см. `${TELEGRAM_USER_ID}` в env.
- **dmPolicy:** `allowlist` — DM принимаются только от `allowFrom`.
- **Группы:** настраиваются по `chatId` и `topicId` в `openclaw.json` → `channels.telegram.groups`.

Никогда не отправляй сообщения в группы / неизвестные DM без явного указания.

---

## Sandbox mounts (где лежит что ВНУТРИ песочницы)

В sandbox-контейнере тебе доступны два дополнительных пути (помимо workspace):

- `/emmbase/` — read-only mount всей базы знаний (`/home/clawd/emmbase/` на хосте). Используй для memory_search, чтения `/emmbase/life/прогнозирование.md`, `/emmbase/projects/...`, `/emmbase/knowledge-base/...` и т.п.
- `/emmbase/inbox/` — read-WRITE подкаталог. Сюда сохраняй ответы/артефакты, которые должен забрать Руслан (Markdown-сводки, JSON-отчёты). НЕ пиши в другие подкаталоги emmbase — туда доступ только на чтение.

Workspace бота (правила, state, sessions) монтируется отдельно — это всё в `/workspace/` и `~/.openclaw/` пути.

ВАЖНО: путь `/home/clawd/emmbase/...` внутри sandbox НЕ существует. Используй только `/emmbase/...`.

---

## Архитектура EMMBASE: все WRITE через inbox

⚠️ КРИТИЧНО (полные правила — в skill `inbox-saver`).

**Базовая идея:** бот — это диспетчер инструкций. Он сам ничего не маршрутизирует в EMMBASE, не редактирует карточки клиентов / `Tasks Board.md` / `life/`. Все команды на сохранение/изменение/удаление кладутся в `/emmbase/inbox/ГГГГ-ММ-ДД_тема.md` с YAML-разметкой (тип / относится к / дата / источник / срочность). Claude в отдельной сессии разбирает inbox и реально выполняет.

**Что бот делает САМ:**
- READ: Gmail, Google Calendar, Yandex Calendar, любые файлы `/emmbase/...` — через скрипты.
- Запись в `~/.openclaw/state/active-tasks.json` — служебный трекер.
- Транскрипция голосовых — pipeline через ffmpeg+Groq.

**Что через inbox (никогда напрямую через скрипт):**
- Создание/редактирование/удаление событий календаря (Google и Yandex).
- Отправка / черновики / ответы в Gmail.
- Обновление карточек клиентов, life, knowledge-base.
- Запись прогнозов, идей, инструкций для Claude.

Подробности — `skills/inbox-saver/SKILL.md`. Конкретные команды read-скриптов — ниже.

---

## Календари и почта — host-скрипты (НЕ MCP)

В openclaw 2026.5.19 MCP не пробрасывается в isolated session. Все интеграции с почтой/календарями — через host-скрипты + `exec`.

### Google Workspace (Gmail + Calendar + Drive)
- Аккаунт: `rusfeodor@gmail.com`
- Скрипт: `~/.openclaw/scripts/gws-cli.py`
- Команды: `gmail unread-count` | `gmail search "<q>" [--limit N]` | `gmail message <id>` | `gmail send <to> "<subj>" "<body>"` | `calendar today` | `calendar range <iso_start> <iso_end>` | `calendar add "<summary>" <iso_start> <iso_end> --description "<text>"`

### Yandex Calendar (CalDAV)
- Аккаунт: `rus-fedorov@yandex.ru`
- Скрипт: `~/.openclaw/scripts/yacal-cli.py`
- 7 календарей: Консультации Созвоны (primary), Буддийские Курсы/Поездки, График Оплат, Личное, Ремон/Перепланировка, Семья, Не забыть (todos)
- Команды: `list-calendars` | `today [--calendar X]` | `range <iso_start> <iso_end> [--calendar X]` | `add "<summary>" <iso_start> <iso_end> [--description "<text>"] [--calendar X]` | `delete <uid> [--calendar X]`
- Подробная логика выбора календаря и параметры — в skill `calendar-keeper`.

### Общее правило

- Все даты ISO 8601 с TZ `+03:00`.
- Скрипты возвращают JSON. Не дампи пользователю — извлеки нужные поля и оформи человеческим текстом.
- Перед `send`/`add`/`delete` — покажи Руслану черновик/параметры и жди явного подтверждения. Не по контексту.
- НИКОГДА не говори «MCP не подключён» / «нет доступа» — есть прямой доступ через скрипты.
- НЕ читай `~/.openclaw/workspace/ivanich_calendar.ics` — deprecated кеш.

---
## Telegram-публикация в каналы

Бот `@Ivanichsila_bot` — administrator в этих каналах с правом `can_post_messages`:

- `@investing_in_your_self` (id: `-1001326567955`, title: «Руслан | Формула роста»)

Чтобы опубликовать пост в канал, используй tool `telegram` (`channel_post`/`sendMessage` action) с `chat_id: -1001326567955`. Текст готовь по правилам `нейрорайтер-промпт.md`.

⚠️ ПУБЛИКУЙ ТОЛЬКО ПО ЯВНОЙ КОМАНДЕ РУСЛАНА (например «опубликуй», «постни», «выложи», «/publish»). Никогда не публикуй на всякий случай, по контексту, потому что мне показалось. Сомневаешься — спроси.

---

## Voice pipeline (.ogg / .amr / .3gp)

### Как это устроено

1. **`.ogg`** (стандартное Telegram voice от смартфона) — openclaw runtime **сам** транскрибирует через Groq Whisper API. Текст автоматически вставляется в диалог как inbound message. **Тебе ничего делать не надо** — просто отвечай на текст.
2. **`.amr` / `.3gp`** (записи с офисных PBX, Asterisk, IP-телефонии, старые телефоны) — Groq Whisper НЕ принимает этот формат, runtime отдаёт `HTTP 400`. Но на VPS работает **host-side cron** `transcribe-audio-watcher.sh` (запуск каждую минуту):
   - ffmpeg конвертирует `.amr` → opus 16k
   - curl к Groq Whisper Large v3
   - Результат **(а) отправляется отдельным сообщением в Telegram** с префиксом `📝 Транскрипт (.amr через ffmpeg)`
   - И **(б) кладётся в `/emmbase/inbox/ГГГГ-ММ-ДД_ЧЧММ_voice-имя.md`** с типом `голосовое` — ты можешь его читать.

### Что делать тебе как боту

- Увидел в логе/диалоге `[media-understanding] audio: failed reason=Audio transcription failed (HTTP 400)` на `audio/amr` — **не паникуй**. Watcher уже обрабатывает. Подожди 60-120 сек (длина файла + ffmpeg + Groq).
- На запрос «расшифруй то голосовое» — **сначала проверь `/emmbase/inbox/`** на свежие `*_voice-*.md` (за последние 5 минут). Если файл там — читай и используй текст.
- **НЕ запускай faster-whisper / pip install whisper / прочую локальную транскрипцию.** Это CPU-heavy и медленно, watcher работает быстрее.
- **НЕ говори «Groq API key не работает»** только потому что в твоём sandbox env переменная `GROQ_API_KEY=***`. Это **намеренное маскирование** openclaw'ом — runtime использует реальный ключ. Запусти `~/.openclaw/scripts/transcribe-audio-watcher.sh` (или подожди cron) — он читает реальный ключ из `~/.openclaw/openclaw.json` напрямую.

### Где живёт реальный ключ Groq (для справки, не для копирования)

- `~/.openclaw/openclaw.json` → `env.GROQ_API_KEY`
- `~/.openclaw/agents/main/agent/auth-profiles.json` → `profiles.groq:global.key`

Оба должны быть синхронизированы — формат `gsk_...`. Если sandbox видит у себя `***` — это OK, всё рабочее.

### Где живёт реальный путь openclaw config

`~/.openclaw/openclaw.json` (БЕЗ `/config/` префикса). Если видишь упоминание `~/.openclaw/config/openclaw.json` где-то в своих рассуждениях — это **галлюцинация**, такого пути не существует.

---

## Image generation

- **Default:** `google/gemini-2.5-flash-image` через OpenRouter — баланс цены и качества.
- **Fast/cheap:** `black-forest-labs/flux-schnell` через OpenRouter (в ~13x дешевле).
- Размер дефолтный: `1024x1024`.

Команда: `/image <prompt>` или просто «нарисуй ...» в чате.

---

## Browser (Playwright headless)

- Headless: всегда (на VPS нет display).
- Args обязательно: `--no-sandbox`, `--disable-dev-shm-usage`, `--disable-blink-features=AutomationControlled`.
- User data dir: `~/.openclaw/browser-profiles/main` — здесь живут cookies.
- SSRF защита включена (`dangerouslyAllowPrivateNetwork: false`).

Не пытайся обходить CAPTCHA. Где есть API (Twitter/LinkedIn/VK) — используй API, не браузер.

---

## MCP-серверы

Конфигурируются в `openclaw.json` → `mcp.servers`. Подтверждённые рабочие пакеты (см. блок-09 + АУДИТ):

| Server | Пакет | Зачем |
|---|---|---|
| **Playwright (web automation)** | `@playwright/mcp` (НЕ `@microsoft/mcp-server-playwright` — такого нет!) | управление браузером сверх native browser tool |
| **Tavily search** | `tavily-mcp` (через uvx) или `@mcptools/mcp-tavily` | продвинутый AI-поиск |
| **Notion** | `@notionhq/notion-mcp-server` (официальный) | работа с базами данных и страницами |
| **GitHub** | managed `https://api.githubcopilot.com/mcp/` или Docker `ghcr.io/github/github-mcp-server` | (НЕ `@modelcontextprotocol/server-github` — deprecated) |
| **Filesystem** | `@modelcontextprotocol/server-filesystem` | расширенный доступ к файлам |

Когда нужен новый MCP — спроси меня, не ставь самостоятельно.

---

## Vector memory (Qdrant + Mem0)

- **Qdrant:** Docker-контейнер, порт `6333` (REST), `6334` (gRPC). Persistent volume на 4 GB.
- **Mem0:** через npm-пакет `@mem0/openclaw-mem0` v1.0.10+ (см. блок-15).
- **8 memory tools** доступны: `memory_search`, `memory_add`, `memory_get`, `memory_list`, `memory_update`, `memory_delete`, `memory_event_list`, `memory_event_status`.

Для долгосрочных фактов используй `memory_add`, не `MEMORY.md` (тот для деклараций, а не для роста знания).

---

## Logging и debug

- Daemon logs: `journalctl --user -u openclaw -f` (на VPS).
- Trajectory bundles (для дебага): `OPENCLAW_TRAJECTORY=/tmp/traces` env var. Slash-команда `/trajectory bug-name` экспортирует bundle.
- Heartbeat/cron логи: `journalctl --user -u openclaw -g 'cron|heartbeat'`.

---

## Команды install/system (defaults)

- **Linux package manager:** `apt` (Ubuntu 24.04). Установка пакетов **только с подтверждением**.
- **Node:** Node.js 22 LTS установлен через nodesource.
- **Python:** `python3.12`, `uv` для venv (быстрее чем pip).
- **GitHub CLI:** `gh` доступен — используй `gh pr ...`, `gh issue ...` вместо чистого git.

---

## Что НЕ используем

- AWS.
- Windows / WSL — VPS на Linux.
- snap-версия Chromium — конфликт с AppArmor (см. `docs/troubleshooting.md`).

---

**Skills общие. Эти настройки — мои. Когда меняется инфраструктура (новый VPS, новый голос, новый MCP) — обновляй файл и `git commit`.**
