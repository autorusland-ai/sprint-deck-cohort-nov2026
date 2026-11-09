# Deploy only the locally reviewed natal block; preserve live forecast history.
$ErrorActionPreference='Stop'
$stage='/home/clawd/.openclaw/forecast-release-2026-11-09'
& scp 'C:\PROJECTS\EMMBASE\life\прогнозирование.md' "clawd-vps-tail:${stage}/reviewed-note.md"
if($LASTEXITCODE -ne 0){throw 'Note upload failed'}
& scp audit/forecast-2026-11-09/natal-before.md "clawd-vps-tail:${stage}/expected-natal-before.md"
if($LASTEXITCODE -ne 0){throw 'Expected block upload failed'}
$remote=@'
python3 - <<'PY'
from pathlib import Path
from datetime import datetime,timezone
import shutil,os
root=Path('/home/clawd/.openclaw/forecast-release-2026-11-09')
target=Path('/home/clawd/emmbase/life/прогнозирование.md')
def read(p): return p.read_text(encoding='utf-8-sig').replace('\r\n','\n')
old=read(root/'expected-natal-before.md').rstrip('\n')
source=read(root/'reviewed-note.md')
start=source.index('## Натальные данные Руслана')
end=source.index('\n### Полные источники',start)
new=source[start:end].rstrip('\n')
current=read(target)
if new in current:
 print('Reviewed natal block already synced; no write needed')
else:
 assert current.count(old)==1,'Live natal block differs from reviewed original; stopping without overwrite'
 backup=root/('forecast-note-backup-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'.md')
 shutil.copy2(target,backup)
 updated=current.replace(old,new,1)
 assert updated.split(new,1)==current.split(old,1),'Unexpected edit outside natal block'
 temp=target.with_name(target.name+'.astro-update.tmp')
 temp.write_text(updated,encoding='utf-8',newline='\n')
 shutil.copystat(target,temp)
 os.replace(temp,target)
 assert read(target)==updated
 print('Natal block deployed and verified; unchanged history; backup:',backup)
PY
'@
& ssh -o BatchMode=yes -o ConnectTimeout=10 clawd-vps-tail $remote.Replace("`r",'')
exit $LASTEXITCODE
