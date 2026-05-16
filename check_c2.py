import os
import subprocess

def run(cmd):
    print(f"RUNNING: {cmd}")
    r = subprocess.run(f"bash -lc '{cmd}'", shell=True, capture_output=True, text=True)
    if r.stdout.strip():
        print("STDOUT:", r.stdout.strip())
    if r.stderr.strip():
        print("STDERR:", r.stderr.strip())
    print("-----")
    return r

run('openclaw config set plugins.allow \'["deepseek","device-pair","groq","memory-core","minimax","openai","openclaw-mem0","openrouter","telegram","memory"]\'')
run('openclaw config set plugins.entries.detect-secrets null')
run('openclaw doctor --fix')

run('cd ~/.openclaw && docker compose -f docker-compose.qdrant.yml up -d')
run('sleep 3')
run('docker ps | grep qdrant')
run('ss -tlnp | grep 6333')

run('openclaw memory add "$(cat ~/.openclaw/workspace/MEMORY.md)"')

run('systemctl --user restart openclaw-gateway')
run('chmod 600 ~/.openclaw/openclaw.json')
