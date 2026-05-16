import os
import subprocess

cmds = {
    "devices": "bash -lc 'openclaw devices list'",
    "models": "bash -lc 'openclaw models status'",
    "channels": "bash -lc 'openclaw channels list'",
    "doctor": "bash -lc 'openclaw doctor --deep | tail -n 25'",
    "crontab": "crontab -l",
    "status": "systemctl --user status openclaw-gateway --no-pager | head -n 10"
}

results = {}
for name, cmd in cmds.items():
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        results[name] = r.stdout + r.stderr
    except Exception as e:
        results[name] = str(e)

print("--- devices ---")
print(results["devices"])
print("--- models ---")
print(results["models"])
print("--- channels ---")
print(results["channels"])
print("--- doctor ---")
print(results["doctor"])
print("--- crontab ---")
print(results["crontab"])
print("--- status ---")
print(results["status"])
