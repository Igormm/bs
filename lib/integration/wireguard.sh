#!/usr/bin/env bs
# shellcheck shell=bash
# shellcheck disable=SC2155

# wireguard.sh — WireGuard Integration Module for BS Framework
# Модуль интеграции WireGuard для фреймворка BS
#
# Description:
#   Provides comprehensive WireGuard VPN management functionality including
#   configuration, key management, peer management, and monitoring.
#   Предоставляет комплексную функциональность управления VPN WireGuard,
#   включая конфигурацию, управление ключами, пирами и мониторинг.
#
# Features:
#   - Configuration file management
#   - Key pair generation and management
#   - Peer management (add/remove/list)
#   - Connection status monitoring
#   - Cross-platform support
#   - Backup and restore functionality
#
# Dependencies:
#   - wireguard-tools (wg, wg-quick)
#   - openssl (for key generation)
#   - iproute2 (for network configuration)
#
# Usage:
#   source "${BS_HOME}/boot.sh"
#   BS::init
#   wireguard::init
#   wireguard::create_interface "wg0" "10.0.0.1/24"
#   wireguard::add_peer "wg0" "peer_pubkey" "10.0.0.2/32"
#
# @author BS Framework
# @since 2026-01-06
# @version 1.0.0
# @depends core/const, core/logger, core/utils, core/errorhandler, lib/system/platformcheck, lib/io/files

# Source Guard / Защита от повторной загрузки
bs::guard "INTEGRATION_WIREGUARD" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "../../core/errorhandler.sh" "../system/platformcheck.sh" "../io/files.sh"

# WireGuard configuration constants
readonly WIREGUARD_CONFIG_DIR="/etc/wireguard"
readonly WIREGUARD_KEY_DIR="${WIREGUARD_CONFIG_DIR}/keys"
readonly WIREGUARD_BACKUP_DIR="/var/backups/wireguard"
readonly WIREGUARD_DEFAULT_PORT=51820
readonly WIREGUARD_DEFAULT_KEEPALIVE=25

# Module initialization
wireguard::init() {
    log::info "Initializing WireGuard module..."
    
    # Check if running as root
    if [[ "$EUID" -ne 0 ]]; then
        error::throw "WireGuard operations require root privileges" \
            "${LIB_ERROR_PERMISSION_DENIED}"
    fi
    
    # Check dependencies
    wireguard::check_dependencies
    
    # Create necessary directories
    wireguard::create_directories
    
    log::success "WireGuard module initialized successfully"
}

# Check WireGuard dependencies
wireguard::check_dependencies() {
    local missing_deps=()
    
    log::debug "Checking WireGuard dependencies..."

    deps::missing_tools missing_deps \
        wg:wireguard-tools wg-quick:wireguard-tools openssl ip:iproute2
    
    # Install missing dependencies based on platform
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log::warn "Missing dependencies: ${missing_deps[*]}"
        wireguard::install_dependencies "${missing_deps[@]}"
    else
        log::debug "All dependencies are installed"
    fi
}

# Install missing dependencies
wireguard::install_dependencies() {
    local deps=("$@")
    
    log::info "Installing missing dependencies: ${deps[*]}..."
    
    if platformcheck::is_debian || platformcheck::is_ubuntu; then
        apt-get update
        apt-get install -y "${deps[@]}"
    elif platformcheck::is_alma || platformcheck::is_fedora; then
        if [[ " ${deps[*]} " =~ " wireguard-tools " ]]; then
            dnf install -y wireguard-tools
        fi
        if [[ " ${deps[*]} " =~ " openssl " ]]; then
            dnf install -y openssl
        fi
        if [[ " ${deps[*]} " =~ " iproute2 " ]]; then
            dnf install -y iproute
        fi
    elif platformcheck::is_macos; then
        if ! utils::has brew; then
            error::throw "Homebrew is required for macOS" \
                "${LIB_ERROR_DEPENDENCY_MISSING}"
        fi
        brew install wireguard-tools openssl
    else
        error::throw "Unsupported platform for dependency installation" \
            "${LIB_ERROR_PLATFORM_UNSUPPORTED}"
    fi
    
    log::success "Dependencies installed successfully"
}

# Create necessary directories
wireguard::create_directories() {
    
    log::debug "Creating WireGuard directories..."
    
    mkdir -p "${WIREGUARD_CONFIG_DIR}" || {
        error::throw "Failed to create config directory" \
            "${LIB_ERROR_FILE_OPERATION}"
    }
    
    mkdir -p "${WIREGUARD_KEY_DIR}" || {
        error::throw "Failed to create key directory" \
            "${LIB_ERROR_FILE_OPERATION}"
    }
    
    mkdir -p "${WIREGUARD_BACKUP_DIR}" || {
        error::throw "Failed to create backup directory" \
            "${LIB_ERROR_FILE_OPERATION}"
    }
    
    # Set proper permissions
    chmod 700 "${WIREGUARD_KEY_DIR}"
    chmod 755 "${WIREGUARD_CONFIG_DIR}"
    chmod 750 "${WIREGUARD_BACKUP_DIR}"
    
    log::debug "WireGuard directories created with proper permissions"
}

# Generate WireGuard key pair
wireguard::generate_keypair() {
    local interface="${1:-}"
    
    if [[ -z "${interface}" ]]; then
        error::throw "Interface name is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    local private_key_file="${WIREGUARD_KEY_DIR}/${interface}_private.key"
    local public_key_file="${WIREGUARD_KEY_DIR}/${interface}_public.key"
    
    log::info "Generating key pair for interface: ${interface}"
    
    # Generate private key
    wg genkey | tee "${private_key_file}" | wg pubkey > "${public_key_file}"
    
    if [[ ! -f "${private_key_file}" ]] || [[ ! -f "${public_key_file}" ]]; then
        error::throw "Failed to generate key pair" \
            "${LIB_ERROR_FILE_OPERATION}"
    fi
    
    # Set proper permissions
    chmod 600 "${private_key_file}"
    chmod 644 "${public_key_file}"
    
    local public_key
    public_key=$(cat "${public_key_file}")
    
    log::success "Key pair generated for ${interface}"
    log::info "Public key: ${public_key}"
    
    echo "${public_key}"
}

# Create WireGuard interface configuration
wireguard::create_interface() {
    local interface="${1:-}"
    local address="${2:-}"
    local listen_port="${3:-${WIREGUARD_DEFAULT_PORT}}"
    local dns="${4:-1.1.1.1,8.8.8.8}"
    local wan_interface="${5:-}"
    
    if [[ -z "${interface}" ]] || [[ -z "${address}" ]]; then
        error::throw "Interface name and address are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    # Autodetect WAN interface from the default route if not specified
    if [[ -z "${wan_interface}" ]]; then
        wan_interface=$(utils::quiet_err ip route show default | awk '/^default/ {print $5; exit}')
        wan_interface="${wan_interface:-eth0}"
    fi
    
    local config_file="${WIREGUARD_CONFIG_DIR}/${interface}.conf"
    
    log::info "Creating WireGuard interface: ${interface}"
    
    # Generate key pair if not exists
    local private_key_file="${WIREGUARD_KEY_DIR}/${interface}_private.key"
    if [[ ! -f "${private_key_file}" ]]; then
        wireguard::generate_keypair "${interface}"
    fi
    
    local private_key
    private_key=$(cat "${private_key_file}")
    
    # Create configuration file
    cat > "${config_file}" << EOF
# WireGuard configuration for ${interface}
# Generated by BS Framework on $(date)

[Interface]
Address = ${address}
PrivateKey = ${private_key}
ListenPort = ${listen_port}
DNS = ${dns}

# Save configuration
SaveConfig = true

# Firewall rules and NAT for internet access
PostUp = ufw route allow in on ${interface} out on ${wan_interface}; iptables -A FORWARD -i ${interface} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${wan_interface} -j MASQUERADE
PostDown = ufw route delete allow in on ${interface} out on ${wan_interface}; iptables -D FORWARD -i ${interface} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${wan_interface} -j MASQUERADE

EOF
    
    if [[ ! -f "${config_file}" ]]; then
        error::throw "Failed to create configuration file" \
            "${LIB_ERROR_FILE_OPERATION}"
    fi
    
    chmod 600 "${config_file}"
    
    log::success "Interface ${interface} created successfully"
    log::info "Configuration file: ${config_file}"
}

# Add peer to interface
wireguard::add_peer() {
    local interface="${1:-}"
    local peer_pubkey="${2:-}"
    local allowed_ips="${3:-}"
    local endpoint="${4:-}"
    local persistent_keepalive="${5:-${WIREGUARD_DEFAULT_KEEPALIVE}}"
    
    if [[ -z "${interface}" ]] || [[ -z "${peer_pubkey}" ]] || [[ -z "${allowed_ips}" ]]; then
        error::throw "Interface, peer public key, and allowed IPs are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    local config_file="${WIREGUARD_CONFIG_DIR}/${interface}.conf"
    
    if [[ ! -f "${config_file}" ]]; then
        error::throw "Interface ${interface} does not exist" \
            "${LIB_ERROR_FILE_NOT_FOUND}"
    fi
    
    log::info "Adding peer to interface: ${interface}"
    
    # Backup original config
    cp "${config_file}" "${config_file}.backup.$(utils::now_s)"
    
    # Add peer configuration
    cat >> "${config_file}" << EOF

[Peer]
# Peer added on $(date)
PublicKey = ${peer_pubkey}
AllowedIPs = ${allowed_ips}
EOF
    
    # Add endpoint if provided
    if [[ -n "${endpoint}" ]]; then
        io::files::append "${config_file}" "Endpoint = ${endpoint}"
    fi
    
    # Add persistent keepalive
    if [[ -n "${persistent_keepalive}" ]]; then
        io::files::append "${config_file}" "PersistentKeepalive = ${persistent_keepalive}"
    fi
    
    log::success "Peer added to ${interface} successfully"
}

# Remove peer from interface
wireguard::remove_peer() {
    local interface="${1:-}"
    local peer_pubkey="${2:-}"
    
    if [[ -z "${interface}" ]] || [[ -z "${peer_pubkey}" ]]; then
        error::throw "Interface and peer public key are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    local config_file="${WIREGUARD_CONFIG_DIR}/${interface}.conf"
    
    if [[ ! -f "${config_file}" ]]; then
        error::throw "Interface ${interface} does not exist" \
            "${LIB_ERROR_FILE_NOT_FOUND}"
    fi
    
    log::info "Removing peer from interface: ${interface}"
    
    # Backup original config
    cp "${config_file}" "${config_file}.backup.$(utils::now_s)"
    
    # Create temporary file
    local temp_file
    temp_file=$(mktemp)
    
    # Remove peer section
    awk -v pubkey="${peer_pubkey}" '
        /^\[Peer\]/ { in_peer=1; skip=0; next }
        /^\[.*\]/ { in_peer=0 }
        in_peer && /PublicKey/ && $3 == pubkey { skip=1 }
        !skip { print }
    ' "${config_file}" > "${temp_file}"
    
    # Replace original file
    mv "${temp_file}" "${config_file}"
    
    log::success "Peer removed from ${interface} successfully"
}

# Start WireGuard interface
wireguard::start_interface() {
    local interface="${1:-}"
    
    if [[ -z "${interface}" ]]; then
        error::throw "Interface name is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Starting WireGuard interface: ${interface}"
    
    # Check if interface is already running
    if utils::quiet wg show "${interface}"; then
        log::warn "Interface ${interface} is already running"
        return 0
    fi
    
    # Start interface using wg-quick
    wg-quick up "${interface}" || {
        error::throw "Failed to start interface ${interface}" \
            "${LIB_ERROR_COMMAND_FAILED}"
    }
    
    log::success "Interface ${interface} started successfully"
}

# Stop WireGuard interface
wireguard::stop_interface() {
    local interface="${1:-}"
    
    if [[ -z "${interface}" ]]; then
        error::throw "Interface name is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Stopping WireGuard interface: ${interface}"
    
    # Check if interface is running
    if ! utils::quiet wg show "${interface}"; then
        log::warn "Interface ${interface} is not running"
        return 0
    fi
    
    # Stop interface using wg-quick
    wg-quick down "${interface}" || {
        error::throw "Failed to stop interface ${interface}" \
            "${LIB_ERROR_COMMAND_FAILED}"
    }
    
    log::success "Interface ${interface} stopped successfully"
}

# Get interface status
wireguard::get_interface_status() {
    local interface="${1:-}"
    
    if [[ -z "${interface}" ]]; then
        error::throw "Interface name is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::debug "Getting status for interface: ${interface}"
    
    # Check if interface exists
    if ! utils::quiet wg show "${interface}"; then
        log::info "Interface ${interface} is not running"
        return "${E_ERROR}"
    fi
    
    # Get detailed status
    wg show "${interface}"
}

# List all WireGuard interfaces
wireguard::list_interfaces() {
    
    log::debug "Listing all WireGuard interfaces..."
    
    # Get interfaces using wg command
    if utils::has wg; then
        wg show interfaces
    else
        # Fallback: list config files
        find "${WIREGUARD_CONFIG_DIR}" -name "*.conf" -exec basename {} .conf \;
    fi
}

# Backup WireGuard configuration
wireguard::backup_config() {
    local interface="${1:-}"
    local backup_name="${2:-backup_$(utils::stamp)}"
    
    if [[ -z "${interface}" ]]; then
        error::throw "Interface name is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    local config_file="${WIREGUARD_CONFIG_DIR}/${interface}.conf"
    local backup_file="${WIREGUARD_BACKUP_DIR}/${interface}_${backup_name}.conf"
    
    if [[ ! -f "${config_file}" ]]; then
        error::throw "Configuration file not found" \
            "${LIB_ERROR_FILE_NOT_FOUND}"
    fi
    
    log::info "Creating backup for interface: ${interface}"
    
    # Copy configuration file
    cp "${config_file}" "${backup_file}" || {
        error::throw "Failed to create backup" \
            "${LIB_ERROR_FILE_OPERATION}"
    }
    
    # Copy keys if they exist
    local private_key_file="${WIREGUARD_KEY_DIR}/${interface}_private.key"
    local public_key_file="${WIREGUARD_KEY_DIR}/${interface}_public.key"
    
    if [[ -f "${private_key_file}" ]]; then
        cp "${private_key_file}" "${WIREGUARD_BACKUP_DIR}/${interface}_${backup_name}_private.key"
    fi
    
    if [[ -f "${public_key_file}" ]]; then
        cp "${public_key_file}" "${WIREGUARD_BACKUP_DIR}/${interface}_${backup_name}_public.key"
    fi
    
    log::success "Backup created: ${backup_file}"
    echo "${backup_file}"
}

# Restore WireGuard configuration
wireguard::restore_config() {
    local interface="${1:-}"
    local backup_file="${2:-}"
    
    if [[ -z "${interface}" ]] || [[ -z "${backup_file}" ]]; then
        error::throw "Interface name and backup file are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    if [[ ! -f "${backup_file}" ]]; then
        error::throw "Backup file not found" \
            "${LIB_ERROR_FILE_NOT_FOUND}"
    fi
    
    log::info "Restoring configuration for interface: ${interface}"
    
    # Stop interface if running
    if utils::quiet wg show "${interface}"; then
        wireguard::stop_interface "${interface}"
    fi
    
    # Restore configuration file
    cp "${backup_file}" "${WIREGUARD_CONFIG_DIR}/${interface}.conf" || {
        error::throw "Failed to restore configuration" \
            "${LIB_ERROR_FILE_OPERATION}"
    }
    
    log::success "Configuration restored for interface: ${interface}"
}

# Generate QR code for mobile clients (requires qrencode)
wireguard::generate_qr() {
    local interface="${1:-}"
    
    if [[ -z "${interface}" ]]; then
        error::throw "Interface name is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    # Check if qrencode is installed
    if ! utils::has qrencode; then
        log::warn "qrencode is not installed. Installing..."
        
        if platformcheck::is_debian || platformcheck::is_ubuntu; then
            apt-get install -y qrencode
        elif platformcheck::is_alma || platformcheck::is_fedora; then
            dnf install -y qrencode
        elif platformcheck::is_macos; then
            brew install qrencode
        else
            error::throw "qrencode not available on this platform" \
                "${LIB_ERROR_DEPENDENCY_MISSING}"
        fi
    fi
    
    local config_file="${WIREGUARD_CONFIG_DIR}/${interface}.conf"
    
    if [[ ! -f "${config_file}" ]]; then
        error::throw "Configuration file not found" \
            "${LIB_ERROR_FILE_NOT_FOUND}"
    fi
    
    log::info "Generating QR code for interface: ${interface}"
    
    # Generate QR code
    qrencode -t ansiutf8 < "${config_file}"
    
    log::success "QR code generated for ${interface}"
}

# Enable automatic startup
wireguard::enable_autostart() {
    local interface="${1:-}"
    
    if [[ -z "${interface}" ]]; then
        error::throw "Interface name is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Enabling autostart for interface: ${interface}"
    
    if platformcheck::is_debian || platformcheck::is_ubuntu || \
       platformcheck::is_alma || platformcheck::is_fedora; then
        
        # Enable using wg-quick service
        systemctl enable wg-quick@${interface} || {
            error::throw "Failed to enable autostart" \
                "${LIB_ERROR_COMMAND_FAILED}"
        }
        
        log::success "Autostart enabled for ${interface}"
    elif platformcheck::is_macos; then
        log::warn "Autostart not implemented for macOS yet"
    else
        log::warn "Autostart not supported on this platform"
    fi
}

# Disable automatic startup
wireguard::disable_autostart() {
    local interface="${1:-}"
    
    if [[ -z "${interface}" ]]; then
        error::throw "Interface name is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Disabling autostart for interface: ${interface}"
    
    if platformcheck::is_debian || platformcheck::is_ubuntu || \
       platformcheck::is_alma || platformcheck::is_fedora; then
        
        # Disable using wg-quick service
        systemctl disable wg-quick@${interface} || {
            error::throw "Failed to disable autostart" \
                "${LIB_ERROR_COMMAND_FAILED}"
        }
        
        log::success "Autostart disabled for ${interface}"
    elif platformcheck::is_macos; then
        log::warn "Autostart disable not implemented for macOS yet"
    else
        log::warn "Autostart disable not supported on this platform"
    fi
}

# Get public IP address for endpoint
wireguard::get_public_ip() {
    
    log::debug "Getting public IP address..."
    
    # Try multiple services for reliability
    local ip_services=(
        "https://api.ipify.org"
        "https://ifconfig.me"
        "https://ipecho.net/plain"
    )
    
    for service in "${ip_services[@]}"; do
        local ip
        ip=$(utils::quiet_err curl -s --connect-timeout 5 --max-time 10 "${service}")
        
        if [[ -n "${ip}" ]] && [[ "${ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "${ip}"
            return 0
        fi
    done
    
    log::warn "Failed to get public IP address"
    return "${E_ERROR}"
}

# Create client configuration for road warrior setup
wireguard::create_client_config() {
    local client_name="${1:-}"
    local server_pubkey="${2:-}"
    local server_endpoint="${3:-}"
    local allowed_ips="${4:-0.0.0.0/0}"
    
    if [[ -z "${client_name}" ]] || [[ -z "${server_pubkey}" ]] || [[ -z "${server_endpoint}" ]]; then
        error::throw "Client name, server public key, and endpoint are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    local client_config_file="${WIREGUARD_CONFIG_DIR}/${client_name}_client.conf"
    local client_private_key_file="${WIREGUARD_KEY_DIR}/${client_name}_client_private.key"
    local client_public_key_file="${WIREGUARD_KEY_DIR}/${client_name}_client_public.key"
    
    log::info "Creating client configuration: ${client_name}"
    
    # Generate client key pair
    if [[ ! -f "${client_private_key_file}" ]]; then
        wg genkey | tee "${client_private_key_file}" | wg pubkey > "${client_public_key_file}"
        chmod 600 "${client_private_key_file}"
        chmod 644 "${client_public_key_file}"
    fi
    
    local client_private_key
    client_private_key=$(cat "${client_private_key_file}")
    
    # Create client configuration
    cat > "${client_config_file}" << EOF
# WireGuard client configuration for ${client_name}
# Generated by BS Framework on $(date)

[Interface]
PrivateKey = ${client_private_key}
Address = 10.0.0.$(shuf -i 2-254 -n 1)/32
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = ${server_pubkey}
Endpoint = ${server_endpoint}
AllowedIPs = ${allowed_ips}
PersistentKeepalive = ${WIREGUARD_DEFAULT_KEEPALIVE}

EOF
    
    chmod 600 "${client_config_file}"
    
    local client_public_key
    client_public_key=$(cat "${client_public_key_file}")
    
    log::success "Client configuration created: ${client_config_file}"
    log::info "Client public key: ${client_public_key}"
    
    # Return client public key for server configuration
    echo "${client_public_key}"
}

# Module info
wireguard::info() {
    cat << EOF
WireGuard Integration Module v1.0.0

Available functions:
  wireguard::init                    - Initialize module
  wireguard::create_interface        - Create new WireGuard interface
  wireguard::add_peer               - Add peer to interface
  wireguard::remove_peer            - Remove peer from interface
  wireguard::start_interface        - Start WireGuard interface
  wireguard::stop_interface         - Stop WireGuard interface
  wireguard::get_interface_status   - Get interface status
  wireguard::list_interfaces        - List all interfaces
  wireguard::backup_config          - Backup configuration
  wireguard::restore_config         - Restore configuration
  wireguard::generate_qr            - Generate QR code for mobile
  wireguard::enable_autostart       - Enable autostart
  wireguard::disable_autostart      - Disable autostart
  wireguard::get_public_ip          - Get public IP address
  wireguard::create_client_config   - Create client configuration

Configuration directories:
  Config: ${WIREGUARD_CONFIG_DIR}
  Keys: ${WIREGUARD_KEY_DIR}
  Backups: ${WIREGUARD_BACKUP_DIR}
EOF
}
