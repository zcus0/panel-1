#!/bin/bash
set -e

# ============================================
# 1Panel OSS Edition - One-line installer
# Usage: bash <(curl -sSL https://raw.githubusercontent.com/YOUR_USER/1panel-oss/main/scripts/install-online.sh)
# ============================================

GITHUB_REPO="zcus0/panel-1"  # Ganti dengan repo kamu
PANEL_EDITION="oss"
EDITION_FILE=".selected_edition"

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
osCheck=$(uname -a)
if [[ $osCheck =~ 'x86_64' ]]; then
    architecture="amd64"
elif [[ $osCheck =~ 'arm64' ]] || [[ $osCheck =~ 'aarch64' ]]; then
    architecture="arm64"
else
    log_error "Unsupported architecture. Use amd64 or arm64."
    exit 1
fi

# Get latest version from GitHub API
log_info "Fetching latest release info..."
LATEST=$(curl -sL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | grep '"tag_name"' | head -1 | cut -d '"' -f 4)

if [[ -z "$LATEST" ]]; then
    log_error "Failed to fetch latest release from GitHub."
    log_error "Check repo: https://github.com/${GITHUB_REPO}/releases"
    exit 1
fi

VERSION="$LATEST"
PACKAGE_FILE_NAME="1panel-${VERSION}-linux-${architecture}.tar.gz"
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/${PACKAGE_FILE_NAME}"

log_info "Latest version: ${VERSION}"
log_info "Architecture: ${architecture}"
log_info "Download URL: ${DOWNLOAD_URL}"

# Download
log_info "Downloading..."
curl -L -o "${PACKAGE_FILE_NAME}" "${DOWNLOAD_URL}"
if [[ ! -f "${PACKAGE_FILE_NAME}" ]]; then
    log_error "Download failed. Check your network."
    exit 1
fi

# Extract
log_info "Extracting..."
tar xzf "${PACKAGE_FILE_NAME}"
if [[ $? -ne 0 ]]; then
    log_error "Extraction failed. File may be corrupted."
    rm -f "${PACKAGE_FILE_NAME}"
    exit 1
fi

# Install
cd "1panel-${VERSION}-linux-${architecture}"
echo "$PANEL_EDITION" > "$EDITION_FILE"

log_info "Running install script..."
/bin/bash install.sh
