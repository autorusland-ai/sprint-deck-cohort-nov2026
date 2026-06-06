#!/bin/bash
set -euo pipefail
export PATH=$HOME/.npm-global/bin:$PATH

LIMIT="${OPENCLAW_WATCHDOG_LIMIT:-3.00}"
OPENCLAW_BIN="${OPENCLAW_BIN:-$HOME/.npm-global/bin/openclaw}"
TG_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TG_USER_ID="${TELEGRAM_USER_ID:-215087477}"
OC_JSON="/home/clawd/.openclaw/openclaw.json"

if [ -z "$TG_TOKEN" ] && [ -f "$OC_JSON" ] && command -v jq >/dev/null 2>&1; then
    TG_TOKEN=$(jq -r '.channels.telegram.botToken // ""' "$OC_JSON")
fi

alert() {
    local text="$1"
    if [ -n "$TG_TOKEN" ] && [ -n "$TG_USER_ID" ]; then
        curl -s "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
            -d "chat_id=$TG_USER_ID&text=$text" >/dev/null || true
    fi
}

stop_gateway() {
    systemctl --user stop openclaw-gateway || true
}

if ! COST_JSON=$("$OPENCLAW_BIN" spend --json 2>/dev/null); then
    stop_gateway
    alert "🚨 KILL SWITCH: cannot read OpenClaw spend; daemon stopped fail-closed."
    exit 1
fi

COST=$(printf '%s\n' "$COST_JSON" | grep -oP '"total_usd":\s*\K[0-9.]+' || true)
if [ -z "$COST" ]; then
    stop_gateway
    alert "🚨 KILL SWITCH: OpenClaw spend output has no total_usd; daemon stopped fail-closed."
    exit 1
fi

if (( $(echo "$COST > $LIMIT" | bc -l) )); then
    stop_gateway
    alert "🚨 KILL SWITCH: spend \$$COST > \$$LIMIT, daemon stopped."
fi

if [ -f "$OC_JSON" ]; then
    PERM=$(stat -c %a "$OC_JSON")
    if [ "$PERM" != "600" ]; then
        chmod 600 "$OC_JSON"
        alert "⚠️ Watchdog fixed openclaw.json permissions to 600 (was $PERM)"
    fi
fi
