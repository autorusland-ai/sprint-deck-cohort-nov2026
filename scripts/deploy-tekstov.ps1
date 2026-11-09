param([ValidateSet('clawd-vps-tail','clawd-vps')][string]$SshAlias='clawd-vps-tail',[switch]$Apply)
# Targeted writing-skill installation only. No cron, model, network or service edits.
$ErrorActionPreference='Stop'
Set-Location (Join-Path $PSScriptRoot '..')
$package='hermes-ivanych/skill-packages/tekstov'
& python -B -m unittest discover -s tests -p test_tekstov_skill.py -v
if($LASTEXITCODE -ne 0){throw 'Local package validation failed'}
& ssh -o BatchMode=yes -o ConnectTimeout=10 $SshAlias 'printf "SSH_OK\n"'
if($LASTEXITCODE -ne 0){throw 'SSH unavailable; nothing deployed'}
$stage='/home/clawd/.openclaw/tekstov-release-2026-11-09'
& ssh -o BatchMode=yes -o ConnectTimeout=10 $SshAlias "mkdir -p '$stage'"
if($LASTEXITCODE -ne 0){throw 'Staging setup failed'}
& scp -r $package "${SshAlias}:${stage}/"
if($LASTEXITCODE -ne 0){throw 'Package upload failed'}
$validate=@'
python3 - <<'PY'
from pathlib import Path
import json,hashlib,re
root=Path('/home/clawd/.openclaw/tekstov-release-2026-11-09/tekstov')
text=(root/'SKILL.md').read_text()
assert text.startswith('---\nname: tekstov\n')
manifest=json.loads((root/'SOURCES.json').read_text())
assert len(manifest['references'])==4
for ref in manifest['references']:
 path=root/ref['package_path']
 assert path.is_relative_to(root) and path.is_file()
 assert hashlib.sha256(path.read_bytes()).hexdigest()==ref['package_sha256']
assert len([p for p in root.rglob('*') if p.is_file()])==7
for ref in re.findall(r'<(references/[^>]+)>',text): assert (root/ref).is_file()
print('Remote package valid; staged only')
PY
'@
& ssh -o BatchMode=yes -o ConnectTimeout=10 $SshAlias $validate.Replace("`r",'')
if($LASTEXITCODE -ne 0){throw 'Remote package validation failed'}
if(-not $Apply){Write-Output 'Validated stage, live skill directories unchanged';exit 0}
# Guard the committed source snapshot; never commit unrelated changes here.
& git diff --exit-code HEAD -- skills/tekstov scripts/deploy-tekstov.ps1 tests/test_tekstov_skill.py
if($LASTEXITCODE -ne 0){throw 'Commit reviewed writing sources before Apply'}
& git -C hermes-ivanych diff --exit-code HEAD -- skill-packages/tekstov
if($LASTEXITCODE -ne 0){throw 'Commit private reference package before Apply'}
$install=@'
sudo -n python3 - <<'PY'
from pathlib import Path
from datetime import datetime,timezone
import shutil,os,pwd,hashlib,json
stage=Path('/home/clawd/.openclaw/tekstov-release-2026-11-09')
source=stage/'tekstov'
backup=stage/('backup-'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
backup.mkdir(mode=0o700)
targets=[('openclaw',Path('/home/clawd/.openclaw/workspace/skills/tekstov'),'clawd'),('hermes',Path('/home/hermes/.hermes/skills/productivity/tekstov'),'hermes')]
# Inspect all destinations before any live write; do not copy secret-looking extras.
for name,target,user in targets:
 if target.is_symlink():raise RuntimeError('Refusing symlink skill destination')
 if target.exists():
  for p in target.rglob('*'):
   assert not p.is_symlink() and (not p.is_file() or p.suffix in ['.md','.json']),'Unexpected existing skill payload; stop'
  shutil.copytree(target,backup/name)
 else:(backup/(name+'-previously-absent.txt')).write_text(str(target)+'\n')
receipt={'installed_at_utc':datetime.now(timezone.utc).isoformat(),'backup':str(backup),'targets':[]}
for name,target,user in targets:
 account=pwd.getpwnam(user)
 temp=target.with_name(target.name+'.install-staging')
 assert not temp.exists(),'Existing install staging; inspect before retry'
 temp.parent.mkdir(parents=True,exist_ok=True)
 shutil.copytree(source,temp)
 for p in [temp]+list(temp.rglob('*')):
  os.chown(p,account.pw_uid,account.pw_gid)
  os.chmod(p,0o755 if p.is_dir() else 0o644)
 # Skill is small; backups exist before this rename. Preserve old tree until success.
 previous=target.with_name(target.name+'.previous-'+backup.name)
 if target.exists():target.rename(previous)
 temp.rename(target)
 for p in source.rglob('*'):
  if p.is_file(): assert p.read_bytes()==(target/p.relative_to(source)).read_bytes()
 receipt['targets'].append({'bot':name,'path':str(target),'skill_sha256':hashlib.sha256((target/'SKILL.md').read_bytes()).hexdigest(),'references':4})
(stage/'INSTALL-RECEIPT.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(receipt,ensure_ascii=False,indent=2))
PY
'@
& ssh -o BatchMode=yes -o ConnectTimeout=10 $SshAlias $install.Replace("`r",'')
if($LASTEXITCODE -ne 0){throw 'Install not confirmed; inspect remote state and backups before retry'}
# Read-only discovery, bounded in time. File installation alone is not a prose-quality test.
$discover=@'
printf '\n=== OpenClaw discovery ===\n'
timeout 30 /home/clawd/.npm-global/bin/openclaw skills list --json | python3 -c 'import sys,json; s=sys.stdin.read(); d=json.loads(s[s.index("{"):]); print([dict((k,x.get(k)) for k in ["name","eligible","disabled","source"]) for x in d.get("skills",[]) if x.get("name")=="tekstov"])'
printf '\n=== Hermes discovery ===\n'
sudo -n -iu hermes timeout 30 /home/hermes/.local/bin/hermes skills list
'@
& ssh -o BatchMode=yes -o ConnectTimeout=10 $SshAlias $discover.Replace("`r",'')
if($LASTEXITCODE -ne 0){throw 'Files installed but CLI discovery not confirmed; inspect output'}
