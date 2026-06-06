#!/usr/bin/env bash
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
stage_workspace_if_exists "workspace/skills/web-quick/SKILL.md"
stage_workspace_if_exists "workspace/skills/page-reader/SKILL.md"
stage_workspace_if_exists "workspace/skills/deep-research/SKILL.md"
stage_workspace_if_exists "workspace/skills/browser-agent/SKILL.md"
stage_workspace_if_exists "workspace/skills/mail-handler/SKILL.md"
stage_workspace_if_exists "workspace/skills/calendar-keeper/SKILL.md"
stage_workspace_if_exists "REPORT-W3.md"
stage_workspace_if_exists ".gitignore"
stage_workspace_if_exists ".gitattributes"

# Learnings stage (auto-created files)
git ls-files --others --modified -- '.learnings/*.md' 2>/dev/null | xargs -r git add

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
