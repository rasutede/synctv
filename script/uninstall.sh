#!/bin/bash

# SyncTV Uninstall Script

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
        echo "Please run as root"
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
    echo "Stopping synctv service..."
    if systemctl is-active --quiet synctv; then
        systemctl stop synctv
        echo "Service stopped"
    else
        echo "Service is not running"
    fi
}

function DisableService() {
    echo "Disabling synctv service..."
    if systemctl is-enabled --quiet synctv 2>/dev/null; then
        systemctl disable synctv
        echo "Service disabled"
    else
        echo "Service is not enabled"
    fi
}

function RemoveService() {
    echo "Removing systemd service..."
    if [ -f "/etc/systemd/system/synctv.service" ]; then
        rm -f "/etc/systemd/system/synctv.service"
        systemctl daemon-reload
        echo "Service file removed"
    else
        echo "Service file not found"
    fi
}

function RemoveBinary() {
    echo "Removing synctv binary and management scripts..."
    
    # Remove main binary
    if [ -f "/usr/bin/synctv" ]; then
        rm -f "/usr/bin/synctv"
        echo "✓ Binary removed from /usr/bin/synctv"
    else
        echo "○ Binary not found at /usr/bin/synctv"
    fi
    
    # Remove all management scripts
    local removed_count=0
    
    if [ -f "/usr/local/bin/synctv-menu" ]; then
        rm -f /usr/local/bin/synctv-menu
        ((removed_count++))
    fi
    
    if [ -f "/usr/local/bin/synctv-ssl" ]; then
        rm -f /usr/local/bin/synctv-ssl
        ((removed_count++))
    fi
    
    if [ -f "/usr/local/bin/synctv-uninstall" ]; then
        rm -f /usr/local/bin/synctv-uninstall
        ((removed_count++))
    fi
    
    if [ -L "/usr/local/bin/synctv" ] || [ -f "/usr/local/bin/synctv" ]; then
        rm -f /usr/local/bin/synctv
        ((removed_count++))
    fi
    
    if [ $removed_count -gt 0 ]; then
        echo "✓ Management scripts removed ($removed_count files)"
    else
        echo "○ No management scripts found"
    fi
    
    # Verify removal
    if command -v synctv >/dev/null 2>&1; then
        echo "⚠ Warning: 'synctv' command still available in PATH"
        echo "  Location: $(which synctv)"
        echo "  You may need to manually remove it or restart your shell"
    else
        echo "✓ All synctv commands removed successfully"
    fi
}

function RemoveData() {
    if [ "$KEEP_DATA" = true ]; then
        echo "Keeping data directory /opt/synctv"
        
        if [ "$KEEP_CERTS" = false ]; then
            echo "Removing SSL certificates..."
            if [ -d "/opt/synctv/cert" ]; then
                rm -rf "/opt/synctv/cert"
                echo "Certificates removed"
            fi
        else
            echo "Keeping SSL certificates"
        fi
    else
        echo "Removing data directory..."
        if [ -d "/opt/synctv" ]; then
            if [ "$KEEP_CERTS" = true ]; then
                echo "Backing up certificates..."
                if [ -d "/opt/synctv/cert" ]; then
                    mkdir -p /tmp/synctv-cert-backup
                    cp -r /opt/synctv/cert/* /tmp/synctv-cert-backup/
                    echo "Certificates backed up to /tmp/synctv-cert-backup"
                fi
            fi
            
            rm -rf "/opt/synctv"
            echo "Data directory removed"
        else
            echo "Data directory not found"
        fi
    fi
}

function RemoveAcme() {
    if [ "$REMOVE_ACME" = true ]; then
        echo "Removing acme.sh..."
        
        # Check if acme.sh is installed
        if [ -d "$HOME/.acme.sh" ]; then
            # Remove all certificates first
            if [ -f "$HOME/.acme.sh/acme.sh" ]; then
                echo "Removing all certificates..."
                "$HOME/.acme.sh/acme.sh" --uninstall
            fi
            
            # Remove acme.sh directory
            rm -rf "$HOME/.acme.sh"
            
            # Remove cron job
            crontab -l 2>/dev/null | grep -v "acme.sh" | crontab - 2>/dev/null || true
            
            echo "acme.sh removed"
        else
            echo "acme.sh not found"
        fi
    else
        echo "Keeping acme.sh (use -a flag to remove)"
    fi
}

function ShowSummary() {
    echo ""
    echo "=========================================="
    echo "  Uninstallation Summary"
    echo "=========================================="
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
    echo "✓ SyncTV has been uninstalled successfully!"
    echo ""
    
    # Check if synctv command still exists
    if command -v synctv >/dev/null 2>&1; then
        echo "⚠ IMPORTANT: Please close and reopen your terminal"
        echo "  The 'synctv' command may still be cached in your current shell"
    fi
    
    if [ "$KEEP_DATA" = true ]; then
        echo ""
        echo "Note: Your data is still at /opt/synctv"
        echo "To completely remove it, run: sudo rm -rf /opt/synctv"
    fi
    
    if [ "$REMOVE_ACME" = false ] && [ -d "$HOME/.acme.sh" ]; then
        echo ""
        echo "Note: acme.sh is still installed"
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
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "Uninstallation cancelled"
        exit 0
    fi
}

function Uninstall() {
    Confirm
    echo ""
    echo "Starting uninstallation..."
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
