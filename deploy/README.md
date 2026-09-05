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

### `scripts/` — что какой делает (26 файлов)

Все cron-выражения в **UTC** (системная таймзона VPS = `Etc/UTC`).

| Скрипт | Cron (UTC → МСК) | Назначение |
|---|---|---|
| **`gws-cli.py`** | по требованию | Google API wrapper (Gmail / Calendar / Drive). Бот вызывает через `exec`. |
| **`yacal-cli.py`** | по требованию | Yandex Calendar CalDAV wrapper (7 календарей). Read+write. |
| **`transcribe-audio-watcher.sh`** | `* * * * *` (каждую мин) | `.amr`/`.3gp` → **DeepGram nova-2** (primary) / Groq Whisper / faster-whisper local — fallback цепочка. **Разделяет говорящих** (`diarize_model=latest` + `utterances`, склейка реплик, голосовой якорь `media/voice-anchor-ruslan.ogg` → «Руслан/Собеседник»). Результат → inbox + Telegram. |
| **`inbox-relocator.sh`** | `* * * * *` (каждую мин) | Страховка: переносит файлы из `~/.openclaw/workspace/inbox/` в `~/emmbase/inbox/` + алерт в Telegram. |
| **`inbox-snapshot.sh`** | `0 * * * *` (каждый час) | Hardlink-snapshot всего inbox в `~/.openclaw/backups/inbox-snapshot/`. 7 дней хранения. Снимок делается **только при реальных изменениях** (sha256-отпечаток содержимого), rsync с `--checksum` и `--delete`. |
| **`inbox-monitor.sh`** | `0 7 * * *` (10:00 МСК) | Telegram-дайджест inbox + детектор «тихих пропаж» (что было в snapshot вчера, нет сегодня). |
| **`calendar-board-sync.sh`** | `0 4 * * *` + `0 17 * * *` (07:00+20:00 МСК) | Сверяет Google+Yandex calendar с Tasks Board. Слотом признаётся только каноническое `ДД.ММ (дн), ЧЧ:ММ` — «после 10:00» не слот. Строка с тегом `#nosync` исключается из сверки в обе стороны. Файл в inbox создаётся **только если набор расхождений изменился** (подпись в `state/cal-board-sync.hash`). Флаг `--dry-run` — печать без записи. |
| **`проверка-связности.sh`** | `40 3 * * *` (06:40 МСК) | Три метрики связности EMMBASE: файлы вне `ПОЛНЫЙ_ИНДЕКС`, битые `[[ссылки]]`, неоднозначные имена. Отчёт с дельтой к прошлому прогону → `inbox/`, тип `вопрос`. **Ничего не чинит.** Флаг `--dry-run`. |
| **`checkin-buffer-cleanup.sh`** | `*/20 * * * *` | Удаляет буфер `life/чекины/_чекин-в-процессе.md`, но **только когда есть** готовый `life/чекины/<дата>.md` — иначе незавершённый опрос потерялся бы. |
| **`astro-daily.sh`** + **`astro-cli.py`** | `50 1 * * *` (04:50 МСК) | Локальный расчёт эфемерид (транзиты swisseph + столпы Бацзы) → `life/прогнозы/_астро-данные-сегодня.md`. Заменил внешние сайты, недоступные с RU-адреса. |
| **`codex-tor-route.sh`** | при загрузке | Заворачивает трафик к `chatgpt.com` в Tor через iptables REDIRECT + REJECT по IPv6-диапазону провайдера. Без него Codex отдаёт 403 по региону. |
| **`setup-telegram-redsocks.sh`** | разово | Установка прозрачного SOCKS-прокси (redsocks + iptables) для `api.telegram.org` — блокировка TimeWeb/РКН с 27.06. |
| **`undici-telegram-proxy.mjs`** | загружается gateway | Патч undici: axios внутри openclaw игнорирует `HTTPS_PROXY`, дозвон до Telegram шёл мимо прокси. |
| **`media-cleanup.sh`** | `0 4 * * *` (07:00 МСК) | Чистит `media/inbound`, `transcribed`, `outbound`, image-generation, `/tmp/openclaw`. |
| **`reminder-operacionka.sh`** | `30 6 * * 1-5` (09:30 МСК будни) | «🔔 Чат Операционка» в Telegram. |
| **`reminder-weekly-digest.sh`** | `0 15 * * 5` (18:00 МСК пт) | «📋 Итоги недели». |
| **`weekly-digest.sh`** | `0 10 * * 1` (13:00 МСК пн) | Дайджест по `workspace/memory/` через kimi. |
| **`daily-digest.sh`** | `30 4 * * 1-5` (07:30 МСК будни) | Ежедневный дайджест EMMBASE (Gmail + Calendar Google/Yandex + Tasks Board). |
| **`archive-memory.sh`** | `0 3 * * 0` (06:00 МСК вс) | Архивация memory в .tgz. |
| **`openclaw-autocommit.sh`** | `0 * * * *` | Автокоммит **двух** репозиториев: `~/.openclaw/` (ветка `main`, конфиг шифруется git-crypt) и вложенного `workspace/` с правилами бота (ветка `bot-rules`). Push в приватный `autorusland-ai/openclaw-backup`. Лог: `logs/autocommit.log`. |
| **`permission-watchdog.sh`** | `*/15 * * * *` | Сторож прав на secrets (0600 на token-файлы). |
| **`telegram-watchdog.sh`** | `*/5 * * * *` | Сторож Telegram-канала: рестарт gateway при неактивной службе, зависших >15 мин входящих в ingress-spool, серии `getMe`-таймаутов или холостых рестартах health-monitor. Проактивные уведомления владельцу. |
| **`google-token-check.sh`** | `0 6 * * *` (09:00 МСК) | Проверяет, обновляется ли Google OAuth-токен; при отказе — алерт в Telegram с кодом ошибки, при восстановлении — отбой. |
| **`pre-update-backup.sh`** | `0 5 * * 0` (08:00 МСК вс) + вручную | Шифрованный снимок состояния, ротация 8 шт. Из архива исключены зависимости, кэши, медиа и codex-home. |
| **`watchdog.sh`** | вручную | Бюджетный watchdog (fail-closed, без spend source). |

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
