# Read-only runtime calculation and bounded error summaries. No LLM requests.
$remote = @'
/home/clawd/browser-env/bin/python3.12 - <<'PY'
import swisseph as s
from datetime import datetime
from zoneinfo import ZoneInfo
print('=== INDEPENDENT EPHEMERIS ===')
f=s.FLG_MOSEPH|s.FLG_SPEED
birth=s.julday(1971,5,5,7+5/60)
c,a=s.houses(birth,43.8,131+59/60,b'P')
print('Timezone:',datetime(1971,5,5,17,5,tzinfo=ZoneInfo('Asia/Vladivostok')).isoformat())
print('Cusps:',c,'ASC/MC:',a[:2])
print('Natal Mercury:',s.calc_ut(birth,s.MERCURY,f)[0])
print('Equation of time minutes:',s.time_equ(birth)*1440)
for p in range(10):
 v=s.calc_ut(s.julday(2026,11,8,5),p,f)[0]
 print(p,round(v[0],6),round(v[3],6))
PY
printf '\n=== OPENCLAW CURRENT OUTPUT ===\n'
/home/clawd/.openclaw/scripts/astro-cli.py all 2026-11-08
printf '\n=== HERMES CURRENT OUTPUT ===\n'
sudo -n -u hermes /home/hermes/.hermes/venvs/astro/bin/python /home/hermes/.hermes/scripts/astro_calc.py 2026-11-08
printf '\n=== SKILL LOCATIONS ===\n'
find /home/clawd/.openclaw -maxdepth 6 -path '*astro*SKILL.md' -print
sudo -n find /home/hermes/.hermes/skills -maxdepth 5 -path '*astro*SKILL.md' -print
printf '\n=== ERROR COUNTS AND CRON STATUS (NO PROMPTS) ===\n'
sudo -n python3 - <<'PY'
import pathlib,re,json,collections
for root in ['/home/hermes/.hermes/logs','/home/clawd/.openclaw/logs']:
 for name in ['gateway.log','agent.log','astro-weekly.log']:
  p=pathlib.Path(root)/name
  if not p.exists(): continue
  lines=p.read_text(errors='replace').splitlines()[-5000:]
  terms=['error','timeout','429','401','403','traceback','failed','polling recovered','delivered']
  print(str(p),{t:sum(t in x.lower() for x in lines) for t in terms})
p=pathlib.Path('/home/hermes/.hermes/cron/jobs.json')
data=json.loads(p.read_text())
jobs=data if isinstance(data,list) else data.get('jobs',[])
for j in jobs:
 print({k:v for k,v in j.items() if k in ['id','name','enabled','paused','last_run_at','last_status','last_error','next_run_at','state']})
PY
'@
& ssh -o BatchMode=yes -o ConnectTimeout=10 clawd-vps-tail $remote.Replace("`r",'')
exit $LASTEXITCODE
