---
name: openclaw-vps-doctor
description: "Диагностика и обслуживание бота «Иваныч» (openclaw на VPS в Москве): бот молчит, не отвечает, потерял инструменты, сломался после обновления, не работает поиск/голосовые/календарь/бэкапы. Используй при любой жалобе на работу бота, а также перед правкой openclaw.json, обновлением версии и настройкой прав агента."
---

# Иваныч: диагностика и обслуживание

Операционный справочник по личному боту на VPS. Собран из разборов реальных
поломок 05–07.2026. **Главное правило: проверяй фактами, не выводами** — ни моими
прошлыми, ни отчётами самого бота (он описывает намерения как результат).

## Доступ и устройство

```bash
ssh clawd-vps-tail          # Tailscale, пользователь clawd; связь рвётся — повторяй с -o ConnectTimeout=45
```

| Что | Где |
|---|---|
| Служба | `systemctl --user openclaw-gateway` (user unit, не системный) |
| Конфиг | `~/.openclaw/openclaw.json` |
| CLI | `~/.npm-global/bin/openclaw` (в PATH может не быть) |
| Правила бота | `~/.openclaw/workspace/` — **вложенный git-репо**, ветка `bot-rules` |
| База знаний | `~/emmbase/`, бот пишет **только** в `inbox/` |
| Скрипты и cron | `~/.openclaw/scripts/`, копии в репо `deploy/scripts/` |
| Ключи моделей | SQLite `~/.openclaw/agents/main/agent/openclaw-agent.sqlite`, таблица `auth_profile_store` |

Логи: `journalctl --user -u openclaw-gateway`. Шум `exec: elevated` отфильтровывай.

---

## 1. «Бот молчит» — порядок проверки

Четыре известных режима отказа. Идти сверху вниз, **не перезапуская вслепую**.

```bash
ssh clawd-vps-tail 'systemctl --user is-active openclaw-gateway
  ls ~/.openclaw/telegram/ingress-spool-default/ | wc -l
  tail -5 ~/.openclaw/logs/telegram-watchdog.log
  timeout 120 ~/.npm-global/bin/openclaw channels status'
```

| Признак | Причина | Лечение |
|---|---|---|
| файлы в ingress-spool старше 15 мин, `update-offset` не двигается | умер потребитель очереди внутри процесса | рестарт gateway (перезапуск канала не помогает) |
| серия `fetch timeout … getMe`, нет успешного трафика | протух пул соединений после обрыва Tor | рестарт gateway |
| `channels status` → `stopped`, `error: restart-loop breaker tripped` | 4+ неудачных старта за 5 мин подавили автозапуск канала | подождать 5 мин без падений → один чистый рестарт |
| служба `failed`, в логе `Invalid config … status=78/CONFIG` | битый конфиг | починить конфиг, затем `systemctl --user reset-failed` перед стартом |

Сторож `telegram-watchdog.sh` (cron `*/5`) ловит все четыре: неактивную службу,
зависшую очередь, серию таймаутов, подавленный канал, плюс холостые рестарты
health-monitor. Уведомляет владельца сам, с первой неудачи восстановления.

⚠️ После рестарта убедись, что очередь разошлась (`ingress-spool` пуст) и в логе
есть `outbound send ok`. «Служба active» ничего не доказывает.

---

## 2. «У бота нет инструментов»

Жалобы вида «недоступны `memory_search`, `curl`, `web_search`». Смотри в логе
строки `[agents/tool-policy]` — там прямо написано, что и каким слоем вырезано.

**Три независимых слоя:**

1. `tools.sandbox.tools.deny` — по умолчанию режет `cron, gateway, nodes`.
2. `tools.sandbox.tools.alsoAllow` — **белый список**: всё, чего в нём нет,
   вырезается в песочнице.
3. `gateway sender owner-only` — `cron` доступен **только владельцу**
   (`commands.ownerAllowFrom`).

⚠️ **Из-за третьего слоя консольный тест врёт.** `openclaw agent --agent main`
не имеет личности владельца → `cron` «недоступен», даже когда всё настроено
верно. Такие вещи проверяются **только реальным сообщением в Telegram**.

**Песочница работает без сети** (`NetworkMode: none`) — это защита, а не поломка.
`curl`/`wget` внутри неё бесполезны, ставить их в образ бессмысленно.
Интернет только через host-инструменты: `web_fetch` (замена curl), `web_search`.

Почему путаница: в переписке с владельцем `curl` работает — там `tools.elevated`
выполняет команды на хосте. В задачах по расписанию этих прав нет.

**В cron-задачах отправлять ничего не надо** — настроено `announce -> telegram`,
итоговый ответ агента уходит сам. Инструмент `message` в песочнице закрыт.

---

## 3. Сеть: что доступно из Москвы

VPS у TimeWeb (РФ). Перед внесением хоста в `NO_PROXY` **проверяй обе ветки**:

```bash
curl -s --max-time 20 -o /dev/null -w "прямо: %{http_code}\n" https://ХОСТ/
curl -s --max-time 40 -x http://127.0.0.1:8118 -o /dev/null -w "через Tor: %{http_code}\n" https://ХОСТ/
```

| Сервис | Напрямую | Через Tor | Как ходит |
|---|---|---|---|
| api.deepgram.com, api.minimax.io | ✅ | ✅ | напрямую, в `NO_PROXY` |
| api.search.brave.com | ✅ | ✅ | напрямую |
| openrouter.ai, api.openai.com | ❌ 403 | ✅ | через privoxy `127.0.0.1:8118` |
| api.tavily.com | ❌ 403 | ✅ | **плагин игнорирует прокси** → выключен |
| api.telegram.org | ❌ | — | transparent SOCKS: iptables + redsocks |

**Codex (`chatgpt.com/backend-api`) — работает, но держится на двух костылях.**
openclaw ходит туда мимо всех настроек прокси, поэтому трафик заворачивается
прозрачно: `codex-tor-route.sh` (cron `17 * * * *`) держит `iptables REDIRECT`
адресов chatgpt.com на redsocks и **закрывает IPv6** (`ip6tables REJECT` на
`2a06:98c1::/32`) — иначе соединение уходит по IPv6 мимо правил v4.

Настройки прокси на этот путь **не влияют**, не трать на них время:
`HTTPS_PROXY`/`ALL_PROXY` в systemd, те же переменные перед CLI,
`models.providers.openai.request.proxy`, конфиг плагина `codex`.

⚠️ Сообщение **«You've reached your Codex subscription usage limit» врёт.** Так
openclaw переводит и 403 по региону, и 429 `insufficient_quota` от мёртвого
платёжного ключа. Прежде чем верить — проверь личный кабинет ChatGPT (лимит
обычно не тронут) и сделай прямой запрос к API (см. п.8).

---

## 4. Модели и ключи

**Все ключи владельца подписочные.** Проверять их обычным API-вызовом
бессмысленно: «insufficient balance», «quota exceeded», «usage limit» там штатный
ответ, а не признак мёртвого ключа.

- ChatGPT Plus **не покрывает** платформенный ключ `sk-proj-…` — это отдельный
  продукт с отдельной оплатой. На сервере лежат оба доступа, они не связаны.
- MiniMax Coding Plan (`sk-cp-`) работает через `api.minimax.io/anthropic`.
- «Empty response» от MiniMax лечится сбросом раздутой сессии (`/new`), не тарифом.

Рабочая цепочка: primary `minimax/MiniMax-M2.7`, fallback
`openrouter/google/gemini-2.5-flash` → `gonka/Qwen3-235B` → `openai/gpt-5.5`
(последним, пока Codex недоступен).

⚠️ **Codex ищет профиль строго с id `openai:manual`** (иначе `Codex app-server
auth profile "openai:manual" was not found`). По умолчанию там лежал мёртвый
платёжный ключ — из-за этого подписка Plus не использовалась вообще. Сейчас под
этим id лежит **копия OAuth-профиля подписки** (`type: oauth`, план `plus`).
Не «наводи порядок», заменяя его на api_key — сломаешь Codex.

Ключи живут в SQLite, **не** в `auth-profiles.json` (там остались старые копии —
полезны как источник при миграции). Восстановление без интерактива:

```bash
printf '%s\n' "$KEY" | openclaw models auth paste-api-key --provider <имя>
```

OAuth-профили (Codex) через `paste-token` не восстанавливаются, а `login` требует
TTY. Переносить напрямую: `auth_profile_store`, `store_key='primary'`,
`store_json.profiles` — структура совпадает со старым `auth-profiles.json`.

---

## 5. Правка конфига и обновление

- **Перед правкой** — копия: `cp openclaw.json openclaw.json.bak-$(date +%s)`.
- **Плагины не принимают произвольные поля.** Ключ Brave кладётся в
  `plugins.entries.brave.config.webSearch.apiKey` + нужна секция
  `tools.web.search = {enabled, provider, maxResults, timeoutSeconds}`.
  Неверное поле роняет старт с `status=78/CONFIG`.
- **Overlay провайдера** возможен только для встроенных; для плагинных
  (`openai-codex`) требует `baseUrl` и `models`, иначе старт падает.
- **Не более ~4 рестартов за 5 минут** — иначе `restart-loop breaker` подавит
  автозапуск канала Telegram (см. п.1). Между правками делай паузы.
- После падений: `systemctl --user reset-failed openclaw-gateway` перед стартом.
- Ждать порт, а не «спать наугад»:
  `for i in $(seq 1 20); do ss -ltn | grep -q 18789 && break; sleep 10; done`

**Обновление openclaw** (грабли 2026.7.x):
1. `npm` целится в `/usr` → нужен `--prefix /home/clawd/.npm-global`.
2. Старт **ждёт подтверждения с клавиатуры** на предупреждениях о неустановленных
   плагинах — под systemd выглядит как вечное зависание без логов. Убрать из
   `plugins.allow`/`entries` то, что не установлено.
3. Ключи провайдеров **не мигрируют** (см. п.4).
4. Каждая неудачная попытка берёт аренду миграции на ~5 минут — рестарты подряд
   бесполезны.

---

## 6. Голос и транскрипция

Звонки — AMR-WB **моно**, обрабатывает host-скрипт `transcribe-audio-watcher.sh`
(cron ежеминутно). Голосовые из Telegram идут другим путём — встроенным
media-understanding.

- DeepGram **обязателен** `language=ru`: без него `nova-3` даёт пустой транскрипт.
- Диаризация: `diarize=true` на моно видит одного спикера. Нужно
  `diarize_model=latest&utterances=true`, совмещать с `diarize` нельзя (400).
- Собирать из `results.utterances[]`, а не из плоского `transcript`, и **склеивать**
  подряд идущие реплики одного говорящего (иначе 491 обрывок на 24 минуты).
- Голосовой якорь `~/.openclaw/media/voice-anchor-ruslan.ogg` клеится встык
  (без паузы — пауза ломает связку) и отрезается **пословно**.

---

## 7. Бэкапы

Два репозитория, оба уходят в приватный `autorusland-ai/openclaw-backup`:

| Ветка | Что | Особенность |
|---|---|---|
| `main` | `~/.openclaw` + `openclaw.json` | шифруется git-crypt (магия `\x00GITCRYPT\x00`) |
| `bot-rules` | `~/.openclaw/workspace` | вложенный репо, нужен `git -C` |

⚠️ В `workspace/` лежат `media/` (записи звонков клиентов) и `openclaw-config.json`
с ключами открытым текстом — исключены через `.gitignore`. Перед пушем прогоняй
поиск по префиксам `sk-proj-`, `sk-or-v1`, `gsk_`, `AIzaSy`, `GOCSPX`, `github_pat_`.

`git-crypt status` без аргумента виснет на untracked-папках — проверяй точечно.
Локальные снимки: `pre-update-backup.sh` (cron вс, ротация 8).

---

## 8. Как работать, чтобы не сломать

- **Проверяй эмпирически.** Гипотезу про причину подтверждай измерением
  (curl, прямой вызов API, лог), а не рассуждением. Половина разборов в этом
  проекте опровергла «очевидный» диагноз.
- **Смотри, уходит ли трафик вообще.** Если сомневаешься, доходит ли запрос до
  сервиса — посмотри SYN-пакеты во время попытки:
  `sudo timeout 45 tcpdump -nn -i any 'tcp[tcpflags] & tcp-syn != 0 and port 443'`.
  Пусто = openclaw отказал локально (кулдаун, отсутствующий профиль), и чинить
  надо не сеть. Этот приём сэкономил бы час возни с прокси.
- **Сравнивай прямой запрос и через Tor** — так отличаешь гео-блок (403 прямо,
  осмысленный ответ через прокси) от настоящей проблемы с ключом или квотой.
  Осмысленная ошибка API (400 «Stream must be set to true») — признак, что
  авторизация и регион в порядке.
- **Не верь отчётам бота** — он описывает намерения как факты.
- **Изолированный тест вместо боевого**: копия скрипта с подменёнными путями в
  `/tmp` и `TG_TOKEN=TEST_INVALID_NO_SEND`, чтобы не слать владельцу мусор.
- **Осторожно с `pkill -f`** из ssh-команды: шаблон совпадёт с собственной
  строкой запуска и убьёт сессию. Спасает класс символов: `git-cryp[t] statu`.
- **Правки на VPS дублируй в репо** `deploy/scripts/` и сверяй хешем.
- **Скрипты защищены от записи** (с 15.08.2026, после того как бот сломал рабочий
  скрипт и пытался обновить платформу). `~/.openclaw/scripts/` — `root:clawd`,
  файлы 750; `~/.npm-global/lib/node_modules` — `root:clawd`; в sudoers запрещены
  `npm/npx/apt/apt-get/dpkg/pip/pip3/snap`. Выкладка теперь в два шага:
  `scp … :/tmp/x.sh` → `sudo cp /tmp/x.sh ~/.openclaw/scripts/ && sudo chown root:clawd … && sudo chmod 750 …`.
  Логи скриптов лежат в том же каталоге и остались writable — дозапись в
  существующий файл прав на каталог не требует, cron из-за защиты не ломается.
- Помни про часовые пояса: cron на VPS в UTC, владелец живёт по Москве.

## История разборов

- [WORK-SUMMARY-2026-07-26.md](../../../WORK-SUMMARY-2026-07-26.md) — восстановление после
  двухсуточного молчания, аудит, обновление платформы.
- [WORK-SUMMARY-2026-07-27.md](../../../WORK-SUMMARY-2026-07-27.md) — права инструментов,
  поиск, Codex, повторяющиеся задачи.
- [deploy/WORK-HISTORY.md](../../../deploy/WORK-HISTORY.md) — хронология с мая.
