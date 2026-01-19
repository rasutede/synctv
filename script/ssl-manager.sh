#!/bin/bash

# SyncTV SSL Certificate Manager
# Supports Let's Encrypt IP certificates with automatic renewal

set -e

CERT_DIR="/opt/synctv/cert"
WEBROOT="/opt/synctv/public"
ACME_HOME="$HOME/.acme.sh"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

function print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

function print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

function check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root or with sudo"
        exit 1
    fi
}

function check_acme_installed() {
    if [ -f "$ACME_HOME/acme.sh" ]; then
        return 0
    fi
    return 1
}

function install_acme() {
    print_info "Installing acme.sh..."
    
    read -p "Enter your email address for certificate notifications: " email
    if [ -z "$email" ]; then
        email="admin@example.com"
    fi
    
    curl -fsSL https://get.acme.sh | sh -s email="$email"
    
    if [ $? -ne 0 ]; then
        print_error "Failed to install acme.sh"
        return 1
    fi
    
    # Source acme.sh environment
    if [ -f "$ACME_HOME/acme.sh.env" ]; then
        . "$ACME_HOME/acme.sh.env"
    fi
    
    print_info "acme.sh installed successfully"
    return 0
}

function is_valid_ipv4() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [ "$i" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

function is_valid_ipv6() {
    local ip=$1
    # Simple IPv6 validation
    if [[ $ip =~ ^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$ ]]; then
        return 0
    fi
    return 1
}

function get_public_ip() {
    local ipv4=$(curl -s -4 https://api.ipify.org 2>/dev/null || curl -s -4 https://ifconfig.me 2>/dev/null)
    local ipv6=$(curl -s -6 https://api64.ipify.org 2>/dev/null || curl -s -6 https://ifconfig.me 2>/dev/null)
    
    echo ""
    print_info "Detected public IP addresses:"
    if [ -n "$ipv4" ]; then
        echo "  IPv4: $ipv4"
    fi
    if [ -n "$ipv6" ]; then
        echo "  IPv6: $ipv6"
    fi
    echo ""
}

function issue_certificate() {
    print_info "=== Issue IP Certificate ==="
    
    if ! check_acme_installed; then
        print_warn "acme.sh is not installed"
        read -p "Do you want to install acme.sh now? (y/n): " install_choice
        if [ "$install_choice" = "y" ] || [ "$install_choice" = "Y" ]; then
            install_acme
            if [ $? -ne 0 ]; then
                return 1
            fi
        else
            print_error "acme.sh is required to issue certificates"
            return 1
        fi
    fi
    
    # Show detected public IPs
    get_public_ip
    
    read -p "Enter your public IP address (IPv4 or IPv6): " ip_address
    
    if [ -z "$ip_address" ]; then
        print_error "IP address cannot be empty"
        return 1
    fi
    
    if ! is_valid_ipv4 "$ip_address" && ! is_valid_ipv6 "$ip_address"; then
        print_error "Invalid IP address format: $ip_address"
        return 1
    fi
    
    read -p "Enter webroot path [$WEBROOT]: " custom_webroot
    custom_webroot=${custom_webroot:-"$WEBROOT"}
    
    print_info "Issuing certificate for IP: $ip_address"
    print_info "Using webroot: $custom_webroot"
    
    # Create webroot directory if it doesn't exist
    mkdir -p "$custom_webroot"
    
    # Source acme.sh environment
    if [ -f "$ACME_HOME/acme.sh.env" ]; then
        . "$ACME_HOME/acme.sh.env"
    fi
    
    # Check if port 80 is available
    if netstat -tuln 2>/dev/null | grep -q ":80 " || ss -tuln 2>/dev/null | grep -q ":80 "; then
        print_warn "Port 80 appears to be in use"
        print_warn "Make sure your web server can serve files from: $custom_webroot/.well-known/acme-challenge/"
    fi
    
    # Issue certificate using HTTP-01 challenge
    # IP certificates only support shortlived profile (7 days validity)
    print_info "Requesting certificate from Let's Encrypt..."
    print_warn "Note: IP certificates are valid for 7 days and will auto-renew every 3 days"
    
    "$ACME_HOME/acme.sh" --issue \
        --server letsencrypt \
        --cert-profile shortlived \
        --days 3 \
        -d "$ip_address" \
        --webroot "$custom_webroot" \
        --force
    
    if [ $? -ne 0 ]; then
        print_error "Failed to issue certificate for $ip_address"
        echo ""
        print_warn "Troubleshooting tips:"
        echo "  1. Ensure port 80 is accessible from the internet"
        echo "  2. Check if the IP address is correct and publicly routable"
        echo "  3. Verify no firewall is blocking port 80"
        echo "  4. Make sure the webroot directory is accessible"
        echo ""
        echo "You can test connectivity with:"
        echo "  curl http://$ip_address/.well-known/acme-challenge/test"
        return 1
    fi
    
    # Install certificate to cert directory
    mkdir -p "$CERT_DIR"
    
    print_info "Installing certificate to $CERT_DIR..."
    
    "$ACME_HOME/acme.sh" --install-cert -d "$ip_address" \
        --key-file "$CERT_DIR/key.pem" \
        --fullchain-file "$CERT_DIR/cert.pem" \
        --reloadcmd "systemctl reload synctv 2>/dev/null || systemctl restart synctv 2>/dev/null || true"
    
    if [ $? -eq 0 ]; then
        print_info "Certificate installed successfully!"
        echo ""
        echo "Certificate files:"
        echo "  Key:  $CERT_DIR/key.pem"
        echo "  Cert: $CERT_DIR/cert.pem"
        echo ""
        print_warn "Important: IP certificates are valid for only 7 days"
        print_info "Auto-renewal is configured to run every 3 days"
        echo ""
        
        # Set proper permissions
        chmod 600 "$CERT_DIR/key.pem"
        chmod 644 "$CERT_DIR/cert.pem"
        
        # Show certificate info
        print_info "Certificate details:"
        openssl x509 -in "$CERT_DIR/cert.pem" -noout -dates -subject 2>/dev/null || true
        
        return 0
    else
        print_error "Failed to install certificate"
        return 1
    fi
}

function renew_certificate() {
    print_info "=== Renew Certificate ==="
    
    if ! check_acme_installed; then
        print_error "acme.sh is not installed"
        return 1
    fi
    
    read -p "Enter IP address: " ip_address
    
    if [ -z "$ip_address" ]; then
        print_error "IP address cannot be empty"
        return 1
    fi
    
    if [ -f "$ACME_HOME/acme.sh.env" ]; then
        . "$ACME_HOME/acme.sh.env"
    fi
    
    print_info "Renewing certificate for $ip_address..."
    
    "$ACME_HOME/acme.sh" --renew -d "$ip_address" --force
    
    if [ $? -eq 0 ]; then
        print_info "Certificate renewed successfully"
        
        # Show new expiry date
        if [ -f "$CERT_DIR/cert.pem" ]; then
            print_info "New certificate expiry:"
            openssl x509 -in "$CERT_DIR/cert.pem" -noout -dates 2>/dev/null || true
        fi
        
        return 0
    else
        print_error "Failed to renew certificate"
        return 1
    fi
}

function show_certificate_info() {
    print_info "=== Certificate Information ==="
    
    if ! check_acme_installed; then
        print_error "acme.sh is not installed"
        return 1
    fi
    
    read -p "Enter IP address (or press Enter to list all): " ip_address
    
    if [ -f "$ACME_HOME/acme.sh.env" ]; then
        . "$ACME_HOME/acme.sh.env"
    fi
    
    if [ -z "$ip_address" ]; then
        print_info "Listing all certificates:"
        "$ACME_HOME/acme.sh" --list
    else
        print_info "Certificate information for $ip_address:"
        "$ACME_HOME/acme.sh" --info -d "$ip_address"
        
        # Also show local certificate file info
        if [ -f "$CERT_DIR/cert.pem" ]; then
            echo ""
            print_info "Local certificate file details:"
            openssl x509 -in "$CERT_DIR/cert.pem" -noout -text 2>/dev/null | grep -A 2 "Validity"
            echo ""
            openssl x509 -in "$CERT_DIR/cert.pem" -noout -subject -issuer 2>/dev/null
        fi
    fi
}

function revoke_certificate() {
    print_info "=== Revoke Certificate ==="
    
    if ! check_acme_installed; then
        print_error "acme.sh is not installed"
        return 1
    fi
    
    read -p "Enter IP address: " ip_address
    
    if [ -z "$ip_address" ]; then
        print_error "IP address cannot be empty"
        return 1
    fi
    
    print_warn "This will revoke and remove the certificate for $ip_address"
    read -p "Are you sure? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_info "Revocation cancelled"
        return 0
    fi
    
    if [ -f "$ACME_HOME/acme.sh.env" ]; then
        . "$ACME_HOME/acme.sh.env"
    fi
    
    print_info "Revoking certificate for $ip_address..."
    
    "$ACME_HOME/acme.sh" --revoke -d "$ip_address"
    
    if [ $? -eq 0 ]; then
        print_info "Certificate revoked successfully"
        
        # Remove certificate from acme.sh
        "$ACME_HOME/acme.sh" --remove -d "$ip_address"
        
        # Optionally remove local certificate files
        read -p "Do you want to remove local certificate files? (y/n): " remove_local
        if [ "$remove_local" = "y" ] || [ "$remove_local" = "Y" ]; then
            rm -f "$CERT_DIR/key.pem" "$CERT_DIR/cert.pem"
            print_info "Local certificate files removed"
        fi
        
        return 0
    else
        print_error "Failed to revoke certificate"
        return 1
    fi
}

function setup_auto_renewal() {
    print_info "=== Setup Auto-Renewal ==="
    
    if ! check_acme_installed; then
        print_error "acme.sh is not installed"
        return 1
    fi
    
    # acme.sh automatically sets up a cron job during installation
    # Verify the cron job exists
    if crontab -l 2>/dev/null | grep -q "acme.sh"; then
        print_info "Auto-renewal is already configured"
        echo ""
        print_info "Current renewal schedule:"
        crontab -l 2>/dev/null | grep "acme.sh"
        echo ""
        print_info "Certificates will be checked and renewed automatically"
        print_warn "IP certificates renew every 3 days (7-day validity)"
        
        # Test the renewal
        read -p "Do you want to test the renewal process now? (y/n): " test_renewal
        if [ "$test_renewal" = "y" ] || [ "$test_renewal" = "Y" ]; then
            print_info "Running renewal test (dry-run)..."
            if [ -f "$ACME_HOME/acme.sh.env" ]; then
                . "$ACME_HOME/acme.sh.env"
            fi
            "$ACME_HOME/acme.sh" --cron --home "$ACME_HOME"
        fi
        
        return 0
    else
        print_warn "acme.sh cron job not found"
        print_info "Attempting to reinstall cron job..."
        
        if [ -f "$ACME_HOME/acme.sh.env" ]; then
            . "$ACME_HOME/acme.sh.env"
        fi
        
        "$ACME_HOME/acme.sh" --install-cronjob
        
        if [ $? -eq 0 ]; then
            print_info "Cron job installed successfully"
            return 0
        else
            print_error "Failed to install cron job"
            return 1
        fi
    fi
}

function check_certificate_status() {
    print_info "=== Certificate Status Check ==="
    
    if [ ! -f "$CERT_DIR/cert.pem" ]; then
        print_warn "No certificate found at $CERT_DIR/cert.pem"
        return 1
    fi
    
    print_info "Checking certificate at $CERT_DIR/cert.pem"
    echo ""
    
    # Get certificate details
    local subject=$(openssl x509 -in "$CERT_DIR/cert.pem" -noout -subject 2>/dev/null | sed 's/subject=//')
    local issuer=$(openssl x509 -in "$CERT_DIR/cert.pem" -noout -issuer 2>/dev/null | sed 's/issuer=//')
    local not_before=$(openssl x509 -in "$CERT_DIR/cert.pem" -noout -startdate 2>/dev/null | sed 's/notBefore=//')
    local not_after=$(openssl x509 -in "$CERT_DIR/cert.pem" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
    
    echo "Subject: $subject"
    echo "Issuer:  $issuer"
    echo "Valid From: $not_before"
    echo "Valid Until: $not_after"
    echo ""
    
    # Check if certificate is expired or expiring soon
    local expiry_epoch=$(date -d "$not_after" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$not_after" +%s 2>/dev/null)
    local current_epoch=$(date +%s)
    local days_left=$(( ($expiry_epoch - $current_epoch) / 86400 ))
    
    if [ $days_left -lt 0 ]; then
        print_error "Certificate has EXPIRED!"
    elif [ $days_left -lt 2 ]; then
        print_warn "Certificate expires in $days_left day(s) - renewal should happen soon"
    else
        print_info "Certificate is valid for $days_left more day(s)"
    fi
}

function show_menu() {
    clear
    echo "=========================================="
    echo "  SyncTV SSL Certificate Manager"
    echo "=========================================="
    echo "1. Issue IP Certificate"
    echo "2. Renew Certificate"
    echo "3. Show Certificate Info"
    echo "4. Check Certificate Status"
    echo "5. Revoke Certificate"
    echo "6. Setup/Check Auto-Renewal"
    echo "7. Install acme.sh"
    echo "0. Exit"
    echo "=========================================="
    echo ""
}

function main() {
    check_root
    
    while true; do
        show_menu
        read -p "Please select an option [0-7]: " choice
        echo ""
        
        case $choice in
            1)
                issue_certificate
                ;;
            2)
                renew_certificate
                ;;
            3)
                show_certificate_info
                ;;
            4)
                check_certificate_status
                ;;
            5)
                revoke_certificate
                ;;
            6)
                setup_auto_renewal
                ;;
            7)
                install_acme
                ;;
            0)
                print_info "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Run main function
main
