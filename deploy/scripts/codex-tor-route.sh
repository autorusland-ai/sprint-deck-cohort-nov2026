#!/usr/bin/env bash
# codex-tor-route.sh — держит трафик к Codex завёрнутым в Tor.
#
# Зачем: chatgpt.com отдаёт 403 (Country not supported) на прямой запрос с
# российского VPS, а openclaw ходит туда МИМО настроек прокси — ни HTTPS_PROXY,
# ни models.providers.*.request.proxy на этот путь не влияют (проверено 27.07.2026).
# Единственный рабочий способ — прозрачное перенаправление на уровне системы,
# как это уже сделано для Telegram: iptables REDIRECT -> redsocks -> Tor.
#
# Дополнительно закрывается IPv6: у VPS есть глобальный адрес, у chatgpt.com есть
# AAAA-записи, и по IPv6 соединение уходило бы мимо правил (они только для IPv4).
# REJECT с tcp-reset даёт мгновенный откат на IPv4, без ожидания таймаута.
#
# Адреса Cloudflare/OpenAI меняются, поэтому скрипт запускается по cron и
# доводит правила до нужного состояния. Свои правила помечаются комментарием,
# чтобы чистка не задела соседние (в частности, правила Telegram).
set -u

HOSTS="chatgpt.com"
REDSOCKS_PORT=12345
TAG="codex-tor"
V6_PREFIX="2a06:98c1::/32"   # Cloudflare, где живёт chatgpt.com
LOG=/home/clawd/.openclaw/logs/codex-tor-route.log
mkdir -p "$(dirname "$LOG")"
ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

ips=""
for h in $HOSTS; do
  ips="$ips $(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1}' | sort -u)"
done
ips=$(echo "$ips" | tr ' ' '\n' | grep -E '^[0-9]+\.' | sort -u)

if [ -z "$ips" ]; then
  echo "$(ts) [warn] не удалось определить адреса $HOSTS — правила не трогаю" >> "$LOG"
  exit 0
fi

added=0
for ip in $ips; do
  if ! sudo iptables -t nat -C OUTPUT -p tcp -d "$ip" --dport 443 \
        -m comment --comment "$TAG" -j REDIRECT --to-ports "$REDSOCKS_PORT" 2>/dev/null; then
    sudo iptables -t nat -I OUTPUT 1 -p tcp -d "$ip" --dport 443 \
        -m comment --comment "$TAG" -j REDIRECT --to-ports "$REDSOCKS_PORT" && added=$((added+1))
  fi
done

# Убираем свои устаревшие правила: адрес больше не резолвится — правило не нужно.
removed=0
while read -r rule_ip; do
  [ -z "$rule_ip" ] && continue
  if ! echo "$ips" | grep -qx "$rule_ip"; then
    sudo iptables -t nat -D OUTPUT -p tcp -d "$rule_ip" --dport 443 \
        -m comment --comment "$TAG" -j REDIRECT --to-ports "$REDSOCKS_PORT" 2>/dev/null && removed=$((removed+1))
  fi
done <<< "$(sudo iptables -t nat -S OUTPUT 2>/dev/null | grep -- "--comment \"$TAG\"" \
            | grep -oE '\-d [0-9.]+' | awk '{print $2}' | sed 's#/32##' | sort -u)"

# IPv6 закрываем, чтобы соединение уходило по IPv4 через перенаправление.
if ! sudo ip6tables -C OUTPUT -d "$V6_PREFIX" -p tcp --dport 443 \
      -m comment --comment "$TAG" -j REJECT --reject-with tcp-reset 2>/dev/null; then
  sudo ip6tables -I OUTPUT 1 -d "$V6_PREFIX" -p tcp --dport 443 \
      -m comment --comment "$TAG" -j REJECT --reject-with tcp-reset && added=$((added+1))
fi

if [ "$added" -gt 0 ] || [ "$removed" -gt 0 ]; then
  sudo netfilter-persistent save >/dev/null 2>&1
  echo "$(ts) добавлено=$added удалено=$removed | адреса: $(echo $ips | tr '\n' ' ')" >> "$LOG"
fi
