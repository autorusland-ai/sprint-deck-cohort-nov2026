$remote = @'
sudo -n python3 - <<'PY'
import pathlib,re,json,collections
print('=== RECENT ERROR CLASSES: LAST 2000 LINES ===')
for name in ['gateway.log','agent.log']:
 p=pathlib.Path('/home/hermes/.hermes/logs')/name
 lines=p.read_text(errors='replace').splitlines()[-2000:]
 print(name,'first:',lines[0][:24],'last:',lines[-1][:24])
 for term in ['429','401','403','Traceback','ConnectTimeout','ReadTimeout','polling recovered','ERROR']:
  hits=[x for x in lines if term.lower() in x.lower()]
  print(term,'count',len(hits))
  for line in hits[-2:]:
   line=re.sub(r'https?://\S+','[URL]',line)
   line=re.sub(r'(?:sk-[\w-]+|\d{7,}:[A-Za-z0-9_-]+|Bearer\s+\S+)','[REDACTED]',line)
   print(line[:450])
p=pathlib.Path('/home/clawd/.openclaw/openclaw.json')
d=json.loads(p.read_text())
print('=== OPENCLAW MODEL ROUTES ONLY ===')
print('agent defaults model',d.get('agents',{}).get('defaults',{}).get('model'))
print('model identifiers',{k:[x.get('id') for x in v.get('models',[])] for k,v in d.get('models',{}).get('providers',{}).items()})
print('=== OPENCLAW SKILL / SANDBOX PATHS ===')
print('skill dirs',d.get('skills',{}).get('load',{}).get('extraDirs'))
print('skill flags',{k:{x:v.get(x) for x in ['enabled','path']} for k,v in d.get('skills',{}).get('entries',{}).items()})
print('workspace',d.get('agents',{}).get('defaults',{}).get('workspace'))
print('sandbox mounts',d.get('agents',{}).get('defaults',{}).get('sandbox',{}).get('docker',{}).get('binds'))
print('=== ASTRO JOB CONFIG CHECKS ===')
d=json.loads(pathlib.Path('/home/hermes/.hermes/cron/jobs.json').read_text())
for j in (d if isinstance(d,list) else d.get('jobs',[])):
 if j.get('id') in ['1171d7294c81','c47518283de5']:
  print('job',j['id'],'keys',list(j))
  for k in ['script','schedule','timezone','skills','skill']: print(k,j.get(k))
  text=str(j)
  print('policy markers',{s:s in text for s in ['Плацидус','слабый сигнал','Дополнительно','08:00','astro_calc']})
PY
'@
& ssh -o BatchMode=yes -o ConnectTimeout=10 clawd-vps-tail $remote.Replace("`r",'')
exit $LASTEXITCODE
