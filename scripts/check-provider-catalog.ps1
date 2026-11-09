$remote = @'
python3 - <<'PY'
import urllib.request,json,pathlib,re,os
url='https://router.mingles.ai/v1/models'
cfg=json.loads(pathlib.Path('/home/clawd/.openclaw/openclaw.json').read_text())
p=cfg.get('models',{}).get('providers',{}).get('gonka',{})
from urllib.parse import urlsplit
base=p.get('baseUrl','').rstrip('/')
u=urlsplit(base)
if base != url.rsplit('/',1)[0]:
 print('Configured catalog endpoint:',u.scheme,u.hostname,u.port,u.path)
 raise SystemExit('Catalog not checked: expected host differs; no credentials sent')
key=p.get('apiKey','')
if re.fullmatch(r'\$\{\w+\}',key): key=cfg.get('env',{}).get(key[2:-1],os.environ.get(key[2:-1],''))
request=urllib.request.Request(url,headers={'Authorization':'Bearer '+key})
try:
 with urllib.request.urlopen(request,timeout=20) as r: data=json.load(r)
 print('GONKA catalog ids:',[x.get('id') for x in data.get('data',[])])
except Exception as e: print('Catalog check inconclusive:',type(e).__name__,str(e)[:100])
PY
'@
& ssh -o BatchMode=yes -o ConnectTimeout=10 clawd-vps-tail $remote.Replace("`r",'')
exit $LASTEXITCODE
