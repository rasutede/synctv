#!/bin/bash

# SyncTV Uninstall Script

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

function print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

function print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

function print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

function Help() {
    echo "Usage: sudo bash uninstall.sh [options]"
    echo "-h: help"
    echo "-k: keep data directory (/opt/synctv)"
    echo "-c: keep SSL certificates"
    echo "-a: remove acme.sh"
    echo "-y: auto confirm (skip confirmation prompt)"
}

function Init() {
    # Check if the user is root or sudo
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root"
        exit 1
    fi
    
    KEEP_DATA=false
    KEEP_CERTS=false
    REMOVE_ACME=false
    AUTO_CONFIRM=false
}

function ParseArgs() {
    while getopts "hkcay" arg; do
        case $arg in
        h)
            Help
            exit 0
            ;;
        k)
            KEEP_DATA=true
            ;;
        c)
            KEEP_CERTS=true
            ;;
        a)
            REMOVE_ACME=true
            ;;
        y)
            AUTO_CONFIRM=true
            ;;
        ?)
            echo "unknown argument"
            exit 1
            ;;
        esac
    done
}

function StopService() {
    print_info "Stopping synctv service..."
    
    # Check if service exists and is running
    if systemctl list-units --full -all | grep -q "synctv.service"; then
        if systemctl is-active --quiet synctv; then
            print_info "Service is running, stopping now..."
            systemctl stop synctv
            
            # Wait for service to stop
            local count=0
            while systemctl is-active --quiet synctv && [ $count -lt 10 ]; do
                sleep 1
                ((count++))
            done
            
            if systemctl is-active --quiet synctv; then
                print_warn "Service did not stop gracefully, forcing stop..."
                systemctl kill synctv 2>/dev/null || true
                sleep 2
            fi
            
            print_info "Service stopped"
        else
            print_info "Service is not running"
        fi
    else
        print_info "Service not found"
    fi
}

function DisableService() {
    print_info "Disabling synctv service..."
    if systemctl is-enabled --quiet synctv 2>/dev/null; then
        systemctl disable synctv
        print_info "Service disabled"
    else
        print_info "Service is not enabled"
    fi
}

function RemoveService() {
    print_info "Removing systemd service..."
    if [ -f "/etc/systemd/system/synctv.service" ]; then
        rm -f "/etc/systemd/system/synctv.service"
        systemctl daemon-reload
        systemctl reset-failed 2>/dev/null || true
        print_info "Service file removed"
    else
        print_info "Service file not found"
    fi
}

function RemoveBinary() {
    print_info "Removing synctv binary and management scripts..."
    
    # Remove main binary
    if [ -f "/usr/bin/synctv" ]; then
        rm -f "/usr/bin/synctv"
        print_info "✓ Binary removed from /usr/bin/synctv"
    else
        print_info "○ Binary not found at /usr/bin/synctv"
    fi
    
    # Remove all management scripts
    local removed_count=0
    local scripts=("synctv-menu" "synctv-ssl" "synctv-uninstall" "synctv")
    
    for script in "${scripts[@]}"; do
        if [ -f "/usr/local/bin/$script" ] || [ -L "/usr/local/bin/$script" ]; then
            rm -f "/usr/local/bin/$script"
            ((removed_count++))
        fi
    done
    
    if [ $removed_count -gt 0 ]; then
        print_info "✓ Management scripts removed ($removed_count files)"
    else
        print_info "○ No management scripts found"
    fi
    
    # Clear command hash cache
    hash -r 2>/dev/null || true
    
    # Verify removal
    if command -v synctv >/dev/null 2>&1; then
        print_warn "⚠ 'synctv' command still available in PATH"
        print_warn "  Location: $(which synctv)"
        print_warn "  You may need to restart your shell"
    else
        print_info "✓ All synctv commands removed successfully"
    fi
}

function RemoveData() {
    if [ "$KEEP_DATA" = true ]; then
        print_info "Keeping data directory /opt/synctv"
        
        if [ "$KEEP_CERTS" = false ]; then
            print_info "Removing SSL certificates..."
            if [ -d "/opt/synctv/cert" ]; then
                rm -rf "/opt/synctv/cert"
                print_info "Certificates removed"
            fi
        else
            print_info "Keeping SSL certificates"
        fi
    else
        print_info "Removing data directory..."
        if [ -d "/opt/synctv" ]; then
            if [ "$KEEP_CERTS" = true ]; then
                print_info "Backing up certificates..."
                if [ -d "/opt/synctv/cert" ]; then
                    mkdir -p /tmp/synctv-cert-backup
                    cp -r /opt/synctv/cert/* /tmp/synctv-cert-backup/ 2>/dev/null || true
                    print_info "Certificates backed up to /tmp/synctv-cert-backup"
                fi
            fi
            
            rm -rf "/opt/synctv"
            print_info "Data directory removed"
        else
            print_info "Data directory not found"
        fi
    fi
}

function RemoveAcme() {
    if [ "$REMOVE_ACME" = true ]; then
        print_info "Removing acme.sh..."
        
        # Check if acme.sh is installed
        if [ -d "$HOME/.acme.sh" ]; then
            # Remove all certificates first
            if [ -f "$HOME/.acme.sh/acme.sh" ]; then
                print_info "Removing all certificates..."
                "$HOME/.acme.sh/acme.sh" --uninstall 2>/dev/null || true
            fi
            
            # Remove acme.sh directory
            rm -rf "$HOME/.acme.sh"
            
            # Remove cron job
            crontab -l 2>/dev/null | grep -v "acme.sh" | crontab - 2>/dev/null || true
            
            # Remove acme.sh environment file
            rm -f "$HOME/.acme.sh.env" 2>/dev/null || true
            
            print_info "acme.sh removed"
        else
            print_info "acme.sh not found"
        fi
    else
        print_info "Keeping acme.sh (use -a flag to remove)"
    fi
}

function ShowSummary() {
    echo ""
    echo "=========================================="
    echo "  Uninstallation Summary"
    echo "=========================================="
    echo "✓ SyncTV service stopped"
    echo "✓ SyncTV binary removed"
    echo "✓ Management scripts removed (synctv command)"
    echo "✓ Systemd service removed"
    
    if [ "$KEEP_DATA" = true ]; then
        echo "✓ Data directory kept at /opt/synctv"
    else
        echo "✓ Data directory removed"
    fi
    
    if [ "$KEEP_CERTS" = true ]; then
        if [ "$KEEP_DATA" = true ]; then
            echo "✓ SSL certificates kept at /opt/synctv/cert"
        else
            echo "✓ SSL certificates backed up to /tmp/synctv-cert-backup"
        fi
    else
        echo "✓ SSL certificates removed"
    fi
    
    if [ "$REMOVE_ACME" = true ]; then
        echo "✓ acme.sh removed"
    else
        echo "○ acme.sh kept (certificates can still auto-renew)"
    fi
    
    echo "=========================================="
    echo ""
    print_info "✓ SyncTV has been uninstalled successfully!"
    echo ""
    
    # Check if synctv command still exists
    if command -v synctv >/dev/null 2>&1; then
        print_warn "⚠ IMPORTANT: Please close and reopen your terminal"
        print_warn "  The 'synctv' command may still be cached in your current shell"
        echo ""
        echo "Run this command to clear the cache:"
        echo "  hash -r"
    fi
    
    if [ "$KEEP_DATA" = true ]; then
        echo ""
        print_info "Note: Your data is still at /opt/synctv"
        echo "To completely remove it, run: sudo rm -rf /opt/synctv"
    fi
    
    if [ "$REMOVE_ACME" = false ] && [ -d "$HOME/.acme.sh" ]; then
        echo ""
        print_info "Note: acme.sh is still installed"
        echo "To remove it, run the uninstall script with -a flag"
    fi
    
    echo ""
}

function Confirm() {
    # Skip confirmation if called with -y flag
    if [ "$AUTO_CONFIRM" = true ]; then
        return 0
    fi
    
    echo "=========================================="
    echo "  SyncTV Uninstallation"
    echo "=========================================="
    echo "This will remove:"
    echo "  - SyncTV binary"
    echo "  - Management scripts"
    echo "  - Systemd service"
    
    if [ "$KEEP_DATA" = false ]; then
        echo "  - Data directory (/opt/synctv)"
    fi
    
    if [ "$KEEP_CERTS" = false ]; then
        echo "  - SSL certificates"
    fi
    
    if [ "$REMOVE_ACME" = true ]; then
        echo "  - acme.sh and all certificates"
    fi
    
    echo ""
    echo "This will keep:"
    
    if [ "$KEEP_DATA" = true ]; then
        echo "  - Data directory (/opt/synctv)"
    fi
    
    if [ "$KEEP_CERTS" = true ]; then
        echo "  - SSL certificates"
    fi
    
    if [ "$REMOVE_ACME" = false ]; then
        echo "  - acme.sh"
    fi
    
    echo "=========================================="
    echo ""
    
    # Check if service is running
    if systemctl is-active --quiet synctv 2>/dev/null; then
        print_warn "⚠ SyncTV service is currently running"
        print_warn "  It will be stopped during uninstallation"
        echo ""
    fi
    
    read -p "Are you sure you want to continue? (yes/no): " confirm < /dev/tty
    
    if [ "$confirm" != "yes" ]; then
        print_info "Uninstallation cancelled"
        exit 0
    fi
}

function Uninstall() {
    Confirm
    echo ""
    print_info "Starting uninstallation..."
    echo ""
    
    StopService
    DisableService
    RemoveService
    RemoveBinary
    RemoveData
    RemoveAcme
    
    ShowSummary
}

Init
ParseArgs "$@"
Uninstall
