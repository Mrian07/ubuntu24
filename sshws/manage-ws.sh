#!/bin/bash
#
# SSH WebSocket Proxy Management Script
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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR]${NC} This script must be run as root"
   exit 1
fi

# Function to show service status
show_status() {
    echo -e "${CYAN}=== WebSocket Proxy Services Status ===${NC}"
    echo ""
    
    for service in ws-dropbear ws-stunnel; do
        if systemctl is-active --quiet "$service"; then
            status="${GREEN}✓ Running${NC}"
        else
            status="${RED}✗ Stopped${NC}"
        fi
        
        echo -e "${BLUE}$service:${NC} $status"
        
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            enabled="${GREEN}enabled${NC}"
        else
            enabled="${YELLOW}disabled${NC}"
        fi
        echo -e "  Status: $enabled"
        
        # Get port info if available
        if systemctl is-active --quiet "$service"; then
            pid=$(systemctl show -p MainPID --value "$service")
            if [[ "$pid" != "0" ]]; then
                ports=$(ss -tulpn | grep "$pid" | awk '{print $5}' | cut -d: -f2 | sort -u | tr '\n' ',' | sed 's/,$//')
                if [[ -n "$ports" ]]; then
                    echo -e "  Ports: $ports"
                fi
            fi
        fi
        echo ""
    done
}

# Function to start services
start_services() {
    echo -e "${GREEN}Starting WebSocket Proxy services...${NC}"
    for service in ws-dropbear ws-stunnel; do
        if systemctl start "$service" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Started $service"
        else
            echo -e "  ${RED}✗${NC} Failed to start $service"
        fi
    done
}

# Function to stop services
stop_services() {
    echo -e "${YELLOW}Stopping WebSocket Proxy services...${NC}"
    for service in ws-dropbear ws-stunnel; do
        if systemctl stop "$service" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Stopped $service"
        else
            echo -e "  ${RED}✗${NC} Failed to stop $service"
        fi
    done
}

# Function to restart services
restart_services() {
    echo -e "${BLUE}Restarting WebSocket Proxy services...${NC}"
    for service in ws-dropbear ws-stunnel; do
        if systemctl restart "$service" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Restarted $service"
        else
            echo -e "  ${RED}✗${NC} Failed to restart $service"
        fi
    done
}

# Function to show logs
show_logs() {
    local service=${1:-ws-dropbear}
    echo -e "${CYAN}=== Logs for $service ===${NC}"
    echo -e "${YELLOW}Press Ctrl+C to exit${NC}"
    echo ""
    journalctl -u "$service" -f
}

# Function to show recent logs
show_recent_logs() {
    local service=${1:-ws-dropbear}
    local lines=${2:-50}
    echo -e "${CYAN}=== Recent logs for $service (last $lines lines) ===${NC}"
    journalctl -u "$service" -n "$lines" --no-pager
}

# Function to enable services
enable_services() {
    echo -e "${GREEN}Enabling WebSocket Proxy services...${NC}"
    for service in ws-dropbear ws-stunnel; do
        if systemctl enable "$service" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Enabled $service"
        else
            echo -e "  ${RED}✗${NC} Failed to enable $service"
        fi
    done
}

# Function to disable services
disable_services() {
    echo -e "${YELLOW}Disabling WebSocket Proxy services...${NC}"
    for service in ws-dropbear ws-stunnel; do
        if systemctl disable "$service" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Disabled $service"
        else
            echo -e "  ${RED}✗${NC} Failed to disable $service"
        fi
    done
}

# Show menu
show_menu() {
    clear
    echo -e "${CYAN}"
    echo "========================================"
    echo "  WebSocket Proxy Management"
    echo "========================================"
    echo -e "${NC}"
    echo ""
    echo "1. Show Status"
    echo "2. Start All Services"
    echo "3. Stop All Services"
    echo "4. Restart All Services"
    echo "5. Enable Auto-start"
    echo "6. Disable Auto-start"
    echo "7. View Live Logs (ws-dropbear)"
    echo "8. View Live Logs (ws-stunnel)"
    echo "9. View Recent Logs (ws-dropbear)"
    echo "10. View Recent Logs (ws-stunnel)"
    echo "0. Exit"
    echo ""
    echo -n "Select option: "
}

# Main loop
main() {
    while true; do
        show_menu
        read -r choice
        echo ""
        
        case $choice in
            1)
                show_status
                ;;
            2)
                start_services
                ;;
            3)
                stop_services
                ;;
            4)
                restart_services
                ;;
            5)
                enable_services
                ;;
            6)
                disable_services
                ;;
            7)
                show_logs "ws-dropbear"
                ;;
            8)
                show_logs "ws-stunnel"
                ;;
            9)
                show_recent_logs "ws-dropbear" 50
                ;;
            10)
                show_recent_logs "ws-stunnel" 50
                ;;
            0)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                ;;
        esac
        
        echo ""
        echo -e "${YELLOW}Press Enter to continue...${NC}"
        read -r
    done
}

# Run main if no arguments
if [[ $# -eq 0 ]]; then
    main
else
    # Command line mode
    case $1 in
        status)
            show_status
            ;;
        start)
            start_services
            ;;
        stop)
            stop_services
            ;;
        restart)
            restart_services
            ;;
        enable)
            enable_services
            ;;
        disable)
            disable_services
            ;;
        logs)
            show_logs "${2:-ws-dropbear}"
            ;;
        recent)
            show_recent_logs "${2:-ws-dropbear}" "${3:-50}"
            ;;
        *)
            echo "Usage: $0 {status|start|stop|restart|enable|disable|logs|recent} [service] [lines]"
            exit 1
            ;;
    esac
fi

exit 0
