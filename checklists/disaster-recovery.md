# Runbook: disaster-recovery

> VPS умер, корруптился, удалён, провайдер заблокировал. Восстановить бота на новом сервере **за 30 минут**.
> Источник: блок-14-git-workflow.md, PRO-04-production-hardening.md.

---

## Условия применения

Этот runbook работает, если у тебя есть:
- Этот deck (с `workspace/`, `config/`, `scripts/`) в git-репозитории.
- `.env` локально (или резервная копия).
- Доступ к SSH-ключу (`~/.ssh/clawd_ed25519`).
- Способность купить новый VPS (Hetzner / Beget / DO).

Если что-то из этого утрачено — см. конец файла «Recovery без deck».

---

## Шаги (30 минут)

### Этап 1 — Новый VPS (5 минут)

1. **Hetzner CX22** (€4.99/мес) или эквивалент: Ubuntu 24.04 LTS, 4 GB RAM, 2 vCPU, 40 GB SSD.
2. После создания — запиши новый IP в `.env`: `VPS_IP=...`.
3. Залей публичный ключ:
   ```bash
   ssh-copy-id -i ~/.ssh/clawd_ed25519.pub root@<NEW_IP>
   ```
4. Создай user `clawd` (не работаем под root):
   ```bash
   ssh root@<NEW_IP> 'adduser --disabled-password --gecos "" clawd && usermod -aG sudo clawd && mkdir -p /home/clawd/.ssh && cp /root/.ssh/authorized_keys /home/clawd/.ssh/ && chown -R clawd:clawd /home/clawd/.ssh && chmod 700 /home/clawd/.ssh'
   ```

### Этап 2 — VPS bootstrap (10 минут)

Подключись через `./scripts/connect.sh` (с обновлённым IP), выполни:

```bash
# 1. Обнови систему и поставь базу
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git ufw fail2ban build-essential

# 2. Node 22 LTS (обязательно — OpenClaw v0.9+ требует)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs

# 3. Swap 2 GB (защита от OOM на 4GB VPS, issue #41778)
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# 4. Firewall — только SSH
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw enable

# 5. fail2ban для SSH brute-force
sudo systemctl enable --now fail2ban

# 6. Linger — systemd user-units работают без логина
sudo loginctl enable-linger clawd

# 7. OpenClaw
npm install -g openclaw@latest
# или: curl -fsSL https://openclaw.ai/install.sh | bash

# 8. Подготовка директории
mkdir -p ~/.openclaw/{secrets,workspace,memory,browser-profiles/main,state,logs}
chmod 700 ~/.openclaw/secrets

# 9. Playwright браузер для browser tool
npx playwright install --with-deps chromium
```

### Этап 3 — Восстановление конфига и личности (10 минут)

С локальной машины:

```bash
# 1. Залей deploy
./scripts/deploy.sh
```

Это зальёт `workspace/` и `config/openclaw.json`. Но секреты надо вручную:

```bash
# 2. Залей secrets (Telegram token и UI token)
ssh clawd-vps 'mkdir -p ~/.openclaw/secrets && chmod 700 ~/.openclaw/secrets'

# Telegram bot token из .env → файл на VPS
ssh clawd-vps "echo '${TELEGRAM_BOT_TOKEN}' > ~/.openclaw/secrets/telegram.token && chmod 600 ~/.openclaw/secrets/telegram.token"

# UI token (генерируем новый)
ssh clawd-vps "openssl rand -hex 32 > ~/.openclaw/secrets/ui.token && chmod 600 ~/.openclaw/secrets/ui.token"
```

Все API-ключи (`MINIMAX_API_KEY` и т.п.) подставляются в `openclaw.json` при `deploy.sh` через env-substitution из `.env`.

### Этап 4 — Systemd unit и старт (3 минуты)

```bash
ssh clawd-vps << 'EOF'
mkdir -p ~/.config/systemd/user
EOF

# Залей unit с локалки
scp config/systemd/openclaw-gateway.service clawd-vps:~/.config/systemd/user/

ssh clawd-vps << 'EOF'
systemctl --user daemon-reload
systemctl --user enable --now openclaw
sleep 5
systemctl --user is-active openclaw
EOF
```

### Этап 5 — Qdrant (если используешь vector memory) (2 минуты)

```bash
# Docker
ssh clawd-vps 'curl -fsSL https://get.docker.com | sudo sh && sudo usermod -aG docker clawd'

# Залей docker-compose
scp config/docker-compose.qdrant.yml clawd-vps:~/.openclaw/

# Запусти
ssh clawd-vps 'cd ~/.openclaw && docker compose -f docker-compose.qdrant.yml up -d'
```

### Этап 6 — Верификация и smoke test

```bash
./scripts/status.sh
```

Все галки должны быть зелёные. Telegram smoke-test: «Привет, ты живой?». Должен ответить.

---

## Этап 7 — Воркшоп 3: ручные шаги (OAuth + браузер)

`bootstrap-vps.sh` (этап 7b) уже ставит **Tor**, браузерный стек (Patchright/Xvfb/browser-use форк, Chrome) и Xvfb-unit. Но три вещи требуют **живого TTY/браузера** и делаются вручную:

### 7.1 — Tor (обход геоблока OpenAI)

VPS в РФ → OpenAI отдаёт `403 unsupported_country_region_territory`. Поэтому весь OpenAI-трафик идёт через Tor SOCKS5. Проверь:

```bash
ssh clawd-vps 'systemctl is-active tor && curl -s --socks5 127.0.0.1:9050 https://api.ipify.org; echo'
```
Должен вернуть IP **не из РФ**. В `.env` уже стоит `OPENAI_SOCKS_PROXY=socks5://127.0.0.1:9050`, конфиг подставляет его в `env`.

### 7.2 — Codex OAuth (primary = openai/gpt-5)

Команда требует **интерактивный TTY** (в автоматизации НЕ работает) и проходит OAuth в браузере:

```bash
ssh -t clawd-vps "bash -lc 'openclaw models auth login --provider openai-codex --set-default --device-code'"
```
Откроется ссылка + код → подтверди в браузере под аккаунтом ChatGPT Plus. Проверка: `openclaw models auth list` покажет `openai-codex:...`.

> Если OAuth снова упрётся в гео-403 — убедись, что Tor активен (7.1), либо как fallback используй `openrouter/openai/gpt-5` через `OPENROUTER_API_KEY` (работает без OAuth).

### 7.3 — Google OAuth (Gmail + Calendar MCP)

`GOOGLE_WORKSPACE_REFRESH_TOKEN` живёт ~6 мес и при восстановлении на новом проекте получается заново:

1. Google Cloud Console → проект → OAuth client ID (Desktop) → в `.env`: `GOOGLE_OAUTH_CLIENT_ID`/`SECRET`. Файл client-secrets: `~/.openclaw/secrets/google-oauth.json`.
2. Залей и запусти `scripts/reauth-google.py` с **пробросом порта** (на VPS нет браузера, редирект уходит по туннелю):
   ```bash
   scp -i ~/.ssh/clawd_ed25519 scripts/reauth-google.py clawd@$VPS_IP:~/reauth-google.py
   ssh -t -L 8765:localhost:8765 -i ~/.ssh/clawd_ed25519 clawd@$VPS_IP \
       "~/browser-env/bin/python ~/reauth-google.py"
   ```
   Скрипт напечатает ссылку → открой в браузере на компьютере → дай согласие (отметь Календарь). Scopes: `gmail.readonly`, `gmail.send`, `calendar` (полный read+write, НЕ `calendar.readonly`).
3. Перенеси новый refresh token в `GOOGLE_WORKSPACE_REFRESH_TOKEN` (`.env` + конфиг на VPS — он встречается в `env` И в `mcp.servers.google-workspace.env`), затем рестарт: `systemctl --user restart openclaw-gateway`.
4. Проверка записи: обмен refresh→access токеном и `tokeninfo` должны показать scope `.../auth/calendar`.

### 7.4 — Проверка браузерного стека

```bash
ssh clawd-vps 'systemctl --user is-active xvfb && ~/browser-env/bin/browser-use --version'
```
Оба должны ответить. Скиллы (`web-quick`, `page-reader`, `deep-research`, `browser-agent`, `mail-handler`, `calendar-keeper`) приезжают вместе с `workspace/` при `deploy.sh`. `self-improving-agent` ставится отдельно: `openclaw skills install self-improving-agent`.

---

## Актуализация конфига перед бэкапом

Бот/мастер мог менять `~/.openclaw/openclaw.json` прямо на VPS. Чтобы git-шаблон не отстал, периодически пере-снимай его (секреты автоматически заменяются на `${VAR}`, leak-scan не даст утечь):

```bash
scp -i ~/.ssh/clawd_ed25519 clawd@$VPS_IP:~/.openclaw/openclaw.json /tmp/oc-live.json
python scripts/snapshot-config.py /tmp/oc-live.json   # → перезапишет config/openclaw.json
rm /tmp/oc-live.json
git add config/openclaw.json && git commit -m "sync config snapshot"
```

---

## Что не восстановится автоматически

- **`memory/YYYY-MM-DD.md`** — daily logs бота. Если не делал `./scripts/pull.sh` регулярно — потеряны.
- **Vector memory в Qdrant** — если не было snapshot, начнётся с нуля. Бот «забудет» долгосрочные факты, но `MEMORY.md` восстановится из git.
- **`browser-profiles/`** — куки браузера. Бот заново залогинится в сервисах.
- **`state/`** — last_briefing, last_heartbeat_hash, todo.md. Заполнится по мере работы.

---

## Превенция (делать регулярно)

- **Раз в день** запускай `./scripts/pull.sh` — синкает `memory/` обратно с VPS в локальный git.
- **Раз в неделю** делай Qdrant snapshot:
  ```bash
  ssh clawd-vps 'docker exec openclaw-qdrant tar czf /qdrant/storage/snapshot-$(date +%F).tar.gz /qdrant/storage/collections'
  ```
- **Раз в месяц** — backup всего `~/.openclaw/` через rsync на NAS / S3.

---

## Recovery без deck

Если deck утрачен (git-репо удалён, локалка дохлая):

1. Создай новый deck с нуля (этот же deck из git open-source шаблона).
2. Личность бота: SOUL.md/USER.md/AGENTS.md придётся переписывать. Ботом нельзя «вспомнить» личность — она была в файлах.
3. История памяти: только если у тебя есть Qdrant snapshot или Telegram-чаты с ботом (можно скачать историю и feed на новый instance).

**Урок:** держи deck в git с регулярным push. Потеря — это часы работы, не дни.

---

## Связанные

- `deploy-agent.md` — обычный deploy.
- `emergency-stop.md` — если ещё работает, но нужно остановить.
- `gateway-restart.md` — если daemon живой но тупит.
