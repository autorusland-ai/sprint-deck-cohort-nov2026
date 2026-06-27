#!/usr/bin/env bash
# Настраивает transparent SOCKS5 proxy для api.telegram.org через Tor.
#
# Зачем: с 27.06.2026 TimeWeb/RKN заблокировали прямой TCP-доступ к api.telegram.org
# с VPS на российских IP. openclaw использует axios для Telegram polling, который
# игнорирует HTTPS_PROXY env. Решение — перехват на уровне OS через iptables NAT +
# redsocks → Tor SOCKS5.
#
# После выполнения:
# - Прямые curl/node/axios запросы к api.telegram.org прозрачно идут через Tor
# - openclaw Telegram polling работает без патчей в коде
# - Работает для любого приложения на VPS (curl, python, browser-use, etc.)
#
# Требуется: sudo (NOPASSWD предпочтительно), Tor уже запущен на 127.0.0.1:9050.

set -e

echo '=== 1. Install redsocks + iptables-persistent ==='
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq redsocks iptables-persistent

echo '=== 2. /etc/redsocks.conf ==='
sudo tee /etc/redsocks.conf > /dev/null <<'EOF'
base {
    log_debug = off;
    log_info = on;
    log = "syslog:daemon";
    daemon = on;
    redirector = iptables;
}
redsocks {
    local_ip = 127.0.0.1;
    local_port = 12345;
    ip = 127.0.0.1;
    port = 9050;
    type = socks5;
}
EOF

echo '=== 3. Enable + start redsocks ==='
sudo systemctl restart redsocks
sudo systemctl enable redsocks
sleep 2
sudo systemctl is-active redsocks || { echo 'redsocks not active'; exit 1; }

echo '=== 4. iptables NAT для официальных Telegram CIDR ==='
# Источник: https://core.telegram.org/resources/cidr.txt
TG_NETS='149.154.160.0/20 91.108.4.0/22 91.108.8.0/22 91.108.12.0/22 91.108.16.0/22 91.108.56.0/22'
for net in $TG_NETS; do
    for port in 443 80; do
        sudo iptables -t nat -C OUTPUT -p tcp -d "$net" --dport "$port" -j REDIRECT --to-ports 12345 2>/dev/null \
            || sudo iptables -t nat -A OUTPUT -p tcp -d "$net" --dport "$port" -j REDIRECT --to-ports 12345
    done
done

echo '=== 5. Persist iptables rules across reboots ==='
sudo netfilter-persistent save

echo '=== 6. Smoke test ==='
TOKEN=$(cat ~/.openclaw/secrets/telegram.token 2>/dev/null)
if [ -n "$TOKEN" ]; then
    RESULT=$(curl -sS --max-time 10 --noproxy '*' -o /dev/null -w '%{http_code}' "https://api.telegram.org/bot${TOKEN}/getMe")
    if [ "$RESULT" = "200" ]; then
        echo "✅ api.telegram.org через redsocks → HTTP 200"
    else
        echo "❌ Smoke test fail: HTTP $RESULT (ожидался 200)"
        exit 1
    fi
fi

echo '=== 7. Restart openclaw-gateway чтобы Telegram polling заработал ==='
systemctl --user restart openclaw-gateway
sleep 8
systemctl --user is-active openclaw-gateway

echo
echo 'Done. Telegram доступен прозрачно через Tor SOCKS5.'
echo 'IP-список Telegram может меняться — обновлять список CIDR раз в год.'
