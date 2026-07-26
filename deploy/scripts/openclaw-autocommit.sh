#!/usr/bin/env bash
# Автокоммит состояния бота. Cron: раз в час.
#
# Два независимых репозитория:
#   ~/.openclaw            — служебные файлы + openclaw.json (шифруется git-crypt), есть origin
#   ~/.openclaw/workspace  — ПРАВИЛА БОТА (SOUL/IDENTITY/USER/AGENTS/skills), отдельный вложенный репо
#
# История поломки: скрипт делал `git add workspace/...` из РОДИТЕЛЬСКОГО репо, но
# workspace — вложенный git-репозиторий, поэтому добавление молча проваливалось
# (ошибка глушилась через 2>/dev/null). С 22.05.2026 не коммитилось вообще ничего,
# при этом cron исправно отрабатывал и выглядел здоровым. Теперь каждый репозиторий
# коммитится своей командой, а неудачи пишутся в лог, а не проглатываются.
set -u

exec 200>/tmp/openclaw-autocommit.lock
flock -n 200 || exit 1

ROOT=/home/clawd/.openclaw
WS="$ROOT/workspace"
LOG="$ROOT/logs/autocommit.log"
mkdir -p "$(dirname "$LOG")"
log() { echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $*" >> "$LOG"; }

# Секреты не коммитим ни при каких обстоятельствах. auth-profiles.json содержит
# ключи всех провайдеров и НЕ покрыт фильтрами git-crypt — только этот список
# и защищает его от попадания в историю.
BLOCK_RE='openclaw\.json|auth-profiles\.json|auth-state\.json|secrets/|\.env$|\.token$|\.key$'

commit_repo() {
  local dir="$1" what="$2"
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || { log "[$what] не git-репозиторий, пропуск"; return; }

  local blocked
  blocked=$(git -C "$dir" diff --cached --name-only | grep -E "$BLOCK_RE" || true)
  if [ -n "$blocked" ]; then
    git -C "$dir" reset -q HEAD
    log "[$what] СТОП: в индексе секреты, коммит отменён: $(echo "$blocked" | tr '\n' ' ')"
    return
  fi

  git -C "$dir" diff --cached --quiet && return

  if git -C "$dir" commit -q -m "Auto-backup $(date +'%Y-%m-%d %H:%M')"; then
    log "[$what] коммит: $(git -C "$dir" log --oneline -1)"
  else
    log "[$what] ОШИБКА коммита"
    return
  fi

  # Выгрузка наружу — только если настроен origin и есть рабочие учётные данные.
  # Сейчас на VPS креды GitHub отсутствуют (push встал в мае), поэтому шаг
  # пропускается с записью в лог; как только владелец добавит токен, выгрузка
  # заработает сама, без правок скрипта.
  if git -C "$dir" remote get-url origin >/dev/null 2>&1; then
    if timeout 90 git -C "$dir" push -q origin HEAD 2>>"$LOG"; then
      log "[$what] выгружено в origin"
    else
      log "[$what] выгрузка не удалась (нет учётных данных GitHub?) — копия только локальная"
    fi
  else
    log "[$what] origin не настроен — копия только локальная"
  fi
}

# --- Родительский репозиторий: служебные файлы ------------------------------
cd "$ROOT" || exit 1
for p in RECOVERY.md REPORT-W2.md REPORT-W3.md .gitignore .gitattributes; do
  [ -e "$p" ] && { git add "$p" 2>>"$LOG" || log "[root] не удалось добавить $p"; }
done
git ls-files --others --modified -- '.learnings/*.md' 2>/dev/null | xargs -r git add 2>>"$LOG"
commit_repo "$ROOT" "root"

# --- Вложенный репозиторий: правила и навыки бота ---------------------------
# Здесь именно то, что дороже всего восстанавливать вручную.
if [ -d "$WS/.git" ]; then
  git -C "$WS" add -A 2>>"$LOG" || log "[workspace] не удалось добавить изменения"
  commit_repo "$WS" "workspace"
else
  log "[workspace] .git отсутствует — правила бота нигде не версионируются!"
fi
