# 28.09.2026 — промт v8, связность v2, обновление openclaw 2026.9.6, уход с OpenRouter

Сессия по навыку [openclaw-vps-doctor](.claude/skills/openclaw-vps-doctor/SKILL.md).
Состояние на входе: openclaw 2026.9.2, Node 24.15, бот жив (служба 11 дней без
падений, очередь пуста), последняя версия в npm — 2026.9.6.

## Итог

| # | Что | Результат |
|---|---|---|
| 1 | Системный промт v8 на VPS | ✅ `bot-rules` `877d1fc` |
| 2 | Связность v2 (`контроль-сессии.py --report`) вместо `проверка-связности.sh` | ✅ крон заменён, старый скрипт → `.sh.off` |
| 3 | Строка `Daily Squash` в кроне | ⛔ не сделано — удаление заблокировал классификатор авто-режима; команда для ручного запуска ниже |
| 4 | Доставка задачи `месячная-очистка-мусора` | ✅ `telegram → 215087477` |
| 5 | Обновление openclaw 2026.9.2 → 2026.9.6 | ✅ с Node 24.15 → 24.21 |
| 6 | OpenRouter → gonka | ✅ heartbeat, чек-ин, недельный прогноз, memoryFlush, weekly-digest; генерация картинок удалена |
| 7 | Лимиты памяти службы | ✅ `MemoryHigh=4G`, `MemoryMax=5G` (было 2500M/3G) |

Коммиты на VPS: `bot-rules` `877d1fc` (промт), `main` `9ed32b2` (`openclaw.json`, git-crypt, gitleaks чисто).
Бэкап до обновления: `~/.openclaw/backups/pre-2026.9.6-20260928-143223/` (+ `refresh-144523/`):
`openclaw.json`, обе SQLite (ключи и состояние, через `sqlite3.backup`), `workspace.tgz`,
`scripts.tgz`, crontab, эталонные `plugins/cron/auth/channels` до обновления.
Копия crontab до правок: `~/.openclaw/backups/crontab.bak-20260928-143111`.

## 1. Промт v8

Текста промта в конфиге бота **нет** — правила inbox живут в навыке
`workspace/skills/inbox-saver/SKILL.md` (адаптация канона
`~/emmbase/agents/openclaw-bot-системный-промт.md`; до `~/emmbase` v8 доезжает сам
через Syncthing, но в голову бота — нет). Суть v8 для бота — одно: эталонное имя
ЭММ `etalonnaya-model-marketinga-ip-fedorova` → `etalonnaya-model-marketinga`.

Сделано: обе ссылки в примерах заменены, добавлено правило «Эталонные имена ссылок»,
шапка v5 → v8. Проверено: целевой `knowledge-base/EMM/etalonnaya-model-marketinga.md`
на VPS есть; в mem0 (74 записи) старого имени нет; `AGENTS.md` 28 284 символа при
`bootstrapMaxChars=34000` — обрезки нет.

## 2. Связность v2

По ТЗ `EMMBASE/agents/тз-скрипт-проверки-связности-базы.md` v2.
- Сухой прогон: rc=0, 0,46 с, файл не записан. Вне индекса 46, битых 2, неоднозначных 170.
- Крон `40 3 * * *` → `cd /home/clawd/emmbase && python3 agents/скрипты/контроль-сессии.py --report /home/clawd/.openclaw/state/connectivity-v2.json >> ~/.openclaw/logs/контроль-сессии-report.log 2>&1`.
  Отступление от ТЗ — запись вывода в лог, чтобы сбой не был тихим.
- `проверка-связности.sh` → `проверка-связности.sh.off` (root:clawd, точка отката).
- Первый боевой прогон — 29.09 06:40 МСК. Проверить лог и файл в `inbox/`.

## 3. Daily Squash — осталось руками

`0 23 * * * cd ~/.openclaw && git checkout main && git merge auto/cron --squash && git commit …`
стартует в ту же минуту, что `openclaw-autocommit.sh` → `index.lock: File exists` в
`autocommit.log` (25.09 23:00). Ветки `auto/cron` в схеме бэкапа нет. Из шаблонов
`deploy/configure.sh` и `DEPLOY-GUIDE.md` строка убрана. На VPS выполнить:

```bash
crontab -l | grep -vF "git merge auto/cron --squash" | crontab -
```

## 5. Обновление 2026.9.2 → 2026.9.6

Порядок: бэкап → пауза `telegram-watchdog` в кроне (`#UPDATE-PAUSE`) → стоп шлюза →
Node → ядро → `config validate` → `plugins update --all` → старт → вернуть сторожа.

Грабли (все внесены в навык):
1. **Первая попытка сорвалась:** `EBADENGINE` — 2026.9.6 требует Node `>=24.16.0 <25 || >=26.1.0`.
   npm ничего не поставил, шлюз поднят обратно за ~1,5 мин.
2. `apt-get install --only-upgrade nodejs` (nodesource) → 24.21.0. С ним новый npm,
   который **молча не выполняет install-скрипты** (включая `postinstall-bundled-plugins`
   openclaw). Переустановлено с `--allow-scripts=@google/genai,koffi,protobufjs,openclaw`.
3. Конфиг валиден без миграции → `doctor --fix` **не запускался**.
4. Плагины brave/codex/zai/deepseek/groq/perplexity/tavily → 2026.9.6.
   `openclaw-mem0` остался 1.0.11: обновление требует `--accept-capabilities` (решение владельца), работает.
5. **Старт ~4 мин** вместо ~25 с (отложенные миграции; 66 старых транскриптов
   «Primary transcript header does not match» — исторические, безвредно).
6. **Память ×2:** RSS ~1,6 ГБ (было ~840 МБ). После правки моделей hot reload упёрся в
   `MemoryHigh=2500M` (memory.current включает файловый кэш SQLite) → процесс в D-state,
   непрерывная подкачка, `/health` молчал ~10 мин. Лимиты подняты на лету
   `systemctl --user set-property openclaw-gateway MemoryHigh=4G MemoryMax=5G`, один
   чистый рестарт. После: anon ~1,9 ГБ + file ~1 ГБ, запас есть.

Проверено после: Telegram `running, connected`; очередь пуста; живой ответ агента;
14 профилей ключей (включая `openai:manual`); `SILENT_REPLY_TOKEN = "NO_REPLY"`;
md5 конфига до правок совпал; `gws-cli.py gmail unread-count` работает; ноль
`tool name conflict` и `truncating`. Простой суммарно: ~1,5 мин + ~20 мин.

## 6. OpenRouter

Ключ без денег с 27.09 06:47 (174 `billing error` за сутки, все вытаскивал резерв).
За 7 дней 223 вызова, все `deepseek-chat-v3-0324`, основная масса — heartbeat.

| Что | Было | Стало |
|---|---|---|
| heartbeat (30 мин, 08–22 МСК) | OR deepseek | `gonka/MiniMaxAI/MiniMax-M2.7` |
| Вечерний чек-ин, недельный прогноз | OR deepseek | gonka MiniMax-M2.7 → Kimi-K2.6 → minimax |
| `compaction.memoryFlush` | OR kimi-k2.6 | `gonka/moonshotai/Kimi-K2.6` |
| `weekly-digest.sh` | OR kimi-k2.6 | gonka Kimi-K2.6 (копия в `deploy/scripts/`, sha256 сверен) |
| резерв основного чата | …→ OR deepseek | убран |
| генерация картинок `mediaModels.image` | OR flux / gemini-image | удалена — владелец ею не пользуется |

Осталось на OpenRouter: распознавание картинок `tools.media.models` →
`qwen/qwen-2.5-vl-72b-instruct` — **и оно не работает** (7 отказов за неделю
«Model does not support images», отказ локальный, денег не тратит). Кандидат —
Codex по подписке Plus (`openai:manual`), нужна проверка реальной картинкой.
Также `mcp.servers.browser-use` ходит в OR gemini-flash-lite — Google через OR закрыт по ToS.

## Открытые вопросы владельцу

- [ ] Удалить `Daily Squash` из крона (команда выше).
- [ ] Распознавание картинок: перевести на Codex/Plus?
- [ ] Отключить `/update` и `/restart` в Telegram: самообновление из чата на этом сервере
      требует Node, root и лимитов памяти — почти наверняка положит бота.
- [ ] mem0 1.0.11 → новая версия требует согласия на доступ к переписке.
- [ ] 29.09 после 06:40 МСК — проверить первый боевой отчёт связности v2.

## Справка: что работает без нейросети

Навыки openclaw (8 шт. в `workspace/skills/`) — инструкции для модели, без LLM не
работают. Без LLM: встроенные команды Telegram (`/status`, `/new`, `/reset`, `/stop`,
`/model`, `/tools`, `/tasks`, `/context`, `/usage`, `/restart`, `/update`…) и 23 из 24
host-скриптов по крону (LLM вызывает только `weekly-digest.sh`).
