# Read-only VPS evidence capture. Local writes go only to the private archive.
$ErrorActionPreference = 'Stop'
$archive = Join-Path $PSScriptRoot '../hermes-ivanych/docs/history/2026-11-09-forecast'
$remote = @'
sudo -n python3 - <<'PY'
from pathlib import Path
from datetime import datetime,timezone
import base64,hashlib,json,subprocess
stage=Path('/home/clawd/.openclaw/forecast-release-2026-11-09')
backup=stage/'backup-20261109T062944Z'
files={}
for name in ['astro-cli.py','astro-daily.sh','astro-weekly.sh','hermes-SKILL.md','_астро-данные-сегодня.md','_астро-данные-неделя.md']:
 files['backup/'+name]=backup/name
for name in ['_астро-данные-сегодня.md','_астро-данные-неделя.md']:
 files['live/'+name]=Path('/home/clawd/emmbase/life/прогнозы')/name
files['live/hermes-astro_calc.py']=Path('/home/hermes/.hermes/scripts/astro_calc.py')
files['staged-SHA256SUMS.txt']=stage/'SHA256SUMS'
result={'captured_at_utc':datetime.now(timezone.utc).isoformat(),'backup_path':str(backup),'files':[]}
for relative,path in files.items():
 data=path.read_bytes()
 result['files'].append({'path':relative,'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data),'base64':base64.b64encode(data).decode('ascii')})
test=subprocess.run(['/home/clawd/browser-env/bin/python3.12','-B','-m','unittest','discover','-s','tests','-p','test_astro_cli.py','-v'],cwd=stage,capture_output=True,text=True,timeout=60)
result['tests']={'exit_code':test.returncode,'stdout':test.stdout,'stderr':test.stderr}
result['live_matches_tested']={}
for name in ['astro-cli.py','astro-daily.sh','astro-weekly.sh']:
 result['live_matches_tested'][name]=(Path('/home/clawd/.openclaw/scripts')/name).read_bytes()==(stage/'deploy/scripts'/name).read_bytes()
print(json.dumps(result,ensure_ascii=False))
PY
'@
$lines = & ssh -o BatchMode=yes -o ConnectTimeout=10 clawd-vps-tail $remote.Replace("`r",'')
if($LASTEXITCODE -ne 0){throw 'VPS evidence collection failed'}
$payload = ($lines -join "`n") | ConvertFrom-Json
New-Item -ItemType Directory -Force (Join-Path $archive 'vps') | Out-Null
foreach($entry in $payload.files){
 if($entry.path -notmatch '^(backup/[^/]+|live/[^/]+|staged-SHA256SUMS\.txt)$'){throw 'Unexpected archive path'}
 $path=Join-Path $archive ('vps/'+$entry.path)
 if(Test-Path -LiteralPath $path){throw "Archive already exists; refusing overwrite: $($entry.path)"}
 New-Item -ItemType Directory -Force (Split-Path $path -Parent) | Out-Null
 [System.IO.File]::WriteAllBytes($path,[Convert]::FromBase64String($entry.base64))
}
# Save metadata/tests without duplicate base64 payloads.
foreach($entry in $payload.files){$entry.PSObject.Properties.Remove('base64')}
$record=Join-Path $archive 'vps/EVIDENCE.json'
if(Test-Path -LiteralPath $record){throw 'Evidence record already exists'}
$payload | ConvertTo-Json -Depth 10 | Set-Content -Encoding utf8 $record
if($payload.tests.exit_code -ne 0){throw 'Evidence saved, but VPS tests failed; inspect private record'}
foreach($property in $payload.live_matches_tested.PSObject.Properties){if(-not $property.Value){throw 'Live source differs from tested source'}}
Write-Output "Captured $($payload.files.Count) VPS artifacts; tests passed; live sources match"
