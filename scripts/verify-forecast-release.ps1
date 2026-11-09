$remote = @'
set -eu
printf '\n=== LIVE CALCULATION ===\n'
/home/clawd/.openclaw/scripts/astro-cli.py natal
/home/clawd/browser-env/bin/python3.12 - <<'PY'
import importlib.util,pathlib,hashlib,datetime
p='/home/clawd/.openclaw/scripts/astro-cli.py'
spec=importlib.util.spec_from_file_location('astro',p);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
for ds,expected in [('1900-01-01','甲戌'),('2000-01-01','戊午'),('2026-08-05','辛亥'),('1971-05-05','庚寅'),('2026-11-08','丙戌')]:
 pillar=m.pillars(datetime.date.fromisoformat(ds))[2]
 got=m.STEMS[pillar[0]]+m.BRANCHES[pillar[1]]
 assert got==expected,(ds,got,expected)
 print('Day anchor OK:',ds,got)
for name in ['astro-cli.py','astro-daily.sh','astro-weekly.sh']:
 live=pathlib.Path('/home/clawd/.openclaw/scripts')/name
 staged=pathlib.Path('/home/clawd/.openclaw/forecast-release-2026-11-09/deploy/scripts')/name
 assert live.read_bytes()==staged.read_bytes(),name
 print('Live matches tested source:',name)
for name in ['_астро-данные-сегодня.md','_астро-данные-неделя.md']:
 p=pathlib.Path('/home/clawd/emmbase/life/прогнозы')/name
 text=p.read_text()
 assert '08:00 МСК' in text and '09:00 МСК' not in text
 assert 'Плацидуса' in text and 'ДОПОЛНИТЕЛЬНЫЕ АСПЕКТЫ' in text
 assert '甲申' in text and '壬辰' in text
 assert 'Traceback' not in text
 print('Published:',text.splitlines()[0],p.stat().st_size,'bytes')
 if 'неделя' in name: assert text.count('\n## ')==7
PY
printf '\n=== BOT SERVICES / TELEGRAM ===\n'
systemctl --user is-active openclaw-gateway
sudo -n systemctl --user -M hermes@ is-active hermes-gateway
curl -s -o /dev/null --max-time 20 -w 'Telegram HTTP %{http_code}\n' https://api.telegram.org
printf '\n=== OPENCLAW SKILL DISCOVERY ===\n'
if timeout 30 /home/clawd/.npm-global/bin/openclaw skills list --json > /home/clawd/.openclaw/forecast-release-2026-11-09/skill-check.json 2>/home/clawd/.openclaw/forecast-release-2026-11-09/skill-check.err; then
 python3 - <<'PY'
import json,pathlib
p=pathlib.Path('/home/clawd/.openclaw/forecast-release-2026-11-09/skill-check.json')
s=p.read_text();d=json.loads(s[s.index('{'):])
for item in d.get('skills',[]):
 if 'astro' in item.get('name',''): print({k:item.get(k) for k in ['name','eligible','disabled','source']})
PY
else
 echo 'Skill discovery CLI did not complete within 30 seconds; file installation only is confirmed.'
fi
'@
& ssh -o BatchMode=yes -o ConnectTimeout=10 clawd-vps-tail $remote.Replace("`r",'')
exit $LASTEXITCODE
