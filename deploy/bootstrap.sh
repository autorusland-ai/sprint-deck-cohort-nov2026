#!/usr/bin/env bash
# bootstrap.sh — установка системных пакетов и сервисов на чистом Ubuntu 24.04 VPS.
# Запускать через sudo. После — bash configure.sh под юзером clawd.
#
# Идемпотентен: можно перезапускать, не сломает то что уже установлено.

set -euo pipefail

# ---------- preflight ----------
[ "$(id -u)" -eq 0 ] || { echo "Запусти через sudo"; exit 1; }
. /etc/os-release
[ "${VERSION_ID:-}" = "24.04" ] || echo "WARNING: тестировался на Ubuntu 24.04, у тебя $VERSION_ID — продолжаю, но возможны несовместимости"

CLAWD_HOME=/home/clawd
DEPLOY_DIR=$(cd "$(dirname "$0")" && pwd)

log() { echo -e "\n\033[1;36m==>\033[0m $*"; }

# ---------- user clawd ----------
log "Создаю пользователя clawd (если нет)"
if ! id clawd &>/dev/null; then
    useradd -m -s /bin/bash clawd
    log "  → создан clawd. Не забудь установить ему SSH-ключ и/или пароль."
fi
usermod -aG sudo,docker,users clawd 2>/dev/null || true

# ---------- apt packages ----------
log "apt update + установка системных пакетов"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq \
    tor privoxy \
    docker.io docker-compose-plugin \
    ffmpeg \
    python3.12-venv python3-pip \
    git curl jq \
    inotify-tools xvfb \
    build-essential ca-certificates

# ---------- Node.js 24 LTS (nodesource) ----------
if ! command -v node &>/dev/null || [ "$(node --version | cut -c2- | cut -d. -f1)" -lt 22 ]; then
    log "Устанавливаю Node.js 24 LTS через nodesource"
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
    apt-get install -y -qq nodejs
fi

# ---------- privoxy → tor ----------
log "Настраиваю Privoxy → Tor (SOCKS5 forward)"
if ! grep -q "forward-socks5t / 127.0.0.1:9050 \." /etc/privoxy/config; then
    echo "" >> /etc/privoxy/config
    echo "forward-socks5t / 127.0.0.1:9050 ." >> /etc/privoxy/config
fi
systemctl enable --now tor privoxy

# ---------- docker ----------
log "Включаю docker сервис"
systemctl enable --now docker

# ---------- linger для clawd (чтобы user@.service работал без логина) ----------
log "Enable linger для clawd"
loginctl enable-linger clawd

# ---------- Ollama (для Mem0 эмбеддингов) ----------
if ! command -v ollama &>/dev/null; then
    log "Устанавливаю Ollama"
    curl -fsSL https://ollama.com/install.sh | sh
    systemctl enable --now ollama
fi

# ---------- Qdrant (через docker, проще чем apt) ----------
log "Поднимаю Qdrant (vector store для Mem0)"
if ! docker ps --format '{{.Names}}' | grep -q '^qdrant$'; then
    docker pull -q qdrant/qdrant:v1.12.4
    docker run -d --name qdrant \
        --restart unless-stopped \
        -p 127.0.0.1:6333:6333 \
        -v qdrant-data:/qdrant/storage \
        qdrant/qdrant:v1.12.4 >/dev/null
fi

# ---------- npm global для clawd ----------
log "Настраиваю npm global prefix для clawd"
sudo -u clawd bash -c "
    mkdir -p $CLAWD_HOME/.npm-global
    npm config set prefix $CLAWD_HOME/.npm-global
    grep -qxF 'export PATH=\$HOME/.npm-global/bin:\$PATH' $CLAWD_HOME/.bashrc || \
        echo 'export PATH=\$HOME/.npm-global/bin:\$PATH' >> $CLAWD_HOME/.bashrc
"

# ---------- openclaw + mem0 ----------
log "Устанавливаю openclaw + mem0 (от имени clawd)"
sudo -u clawd bash -c "
    export PATH=$CLAWD_HOME/.npm-global/bin:\$PATH
    npm install -g --silent openclaw@2026.5.19 @mem0/openclaw-mem0@1.0.11
"

# ---------- Python venv для MCP-серверов ----------
log "Python venv для google-workspace-mcp + browser-use"
sudo -u clawd bash -c "
    [ -d $CLAWD_HOME/browser-env ] || python3.12 -m venv $CLAWD_HOME/browser-env
    $CLAWD_HOME/browser-env/bin/pip install -q --upgrade pip
    $CLAWD_HOME/browser-env/bin/pip install -q google-workspace-mcp==2.0.1 browser-use caldav icalendar
"

# ---------- директории openclaw ----------
log "Создаю каталоги openclaw"
sudo -u clawd bash -c "
    mkdir -p $CLAWD_HOME/.openclaw/{scripts,secrets,workspace/skills,media/inbound,media/outbound,sandboxes,cron,state,agents/main/agent,sandbox-image}
    chmod 700 $CLAWD_HOME/.openclaw/secrets
    mkdir -p $CLAWD_HOME/emmbase/inbox
"

# ---------- копируем артефакты из deploy/ ----------
log "Копирую скрипты, workspace и systemd-юниты"
sudo -u clawd bash -c "
    cp -r $DEPLOY_DIR/scripts/* $CLAWD_HOME/.openclaw/scripts/
    chmod +x $CLAWD_HOME/.openclaw/scripts/*.sh $CLAWD_HOME/.openclaw/scripts/*.py 2>/dev/null || true
    cp -r $DEPLOY_DIR/workspace/* $CLAWD_HOME/.openclaw/workspace/
    mkdir -p $CLAWD_HOME/.config/systemd/user/openclaw-gateway.service.d/
    cp $DEPLOY_DIR/systemd/openclaw-gateway.service $CLAWD_HOME/.config/systemd/user/
    cp $DEPLOY_DIR/systemd/openclaw-gateway.service.d/proxy.conf $CLAWD_HOME/.config/systemd/user/openclaw-gateway.service.d/
    cp $DEPLOY_DIR/systemd/xvfb.service $CLAWD_HOME/.config/systemd/user/
"

# ---------- sandbox docker image ----------
log "Собираю sandbox Docker image"
sudo -u clawd bash -c "
    cat > $CLAWD_HOME/.openclaw/sandbox-image/Dockerfile <<'EOF'
FROM python:3.12-slim-bookworm
RUN apt-get update -qq && apt-get install -y -qq curl jq ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /workspace
CMD [\"sleep\", \"infinity\"]
EOF
    docker build -q -t comandos-openclaw-sandbox:bookworm-slim $CLAWD_HOME/.openclaw/sandbox-image/
"

# ---------- pull ollama embedding model ----------
log "Тяну nomic-embed-text (768-dim) для Mem0"
sudo -u clawd bash -c "ollama pull nomic-embed-text >/dev/null"

# ---------- systemd user services ----------
log "Регистрирую systemd user units (gateway пока НЕ стартую — нет config)"
sudo -u clawd XDG_RUNTIME_DIR=/run/user/$(id -u clawd) bash -c "
    systemctl --user daemon-reload
    systemctl --user enable xvfb.service
    systemctl --user start xvfb.service
"

# ---------- финал ----------
log "Bootstrap завершён"
cat <<EOF

Следующий шаг — настроить ключи и OAuth:

    sudo -u clawd bash $DEPLOY_DIR/configure.sh

Что уже стоит и крутится:
  ✓ Tor + Privoxy (127.0.0.1:9050 / 127.0.0.1:8118)
  ✓ Docker + sandbox image: comandos-openclaw-sandbox:bookworm-slim
  ✓ Ollama + nomic-embed-text (127.0.0.1:11434)
  ✓ Qdrant (127.0.0.1:6333)
  ✓ Node.js $(node --version), npm-global для clawd
  ✓ openclaw $(/home/clawd/.npm-global/bin/openclaw --version 2>/dev/null | head -1)
  ✓ Python venv с google-workspace-mcp + browser-use
  ✓ Helper-скрипты в ~clawd/.openclaw/scripts/
  ✓ Workspace правила в ~clawd/.openclaw/workspace/
  ✓ systemd units установлены (gateway НЕ запущен)
EOF
