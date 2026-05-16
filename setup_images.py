import os
import json

p = '/home/clawd/.openclaw/openclaw.json'
with open(p) as f:
    c = json.load(f)

c.setdefault('agents', {}).setdefault('defaults', {})
c['agents']['defaults'].setdefault('imageGenerationModel', {})
c['agents']['defaults']['imageGenerationModel']['primary'] = "openrouter/google/gemini-2.5-flash-image"
c['agents']['defaults']['imageGenerationModel']['fallbacks'] = ["openrouter/black-forest-labs/flux-schnell"]

c.setdefault('tools', {})['profile'] = "full"

with open(p, 'w') as f:
    json.dump(c, f, indent=2)

print("Config updated. Restarting gateway...")
os.system('systemctl --user restart openclaw-gateway')
os.system('sleep 5')
print("Running openclaw doctor...")
os.system('bash -lc "openclaw doctor --deep | tail -n 10"')
