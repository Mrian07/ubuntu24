#!/bin/bash
#
# SSH WebSocket Proxy Testing Script
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

echo -e "${CYAN}"
echo "========================================"
echo "  WebSocket Proxy Connection Test"
echo "========================================"
echo -e "${NC}"
echo ""

# Test service status
test_service_status() {
    local service=$1
    echo -n "Testing $service... "
    
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}✓ Running${NC}"
        return 0
    else
        echo -e "${RED}✗ Not Running${NC}"
        return 1
    fi
}

# Test port listening
test_port() {
    local port=$1
    local service=$2
    
    echo -n "Testing port $port ($service)... "
    
    if ss -tulpn | grep -q ":$port "; then
        echo -e "${GREEN}✓ Listening${NC}"
        return 0
    else
        echo -e "${RED}✗ Not Listening${NC}"
        return 1
    fi
}

# Get listening ports for a service
get_service_ports() {
    local service=$1
    local pid=$(systemctl show -p MainPID --value "$service" 2>/dev/null)
    
    if [[ -n "$pid" && "$pid" != "0" ]]; then
        ss -tulpn | grep "$pid" | awk '{print $5}' | cut -d: -f2 | sort -u
    fi
}

# Test WebSocket connection
test_websocket() {
    local host=${1:-localhost}
    local port=$2
    local path=${3:-/}
    
    echo -n "Testing WebSocket connection to $host:$port$path... "
    
    # Simple HTTP upgrade test
    response=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Upgrade: websocket" \
        -H "Connection: Upgrade" \
        -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
        -H "Sec-WebSocket-Version: 13" \
        --max-time 5 \
        "http://$host:$port$path" 2>/dev/null || echo "000")
    
    if [[ "$response" == "101" || "$response" == "200" ]]; then
        echo -e "${GREEN}✓ Connected (HTTP $response)${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed (HTTP $response)${NC}"
        return 1
    fi
}

# Main tests
echo -e "${BLUE}=== Service Status Tests ===${NC}"
test_service_status "ws-dropbear.service" || true
test_service_status "ws-stunnel.service" || true
echo ""

echo -e "${BLUE}=== Port Listening Tests ===${NC}"

# Get ports for ws-dropbear
dropbear_ports=$(get_service_ports "ws-dropbear.service")
if [[ -n "$dropbear_ports" ]]; then
    echo "ws-dropbear ports: $dropbear_ports"
    for port in $dropbear_ports; do
        test_port "$port" "ws-dropbear" || true
    done
else
    echo -e "${YELLOW}No ports found for ws-dropbear${NC}"
fi

echo ""

# Get ports for ws-stunnel
stunnel_ports=$(get_service_ports "ws-stunnel.service")
if [[ -n "$stunnel_ports" ]]; then
    echo "ws-stunnel ports: $stunnel_ports"
    for port in $stunnel_ports; do
        test_port "$port" "ws-stunnel" || true
    done
else
    echo -e "${YELLOW}No ports found for ws-stunnel${NC}"
fi

echo ""

# Python check
echo -e "${BLUE}=== Python Environment ===${NC}"
if command -v python3 &> /dev/null; then
    python_version=$(python3 --version 2>&1)
    echo -e "Python: ${GREEN}✓${NC} $python_version"
else
    echo -e "Python: ${RED}✗ Not found${NC}"
fi

echo ""

# System info
echo -e "${BLUE}=== System Information ===${NC}"
echo "OS: $(lsb_release -d | cut -f2)"
echo "Kernel: $(uname -r)"
echo "Uptime: $(uptime -p)"

echo ""

# Service logs check
echo -e "${BLUE}=== Recent Service Logs ===${NC}"
echo ""
echo -e "${CYAN}ws-dropbear (last 5 lines):${NC}"
journalctl -u ws-dropbear -n 5 --no-pager 2>/dev/null || echo "No logs available"

echo ""
echo -e "${CYAN}ws-stunnel (last 5 lines):${NC}"
journalctl -u ws-stunnel -n 5 --no-pager 2>/dev/null || echo "No logs available"

echo ""
echo -e "${GREEN}========================================"
echo "  Test Complete!"
echo -e "========================================${NC}"
echo ""

# Summary
echo -e "${YELLOW}Tip:${NC} Use 'manage-ws.sh' for service management"
echo -e "${YELLOW}Tip:${NC} Use 'journalctl -u ws-dropbear -f' to view live logs"
echo ""

exit 0
