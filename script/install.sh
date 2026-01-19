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
    
    # Get the directory where the install script is located
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Copy SSL manager script if it exists
    if [ -f "$SCRIPT_DIR/ssl-manager.sh" ]; then
        cp "$SCRIPT_DIR/ssl-manager.sh" /usr/local/bin/synctv-ssl
        chmod +x /usr/local/bin/synctv-ssl
        echo "SSL manager script installed"
    elif [ -f "./script/ssl-manager.sh" ]; then
        cp "./script/ssl-manager.sh" /usr/local/bin/synctv-ssl
        chmod +x /usr/local/bin/synctv-ssl
        echo "SSL manager script installed"
    else
        echo "Warning: SSL manager script not found, will be created inline"
        # Create a basic SSL manager script inline
        cat <<'SSL_EOF' > /usr/local/bin/synctv-ssl
#!/bin/bash
echo "SSL Certificate Management"
echo "For full SSL management, please download ssl-manager.sh from the repository"
echo ""
echo "Quick SSL setup:"
echo "1. Install acme.sh: curl https://get.acme.sh | sh"
echo "2. Issue certificate: ~/.acme.sh/acme.sh --issue --server letsencrypt --cert-profile shortlived --days 3 -d YOUR_IP --webroot /opt/synctv/public"
echo "3. Install certificate: ~/.acme.sh/acme.sh --install-cert -d YOUR_IP --key-file /opt/synctv/cert/key.pem --fullchain-file /opt/synctv/cert/cert.pem"
SSL_EOF
        chmod +x /usr/local/bin/synctv-ssl
    fi
    
    # Copy uninstall script if it exists
    if [ -f "$SCRIPT_DIR/uninstall.sh" ]; then
        cp "$SCRIPT_DIR/uninstall.sh" /usr/local/bin/synctv-uninstall
        chmod +x /usr/local/bin/synctv-uninstall
        echo "Uninstall script installed"
    elif [ -f "./script/uninstall.sh" ]; then
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
    
    print_warn "This will uninstall SyncTV"
    read -p "Are you sure? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        print_info "Uninstallation cancelled"
        return 0
    fi
    
    # Check if uninstall script exists
    if [ -f "/usr/local/bin/synctv-uninstall" ]; then
        /usr/local/bin/synctv-uninstall
    else
        print_error "Uninstall script not found"
        print_info "Manual uninstallation steps:"
        echo "  1. systemctl stop synctv"
        echo "  2. systemctl disable synctv"
        echo "  3. rm /etc/systemd/system/synctv.service"
        echo "  4. rm /usr/bin/synctv"
        echo "  5. rm -rf /opt/synctv"
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
    
    # Ask to start service
    read -p "Do you want to start SyncTV now? (y/n): " start_choice
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
    echo "Note: SyncTV is currently running on HTTP only."
    echo "To enable HTTPS, you need to configure SSL certificates."
    echo ""
    
    # Ask about SSL configuration
    read -p "Do you want to configure SSL certificate now? (y/n): " ssl_choice
    if [ "$ssl_choice" = "y" ] || [ "$ssl_choice" = "Y" ]; then
        echo ""
        if [ -f "/usr/local/bin/synctv-ssl" ]; then
            /usr/local/bin/synctv-ssl
        else
            echo "Error: SSL management script not found at /usr/local/bin/synctv-ssl"
            echo "Please check the installation or download ssl-manager.sh manually"
        fi
    else
        echo ""
        echo "You can configure SSL later with: sudo synctv ssl"
        echo ""
        echo "Quick SSL setup steps:"
        echo "1. Run: sudo synctv ssl"
        echo "2. Select 'Issue IP Certificate'"
        echo "3. Enter your public IP address"
        echo "4. Wait for certificate issuance"
        echo "5. Restart SyncTV to apply changes"
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
    echo "  HTTPS: https://YOUR_IP:8443 (after SSL configuration)"
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
