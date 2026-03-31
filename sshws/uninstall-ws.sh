#!/bin/bash
#
# SSH WebSocket Proxy Uninstallation Script
# Compatible with Ubuntu 24.04 LTS
# ==========================================

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR]${NC} This script must be run as root"
   exit 1
fi

echo -e "${BLUE}"
echo "========================================"
echo "  WebSocket Proxy Uninstallation"
echo "========================================"
echo -e "${NC}"
echo ""

# Confirmation
echo -e "${YELLOW}This will remove all WebSocket Proxy services and files.${NC}"
echo -n "Are you sure you want to continue? (yes/no): "
read -r confirm

if [[ "$confirm" != "yes" ]]; then
    echo -e "${GREEN}Uninstallation cancelled.${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}Starting uninstallation...${NC}"
echo ""

# Stop services
echo -e "${YELLOW}[1/5]${NC} Stopping services..."
for service in ws-dropbear ws-stunnel ws-ovpn; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        systemctl stop "$service" && echo -e "  ${GREEN}✓${NC} Stopped $service"
    fi
done

# Disable services
echo -e "${YELLOW}[2/5]${NC} Disabling services..."
for service in ws-dropbear ws-stunnel ws-ovpn; do
    if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        systemctl disable "$service" && echo -e "  ${GREEN}✓${NC} Disabled $service"
    fi
done

# Remove service files
echo -e "${YELLOW}[3/5]${NC} Removing service files..."
for service in ws-dropbear.service ws-stunnel.service ws-ovpn.service ws-nontls.service; do
    if [[ -f "/etc/systemd/system/$service" ]]; then
        rm -f "/etc/systemd/system/$service" && echo -e "  ${GREEN}✓${NC} Removed $service"
    fi
done

# Remove scripts
echo -e "${YELLOW}[4/5]${NC} Removing proxy scripts..."
for script in ws-dropbear ws-stunnel ws-ovpn ws-ovpn.py; do
    if [[ -f "/usr/local/bin/$script" ]]; then
        rm -f "/usr/local/bin/$script" && echo -e "  ${GREEN}✓${NC} Removed $script"
    fi
done

# Reload systemd
echo -e "${YELLOW}[5/5]${NC} Reloading systemd..."
systemctl daemon-reload && echo -e "  ${GREEN}✓${NC} Systemd reloaded"

echo ""
echo -e "${GREEN}========================================"
echo "  Uninstallation Complete!"
echo -e "========================================${NC}"
echo ""
echo -e "${BLUE}All WebSocket Proxy services have been removed.${NC}"
echo ""

exit 0
