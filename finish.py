import os

# 1. Update crontab
os.system('crontab -l > /tmp/cron.txt 2>/dev/null')
try:
    with open('/tmp/cron.txt', 'r') as f:
        lines = f.readlines()
except FileNotFoundError:
    lines = []

lines = [l for l in lines if 'watchdog' not in l]
lines.append('*/30 * * * * /home/clawd/.openclaw/scripts/watchdog.sh\n')

with open('/tmp/cron.txt', 'w') as f:
    f.writelines(lines)

os.system('crontab /tmp/cron.txt')

# 2. Start daemon
os.system('systemctl --user start openclaw-gateway')
