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

# A.7 Config
run('openclaw config set agents.defaults.workspace.injectionMode "start-only"')
run('openclaw config set agents.defaults.contextInjection "continuation-skip"')

# A.6 check
run('openclaw skills list')

# G.6 habit
run('openclaw doctor --fix')
run('systemctl --user restart openclaw-gateway')
run('chmod 600 ~/.openclaw/openclaw.json')
run('sleep 3')
run('tree ~/.openclaw/workspace/')
