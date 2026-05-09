# Hatch skipped → scope upgrade не одобрен

> **Симптом**: onboard прошёл, pairing есть, но tool-calls ломаются. В логах:

```text
[telegram] connect error: scope upgrade pending approval
gateway closed (1008): pairing required: device is asking for more scopes than currently approved
```

В `openclaw devices list` у device только `operator.pairing`, без approvals/admin scopes.

## Причина

На шаге onboard `How do you want to hatch your bot?` был выбран `Do this later`. Этот шаг нужен, чтобы первичный chat активировал scope upgrade (права доступа). Без него CLI остаётся с урезанными правами.

## Профилактика

В onboard всегда выбирай:

```text
Hatch in Terminal (recommended)
```

После этого пройди короткий начальный диалог в TUI.

## Если уже пропустил

Запусти dashboard:

```bash
openclaw dashboard --no-open
```

Открой выданный URL через SSH-туннель, нажми approve на pending pairing-запросе и проверь:

```bash
openclaw devices list
```

Должны появиться полные scopes, включая approvals/admin.
