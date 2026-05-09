# Slow first response / fetch-timeout на первом сообщении

> **Симптом**: первое сообщение боту в Telegram отвечает 45+ секунд или падает в `fetch-timeout`. CPU на VPS забит на 95%+.

## Причина

OpenClaw при первом активном использовании плагинов может staging/install bundled runtime deps. На 2 vCPU это блокирует event loop и Telegram не успевает дождаться ответа.

Типичные логи:

```text
[plugins] memory-core staging bundled runtime deps (45 specs): ...
[diagnostic] liveness warning: cpu utilization 0.955, eventLoopDelayMaxMs=18857
[telegram] sendChatAction failed: Network request failed
[fetch-timeout] fetch timeout reached; aborting operation
```

## Фикс

1. Включить `plugins.allow` whitelist только для нужных плагинов.
2. Поднять `agents.defaults.timeoutSeconds=180`.
3. Добавить systemd override:
   - `OPENCLAW_NO_RESPAWN=1`
   - `NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache`
4. Перезапустить `openclaw-gateway`.

Готовый пошаговый блок см. в `workshop-1/01-prompts.md`, Промпт 6.5.

## Когда апгрейдить VPS

Если после whitelist бот стабильно отвечает дольше 30 секунд, 2 vCPU не хватает. Рекомендуемый минимум для комфортной работы: 4 vCPU / 8 GB RAM.
