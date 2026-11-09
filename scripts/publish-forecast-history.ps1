# Publish only reviewed audit commits and handoff. Never force-push or push upstream.
$ErrorActionPreference='Stop'
Set-Location (Join-Path $PSScriptRoot '..')
function Git {
 param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
 $output=& git.exe @Arguments
 if($LASTEXITCODE -ne 0){throw "Git command failed: $($Arguments[0])"}
 return $output
}
$publicUrl='https://github.com/autorusland-ai/sprint-deck-cohort-nov2026.git'
$privateUrl='https://github.com/autorusland-ai/ivanych-hermes.git'
if((Git @('remote','get-url','fork')) -ne $publicUrl){throw 'Unexpected public fork; refusing push'}
if((Git @('-C','hermes-ivanych','remote','get-url','origin')) -ne $privateUrl){throw 'Unexpected private remote; refusing push'}
if((Git @('branch','--show-current')) -ne 'main'){throw 'Unexpected COMANDOS branch'}
if((Git @('-C','hermes-ivanych','branch','--show-current')) -ne 'main'){throw 'Unexpected Hermes branch'}

# Credential helper stdout stays in memory. Never print helper fields or the token.
$query="protocol=https`nhost=github.com`n`n"
$credentialLines=$query | & git.exe credential fill
if($LASTEXITCODE -ne 0){throw 'GitHub credential helper unavailable'}
$token=$null
foreach($line in $credentialLines){if($line.StartsWith('password=')){$token=$line.Substring(9)}}
if(-not $token){throw 'No GitHub credential returned'}
$headers=@{Authorization="Bearer $token";Accept='application/vnd.github+json';'X-GitHub-Api-Version'='2022-11-28'}
$repo=Invoke-RestMethod -Uri 'https://api.github.com/repos/autorusland-ai/ivanych-hermes' -Headers $headers
if($repo.full_name -ne 'autorusland-ai/ivanych-hermes' -or $repo.private -ne $true){throw 'Hermes is NOT verified private; refusing publication'}
Write-Output 'GitHub confirms Hermes repository is private.'
$token=$null;$credentialLines=$null;$headers=$null

& python scripts/save-forecast-history.py --verify
if($LASTEXITCODE -ne 0){throw 'Archive verification failed'}
& python -B -m unittest discover -s tests -p test_tekstov_skill.py -v
if($LASTEXITCODE -ne 0){throw 'Writing skill package verification failed'}
$publicFiles=@('AGENTS.md','docs/SESSION-HANDOFF.md','scripts/save-forecast-history.py','scripts/capture-forecast-history.ps1','scripts/publish-forecast-history.ps1','skills/tekstov/SKILL.md','skills/tekstov/EVAL.md','scripts/build-tekstov-skill.py','scripts/deploy-tekstov.ps1','scripts/check-vps-access.ps1','tests/test_tekstov_skill.py')
$privateFiles=@('.gitattributes','docs/forecast-handoff-2026-11-09.md','docs/history/2026-11-09-forecast','docs/writing-handoff-2026-11-09.md','docs/history/2026-11-09-writing','skill-packages/tekstov')
# Do not absorb unrelated staged files into these commits.
foreach($name in @(Git @('-c','core.quotepath=false','diff','--cached','--name-only'))){if($name -and $name -notin $publicFiles){throw 'Unrelated staged COMANDOS change; stopping'}}
foreach($name in @(Git @('-c','core.quotepath=false','-C','hermes-ivanych','diff','--cached','--name-only'))){
 if(-not $name){continue}
 $allowed=$false
 foreach($prefix in $privateFiles){if($name -eq $prefix -or $name.StartsWith($prefix+'/')){$allowed=$true}}
 if(-not $allowed){throw 'Unrelated staged Hermes change; stopping'}
}

Git (@('add','--')+$publicFiles)
Git (@('-C','hermes-ivanych','add','--')+$privateFiles)
Git @('-C','hermes-ivanych','add','--renormalize','--','docs/history/2026-11-09-forecast','docs/history/2026-11-09-writing','skill-packages/tekstov/references')
Git @('diff','--cached','--check')
Git @('-C','hermes-ivanych','diff','--cached','--check')
# Verify Git stores immutable archive/reference bytes exactly (no LF/CRLF conversion).
foreach($name in @(Git @('-c','core.quotepath=false','-C','hermes-ivanych','diff','--cached','--name-only','--diff-filter=ACMR'))){
 if($name -like 'docs/history/*' -or $name -like 'skill-packages/tekstov/references/*'){
  $raw=Git @('-C','hermes-ivanych','hash-object','--no-filters','--',$name)
  $indexed=Git @('-C','hermes-ivanych','rev-parse',(':'+$name))
  if($raw -ne $indexed){throw "Git normalized immutable bytes: $name"}
 }
}
# Inspect every new/modified file in the outgoing snapshots without printing contents.
$pattern='(?:sk-(?:proj-|cp-)?[A-Za-z0-9_-]{24,}|gh[pousr]_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{25,}|[0-9]{8,12}:[A-Za-z0-9_-]{30,}|-----BEGIN (?:OPENSSH |RSA |EC )?PRIVATE KEY-----)'
foreach($spec in @(@{Folder='.';Base='c2285ae'},@{Folder='hermes-ivanych';Base='e5cfd30'})){
 $paths=@(Git @('-C',$spec.Folder,'diff','--cached','--name-only','--diff-filter=ACMR',$spec.Base))
 foreach($name in $paths){
  if(-not $name){continue}
  if($name -match '(^|/)(\.env($|\.)|secrets/|\.backups/|config\.yaml$|openclaw\.json$)'){throw 'Sensitive path in outgoing commit'}
  # Use literal paths: quoted Unicode names from git are disabled for this call below.
 }
 $paths=@(Git @('-c','core.quotepath=false','-C',$spec.Folder,'diff','--cached','--name-only','--diff-filter=ACMR',$spec.Base))
 foreach($name in $paths){
  if(-not $name){continue}
  $path=Join-Path $spec.Folder $name
  if([regex]::IsMatch([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $path)),$pattern)){throw "Possible credential in outgoing file: $name"}
 }
}
# Commit only the explicit paths, not the pre-existing knowledge-base/Obsidian changes.
& git.exe diff --cached --quiet
if($LASTEXITCODE -eq 1){Git (@('commit','-m','docs: preserve verified forecast audit and session handoff','--')+$publicFiles)}
elseif($LASTEXITCODE -ne 0){throw 'COMANDOS index check failed'}
& git.exe -C hermes-ivanych diff --cached --quiet
if($LASTEXITCODE -eq 1){Git (@('-C','hermes-ivanych','commit','-m','docs: archive forecast audit evidence and restoration handoff','--')+$privateFiles)}
elseif($LASTEXITCODE -ne 0){throw 'Hermes index check failed'}
Git @('-C','hermes-ivanych','push','origin','HEAD:refs/heads/main')
Git @('push','fork','HEAD:refs/heads/main')
$localPublic=Git @('rev-parse','HEAD')
$localPrivate=Git @('-C','hermes-ivanych','rev-parse','HEAD')
$remotePublic=((Git @('ls-remote','fork','refs/heads/main')) -split '\s+')[0]
$remotePrivate=((Git @('-C','hermes-ivanych','ls-remote','origin','refs/heads/main')) -split '\s+')[0]
if($localPublic -ne $remotePublic -or $localPrivate -ne $remotePrivate){throw 'GitHub SHA differs from local HEAD'}
$receipt=@{verified_at_utc=[DateTime]::UtcNow.ToString('o');public_fork=@{url=$publicUrl;sha=$remotePublic};private_hermes=@{url=$privateUrl;private_verified=$true;sha=$remotePrivate};archive_verified=$true;upstream_origin_pushed=$false;vps_fresh_capture=$false}
$receipt | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 audit/forecast-2026-11-09/GITHUB-VERIFIED.json
Write-Output "VERIFIED public fork: $remotePublic"
Write-Output "VERIFIED private Hermes: $remotePrivate"
Write-Output 'No upstream push; no force push; unrelated working changes preserved.'
