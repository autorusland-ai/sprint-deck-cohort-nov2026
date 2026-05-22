# 🎤 Воркшоп 1 — 11 промптов (гибридный путь)

> **AI делает 80% рутины, ты делаешь 1 ключевой шаг руками.**
> Перед началом убедись что вставил `00-meta-prompt.md` в чат с AI.

---

## 🧭 Структура воркшопа

```
ЧАСТЬ А1 — AI делает рутину (5 промптов, ~10 минут)
   П1. Склонировать deck + .env
   П2. SSH-ключ
   П3. Загрузить ключ на VPS
   П4. VPS hardening
   П5. Node 22 + npm + установить OpenClaw
   П6. СТОП — передаю эстафету тебе

   ⏸ ЧАСТЬ А2 — ТЫ САМ в Mac Terminal (~10 минут)
   ssh clawd@VPS_IP
   openclaw onboard   ← интерактивный мастер
   → бот отвечает в Telegram

ЧАСТЬ Б — AI доделывает тонкости (4 промпта, ~10 минут)
   П7. Alias premium / think
   П8. Watchdog
   П9. Картинки
   П10. SOUL.md (личность)
   П11. Финальная самопроверка
```

**Итого**: ~30 минут.

---

## 🟢 ПРЕД-ШАГ — Открой пустую папку в Antigravity (1 мин, ты сам)

ДО первого промпта подготовь рабочую папку:

1. **Создай новую пустую папку** в Finder (например `~/Desktop/Командос`)
2. В Antigravity: **File → Open Folder** → выбери эту папку
3. Убедись что в ней **ничего нет** кроме `.DS_Store` (если есть твои файлы — выбери другую пустую, иначе git clone упадёт)

Теперь Antigravity открыт на твоей рабочей папке. AI будет работать **прямо в ней**.

---

## 📦 ПРОМПТ 1 — Склонировать deck В ТЕКУЩУЮ ПАПКУ + .env

```
Промпт 1: Склонируй deck В МОЮ РАБОЧУЮ ПАПКУ (ту что открыта сейчас в Antigravity).

ШАГ 1 — узнай где мы:
  pwd
  ls -la

ШАГ 2 — клонируй ПРЯМО СЮДА (точка в конце критична!):
  rm -f .DS_Store
  git clone https://github.com/Comandosai/sprint-deck-cohort-nov2026.git .

  ⚠️ Точка в конце = клонировать в ТЕКУЩУЮ папку, не в подпапку.
  Если git ругается «destination path already exists and is not empty» —
  СТОП, спроси меня.

ШАГ 3 — проверь что файлы появились:
  ls -la
  Должно быть: README.md, AGENTS.md, .env.example, .gitignore, .git/,
  workshop-1/, knowledge-base/, standards/, config/, audit/, scripts/,
  checklists/, docs/, skills/, workspace/

ШАГ 4 — теперь ЧИТАЙ файлы:
  1. standards/workshop-1-standard.md — ИСТОЧНИК ИСТИНЫ.
     Прочитай ПОЛНОСТЬЮ. Запомни разделы A-H и критерии ❗/⚠️/💡.
  2. knowledge-base/README.md — индекс known-issues.
  3. config/openclaw.json — эталонный конфиг (для справки).

ШАГ 5 — создай .env:
  cp .env.example .env

ШАГ 6 — скажи мне:
  «вставь свои 9 значений в .env, файл лежит по пути [полный pwd]/.env»
  
  Я открою .env в Antigravity и впишу из Notes:
  VPS_IP, ROOT_PASSWORD, MINIMAX_API_KEY, DEEPSEEK_API_KEY,
  OPENROUTER_API_KEY, GROQ_API_KEY, OPENAI_API_KEY,
  TELEGRAM_BOT_TOKEN, TELEGRAM_USER_ID.

После моего «готово»:
- Проверь .env — минимум 9 непустых VAR=значение
- Покажи список ИМЁН переменных (БЕЗ значений!)
- Кратко (3-5 строк) перескажи ключевые ❗ критерии стандарта
- Скажи «контекст загружен, готов к Промпту 2 (SSH-ключ)»

⛔ ВАЖНО: ВСЁ В ТЕКУЩЕЙ ПАПКЕ.
НЕ создавай новую папку comandos-claw-deck где-то ещё.
НЕ делай cd ~/Desktop/что-то — работай В ТЕКУЩЕМ pwd.
```

---

## 🔑 ПРОМПТ 2 — SSH-ключ

```
Промпт 2: Создай SSH-ключ ed25519 в ~/.ssh/clawd_ed25519 БЕЗ пароля.

ssh-keygen -t ed25519 -f ~/.ssh/clawd_ed25519 -C "clawd@vps" -N ""

Покажи мне ПУБЛИЧНЫЙ ключ (содержимое clawd_ed25519.pub) — он понадобится в
следующем промпте.
```

---

## 🔌 ПРОМПТ 3 — Загрузить ключ на VPS

```
Промпт 3: Загрузи мой публичный SSH-ключ на VPS как root.

VPS_IP и ROOT_PASSWORD читай из .env через
`set -a; source .env; set +a`.

Если твой инструмент блокирует SSH с паролем (Codex/Claude Code часто блокируют)
— дай мне готовую команду для МОЕГО Mac Terminal:

  ssh-copy-id -i ~/.ssh/clawd_ed25519.pub root@<VPS_IP>

Я введу root-пароль сам и скажу «загрузил».

После моего «загрузил» проверь:
  ssh -i ~/.ssh/clawd_ed25519 -o BatchMode=yes root@<VPS_IP> "echo OK"

Должно ответить OK без пароля. Это закрывает A.4 (SSH key-based auth работает).
```

---

## 🛡 ПРОМПТ 4 — VPS hardening

```
Промпт 4: Подготовь VPS по разделу A стандарта (standards/workshop-1-standard.md).

Подключайся как root через ~/.ssh/clawd_ed25519. Выполни лестницу с обязательными
проверками — НЕ перепрыгивай через STOP-gate, иначе можно потерять доступ к VPS.

1. Обнови систему:
   DEBIAN_FRONTEND=noninteractive apt update
   DEBIAN_FRONTEND=noninteractive apt upgrade -y

2. Создай пользователя clawd:
   adduser --disabled-password --gecos "" clawd
   usermod -aG sudo clawd

3. Настрой passwordless sudo ДО любых SSH-блокировок:
   echo "clawd ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/clawd
   chmod 440 /etc/sudoers.d/clawd
   visudo -cf /etc/sudoers.d/clawd

   Проверка внутри root-сессии:
     su - clawd -c "sudo -n whoami"
   Ожидаемый вывод: root

   Если вывод другой — СТОП. Root SSH НЕ закрывать. ufw / fail2ban / смену порта НЕ включать.

4. Скопируй SSH-ключ пользователю clawd:
   install -d -m 700 -o clawd -g clawd /home/clawd/.ssh
   cp /root/.ssh/authorized_keys /home/clawd/.ssh/authorized_keys
   chown clawd:clawd /home/clawd/.ssh/authorized_keys
   chmod 600 /home/clawd/.ssh/authorized_keys

🛑 5. STOP-GATE 1 — проверка запасного входа ДО блокировки root.

   ⚠️ Эту команду выполнять с ЛОКАЛЬНОЙ машины (Mac), где лежит приватный ключ
   ~/.ssh/clawd_ed25519. НЕ выполнять внутри root-сессии на VPS: на VPS нет
   локального приватного ключа Mac.

   Текущую root-сессию на VPS держи ОТКРЫТОЙ как страховочный канал.

   На Mac в новом терминале:
     ssh -i ~/.ssh/clawd_ed25519 -o BatchMode=yes clawd@<VPS_IP> "whoami && sudo -n whoami"

   Или через .env:
     set -a && source .env && set +a && ssh -i ~/.ssh/clawd_ed25519 -o BatchMode=yes clawd@$VPS_IP "whoami && sudo -n whoami"

   Ожидаемый вывод СТРОГО:
     clawd
     root

   Если вывод другой — СТОП. НЕЛЬЗЯ:
     - закрывать root SSH (PermitRootLogin no);
     - включать fail2ban;
     - включать ufw;
     - менять порт SSH;
     - продолжать hardening.
   Покажи пользователю вывод и жди — разберёмся с ключом/sudo.

6. Только после успешного STOP-GATE 1 — закрой root SSH.
   В /etc/ssh/sshd_config выставить:
     PermitRootLogin no
     PasswordAuthentication no
     PubkeyAuthentication yes

   Перед перезапуском обязательно:
     sshd -t
   Если sshd -t показывает ошибку — СТОП. НЕ перезапускай SSH.
   Если ошибок нет:
     systemctl reload ssh || systemctl reload sshd

7. Ещё раз проверь вход clawd после закрытия root (с Mac, не на VPS):
     ssh -i ~/.ssh/clawd_ed25519 -o BatchMode=yes clawd@<VPS_IP> "whoami && sudo -n whoami"
   Или через .env:
     set -a && source .env && set +a && ssh -i ~/.ssh/clawd_ed25519 -o BatchMode=yes clawd@$VPS_IP "whoami && sudo -n whoami"

   Ожидаемый вывод: clawd / root. Если другой — СТОП.

8. Настрой ufw, ПОКА не закрывая текущий рабочий SSH-путь:
   ufw default deny incoming
   ufw default allow outgoing
   ufw allow 22/tcp comment "temporary SSH during setup"

9. Установи fail2ban (после этого НЕ делать массовых SSH-проверок):
   apt install -y fail2ban

   Создать /etc/fail2ban/jail.local:
     [sshd]
     enabled = true
     bantime = 86400
     findtime = 600
     maxretry = 3

   systemctl enable fail2ban
   systemctl start fail2ban
   systemctl is-active fail2ban

   ⚠️ После этого НЕ делай много SSH-подключений подряд. НЕ проверяй root-вход циклом.

10. Включи ufw:
    ufw --force enable
    ufw status

🛑 11. STOP-GATE 2 — смена SSH-порта без потери доступа.

    Выбрать новый порт:
      NEW_PORT=$(shuf -i 10000-60000 -n 1)
      echo $NEW_PORT

    Открыть новый порт ДО изменения sshd:
      ufw allow ${NEW_PORT}/tcp comment "SSH new port"

    Поменять порт в sshd_config:
      sed -i "s/^#*Port .*/Port ${NEW_PORT}/" /etc/ssh/sshd_config

    Добавить ограничения:
      grep -q "^MaxStartups" /etc/ssh/sshd_config || echo "MaxStartups 5:30:10" >> /etc/ssh/sshd_config
      grep -q "^MaxSessions" /etc/ssh/sshd_config || echo "MaxSessions 5" >> /etc/ssh/sshd_config

    Проверить синтаксис:
      sshd -t
    Если ошибка — СТОП. НЕ перезапускай SSH.
    Если ОК:
      systemctl reload ssh || systemctl reload sshd

12. Проверь новый порт во ВТОРОЙ SSH-сессии (с Mac, не закрывая текущую).

    СКАЖИ ПОЛЬЗОВАТЕЛЮ:
      «СТОП. Открой второй терминал на локальной машине и проверь:»

      ssh -p <NEW_PORT> -i ~/.ssh/clawd_ed25519 -o BatchMode=yes clawd@<VPS_IP> "whoami && sudo -n whoami"
    Или через .env:
      set -a && source .env && set +a && ssh -p $NEW_PORT -i ~/.ssh/clawd_ed25519 -o BatchMode=yes clawd@$VPS_IP "whoami && sudo -n whoami"

    Ожидаемый вывод: clawd / root.

    Только после подтверждения пользователя «работает» — продолжай.
    Если не подтвердил — НЕЛЬЗЯ удалять allow 22/tcp.

13. Только после подтверждения — удали порт 22:
    ufw delete allow 22/tcp
    ufw status

14. Обнови .env на локальной машине:
    VPS_USER=clawd
    SSH_PORT=<NEW_PORT>

15. Финальная проверка + остальная инфраструктура:
    ssh -p <NEW_PORT> -i ~/.ssh/clawd_ed25519 -o BatchMode=yes clawd@<VPS_IP> "whoami && sudo -n whoami"
    Ожидаемый вывод: clawd / root.

    Покажи:
      grep -E "^(Port|PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|MaxStartups|MaxSessions)" /etc/ssh/sshd_config
      fail2ban-client get sshd bantime
      ufw status

    Доделай (через sudo от clawd):
      sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile && echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
      sudo apt install -y unattended-upgrades && echo 'Unattended-Upgrade::Automatic-Reboot "false";' | sudo tee /etc/apt/apt.conf.d/52unattended-upgrades-local
      sudo loginctl enable-linger clawd

Покажи какие критерии A.1-A.14 закрыл.

КЛЮЧЕВЫЕ ПРАВИЛА:
1. Root SSH нельзя закрывать, пока clawd не проверен в новой SSH-сессии с Mac.
2. Порт 22 нельзя закрывать, пока новый порт не проверен пользователем во второй сессии.
3. Старую рабочую SSH-сессию нельзя закрывать до конца проверки.
4. Если проверка не прошла — агент обязан остановиться. Нельзя «попробовать продолжить».
5. После включения fail2ban нельзя делать много SSH-подключений подряд.
6. Проверку root-входа нельзя делать циклом.
7. Если агент видит ошибку SSH — показать вывод пользователю и ждать решения.
```

---

### 🚨 Если SSH отвалился после Промпта 4 (rescue)

**Симптом** — при попытке подключиться SSH сразу обрывается:

```
kex_exchange_identification: Connection closed by remote host
Connection closed by <IP> port 22
```

**Это обычно НЕ проблема SSH-ключа.** Сервер закрыл соединение ещё до handshake. Частые причины:

- `fail2ban` забанил твой IP после серии попыток входа;
- `ufw limit 22/tcp` сработал из-за залпа SSH-команд (часто — агент циклил `su - clawd` или повторные проверки root SSH);
- меняется внешний IP (VPN / мобильный интернет);
- `sshd` слушает другой порт или перезапущен с ошибкой.

**Что делать:**

1. **Не долби SSH агентом.** Каждая попытка усиливает бан.
2. Зайди в VPS через **web-console / VNC / console провайдера** (Beget / Hetzner / etc.).
3. В web-console выполни:

```bash
sudo systemctl status ssh --no-pager
sudo journalctl -u ssh -n 80 --no-pager
sudo fail2ban-client status sshd || true
sudo ufw status numbered
sudo ss -tlnp | grep ssh
```

4. На Mac узнай свой текущий внешний IP:

```bash
curl -4 ifconfig.me
```

5. Если IP в бане — разбань (в web-console VPS):

```bash
sudo fail2ban-client set sshd unbanip <ТВОЙ_IP>
sudo systemctl restart fail2ban
```

6. Проверь обычный SSH из терминала Mac (не через агента):

```bash
ssh -vvv -i ~/.ssh/clawd_ed25519 clawd@<VPS_IP>
```

7. Если снова рвёт — временно (только для диагностики) останови fail2ban:

```bash
sudo systemctl stop fail2ban
```

После восстановления доступа **обязательно** включи обратно:

```bash
sudo systemctl start fail2ban
sudo systemctl is-active fail2ban
```

**Чего НЕ делать:**

- не добавлять IP участника в `ignoreip` по умолчанию;
- не ограничивать SSH «только с моего IP» (мобильный/VPN меняют его);
- не пересоздавать SSH-ключ и не переустанавливать VPS — это редко настоящая причина;
- не отключать fail2ban навсегда;
- после включения `fail2ban` / `ufw limit` — не пускать параллельные SSH-команды и не циклить проверки root-входа.

Критерии стандарта **A.5** (ufw active с rate-limit) и **A.6** (fail2ban active) остаются обязательными — этот раздел только про восстановление доступа, не про отключение защиты.

---

## 📦 ПРОМПТ 5 — Node 22 + npm + OpenClaw

```
Промпт 5: Установи Node 22 + npm prefix + OpenClaw на VPS под clawd.

Подключайся как clawd через ssh -i ~/.ssh/clawd_ed25519.

1. nvm установка через https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh

2. nvm install 22 → nvm use 22 → nvm alias default 22

3. npm prefix:
   mkdir -p ~/.npm-global
   npm config set prefix '~/.npm-global'

4. ⚠️ PATH в ТРИ файла (это КРИТИЧНО для cron/systemd/non-login shell):
   echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.bashrc
   echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.profile
   echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.bash_profile

5. npm i -g openclaw  (БЕЗ sudo)

6. Временный фикс OpenClaw 2026.4.29: bundled telegram-extension требует
   `grammy`, но пакет не всегда подтягивается зависимостью:
   bash -lc "npm i -g grammy"

Проверки через bash -lc:
- node --version → v22.x.x
- bash -lc "openclaw --version" → 2026.4.x
- bash -lc "which openclaw" → /home/clawd/.npm-global/bin/openclaw
- bash -lc "npm ls -g grammy --depth=0" → grammy установлен

⛔ ЗАПРЕЩЕНО: НЕ ЗАПУСКАЙ openclaw onboard! Это интерактивный TTY-мастер
для ЧЕЛОВЕКА. Через AI-batch вызовы он не работает корректно (мы это
проверили — упирается в pairing-ловушки на 2 дня).

Покажи что закрыл из B.1, B.5. Скажи: «openclaw установлен, готов к
ручному onboarding — делай Промпт 6».
```

---

## ⏸ ПРОМПТ 6 — СТОП. Эстафета человеку

```
Промпт 6: Стоп. Сейчас Я открою Mac Terminal и САМ пройду интерактивный
openclaw onboard. Это TTY-мастер, ты не справишься через batch.

Не делай больше ничего. Жди моё сообщение «бот живой в Telegram».

Когда я вернусь — дам Промпт 6.5 (tuning после onboard).
```

---

# ⏸ ЧАСТЬ А2 — ТЫ САМ в терминале (10 минут)

> Подойдёт **любой полноценный терминал** (НЕ AI-плагин в Antigravity!):
> - 🟢 Antigravity Terminal (View → Terminal) — рекомендуется, в папке проекта
> - 🟡 Mac Terminal.app (Spotlight → Terminal)
> - 🔵 Windows: WSL / Git Bash
>
> ⚠️ Главное **НЕ путать**: AI-плагин Antigravity (Claude Code / Codex) не может запустить TTY-мастер. А **встроенный Terminal в Antigravity** (View → Terminal) — это обычный shell, в нём всё работает.

## 🔌 Подключись к VPS как clawd

Открой терминал **в папке проекта** (там где `.env`):
- 🟢 **Antigravity Terminal** (View → Terminal) — открывается уже в папке проекта, рекомендую
- 🟡 **Mac Terminal.app** — тогда сначала `cd` в папку проекта
- 🔵 **Windows: WSL / Git Bash** — команда работает идентично Mac

**Универсальная команда** (подставит VPS_IP автоматически из `.env`):

```bash
set -a && source .env && set +a && ssh -i ~/.ssh/clawd_ed25519 clawd@$VPS_IP
```

Что делает:
- `set -a && source .env && set +a` — подгружает переменные из `.env` в shell
- `$VPS_IP` — подставится автоматически (твой IP из `.env`)
- `~/.ssh/clawd_ed25519` — стандартный путь к ключу (создан в Промпте 2)
- `clawd` — стандартный юзер на VPS (создан в Промпте 4)

Должна открыться сессия `clawd@vps:~$` **без пароля**.

⚠️ Если получишь ошибку `Could not resolve hostname vps_ip` — значит ты в неправильной папке (нет `.env`) или `VPS_IP` пустой. Проверь: `pwd` (где ты) и `cat .env | grep VPS_IP` (есть ли значение).

## 💡 Keepalive и tmux перед длинным onboard

Один раз на своём компьютере добавь SSH keepalive, чтобы сессия не отваливалась:

```bash
mkdir -p ~/.ssh && cat >> ~/.ssh/config <<'EOF'

Host *
  ServerAliveInterval 30
  ServerAliveCountMax 6
EOF
chmod 600 ~/.ssh/config
```

На VPS запусти onboard внутри `tmux`:

```bash
sudo apt install -y tmux
tmux new -s onboard
```

Если SSH оборвётся: подключись снова и выполни `tmux attach -t onboard`.

## 🧙 Запусти мастер

```bash
openclaw onboard
```

## 📋 Cheat-sheet ответов на вопросы мастера

| # | Вопрос мастера | Ответ |
|---|---|---|
| 1 | Welcome / continue? | **Enter** |
| 1a | Personal-by-default / shared use warning? | **Yes** |
| 2 | Mode? | **local** |
| 2a | Existing config detected / Config handling? | **Use existing values** |
| 3 | Flow? | **quickstart** |
| 4 | **Authentication mode?** | **token** ⚠️ (НЕ skip!) |
| 5 | Gateway bind? | **loopback** |
| 6 | Gateway port? | **18789** или Enter |
| 7 | **Enable device-pair plugin?** | **yes** ⚠️ (если спросит — обязательно!) |
| 8 | Configure providers now? | **yes** |
| 9 | Add MiniMax? / MiniMax auth method? | **yes** → **MiniMax API key (Global)** → вставь `MINIMAX_API_KEY` |
| 10 | Add DeepSeek? | **yes** → вставь `DEEPSEEK_API_KEY` |
| 11 | Add OpenRouter? | **yes** → вставь `OPENROUTER_API_KEY` |
| 12 | Add Groq? | **yes** → вставь `GROQ_API_KEY` |
| 13 | Add OpenAI? | **yes** → вставь `OPENAI_API_KEY` |
| 14 | Default primary model? | **Keep current (minimax/MiniMax-M2.7)** ⚠️ (не Browse/Enter manually) |
| 15 | Configure channels? | **yes** |
| 16 | Channel type? | **telegram** |
| 17 | Telegram bot token? / Web search provider? | token → `TELEGRAM_BOT_TOKEN`; web search → **Skip for now** |
| 17a | Skills status / Configure skills now? | **No / skip** |
| 17b | Hooks / Enable hooks? | **Skip for now** |
| 18 | Channel name? / Health check timeout? | **main** или Enter; timeout panel → продолжай дальше |
| 19 | dmPolicy / allowFrom? | В QuickStart может **не появиться** — фикс в Промпте 6.5 |
| 20 | Allow from user IDs? | Обычно **не появляется** — фикс в Промпте 6.5 |
| 21 | Install skills now? / Telegram already configured? | **skip** или **Skip (leave as-is)** |
| 22 | Install systemd-user service? | **yes** |
| 23 | Enable linger? | **yes** |
| 24 | **How do you want to hatch your bot?** | **Hatch in Terminal (recommended)** ⚠️ НЕ `Do this later` |
| 25-28 | Workspace backup / Security / Shell completion / What now | info-панели — просто Enter |

**Если мастер задал вопрос которого нет в таблице** → нажми Ctrl+C, открой
консультанта (см. `knowledge-base/CONSULTANT-PROMPT.md`) и спроси что выбрать,
потом запусти `openclaw onboard` снова.

## ✅ Проверка после onboard

В той же SSH-сессии:

```bash
openclaw devices list           # должна быть запись с operator.admin / approvals
openclaw models status          # 5 провайдеров с ✓
openclaw channels list          # telegram main active
openclaw doctor --deep | tail   # 0 critical
systemctl --user status openclaw-gateway --no-pager | head -10
```

## 🤖 Напиши боту в Telegram

Открой Telegram → найди своего бота → напиши **«Привет!»**

Должно ответить. На 4 vCPU обычно 5-15 сек, на 2 vCPU может быть 30-50 сек. В SSH параллельно:
```bash
openclaw logs --since 30s
```

Найди строку с выбранной primary-моделью: `minimax/MiniMax-M2.7` для Asia VPS или `deepseek/deepseek-v4-flash` для EU/RU.

⚠️ Если ответ стабильно дольше 30 сек — это сигнал апгрейдить VPS до 4 vCPU / 8 GB.

---

# 💚 Возвращайся в Antigravity

Скажи AI: **«бот живой в Telegram. Дай Промпт 6.5.»**

---

## 🧩 ПРОМПТ 6.5 — Tuning после onboard

```
Промпт 6.5: Tuning после onboard. Закрываем дыры QuickStart режима.

На VPS под clawd через bash -lc:

1. Закрой бота от чужих:
   openclaw config set channels.telegram.dmPolicy "allowlist"
   openclaw config set channels.telegram.allowFrom '["TELEGRAM_USER_ID"]'
   Замени TELEGRAM_USER_ID на числовой user_id из ~/.env.

2. Назначь command owner для админ-команд:
   openclaw config set commands.ownerAllowFrom '["telegram:TELEGRAM_USER_ID"]'

3. Включи plugins.allow whitelist для скорости:
   python3 <<'EOF'
   import json, shutil
   p = "/home/clawd/.openclaw/openclaw.json"
   shutil.copy(p, p + ".bak.before-tuning")
   c = json.load(open(p))
   c.setdefault("plugins", {}).setdefault("allow", [])
   c["plugins"].setdefault("entries", {})
   for prov in ["telegram","minimax","deepseek","openrouter","groq","openai","device-pair","memory-core"]:
       if prov not in c["plugins"]["allow"]:
           c["plugins"]["allow"].append(prov)
       c["plugins"]["entries"][prov] = {"enabled": True}
   json.dump(c, open(p, "w"), indent=2)
   print("plugins.allow:", c["plugins"]["allow"])
   EOF

4. Подними таймауты для slow networks:
   python3 <<'EOF'
   import json
   p = "/home/clawd/.openclaw/openclaw.json"
   c = json.load(open(p))
   c.setdefault("agents", {}).setdefault("defaults", {})["timeoutSeconds"] = 180
   c.setdefault("models", {}).setdefault("providers", {}).setdefault("minimax", {})["timeoutSeconds"] = 120
   json.dump(c, open(p, "w"), indent=2)
   print("timeouts: agents=180s, minimax=120s")
   EOF

5. Добавь systemd override для Node:
   mkdir -p ~/.config/systemd/user/openclaw-gateway.service.d
   cat > ~/.config/systemd/user/openclaw-gateway.service.d/override.conf <<'EOF'
   [Service]
   Environment="OPENCLAW_NO_RESPAWN=1"
   Environment="NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache"
   EOF
   mkdir -p /var/tmp/openclaw-compile-cache
   systemctl --user daemon-reload

6. Restart daemon + проверка:
   systemctl --user restart openclaw-gateway && sleep 12
   journalctl --user -u openclaw-gateway --since "30 seconds ago" --no-pager | grep -E "ready|telegram.*provider" | tail -5

Закрой D.2, D.3 и сними блокер fetch-timeout на первом сообщении.
```

---

## 🎨 ПРОМПТ 7 — Geo-aware primary + aliases premium/think

```
Промпт 7: Бот живой. Настрой каскад моделей с учётом физики моего VPS.

На VPS под clawd через bash -lc:

1. Проверь auth profiles:
   openclaw auth list

2. Измерь RTT до провайдеров:
   ping -c 3 -W 2 api.minimaxi.com
   ping -c 3 -W 2 api.deepseek.com
   ping -c 3 -W 2 api.openai.com

3. Выбери primary:
   - если RTT MiniMax ≤80ms → primary = minimax/MiniMax-M2.7
   - если RTT MiniMax >80ms → primary = ближайший дешёвый провайдер, обычно deepseek/deepseek-v4-flash для EU/RU

4. Примени primary через CLI:
   openclaw config set agents.defaults.model.primary "<PRIMARY>"

5. Настрой fallback только дешевле или сопоставимо с primary:
   если primary = minimax/MiniMax-M2.7:
     openclaw fallbacks add minimax/MiniMax-M2.7 deepseek/deepseek-v4-flash
   если primary = deepseek/deepseek-v4-flash:
     не добавляй дорогой fallback автоматически; оставь premium только ручной командой

6. Aliases:
   openclaw aliases set premium deepseek/deepseek-v4-pro
   openclaw aliases set think deepseek/deepseek-v4-pro:thinking
   openclaw aliases list

Также проверь:
- openclaw models status — primary = выбранная модель
- openclaw models test "<PRIMARY>" — зелёный, если команда доступна
- Telegram «привет» отвечает за ≤30 сек

Закрой C.3, C.4, C.7, C.8, C.10.
```

---

## 🛡 ПРОМПТ 8 — Watchdog

```
Промпт 8: Настрой watchdog kill-switch по разделу F стандарта.

На VPS под clawd:

1. Создай ~/.openclaw/scripts/watchdog.sh с правами +x.
   ⚠️ ОБЯЗАТЕЛЬНО первой строкой ПОСЛЕ shebang:
     export PATH=$HOME/.npm-global/bin:$PATH
   Без этого cron не найдёт openclaw.

2. Логика watchdog: если за последний час расход > $3 — стоп daemon + alert
   в Telegram.

   TG_TOKEN и TG_USER_ID подставь ПРЯМЫМИ значениями из .env через
   `set -a; source ~/.env; set +a` heredoc.

3. crontab под clawd: */30 * * * * /home/clawd/.openclaw/scripts/watchdog.sh

4. Проверки:
   - crontab -l показывает строку
   - bash -lc "bash ~/.openclaw/scripts/watchdog.sh" → exit 0
   - chmod 700 на watchdog.sh (НЕ 600! Cron должен исполнить — execute-bit нужен)

Также напомни мне зайти на openrouter.ai → Settings → Spending Limit → $30/мес.

Закрой F.1-F.5.
```

---

## 🎨 ПРОМПТ 9 — Картинки

```
Промпт 9: Настрой генерацию картинок по разделу E стандарта.

Через bash -lc на VPS:

1. openclaw config set agents.defaults.imageGenerationModel.primary \
     openrouter/google/gemini-2.5-flash-image

2. openclaw config set agents.defaults.imageGenerationModel.fallbacks \
     '["openrouter/black-forest-labs/flux-schnell"]'

3. ⚠️ tools.profile ОБЯЗАТЕЛЬНО = "full" (стандарт E.1, не "messaging" и не "coding"!):
   bash -lc "openclaw config set tools.profile full"
   Иначе картинки могут не работать и провалится финальная самопроверка.

Перезапусти daemon:
  systemctl --user restart openclaw && sleep 5 && bash -lc "openclaw doctor --deep | tail -10"

После я напишу боту "/image кот в шапке астронавта" — покажи логи и подтверди
что картинка пришла.

Закрой E.1-E.5.
```

---

## 👤 ПРОМПТ 10 — SOUL.md (личность)

```
Промпт 10: Настрой личность бота через SOUL.md.

Спроси меня: «Как зовут твоего цифрового сотрудника? Какой у него характер
(дерзкий / тёплый / деловой / технарь)?»

После моего ответа создай ~/.openclaw/workspace/SOUL.md:

# Личность

## Имя
[имя]

## Характер
[характер]

## Правила
- Отвечай кратко и по делу на русском
- НИКОГДА не используй пустые фразы: «Отличный вопрос!», «С удовольствием
  помогу!», «Вот развёрнутый ответ:», «Конечно!»
- Не показывай chain-of-thought, не пиши «Анализирую...»
- Если не знаешь — скажи прямо «не знаю», не выдумывай

Перезапусти daemon. Я напишу боту «привет» — он должен представиться по имени
БЕЗ пустых фраз.

Закрой D.7, H.1-H.3.
```

---

## ✅ ПРОМПТ 11 — Финальная самопроверка

```
Промпт 11: Финальная самопроверка Воркшопа 1.

Пройдись по разделам A-H стандарта (standards/workshop-1-standard.md) и для
КАЖДОГО ❗ критерия выдай:
- ✅ закрыто (с доказательством — командой и её выводом)
- ⚠️ частично/неясно (с пояснением)
- ❌ не закрыто (с объяснением)

Обязательно покажи сырой вывод:
- bash -lc "openclaw devices list"
- bash -lc "openclaw models status"
- bash -lc "openclaw channels list"
- bash -lc "openclaw doctor --deep | tail -25"
- crontab -l
- systemctl --user status openclaw --no-pager | head -10

Сохрани отчёт самопроверки на VPS как ~/.openclaw/workshop-1-self-check.md
для последующего аудита.

Вердикт:
- 🎉 «Воркшоп 1 пройден» — все ❗ закрыты
- 🟡 «Почти готово» — все ❗ закрыты, есть ⚠️
- ❌ «Есть проблемы» — что-то ❗ не закрыто
```

---

# 🎯 После 11 промптов

После Промпта 11 у тебя должно быть:
- ✅ Бот в Telegram отвечает на «привет» через MiniMax M2.7
- ✅ `/image кот` возвращает картинку за 5-15 сек
- ✅ Бот представляется по имени
- ✅ Watchdog в crontab каждые 30 мин
- ✅ Все ❗ критерии стандарта закрыты

**Дальше:**
1. **`02-self-check.md`** — копируй 8 запросов прямо в Telegram-бот, собирай артефакты состояния
2. **`03-audit.md`** — запусти независимый аудит в НОВОМ чате Antigravity

После аудита получишь окончательный вердикт.

---

# 🆘 Если на любом промпте что-то падает

**Не паникуй и не лезь чинить через AI «попробуй ещё раз»** — это путь к двум дням ада.

Открой `knowledge-base/CONSULTANT-PROMPT.md`, скопируй его в **НОВЫЙ чат AI**
(не в этот!) — это твой персональный консультант с базой знаний 20 блоков
исследований + known-issues. Задай конкретный вопрос — получишь точный фикс
за 30 секунд.

Также см. `knowledge-base/known-issues/`:
- `1008-pairing-required.md` — gateway closed 1008
- `path-non-login-shell.md` — openclaw: command not found из cron
- `slug-case-sensitive.md` — minimax/minimax-m2.7 vs minimax/MiniMax-M2.7
- `device-pair-disabled.md` — paired.json пустой
- `runaway-4200-incident.md` — что не делать с fallback моделями
