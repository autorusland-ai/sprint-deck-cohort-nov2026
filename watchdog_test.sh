#!/bin/bash
export PATH=$HOME/.npm-global/bin:$PATH

LIMIT=0.001
TG_TOKEN="8527528241:AAHJtz8WUu81dVDOzHlbCzg7kRJGmIoiDSg"
TG_USER_ID="215087477"

COST="10.00"

if (( $(echo "$COST > $LIMIT" | bc -l) )); then
    systemctl --user stop openclaw-gateway
    curl -s "https://api.telegram.org/bot$TG_TOKEN/sendMessage" -d "chat_id=$TG_USER_ID&text=🚨 KILL SWITCH TEST: spend \$$COST > \$$LIMIT, daemon stopped."
fi
