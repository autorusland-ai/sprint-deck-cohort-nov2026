#!/usr/bin/env bash
# Полный шифрованный снимок состояния бота.
# Запуск: вручную перед обновлением openclaw + по cron раз в неделю.
#
# ВНИМАНИЕ: парольная фраза ниже лежит открытым текстом в этом файле, то есть
# защищает архив только при выносе за пределы VPS, а не от того, у кого есть
# доступ к машине. Менять её нельзя молча — старые архивы расшифровываются
# только прежней фразой.
set -u
cd ~ || exit 1

BACKUP_DIR="$HOME/.openclaw/backups"
BACKUP_PATH="$BACKUP_DIR/openclaw-backup-$(date +%Y%m%d%H%M%S).tgz"
KEEP=8   # снимков хранить (≈2 месяца при еженедельном запуске)
mkdir -p "$BACKUP_DIR"

# В архив кладём только невосстановимое: правила бота, конфиг, ключи, скрипты,
# историю сессий. Всё, что ставится заново одной командой или качается снова
# (зависимости, кэши, медиа, профили браузера), исключаем — иначе архив
# распухает почти на гигабайт и его перестают делать.
tar -czf "$BACKUP_PATH" \
    --exclude='.openclaw/backups' \
    --exclude='.openclaw/npm/node_modules' \
    --exclude='.openclaw/qdrant/storage' \
    --exclude='.openclaw/qdrant-data' \
    --exclude='.openclaw/media' \
    --exclude='.openclaw/cache' \
    --exclude='.openclaw/browser-profiles' \
    --exclude='.openclaw/agents/*/agent/codex-home' \
    --exclude='.openclaw/logs' \
    --exclude='*.trajectory.jsonl' \
    .openclaw/ 2>/dev/null

gpg --batch --yes --passphrase "openclaw-safe-backup" --symmetric "$BACKUP_PATH"
rm -f "$BACKUP_PATH"

# Ротация: старые снимки удаляем, иначе диск заполнится молча.
ls -t "$BACKUP_DIR"/openclaw-backup-*.tgz.gpg 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f

echo "Снимок готов: ${BACKUP_PATH}.gpg ($(du -h "${BACKUP_PATH}.gpg" | cut -f1))"
echo "Снимков в хранилище: $(ls "$BACKUP_DIR"/openclaw-backup-*.tgz.gpg 2>/dev/null | wc -l)"
