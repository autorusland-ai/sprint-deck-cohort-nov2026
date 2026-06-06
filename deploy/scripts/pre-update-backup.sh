#!/usr/bin/env bash
cd ~ || exit 1
BACKUP_NAME="openclaw-backup-$(date +%Y%m%d%H%M%S).tgz"
BACKUP_PATH="$HOME/.openclaw/backups/$BACKUP_NAME"

echo "Creating tarball..."
tar -czf "$BACKUP_PATH" --exclude='.openclaw/backups' --exclude='.openclaw/qdrant/storage' .openclaw/ 2>/dev/null

echo "Encrypting with GPG..."
gpg --batch --yes --passphrase "openclaw-safe-backup" --symmetric "$BACKUP_PATH"
rm -f "$BACKUP_PATH"
echo "Backup created at ${BACKUP_PATH}.gpg"
