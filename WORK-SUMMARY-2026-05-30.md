# Резюме работ 30.05.2026 (вечерняя сессия — починка бота)

## Контекст

Утром Codex (от меня же, в предыдущей сессии) включил `sandbox.mode=all + backend=docker`,
после чего бот в Telegram (@Ivanichsila_bot) на каждое сообщение отвечал
`⚠️ Something went wrong while processing your request.`
Эта сессия — починка от начала до конца. Все правки сделаны на live VPS
(`clawd@7808894-zm343910.twc1.net`, SSH alias `clawd-vps-tail`).

## Корневые причины (по порядку обнаружения)

1. **Docker permission denied.** Процесс `openclaw-gateway` (PID 1219275, стартовал
   2026-05-30 17:15 UTC) был запущен ДО того, как юзера `clawd` добавили в группу
   `docker`. У живого процесса `/proc/PID/status` показывал `Groups: 27 100 1000`
   (без 112/docker). Каждый запрос валился на
   `Failed to inspect sandbox image: permission denied while trying to connect to
   the docker API at unix:///var/run/docker.sock`, и все 4 модели каскада умирали
   одной ошибкой → пользователь видел "Something went wrong".

2. **OpenAI Codex token истёк.** Static manual token `ac_V8Ehg...8TQdUVFc` отвергался
   Codex app-server'ом с `failed to set external auth: invalid ID token format`.

3. **MiniMax — нет денег.** Провайдер вернул `insufficient balance (1008)`,
   openclaw сам поставил холд `[disabled:billing 5h]`.

4. **OpenAI блокирует RU IP.** VPS у TimeWeb (RU). Direct `api.openai.com` отвечает
   `403 unsupported_country_region_territory`, Codex auth тоже.

5. **`openai/gpt-5` через ChatGPT Codex недоступен.** Codex/ChatGPT-аккаунт
   предоставляет только `gpt-5.5`. Прямой `gpt-5` живёт только через платный OpenAI
   API (который тоже region-blocked для RU).

## Что сделано на VPS (всё **live**, локальный config НЕ менялся)

### 1. Группа docker для openclaw-gateway

```
systemctl --user stop openclaw-gateway
sudo systemctl restart user@1000.service     # пересоздаёт PAM-сессию с новыми группами
# linger=yes → user manager сам поднимается, gateway автозапускается
```

Проверка: `cat /proc/$(systemctl --user show -p MainPID --value openclaw-gateway)/status | grep ^Groups` → должно содержать **112** (docker).

### 2. Снят cooldown MiniMax + ЗАМЕНЁН ключ (31.05)

⚠️ Важная история: 30.05 пополнил «подписку $20» на minimax — оказалось это Chat Plus,
а не API balance. API продолжал давать `insufficient balance (1008)`. Решение —
**новый ключ от другого аккаунта/тарифа**, где деньги уже зачислены на API. Текущий
рабочий ключ начинается на `sk-cp-t25N6U...` (формат `sk-cp-...`, не `sk-api-1...`).

Если нужна замена ключа — править в ДВУХ местах (legacy дубль в `models.json` имеет
приоритет над `auth-profiles.json` при реальном API-вызове):

```bash
# при остановленном gateway, NEW=<новый-ключ>
python3 <<'PY'
import json
NEW = 'sk-...'

p1 = '/home/clawd/.openclaw/agents/main/agent/models.json'
d1 = json.load(open(p1))
d1['providers']['minimax']['apiKey'] = NEW
if 'minimax-cn' in d1['providers']:
    d1['providers']['minimax-cn']['apiKey'] = NEW
json.dump(d1, open(p1,'w'), indent=2)

p2 = '/home/clawd/.openclaw/agents/main/agent/auth-profiles.json'
d2 = json.load(open(p2))
d2['profiles']['minimax:global']['apiKey'] = NEW
json.dump(d2, open(p2,'w'), indent=2)
PY
```

Проверить новый ключ ДО прописывания в config:

```bash
curl -X POST 'https://api.minimax.io/anthropic/v1/messages' \
  -H "x-api-key: $NEW" -H 'anthropic-version: 2023-06-01' \
  -H 'content-type: application/json' \
  -d '{"model":"MiniMax-M2.7","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}'
# 200 + base_resp.status_msg=success → OK
# {"error":...,"insufficient balance (1008)"} → не тот аккаунт/без баланса
```

### 2a. Снятие cooldown в auth-state.json (если стоит)

```bash
# при остановленном gateway
python3 -c '
import json
p="/home/clawd/.openclaw/agents/main/agent/auth-state.json"
d=json.load(open(p))
mm=d["usageStats"]["minimax:global"]
mm.pop("disabledUntil", None); mm.pop("disabledReason", None)
mm["errorCount"]=0; mm["failureCounts"]={}; mm.pop("lastFailureAt", None)
json.dump(d, open(p,"w"), indent=4)
'
```

### 3. Удалён сломанный manual Codex профиль

При остановленном gateway:

```bash
python3 -c '
import json
p="/home/clawd/.openclaw/agents/main/agent/auth-profiles.json"
d=json.load(open(p))
d["profiles"].pop("openai-codex:manual", None)
json.dump(d, open(p,"w"), indent=2)
'
```

### 4. OAuth для Codex через Tor (главный фикс auth)

На VPS уже работает Tor (порт SOCKS5 `127.0.0.1:9050`) и Privoxy (HTTP
`127.0.0.1:8118`), оба `systemctl is-active` → active.

**Команда логина (нужны env-переменные на прокси для OAuth flow):**

```bash
HTTPS_PROXY=http://127.0.0.1:8118 \
HTTP_PROXY=http://127.0.0.1:8118 \
ALL_PROXY=socks5h://127.0.0.1:9050 \
/home/clawd/.npm-global/bin/openclaw models auth login --provider openai-codex
```

Дальше: команда выведет URL `https://auth.openai.com/oauth/authorize?...`. Открыть
в браузере → залогиниться в ChatGPT-аккаунт `auto.rusland@gmail.com` → нажать
Authorize → браузер редиректит на `http://localhost:1455/auth/callback?code=...`
(покажет ERR_CONNECTION_REFUSED, это нормально). Скопировать **полный URL из адресной
строки** браузера (Ctrl+L → Ctrl+C), ОБЯЗАТЕЛЬНО через Notepad убедиться что одна
строка без переносов, вставить в SSH-приглашение `Paste the authorization code (or
full redirect URL):`, Enter.

Сохраняет профиль `openai-codex:auto.rusland@gmail.com` (oauth) в
`~/.openclaw/agents/main/agent/auth-profiles.json`. Refresh token продлевает себя
автоматически (текущая expiration 2026-06-09).

**Если перенос строки в URL** → State mismatch.
**Если пропущены env-переменные** → `unsupported_region`.

### 5. Прокси для gateway service (inference тоже через Tor)

Создан systemd drop-in `~/.config/systemd/user/openclaw-gateway.service.d/proxy.conf`:

```ini
[Service]
Environment="HTTPS_PROXY=http://127.0.0.1:8118"
Environment="HTTP_PROXY=http://127.0.0.1:8118"
Environment="NO_PROXY=localhost,127.0.0.1,::1,api.telegram.org,api.deepseek.com,api.minimax.io,gonka-gateway.mingles.ai,openrouter.ai,api.tavily.com,api.groq.com,console.groq.com,api.openrouter.ai"
```

`NO_PROXY` критичен: без него Telegram/DeepSeek/MiniMax/Gonka/OpenRouter/Groq тоже
пойдут через Tor, что замедлит/сломает их (особенно Telegram polling и Groq Whisper
для транскрипции voice — Groq отвечает 404 на Tor exit nodes).

**Важная история 31.05:** забыли добавить `api.groq.com` в NO_PROXY → транскрипция
voice в Telegram перестала работать с ошибкой `media-understanding: audio: failed
reason=Audio transcription failed (HTTP 403)`. Бот тогда в чате сказал
«groq_api_key не найден» — это была неправильная гипотеза, ключ был валиден,
проблема в proxy routing. Лечится одной строкой NO_PROXY.

Применить:

```bash
systemctl --user daemon-reload
systemctl --user restart openclaw-gateway
# verify:
cat /proc/$(systemctl --user show -p MainPID --value openclaw-gateway)/environ \
  | tr '\0' '\n' | grep -iE 'PROXY|NO_PROXY'
```

### 6. Модели: primary и fallbacks

```bash
/home/clawd/.npm-global/bin/openclaw models set openai/gpt-5.5
/home/clawd/.npm-global/bin/openclaw models fallbacks clear
/home/clawd/.npm-global/bin/openclaw models fallbacks add 'deepseek/deepseek-v4-flash'
/home/clawd/.npm-global/bin/openclaw models fallbacks add 'minimax/MiniMax-M2.7'
/home/clawd/.npm-global/bin/openclaw models fallbacks add 'gonka/Qwen/Qwen3-235B-A22B-Instruct-2507-FP8'
```

**Итоговое состояние (после правок 31.05 — оптимизация latency):**
- Default: `deepseek/deepseek-v4-flash` (быстрый, без Tor-латенси)
- Fallbacks: `openai/gpt-5.5`, `minimax/MiniMax-M2.7`, `gonka/Qwen/Qwen3-235B-A22B-Instruct-2507-FP8`

`openai/gpt-5.5` остаётся в каскаде как «думающий fallback» для тяжёлых задач,
но primary дёрнут на deepseek чтобы простые вопросы не ждали по 30-90 сек через Tor.

⚠️ **НЕ ставить `openai/gpt-5`** — Codex/ChatGPT-аккаунт его не предоставляет,
запрос вернёт `400 invalid_request_error: 'gpt-5' model is not supported when using
Codex with a ChatGPT account.`

### 6a. Cron-задачи

Обе используют `--model openai/gpt-5.5` явно (per-job override обходит default):

| ID | Name | Schedule | Назначение |
|----|------|----------|------------|
| `f556c692-...` | `Утренний-прогноз` | `0 5 * * * @ Europe/Moscow` (08:00 МСК) | астрология + задачи дня |
| `380a8653-...` | `pattern-analysis-weekly` | `0 9 * * 0 @ Europe/Moscow` (Вс 09:00 МСК) | анализ паттернов запросов |

**Если перенастраиваешь утренний прогноз через `cron edit` — НЕ забудь явно указать**
`--model openai/gpt-5.5`, иначе унаследует старый `openai/gpt-5` (был в payload до 31.05) и упадёт.

### 6b. Sandbox workspaceAccess

Codex (предыдущая сессия) поставил `workspaceAccess: none` — это ломало cron утренней
сводки на `Write: /workspace/bazi_calc.py failed` и блокировало запись задач ботом в
`~/.openclaw/state/active-tasks.json`. Изменено на `rw`:

```bash
python3 -c '
import json
p="/home/clawd/.openclaw/openclaw.json"
d=json.load(open(p))
d["agents"]["defaults"]["sandbox"]["workspaceAccess"]="rw"
json.dump(d, open(p,"w"), indent=2)
'
# Затем пересоздать контейнер sandbox чтобы новый config подхватился:
/home/clawd/.npm-global/bin/openclaw sandbox recreate --all --force
```

Допустимые значения: `"none"`, `"ro"`, `"rw"` (НЕ `"read-write"` — config validation отвергнет).

### 6c. Правило записи задач — где жёстко прописано

- `~/.openclaw/workspace/SOUL.md` (раздел `## Правила базовые`, первая строка): императив
  «**Перед началом любой задачи** — записать её в `~/.openclaw/state/active-tasks.json`».
- `~/.openclaw/workspace/трекер-активных-задач.md` — полный регламент (категории, структура
  JSON-записи, heartbeat-проверки, ссылка на weekly cron).

Если recovery — оба файла нужно восстановить иначе бот перестанет писать задачи и
weekly анализ паттернов окажется бесполезным.

## Файлы на VPS, тронутые этой сессией

| Путь | Что изменено |
|------|--------------|
| `~/.openclaw/openclaw.json` | primary `openai/gpt-5.5`, fallbacks `[deepseek-v4-flash, minimax, gonka]`. Утренние правки Codex (sandbox docker, owner ID, Qwen deny) сохранены. |
| `~/.openclaw/agents/main/agent/auth-profiles.json` | удалён `openai-codex:manual`, добавлен `openai-codex:auto.rusland@gmail.com` (OAuth) |
| `~/.openclaw/agents/main/agent/auth-state.json` | сброшен cooldown `minimax:global` |
| `~/.config/systemd/user/openclaw-gateway.service.d/proxy.conf` | **новый** drop-in с HTTPS_PROXY/HTTP_PROXY/NO_PROXY |
| `~/.openclaw/openclaw.json.bak` | автоматический бэкап от `openclaw models set/fallbacks` (последний) |

## Что НЕ менялось

- Локальный `c:\PROJECTS\COMANDOS\config\openclaw.json` — старый primary (`openai/gpt-5`).
  **Если запустить `scripts/deploy.sh` — он откатит VPS на gpt-5 и сломает auth chain снова.**
  Перед deploy нужно либо синхронизировать локальный config с тем что сейчас на VPS,
  либо deploy.sh скорректировать.
- Docker image `comandos-openclaw-sandbox:bookworm-slim` — без изменений.
- `~/.openclaw/scripts/watchdog.sh` — без изменений.
- Cron утреннего прогноза — без изменений.

## Recovery после полного дефолта VPS

1. Поставить openclaw, восстановить config и agent dir из бэкапа (`*.bak`).
2. Убедиться, что юзер в группе docker: `groups clawd` → должен быть `docker`. Если
   нет — `sudo usermod -aG docker clawd && sudo systemctl restart user@1000.service`.
3. Tor + Privoxy: `systemctl is-active tor` и `ss -ntlp | grep -E ':9050|:8118'`.
   Если нет — поставить: `sudo apt install tor privoxy`; для Privoxy в
   `/etc/privoxy/config` должна быть строка `forward-socks5t / 127.0.0.1:9050 .`.
4. Восстановить drop-in proxy: см. секцию 5 выше.
5. OAuth для Codex: см. секцию 4 выше (нужен браузер с доступом к
   `auto.rusland@gmail.com` ChatGPT).
6. Восстановить cooldown'ы в `auth-state.json` (если есть устаревшие): см. секцию 2.
7. Применить primary/fallbacks: см. секцию 6.
8. `systemctl --user daemon-reload && systemctl --user restart openclaw-gateway`.
9. Проверить:
   ```
   /home/clawd/.npm-global/bin/openclaw models status | head -5
   cat /proc/$(systemctl --user show -p MainPID --value openclaw-gateway)/environ \
       | tr '\0' '\n' | grep -E 'PROXY|NO_PROXY'
   ```

## Известные хрупкости

- **OpenRouter в NO_PROXY**, но если придётся гонять gpt через openrouter — убрать
  его из NO_PROXY (он сам ходит к OpenAI правильно).
- **Tor exit nodes меняются**. Если OAuth внезапно начнёт давать `unsupported_region`
  — это значит Tor выкатил exit node в санкционной зоне. Перезапустить Tor:
  `sudo systemctl restart tor`, попробовать снова.
- **OAuth token истечёт 2026-06-09**. Refresh должен работать автоматически, но если
  не сработает — повторить OAuth login.
- **Локальный config не синхронизирован**. См. предупреждение выше про deploy.sh.
- **Telegram DNS warnings** в логе — фоновый шум IPv6 проблемы DNS, не влияет на
  работу (бот сам fallback на IPv4 IP).

## Утренние правки (от предыдущей сессии Codex 29-30.05) — что сохранено

Полное описание — в git history (`a40babe`, `11134d7`, `a5c0735`, `f97a84d`,
`af63bbe`, `bfad5d4`). Кратко: owner ID `215087477`, sandbox docker, Qwen deny
web/browser, watchdog без hardcoded token, status scripts с полным путём к openclaw.
Эти изменения остались в силе.
