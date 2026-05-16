import os
import subprocess

def run(cmd):
    print(f"RUNNING: {cmd}")
    r = subprocess.run(f"bash -lc '{cmd}'", shell=True, capture_output=True, text=True)
    print("STDOUT:", r.stdout.strip())
    if r.stderr.strip():
        print("STDERR:", r.stderr.strip())
    print("-----")
    return r

# Set configurations
run('openclaw config set agents.defaults.heartbeat.model "openrouter/google/gemini-2.5-flash-lite"')
run('openclaw config set agents.defaults.heartbeat.enabled true')
run('openclaw config set channels.telegram.commands.context.enabled true')
run('openclaw config set channels.telegram.commands.usage.enabled true')
run('openclaw config set channels.telegram.ackReaction "👀"')

# Prompt caching
# In newer OpenClaw, caching is usually enabled by default if supported by provider plugin, 
# or configured at provider level. 
run('openclaw config set models.providers.openrouter.promptCaching true')
run('openclaw config set models.providers.deepseek.promptCaching true')
run('openclaw config set models.providers.minimax.promptCaching true')

# Crontab update
cron_content = "*/15 * * * * /home/clawd/.openclaw/scripts/watchdog.sh\n"
with open("/tmp/newcron", "w") as f:
    f.write(cron_content)
run('crontab /tmp/newcron')

# Fix and restart
run('openclaw doctor --fix')
run('systemctl --user restart openclaw-gateway')
run('chmod 600 ~/.openclaw/openclaw.json')
run('sleep 3')

# Verification
run('crontab -l')
run('stat -c "%a %n" ~/.openclaw/openclaw.json')
