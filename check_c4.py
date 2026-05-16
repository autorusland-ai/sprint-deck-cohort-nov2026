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

run('cd ~/.openclaw && sudo docker-compose -f docker-compose.qdrant.yml up -d')
run('sleep 3')
run('ss -tlnp | grep 6333')
run('systemctl --user restart openclaw-gateway')
run('sleep 5')
run('openclaw memory add "$(cat ~/.openclaw/workspace/MEMORY.md)"')
run('openclaw memory list')
