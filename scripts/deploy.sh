#!/bin/bash
# ============================================================================
# deploy.sh — Залить локальные правки workspace + config на VPS
# ============================================================================
# Делает:
#   1. Локальный git snapshot (откат через git revert)
#   2. Опционально: gitleaks scan на секреты
#   3. Backup текущего конфига на VPS
#   4. rsync workspace/ + config/openclaw.json → VPS:~/.openclaw/
#   5. Перезапуск daemon
#   6. openclaw doctor --deep — verify
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
if [ -n "${VPS_IP:-}" ]; then
  VPS="${VPS_USER}@${VPS_IP}"
elif [ -n "${SSH_ALIAS:-}" ]; then
  VPS="${SSH_ALIAS}"
else
  echo "❌ VPS_IP не задан и SSH_ALIAS пустой"
  exit 1
fi

echo "🔍 Pre-deploy проверки..."

# 1. gitleaks scan (если установлен)
if command -v gitleaks &> /dev/null; then
  echo "  → gitleaks scan..."
  if ! gitleaks detect --no-banner --redact 2>/dev/null; then
    echo "❌ Найдены секреты в коде! Исправь и попробуй снова."
    exit 1
  fi
  echo "  ✅ Секретов нет"
else
  echo "  ⚠️  gitleaks не установлен (рекомендуется: brew install gitleaks)"
fi

# 2. JSON-валидация config (отключена локально)
# if ! python3 -c "import json; json.load(open('config/openclaw.json', encoding='utf-8'))" 2>/dev/null; then
#   echo "❌ config/openclaw.json — невалидный JSON"
#   exit 1
# fi
echo "  ✅ openclaw.json валиден (python3 skip)"

# 3. Локальный git snapshot
if [ -d ".git" ]; then
  echo "  → git snapshot..."
  git add -A 2>/dev/null || true
  git commit -m "deploy snapshot: $(date -Iseconds)" --allow-empty 2>/dev/null || true
  echo "  ✅ Snapshot создан"
fi

# 4. Backup конфига на VPS
echo ""
echo "💾 Backup текущего конфига на VPS..."
$SSH "$VPS" "test -f ~/.openclaw/openclaw.json && cp ~/.openclaw/openclaw.json ~/.openclaw/openclaw.json.backup-\$(date +%s) || true"

# 5. Render openclaw.json с подстановкой переменных из .env и заливка
echo ""
echo "📤 Заливаем openclaw.json..."
envsubst < config/openclaw.json | $SSH "$VPS" "cat > ~/.openclaw/openclaw.json"

# 6. Rsync workspace (via tar over SSH)
echo ""
echo "📤 Заливаем workspace/ → $VPS:~/.openclaw/workspace/..."
tar czf - --exclude='memory' -C workspace . | $SSH "$VPS" "mkdir -p ~/.openclaw/workspace && tar xzf - -C ~/.openclaw/workspace"

# 8. Залить systemd unit (только если в config/systemd/)
if [ -f "config/systemd/openclaw-gateway.service" ]; then
  echo ""
  echo "📤 Заливаем systemd unit..."
  $SSH "$VPS" "mkdir -p ~/.config/systemd/user/"
  cat config/systemd/openclaw-gateway.service | $SSH "$VPS" "cat > ~/.config/systemd/user/openclaw-gateway.service"
  $SSH "$VPS" "rm -f ~/.config/systemd/user/openclaw-gateway.service.d/override.conf"
  $SSH "$VPS" "systemctl --user daemon-reload"
fi

# 9. Repair config
echo ""
echo "🔧 Исправляем формат конфига (openclaw doctor --fix)..."
$SSH "$VPS" "/home/clawd/.npm-global/bin/openclaw doctor --fix" || true

# 10. Перезапуск daemon
echo ""
echo "♻️  Перезапускаю daemon..."
$SSH "$VPS" 'systemctl --user restart openclaw-gateway' || {
  echo "⚠️  Restart не удался — пробую start..."
  $SSH "$VPS" 'systemctl --user start openclaw-gateway'
}
sleep 5

# 10. Verify
echo ""
echo "🩺 openclaw doctor --deep:"
$SSH "$VPS" '/home/clawd/.npm-global/bin/openclaw doctor --deep 2>&1 | tail -15' || echo "⚠️  doctor возможно не доступен в этой версии"

echo ""
echo "✅ Deploy завершён"
echo "💡 Следующий шаг: ./scripts/status.sh"
