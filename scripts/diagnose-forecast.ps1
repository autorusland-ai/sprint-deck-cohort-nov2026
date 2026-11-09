# Read-only VPS diagnostics; no config writes, restarts or model calls.
$ErrorActionPreference = 'Stop'
$remote = @'
printf '\n=== HOST ===\n'
date -Is
uptime
free -h
df -h /
printf '\n=== SERVICES ===\n'
systemctl --user show openclaw-gateway -p ActiveState -p SubState -p NRestarts
sudo -n systemctl --user -M hermes@ show hermes-gateway -p ActiveState -p SubState -p NRestarts
systemctl is-active tor@default redsocks tg-net-watchdog.timer
printf '\n=== TELEGRAM NETWORK ===\n'
curl -s -o /dev/null -w '%{http_code}\n' --max-time 20 https://api.telegram.org
printf '\n=== ASTRO OWNERSHIP ===\n'
ls -ld /home/clawd/.openclaw/scripts /home/clawd/.openclaw/scripts/astro-cli.py /home/clawd/.openclaw/workspace /home/clawd/.openclaw/workspace/skills /home/clawd/emmbase/life/прогнозы
printf '\n=== ASTRO FILES ===\n'
find /home/clawd/.openclaw/scripts -maxdepth 2 -iname '*astro*' -printf '%p\n'
sudo -n find /home/hermes/.hermes/scripts -maxdepth 1 -iname '*astro*' -printf '%p\n'
printf '\n=== CRON ASTRO ===\n'
crontab -l | grep -i astro
printf '\n=== RECENT SERVICE WARNINGS ===\n'
journalctl --user -u openclaw-gateway --since '24 hours ago' -p warning --no-pager -n 35
sudo -n journalctl _UID=1001 --since '24 hours ago' -p warning --no-pager -n 35
'@
$remote = $remote.Replace("`r", '')
& ssh -o BatchMode=yes -o ConnectTimeout=10 clawd-vps-tail $remote
exit $LASTEXITCODE
