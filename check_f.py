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

# Install gh and gitleaks
run('curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null && sudo apt update && sudo apt install gh -y')

run('curl -sSfL https://raw.githubusercontent.com/gitleaks/gitleaks/master/install.sh | sudo sh -s -- -b /usr/local/bin')

# E.8 gitleaks pre-commit
pre_commit = """#!/usr/bin/env bash
gitleaks protect -v --staged
"""
with open("/tmp/pre-commit", "w") as f: f.write(pre_commit)
run('mkdir -p ~/.openclaw/.git/hooks && cp /tmp/pre-commit ~/.openclaw/.git/hooks/pre-commit && chmod +x ~/.openclaw/.git/hooks/pre-commit')

gitleaks_toml = """
[allowlist]
paths = [
    '''openclaw.json''',
    '''.env''',
    '''secrets/.*'''
]
"""
with open("/tmp/.gitleaks.toml", "w") as f: f.write(gitleaks_toml)
run('cp /tmp/.gitleaks.toml ~/.openclaw/.gitleaks.toml')
run('cd ~/.openclaw && git add .gitleaks.toml && git commit -m "Add gitleaks allowlist"')

# E.10-E.13 Autocommit script
autocommit_sh = """#!/usr/bin/env bash
exec 200>/tmp/openclaw-autocommit.lock
flock -n 200 || exit 1

cd ~/.openclaw || exit 1

stage_workspace_if_exists() {
  local p="$1"
  if [ -e "$p" ] || [ -d "$p" ]; then
    git add "$p" 2>/dev/null
  fi
}

stage_workspace_if_exists "workspace/MEMORY.md"
stage_workspace_if_exists "workspace/SOUL.md"
stage_workspace_if_exists "workspace/USER.md"
stage_workspace_if_exists "workspace/AGENTS.md"
stage_workspace_if_exists "workspace/IDENTITY.md"
stage_workspace_if_exists "workspace/HEARTBEAT.md"
stage_workspace_if_exists "workspace/memory"
stage_workspace_if_exists "workspace/archive"
stage_workspace_if_exists "RECOVERY.md"
stage_workspace_if_exists "REPORT-W2.md"
stage_workspace_if_exists ".gitignore"
stage_workspace_if_exists ".gitattributes"

# Blocklist Guard
BLOCKED=$(git diff --cached --name-only | grep -E "openclaw\.json|auth-profiles\.json|secrets/|\.env|\.token$|\.key$")
if [ -n "$BLOCKED" ]; then
  git reset HEAD
  echo "Blocked files detected in staging! Aborting."
  exit 1
fi

# Commit
if ! git diff --cached --quiet; then
  git commit -m "Auto-backup $(date +'%Y-%m-%d %H:%M')" || exit 0
  git checkout -b auto/cron 2>/dev/null || git checkout auto/cron
fi
"""
run('mkdir -p ~/.openclaw/scripts')
with open("/tmp/openclaw-autocommit.sh", "w") as f: f.write(autocommit_sh)
run('cp /tmp/openclaw-autocommit.sh ~/.openclaw/scripts/openclaw-autocommit.sh && chmod +x ~/.openclaw/scripts/openclaw-autocommit.sh')

# Permission watchdog script F.5
watchdog_sh = """#!/usr/bin/env bash
cd ~/.openclaw || exit 1
for file in openclaw.json workspace/SOUL.md auth-profiles.json secrets/*; do
  if [ -e "$file" ]; then
    perms=$(stat -c "%a" "$file")
    if [ "$perms" != "600" ]; then
      chmod 600 "$file"
      echo "Fixed perms for $file"
      if [ -f .env ]; then
        source .env
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
          -d chat_id="${TELEGRAM_USER_ID}" \
          -d text="🚨 Watchdog: Исправлены права $file на 600"
      fi
    fi
  fi
done
"""
with open("/tmp/permission-watchdog.sh", "w") as f: f.write(watchdog_sh)
run('cp /tmp/permission-watchdog.sh ~/.openclaw/scripts/permission-watchdog.sh && chmod +x ~/.openclaw/scripts/permission-watchdog.sh')

# Cron setup
cron = """0 * * * * ~/.openclaw/scripts/openclaw-autocommit.sh
0 23 * * * cd ~/.openclaw && git checkout main && git merge auto/cron --squash && git commit -m "Daily Squash"
*/15 * * * * ~/.openclaw/scripts/permission-watchdog.sh
"""
with open("/tmp/crontab.txt", "w") as f: f.write(cron)
run('crontab /tmp/crontab.txt')

# E.14 RECOVERY.md
recovery_md = """# OpenClaw Disaster Recovery Runbook

## Сценарий 1: VPS сгорел (Disaster Recovery)
1. Подними новый VPS на Ubuntu 24.04.
2. `git clone https://github.com/твоё_имя/openclaw-backup.git ~/.openclaw`
3. Установи `git-crypt` и достань ключ из менеджера паролей:
   `git-crypt unlock /path/to/openclaw-gitcrypt.key`
4. Выполни `openclaw doctor --fix`
5. `systemctl --user restart openclaw-gateway`

## Сценарий 2: git-crypt ключ потерян
1. Ключ не восстановить.
2. Если токены потеряны, перевыпусти их у провайдеров.
3. Удали репо, создай новый `git init`, настрой конфиг с нуля.

## Сценарий 3: Бот не отвечает в Telegram
1. `ssh clawd@VPS_IP`
2. `systemctl --user status openclaw-gateway`
3. `openclaw logs --tail 50`
4. Проверь наличие баланса у провайдеров или лимиты `openclaw doctor`.
"""
with open("/tmp/RECOVERY.md", "w") as f: f.write(recovery_md)
run('cp /tmp/RECOVERY.md ~/.openclaw/RECOVERY.md')
