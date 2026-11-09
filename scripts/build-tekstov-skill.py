"""Package the user-provided writing references for PRIVATE storage and both bots.
No IDE rules, SEO bundle, macOS metadata, credentials or external downloads.
"""
from pathlib import Path
import hashlib
import json
import re

ROOT=Path(__file__).resolve().parents[1]
SOURCE=Path('C:/PROJECTS/EMMBASE/agents/skill-tekstov')
WRITER=SOURCE/'╨а╨╛╨╗╨╕ ╨в╨╡╨║╤Б╤В╤Л'/'writer'
PACKAGE=ROOT/'hermes-ivanych/skill-packages/tekstov'
HISTORY=ROOT/'hermes-ivanych/docs/history/2026-11-09-writing'
NAMES=['pishi-sokraschaj-konspekt.md','kurs-silnogo-teksta-ilyahov.md',
       'yasno-ponyatno-ilyahov-full.md','bolshaya_kniga_o_sotssetyakh_ilyakhov_skryabin.md']
SECRET=re.compile(r'(?:sk-(?:proj-|cp-)?[A-Za-z0-9_-]{24,}|gh[pousr]_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{25,}|[0-9]{8,12}:[A-Za-z0-9_-]{30,}|-----BEGIN (?:OPENSSH |RSA |EC )?PRIVATE KEY-----)')

def sha(data): return hashlib.sha256(data).hexdigest()
def save(path,data,immutable=False):
    assert not SECRET.search(data.decode('utf-8-sig')), 'Possible credential: '+path.name
    if path.exists():
        if path.read_bytes()==data:return
        assert not immutable,'Preserve original history, create a new version: '+str(path)
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(data)

def normalized(path): return path.read_text(encoding='utf-8-sig').replace('\r\n','\n').encode('utf-8')
records=[]
for name in NAMES:
    source=WRITER/'knowledge'/name
    raw=source.read_bytes()
    data=normalized(source)
    save(PACKAGE/'references'/name,data)
    save(HISTORY/'source/writer/knowledge'/name,raw,True)
    records.append({'source_relative':source.relative_to(SOURCE).as_posix(),
                    'original_sha256':sha(raw),'package_path':'references/'+name,'package_sha256':sha(data),'bytes':len(data)})
role=WRITER/'_role_writer.md'
raw=role.read_bytes()
save(HISTORY/'source/writer/_role_writer.md',raw,True)
for name in ['SKILL.md','EVAL.md']:
    save(PACKAGE/name,normalized(ROOT/'skills/tekstov'/name))
manifest={'schema':1,'skill':'tekstov','source':'user-provided skill-tekstov folder',
          'source_role_sha256':sha(raw),'references':records,
          'scope':'Writer role and four reference summaries; IDE rules, SEO, metadata excluded',
          'privacy':'Source summaries remain in the private repository; do not publish the reference bundle in the public fork',
          'learning':'Prompt/skill integration and reference retrieval, not weight training'}
encoded=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
save(PACKAGE/'SOURCES.json',encoded)
save(HISTORY/'SOURCE-MANIFEST.json',encoded,True)
for path in PACKAGE.rglob('*'):
    if path.is_file():
        assert path.suffix in {'.md','.json'} and '__MACOSX' not in str(path) and '.DS_Store' not in str(path)
print('Built private tekstov package: native skill, evaluation cases, four references and source hashes.')
