#!/usr/bin/env bash
cd ~/.openclaw || exit 1
for file in openclaw.json workspace/SOUL.md auth-profiles.json secrets/*; do
  if [ -e "$file" ]; then
    perms=$(stat -c "%a" "$file")
    if [ "$perms" != "600" ]; then
      chmod 600 "$file"
      echo "Fixed perms for $file"
      if [ -f .env ]; then
        source .env
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"           -d chat_id="${TELEGRAM_USER_ID}"           -d text="???? Watchdog: ???????????????????? ?????????? $file ???? 600"
      fi
    fi
  fi
done
