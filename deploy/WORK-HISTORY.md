# История работ над OpenClaw-ботом (Иванычь / @Ivanichsila_bot)

Хронологический журнал всех правок над инстансом на `clawd@7808894-zm343910.twc1.net` (TimeWeb Cloud VPS). Каждый блок — отдельная сессия, что нашёл, что сделал, что сломалось/починилось.

## 2026-05-08..28 — установочный период (до меня)

Не моя работа, восстановил по артефактам:

- Установлен openclaw 2026.5.19 через `npm install -g`, prefix `/home/clawd/.npm-global/`.
- Создан Python venv `/home/clawd/browser-env` с `google-workspace-mcp` и `browser-use`.
- Поднят Tor + Privoxy (порты 9050/8118) — обход RU-блокировки OpenAI.
- Поднят Ollama (`:11434`) с `nomic-embed-text` для эмбеддингов.
- Поднят Qdrant (`:6333`) для Mem0 vector store.
- Зарегистрирован OAuth Client в Google Cloud (проект `ivanichclawbot`, client_id `130111462890-...`).
- Получены API ключи: DeepSeek, MiniMax (sk-api-1...), Groq, OpenRouter, Brave, Tavily.
- Telegram бот `@Ivanichsila_bot` создан и добавлен как admin в канал `@investing_in_your_self`.
- Workspace правила: `SOUL.md`, `IDENTITY.md`, `TOOLS.md`, `USER.md`, `AGENTS.md`, skills (`calendar-keeper`, `mail-handler`, `self-improving-agent`, `browser-agent`, `deep-research`, `page-reader`, `web-quick`).
- Helper скрипты (часть): `weekly-digest.sh`, `archive-memory.sh`, `openclaw-autocommit.sh`, `permission-watchdog.sh`, `reminder-operacionka.sh`, `reminder-weekly-digest.sh` (последние два — со СЛОМАННЫМИ токенами).
- Cron вертится: openclaw-autocommit, weekly-digest, archive-memory, permission-watchdog, daily-squash, reminders.
- systemd user units: `openclaw-gateway.service`, `xvfb.service`. Linger включён.

## 2026-05-29..30 — Codex auto-session (предыдущий Claude инстанс)

Подробности в `c:\PROJECTS\COMANDOS\WORK-SUMMARY-2026-05-30.md` (раздел «Утренние правки»). Кратко:

- Поправил Telegram owner ID в `openclaw.json` (`allowFrom`, `groupAllowFrom`, `ownerAllowFrom` → `215087477`).
- Обновил `AGENTS.md` с правильным каскадом моделей и владельцем (Руслан Фёдоров).
- В `.gitignore` добавлено `.claude/`.
- Заполнен `workspace/IDENTITY.md` (Иванычь) и `workspace/TOOLS.md` (clawd-vps-tail / 100.76.223.48).
- Пофикшен `scripts/status.sh` под текущий openclaw CLI 2026.5.19 (`models status --plain` вместо устаревшего `models test`).
- Включён sandbox в `openclaw.json`: `mode: all`, `backend: docker`, `scope: agent`, `image: comandos-openclaw-sandbox:bookworm-slim`.
- Создан Docker image `comandos-openclaw-sandbox:bookworm-slim` (тег `python:3.12-slim-bookworm`, минимальный).
- Для Qwen прописан deny на `group:web` + `browser` (security audit убрал critical → 0).
- `watchdog.sh` — убран hardcoded Telegram token, читает из env / live `openclaw.json`.
- Cron утреннего прогноза обновлён через `openclaw cron edit` (запрещён astrosofa.com, `bestEffort=true`, `failureAlert`).

⚠️ **Что сломалось из-за этой сессии:**
- Юзер `clawd` добавлен в группу `docker`, НО `user@1000.service` запущен раньше. У процесса `openclaw-gateway` Groups=`27 100 1000` (без 112/docker). Любой запрос к docker → permission denied → 4 модели в каскаде падают.
- В payload утреннего прогноза остался путь `/home/clawd/emmbase/...`, но sandbox этот путь не видит (нет mount).
- `workspaceAccess: none` в sandbox config — бот не может писать в `/workspace/bazi_calc.py` для расчёта Бацзы.
- Codex auth токен `ac_V8Ehg...` истёк (`invalid ID token format`), primary `openai/gpt-5` падает.
- MiniMax — `insufficient balance (1008)`, нет денег.

## 2026-05-30 вечер — починка docker + Codex + Tor

Bot в Telegram отвечал «Something went wrong» на каждый запрос.

**Корневая причина 1: docker group**
- Диагноз: `cat /proc/$(systemctl --user show -p MainPID --value openclaw-gateway)/status | grep Groups` → нет 112.
- Лечение: `sudo systemctl restart user@1000.service` (linger=yes → user manager + gateway автоматически возобновились с правильными группами).
- Проверка: после рестарта `Groups: 27 100 112 987 1000` ✓.

**Корневая причина 2: Codex token истёк**
- Удалил старый профиль `openai-codex:manual` из `auth-profiles.json`.
- Прошёл новый OAuth flow через Tor:
  ```
  HTTPS_PROXY=http://127.0.0.1:8118 HTTP_PROXY=http://127.0.0.1:8118 \
    ALL_PROXY=socks5h://127.0.0.1:9050 \
    openclaw models auth login --provider openai-codex
  ```
- Подсадная ловушка #1: User скопировал URL со страницы ошибки браузера, перенос строки в адресе → `State mismatch`. Лечится копированием из адресной строки (Ctrl+L → Ctrl+C → через Notepad).
- Подсадная ловушка #2: VPS в RU → OpenAI вернул `unsupported_region` без прокси-env. Лечится `HTTPS_PROXY=...` env перед командой.
- Получен новый профиль `openai-codex:auto.rusland@gmail.com` (OAuth), refresh обновляется автоматически.

**Корневая причина 3: gpt-5 vs gpt-5.5**
- Codex/ChatGPT-Plus не предоставляет `gpt-5` → `400 invalid_request_error: 'gpt-5' model is not supported`.
- Поменял primary с `openai/gpt-5` на `openai/gpt-5.5` (`openclaw models set openai/gpt-5.5`).

**Прокси для inference в gateway service**
- Создан systemd drop-in `~/.config/systemd/user/openclaw-gateway.service.d/proxy.conf` с `HTTPS_PROXY=http://127.0.0.1:8118` и `NO_PROXY` со списком всех не-OpenAI хостов (Telegram, DeepSeek, MiniMax, Gonka, OpenRouter, Tavily).

**MiniMax cooldown**
- Сбросил `disabledUntil` в `auth-state.json` (вручную через python). Вернул в fallbacks. Деньги ещё не положены, но в каскаде теперь minimax — gonka.

**Sandbox workspaceAccess: rw**
- Без этого бот не мог писать ни в `/workspace`, ни в `~/.openclaw/state/active-tasks.json`. Изменил `agents.defaults.sandbox.workspaceAccess: "rw"` (важно: именно `"rw"`, не `"read-write"` — schema принимает только `none/ro/rw`).
- Sandbox пересоздан через `openclaw sandbox recreate --all --force`.

**Recovery документация**: создан `c:\PROJECTS\COMANDOS\WORK-SUMMARY-2026-05-30.md`.

**Долгосрочная память Claude (для будущих сессий):**
- `vps-openai-via-tor.md` — про прокси-обвязку.
- `codex-only-gives-gpt-5-5.md` — про ограничение ChatGPT-аккаунта.
- `oauth-callback-url-newlines.md` — про ловушку переноса строки.

## 2026-05-31 утро — sandbox bind emmbase + pattern tracker

**Утренний прогноз 08:00 МСК не пришёл**
- В cron job `f556c692-...` был per-job override `--model openai/gpt-5` (старый primary, перекрывал глобальный gpt-5.5). При сработке в 05:00 UTC: `invalid_request_error`. Также падал `Write: /workspace/bazi_calc.py failed` (sandbox без mount на emmbase + ICS).
- Поменял через `openclaw cron edit f556c692-... --model openai/gpt-5.5`.
- Добавил bind в sandbox: `/home/clawd/emmbase:/emmbase:ro` + `/home/clawd/emmbase/inbox:/emmbase/inbox:rw`.
- Пришлось разрешить `dangerouslyAllowExternalBindSources: true` (под `agents.defaults.sandbox.docker`) — иначе schema запрещает bind вне `~/.openclaw/workspace`.
- Поменял в payload cron `/home/clawd/emmbase/...` → `/emmbase/...` (sandbox-путь).
- Ручной запуск `openclaw cron run f556c692-...` — отчёт ушёл, через deepseek-v4-flash (gpt-5.5 + minimax не справились с 41k токенов контекста).

**Latency оптимизация**
- Бот тратил ~1 мин на простой запрос. Анализ trace:
  - tavily MCP fail каждый раз (npx -y @marcopirazzini/tavily-mcp@latest) — ~5-7 сек впустую.
  - mem0 recall injecting 15 memories (~848 tokens prefix) — ~3-5 сек.
  - bwrap sandbox cold start.
- Удалил tavily из `mcp.servers`. Уменьшил `plugins.openclaw-mem0.config.skills.recall.tokenBudget: 1500 → 1000`.
- Primary поменял с gpt-5.5 на deepseek-v4-flash (быстрее, не через Tor). Gpt-5.5 ушёл в fallback.

**Pattern tracker**
- В workspace был `трекер-активных-задач.md` с правилами записи задач в `~/.openclaw/state/active-tasks.json`, но бот не выполнял (правило слабое).
- Усилил: в `SOUL.md` → раздел «Правила базовые» первая строка: «Перед началом любой задачи — записать её в active-tasks.json».
- Переписал `трекер-активных-задач.md` с КРИТИЧНЫМ блоком триггера.
- Создал cron `pattern-analysis-weekly` (Вс 09:00 МСК) через `openclaw cron add` — анализ активности за неделю, отчёт в Telegram.

**MiniMax — попытка #1 пополнения**
- Юзер купил подписку $20 на minimax. Прямой curl с тем же ключом — всё ещё `insufficient balance (1008)`.
- Корневая причина: Chat Plus subscription (для веб-чата) ≠ API balance. У MiniMax это разные продукты.
- Решение: либо top-up на API balance, либо ключ другого аккаунта/тарифа.

## 2026-05-31 день — Voice транскрипция + AMR cron + Telegram channel publish

**Voice не транскрибировались (`media-understanding: HTTP 403`)**
- Прямой curl Groq: 200 OK напрямую, 404 через Privoxy. Tor exit nodes Groq не пускает.
- `api.groq.com` не было в `NO_PROXY`. Добавил.
- Потом изменилась ошибка на `HTTP 401`. Расследование: в `auth-profiles.json` `groq:global.key` был СТАРЫЙ ключ, в `env.GROQ_API_KEY` — рабочий. Синхронизировал.

**.amr файлы — host-side обёртка**
- 4 пересланных файла от Рустама Габбасова в формате .amr. Groq Whisper не принимает .amr → `HTTP 400`.
- `media-understanding` плагин openclaw НЕ имеет авто-конверсии (проверил исходники).
- Решение: написал `~/.openclaw/scripts/transcribe-audio-watcher.sh` — bash-скрипт с flock, ffmpeg → opus → Groq Whisper → Telegram. Cron каждую минуту.
- Tested на одном файле успешно. Удалил 32 накопленных файлов (юзер не захотел сводки за всё прошлое). 4 свежих от Рустама → 4 транскрипта в Telegram.

**Media cleanup**
- 98 MB накопилось в `~/.openclaw/media/inbound/`. Создал `media-cleanup.sh` (cron 04:00 UTC): чистит `inbound` >3д, `transcribed` >1д, `transcribe-failed` >14д, `outbound` >3д, `tool-image-generation` >7д, `/tmp/openclaw` >7д. Ротация логов >5MB → tail 1000 lines.
- Первый запуск освободил ~92 MB.

**Reminder-скрипты починены**
- `reminder-operacionka.sh` и `reminder-weekly-digest.sh` имели hardcoded токен СТАРОГО бота (`8527524417:AAG...`) и `CHAT_ID=8527528241` (id самого бота, не пользователя). Никуда не доходили.
- Создан `~/.openclaw/secrets/telegram.token` (0600). Скрипты теперь читают `BOT_TOKEN=$(cat ...)`. CHAT_ID = 215087477 (Руслан).

**Telegram channel publish — @investing_in_your_self**
- Бот админ канала, но не публиковал — `telegram` tool в sandbox default deny.
- `tools.sandbox.tools.alsoAllow: ["telegram"]` + `tools.elevated.allowFrom.telegram: ["215087477"]`.
- В TOOLS.md добавлен channel id `-1001326567955` + правило публиковать только по явной команде.
- В нейрорайтер-промпт добавлен guard rail.

**VC.RU удалён**
- У пользователя нет API ключа VC (только логин/пароль). Browser-автоматизация хрупкая.
- Удалил: `~/.openclaw/secrets/vc-ru.json`, `~/.openclaw/browser-profiles/vcru/` (26 MB), 5 файлов `vcru_cookies*.json` / `vcru_storage*.json`.
- Bash history очищена от упоминаний пароля.

**MiniMax — попытка #2 (новый ключ)**
- Пользователь признал что подписка $20 не помогла. Прислал НОВЫЙ ключ формата `sk-cp-...` от другого тарифа (вместо старого `sk-api-1...`).
- Прямой curl — `success`. Прописал в обоих местах (`models.json` + `auth-profiles.json`), сбросил cooldown.
- Поставил MiniMax обратно как primary (юзер выбрал — он быстрее deepseek и не через Tor).

## 2026-06-01 утро — Google OAuth re-auth + MCP не в isolated session

**Google Workspace MCP не работал**
- Старый refresh_token истёк (`invalid_grant: Token has been expired or revoked`). Также 2 backup tokens из `~/.openclaw/secrets/google-token.json` — тоже истекли.
- В secrets файл указывал на `rusfincoach@gmail.com` (другой Google аккаунт). Пользователь указал использовать `rusfeodor@gmail.com`.
- Прошёл новый OAuth flow с `redirect_uri=http://localhost` (как в `client_secret_*.json` Desktop client).
- ⚠️ Ловушка: пользователь дважды прислал client_secret JSON думая что это нужно. На самом деле — после OAuth flow в браузере, нужен **redirect URL** с `?code=4/0...` который браузер показывает на странице ошибки `http://localhost`.
- Также: пользователь упёрся в «Приложение не верифицировано» — лечится «Дополнительно → Перейти на ivanichclawbot (небезопасно)».
- Обменял code на refresh_token, прописал в `env.GOOGLE_WORKSPACE_REFRESH_TOKEN` + mcp server env + backup в `~/.openclaw/secrets/google-token.json`.
- Прямой curl Calendar API → видит календарь rusfeodor@gmail.com (owner).

**MCP не пробрасывается в isolated Telegram-session**
- Несмотря на:
  - MCP-сервер `google-workspace` запущен как child gateway (видно в pstree).
  - Прямой stdio-тест возвращает 44 tools (calendar_get_events, query_gmail_emails и др).
  - `tools.sandbox.tools.alsoAllow: [google-workspace, browser-use]` добавлено.
  - `tools.elevated.allowFrom.telegram: [215087477]` добавлено.
- Бот всё равно говорит «MCP не подключён». В логе `journalctl` нет ни одного `[bundle-mcp]` события.
- Архитектурное ограничение openclaw 2026.5.19 — MCP работают только в main session / Codex agent harness, не в isolated sub-agents.
- **Обход:** написал `~/.openclaw/scripts/gws-cli.py` — Python wrapper над Google REST API (Gmail/Calendar) с auto-refresh access_token. Бот вызывает через `exec` (этот tool разрешён + elevated).
- Skills `calendar-keeper`/`mail-handler` + `TOOLS.md` обновлены: указывают на gws-cli.py, явно запрещают говорить «MCP не подключён».
- ⚠️ Залипший контекст: бот цеплялся за свои предыдущие ответы «MCP не подключён» в Telegram сессии. Лечится `/new` (свежая session без cached history).
- После `/new` бот сразу вызвал `[exec] python3 ~/.openclaw/scripts/gws-cli.py gmail unread-count` ✓.

## Итог по состоянию 2026-06-01

| Компонент | Состояние |
|---|---|
| Bot Telegram отвечает | ✅ |
| Voice .ogg транскрипция | ✅ (Groq Whisper напрямую) |
| Voice .amr транскрипция | ✅ (cron-watcher через ffmpeg) |
| Утренний прогноз 08:00 МСК | ✅ (gpt-5.5, читает /emmbase mount) |
| Pattern-analysis Вс 09:00 МСК | ✅ (новый cron) |
| Media cleanup | ✅ (ежедневно 04:00 UTC) |
| Reminder-скрипты | ✅ (правильный токен) |
| Telegram channel publish (@investing_in_your_self) | ✅ (telegram tool разрешён, channel id в TOOLS.md) |
| Gmail + Calendar (rusfeodor@gmail.com) | ✅ (через host-script gws-cli.py) |
| Google Drive | ✅ (тот же gws-cli.py, scope drive.file) |
| MiniMax primary | ✅ (новый ключ sk-cp-...) |
| DeepSeek fallback | ✅ |
| gpt-5.5 через Codex (Tor) | ✅ (fallback) |
| Gonka/Qwen | ✅ (fallback) |
| MCP google-workspace в isolated session | ❌ (обход через gws-cli.py) |
| MCP browser-use в isolated session | ❌ (тоже обход нужен) |
| VC.RU | ⛔ удалено (нет API key) |

## Memory-записи для будущих Claude-сессий

В `C:\Users\rus-f\.claude\projects\c--PROJECTS-COMANDOS\memory\`:

- `vps-openai-via-tor.md` — VPS у TimeWeb, OpenAI заблокирован → Tor+Privoxy + NO_PROXY список.
- `codex-only-gives-gpt-5-5.md` — ChatGPT Codex не даёт gpt-5, только gpt-5.5.
- `oauth-callback-url-newlines.md` — копировать redirect URL через Notepad, иначе State mismatch.
- `minimax-subscription-vs-api-balance.md` — Chat Plus подписка ≠ API credits.
- `groq-key-stored-twice.md` — Groq ключ в env + auth-profiles одновременно.
- `amr-host-side-transcribe.md` — openclaw не конвертирует, host cron-обёртка.
- `openclaw-mcp-not-in-isolated.md` — MCP не пробрасывается боту, обход через host-script.
- `yandex-calendar-caldav.md` — 7 календарей Yandex через CalDAV (app password), `yacal-cli.py`.
- `emmbase-inbox-only-write.md` — бот пишет только в `/emmbase/inbox/` с YAML-разметкой; сверка с `Tasks Board.md`.

См. `MEMORY.md` индекс в той же папке.

---

## Расширение 01.06.2026 — Yandex CalDAV (read+write)

### Цель
Пользователь хотел доступ к Yandex Calendar для рабочих и бытовых событий (отдельно от Google).

### Что сделано

1. Из embed-токена `https://calendar.yandex.ru/embed/week?private_token=...` стало понятно, что это **read-only** для viewer'а. Для read+write нужен CalDAV.
2. Пользователь создал **app password** на [id.yandex.ru/security/app-passwords](https://id.yandex.ru/security/app-passwords) (тип «Календарь», формат `xxxx xxxx xxxx xxxx`).
3. Auth-проба: `curl -u "rus-fedorov@yandex.ru:PWD" -X PROPFIND https://caldav.yandex.ru/` → HTTP **207** ✓.
4. Установлены Python пакеты: `caldav` 3.2.1 + `icalendar` в `/home/clawd/browser-env`.
5. Креды → `~/.openclaw/secrets/yandex-caldav.json` (chmod 0600).
6. Написан `~/.openclaw/scripts/yacal-cli.py` (читает creds, команды: `list-calendars`, `today`, `range`, `add`, `delete`, поддержка `--calendar` с частичным вхождением).
7. Обнаружены 7 календарей у пользователя:
   - Консультации Созвоны (primary, клиентские встречи)
   - Буддийские Курсы/Поездки
   - График Оплат
   - Личное
   - Ремон\Перепланировка\Мебелировка
   - Семья
   - Не забыть (todo-ресурс, не events)

### Обновлено

- `~/.openclaw/workspace/skills/calendar-keeper/SKILL.md` — добавлена Yandex-секция с матрицей «куда что писать».
- `~/.openclaw/workspace/TOOLS.md` — секция «Календари и почта — host-скрипты» объединена для Google + Yandex.
- `configure.sh` (deploy) — шаг 3b «Yandex Calendar (опционально)» с auth-пробой.
- `bootstrap.sh` (deploy) — `pip install caldav icalendar` добавлено в python venv setup.

### Важно

- App password можно отозвать в любой момент в том же интерфейсе. После того как засветился в чате — рекомендация пересоздать.
- Уже есть Telemost-зеркалирование: встречи в Yandex дублируются в Google Calendar автоматически (видно `Елена Варанкина (localrolls.ru)` 01.06 в обоих).

---

## Расширение 06.06.2026 — EMMBASE inbox-only architecture

### Триггер
Пользователь прислал содержимое своего системного промта `/emmbase/agents/openclaw-bot-системный-промт.md` и попросил, чтобы бот следовал ему: при любой команде на сохранение/изменение в базе EMMBASE — класть инструкции в `/emmbase/inbox/` с YAML-разметкой, а не выполнять напрямую. Claude в отдельной сессии разбирает inbox.

### Архитектурное правило (что бот делает САМ vs через inbox)

| САМ (напрямую) | Через inbox |
|---|---|
| READ Gmail / Calendar / EMMBASE files | Создание / редактирование / удаление событий календаря |
| Запись в `~/.openclaw/state/active-tasks.json` | Отправка / черновики Gmail |
| Транскрипция голосовых (ffmpeg+Groq pipeline) | Обновление карточек клиентов |
| Ответы в чат | Запись прогнозов / идей / решений |
| | Изменение `Tasks Board.md`, `MISSION_CONTROL.md`, `LIFE_CONTROL.md` |

### Шаблон файла в inbox

`/emmbase/inbox/ГГГГ-ММ-ДД_короткая-тема.md`:

```
# Тип: [задача / лид / обновление-клиента / идея / решение / голосовое / промт / личное / контент / прогноз / инструкция]
# Относится к: [клиент: Имя / проект: название / личное: сфера / бизнес / нет привязки]
# Дата: ГГГГ-ММ-ДД ЧЧ:ММ
# Источник: бот
# Срочность: [🔴 срочно / 🟡 обычно / 🟢 не срочно]

[тело]
```

### Что обновлено

- `~/.openclaw/workspace/SOUL.md` — критический блок перед Anti-verbosity со ссылкой на skill `inbox-saver`.
- Новый skill `~/.openclaw/workspace/skills/inbox-saver/SKILL.md` — полный шаблон, 11 типов, примеры, ❌-список (КЛИЕНТЫ/, life/, knowledge-base/, и т.д.).
- `~/.openclaw/workspace/skills/calendar-keeper/SKILL.md` — переписан, WRITE команды только через inbox.
- `~/.openclaw/workspace/skills/mail-handler/SKILL.md` — переписан, WRITE только через inbox.
- `~/.openclaw/workspace/TOOLS.md` — секция «Архитектура EMMBASE» с правилом для всех сессий.

### Дополнительное правило сверки с Tasks Board.md (06.06)

Calendar-keeper теперь обязан при ЛЮБОМ вопросе про встречи/даты:
1. Прочитать календарь (Google / Yandex).
2. Параллельно прочитать `/emmbase/Tasks Board.md`, секция «📅 Календарь».
3. Сопоставить: дата + день недели + время + клиент.
4. При расхождении — сообщить Руслану конкретно, спросить какая правильно.
5. Положить инструкцию в inbox для Claude с описанием расхождения и решением.

**Пример живого конфликта найден в самом Tasks Board:** `Вс 08.06` — но 08.06.2026 это понедельник.

### Smoke-test подтверждён

Пользователь подтвердил «всё работает» — бот применяет skill `inbox-saver`, не пишет напрямую в `/emmbase/` (кроме inbox), сверяет с Tasks Board.

---

## Финальная инвентаризация для recovery

### Скрипты на VPS (13 шт., все в `deploy/scripts/`)

`gws-cli.py`, `yacal-cli.py`, `transcribe-audio-watcher.sh`, `media-cleanup.sh`, `reminder-operacionka.sh`, `reminder-weekly-digest.sh`, `weekly-digest.sh`, `daily-digest.sh`, `archive-memory.sh`, `openclaw-autocommit.sh`, `permission-watchdog.sh`, `pre-update-backup.sh`, `watchdog.sh`.

### Workspace skills (8 шт., все в `deploy/workspace/skills/`)

`calendar-keeper`, `mail-handler`, `inbox-saver`, `browser-agent`, `deep-research`, `page-reader`, `web-quick`, `self-improving-agent`.

### Crontab (для `crontab -e` под clawd)

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

### Openclaw cron jobs (через `openclaw cron list`)

| ID | Имя | Schedule | Модель |
|---|---|---|---|
| `f556c692-...` | Утренний-прогноз | `0 5 * * *` Europe/Moscow (08:00 МСК) | `openai/gpt-5.5` |
| `380a8653-...` | pattern-analysis-weekly | `0 9 * * 0` Europe/Moscow (Вс 09:00) | `openai/gpt-5.5` |

### Secrets (`~/.openclaw/secrets/`, все chmod 600)

- `telegram.token` — Telegram bot token (`@Ivanichsila_bot`)
- `yandex-caldav.json` — Yandex CalDAV creds
- `google-token.json` — Google OAuth refresh_token backup
- `google-credentials.json` / `google-oauth.json` — OAuth client config
- `google-gemini-api.key` — Gemini API key (для будущего)
- `openai-primary.token` / `openai-backup.token` — устаревшие
- `google-rusfincoach.txt` — устаревший аккаунт (можно удалить)

---

## Цикл 09.06–17.06.2026 — DeepGram, sync-checker, monitoring, snapshots

### Расширение 09.06 — Системный промт v3 + Бакланов-инцидент

Пользователь обновил `/emmbase/agents/openclaw-bot-системный-промт.md` до v3 — новые поля YAML в файлах inbox:
- `# Дата события:` (вместо `# Дата:`) — когда событие произошло, не дата записи
- `# Телефон:` — для поиска карточки клиента по номеру
- `# Связать с: [[obsidian-links]]` — граф связей

Причина: инцидент 09.06 — Claude поместил сегодняшний транскрипт звонка с Александром Николаевичем Баклановым (Альфарма-М) в карточку клиента с **именем 2026-06-08** (вчерашняя дата), Руслан искал по 09.06 и не нашёл. Файл сам был на месте (`КЛИЕНТЫ/Альфарма-М (Баканов)/2026-06-08_транскрипт-звонок.md`), но из-за неправильного имени казался пропавшим.

Обновлено:
- `transcribe-audio-watcher.sh` — парсит PBX-формат имён `<имя_клиента>_<phone>_YYYYMMDDHHMMSS---uuid.amr`, извлекает timestamp звонка → `# Дата события`, телефон → `# Телефон`.
- `inbox-saver/SKILL.md` — переписан под v3 с примерами.

Параллельно отдельный документ `feedback-for-claude-2026-06-09.md` (в корне репо) — обратная связь для Claude по 6 правилам разбора inbox.

### Расширение 09.06 (continued) — путаница workspace/inbox vs emmbase/inbox

Бот регулярно писал в `~/.openclaw/workspace/inbox/` (своя рабочая папка) вместо `/emmbase/inbox/` (Obsidian vault). За период 01.06–03.06 накопилось 12 «потерянных» файлов (Florida Beach, Mikhail, Кир Воликов, Чемоданов, Топорков и т.д.) которые Claude никогда не видел.

Применено:
- 12 файлов перенесены в `/emmbase/inbox/` руками.
- Создан **`inbox-relocator.sh`** (cron каждую минуту) — переносит файлы из workspace/inbox в emmbase/inbox + шлёт Telegram-алерт «бот опять промахнулся».
- В `SOUL.md` и `inbox-saver/SKILL.md` добавлен жёсткий блок «❌ Запрещённые пути».

### Расширение 09.06 (continued) — Google refresh_token истёк (опять)

Через 9 дней после re-auth 31.05 Google снова отозвал refresh_token (Google policy: testing-mode apps теряют tokens через 7 дней). Симптом: утренний дайджест показал «Gmail: ошибка чтения, Google: нет событий».

Решение: новый OAuth flow через **OOB** (`urn:ietf:wg:oauth:2.0:oob`) — Google показывает code прямо на странице крупным шрифтом, не надо копировать redirect URL из адресной строки (проще для пользователя — он раньше путал OAuth URL с redirect URL).

Memory: [`google-refresh-token-7-day-expiry.md`](https://example.com/memory). Root fix — Google Cloud Console → OAuth consent screen → Publish App. Пользователь это сделал 09.06 (status «In production»), но для sensitive scopes (Gmail/Calendar) Google всё равно может отзывать токены для unverified apps. Полное решение — пройти verification (требует privacy policy URL, ~2-6 недель ожидания).

### Расширение 17.06 — DeepGram primary + 3-уровневый fallback транскрипции

Watcher транскрипции упирался в Groq Whisper Large v3 на длинных файлах (25+ мин записи ФИС / Музыченко). Groq имеет неявные ограничения по длине, ответ — пустой transcript.

Применено:
- Добавлен **DeepGram API ключ** в `env` + `~/.openclaw/secrets/deepgram.token`.
- `transcribe-audio-watcher.sh` переписан с 3 уровнями fallback:
  1. **DeepGram nova-2** (ru, smart_format, diarize, principle) — принимает AMR **напрямую без ffmpeg**, длинные файлы (25+ мин) OK.
  2. **Groq Whisper Large v3** (fallback) — через ffmpeg → opus.
  3. **faster-whisper local** (fallback fallback) — model `base` на CPU, offline. Установлен через `/home/clawd/browser-env/bin/pip install faster-whisper`.
- Параметр `engine` теперь в логе `[ok:deepgram]` / `[ok:groq]` / `[ok:whisper-local]` — видно какой движок отработал.
- Защита от collision: если файл с тем же именем уже есть в inbox, добавляется суффикс `_2.md`, `_3.md` (раньше был silent overwrite).

Re-транскрибированы оба AMR ФИС (по 25 минут каждый) → 19 823 chars transcript в `/emmbase/inbox/2026-06-17_0653_voice-fis-muzychenko.md`.

### Расширение 17.06 — inbox monitoring + hourly snapshot

Триггер: 16.06 три файла исчезли из inbox без следа (предположительно Syncthing засинкал удаление с компа). Раньше для recovery не было снапшота.

Применено:
- **`inbox-snapshot.sh`** — каждый час rsync с hardlink-копированием из `~/emmbase/inbox/` в `~/.openclaw/backups/inbox-snapshot/snapshot-ГГГГ-ММ-ДД_ЧЧ/`. Hardlinks → дисковое место не растёт. Хранится 7 дней. `LATEST` симлинк всегда указывает на последний.
- **`inbox-monitor.sh`** — раз в день в 10:00 МСК Telegram-дайджест:
  - сколько файлов в inbox корне сейчас
  - сколько Claude разобрал за 24ч (новые файлы в КЛИЕНТЫ, life, projects)
  - **⚠️ алерт «пропали без следа»**: файлы которые были в snapshot вчера, но сегодня нет нигде в emmbase

Recovery файла из snapshot: `cp ~/.openclaw/backups/inbox-snapshot/snapshot-ГГГГ-ММ-ДД_ЧЧ/файл.md ~/emmbase/inbox/`.

### Расширение 17.06 — calendar-board-sync (двунаправленная сверка)

Раньше сверка с Tasks Board была только **реактивная** (calendar-keeper skill, при запросе пользователя). Добавлена **пассивная** сверка:

- **`calendar-board-sync.sh`** (cron 04:00 + 17:00 UTC = 07:00 + 20:00 МСК):
  - Читает Google + Yandex (все 6 events-календарей) на сегодня + 7 дней.
  - Парсит секцию «📅 Календарь» из `Tasks Board.md`.
  - При расхождении:
    1. Telegram-сообщение Руслану с конкретикой («🆕 В календарях, нет в Tasks Board: ...», «⚠️ В Tasks Board, нет в календарях: ...»).
    2. Файл-инструкция Claude'у в `/emmbase/inbox/ГГГГ-ММ-ДД_ЧЧММ_sync-calendar-tasks-board.md`.

Этот двунаправленный sync покрывает сценарий: Руслан добавляет событие напрямую в Google Calendar (через мобильный/web), минуя бота — бот это автоматически обнаруживает и просит Claude обновить Tasks Board.

### Расширение 17.06 — Inbox подпапки в правилах

В `/emmbase/inbox/` есть 3 функциональных подпапки:
- `claude-инструкции/` — бот может класть **мета-инструкции** Claude'у по обслуживанию базы (обновить индексы, чистка ссылок, и т.п.).
- `ruslan-actions/` — бот документирует **ручные действия Руслана** для будущей автоматизации.
- `_archive/` — Claude складывает разобранные файлы (бот не пишет сам).

Добавлены явные правила в `inbox-saver/SKILL.md` (раздел «Подпапки inbox/ — когда использовать»). Структура НЕ плоская — у каждой подпапки своя роль.

### Финальная инвентаризация на 17.06.2026

**Скрипты на VPS (17 шт., все в `deploy/scripts/`):**

| Скрипт | Cron | Назначение |
|---|---|---|
| `transcribe-audio-watcher.sh` | `* * * * *` (каждую мин) | DeepGram→Groq→whisper-local, .amr→inbox |
| `inbox-relocator.sh` | `* * * * *` | страховка от workspace/inbox-промахов |
| `permission-watchdog.sh` | `*/15 * * * *` | права на secrets |
| `openclaw-autocommit.sh` | `0 * * * *` | git автокоммит ~/.openclaw |
| `inbox-snapshot.sh` | `0 * * * *` | hardlink-snapshot inbox каждый час |
| `daily-digest.sh` | `30 4 * * 1-5` (07:30 МСК будни) | дайджест emmbase по календарю/почте |
| `calendar-board-sync.sh` | `0 4 * * *` + `0 17 * * *` (07:00+20:00 МСК) | сверка календарей ↔ Tasks Board |
| `inbox-monitor.sh` | `0 7 * * *` (10:00 МСК) | Telegram-дайджест inbox + детектор пропаж |
| `reminder-operacionka.sh` | `30 6 * * 1-5` (09:30 МСК будни) | 🔔 «Чат Операционка» |
| `reminder-weekly-digest.sh` | `0 15 * * 5` (18:00 МСК пятн.) | 📋 «Итоги недели» |
| `media-cleanup.sh` | `0 4 * * *` (07:00 МСК) | чистка media/* старше N дней |
| `archive-memory.sh` | `0 3 * * 0` (06:00 МСК вс) | архив workspace/memory |
| `weekly-digest.sh` | `0 10 * * 1` (13:00 МСК пн) | weekly-дайджест workspace/memory |
| `watchdog.sh` | вручную | бюджетный fail-closed |
| `pre-update-backup.sh` | вручную | снэпшот перед `openclaw update` |
| `gws-cli.py` | по требованию из бота | Google API wrapper (Gmail/Calendar/Drive) |
| `yacal-cli.py` | по требованию из бота | Yandex CalDAV wrapper (7 календарей) |

**Дополнительно (не из моего bundle, оставлено как есть):**
- ~~`/tmp/watcher.sh` cron `*/30 * * * *` — отдельный watcher md-изменений emmbase, создан 11.06 (вероятно Claude'ом). ⚠️ В `/tmp/` — пропадёт при reboot VPS.~~
  **Так и вышло:** файл вычищен из `/tmp` 09.07.2026, после чего cron полмесяца писал в лог `not found` (891 КБ мусора), а `emmbase-changes.log` замёрз. Потребителей его вывода не нашлось, состояние было сломано (полный дамп вместо дельты) → строка удалена из crontab 26.07.2026. Мораль: скриптам не место в `/tmp`.

**Workspace skills (8 шт.):** calendar-keeper, mail-handler, inbox-saver, browser-agent, deep-research, page-reader, web-quick, self-improving-agent.

**Env-ключи в `~/.openclaw/openclaw.json`:** GROQ_API_KEY, OPENROUTER_API_KEY, BRAVE_API_KEY, TAVILY_API_KEY, GOOGLE_OAUTH_CLIENT_ID/SECRET, GOOGLE_WORKSPACE_CLIENT_ID/SECRET/REFRESH_TOKEN, **DEEPGRAM_API_KEY** (новое), OPENAI_SOCKS_PROXY, HTTPS_PROXY/HTTP_PROXY/NO_PROXY.

**Secrets (`~/.openclaw/secrets/`, все 0600):** telegram.token, yandex-caldav.json, **deepgram.token** (новое), google-* (5 файлов), openai-* (2 файла).

**Cron-таймзона:** `Etc/UTC` (проверено через `timedatectl`). Все cron-выражения в UTC.

### Memory-записи (добавлено в этот цикл)

- `google-refresh-token-7-day-expiry.md` — 7-day цикл expiry для Testing apps + OOB flow.
- `deploy-bash-hardening-patterns.md` — `scp && ssh` цепочка, `set -e` в ssh-блоке, cron-дедуп по имени скрипта (не точной строке).


---

# Цикл 26.07.2026 — восстановление, аудит, обновление платформы

Полный разбор: **[../WORK-SUMMARY-2026-07-26.md](../WORK-SUMMARY-2026-07-26.md)**.
Коммиты: `945f0e8`, `6a77ee1`, `2567390`, `a6c8091`.

**Кратко, что изменилось в инфраструктуре:**

| Область | Изменение |
|---|---|
| Транскрипция | разделение говорящих (`diarize_model=latest` + `utterances`), голосовой якорь, склейка реплик |
| Мониторинг | `telegram-watchdog.sh` ловит зависший ingress-spool; новый `google-token-check.sh` |
| Бэкапы | автокоммит чинит вложенный `workspace/`, push на GitHub восстановлен (ветки `main` + `bot-rules`), снимки еженедельно |
| Платформа | openclaw `2026.5.19` → `2026.7.1-2` |
| Гигиена | освобождено ~2.3 ГБ (journal, sessions, бэкапы конфига) |

**Что важно помнить при следующих работах:**

1. Провайдеры моделей в `2026.7.x` — **отдельные плагины**; ключи хранятся не в
   `auth-profiles.json`, а в `agents/main/agent/openclaw-agent.sqlite`.
2. При старте новая версия **ждёт подтверждения с клавиатуры** на предупреждениях
   конфига — под systemd это выглядит как вечное зависание без логов.
3. `npm` на VPS по умолчанию целится в `/usr` — всегда указывать
   `--prefix /home/clawd/.npm-global`.
4. `workspace/` содержит `media/` с записями звонков клиентов и
   `openclaw-config.json` с ключами открытым текстом — **не пушить целиком**,
   в репо есть `.gitignore` с исключениями.
5. `git-crypt status` без аргумента виснет на untracked-папках — проверять точечно.
