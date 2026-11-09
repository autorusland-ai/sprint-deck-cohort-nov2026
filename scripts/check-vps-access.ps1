# Read-only connectivity probes through the two existing SSH aliases; no route changes.
$ErrorActionPreference='Continue'
foreach($alias in @('clawd-vps-tail','clawd-vps')){
 Write-Output "Checking configured alias: $alias"
 & ssh -o BatchMode=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 $alias 'printf "SSH_OK\n"; id -un; date -Is'
 if($LASTEXITCODE -eq 0){Write-Output "REACHABLE_ALIAS=$alias";exit 0}
 Write-Output "Alias unavailable (exit $LASTEXITCODE)"
}
exit 1
