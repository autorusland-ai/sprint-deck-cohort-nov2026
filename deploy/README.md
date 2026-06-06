# OpenClaw VPS Deploy Bundle

Полное развёртывание бота-агента «Иванычь» (Telegram + Gmail/Google Calendar + Yandex CalDAV + Voice + Tor proxy + EMMBASE inbox-only architecture) на свежем Ubuntu 24.04 VPS.

## TL;DR (2 команды на чистом VPS)

```bash
# 1. Под root — системные пакеты, юзер clawd, Tor, Docker, Node, Python venv, openclaw CLI
sudo bash bootstrap.sh

# 2. Под clawd — интерактивная настройка ключей + OAuth flows + crontab
sudo -u clawd bash configure.sh
```

После этого в Telegram пишешь боту — отвечает.

## Что в этом bundle

| Файл / папка | Зачем |
|---|---|
| **[DEPLOY-GUIDE.md](DEPLOY-GUIDE.md)** | **Главный мануал.** Архитектура, провайдеры, известные ловушки, recovery-процедуры. **Читать первым.** |
| [WORK-HISTORY.md](WORK-HISTORY.md) | Хронология всех правок 30.05 – 06.06.2026 (для контекста, не для исполнения). |
| [bootstrap.sh](bootstrap.sh) | Системные пакеты (apt), user setup, Tor + Privoxy, Docker, Node 24, Python 3.12 venv, npm-global openclaw + mem0, sandbox Docker image, Ollama + Qdrant. **Один раз, под root.** |
| [configure.sh](configure.sh) | Интерактивная настройка: 8 API ключей провайдеров, Telegram bot token, OAuth Google (через браузер) + Yandex CalDAV app-password, crontab install. **Под `clawd`.** |
| [openclaw-template.json](openclaw-template.json) | Шаблон `~/.openclaw/openclaw.json` с placeholder'ами. `configure.sh` подставит значения. |
| [systemd/](systemd/) | `openclaw-gateway.service` (user unit), drop-in `proxy.conf` (HTTPS_PROXY+NO_PROXY), `xvfb.service` (для browser-use). |
| [scripts/](scripts/) | 13 helper-скриптов — host-side API wrappers и cron-задачи. См. таблицу ниже. |
| [workspace/](workspace/) | Правила бота: SOUL, IDENTITY, TOOLS, USER, AGENTS, 8 skills, шаблоны постов. |

### `scripts/` — что какой делает

| Скрипт | Что | Запуск |
|---|---|---|
| **`gws-cli.py`** | Google API wrapper (Gmail / Calendar / Drive). Бот вызывает через `exec`. | По требованию из бота |
| **`yacal-cli.py`** | Yandex Calendar CalDAV wrapper (7 календарей). Read+write. | По требованию из бота |
| **`transcribe-audio-watcher.sh`** | Конверсия `.amr`/`.3gp` → ogg → Groq Whisper → транскрипт в Telegram. | Cron, каждую минуту |
| **`media-cleanup.sh`** | Чистит `media/inbound`, `transcribed`, `outbound`, image-generation, `/tmp/openclaw`. | Cron, 04:00 UTC |
| **`reminder-operacionka.sh`** | «🔔 Чат Операционка» в Telegram. | Cron, будни 09:30 МСК |
| **`reminder-weekly-digest.sh`** | «📋 Итоги недели». | Cron, пятница 18:00 МСК |
| **`weekly-digest.sh`** | Дайджест по `workspace/memory/` через kimi. | Cron, понедельник 10:00 МСК |
| **`daily-digest.sh`** | Ежедневный дайджест базы EMMBASE. | Cron |
| **`archive-memory.sh`** | Архивация memory в .tgz. | Cron, воскресенье 03:00 |
| **`openclaw-autocommit.sh`** | Автокоммит `~/.openclaw/` в git. | Cron, каждый час |
| **`permission-watchdog.sh`** | Сторож прав на secrets. | Cron, каждые 15 мин |
| **`pre-update-backup.sh`** | Снэпшот перед `openclaw update`. | Вручную |
| **`watchdog.sh`** | Бюджетный watchdog (fail-closed, без spend source). | Вручную |

### `workspace/skills/` — 8 skills

| Skill | Описание |
|---|---|
| **`calendar-keeper`** | Календари Google+Yandex. **Сверяет с `Tasks Board.md`**. WRITE → inbox-saver. |
| **`mail-handler`** | Gmail. READ напрямую, WRITE → inbox-saver. |
| **`inbox-saver`** | **Архитектурный**: все команды на сохранение/изменение → `/emmbase/inbox/` с YAML-разметкой. Claude разбирает inbox в отдельной сессии. |
| `browser-agent` | Web automation через browser-use MCP. |
| `deep-research` | Многоступенчатое исследование тем. |
| `page-reader` | Чтение web-страницы. |
| `web-quick` | Быстрый поиск через Brave/Tavily. |
| `self-improving-agent` | Лог learnings/errors для эволюции бота. |

## Recovery — типовые сценарии

| Симптом | Куда смотреть |
|---|---|
| Бот молчит / 500 / Something went wrong | `DEPLOY-GUIDE.md` § «Recovery — типовые симптомы» |
| «Gmail/Calendar MCP не подключён» | `DEPLOY-GUIDE.md` § «MCP не пробрасывается → host-script через exec» + `/new` в Telegram |
| Voice .amr не транскрибируется | `DEPLOY-GUIDE.md` § «AMR pipeline». Проверь `transcribe-audio.log`. |
| 401/403 от Groq/OpenAI/Google | Проверь NO_PROXY + sync ключа в auth-profiles |
| Утренний прогноз не пришёл в 08:00 МСК | `openclaw cron list` → проверь `Model`. Должно быть `openai/gpt-5.5` (НЕ `gpt-5`). |

## Полный backup секретов (для recovery той же VPS-конфигурации)

Делается один раз, лежит **не в этом bundle** (зашифровано GPG, твой пароль):

```bash
# На VPS:
tar -czf /tmp/openclaw-secrets-raw.tgz -C ~ \
  .openclaw/openclaw.json \
  .openclaw/agents/main/agent/auth-profiles.json \
  .openclaw/agents/main/agent/models.json \
  .openclaw/agents/main/agent/auth-state.json \
  .openclaw/secrets/

# На VPS (интерактивно — gpg попросит passphrase дважды):
ssh -tt clawd-vps-tail "gpg --symmetric --cipher-algo AES256 \
  --output /tmp/openclaw-secrets.tgz.gpg /tmp/openclaw-secrets-raw.tgz \
  && shred -u /tmp/openclaw-secrets-raw.tgz"

# Скачать к себе:
scp clawd-vps-tail:/tmp/openclaw-secrets.tgz.gpg ./openclaw-secrets-backup.tgz.gpg
ssh clawd-vps-tail "rm /tmp/openclaw-secrets.tgz.gpg"
```

**Восстановление** на новой машине после `bootstrap.sh`:

```bash
gpg -d openclaw-secrets-backup.tgz.gpg | tar -xzv -C ~
systemctl --user restart openclaw-gateway
```

Не клади `.gpg`-файл рядом с этим bundle в git — если пароль слабый, утечка ключа + пароля = компрометация. Держи в облаке/external drive отдельно.

## Что НЕ автоматизируется

1. **Создать Telegram бота** через `@BotFather` — получить bot token, заполнить в configure.sh.
2. **OAuth Google** — открыть URL в браузере под `rusfeodor@gmail.com`, нажать «Разрешить», скопировать redirect URL обратно (configure.sh ведёт).
3. **Yandex CalDAV app password** — создать на [id.yandex.ru/security/app-passwords](https://id.yandex.ru/security/app-passwords) под нужный аккаунт.
4. **OAuth Codex** (опционально, для `openai/gpt-5.5` через ChatGPT-аккаунт) — `auth.openai.com`, то же что и Google.
5. **API top-ups** — деньги на DeepSeek / MiniMax (важно: API balance, не Chat Plus subscription) / Groq / OpenRouter.
6. **Адаптация `workspace/`** под нового пользователя — SOUL, IDENTITY, USER, нейрорайтер-промпт жёстко завязаны на «Иванычь / Руслан Фёдоров».
7. **Telegram канал admin** для публикации — добавить бота через UI канала.
8. **DNS бота** — Telegram polling работает прозрачно, но если нужен webhook — настройка домена + SSL отдельно.

## Минимальные требования

- Ubuntu 24.04 LTS (тестирован).
- ≥4 GB RAM (Memory limits в systemd: 1.5 GB high / 2 GB max).
- ≥40 GB disk (sandbox image ~190MB, mem0 + ollama models ~600MB, /tmp/openclaw rotates).
- Outbound интернет к telegram.org + провайдерам ИИ + Google OAuth.
- Если VPS в санкционной юрисдикции (RU/etc): обязателен Tor — bootstrap.sh ставит.
- SSH-доступ с sudo для bootstrap.

## Долгосрочная память (memory)

В дополнение к этому bundle, у меня (Claude) есть 9 файлов памяти в `~/.claude/projects/c--PROJECTS-COMANDOS/memory/` — нетривиальные находки сессии (Tor exit nodes, dual key storage, MCP-in-isolated, inbox architecture, и т.д.). Они автоматически грузятся в каждую следующую сессию через `MEMORY.md` индекс. При переносе на другой VPS эти знания **переезжают со мной**, а не с bundle.

## Сборка ушла в работу 06.06.2026

Все правки за период 30.05.2026 – 06.06.2026 — в [WORK-HISTORY.md](WORK-HISTORY.md). Это коммитабельная папка (нет секретов внутри). Рекомендую сделать `git init` + `git add -A` + `git commit` для версионирования.
