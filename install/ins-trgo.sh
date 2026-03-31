#!/bin/bash
#
# Trojan-Go Installation Script
# Compatible with Ubuntu 24.04 LTS
# ==========================================

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

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
echo -e "${CYAN}"
echo "========================================"
echo "  Trojan-Go Installation - Ubuntu 24.04"
echo "========================================"
echo -e "${NC}"

cd /root

# Get domain
if [[ -e /etc/xray/domain ]]; then
    domain=$(cat /etc/xray/domain)
    log_info "Using domain: $domain"
elif [[ -e /root/domain ]]; then
    domain=$(cat /root/domain)
    log_info "Using domain: $domain"
else
    log_error "Domain file not found. Please run Xray installation first."
    exit 1
fi

# Check if SSL certificates exist
if [[ ! -f /etc/xray/xray.crt ]] || [[ ! -f /etc/xray/xray.key ]]; then
    log_error "SSL certificates not found. Please run Xray installation first."
    exit 1
fi

# Install required packages
log_info "Installing required packages..."
apt-get update -qq
apt-get install -y curl unzip iptables netfilter-persistent >/dev/null 2>&1

# Get latest Trojan-Go version
log_info "Fetching latest Trojan-Go version..."
latest_version=$(curl -s "https://api.github.com/repos/p4gefau1t/trojan-go/releases" | grep tag_name | sed -E 's/.*"v(.*)".*/\1/' | head -n 1)

if [[ -z "$latest_version" ]]; then
    log_error "Failed to fetch latest version"
    exit 1
fi

log_info "Latest version: v${latest_version}"

# Download Trojan-Go
trojango_link="https://github.com/p4gefau1t/trojan-go/releases/download/v${latest_version}/trojan-go-linux-amd64.zip"

log_info "Downloading Trojan-Go..."
mkdir -p "/usr/bin/trojan-go"
mkdir -p "/etc/trojan-go"
mkdir -p "/var/log/trojan-go"

# Download to temp directory
temp_dir=$(mktemp -d)
cd "$temp_dir"

if curl -sL "${trojango_link}" -o trojan-go.zip; then
    log_success "Downloaded Trojan-Go"
else
    log_error "Failed to download Trojan-Go"
    rm -rf "$temp_dir"
    exit 1
fi

# Extract and install
log_info "Installing Trojan-Go..."
if unzip -q trojan-go.zip; then
    mv trojan-go /usr/local/bin/trojan-go
    chmod +x /usr/local/bin/trojan-go
    log_success "Trojan-Go installed to /usr/local/bin/trojan-go"
else
    log_error "Failed to extract Trojan-Go"
    rm -rf "$temp_dir"
    exit 1
fi

# Cleanup temp directory
cd /root
rm -rf "$temp_dir"

# Create log files
touch /etc/trojan-go/trgo
touch /var/log/trojan-go/trojan-go.log
chmod 644 /var/log/trojan-go/trojan-go.log

# Generate UUID
uuid=$(cat /proc/sys/kernel/random/uuid)
log_info "Generated UUID: $uuid"

# Create Trojan-Go configuration
log_info "Creating Trojan-Go configuration..."
cat > /etc/trojan-go/config.json <<EOF
{
  "run_type": "server",
  "local_addr": "0.0.0.0",
  "local_port": 2087,
  "remote_addr": "127.0.0.1",
  "remote_port": 89,
  "log_level": 1,
  "log_file": "/var/log/trojan-go/trojan-go.log",
  "password": ["$uuid"],
  "disable_http_check": true,
  "udp_timeout": 60,
  "ssl": {
    "verify": false,
    "verify_hostname": false,
    "cert": "/etc/xray/xray.crt",
    "key": "/etc/xray/xray.key",
    "key_password": "",
    "cipher": "",
    "curves": "",
    "prefer_server_cipher": false,
    "sni": "$domain",
    "alpn": ["http/1.1"],
    "session_ticket": true,
    "reuse_session": true,
    "plain_http_response": "",
    "fallback_addr": "127.0.0.1",
    "fallback_port": 0,
    "fingerprint": "firefox"
  },
  "tcp": {
    "no_delay": true,
    "keep_alive": true,
    "prefer_ipv4": true
  },
  "mux": {
    "enabled": false,
    "concurrency": 8,
    "idle_timeout": 60
  },
  "websocket": {
    "enabled": true,
    "path": "/trojango",
    "host": "$domain"
  },
  "api": {
    "enabled": false,
    "api_addr": "",
    "api_port": 0,
    "ssl": {
      "enabled": false,
      "key": "",
      "cert": "",
      "verify_client": false,
      "client_cert": []
    }
  }
}
EOF

log_success "Configuration created"

# Create systemd service
log_info "Creating systemd service..."
cat > /etc/systemd/system/trojan-go.service <<'EOF'
[Unit]
Description=Trojan-Go Service
Documentation=https://p4gefau1t.github.io/trojan-go/
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/trojan-go -config /etc/trojan-go/config.json
Restart=on-failure
RestartPreventExitStatus=23
RestartSec=5s
StandardOutput=journal
StandardError=journal
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

log_success "Systemd service created"

# Save UUID
echo "$uuid" > /etc/trojan-go/uuid.txt
chmod 600 /etc/trojan-go/uuid.txt

# Configure iptables
log_info "Configuring iptables..."
if command -v iptables-save &> /dev/null; then
    iptables-save > /etc/iptables.up.rules 2>/dev/null || true
fi

if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save >/dev/null 2>&1 || true
    netfilter-persistent reload >/dev/null 2>&1 || true
fi

# Reload systemd and start service
log_info "Starting Trojan-Go service..."
systemctl daemon-reload

if systemctl enable trojan-go >/dev/null 2>&1; then
    log_success "Service enabled"
else
    log_warn "Failed to enable service"
fi

# Stop if running
systemctl stop trojan-go >/dev/null 2>&1 || true

# Start service
if systemctl start trojan-go >/dev/null 2>&1; then
    log_success "Service started"
else
    log_error "Failed to start service"
    log_info "Checking service status..."
    systemctl status trojan-go --no-pager -l
    exit 1
fi

# Wait for service to start
sleep 2

# Check service status
if systemctl is-active --quiet trojan-go; then
    log_success "✓ Trojan-Go is running"
else
    log_error "✗ Trojan-Go failed to start"
    log_info "Service logs:"
    journalctl -u trojan-go -n 20 --no-pager
    exit 1
fi

# Display summary
echo ""
echo -e "${GREEN}========================================"
echo "  Installation Complete!"
echo -e "========================================${NC}"
echo ""
echo -e "${BLUE}Configuration:${NC}"
echo -e "  Domain: ${CYAN}$domain${NC}"
echo -e "  UUID: ${CYAN}$uuid${NC}"
echo -e "  Port: ${CYAN}2087${NC}"
echo -e "  WebSocket Path: ${CYAN}/trojango${NC}"
echo -e "  Version: ${CYAN}v${latest_version}${NC}"
echo ""
echo -e "${BLUE}Files:${NC}"
echo "  • Binary: /usr/local/bin/trojan-go"
echo "  • Config: /etc/trojan-go/config.json"
echo "  • UUID: /etc/trojan-go/uuid.txt"
echo "  • Log: /var/log/trojan-go/trojan-go.log"
echo ""
echo -e "${BLUE}Service Management:${NC}"
echo "  • Status: systemctl status trojan-go"
echo "  • Restart: systemctl restart trojan-go"
echo "  • Logs: journalctl -u trojan-go -f"
echo "  • Stop: systemctl stop trojan-go"
echo ""
echo -e "${YELLOW}Note:${NC} Make sure Nginx is configured to proxy /trojango path"
echo ""

log_success "Trojan-Go installation completed successfully!"

exit 0
