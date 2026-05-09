# Geographic latency до LLM provider

> **Симптом**: бот отвечает через fallback или стабильно ловит timeout на primary. Особенно часто: MiniMax primary на VPS в RU/EU.

## Причина

RTT до API физически важен. Например, VPS в Москве может иметь около 160ms до MiniMax Singapore и около 7ms до DeepSeek через Cloudfront edge. Это не ошибка ключа и не обязательно проблема OpenClaw.

## Диагностика

```bash
ping -c 3 -W 2 api.minimaxi.com
ping -c 3 -W 2 api.deepseek.com
ping -c 3 -W 2 api.openai.com
```

## Выбор primary

| Регион VPS | Primary | Почему |
|---|---|---|
| Asia (SG/HK/JP) | `minimax/MiniMax-M2.7` | близко к MiniMax |
| EU | `deepseek/deepseek-v4-flash` | обычно низкий RTT |
| RU | `deepseek/deepseek-v4-flash` | MiniMax далеко |
| US | OpenAI или DeepSeek | зависит от RTT |

Правило стандарта: если RTT MiniMax ≤80ms, можно оставлять MiniMax primary. Если >80ms, выбирай ближайший дешёвый provider.

## Фикс

```bash
openclaw config set agents.defaults.model.primary deepseek/deepseek-v4-flash
systemctl --user restart openclaw-gateway
```

Не добавляй дорогой auto-fallback. Premium-модели должны включаться вручную через alias/команду.
