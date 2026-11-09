$ErrorActionPreference = 'Stop'
$target = 'audit/forecast-2026-11-09'
New-Item -ItemType Directory -Force $target | Out-Null
$files = @{
 'astro-cli.py'='/home/clawd/.openclaw/scripts/astro-cli.py';
 'astro-daily.sh'='/home/clawd/.openclaw/scripts/astro-daily.sh';
 'astro-weekly.sh'='/home/clawd/.openclaw/scripts/astro-weekly.sh';
 'astro_calc.py'='/home/hermes/.hermes/scripts/astro_calc.py';
 'astro_calc_run.py'='/home/hermes/.hermes/scripts/astro_calc_run.py';
 'astro_week_run.py'='/home/hermes/.hermes/scripts/astro_week_run.py';
 'hermes-SKILL.md'='/home/hermes/.hermes/skills/research/astro-bazi-forecast/SKILL.md'
}
foreach ($name in $files.Keys) {
 $content = & ssh -o BatchMode=yes -o ConnectTimeout=10 clawd-vps-tail "sudo -n cat '$($files[$name])'"
 if ($LASTEXITCODE -ne 0) { throw "Download failed: $name" }
 $content | Set-Content -Encoding utf8 "$target/$name"
 Write-Output "Fetched $name"
}
