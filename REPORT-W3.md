# REPORT-W3.md — Воркшоп 3: Полный отчёт

**Дата:** 2026-05-22
**OpenClaw:** 2026.5.19 (a185ca2)
**Хост:** Ubuntu 24.04, VPS

---

## A. Каскад моделей (OAuth + primary)

### A.1-A.4 — OpenAI Codex OAuth
- **Профиль:** `openai-codex:manual` — создан через `openclaw models auth paste-token --provider openai-codex`
- **Токен:** получен через OAuth flow (код авторизации из браузера)
- **Default model:** `openai/gpt-5` (установлен в agents.defaults.model.primary)
- **Fallback:** `minimax/MiniMax-M2.7` → `deepseek/deepseek-v4-flash`

### A.5 — Fallback minimax
- Оставлен как fallback. DeepSeek — второй fallback.

### OpenAI API ключи
- **Key 1 (Primary):** `~/.openclaw/secrets/openai-primary.token` — используется через OpenRouter (gonka provider)
- **Key 2 (Backup):** `~/.openclaw/secrets/openai-backup.token`
- **Tor SOCKS5:** `127.0.0.1:9050` — обход геоблокировки OpenAI
- **Статус:** ключи валидны, но insufficient_quota на OpenAI напрямую. Работают через OpenRouter.

---

## B. Веб-инструменты

### B.1-B.3 — Brave Search
- **Ключ:** `~/.openclaw/.env` → `BRAVE_API_KEY`
- **В конфиге:** `openclaw.json` → `env.BRAVE_API_KEY`

### B.4-B.5 — Tavily MCP
- **Ключ:** `~/.openclaw/.env` → `TAVILY_API_KEY`
- **MCP сервер:** `openclaw.json` → `mcp.servers.tavily`:
  ```json
  {
    "command": "npx",
    "args": ["-y", "@marcopirazzini/tavily-mcp@latest"],
    "env": {
      "TAVILY_API_KEY": "${TAVILY_API_KEY}"
    }
  }
  ```

### B.6-B.7 — Иерархия веб-инструментов
- Добавлена в `AGENTS.md`:
  1. `web_search` (Brave) — поиск
  2. `web_fetch` — статичные страницы
  3. `browser-use` / `browser-agent` — динамика, формы, клики

---

## C. Браузерный стек с антидетектом

### C.1 — apt deps
- `xvfb`, `xdotool`, `x11-utils`, `python3.12-venv`

### C.2 — Python venv
- **Путь:** `/home/clawd/browser-env`
- **Python:** 3.12.3
- **Менеджер пакетов:** pip + uv

### C.3 — Установленные пакеты
| Пакет | Версия |
|---|---|
| browser-use[cli] | 0.12.7 |
| patchright | 1.60.0 |
| playwright-stealth | 2.0.3 |
| PyVirtualDisplay | 3.0 |
| fake-useragent | 2.2.0 |
| google-workspace-mcp | 2.0.1 |
| browser-use-fork (local) | editable install |

### C.4 — Chrome
- **Версия:** Google Chrome 148.0.7778.178
- **Установлен через:** `patchright install chrome --with-deps`

### C.5 — browser-use форк
- **Путь:** `/home/clawd/browser-use-fork`
- **Модификация:** `from playwright` → `from patchright` во всех .py файлах
- **Установлен:** `pip install -e .`

### C.6 — Browser profile
- **Путь:** `/home/clawd/.browser-profiles/default`

### C.7 — Xvfb
- **systemd unit:** `~/.config/systemd/user/xvfb.service`
- **Команда:** `/usr/bin/Xvfb :99 -screen 0 1920x1080x24`
- **Автозапуск:** enabled
- **Restart:** `systemctl --user restart xvfb`

### C.8 — browser-use MCP
```json
{
  "command": "/home/clawd/browser-env/bin/browser-use",
  "args": ["--mcp"],
  "env": {
    "OPENROUTER_API_KEY": "${OPENROUTER_API_KEY}",
    "OPENROUTER_BASE_URL": "https://openrouter.ai/api/v1",
    "BROWSER_USE_LLM": "openrouter/google/gemini-2.5-flash-lite",
    "DISPLAY": ":99",
    "BROWSER_HEADLESS": "false",
    "BROWSER_PROFILE_DIR": "/home/clawd/.browser-profiles/default"
  }
}
```

### C.9 — tools.deny
```json
{
  "tools": {
    "deny": [
      "~/.openclaw/openclaw.json",
      "~/.openclaw/credentials/",
      "~/.openclaw/secrets/"
    ]
  }
}
```

---

## D. 7 скиллов

### D.1-D.6 — Созданные скиллы
| Скилл | Назначение | Путь |
|---|---|---|
| `web-quick` | Быстрый факт, новость | `workspace/skills/web-quick/SKILL.md` |
| `page-reader` | Суммаризация статьи по URL | `workspace/skills/page-reader/SKILL.md` |
| `deep-research` | Глубокий ресёрч (Tavily) | `workspace/skills/deep-research/SKILL.md` |
| `browser-agent` | Клик, форма, логин | `workspace/skills/browser-agent/SKILL.md` |
| `mail-handler` | Gmail: чтение, поиск, отправка | `workspace/skills/mail-handler/SKILL.md` |
| `calendar-keeper` | Google Calendar: чтение событий | `workspace/skills/calendar-keeper/SKILL.md` |

### D.7 — self-improving-agent
- Установлен из ClawHub: `openclaw skills install self-improving-agent`
- Версия: 3.0.21
- Назначение: автоматическая реакция на ошибки/коррекции

### D.8 — OPENROUTER_API_KEY
- Добавлен в `openclaw.json` → `env.OPENROUTER_API_KEY`
- Взят из существующего gonka provider key

---

## E. Google Workspace OAuth

### E.1-E.4 — Учётные данные
| Файл | Назначение |
|---|---|
| `~/.openclaw/secrets/google-oauth.json` | OAuth client config (installed format) |
| `~/.openclaw/secrets/google-token.json` | Токены доступа (access + refresh) |
| `~/.openclaw/secrets/google-credentials.json` | Credentials в installed формате (для OpenClaw tools) |
| `~/.config/google-oauthlib-tool/credentials.json` | ADC-формат для google-auth библиотек |

### E.5-E.6 — Параметры проекта
- **Проект:** ivanichclawbot
- **Client ID:** `130111462890-9g2jsrgvts05065hrfn21d8u2e83hjmk.apps.googleusercontent.com`
- **Client Secret:** `~/.openclaw/secrets/google-oauth.json` → installed.client_secret
- **Refresh Token:** `~/.openclaw/secrets/google-token.json` → refresh_token

### E.7-E.8 — Scopes (текущие)
- `gmail.readonly` ✅
- `gmail.send` ✅
- `calendar.readonly` ✅
- `calendar.events.readonly` ✅
- `calendar.events` (write) ❌ — если нужно добавлять события, нужен новый OAuth с `https://www.googleapis.com/auth/calendar`

### E.9 — MCP server
```json
{
  "command": "/home/clawd/browser-env/bin/google-workspace-worker",
  "env": {
    "GOOGLE_WORKSPACE_CLIENT_ID": "130111462890-9g2jsrgvts05065hrfn21d8u2e83hjmk.apps.googleusercontent.com",
    "GOOGLE_WORKSPACE_CLIENT_SECRET": "из google-oauth.json",
    "GOOGLE_WORKSPACE_REFRESH_TOKEN": "из google-token.json"
  }
}
```

### E.10-E.12 — Статус
- **Календарь (чтение):** ✅ работает
- **Почта (чтение):** ✅ работает  
- **Календарь (запись):** ❌ readonly scope

---

## F. HEARTBEAT.md

### F.1-F.2 — Правила heartbeat
- 6 правил "Когда писать мне первым"
- Запреты (не вызывать web_search/web_fetch/browser-use/sessions_spawn)
- Файл: `workspace/HEARTBEAT.md`

---

## H. Autocommit whitelist

### H.1 — Расширение
Добавлены в `~/.openclaw/scripts/openclaw-autocommit.sh`:
- `workspace/skills/web-quick/SKILL.md`
- `workspace/skills/page-reader/SKILL.md`
- `workspace/skills/deep-research/SKILL.md`
- `workspace/skills/browser-agent/SKILL.md`
- `workspace/skills/mail-handler/SKILL.md`
- `workspace/skills/calendar-keeper/SKILL.md`
- `REPORT-W3.md`
- `.learnings/*.md` — авто-добавление через `git ls-files --others --modified`

---

## 🔑 Где что лежит (для восстановления)

### Секреты (`~/.openclaw/secrets/`)
| Файл | Что содержит |
|---|---|
| `openai-primary.token` | OpenAI API Key 1 (для OpenRouter) |
| `openai-backup.token` | OpenAI API Key 2 (запасной) |
| `google-oauth.json` | OAuth client config (ivanichclawbot) |
| `google-credentials.json` | Credentials для OpenClaw tools (ivanichclawbot) |
| `google-token.json` | Access + refresh токены Google |
| `google-rusfincoach.txt` | Логин/пароль от rusfincoach@gmail.com |

### Конфиги
| Файл | Назначение |
|---|---|
| `~/.openclaw/openclaw.json` | Главный конфиг (env vars, MCP servers, models) |
| `~/.openclaw/.env` | Переменные окружения (chmod 600) |
| `~/.openclaw/workspace/AGENTS.md` | Правила работы бота |
| `~/.openclaw/workspace/HEARTBEAT.md` | Правила heartbeat |
| `~/.openclaw/workspace/skills/*/SKILL.md` | 7 скиллов |
| `~/.openclaw/scripts/openclaw-autocommit.sh` | Autocommit whitelist |

### MCP серверы
| Сервер | Команда |
|---|---|
| `browser-use` | `/home/clawd/browser-env/bin/browser-use --mcp` |
| `tavily` | `npx -y @marcopirazzini/tavily-mcp@latest` |
| `google-workspace` | `/home/clawd/browser-env/bin/google-workspace-worker` (через env vars) |

### Сервисы systemd
| Сервис | Статус | Команда рестарта |
|---|---|---|
| `openclaw-gateway` | active | `systemctl --user restart openclaw-gateway` |
| `xvfb` | active | `systemctl --user restart xvfb` |

### Python venv
- **Путь:** `/home/clawd/browser-env`
- **Активация:** `source /home/clawd/browser-env/bin/activate`

### Browser-use форк
- **Путь:** `/home/clawd/browser-use-fork`
- **Установка после клонирования:** `cd /home/clawd/browser-use-fork && source /home/clawd/browser-env/bin/activate && pip install -e .`

---

## ⚠️ Известные проблемы

1. **Google Calendar write** — не работает из-за readonly OAuth scopes. Для записи: новый OAuth с `https://www.googleapis.com/auth/calendar` (вместо readonly)
2. **OpenAI direct** — keys valid but insufficient_quota. Нужен счёт на platform.openai.com/wallet для прямого доступа
3. **OAuth token refresh** — Codex токен живёт 30 дней. Обновление: `openclaw models auth login --provider openai-codex --set-default` (нужен TTY/браузер)
4. **google-workspace-mcp** — пакет 2.0.1 имеет баг с `mcp.run()` (FastMCP). На VPS работает через env vars напрямую, не через MCP transport
