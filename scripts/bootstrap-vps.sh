#!/bin/bash
# ============================================================================
# bootstrap-vps.sh — Полная автоматическая настройка нового VPS для OpenClaw
# ============================================================================
# Использование: ./scripts/bootstrap-vps.sh <VPS_IP>
# 
# Скрипт выполнит:
# 1. Создание пользователя clawd и настройку SSH
# 2. Установку зависимостей (Node 22, Docker, ufw, fail2ban)
# 3. Настройку Swap 2GB и файрвола (только SSH)
# 4. Установку OpenClaw и Playwright
# 5. Запуск векторной базы Qdrant
# 6. Перенос секретов из .env
# 7. Финальный запуск ./scripts/deploy.sh
# ============================================================================

set -e

cd "$(dirname "$0")/.." || exit 1

if [ -z "$1" ]; then
  echo "❌ Ошибка: Укажите IP-адрес нового сервера."
  echo "Использование: ./scripts/bootstrap-vps.sh <VPS_IP>"
  exit 1
fi

NEW_VPS_IP="$1"
ROOT_VPS="root@$NEW_VPS_IP"
CLAWD_VPS="clawd@$NEW_VPS_IP"
SSH_KEY="${HOME}/.ssh/clawd_ed25519"

echo "🚀 Начинаем развертывание OpenClaw на сервере $NEW_VPS_IP"

# 0. Проверка .env
if [ ! -f ".env" ]; then
  echo "❌ .env не найден. Скопируйте .env.example в .env и заполните токены."
  exit 1
fi
set -a
source .env
set +a

# 1. SSH ключи
if [ ! -f "$SSH_KEY" ]; then
    echo "🔑 SSH ключ $SSH_KEY не найден. Создаю новый..."
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N ""
fi

echo "1/8 🔑 Копируем публичный ключ пользователю root..."
ssh-copy-id -i "${SSH_KEY}.pub" "$ROOT_VPS" || {
  echo "⚠️ Не удалось скопировать ключ через ssh-copy-id."
  echo "Убедитесь, что вы можете подключиться по паролю, или скопируйте ключ вручную."
}

echo "2/8 👤 Создаем безопасного пользователя 'clawd'..."
ssh -i "$SSH_KEY" "$ROOT_VPS" "
  if ! id -u clawd >/dev/null 2>&1; then
    adduser --disabled-password --gecos \"\" clawd
    usermod -aG sudo clawd
  fi
  mkdir -p /home/clawd/.ssh
  cp /root/.ssh/authorized_keys /home/clawd/.ssh/
  chown -R clawd:clawd /home/clawd/.ssh
  chmod 700 /home/clawd/.ssh
  echo 'clawd ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/90-clawd >/dev/null
"

echo "3/8 ⚙️  Базовая настройка сервера (Swap, UFW, Fail2ban)..."
ssh -i "$SSH_KEY" "$CLAWD_VPS" "sudo -S bash -c '
  apt update && apt upgrade -y
  apt install -y curl git ufw fail2ban build-essential wget

  # Защита от Out-of-Memory: Swap 2 GB
  if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo \"/swapfile none swap sw 0 0\" >> /etc/fstab
  fi

  # Firewall (разрешаем только SSH)
  ufw --force enable
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow ssh

  # Безопасность
  systemctl enable --now fail2ban
  loginctl enable-linger clawd
'"

echo "4/8 📦 Установка Node 22 LTS и Docker..."
ssh -i "$SSH_KEY" "$CLAWD_VPS" "sudo -S bash -c '
  if ! command -v node >/dev/null 2>&1 || [[ \"\$(node -v)\" != v22* ]]; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt install -y nodejs
  fi

  if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker clawd
  fi
'"

echo "5/8 🤖 Установка OpenClaw и браузера..."
ssh -i "$SSH_KEY" "$CLAWD_VPS" "
  # Глобальная установка npm-пакетов без sudo
  mkdir -p ~/.npm-global
  npm config set prefix '~/.npm-global'
  if ! grep -q '~/.npm-global/bin' ~/.bashrc; then
    echo 'export PATH=\"\$HOME/.npm-global/bin:\$PATH\"' >> ~/.bashrc
  fi
  export PATH=\"\$HOME/.npm-global/bin:\$PATH\"

  npm install -g openclaw@latest
  
  # Структура папок OpenClaw
  mkdir -p ~/.openclaw/{secrets,workspace,memory,browser-profiles/main,state,logs,config/systemd/user}
  chmod 700 ~/.openclaw/secrets

  # Playwright (для browser tool)
  npx playwright install --with-deps chromium
"

echo "6/8 🔐 Настройка секретов (Telegram Token)..."
ssh -i "$SSH_KEY" "$CLAWD_VPS" "
  echo '${TELEGRAM_BOT_TOKEN}' > ~/.openclaw/secrets/telegram.token
  chmod 600 ~/.openclaw/secrets/telegram.token
  if [ ! -f ~/.openclaw/secrets/ui.token ]; then
    openssl rand -hex 32 > ~/.openclaw/secrets/ui.token
    chmod 600 ~/.openclaw/secrets/ui.token
  fi
"

echo "7/8 🐘 Запуск Qdrant (векторная память)..."
scp -i "$SSH_KEY" config/docker-compose.qdrant.yml "$CLAWD_VPS:~/.openclaw/"
ssh -i "$SSH_KEY" "$CLAWD_VPS" "
  cd ~/.openclaw
  docker compose -f docker-compose.qdrant.yml up -d
"

echo "8/8 🚀 Обновление .env и финальный деплой бота..."
# Обновляем IP в .env
if grep -q "^VPS_IP=" .env; then
  sed -i -e "s/^VPS_IP=.*/VPS_IP=${NEW_VPS_IP}/" .env || true
else
  echo "VPS_IP=${NEW_VPS_IP}" >> .env
fi

# Деплоим воркспейс и системд сервис
./scripts/deploy.sh

echo "========================================================================="
echo "🎉 УРА! Бот успешно развернут на новом VPS ($NEW_VPS_IP)."
echo "========================================================================="
echo "Проверить статус: ./scripts/status.sh"
