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

# Qdrant
run('cd ~/.openclaw && docker compose -f docker-compose.qdrant.yml up -d')

# Mem0 SDK
run('openclaw plugins install --dangerously-force-unsafe-install @mem0/openclaw-mem0')

# Mem0 config
run('openclaw config set agents.defaults.memory.vectorStore "qdrant://127.0.0.1:6333"')
run('openclaw config set agents.defaults.memory.collection "openclaw_main"')
run('openclaw config set agents.defaults.memory.embedder "openai/text-embedding-3-small"')

# Auto-capture
run('openclaw config set agents.defaults.memory.autoCapture true')
run('openclaw config set agents.defaults.memory.dedupeThreshold 0.92')

# Privacy guard
run('openclaw config set plugins.entries.detect-secrets.enabled true')
run('openclaw config set agents.defaults.privacyGuard.blockOnDetect true')
run('openclaw config set agents.defaults.privacyGuard.fallbackClassifier "openrouter/google/gemini-2.5-flash-lite"')

# Doctor & Restart
run('openclaw doctor --fix')
run('systemctl --user restart openclaw-gateway')
run('chmod 600 ~/.openclaw/openclaw.json')
run('sleep 5')

# Seed MEMORY.md
run('openclaw memory add "$(cat ~/.openclaw/workspace/MEMORY.md)"')

# Verifications
run('ss -tlnp | grep 6333')
run('openclaw skills list | grep -i mem0')
