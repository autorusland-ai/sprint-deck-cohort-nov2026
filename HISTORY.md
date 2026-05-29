# История работы — Comandos Claw Deck

> Документ восстановлен 2026-05-13 на основе артефактов проекта.
> Обновляй вручную или через AI-плагин после каждой значимой сессии.

---

## 📋 Сводка проекта

| Параметр | Значение |
|---|---|
| **Проект** | Comandos Claw Deck — пульт управления OpenClaw-агентом на VPS |
| **Бот** | Иваныч — шутливый помощник из советского прошлого |
| **Deck версия** | 1.8.0 (geo-aware primary, OpenClaw gateway unit) |
| **VPS** | Linux Ubuntu 24.04, пользователь `clawd` |
| **Telegram** | @ai_comandos (ID: 215087477) |
| **Репозиторий** | https://github.com/Comandosai/sprint-deck-cohort-nov2026 |

---

## 🗓 Хронология работы

---

### Версия 1.0 – 1.4 (до 2 мая 2026)
**Тема: Базовая установка и структура**

**Что сделано:**
- ✅ Создана структура проекта `comandos-claw-deck/`
- ✅ Написан `workshop-1/` — гайд по установке бота от нуля
- ✅ Создан `standards/workshop-1-standard.md` — ~30 критериев готовности
- ✅ Создан `audit/` — фреймворк независимого аудита
- ✅ Self-check через сам Telegram-бот (8 запросов в боте)
- ✅ Независимый аудитор в новом чате (Контур 3)
- ✅ `workshop-1/guide.html` — интерактивный HTML-гайд с брендингом COMANDOS AI
- ✅ `workshop-1/presentation.html` — кинематографическая презентация спринта

---

### Версия 1.5 (2 мая 2026)
**Тема: Реальная отладка — 2 дня на живом VPS**

**Главные изменения:**
- 🎯 **Гибридный путь установки**: AI делает рутину (5 промптов), человек делает `openclaw onboard` в Terminal вручную (~10 мин), AI доделывает тонкости (4 промпта). Итого ~30 мин вместо ~90.
- 📋 **`workshop-1/01a-install-by-hand.md`** — план Б, полностью ручная установка без AI.
- 🛡 **Усиленный meta-prompt** с режимами DIAGNOSE → FIX → VERIFY.
- ⛔ Явный запрет запуска `openclaw onboard` через AI (ловушка №1).

**Задокументированные баги OpenClaw 2026.4.x:**
| Баг | Симптом | Фикс |
|---|---|---|
| `1008 pairing required` | Любой запрос к моделям → 1008 | Ручной onboard + device-pair плагин включён |
| `path-non-login-shell` | `openclaw: command not found` из cron | PATH в 3 файла + `bash -lc` |
| `slug-case-sensitive` | fallback на DeepSeek вместо MiniMax | `minimax/MiniMax-M2.7` с заглавными |
| `device-pair disabled` | scope-upgrade → 1008 | Включить плагин в config |

---

### Версия 1.6 (5 мая 2026)
**Тема: Knowledge-base под рукой**

**Что добавлено:**
- 📚 **`knowledge-base/`** (~2 МБ): 20 блоков ресерча + 5 PRO-материалов
- 🆘 **7 known-issues** на основе реальной 2-дневной отладки:
  1. `1008-pairing-required` — главная ловушка установки
  2. `path-non-login-shell` — openclaw не виден из cron
  3. `device-pair-disabled` — плагин выключен → нет pairing
  4. `slug-case-sensitive` — регистр в slug важен
  5. `bot-silent-in-telegram` — универсальный гид «бот молчит»
  6. `runaway-4200-incident` — кейс $4200 за 63 часа (!)
  7. `env-not-in-systemd` — env не пробрасывается в daemon
- 🆘 **`knowledge-base/CONSULTANT-PROMPT.md`** — промпт для AI как эксперта

---

### Воркшоп 1 — ЗАВЕРШЁН ✅
**Тема: VPS → Работающий бот в Telegram**

**Результаты (из `workshop-1-self-check.md`):**

| Раздел | Статус |
|---|---|
| A. VPS базовая настройка (Ubuntu 24.04, clawd, sudo, ufw, fail2ban, swap, Node 22) | ✅ |
| B. OpenClaw daemon (npm-global, systemd-user active, gateway 127.0.0.1) | ✅ |
| C. Каскад моделей (5 auth profiles, primary MiniMax, fallback DeepSeek Flash, alias premium) | ✅ |
| D. Telegram-бот (dmPolicy allowlist, ответ ≤30 сек) | ✅ |
| E. Картинки (tools.profile = "full") | ✅ |
| F. Защита от runaway (watchdog cron каждые 30 мин, OpenRouter лимит $30/мес) | ✅ |

**Итоговый конфиг каскада:**
```
primary:  minimax/MiniMax-M2.7        (начальный W1)
→ в v1.8 переключено на deepseek/deepseek-v4-flash (geo-aware для EU/RU VPS)
fallback: deepseek/deepseek-v4-flash
premium:  deepseek/deepseek-v4-pro    (по /model premium)
thinking: deepseek/deepseek-v4-pro:thinking
heartbeat: openrouter/google/gemini-2.5-flash-lite
subagents: openrouter/moonshotai/kimi-k2.6
```

**Watchdog:** `crontab -l` → `*/30 * * * * /home/clawd/.openclaw/scripts/watchdog.sh`
- Kill-switch при spend > $3
- Автоисправление прав `openclaw.json` на 600
- Уведомление в Telegram при срабатывании

---

### Воркшоп 2 — ЗАВЕРШЁН ✅
**Тема: Память, безопасность, GitHub**

**Раздел A — Архитектура памяти:**
- ✅ `workspace/MEMORY.md` — 5 секций (Предпочтения, Клиенты, Решения, Контакты, Фреймворки), <200 строк
- ✅ `workspace/memory/` — папка с daily logs + шаблон `_template.md`
- ✅ Ежедневный файл `2026-05-12.md` создан
- ✅ Только `memory-triage` (mem0) — лишних memory-плагинов нет
- ✅ `MEMORY.md` инжектируется как `start-only`

**Раздел B — Защита контекста:**
- ✅ Compaction включён, режим `summarize-middle`
- ✅ Модель-суммаризатор: `openrouter/moonshotai/kimi-k2.6`
- ✅ Теги `decision`, `fact`, `action-required` защищены от сжатия (preserveTags)
- ✅ `maxHistoryShare: 0.5`, `keepRecentTokens: 40000`
- ✅ `memoryLimitBytes: 500MB`, агрессивный `memoryFlush` на диск
- ✅ `continuation-skip` с кнопкой [Continue] для длинных ответов

**Раздел C — Постоянная память + Privacy:**
- ✅ Docker-контейнер `qdrant/qdrant:v1.12.4` (bind: `127.0.0.1:6333`, скачан из gcr-зеркала)
- ✅ SDK `@mem0/openclaw-mem0` установлен (с `--dangerously-force-unsafe-install`)
- ✅ `vectorStore: qdrant://127.0.0.1:6333`, `collection: openclaw_main`
- ✅ Embedder: `openai/text-embedding-3-small`
- ⚠️ Гибридный поиск / reranker — дефолт (ограничение Mem0 SDK 2.x, перенесено на W3)
- ✅ `autoCapture: true`, `dedupeThreshold: 0.92`
- ✅ `privacyGuard` + `detect-secrets` активированы (`blockOnDetect: true`)
- ✅ Memory Search Protocol прописан в `AGENTS.md` и `SOUL.md`

**Раздел E — Безопасность и GitHub:**
- ✅ Приватный репозиторий `openclaw-backup` на GitHub с push protection
- ✅ `git-crypt init` — зашифрованы: `openclaw.json`, `*.token`, `secrets/**`, `.env`
- ✅ Ключ `openclaw-gitcrypt.key` выгружен владельцу и удалён с VPS
- ✅ `gitleaks v8.21.2` + pre-commit hook + `.gitleaks.toml`
- ✅ Cron-скрипт `openclaw-autocommit.sh` с allowlist путей (без `git add .`)
- ✅ `RECOVERY.md` создан

**Раздел F — Гигиена памяти:**
- ✅ `archive-memory.sh` в cron — очистка фактов старше 30 дней в `archive/`
- ✅ `weekly-digest.sh` в cron (каждый понедельник) — саммари через `kimi-k2.6` → `MEMORY.md`
- ✅ `pre-update-backup.sh` — `tar+gpg` шифрование `~/.openclaw` перед обновлением

**Раздел G — Базовая гигиена (доделки W1):**
- ✅ Heartbeat на `gemini-2.5-flash-lite`
- ✅ Prompt caching включён
- ✅ Удалены даты YYYY-MM-DD из конфигурационных файлов
- ✅ Права `openclaw.json` = 600
- ✅ `permission-watchdog.sh` каждые 15 мин
- ✅ `openclaw doctor` — синтаксис конфига валиден

---

### Версия 1.8.0 (актуальная)
**Тема: Geo-aware primary, финальный тюнинг**

**Изменения:**
- 🌍 Primary модель переключена с `minimax/MiniMax-M2.7` на `deepseek/deepseek-v4-flash`  
  *Причина: geo-aware логика — для EU/RU VPS DeepSeek физически ближе и дешевле*
- ⛔ Auto-fallback на дорогие модели убран (`fallbacks: []` для primary)
- 🤖 Бот переименован/настроен как **Иваныч** (SOUL.md прописан)

---

## 🤖 Личность бота (Иваныч)

**Файл:** `workspace/SOUL.md`

- **Характер:** Шутливый помощник из советского прошлого, добрый.
- **Язык:** Всегда русский, кратко и по делу.
- **Anti-verbosity:** Жёсткие правила против многословия MiniMax:
  - Запрещено повторять вопрос пользователя
  - Запрещено выводить chain-of-thought наружу
  - Запрещены пустые вступления («Отличный вопрос!», «Конечно!»)
  - Простой вопрос → один абзац. Точка.
- **Память:** Перед фактологическим ответом — обязательный `memory_search`. Без вызова → отвечать «не помню».

---

## 🏗 Текущее состояние инфраструктуры

```
[Telegram] ←→ [VPS: OpenClaw daemon (systemd-user)] ←→ [LLM-провайдеры]
                     ↑                    ↓
                     │             [Qdrant 127.0.0.1:6333]
              SSH (./scripts/)     [mem0 openclaw_main]
                     │
         [Этот deck в Antigravity]
```

**Daemon:** `openclaw-gateway.service` — `active (running)`  
**Watchdog:** cron `*/30 * * * *`, kill при spend > $3.00  
**Backup:** cron autocommit → GitHub `openclaw-backup` (приватный, git-crypt)

---

## 📂 Ключевые файлы проекта

| Файл | Назначение |
|---|---|
| `workspace/SOUL.md` | Личность Иваныча — голос, правила, anti-verbosity |
| `workspace/MEMORY.md` | Долгосрочная декларативная память (5 секций) |
| `workspace/USER.md` | Профиль владельца (плейсхолдеры заполнить!) |
| `workspace/BOOT.md` | Стартовый ритуал при старте gateway |
| `workspace/AGENTS.md` | SOP для бота — инструкции как работать |
| `workspace/TOOLS.md` | Инфраструктурные детали: SSH, Voice, MCP, Qdrant |
| `config/openclaw.json` | Главный конфиг (4 модели, spending, voice, image, mem0) |
| `watchdog.sh` | Kill-switch + проверка прав (запущен на VPS через cron) |

---

## 🔮 Что осталось / Следующие шаги

### Незакрытые вопросы
- ⚠️ `workspace/USER.md` — плейсхолдеры `{{...}}` **не заполнены**. Бот не знает профиль владельца.
- ⚠️ `workspace/IDENTITY.md` — плейсхолдеры **не заполнены**. Нет имени, эмодзи, аватара в config.
- ⚠️ D. Амнезия-тест (Qdrant + mem0) — ещё не проведён полностью.
- ⚠️ Гибридный поиск / reranker — перенесено на W3.

### Обсуждалось сегодня (2026-05-13)
1. **Knowledge-base** (`Downloads\BASE\knowledge-base`, 97 MD-файлов):
   - Вариант A: статика в workspace (только топ-5 файлов)
   - Вариант B: MCP Filesystem server (`@modelcontextprotocol/server-filesystem`) — простой поиск по файлам
   - Вариант C: Векторная индексация в Qdrant (RAG) — семантический поиск
   - **Рекомендация:** B + C совместно (filesystem для точечного, Qdrant для смыслового)

2. **Обновление базы знаний** — варианты синхронизации:
   - Вариант A: `scripts/sync-kb.sh` (ручной rsync) — быстрый старт ✅
   - Вариант B: Windows Task Scheduler (авто каждые 6ч)
   - Вариант C: git + cron pull на VPS (для истории изменений)
   - После sync — инкрементальная переиндексация `reindex.py` для Qdrant

### Воркшоп 3 (запланирован)
- Гибридный поиск / reranker в Qdrant
- Подключение knowledge-base (sync-kb.sh + reindex.py)
- Кастомные skills

---

## 📝 Лог сессий

| Дата | Сессия | Что сделано |
|---|---|---|
| до 02.05.2026 | W1 pre | Базовая структура deck v1.0–1.4 |
| 02.05.2026 | W1 debug | 2 дня отладки, задокументированы 4 бага OpenClaw, v1.5 |
| 05.05.2026 | W1 KB | Добавлена knowledge-base + 7 known-issues, v1.6 |
| ~12.05.2026 | W2 | Память (Qdrant+mem0), безопасность (git-crypt+gitleaks), гигиена |
| 12.05.2026 | W2 tuning | Geo-aware primary (DeepSeek для EU/RU), настройка Иваныча, v1.8 |
| 13.05.2026 | Сегодня | Обсуждение подключения внешней KB (97 файлов), варианты sync |

---

## ?? ������� �������������� ���� (��� �������)

> ������ runbook: `checklists/disaster-recovery.md`
> ���� ���� � ���������, ����� ������ ����������������.

### ��� ����� ����� ������������

| ��� | ��� �������� | ���� ������ |
|---|---|---|
| Deck (�������, workspace, scripts) | git-���� | ������ |
| API-����� | `.env` �������� �� �� | **������� � ����� �����!** |
| SSH-���� � VPS | `~/.ssh/clawd_ed25519` | **������� � ������ �����!** |
| �������� ������� (SOUL, BOOT, AGENTS) | � git-���� | ������ |
| ���������� ���� memory/ | VPS + git (����� pull.sh) | ������� ���� �� ������ pull.sh |
| ��������� ������ Qdrant | ������ �� VPS | ������� ���� ��� snapshot |

---

### �������� A � Daemon ����, VPS ���

```bash
ssh clawd-vps "systemctl --user restart openclaw-gateway"
./scripts/status.sh
```

���� �� ������� > `checklists/gateway-restart.md`

---

### �������� B � ������ ������ / ��������

```bash
git commit -am "backup before fix"
git checkout HEAD~1 -- config/openclaw.json
./scripts/deploy.sh
```

---

### �������� C � VPS ���� ��������� (~30 �����)

1. ����� VPS (Hetzner CX22, Ubuntu 24.04) > IP � `.env`
2. Bootstrap: apt, Node 22, swap, ufw, fail2ban, linger, `npm install -g openclaw@latest`
3. `./scripts/deploy.sh` � �������� workspace + config
4. �������: `telegram.token` � `ui.token` � `~/.openclaw/secrets/`
5. Systemd unit > `systemctl --user enable --now openclaw`
6. Qdrant (���� ����� ������): docker + `docker-compose.qdrant.yml`
7. ��������: `./scripts/status.sh` > �������� ���� �������

������ �������: `checklists/disaster-recovery.md`

---

### �������� D � ������ ������� ����� ������

```bash
./scripts/emergency-stop.sh
```

---

### ��������� (������ ���������)

| ������� | �������� |
|---|---|
| ����� ������� ��������� | `git commit -am "..."` |
| ��� � ���� | `./scripts/pull.sh` (���� memory � VPS) |
| ��� � ������ | Qdrant snapshot (������� � disaster-recovery.md) |
| ��� � ����� | ��������� ��� .env ����� ��������� |

> **������� �������:** deck � git + .env � ���������� ����� = ����� ������� ����������������� �� 30 �����.

---

## ?? ������ 2026-05-14

### ��������: Groq Whisper �� ����� API-����

**�������:** ��� ������� ���� API-����� ��� Groq Whisper� ��� ��������� ����������.

**�������:** `env-not-in-systemd` � ��������� ���. systemd �� ������ `.env` �������������. `openclaw.json` ���������� `${GROQ_API_KEY}` ��� �����������, �� ��� ������ ����������� �� ���������.

**�������:**
- ����� Telegram-���� ������ systemd override-����:
  `~/.config/systemd/user/openclaw-gateway.service.d/env.conf`
- ��������� ������ `Environment="GROQ_API_KEY=gsk_..."`
- `systemctl --user daemon-reload && restart` � ��� ���������� ���� �����
- ������ ������ `config/systemd/env.conf.example` � deck
- �������� **���� 4.5** � `checklists/disaster-recovery.md`

**������:** ? Whisper �������������� ���������

---

### A.15: �������� ���������� SSH ����� Tailscale

**��� ������� �� �����:**

1. ? Tailscale ���������� �� VPS ����� Telegram-���� (`curl -fsSL https://tailscale.com/install.sh | sh`)
2. ? Tailscale ���������� �� Windows-�����, ����� ����� Google-������� rusland@
3. ? VPS ����������� ����� Auth Key �� admin.tailscale.com
4. ? SSH ����� Tailscale ��������: `ssh clawd-vps-tail "echo OK"` � ��������
5. ? ��������� SSH ������: `sudo ufw delete` (������� ������� `22/tcp` IPv4 + IPv6)
6. ? sshd ���������: `ListenAddress 100.76.223.48` + `ListenAddress 127.0.0.1`
7. ? `~/.ssh/config` ������� � �������� ����� `clawd-vps-tail`
8. ? `.env` �������: `VPS_IP=100.76.223.48`, `VPS_PUBLIC_IP=186.246.3.224`
9. ? `RECOVERY.md` �� VPS ������� � ����������� �� �������������� Tailscale

**������� ������:**

| ���������� | Tailscale IP | Hostname |
|---|---|---|
| VPS | 100.76.223.48 | 7808894-zm343910 |
| Windows-���� | 100.108.36.104 | redrus |
| ������� Tailscale | auto.rusland@ | Google |

**��� ������ ������������:**
```
ssh clawd-vps-tail   # ����� Tailscale (��������)
```

**��������� IP** `186.246.3.224` � SSH ����������, ������ ��� �������.

**������ A.15:** ? �������

---

### ����������� (�� �����������)

- ����������� knowledge-base `Downloads\BASE\knowledge-base` (97 MD-������):
  - ��������: MCP Filesystem / Qdrant RAG / ������� � workspace
  - �������� �������������: ������ rsync / Task Scheduler / git+cron
  - ������� ��������

- ������� �� ������������: ��������� � ���������� ������ �� vc.ru

---

### ��� ������ (�������)

| ���� | ������ | ��� ������� |
|---|---|---|
| �� 02.05.2026 | W1 pre | ������� ��������� deck v1.0-1.4 |
| 02.05.2026 | W1 debug | 2 ��� �������, ����������������� 4 ���� OpenClaw, v1.5 |
| 05.05.2026 | W1 KB | ��������� knowledge-base + 7 known-issues, v1.6 |
| ~12.05.2026 | W2 | ������ (Qdrant+mem0), ������������ (git-crypt+gitleaks), ������� |
| 12.05.2026 | W2 tuning | Geo-aware primary (DeepSeek ��� EU/RU), ��������� �������, v1.8 |
| 13.05.2026 | KB planning | ���������� ����������� ������� KB (97 ������), �������� sync |
| 14.05.2026 | Groq fix | env-not-in-systemd: ������ env.conf override, Whisper ��������� |
| 14.05.2026 | A.15 | Tailscale: ��������� SSH ������, ������� ����� 100.76.223.48 |


---

## 📝 Сессия 2026-05-24 — Синхронизация правил бота (EMMBASE-зоны)

**Контекст:** отчёт о 3 расхождениях между правилами и реальным поведением бота на VPS.

**Корень проблемы #1 (главное):** в `~/.openclaw/workspace/AGENTS.md` правило «изменение конфигов вне workspace → спроси» перебивало разрешение из `EMMBASE_OPS.md`. Vault `/home/clawd/emmbase` лежит вне workspace, поэтому бот трактовал запись в КЛИЕНТЫ/ и life/ как «вне workspace → спроси» и осторожничал («только по твоей команде»). Простой ре-синк не помог бы — файлы уже были идентичны.

**Что сделано:**
- `EMMBASE_OPS.md` v18.05 → v24.05: архитектура разбита на 🟢 «Зоны записи (без спроса)» (inbox/, КЛИЕНТЫ/, КЛИЕНТЫ-АН/, life/) и 🔴 «Зоны Claude (не писать)». В 🔴 добавлены ранее отсутствовавшие WIKI/, agents/, content/, cowork_outputs/, RAW/. Новый раздел ⛔ — запрет workspace/prompts/.
- `AGENTS.md`: в обоих блоках принятия решений («External vs Internal» + «Decision Framework») рабочие зоны EMMBASE явно переведены в «без спроса», конфиги OpenClaw и зоны Claude — в «спроси».
- `workspace/prompts/neurotranscriber.md` → перенесён в `emmbase/inbox/2026-05-24_промт-нейротранскрибатор.md`, папка prompts/ удалена.
- Канон `emmbase/agents/openclaw-bot-системный-промт.md` обновлён до v24.05 (→ Syncthing → C:/PROJECTS/EMMBASE/).

**Развёрнуто:** VPS (~/.openclaw/workspace + ~/emmbase/agents), бэкапы оригиналов `*.bak-<ts>`. Бот перезагружен (`systemctl --user restart openclaw-gateway`, active). Deck закоммичен: `992f667`.

**Архитектурный вывод (важно на будущее):** правила бота живут в `~/.openclaw/workspace/` (конфиг OpenClaw), а база знаний — в `~/emmbase/` (Obsidian vault, Syncthing). Это РАЗНЫЕ места. Канон-промт в vault — справочник для Claude, бот его не грузит; бот грузит SOUL/AGENTS/EMMBASE_OPS/USER/TOOLS из workspace.

| Дата | Сессия | Что сделано |
|---|---|---|
| 24.05.2026 | Bot rules sync | EMMBASE-зоны, фикс write-without-ask для КЛИЕНТЫ/life, запрет prompts/, перезагрузка бота |


---

## 📝 Сессия 2026-05-28 — v2: единая точка входа inbox/ (откат 24.05)

**Контекст:** обновлённый канон `C:\PROJECTS\EMMBASE\agents\openclaw-bot-системный-промт.md` v2 от 28.05 (создан Claude в другой сессии). Новая логика: ВСЁ в `inbox/`, бот не маршрутизирует, Claude — единственный, кто разносит файлы по базе.

**Что изменилось vs 24.05:**
- Прошлая правка 24.05 (разрешение боту писать в `КЛИЕНТЫ/`, `КЛИЕНТЫ-АН/`, `life/` без спроса) **отменена**.
- Теперь единственная зона записи — `inbox/`. Прямая запись в КЛИЕНТЫ/life/WIKI/* и куда угодно ещё — запрещена.
- Расширен формат файла в inbox/: добавлены обязательные поля `# Относится к:` и `# Срочность:` (🔴/🟡/🟢).
- Добавлены новые типы: решение, контент, прогноз, промт, личное.

**Файлы:**
- `~/.openclaw/workspace/EMMBASE_OPS.md` v24.05 → v28.05 v2 (полная переработка под inbox-only).
- `~/.openclaw/workspace/AGENTS.md`: оба блока решений переведены на «inbox/ — единственная точка входа», КЛИЕНТЫ/life вернулись в «спроси / запрещено».
- `~/emmbase/agents/openclaw-bot-системный-промт.md` — уже v2 (Syncthing с локальной `C:\PROJECTS\EMMBASE\`).

**Развёрнуто:** VPS, бэкапы `*.bak-<ts>`, gateway перезагружен (`systemctl --user restart openclaw-gateway`, active).

**Архитектурный сдвиг:** модель ответственности упростилась. Бот — только захват (транскрипция + разметка в inbox). Claude — единственный организатор. Это устраняет риск конфликтов записи и упрощает revision history (один формат, одна папка).

| Дата | Сессия | Что сделано |
|---|---|---|
| 28.05.2026 | Bot rules v2 | inbox-only, расширенная разметка, откат прав КЛИЕНТЫ/life от 24.05 |


---

## 📝 Сессия 2026-05-29 — Разбор рапорта бота (изменения настроек)

**Контекст:** бот положил в `inbox/` рапорт `2026-05-29_изменения-настроек.md` с 5 заявленными изменениями своей конфигурации, просит подтверждения.

**Решения Руслана:** все 5 оставить как есть, кроме п.4a (восстановить целостность архитектуры vault) и п.2 (удалить задачу про транскрипты Фаворит).

**Что выяснилось при разведке VPS:**
- ❌ `~/emmbase/workspace/` — папки **не существовало** (бот заявил, что создал — на деле нет).
- ✅ `~/.openclaw/workspace/трекер-активных-задач.md` — лежит в правильном месте.
- ✅ `~/.openclaw/state/active-tasks.json` — в правильном месте, версия 1, одна тестовая задача `done`.
- ❌ `~/emmbase/inbox/2026-05-29_фаворит-транскрипты.md` — файла **не существует** (бот его не создавал).

**Итог:** никаких файловых правок на VPS не потребовалось — архитектура **уже целая**, бот в рапорте описал намерения, а не факты.

**Что сделано:**
- Рапорт дополнен резолюцией и перемещён `~/emmbase/inbox/` → `~/emmbase/_archive/inbox/` (через локальную Windows-копию, Syncthing донёс).
- В долговременную память добавлена feedback-запись [[verify-bot-reports-on-vps]] — правило всегда проверять реальное состояние VPS прежде чем верить рапортам бота, с описанием инцидента 29.05 как причины.

**Что новенького у бота (зафиксировано, но не правилось):**
- Cron-задача утренний прогноз 08:00 МСК (`~/.openclaw/cron/jobs.json` id `f556c692-...`), модель `deepseek-v4-flash`, delivery `telegram:215087477`.
- Система трекинга активных задач: `active-tasks.json` + правила в `~/.openclaw/workspace/трекер-активных-задач.md`. Heartbeat 60 мин (08:00–22:00 МСК) шлёт напоминания если задача `in-progress` > 2ч или дедлайн < 3ч.
- Категоризация запросов (9 категорий) с планом ежемесячного анализа топ-5 паттернов для предложений автоматизаций.

| Дата | Сессия | Что сделано |
|---|---|---|
| 29.05.2026 | Bot report processing | Разбор рапорта бота, разведка VPS, архивация в `_archive/inbox/`, feedback-память о проверке рапортов |
