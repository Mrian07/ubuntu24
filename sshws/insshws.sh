#!/bin/bash
#
# SSH WebSocket Proxy Installation Script
# Compatible with Ubuntu 24.04 LTS
# ==========================================

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

# Display banner
echo -e "${BLUE}"
echo "========================================"
echo "  SSH WebSocket Proxy - Ubuntu 24.04"
echo "========================================"
echo -e "${NC}"

# Configuration
REPO_URL="https://raw.githubusercontent.com/Mrian07/ubuntu24/main"

# Detect Python version for Ubuntu 24.04
detect_python() {
    if command -v python3 &> /dev/null; then
        PYTHON_BIN=$(command -v python3)
        PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)
        log_info "Detected Python: $PYTHON_BIN (version $PYTHON_VERSION)"
    elif command -v python &> /dev/null; then
        PYTHON_BIN=$(command -v python)
        PYTHON_VERSION=$(python --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)
        log_info "Detected Python: $PYTHON_BIN (version $PYTHON_VERSION)"
    else
        log_error "Python is not installed. Installing Python3..."
        apt-get update -qq
        apt-get install -y python3 python3-pip >/dev/null 2>&1
        PYTHON_BIN=$(command -v python3)
        PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)
        log_success "Python3 installed successfully"
    fi
}

# Install required packages
install_dependencies() {
    log_info "Installing required dependencies..."
    apt-get update -qq
    apt-get install -y wget curl python3 python3-pip >/dev/null 2>&1
    log_success "Dependencies installed"
}

# Download and install WebSocket proxy script
install_ws_proxy() {
    local service_name=$1
    local script_name=$2
    local service_file=$3
    local description=$4
    local exec_args=${5:-}
    
    log_info "Installing $description..."
    
    # Download script
    if wget -q -O "/usr/local/bin/$script_name" "${REPO_URL}/sshws/$script_name"; then
        chmod +x "/usr/local/bin/$script_name"
        log_success "Downloaded $script_name"
    else
        log_error "Failed to download $script_name"
        return 1
    fi
    
    # Create systemd service
    log_info "Creating systemd service: $service_file"
    cat > "/etc/systemd/system/$service_file" <<EOF
[Unit]
Description=$description
Documentation=https://github.com/Mrian07/aingman-script
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=$PYTHON_BIN -O /usr/local/bin/$script_name $exec_args
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service
    systemctl daemon-reload
    
    if systemctl enable "$service_name" >/dev/null 2>&1; then
        log_success "Enabled $service_name"
    else
        log_warn "Failed to enable $service_name"
    fi
    
    if systemctl restart "$service_name" >/dev/null 2>&1; then
        log_success "Started $service_name"
    else
        log_error "Failed to start $service_name"
        systemctl status "$service_name" --no-pager -l
        return 1
    fi
    
    # Wait for service to start
    sleep 2
    
    # Check service status
    if systemctl is-active --quiet "$service_name"; then
        log_success "✓ $service_name is running"
        return 0
    else
        log_error "✗ $service_name failed to start"
        log_info "Checking service logs..."
        journalctl -u "$service_name" -n 20 --no-pager
        return 1
    fi
}

# Main installation
main() {
    log_info "Starting SSH WebSocket Proxy installation..."
    
    # Install dependencies
    install_dependencies
    
    # Detect Python
    detect_python
    
    # Install ws-dropbear (Non-TLS WebSocket for Dropbear)
    log_info ""
    log_info "=== Installing Dropbear WebSocket Proxy ==="
    if install_ws_proxy "ws-dropbear.service" "ws-dropbear" "ws-dropbear.service" "Dropbear WebSocket Proxy (Non-TLS)"; then
        WS_DROPBEAR_STATUS="✓ Running"
    else
        WS_DROPBEAR_STATUS="✗ Failed"
    fi
    
    # Install ws-stunnel (WebSocket for Stunnel)
    log_info ""
    log_info "=== Installing Stunnel WebSocket Proxy ==="
    if install_ws_proxy "ws-stunnel.service" "ws-stunnel" "ws-stunnel.service" "Stunnel WebSocket Proxy"; then
        WS_STUNNEL_STATUS="✓ Running"
    else
        WS_STUNNEL_STATUS="✗ Failed"
    fi
    
    # Optional: Install ws-ovpn (commented out by default)
    # Uncomment below to enable OpenVPN WebSocket
    # log_info ""
    # log_info "=== Installing OpenVPN WebSocket Proxy ==="
    # if install_ws_proxy "ws-ovpn.service" "ws-ovpn.py" "ws-ovpn.service" "OpenVPN WebSocket Proxy" "2086"; then
    #     WS_OVPN_STATUS="✓ Running"
    # else
    #     WS_OVPN_STATUS="✗ Failed"
    # fi
    
    # Display summary
    echo ""
    echo -e "${GREEN}========================================"
    echo "  Installation Complete!"
    echo -e "========================================${NC}"
    echo ""
    echo -e "${BLUE}Service Status:${NC}"
    echo -e "  • Dropbear WebSocket: $WS_DROPBEAR_STATUS"
    echo -e "  • Stunnel WebSocket:  $WS_STUNNEL_STATUS"
    # echo -e "  • OpenVPN WebSocket:  $WS_OVPN_STATUS"
    echo ""
    echo -e "${YELLOW}Python Version:${NC} $PYTHON_VERSION"
    echo -e "${YELLOW}Python Binary:${NC} $PYTHON_BIN"
    echo ""
    
    # Show service management commands
    echo -e "${BLUE}Service Management Commands:${NC}"
    echo "  • Check status:  systemctl status ws-dropbear"
    echo "  • View logs:     journalctl -u ws-dropbear -f"
    echo "  • Restart:       systemctl restart ws-dropbear"
    echo "  • Stop:          systemctl stop ws-dropbear"
    echo ""
    
    log_success "SSH WebSocket Proxy installation completed!"
}

# Run main function
main

exit 0
