#!/bin/bash
export PATH=$HOME/.npm-global/bin:$PATH

LIMIT=3.00
TG_TOKEN="8527528241:AAHJtz8WUu81dVDOzHlbCzg7kRJGmIoiDSg"
TG_USER_ID="215087477"

COST=$(openclaw spend --json 2>/dev/null | grep -oP '"total_usd":\s*\K[0-9.]+' || echo "0")
if [ -z "$COST" ]; then COST="0"; fi

if (( $(echo "$COST > $LIMIT" | bc -l) )); then
    systemctl --user stop openclaw-gateway
    curl -s "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_USER_ID&text=🚨 KILL SWITCH: spend \$$COST > \$$LIMIT, daemon stopped."
fi

OC_JSON="/home/clawd/.openclaw/openclaw.json"
if [ -f "$OC_JSON" ]; then
    PERM=$(stat -c %a "$OC_JSON")
    if [ "$PERM" != "600" ]; then
        chmod 600 "$OC_JSON"
        curl -s "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_USER_ID&text=⚠️ Watchdog fixed openclaw.json permissions to 600 (was $PERM)"
    fi
fi
