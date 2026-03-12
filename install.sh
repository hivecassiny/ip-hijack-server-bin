#!/bin/bash
#
# IP Hijack Server — Interactive Installer
# https://github.com/hivecassiny/ip-hijack-server-bin
#
set -e

REPO="hivecassiny/ip-hijack-server-bin"
BASE_URL="https://raw.githubusercontent.com/${REPO}/main/bin"
INSTALL_DIR="/usr/local/bin"
SERVICE_DIR="/etc/systemd/system"
SERVER_BIN="ip-hijack-server"
DATA_DIR="/var/lib/ip-hijack"

# ─── Colors ───────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

VERSION="1.0.0"
BUILD="2026-03-12.7"

print_banner() {
    echo ""
    echo -e "${CYAN}${BOLD}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║       IP Hijack Server Installer         ║"
    echo "  ║               v${VERSION}                    ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo -e "  ${DIM}build ${BUILD}${RESET}"
}

info()    { echo -e "  ${GREEN}[✓]${RESET} $1"; }
warn()    { echo -e "  ${YELLOW}[!]${RESET} $1"; }
error()   { echo -e "  ${RED}[✗]${RESET} $1"; }
step()    { echo -e "\n  ${CYAN}${BOLD}▸ $1${RESET}"; }
prompt()  { echo -en "  ${BOLD}$1${RESET}"; }

# ─── Detect Architecture ─────────────────────────────────────────
detect_arch() {
    local os arch
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)

    case "$arch" in
        x86_64|amd64)   arch="amd64" ;;
        aarch64|arm64)   arch="arm64" ;;
        armv7l|armhf)    arch="arm"   ;;
        *)               error "Unsupported architecture: $arch (Server supports amd64/arm64/arm only)"; exit 1 ;;
    esac

    case "$os" in
        linux)  ;;
        darwin) ;;
        *)      error "Unsupported OS: $os"; exit 1 ;;
    esac

    DETECTED_OS="$os"
    DETECTED_ARCH="$arch"
    PLATFORM="${os}-${arch}"
}

# ─── Check Root ───────────────────────────────────────────────────
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# ─── Download Binary ─────────────────────────────────────────────
download_bin() {
    local name="$1" url="$2" dest="$3"
    step "Downloading ${name}..."
    if command -v wget &>/dev/null; then
        wget -q --show-progress -O "$dest" "$url" || { error "Download failed"; exit 1; }
    elif command -v curl &>/dev/null; then
        curl -fL --progress-bar -o "$dest" "$url" || { error "Download failed"; exit 1; }
    else
        error "Neither curl nor wget found. Please install one."
        exit 1
    fi
    chmod +x "$dest"
    info "Installed to ${dest}"
}

# ─── Install Server ──────────────────────────────────────────────
install_server() {
    step "Installing Server (${PLATFORM})"

    local url="${BASE_URL}/server-${PLATFORM}"
    download_bin "server-${PLATFORM}" "$url" "${INSTALL_DIR}/${SERVER_BIN}"

    mkdir -p "$DATA_DIR"

    echo ""
    prompt "TCP port (for Agent connections) [9000]: "
    read -r TCP_PORT < /dev/tty
    TCP_PORT="${TCP_PORT:-9000}"
    TCP_PORT="${TCP_PORT#:}"
    TCP_ADDR=":${TCP_PORT}"

    prompt "HTTP port (for Web UI) [8080]: "
    read -r HTTP_PORT < /dev/tty
    HTTP_PORT="${HTTP_PORT:-8080}"
    HTTP_PORT="${HTTP_PORT#:}"
    HTTP_ADDR=":${HTTP_PORT}"

    prompt "Admin password [admin]: "
    read -r ADMIN_PASS < /dev/tty
    ADMIN_PASS="${ADMIN_PASS:-admin}"

    prompt "Database path [${DATA_DIR}/hijack.db]: "
    read -r DB_PATH < /dev/tty
    DB_PATH="${DB_PATH:-${DATA_DIR}/hijack.db}"

    prompt "Enable compression? [Y/n]: "
    read -r COMP < /dev/tty
    COMP="${COMP:-Y}"
    local compress_flag="-compress=true"
    if [[ "$COMP" =~ ^[nN] ]]; then
        compress_flag="-compress=false"
    fi

    mkdir -p "$(dirname "$DB_PATH")"

    if [ "$DETECTED_OS" = "linux" ] && command -v systemctl &>/dev/null; then
        step "Creating systemd service..."
        cat > "${SERVICE_DIR}/ip-hijack-server.service" <<UNIT
[Unit]
Description=IP Hijack Management Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/${SERVER_BIN} -tcp ${TCP_ADDR} -http ${HTTP_ADDR} -db ${DB_PATH} -admin-pass ${ADMIN_PASS} ${compress_flag}
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
UNIT

        systemctl daemon-reload
        systemctl enable ip-hijack-server
        systemctl start ip-hijack-server || true
        sleep 1
        if systemctl is-active ip-hijack-server &>/dev/null; then
            info "Service created and started"
            echo ""
            echo -e "  ${DIM}Web UI:${RESET}  http://<your-ip>${HTTP_ADDR}"
            echo -e "  ${DIM}Agent TCP:${RESET}  ${TCP_ADDR}"
        else
            warn "Service created but failed to start. Recent logs:"
            echo ""
            journalctl -u ip-hijack-server --no-pager -n 10 2>/dev/null || systemctl status ip-hijack-server --no-pager 2>/dev/null || true
        fi
        echo ""
        echo -e "  ${DIM}Manage with:${RESET}"
        echo -e "    systemctl status  ip-hijack-server"
        echo -e "    systemctl restart ip-hijack-server"
        echo -e "    journalctl -u ip-hijack-server -f"
    else
        echo ""
        info "Run manually:"
        echo -e "    ${SERVER_BIN} -tcp ${TCP_ADDR} -http ${HTTP_ADDR} -db ${DB_PATH} -admin-pass ${ADMIN_PASS} ${compress_flag}"
    fi
}

# ─── Uninstall ────────────────────────────────────────────────────
uninstall() {
    step "Uninstalling IP Hijack Server..."

    if [ "$DETECTED_OS" = "linux" ] && command -v systemctl &>/dev/null; then
        if systemctl is-active ip-hijack-server &>/dev/null; then
            systemctl stop ip-hijack-server
            info "Stopped ip-hijack-server"
        fi
        if [ -f "${SERVICE_DIR}/ip-hijack-server.service" ]; then
            systemctl disable ip-hijack-server 2>/dev/null || true
            rm -f "${SERVICE_DIR}/ip-hijack-server.service"
            info "Removed ip-hijack-server service"
        fi
        systemctl daemon-reload
    fi

    if [ -f "${INSTALL_DIR}/${SERVER_BIN}" ]; then
        rm -f "${INSTALL_DIR}/${SERVER_BIN}"
        info "Removed ${INSTALL_DIR}/${SERVER_BIN}"
    fi

    echo ""
    prompt "Also remove data (database, UUID) in ${DATA_DIR}? [y/N]: "
    read -r RM_DATA < /dev/tty
    if [[ "$RM_DATA" =~ ^[yY] ]]; then
        rm -rf "$DATA_DIR"
        info "Removed ${DATA_DIR}"
    else
        warn "Data preserved in ${DATA_DIR}"
    fi

    info "Uninstall complete"
}

# ─── Update ───────────────────────────────────────────────────────
update() {
    step "Updating Server..."

    if [ ! -f "${INSTALL_DIR}/${SERVER_BIN}" ]; then
        warn "Server is not installed. Run install first."
        return
    fi

    download_bin "server-${PLATFORM}" "${BASE_URL}/server-${PLATFORM}" "${INSTALL_DIR}/${SERVER_BIN}"
    if [ "$DETECTED_OS" = "linux" ] && systemctl is-active ip-hijack-server &>/dev/null; then
        systemctl restart ip-hijack-server
        info "Restarted ip-hijack-server"
    fi
}

# ─── Status ───────────────────────────────────────────────────────
show_status() {
    step "Server Status"
    echo ""

    if [ -f "${INSTALL_DIR}/${SERVER_BIN}" ]; then
        echo -e "  Server binary: ${GREEN}installed${RESET}  (${INSTALL_DIR}/${SERVER_BIN})"
    else
        echo -e "  Server binary: ${DIM}not installed${RESET}"
    fi

    if [ "$DETECTED_OS" = "linux" ] && command -v systemctl &>/dev/null; then
        echo ""
        if systemctl is-active ip-hijack-server &>/dev/null; then
            echo -e "  ip-hijack-server: ${GREEN}running${RESET}"
        elif [ -f "${SERVICE_DIR}/ip-hijack-server.service" ]; then
            echo -e "  ip-hijack-server: ${YELLOW}stopped${RESET}"
        else
            echo -e "  ip-hijack-server: ${DIM}not configured${RESET}"
        fi
    fi

    echo ""
    echo -e "  Platform: ${BOLD}${PLATFORM}${RESET}"

    if [ -f "${DATA_DIR}/hijack.db" ]; then
        local db_size
        db_size=$(du -h "${DATA_DIR}/hijack.db" | cut -f1)
        echo -e "  Database: ${DATA_DIR}/hijack.db (${db_size})"
    fi
}

# ─── Service Control ──────────────────────────────────────────────
svc_start() {
    if ! command -v systemctl &>/dev/null; then error "systemd not available"; exit 1; fi
    if ! [ -f "${SERVICE_DIR}/ip-hijack-server.service" ]; then error "Service not installed"; exit 1; fi
    systemctl start ip-hijack-server && info "ip-hijack-server started" || error "Failed to start"
}

svc_stop() {
    if ! command -v systemctl &>/dev/null; then error "systemd not available"; exit 1; fi
    systemctl stop ip-hijack-server && info "ip-hijack-server stopped" || error "Failed to stop"
}

svc_restart() {
    if ! command -v systemctl &>/dev/null; then error "systemd not available"; exit 1; fi
    if ! [ -f "${SERVICE_DIR}/ip-hijack-server.service" ]; then error "Service not installed"; exit 1; fi
    systemctl restart ip-hijack-server && info "ip-hijack-server restarted" || error "Failed to restart"
}

svc_logs() {
    if ! command -v journalctl &>/dev/null; then error "journalctl not available"; exit 1; fi
    journalctl -u ip-hijack-server -f --no-pager -n 50
}

# ─── Main Menu ────────────────────────────────────────────────────
main_menu() {
    print_banner
    detect_arch
    info "Detected platform: ${BOLD}${PLATFORM}${RESET}"
    echo ""

    echo -e "  ${BOLD}Select an option:${RESET}"
    echo ""
    echo -e "    ${CYAN}1)${RESET}  Install Server"
    echo -e "    ${CYAN}2)${RESET}  Update Server"
    echo -e "    ${CYAN}3)${RESET}  Uninstall Server"
    echo -e "    ${DIM}────────────────────${RESET}"
    echo -e "    ${CYAN}4)${RESET}  Start Server"
    echo -e "    ${CYAN}5)${RESET}  Stop Server"
    echo -e "    ${CYAN}6)${RESET}  Restart Server"
    echo -e "    ${CYAN}7)${RESET}  View Logs"
    echo -e "    ${DIM}────────────────────${RESET}"
    echo -e "    ${CYAN}8)${RESET}  Show Status"
    echo -e "    ${CYAN}0)${RESET}  Exit"
    echo ""
    prompt "Enter choice [0-8]: "
    read -r choice < /dev/tty

    case "$choice" in
        1) check_root; install_server ;;
        2) check_root; update ;;
        3) check_root; uninstall ;;
        4) check_root; svc_start ;;
        5) check_root; svc_stop ;;
        6) check_root; svc_restart ;;
        7) svc_logs ;;
        8) show_status ;;
        0) echo "  Bye."; exit 0 ;;
        *) error "Invalid choice"; exit 1 ;;
    esac

    echo ""
    info "Done!"
    echo ""
}

case "${1:-}" in
    install)    check_root; detect_arch; install_server ;;
    update)     check_root; detect_arch; update ;;
    uninstall)  check_root; detect_arch; uninstall ;;
    start)      check_root; svc_start ;;
    stop)       check_root; svc_stop ;;
    restart)    check_root; svc_restart ;;
    logs)       svc_logs ;;
    status)     detect_arch; show_status ;;
    *)          main_menu ;;
esac
