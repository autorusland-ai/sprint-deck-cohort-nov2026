#!/bin/bash
# ============================================================================
# status.sh — Healthcheck OpenClaw на VPS
# ============================================================================
# Проверяет:
#   - daemon (systemctl)
#   - openclaw doctor
#   - gateway listen (порт 18789)
#   - spending command availability
#   - model status
#   - RAM, диск
# ============================================================================

set -e

cd "$(dirname "$0")/.." || exit 1

if [ ! -f ".env" ]; then
  echo "❌ .env не найден"
  exit 1
fi
set -a
# shellcheck disable=SC1091
source .env
set +a

: "${VPS_USER:=clawd}"
SSH_KEY="${HOME}/.ssh/clawd_ed25519"
SSH="ssh -i $SSH_KEY"
OPENCLAW_BIN="/home/clawd/.npm-global/bin/openclaw"
if [ -n "${VPS_IP:-}" ]; then
  VPS="${VPS_USER}@${VPS_IP}"
elif [ -n "${SSH_ALIAS:-}" ]; then
  VPS="${SSH_ALIAS}"
else
  echo "❌ VPS_IP не задан и SSH_ALIAS пустой"
  exit 1
fi

echo "🔍 OpenClaw Healthcheck — $(date)"
echo "===================================="
echo ""

echo "📦 Daemon:"
if $SSH "$VPS" 'systemctl --user is-active openclaw-gateway' 2>/dev/null | grep -q active; then
  echo "  ✅ Active"
else
  echo "  ❌ Down"
  $SSH "$VPS" 'systemctl --user status openclaw-gateway --no-pager 2>&1 | head -5'
fi

echo ""
echo "🩺 openclaw doctor:"
$SSH "$VPS" "$OPENCLAW_BIN doctor --deep 2>&1 | tail -10" || echo "  ⚠️  doctor недоступен"

echo ""
echo "🌐 Gateway (порт 18789):"
if $SSH "$VPS" 'ss -tlnp 2>/dev/null | grep -q 18789'; then
  echo "  ✅ Listening on 127.0.0.1:18789"
else
  echo "  ❌ Не слушает"
fi

echo ""
echo "💰 Spending today:"
echo "  ⚠️  openclaw spend недоступен в этой версии CLI"

echo ""
echo "🤖 Model status:"
$SSH "$VPS" "$OPENCLAW_BIN models status --plain 2>/dev/null | sed 's/^/  /'" 2>/dev/null || echo "  ⚠️  models status недоступен"

echo ""
echo "📊 Memory:"
$SSH "$VPS" 'free -h | grep Mem | awk "{print \"  RAM: \" \$3 \" / \" \$2 \" used\"}"'

echo ""
echo "💾 Disk:"
$SSH "$VPS" 'df -h / | tail -1 | awk "{print \"  Disk: \" \$3 \" / \" \$2 \" (\" \$5 \" used)\"}"'

echo ""
echo "🔥 Top OpenClaw processes:"
$SSH "$VPS" 'ps aux | grep -i openclaw | grep -v grep | head -3 | awk "{printf \"  PID %s: %s%% CPU, %s%% RAM — %s\\n\", \$2, \$3, \$4, \$11}"'

echo ""
echo "===================================="
echo "Done."
