import os
import subprocess

def run(cmd):
    print(f"RUNNING: {cmd}")
    r = subprocess.run(f"bash -lc '{cmd}'", shell=True, capture_output=True, text=True)
    if r.stdout.strip():
        print("STDOUT:", r.stdout.strip())
    if r.stderr.strip():
        print("STDERR:", r.stderr.strip())
    print("-----")
    return r

run('sudo apt-get install -y git-crypt git')

run('cd ~/.openclaw && git init -b main')

gitignore = """openclaw.json
*.token
*.key
secrets/**
.env
qdrant/storage/**
tmp/
logs/
*.ogg
agents/*/sessions/cache/
"""
with open("/tmp/.gitignore", "w") as f:
    f.write(gitignore)
run('cp /tmp/.gitignore ~/.openclaw/.gitignore')

run('touch ~/.openclaw/README.md')
run('cd ~/.openclaw && git config --global user.email "bot@example.com" && git config --global user.name "Bot"')
run('cd ~/.openclaw && git add .gitignore README.md && git commit -m "Initial commit with gitignore"')

run('cd ~/.openclaw && git-crypt init')

gitattributes = """openclaw.json filter=git-crypt diff=git-crypt
*.token filter=git-crypt diff=git-crypt
secrets/** filter=git-crypt diff=git-crypt
.env filter=git-crypt diff=git-crypt
"""
with open("/tmp/.gitattributes", "w") as f:
    f.write(gitattributes)
run('cp /tmp/.gitattributes ~/.openclaw/.gitattributes')

run('cd ~/.openclaw && git add .gitattributes openclaw.json')
run('cd ~/.openclaw && git commit -m "Add git-crypt and encrypt config"')
run('cd ~/.openclaw && git-crypt status')

run('cd ~/.openclaw && git-crypt export-key ~/openclaw-gitcrypt.key && chmod 600 ~/openclaw-gitcrypt.key')
run('ls -l ~/openclaw-gitcrypt.key')
