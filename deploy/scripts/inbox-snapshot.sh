#!/usr/bin/env bash
# Снапшот /emmbase/inbox/ раз в час — на случай если Claude/Syncthing/что-то ещё
# удалит файлы до того как Руслан успеет их увидеть.
#
# Логика: hardlink-based snapshot (как Time Machine).
# - Каждый час создаётся snapshot-YYYY-MM-DD_HH/ через rsync --link-dest=
# - Hardlinks → дисковое место не растёт, пока файл не меняется
# - Хранится 7 дней snapshot'ов
#
# Восстановление: cp -a ~/.openclaw/backups/inbox-snapshot/snapshot-LATEST/файл ~/emmbase/inbox/

set -u

SRC=/home/clawd/emmbase/inbox
BACKUP_ROOT=/home/clawd/.openclaw/backups/inbox-snapshot
LOG=/home/clawd/.openclaw/scripts/inbox-snapshot.log
RETAIN_DAYS=7

mkdir -p "$BACKUP_ROOT"
ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

[ -d "$SRC" ] || { echo "$(ts) [skip] source missing: $SRC" >> "$LOG"; exit 0; }

NEW_SNAPSHOT="$BACKUP_ROOT/snapshot-$(date -u '+%Y-%m-%d_%H')"
LATEST_LINK="$BACKUP_ROOT/LATEST"

# Найти предыдущий snapshot для hardlink-копии
PREV_SNAPSHOT=$(ls -1d "$BACKUP_ROOT"/snapshot-* 2>/dev/null | sort -r | head -1)

if [ -n "$PREV_SNAPSHOT" ] && [ "$PREV_SNAPSHOT" != "$NEW_SNAPSHOT" ]; then
    rsync -a --link-dest="$PREV_SNAPSHOT" "$SRC/" "$NEW_SNAPSHOT/" 2>>"$LOG"
elif [ ! -d "$NEW_SNAPSHOT" ]; then
    rsync -a "$SRC/" "$NEW_SNAPSHOT/" 2>>"$LOG"
fi

# Обновить LATEST симлинк
ln -snf "$NEW_SNAPSHOT" "$LATEST_LINK"

# Подсчитать что в snapshot'е
FILES=$(find "$NEW_SNAPSHOT" -type f 2>/dev/null | wc -l)
SIZE=$(du -sh "$NEW_SNAPSHOT" 2>/dev/null | cut -f1)
echo "$(ts) [snapshot] $(basename "$NEW_SNAPSHOT") files=$FILES size=$SIZE" >> "$LOG"

# Очистить старые snapshot'ы (>RETAIN_DAYS дней)
find "$BACKUP_ROOT" -maxdepth 1 -type d -name 'snapshot-*' -mtime +$RETAIN_DAYS -exec rm -rf {} \; 2>>"$LOG"
