import os
import subprocess
import json

def run(cmd):
    print(f"RUNNING: {cmd}")
    r = subprocess.run(f"bash -lc '{cmd}'", shell=True, capture_output=True, text=True)
    if r.stdout.strip():
        print("STDOUT:", r.stdout.strip())
    if r.stderr.strip():
        print("STDERR:", r.stderr.strip())
    print("-----")
    return r

# B.1-B.6 Compaction base
run('openclaw config set agents.defaults.compaction.enabled true')
run('openclaw config set agents.defaults.compaction.mode "summarize-middle"')
run('openclaw config set agents.defaults.compaction.keepRecentTokens 40000')
run('openclaw config set agents.defaults.compaction.maxHistoryShare 0.5')
run('openclaw config set agents.defaults.compaction.summarizerModel "openrouter/moonshotai/kimi-k2.6"')
run('openclaw config set agents.defaults.compaction.preserveTags \'["decision", "fact", "action-required"]\'')

# B.7-B.8 memoryFlush
run('openclaw config set agents.defaults.compaction.memoryFlush.enabled true')
run('openclaw config set agents.defaults.compaction.memoryFlush.model "openrouter/moonshotai/kimi-k2.6"')

# B.9 contextPruning
run('openclaw config set agents.defaults.contextPruning.mode "cache-ttl"')

# B.10 contextInjection
run('openclaw config set agents.defaults.contextInjection "continuation-skip"')

# Doctor & Restart
run('openclaw doctor --fix')
run('systemctl --user restart openclaw-gateway')
run('chmod 600 ~/.openclaw/openclaw.json')

# Verification
run('openclaw doctor --deep | tail -n 25')
