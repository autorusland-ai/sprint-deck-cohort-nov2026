"""Archive an explicit list of non-secret audit files into the PRIVATE Hermes repo.
Run from COMANDOS. Existing differing archive files are never overwritten.
--verify checks every recorded SHA256 without modifying files.
"""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / 'hermes-ivanych/docs/history/2026-11-09-forecast'
MANIFEST = ARCHIVE / 'MANIFEST.json'

def digest(data):
    return hashlib.sha256(data).hexdigest()

def verify():
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    for item in manifest['files']:
        path = ARCHIVE / item['path']
        assert path.is_relative_to(ARCHIVE), 'Invalid archive path'
        assert digest(path.read_bytes()) == item['sha256'], item['path']
    print('Verified archive SHA256:', len(manifest['files']), 'files')

if '--verify' in sys.argv:
    verify()
    raise SystemExit(0)

items = {}
for name in ['REPORT.md', 'astro-cli.py', 'astro-daily.sh', 'astro-weekly.sh',
             'astro_calc.py', 'astro_calc_run.py', 'astro_week_run.py',
             'hermes-SKILL.md', 'natal-before.md']:
    items['local/' + name] = ROOT / 'audit/forecast-2026-11-09' / name
vault = Path('C:/PROJECTS/EMMBASE')
for name in ['2026-11-08_1745_скилл-astro-forecast-v2-текст.md',
             '2026-11-08_1745_инструкция-починки-astro-cli.md',
             '2026-11-08_1745_решения-по-астропрогнозу.md']:
    items['input/' + name] = vault / 'inbox' / name
items['input/прогнозирование-after.md'] = vault / 'life/прогнозирование.md'
for name in ['astro-cli.py', 'astro-daily.sh', 'astro-weekly.sh']:
    items['installed/' + name] = ROOT / 'deploy/scripts' / name
items['installed/test_astro_cli.py'] = ROOT / 'tests/test_astro_cli.py'
items['installed/openclaw-SKILL.md'] = ROOT / 'skills/astro-forecast/SKILL.md'
items['installed/hermes-SKILL.md'] = ROOT / 'hermes-ivanych/vps/.hermes/skills/research/astro-bazi-forecast/SKILL.md'

# Fail closed on common live credential formats; print only the filename.
secret = re.compile(rb'(?:sk-(?:proj-|cp-)?[A-Za-z0-9_-]{24,}|gh[pousr]_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{25,}|[0-9]{8,12}:[A-Za-z0-9_-]{30,}|-----BEGIN (?:OPENSSH |RSA |EC )?PRIVATE KEY-----)')
for relative, source in items.items():
    data = source.read_bytes()
    assert not secret.search(data), 'Possible secret: ' + str(source.relative_to(ROOT) if source.is_relative_to(ROOT) else source.name)
    target = ARCHIVE / relative
    if target.exists():
        assert target.read_bytes() == data, 'Archive differs; preserve existing and create a new version: ' + relative
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)

files = []
for path in sorted(ARCHIVE.rglob('*')):
    if not path.is_file() or path == MANIFEST:
        continue
    data = path.read_bytes()
    assert not secret.search(data), 'Possible secret in archive: ' + str(path.relative_to(ARCHIVE))
    files.append({'path': path.relative_to(ARCHIVE).as_posix(), 'bytes': len(data), 'sha256': digest(data)})
manifest = {'schema': 1, 'recorded_at_utc': datetime.now(timezone.utc).isoformat(),
            'privacy': 'private repository only; no credentials/full config/backups with secrets',
            'scope': 'audit report, explicit input files, before/after sources and selected VPS evidence; not a full DSH chat export',
            'implementation_commits': {'COMANDOS': ['70816f8', 'e8bced5', 'f957f0c'], 'Hermes': ['5b56ef1']},
            'files': files}
if MANIFEST.exists():
    existing = json.loads(MANIFEST.read_text(encoding='utf-8'))
    assert existing['files'] == files, 'Existing manifest differs; archive is immutable'
else:
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
verify()
