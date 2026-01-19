#!/bin/bash

download_tools_list=(
    "curl"
    "wget"
)

function Help() {
    echo "Usage: sudo -v ; curl -fsSL https://raw.githubusercontent.com/synctv-org/synctv/main/script/install.sh | sudo bash -s -- -v latest"
    echo "-h: help"
    echo "-v: install version (default: latest)"
    echo "-p: github proxy (default: https://ghfast.top/)"
    echo "-m: micro architecture (no default value)"
    echo "  example: -m v2"
    echo "  example: -m 6"
}

function Init() {
    # Check if the user is root or sudo
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit
    fi
    VERSION="latest"
    GH_PROXY="https://ghfast.top/"
    InitOS
    InitArch
    InitDownloadTools
}

function ParseArgs() {
    while getopts "hv:p:m:" arg; do
        case $arg in
        h)
            Help
            exit 0
            ;;
        v)
            VERSION="$OPTARG"
            ;;
        p)
            GH_PROXY="$OPTARG"
            ;;
        m)
            Microarchitecture="$OPTARG"
            ;;
        ?)
            echo "unkonw argument"
            exit 1
            ;;
        esac
    done
}

function FixArgs() {
    # 如果GH_PROXY结尾不是/，则补上
    if [ "${GH_PROXY: -1}" != "/" ]; then
        GH_PROXY="$GH_PROXY/"
    fi
    # 如果VERSION不是以v开头且不是latest、dev，则补上v
    if [[ "$VERSION" != v* ]] && [ "$VERSION" != "latest" ] && [ "$VERSION" != "dev" ]; then
        VERSION="v$VERSION"
    fi

}

function InitOS() {
    case "$(uname)" in
    Linux)
        OS='linux'
        ;;
    # Darwin)
    #     OS='darwin'
    #     ;;
    *)
        echo "OS: ${OS} not supported"
        exit 2
        ;;
    esac
}

# Ref: https://dl.xanmod.org/check_x86-64_psabi.sh
# https://go.dev/wiki/MinimumRequirements#amd64
AMD64_MICRO_DETECTION_SCRIPT=$(
    cat <<EOF
BEGIN {
    while (!/flags/) if (getline < "/proc/cpuinfo" != 1) exit 1
    if (/lm/&&/cmov/&&/cx8/&&/fpu/&&/fxsr/&&/mmx/&&/syscall/&&/sse2/) level = 1
    if (level == 1 && /cx16/&&/lahf/&&/popcnt/&&/sse4_1/&&/sse4_2/&&/ssse3/) level = 2
    if (level == 2 && /avx/&&/avx2/&&/bmi1/&&/bmi2/&&/f16c/&&/fma/&&/abm/&&/movbe/&&/xsave/) level = 3
    if (level == 3 && /avx512f/&&/avx512bw/&&/avx512cd/&&/avx512dq/&&/avx512vl/) level = 4
    if (level > 0) { print "v" level; exit 0 }
    exit 1
}
EOF
)

function InitArch() {
    case "$(uname -m)" in
    x86_64 | amd64)
        ARCH='amd64'
        if [ ! "$Microarchitecture" ]; then
            Microarchitecture="$(awk "$AMD64_MICRO_DETECTION_SCRIPT")"
        fi
        ;;
    i?86 | x86)
        ARCH='386'
        ;;
    arm64 | aarch64)
        ARCH='arm64'
        ;;
    arm*)
        ARCH='arm'
        ;;
    *)
        echo "arch: ${ARCH} not supported"
        exit 2
        ;;
    esac
}

function CurrentVersion() {
    if [ -n "$(command -v synctv)" ]; then
        echo "$(synctv version | head -n 1 | awk '{print $2}')"
    else
        echo "uninstalled"
    fi
}

function InitDownloadTools() {
    for tool in "${download_tools_list[@]}"; do
        if [ -n "$(command -v $tool)" ]; then
            download_tool="$tool"
            break
        fi
    done
    if [ -z "$download_tool" ]; then
        echo "no download tools"
        exit 1
    fi
}

function Download() {
    case "$download_tool" in
    curl)
        status_code=$(curl -L "$1" -o "$2" --progress-bar -w "%{http_code}\n")
        if [ $? -ne 0 ]; then
            echo "download $1 failed"
            exit 1
        fi
        if [ "$status_code" != "200" ]; then
            echo "download $1 failed, status code: $status_code"
            exit 1
        fi
        ;;
    wget)
        wget -O "$2" "$1"
        if [ $? -ne 0 ]; then
            echo "download $1 failed"
            exit 1
        fi
        ;;
    *)
        echo "download tool: $download_tool not supported"
        exit 1
        ;;
    esac
}

function DownloadURL() {
    if [ -n "$Microarchitecture" ] && [ "${Microarchitecture:0:1}" != "-" ]; then
        Microarchitecture="-$Microarchitecture"
    fi
    if [[ $1 == v* ]]; then
        echo "${GH_PROXY}https://github.com/synctv-org/synctv/releases/download/$1/synctv-${OS}-${ARCH}${Microarchitecture}"
    else
        echo "${GH_PROXY}https://github.com/synctv-org/synctv/releases/$1/download/synctv-${OS}-${ARCH}${Microarchitecture}"
    fi
}

function InstallWithVersion() {
    tmp_dir=$(mktemp -d 2>/dev/null || mktemp -d -t 'synctv-install.XXXXXXXXXX')
    trap 'rm -rf "$tmp_dir"' EXIT

    URL="$(DownloadURL "$1")"
    echo "download: $URL"

    case "$OS" in
    linux)
        Download "$URL" "$tmp_dir/synctv"

        cp "$tmp_dir/synctv" /usr/bin/synctv.new
        if [ $? -ne 0 ]; then
            echo "copy synctv to /usr/bin/synctv.new failed"
            exit 1
        fi

        chmod 755 /usr/bin/synctv.new
        chown root:root /usr/bin/synctv.new
        mv /usr/bin/synctv{.new,}
        if [ $? -ne 0 ]; then
            echo "move /usr/bin/synctv{.new,} failed"
            exit 1
        fi
        echo "synctv installed to /usr/bin/synctv"
        ;;
    darwin)
        Download "$URL" "$tmp_dir/synctv"

        mkdir -m 0555 -p /usr/local/bin
        if [ $? -ne 0 ]; then
            echo "mkdir /usr/local/bin failed"
            exit 1
        fi

        cp "$tmp_dir/synctv" /usr/local/bin/synctv.new
        if [ $? -ne 0 ]; then
            echo "copy synctv to /usr/local/bin/synctv.new failed"
            exit 1
        fi

        chmod a=x /usr/local/bin/synctv.new
        mv /usr/local/bin/synctv{.new,}
        if [ $? -ne 0 ]; then
            echo "move /usr/local/bin/synctv{.new,} failed"
            exit 1
        fi
        echo "synctv installed to /usr/local/bin/synctv"
        ;;
    *)
        echo 'OS not supported'
        exit 2
        ;;
    esac
}

function InitLinuxSystemctlService() {
    if [ -z "$(command -v systemctl)" ]; then
        echo "systemctl command not found"
        exit 1
    fi
    mkdir -p "/opt/synctv"
    if [ ! -d "/etc/systemd/system" ]; then
        echo "/etc/systemd/system not found"
        exit 1
    fi

    if [ -f "/etc/systemd/system/synctv.service" ]; then
        return
    fi

    if [ -f "./script/synctv.service" ]; then
        echo "use ./script/synctv.service"
        cp "./script/synctv.service" "/etc/systemd/system/synctv.service"
        if [ $? -ne 0 ]; then
            echo "copy ./script/synctv.service to /etc/systemd/system/synctv.service failed"
            exit 1
        fi
    else
        echo "use default synctv.service"
        cat <<EOF >"/etc/systemd/system/synctv.service"
[Unit]
Description=SyncTV Service
After=network.target

[Service]
ExecStart=/usr/bin/synctv server --data-dir /opt/synctv
WorkingDirectory=/opt/synctv
Restart=unless-stopped

[Install]
WantedBy=multi-user.target
EOF
        if [ $? -ne 0 ]; then
            echo "write /etc/systemd/system/synctv.service failed"
            exit 1
        fi
    fi

    systemctl daemon-reload
    echo "/etc/systemd/system/synctv.service install success"
}

function InstallManagementScript() {
    echo "Installing management scripts..."
    
    # Create SSL manager script (embedded, based on 3x-ui implementation)
    cat <<'SSL_SCRIPT_EOF' > /usr/local/bin/synctv-ssl
#!/bin/bash
# SyncTV SSL Certificate Manager
# Debug: Script started
CERT_DIR="/opt/synctv/cert"
ACME_HOME="$HOME/.acme.sh"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
check_acme_installed() { [ -f "$ACME_HOME/acme.sh" ]; }

is_port_in_use() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null | awk -v p=":${port}$" '$4 ~ p {exit 0} END {exit 1}' && return 0
    elif command -v netstat >/dev/null 2>&1; then
        netstat -lnt 2>/dev/null | awk -v p=":${port} " '$4 ~ p {exit 0} END {exit 1}' && return 0
    fi
    return 1
}

install_acme() {
    print_info "Installing acme.sh..."
    read -p "Enter your email address for certificate notifications: " email < /dev/tty
    [ -z "$email" ] && email="admin@example.com"
    curl -fsSL https://get.acme.sh | sh -s email="$email"
    [ $? -ne 0 ] && { print_error "Failed to install acme.sh"; return 1; }
    [ -f "$ACME_HOME/acme.sh.env" ] && . "$ACME_HOME/acme.sh.env"
    print_info "acme.sh installed successfully"
}

is_valid_ipv4() {
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    IFS='.' read -ra ADDR <<< "$1"
    for i in "${ADDR[@]}"; do [ "$i" -gt 255 ] && return 1; done
    return 0
}

get_public_ip() {
    local urls=("https://api4.ipify.org" "https://ipv4.icanhazip.com" "https://v4.api.ipinfo.io/ip")
    for url in "${urls[@]}"; do
        local ip=$(curl -s --max-time 3 "$url" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "$ip" ]]; then
            echo "$ip"
            return 0
        fi
    done
    return 1
}

issue_certificate() {
    print_info "=== Issue Let's Encrypt IP Certificate ==="
    echo ""
    print_warn "IP certificates are valid for ~6 days and will auto-renew"
    print_warn "Port 80 must be open and accessible from the internet"
    echo ""
    
    check_acme_installed || {
        print_warn "acme.sh is not installed"
        read -p "Install acme.sh now? (y/n): " choice < /dev/tty
        [[ "$choice" =~ ^[Yy]$ ]] && install_acme || { print_error "acme.sh required"; return 1; }
    }
    
    # Get public IP
    local detected_ip=$(get_public_ip)
    if [[ -n "$detected_ip" ]]; then
        print_info "Detected public IP: $detected_ip"
    fi
    echo ""
    
    read -p "Enter your public IPv4 address: " ipv4 < /dev/tty
    [ -z "$ipv4" ] && { print_error "IP address cannot be empty"; return 1; }
    is_valid_ipv4 "$ipv4" || { print_error "Invalid IPv4: $ipv4"; return 1; }
    
    # Choose port for HTTP-01 listener
    local WebPort=80
    read -p "Port to use for ACME HTTP-01 listener (default 80): " WebPort < /dev/tty
    WebPort="${WebPort:-80}"
    if ! [[ "${WebPort}" =~ ^[0-9]+$ ]] || ((WebPort < 1 || WebPort > 65535)); then
        print_warn "Invalid port. Using default 80"
        WebPort=80
    fi
    
    # Check if port is in use
    while is_port_in_use "${WebPort}"; do
        print_warn "Port ${WebPort} is in use"
        read -p "Enter another port (or press Enter to abort): " alt_port < /dev/tty
        if [[ -z "$alt_port" ]]; then
            print_error "Cannot proceed with port ${WebPort} in use"
            return 1
        fi
        WebPort="$alt_port"
    done
    
    print_info "Using port ${WebPort} for standalone validation"
    
    # Stop SyncTV temporarily to free port 80
    if [[ "${WebPort}" -eq 80 ]]; then
        print_info "Stopping SyncTV temporarily..."
        systemctl stop synctv 2>/dev/null || true
    fi
    
    # Create certificate directory
    mkdir -p "$CERT_DIR"
    
    # Source acme.sh environment
    [ -f "$ACME_HOME/acme.sh.env" ] && . "$ACME_HOME/acme.sh.env"
    
    # Issue certificate with standalone mode
    print_info "Issuing certificate for ${ipv4}..."
    "$ACME_HOME/acme.sh" --set-default-ca --server letsencrypt >/dev/null 2>&1
    "$ACME_HOME/acme.sh" --issue \
        -d "${ipv4}" \
        --standalone \
        --server letsencrypt \
        --keylength ec-256 \
        --days 6 \
        --httpport ${WebPort} \
        --force
    
    local issue_result=$?
    
    # Restart SyncTV if we stopped it
    if [[ "${WebPort}" -eq 80 ]]; then
        print_info "Restarting SyncTV..."
        systemctl start synctv 2>/dev/null || true
    fi
    
    if [ $issue_result -ne 0 ]; then
        print_error "Failed to issue certificate"
        echo ""
        print_warn "Troubleshooting:"
        echo "  1. Ensure port ${WebPort} is accessible from the internet"
        echo "  2. Check firewall settings"
        echo "  3. Verify IP address is correct: ${ipv4}"
        rm -rf ~/.acme.sh/${ipv4} 2>/dev/null
        return 1
    fi
    
    print_info "Certificate issued successfully, installing..."
    
    # Install certificate
    local reloadCmd="systemctl restart synctv 2>/dev/null || true"
    "$ACME_HOME/acme.sh" --installcert -d "${ipv4}" \
        --key-file "${CERT_DIR}/key.pem" \
        --fullchain-file "${CERT_DIR}/cert.pem" \
        --reloadcmd "${reloadCmd}" 2>&1 || true
    
    # Verify certificate files exist
    if [[ ! -f "${CERT_DIR}/cert.pem" || ! -f "${CERT_DIR}/key.pem" ]]; then
        print_error "Certificate files not found after installation"
        rm -rf ~/.acme.sh/${ipv4} 2>/dev/null
        return 1
    fi
    
    # Set permissions
    chmod 600 "${CERT_DIR}/key.pem" 2>/dev/null
    chmod 644 "${CERT_DIR}/cert.pem" 2>/dev/null
    
    # Enable auto-upgrade
    "$ACME_HOME/acme.sh" --upgrade --auto-upgrade >/dev/null 2>&1
    
    print_info "Certificate installed successfully!"
    echo ""
    echo "Certificate files:"
    echo "  Cert: ${CERT_DIR}/cert.pem"
    echo "  Key:  ${CERT_DIR}/key.pem"
    echo ""
    print_info "Certificate valid for ~6 days, auto-renews via acme.sh cron"
    echo ""
    
    # Show certificate details
    openssl x509 -in "${CERT_DIR}/cert.pem" -noout -dates 2>/dev/null || true
    
    echo ""
    echo "=========================================="
    print_info "Certificate issued successfully!"
    echo "=========================================="
    echo ""
    print_warn "NEXT STEP: Configure SyncTV to use HTTPS"
    echo ""
    echo "SyncTV needs to be configured to use the certificate."
    echo "You have two options:"
    echo ""
    echo "Option 1: Automatic Configuration (Recommended)"
    echo "  - Automatically update SyncTV settings"
    echo "  - Enable HTTPS on port 443"
    echo "  - Restart service"
    echo ""
    echo "Option 2: Manual Configuration"
    echo "  - You configure SyncTV yourself"
    echo "  - More control over settings"
    echo ""
    
    read -p "Choose option (1=Auto, 2=Manual, Enter=Auto): " config_choice < /dev/tty
    config_choice=${config_choice:-1}
    
    if [[ "$config_choice" == "1" ]]; then
        print_info "Configuring SyncTV for HTTPS..."
        
        # Check if SyncTV binary supports cert command
        if /usr/bin/synctv --help 2>&1 | grep -q "cert"; then
            # Use SyncTV's built-in cert command if available
            /usr/bin/synctv cert --cert-file "${CERT_DIR}/cert.pem" --key-file "${CERT_DIR}/key.pem" 2>/dev/null || true
        fi
        
        # Create or update config file
        local config_file="/opt/synctv/config.yaml"
        if [ ! -f "$config_file" ]; then
            print_info "Creating HTTPS configuration..."
            cat > "$config_file" <<EOF
server:
  http:
    listen: ":8080"
  https:
    enabled: true
    listen: ":443"
    cert_file: "${CERT_DIR}/cert.pem"
    key_file: "${CERT_DIR}/key.pem"
EOF
            print_info "Configuration file created at $config_file"
        else
            print_warn "Config file exists. Please manually add HTTPS configuration:"
            echo ""
            echo "Add these lines to $config_file:"
            echo ""
            echo "server:"
            echo "  https:"
            echo "    enabled: true"
            echo "    listen: \":443\""
            echo "    cert_file: \"${CERT_DIR}/cert.pem\""
            echo "    key_file: \"${CERT_DIR}/key.pem\""
            echo ""
        fi
        
        # Restart SyncTV
        print_info "Restarting SyncTV..."
        systemctl restart synctv
        sleep 2
        
        if systemctl is-active --quiet synctv; then
            print_info "✓ SyncTV restarted successfully"
            echo ""
            echo "=========================================="
            print_info "HTTPS is now enabled!"
            echo "=========================================="
            echo ""
            echo "Access your SyncTV instance:"
            echo "  HTTP:  http://${ipv4}:8080"
            echo "  HTTPS: https://${ipv4}:443"
            echo ""
            print_warn "Note: You may need to open port 443 in your firewall"
        else
            print_error "Failed to restart SyncTV"
            echo "Check logs with: sudo journalctl -u synctv -n 50"
        fi
    else
        print_info "Manual configuration selected"
        echo ""
        echo "To enable HTTPS, add this to your SyncTV config:"
        echo ""
        echo "File: /opt/synctv/config.yaml"
        echo ""
        echo "server:"
        echo "  http:"
        echo "    listen: \":8080\""
        echo "  https:"
        echo "    enabled: true"
        echo "    listen: \":443\""
        echo "    cert_file: \"${CERT_DIR}/cert.pem\""
        echo "    key_file: \"${CERT_DIR}/key.pem\""
        echo ""
        echo "Then restart: sudo systemctl restart synctv"
    fi
}

show_menu() {
    clear
    echo "=========================================="
    echo "  SyncTV SSL Certificate Manager"
    echo "=========================================="
    echo "1. Issue IP Certificate"
    echo "2. Show Certificate Info"
    echo "3. Check Auto-Renewal Status"
    echo "4. Renew Certificate (Force)"
    echo "0. Exit"
    echo "=========================================="
}

# Main execution
# Check root privileges
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root or with sudo"
    exit 1
fi

# Check if called with --auto flag for automatic certificate issuance
if [[ "$1" == "--auto" ]]; then
    echo "=========================================="
    echo "  Automatic SSL Certificate Setup"
    echo "=========================================="
    echo ""
    issue_certificate
    exit_code=$?
    exit $exit_code
fi

# Interactive menu mode
while true; do
    show_menu
    read -p "Select option [0-4]: " choice < /dev/tty
    echo ""
    case $choice in
        1) issue_certificate ;;
        2) 
            if check_acme_installed; then
                [ -f "$ACME_HOME/acme.sh.env" ] && . "$ACME_HOME/acme.sh.env"
                "$ACME_HOME/acme.sh" --list
            else
                print_error "acme.sh not installed"
            fi
            ;;
        3)
            if check_acme_installed; then
                if crontab -l 2>/dev/null | grep -q "acme.sh"; then
                    print_info "Auto-renewal is configured"
                    crontab -l 2>/dev/null | grep "acme.sh"
                else
                    print_warn "Cron job not found"
                fi
            else
                print_error "acme.sh not installed"
            fi
            ;;
        4)
            if check_acme_installed; then
                read -p "Enter IP address to renew: " ip < /dev/tty
                [ -f "$ACME_HOME/acme.sh.env" ] && . "$ACME_HOME/acme.sh.env"
                "$ACME_HOME/acme.sh" --renew -d "$ip" --force
            else
                print_error "acme.sh not installed"
            fi
            ;;
        0) print_info "Exiting..."; exit 0 ;;
        *) print_error "Invalid option" ;;
    esac
    echo ""; read -p "Press Enter to continue..." < /dev/tty
done
SSL_SCRIPT_EOF
    chmod +x /usr/local/bin/synctv-ssl
    echo "SSL manager script installed"
    
    # Copy uninstall script if it exists (for local installation)
    if [ -f "./script/uninstall.sh" ]; then
        cp "./script/uninstall.sh" /usr/local/bin/synctv-uninstall
        chmod +x /usr/local/bin/synctv-uninstall
        echo "Uninstall script installed"
    fi
    
    # Create synctv-menu script
    cat <<'MENU_EOF' > /usr/local/bin/synctv-menu
#!/bin/bash

# SyncTV Management Menu

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

function check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This operation requires root privileges"
        return 1
    fi
    return 0
}

function get_service_status() {
    if systemctl is-active --quiet synctv; then
        echo -e "${GREEN}Running${NC}"
    else
        echo -e "${RED}Stopped${NC}"
    fi
}

function start_service() {
    if ! check_root; then
        echo "Please run: sudo synctv start"
        return 1
    fi
    
    print_info "Starting SyncTV service..."
    systemctl start synctv
    
    if [ $? -eq 0 ]; then
        systemctl enable synctv >/dev/null 2>&1
        print_info "SyncTV started successfully"
        sleep 1
        systemctl status synctv --no-pager -l
    else
        print_error "Failed to start SyncTV"
        return 1
    fi
}

function stop_service() {
    if ! check_root; then
        echo "Please run: sudo synctv stop"
        return 1
    fi
    
    print_info "Stopping SyncTV service..."
    systemctl stop synctv
    
    if [ $? -eq 0 ]; then
        print_info "SyncTV stopped successfully"
    else
        print_error "Failed to stop SyncTV"
        return 1
    fi
}

function restart_service() {
    if ! check_root; then
        echo "Please run: sudo synctv restart"
        return 1
    fi
    
    print_info "Restarting SyncTV service..."
    systemctl restart synctv
    
    if [ $? -eq 0 ]; then
        print_info "SyncTV restarted successfully"
        sleep 1
        systemctl status synctv --no-pager -l
    else
        print_error "Failed to restart SyncTV"
        return 1
    fi
}

function show_status() {
    echo ""
    echo "=========================================="
    echo "  SyncTV Service Status"
    echo "=========================================="
    systemctl status synctv --no-pager -l
    echo "=========================================="
}

function show_logs() {
    echo ""
    print_info "Showing SyncTV logs (Press Ctrl+C to exit)"
    echo ""
    sleep 1
    journalctl -u synctv -f --no-pager
}

function show_logs_recent() {
    echo ""
    echo "=========================================="
    echo "  Recent SyncTV Logs (Last 50 lines)"
    echo "=========================================="
    journalctl -u synctv -n 50 --no-pager
    echo "=========================================="
}

function enable_service() {
    if ! check_root; then
        echo "Please run: sudo synctv enable"
        return 1
    fi
    
    print_info "Enabling SyncTV service..."
    systemctl enable synctv
    
    if [ $? -eq 0 ]; then
        print_info "SyncTV will start automatically on boot"
    else
        print_error "Failed to enable SyncTV"
        return 1
    fi
}

function disable_service() {
    if ! check_root; then
        echo "Please run: sudo synctv disable"
        return 1
    fi
    
    print_info "Disabling SyncTV service..."
    systemctl disable synctv
    
    if [ $? -eq 0 ]; then
        print_info "SyncTV will not start automatically on boot"
    else
        print_error "Failed to disable SyncTV"
        return 1
    fi
}

function uninstall_service() {
    if ! check_root; then
        echo "Please run: sudo synctv uninstall"
        return 1
    fi
    
    print_warn "This will uninstall SyncTV and all management scripts"
    read -p "Are you sure? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_info "Uninstallation cancelled"
        return 0
    fi
    
    # Check if uninstall script exists
    if [ -f "/usr/local/bin/synctv-uninstall" ]; then
        echo ""
        print_info "Running uninstall script..."
        /usr/local/bin/synctv-uninstall
        
        # If uninstall was successful, inform user and exit
        if [ $? -eq 0 ]; then
            echo ""
            print_info "Uninstallation complete. Please close this terminal."
            echo ""
            # Exit the script completely
            exit 0
        fi
    else
        print_error "Uninstall script not found"
        print_info "Manual uninstallation steps:"
        echo "  1. systemctl stop synctv"
        echo "  2. systemctl disable synctv"
        echo "  3. rm /etc/systemd/system/synctv.service"
        echo "  4. rm /usr/bin/synctv"
        echo "  5. rm -rf /opt/synctv"
        echo "  6. rm /usr/local/bin/synctv*"
        return 1
    fi
}

function ssl_management() {
    if ! check_root; then
        echo "Please run: sudo synctv ssl"
        return 1
    fi
    
    if [ -f "/usr/local/bin/synctv-ssl" ]; then
        /usr/local/bin/synctv-ssl
    else
        print_error "SSL management script not found"
        return 1
    fi
}

function show_version() {
    if [ -f "/usr/bin/synctv" ]; then
        /usr/bin/synctv version
    else
        print_error "SyncTV binary not found"
    fi
}

function show_menu() {
    clear
    echo "=========================================="
    echo "       SyncTV Management Panel"
    echo "=========================================="
    echo " Status: $(get_service_status)"
    echo "=========================================="
    echo " 1. Start Service"
    echo " 2. Stop Service"
    echo " 3. Restart Service"
    echo " 4. Show Status"
    echo " 5. View Logs (Live)"
    echo " 6. View Recent Logs"
    echo " 7. Enable Auto-Start"
    echo " 8. Disable Auto-Start"
    echo " 9. SSL Certificate Management"
    echo " 10. Show Version"
    echo " 11. Uninstall"
    echo " 0. Exit"
    echo "=========================================="
}

function handle_command() {
    case "$1" in
        start)
            start_service
            ;;
        stop)
            stop_service
            ;;
        restart)
            restart_service
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs
            ;;
        enable)
            enable_service
            ;;
        disable)
            disable_service
            ;;
        uninstall)
            uninstall_service
            ;;
        ssl)
            ssl_management
            ;;
        version)
            show_version
            ;;
        menu|"")
            # Show interactive menu
            while true; do
                show_menu
                read -p "Please select an option [0-11]: " choice
                echo ""
                
                case $choice in
                    1)
                        start_service
                        ;;
                    2)
                        stop_service
                        ;;
                    3)
                        restart_service
                        ;;
                    4)
                        show_status
                        ;;
                    5)
                        show_logs
                        ;;
                    6)
                        show_logs_recent
                        ;;
                    7)
                        enable_service
                        ;;
                    8)
                        disable_service
                        ;;
                    9)
                        ssl_management
                        ;;
                    10)
                        show_version
                        ;;
                    11)
                        uninstall_service
                        if [ $? -eq 0 ]; then
                            exit 0
                        fi
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
            ;;
        help|--help|-h)
            echo "SyncTV Management Commands:"
            echo "  synctv              - Show interactive menu"
            echo "  synctv start        - Start service"
            echo "  synctv stop         - Stop service"
            echo "  synctv restart      - Restart service"
            echo "  synctv status       - Show service status"
            echo "  synctv logs         - View live logs"
            echo "  synctv enable       - Enable auto-start"
            echo "  synctv disable      - Disable auto-start"
            echo "  synctv ssl          - SSL certificate management"
            echo "  synctv version      - Show version"
            echo "  synctv uninstall    - Uninstall SyncTV"
            ;;
        *)
            print_error "Unknown command: $1"
            echo "Run 'synctv help' for usage information"
            exit 1
            ;;
    esac
}

# Main
handle_command "$1"
MENU_EOF

    chmod +x /usr/local/bin/synctv-menu
    
    # Create symlink (remove old one first if exists)
    rm -f /usr/local/bin/synctv
    ln -s /usr/local/bin/synctv-menu /usr/local/bin/synctv
    
    echo "Management scripts installed successfully"
    echo "You can now use 'synctv' command to manage the service"
}

function InitSystemctlService() {
    case "$OS" in
    linux)
        InitLinuxSystemctlService
        InstallManagementScript
        ;;
    esac
}

function Install() {
    current_version="$(CurrentVersion)"
    echo "current version: $current_version"
    echo "install version: $VERSION"
    if [ "$current_version" != "uninstalled" ] && [ "$current_version" = "$VERSION" ] && [ "$current_version" != "dev" ]; then
        echo "current version is $current_version, skip"
        exit 0
    fi

    InstallWithVersion "$VERSION"

    echo "install success"
}

function PostInstall() {
    echo ""
    echo "=========================================="
    echo "  Installation Complete!"
    echo "=========================================="
    echo ""
    
    # Verify management scripts are installed
    if [ ! -f "/usr/local/bin/synctv" ]; then
        echo "Warning: Management script not found at /usr/local/bin/synctv"
        echo "You may need to add /usr/local/bin to your PATH"
    fi
    
    # Ask to start service (read from /dev/tty for pipe installation)
    if [ -t 0 ]; then
        # Interactive terminal
        read -p "Do you want to start SyncTV now? (y/n): " start_choice
    else
        # Non-interactive (pipe), read from tty
        read -p "Do you want to start SyncTV now? (y/n): " start_choice < /dev/tty
    fi
    
    if [ "$start_choice" = "y" ] || [ "$start_choice" = "Y" ]; then
        systemctl enable synctv
        systemctl start synctv
        
        if [ $? -eq 0 ]; then
            echo ""
            echo "✓ SyncTV started successfully"
            sleep 1
            systemctl status synctv --no-pager -l
        else
            echo ""
            echo "✗ Failed to start SyncTV"
            echo "You can start it manually with: sudo systemctl start synctv"
        fi
    else
        echo ""
        echo "You can start SyncTV later with: sudo synctv start"
    fi
    
    echo ""
    echo "=========================================="
    echo "  SSL Certificate Configuration"
    echo "=========================================="
    echo ""
    echo "⚠ IMPORTANT: SyncTV is currently running on HTTP only."
    echo "To enable HTTPS, you need to:"
    echo "  1. Issue an SSL certificate"
    echo "  2. Configure SyncTV to use the certificate"
    echo ""
    
    # Ask about SSL configuration (read from /dev/tty for pipe installation)
    if [ -t 0 ]; then
        read -p "Do you want to configure SSL certificate now? (y/n): " ssl_choice
    else
        read -p "Do you want to configure SSL certificate now? (y/n): " ssl_choice < /dev/tty
    fi
    
    if [ "$ssl_choice" = "y" ] || [ "$ssl_choice" = "Y" ]; then
        echo ""
        echo "=========================================="
        echo "  Starting SSL Configuration"
        echo "=========================================="
        echo ""
        
        if [ -f "/usr/local/bin/synctv-ssl" ]; then
            # Execute SSL script in auto mode
            /usr/local/bin/synctv-ssl --auto
            
            # Check if it executed successfully
            if [ $? -eq 0 ]; then
                echo ""
                echo "✓ SSL configuration completed successfully"
            else
                echo ""
                echo "⚠ SSL configuration encountered an issue"
                echo "You can try again with: sudo synctv ssl"
            fi
        else
            echo "Error: SSL management script not found at /usr/local/bin/synctv-ssl"
            echo "Please run: sudo synctv ssl"
        fi
        
        echo ""
        echo "=========================================="
    else
        echo ""
        echo "You can configure SSL later with: sudo synctv ssl"
        echo ""
        echo "Quick SSL setup steps:"
        echo "1. Run: sudo synctv ssl"
        echo "2. Select 'Issue IP Certificate'"
        echo "3. Enter your public IP address"
        echo "4. Certificate will be saved to /opt/synctv/cert/"
        echo "5. Configure SyncTV to use HTTPS (see below)"
    fi
    
    echo ""
    echo "=========================================="
    echo "  Quick Start Guide"
    echo "=========================================="
    echo ""
    echo "Management Commands:"
    echo "  synctv              - Open management menu"
    echo "  synctv start        - Start service"
    echo "  synctv stop         - Stop service"
    echo "  synctv restart      - Restart service"
    echo "  synctv status       - Show service status"
    echo "  synctv logs         - View live logs"
    echo "  synctv ssl          - SSL certificate management"
    echo "  synctv uninstall    - Uninstall SyncTV"
    echo ""
    echo "Access SyncTV:"
    echo "  HTTP:  http://YOUR_IP:8080"
    echo ""
    echo "After SSL configuration:"
    echo "  HTTPS: https://YOUR_IP:8443"
    echo ""
    echo "⚠ Note: After issuing SSL certificate, you need to configure"
    echo "  SyncTV to use HTTPS. The SSL script will guide you through this."
    echo ""
    echo "For more commands, run: synctv help"
    echo "=========================================="
}

Init
ParseArgs "$@"
FixArgs
Install
InitSystemctlService
PostInstall
