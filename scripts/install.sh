#!/bin/bash
set -e

PANEL_NAME="1panel"
PANEL_EDITION="oss"
PANEL_CONF_DIR="/opt/1panel"
PANEL_LOG_DIR="/opt/1panel/logs"
PANEL_BASE_DIR="/opt/1panel"
INSTALL_DIR="/usr/local/bin"
PANEL_USER="1panel"
PANEL_GROUP="1panel"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Check architecture
osCheck=$(uname -m)
case "$osCheck" in
    x86_64)  architecture="amd64" ;;
    aarch64) architecture="arm64" ;;
    armv7l)  architecture="armv7" ;;
    *)       log_error "Unsupported architecture: $osCheck"; exit 1 ;;
esac

# Check binaries exist
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ ! -f "${SCRIPT_DIR}/1panel-core" ]] || [[ ! -f "${SCRIPT_DIR}/1panel-agent" ]]; then
    log_error "1panel-core or 1panel-agent not found in ${SCRIPT_DIR}"
    exit 1
fi

log_info "Installing 1Panel OSS Edition (${architecture})..."

# Create group and user
if ! getent group "${PANEL_GROUP}" >/dev/null 2>&1; then
    groupadd -r "${PANEL_GROUP}"
    log_info "Created group: ${PANEL_GROUP}"
fi

if ! getent passwd "${PANEL_USER}" >/dev/null 2>&1; then
    useradd -r -g "${PANEL_GROUP}" -s /sbin/nologin -M "${PANEL_USER}"
    log_info "Created user: ${PANEL_USER}"
fi

# Create directories
mkdir -p "${PANEL_CONF_DIR}/conf"
mkdir -p "${PANEL_LOG_DIR}"
mkdir -p "${PANEL_CONF_DIR}/database"
mkdir -p "${PANEL_CONF_DIR}/cert"
mkdir -p "${PANEL_CONF_DIR}/tmp"
mkdir -p "${PANEL_CONF_DIR}/ssh"
mkdir -p "${PANEL_CONF_DIR}/firewall"

# Install binaries
log_info "Installing binaries to ${INSTALL_DIR}/..."
cp "${SCRIPT_DIR}/1panel-core" "${INSTALL_DIR}/1panel-core"
cp "${SCRIPT_DIR}/1panel-agent" "${INSTALL_DIR}/1panel-agent"
chmod 755 "${INSTALL_DIR}/1panel-core"
chmod 755 "${INSTALL_DIR}/1panel-agent"

# Install frontend assets
if [[ -d "${SCRIPT_DIR}/web" ]]; then
    log_info "Installing frontend assets..."
    cp -r "${SCRIPT_DIR}/web" "${PANEL_CONF_DIR}/web"
fi

# Write edition file
echo "${PANEL_EDITION}" > "${PANEL_CONF_DIR}/.selected_edition"

# Set ownership
chown -R "${PANEL_USER}:${PANEL_GROUP}" "${PANEL_CONF_DIR}"

# Create minimal config if not exists
if [[ ! -f "${PANEL_CONF_DIR}/conf/app.yaml" ]]; then
    cat > "${PANEL_CONF_DIR}/conf/app.yaml" << 'YAML'
server:
  http_port: 9999
  https_port: 9998
  log_level: info
  app_data_dir: /opt/1panel
database:
  type: sqlite
YAML
    chown "${PANEL_USER}:${PANEL_GROUP}" "${PANEL_CONF_DIR}/conf/app.yaml"
fi

# Create systemd service - 1panel-core
cat > /etc/systemd/system/1panel-core.service << 'UNIT'
[Unit]
Description=1Panel Core Service
After=network.target

[Service]
Type=simple
User=1panel
Group=1panel
ExecStart=/usr/local/bin/1panel-core
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
WorkingDirectory=/opt/1panel

[Install]
WantedBy=multi-user.target
UNIT

# Create systemd service - 1panel-agent
cat > /etc/systemd/system/1panel-agent.service << 'UNIT'
[Unit]
Description=1Panel Agent Service
After=network.target 1panel-core.service

[Service]
Type=simple
User=1panel
Group=1panel
ExecStart=/usr/local/bin/1panel-agent
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
WorkingDirectory=/opt/1panel

[Install]
WantedBy=multi-user.target
UNIT

# Reload and enable services
systemctl daemon-reload
systemctl enable 1panel-core 1panel-agent
systemctl start 1panel-core
systemctl start 1panel-agent

# Check status
sleep 2
if systemctl is-active --quiet 1panel-core; then
    log_info "1Panel Core is running"
else
    log_warn "1Panel Core failed to start. Check: journalctl -u 1panel-core"
fi

if systemctl is-active --quiet 1panel-agent; then
    log_info "1Panel Agent is running"
else
    log_warn "1Panel Agent failed to start. Check: journalctl -u 1panel-agent"
fi

echo ""
log_info "============================================"
log_info "  1Panel OSS Edition installed successfully!"
log_info "  Core: http://$(hostname -I | awk '{print $1}'):9999"
log_info "  Logs: ${PANEL_LOG_DIR}/"
log_info "============================================"
echo ""
