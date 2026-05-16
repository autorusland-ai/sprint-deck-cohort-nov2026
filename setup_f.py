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

run('mkdir -p ~/.openclaw/scripts ~/.openclaw/workspace/archive ~/.openclaw/backups')

archive_sh = """#!/usr/bin/env bash
mkdir -p ~/.openclaw/workspace/archive
find ~/.openclaw/workspace/memory/ -name "*.md" -mtime +30 -exec mv {} ~/.openclaw/workspace/archive/ \\;
"""
with open("/tmp/archive-memory.sh", "w") as f: f.write(archive_sh)
run('cp /tmp/archive-memory.sh ~/.openclaw/scripts/archive-memory.sh && chmod +x ~/.openclaw/scripts/archive-memory.sh')

run('openclaw config set agents.defaults.memorySearch.paths \'["workspace/memory", "workspace/archive"]\'')

digest_sh = """#!/usr/bin/env bash
cd ~/.openclaw || exit 1
MEM_FILES=$(find workspace/memory -mtime -7 -name "*.md" | sort)
if [ -z "$MEM_FILES" ]; then
    echo "No memory files for the past 7 days."
    exit 0
fi

CONTENT=$(cat $MEM_FILES)
PROMPT="Прочитай файлы memory/ за прошлые 7 дней: \\n\\n$CONTENT\\n\\nСуммируй: 3-5 ключевых тем, 5 фактов, 3 решения, action items на следующую неделю. Дай результат без лишних слов."

DIGEST=$(openclaw execute --model openrouter/moonshotai/kimi-k2.6 "$PROMPT")

echo "" >> workspace/MEMORY.md
echo "## Week of $(date +%Y-%m-%d)" >> workspace/MEMORY.md
echo "$DIGEST" >> workspace/MEMORY.md
"""
with open("/tmp/weekly-digest.sh", "w") as f: f.write(digest_sh)
run('cp /tmp/weekly-digest.sh ~/.openclaw/scripts/weekly-digest.sh && chmod +x ~/.openclaw/scripts/weekly-digest.sh')

pre_update_sh = """#!/usr/bin/env bash
cd ~ || exit 1
BACKUP_NAME="openclaw-backup-$(date +%Y%m%d%H%M%S).tgz"
BACKUP_PATH="$HOME/.openclaw/backups/$BACKUP_NAME"

echo "Creating tarball..."
tar -czf "$BACKUP_PATH" --exclude='.openclaw/backups' --exclude='.openclaw/qdrant/storage' .openclaw/ 2>/dev/null

echo "Encrypting with GPG..."
gpg --batch --yes --passphrase "openclaw-safe-backup" --symmetric "$BACKUP_PATH"
rm -f "$BACKUP_PATH"
echo "Backup created at ${BACKUP_PATH}.gpg"
"""
with open("/tmp/pre-update-backup.sh", "w") as f: f.write(pre_update_sh)
run('cp /tmp/pre-update-backup.sh ~/.openclaw/scripts/pre-update-backup.sh && chmod +x ~/.openclaw/scripts/pre-update-backup.sh')

cron_add = """0 3 * * 0 ~/.openclaw/scripts/archive-memory.sh
0 10 * * 1 ~/.openclaw/scripts/weekly-digest.sh
"""
with open("/tmp/cron_f.txt", "w") as f: f.write(cron_add)
run('crontab -l | grep -v "archive-memory" | grep -v "weekly-digest" > /tmp/current_cron 2>/dev/null || true')
run('cat /tmp/current_cron /tmp/cron_f.txt | crontab -')

run('~/.openclaw/scripts/archive-memory.sh')
run('~/.openclaw/scripts/pre-update-backup.sh')
run('ls -lh ~/.openclaw/backups/')
