#!/usr/bin/env bash
# Снапшот /emmbase/inbox/ раз в час — на случай если Claude/Syncthing/что-то ещё
# удалит файлы до того как Руслан успеет их увидеть.
#
# Логика: hardlink-based snapshot (как Time Machine).
# - Раз в час считается отпечаток (fingerprint) содержимого inbox
# - Если отпечаток совпал с прошлым запуском → снапшот НЕ создаётся,
#   в лог пишется короткая строка "без изменений"
# - Если изменился → создаётся snapshot-YYYY-MM-DD_HH/ через rsync --link-dest=
# - Hardlinks → дисковое место не растёт, пока файл не меняется
# - Хранится 7 дней snapshot'ов
#
# Отпечаток = sha256 от отсортированного списка "тип|относительный путь|размер|mtime"
# по всем файлам/каталогам/симлинкам внутри inbox (mtime с наносекундами).
# Любое добавление, удаление, переименование или правка файла меняет отпечаток.
# При любой ошибке подсчёта отпечатка снапшот делается принудительно
# (лучше лишний снапшот, чем пропущенный).
#
# Восстановление: cp -a ~/.openclaw/backups/inbox-snapshot/snapshot-LATEST/файл ~/emmbase/inbox/

set -u

SRC=/home/clawd/emmbase/inbox
BACKUP_ROOT=/home/clawd/.openclaw/backups/inbox-snapshot
LOG=/home/clawd/.openclaw/scripts/inbox-snapshot.log
STATE=/home/clawd/.openclaw/backups/inbox-snapshot/.fingerprint
RETAIN_DAYS=7

mkdir -p "$BACKUP_ROOT"
ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

# Ротация старых snapshot'ов (>RETAIN_DAYS дней) — выполняется в любом случае.
# Самый свежий снапшот не удаляем никогда: теперь снапшоты создаются редко,
# и без этой защиты «тихий» inbox за 8 дней остался бы вообще без бэкапа.
rotate() {
    local keep
    keep=$(ls -1d "$BACKUP_ROOT"/snapshot-* 2>/dev/null | sort -r | head -1)
    find "$BACKUP_ROOT" -maxdepth 1 -type d -name 'snapshot-*' -mtime +$RETAIN_DAYS \
         ! -path "$keep" -exec rm -rf {} \; 2>>"$LOG"
}

[ -d "$SRC" ] || { echo "$(ts) [skip] source missing: $SRC" >> "$LOG"; exit 0; }

NEW_SNAPSHOT="$BACKUP_ROOT/snapshot-$(date -u '+%Y-%m-%d_%H')"
LATEST_LINK="$BACKUP_ROOT/LATEST"

# --- Отпечаток текущего содержимого inbox --------------------------------
# NUL-разделители + sort -z → корректно для любых имён файлов (пробелы, \n, юникод)
FP=""
TMPLIST=$(mktemp "${TMPDIR:-/tmp}/inbox-fp.XXXXXX" 2>/dev/null) || TMPLIST=""
if [ -n "$TMPLIST" ]; then
    trap 'rm -f "$TMPLIST"' EXIT
    if find "$SRC" -mindepth 1 -printf '%y|%P|%s|%T@\0' > "$TMPLIST" 2>>"$LOG"; then
        FP=$(LC_ALL=C sort -z < "$TMPLIST" 2>>"$LOG" | sha256sum 2>>"$LOG" | cut -d' ' -f1)
    fi
    rm -f "$TMPLIST"
    trap - EXIT
fi
# Некорректный отпечаток → считаем что изменилось (принудительный снапшот)
case "$FP" in
    [0-9a-f][0-9a-f]*) : ;;
    *) FP="" ;;
esac

# --- Сравнение с прошлым запуском ----------------------------------------
PREV_FP=""
PREV_NAME=""
if [ -f "$STATE" ]; then
    read -r PREV_FP PREV_NAME < "$STATE" 2>/dev/null || { PREV_FP=""; PREV_NAME=""; }
fi

# "Без изменений" только если: отпечаток посчитан, совпал с прошлым,
# и каталог того снапшота реально на месте (не съеден ротацией).
if [ -n "$FP" ] && [ "$FP" = "$PREV_FP" ] && [ -n "$PREV_NAME" ] && [ -d "$BACKUP_ROOT/$PREV_NAME" ]; then
    FILES=$(find "$BACKUP_ROOT/$PREV_NAME" -type f 2>/dev/null | wc -l)
    echo "$(ts) [skip] без изменений (последний: $PREV_NAME) files=$FILES" >> "$LOG"
    rotate
    exit 0
fi

# --- Изменилось (или первый запуск) → создаём снапшот --------------------
# Найти предыдущий snapshot для hardlink-копии (кроме текущего часа)
PREV_SNAPSHOT=$(ls -1d "$BACKUP_ROOT"/snapshot-* 2>/dev/null | grep -vxF "$NEW_SNAPSHOT" | sort -r | head -1)

# --delete нужно, если снапшот за текущий час уже существует (повторный запуск
# после удаления файла) — иначе удалённый файл остался бы висеть в снапшоте.
# --checksum: быстрая проверка rsync сравнивает mtime с точностью до секунды и
# пропустила бы правку того же размера в пределах одной секунды. Inbox ~2.5 МБ,
# и снапшот теперь делается только при изменениях — цена сверки копеечная.
if [ -n "$PREV_SNAPSHOT" ]; then
    rsync -a --checksum --delete --link-dest="$PREV_SNAPSHOT" "$SRC/" "$NEW_SNAPSHOT/" 2>>"$LOG"
else
    rsync -a --checksum --delete "$SRC/" "$NEW_SNAPSHOT/" 2>>"$LOG"
fi

# Обновить LATEST симлинк
ln -snf "$NEW_SNAPSHOT" "$LATEST_LINK"

# Подсчитать что в snapshot'е
FILES=$(find "$NEW_SNAPSHOT" -type f 2>/dev/null | wc -l)
SIZE=$(du -sh "$NEW_SNAPSHOT" 2>/dev/null | cut -f1)
echo "$(ts) [snapshot] $(basename "$NEW_SNAPSHOT") files=$FILES size=$SIZE" >> "$LOG"

# Запомнить отпечаток. Если посчитать не удалось — состояние сбрасываем,
# чтобы следующий запуск снова сделал снапшот, а не решил "без изменений".
if [ -n "$FP" ]; then
    printf '%s %s\n' "$FP" "$(basename "$NEW_SNAPSHOT")" > "$STATE"
else
    rm -f "$STATE"
fi

rotate
