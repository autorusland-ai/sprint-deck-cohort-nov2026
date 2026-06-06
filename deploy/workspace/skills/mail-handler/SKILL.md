---
name: mail-handler
description: "Gmail (rusfeodor@gmail.com через gws-cli.py). READ напрямую. WRITE (send/reply/draft) — ВСЕГДА через inbox-saver."
---

# Mail Handler

## READ — напрямую

- `exec ~/.openclaw/scripts/gws-cli.py gmail unread-count`
- `exec ~/.openclaw/scripts/gws-cli.py gmail search "<query>" [--limit N]`
  - Query синтаксис Gmail: `is:unread`, `from:foo@bar`, `subject:X`, `after:2026/05/01`, `label:inbox`
- `exec ~/.openclaw/scripts/gws-cli.py gmail message <id>` — полный текст письма

## WRITE — ТОЛЬКО через inbox-saver

«отправь письмо», «ответь Иванову», «сделай черновик» — ВСЁ через inbox.

❌ НЕ вызывай `gws-cli.py gmail send` / `reply` / `draft` напрямую.

✅ Делаешь так:
1. Покажи Руслану черновик письма (текстом в Telegram-чате).
2. Если Руслан явно сказал «отправляй» / «да, шли» — создаёшь файл `/emmbase/inbox/ГГГГ-ММ-ДД_письмо-кому.md` с типом `инструкция`:

```
# Тип: инструкция
# Относится к: клиент: Имя (если применимо)
# Дата: ГГГГ-ММ-ДД ЧЧ:ММ
# Источник: бот
# Срочность: 🟡 обычно

ИНСТРУКЦИЯ для Claude: Отправь Gmail-письмо от [[rusfeodor@gmail.com]] на адрес: {to}.

Тема: {subject}

Тело:
{body}
```

3. Скажи Руслану: «Положил в inbox как инструкцию — Claude отправит при следующем разборе».

## Чего НЕ делать

- НЕ отправляй письма самостоятельно через скрипт.
- НЕ говори «Gmail MCP не подключён» — есть прямые скрипты для read.
- На сложные ответы (юридические, договорные, многораундовые) — ВСЕГДА показывай черновик, не торопись с инструкцией в inbox.
