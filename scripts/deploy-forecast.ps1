param([switch]$Apply)
# Targeted forecast release; never uploads openclaw.json, secrets, persona or cron.
$ErrorActionPreference = 'Stop'
$stage = '/home/clawd/.openclaw/forecast-release-2026-11-09'
function Remote([string]$command) {
 & ssh -o BatchMode=yes -o ConnectTimeout=10 clawd-vps-tail $command.Replace("`r",'')
 if ($LASTEXITCODE -ne 0) { throw "Remote step failed ($LASTEXITCODE)" }
}
if (-not $Apply) {
 Remote "mkdir -p '$stage/deploy/scripts' '$stage/tests' '$stage/skills'; rm -f '$stage/VERIFIED'"
 foreach ($name in @('astro-cli.py','astro-daily.sh','astro-weekly.sh')) {
  & scp "deploy/scripts/$name" "clawd-vps-tail:${stage}/deploy/scripts/$name"
  if ($LASTEXITCODE -ne 0) { throw "Upload failed: $name" }
 }
 & scp tests/test_astro_cli.py "clawd-vps-tail:${stage}/tests/test_astro_cli.py"
 if ($LASTEXITCODE -ne 0) { throw 'Test upload failed' }
 & scp skills/astro-forecast/SKILL.md "clawd-vps-tail:${stage}/skills/openclaw-SKILL.md"
 if ($LASTEXITCODE -ne 0) { throw 'Skill upload failed' }
 & scp hermes-ivanych/vps/.hermes/skills/research/astro-bazi-forecast/SKILL.md "clawd-vps-tail:${stage}/skills/hermes-SKILL.md"
 if ($LASTEXITCODE -ne 0) { throw 'Hermes skill upload failed' }
 Remote @'
set -eu
STAGE=/home/clawd/.openclaw/forecast-release-2026-11-09
python3 - "$STAGE" <<'PY'
import pathlib,sys
root=pathlib.Path(sys.argv[1])
for p in list((root/'deploy/scripts').glob('*'))+list((root/'tests').glob('*.py'))+list((root/'skills').glob('*.md')):
 p.write_text(p.read_text(encoding='utf-8-sig').replace('\r\n','\n'),encoding='utf-8',newline='\n')
PY
bash -n "$STAGE/deploy/scripts/astro-daily.sh"
bash -n "$STAGE/deploy/scripts/astro-weekly.sh"
cd "$STAGE"
/home/clawd/browser-env/bin/python3.12 -B -m unittest discover -s tests -p test_astro_cli.py -v
/home/clawd/browser-env/bin/python3.12 deploy/scripts/astro-cli.py all 2026-11-08 > control-2026-11-08.txt
sha256sum deploy/scripts/* tests/test_astro_cli.py skills/* > SHA256SUMS
touch VERIFIED
printf '\nSTAGING VERIFIED; live files unchanged\n'
'@
 exit 0
}
# Require a committed snapshot of these exact local source files before live writes.
& git diff --exit-code HEAD -- deploy/scripts/astro-cli.py deploy/scripts/astro-daily.sh deploy/scripts/astro-weekly.sh tests/test_astro_cli.py skills/astro-forecast/SKILL.md
if ($LASTEXITCODE -ne 0) { throw 'Commit reviewed forecast sources before applying' }
Remote @'
set -eu
STAGE=/home/clawd/.openclaw/forecast-release-2026-11-09
test -f "$STAGE/VERIFIED"
cd "$STAGE"
sha256sum -c SHA256SUMS
BACKUP="$STAGE/backup-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -m 700 "$BACKUP"
for name in astro-cli.py astro-daily.sh astro-weekly.sh; do
 cp -p "/home/clawd/.openclaw/scripts/$name" "$BACKUP/$name"
done
for name in _астро-данные-сегодня.md _астро-данные-неделя.md; do
 test ! -f "/home/clawd/emmbase/life/прогнозы/$name" || cp -p "/home/clawd/emmbase/life/прогнозы/$name" "$BACKUP/$name"
done
sudo -n cp -p /home/hermes/.hermes/skills/research/astro-bazi-forecast/SKILL.md "$BACKUP/hermes-SKILL.md"
# Fail before writes if upload did not pass tests; install CLI atomically first.
for name in astro-cli.py astro-daily.sh astro-weekly.sh; do
 owner=$(stat -c %u "/home/clawd/.openclaw/scripts/$name")
 group=$(stat -c %g "/home/clawd/.openclaw/scripts/$name")
 mode=$(stat -c %a "/home/clawd/.openclaw/scripts/$name")
 sudo -n install -o "$owner" -g "$group" -m "$mode" "$STAGE/deploy/scripts/$name" "/home/clawd/.openclaw/scripts/$name.new"
 sudo -n mv "/home/clawd/.openclaw/scripts/$name.new" "/home/clawd/.openclaw/scripts/$name"
done
mkdir -p /home/clawd/.openclaw/workspace/skills/astro-forecast
install -m 644 "$STAGE/skills/openclaw-SKILL.md" /home/clawd/.openclaw/workspace/skills/astro-forecast/SKILL.md
sudo -n install -o hermes -g hermes -m 644 "$STAGE/skills/hermes-SKILL.md" /home/hermes/.hermes/skills/research/astro-bazi-forecast/SKILL.md
/home/clawd/.openclaw/scripts/astro-daily.sh
/home/clawd/.openclaw/scripts/astro-weekly.sh
printf '\nBACKUP=%s\n' "$BACKUP"
systemctl --user is-active openclaw-gateway
sudo -n systemctl --user -M hermes@ is-active hermes-gateway
printf '\nTargeted forecast release installed; no restart and no model call.\n'
'@
