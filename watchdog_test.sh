#!/bin/bash
set -euo pipefail
export PATH=$HOME/.npm-global/bin:$PATH

LIMIT="${OPENCLAW_WATCHDOG_TEST_LIMIT:-0.001}"
TG_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TG_USER_ID="${TELEGRAM_USER_ID:-215087477}"

COST="10.00"

if (( $(echo "$COST > $LIMIT" | bc -l) )); then
    systemctl --user stop openclaw-gateway
    if [ -n "$TG_TOKEN" ] && [ -n "$TG_USER_ID" ]; then
        curl -s "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
            -d "chat_id=$TG_USER_ID&text=🚨 KILL SWITCH TEST: spend \$$COST > \$$LIMIT, daemon stopped." >/dev/null || true
    fi
fi
