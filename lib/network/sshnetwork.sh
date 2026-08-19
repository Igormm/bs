#!/usr/bin/env bs
# shellcheck shell=bash
# shellcheck disable=SC2155

# sshnetwork.sh — SSH Network Module for BS Framework
# Модуль SSH сети для фреймворка BS
#
# Description:
#   Provides comprehensive SSH network management including device discovery,
#   file transfers, remote command execution, and network monitoring.
#   Предоставляет комплексное управление SSH сетью, включая обнаружение устройств,
#   передачу файлов, удаленное выполнение команд и мониторинг сети.
#
# Features:
#   - Automatic device discovery in local network
#   - File transfers (scp, rsync)
#   - Remote command execution
#   - SSH key management
#   - Connection testing and monitoring
#   - Batch operations on multiple hosts
#   - Network topology mapping
#   - Performance metrics
#
# Dependencies:
#   - ssh (client and server)
#   - scp (secure copy)
#   - rsync (for efficient transfers)
#   - nmap (for network scanning)
#   - ping (for connectivity testing)
#   - ssh-keygen (for key management)
#
# Usage:
#   source "${BS_HOME}/boot.sh"
#   BS::init
#   sshnetwork::init
#   sshnetwork::discover_devices "192.168.1.0/24"
#   sshnetwork::transfer_file "/local/file" "user@host:/remote/path"
#
# @author BS Framework
# @since 2026-01-06
# @version 1.0.0
# @depends core/const, core/logger, core/utils, core/errorhandler, lib/system/platformcheck, lib/io/files

# Source Guard / Защита от повторной загрузки
bs::guard "NETWORK_SSH" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "../../core/errorhandler.sh" "../system/platformcheck.sh" "../io/files.sh"

# SSH Network configuration constants
readonly SSH_NETWORK_CONFIG_DIR="${HOME}/.config/sshnetwork"
readonly SSH_NETWORK_KNOWN_HOSTS_FILE="${SSH_NETWORK_CONFIG_DIR}/known_devices"
readonly SSH_NETWORK_LOG_FILE="${SSH_NETWORK_CONFIG_DIR}/network.log"
readonly SSH_NETWORK_SCAN_TIMEOUT=5
readonly SSH_NETWORK_CONNECT_TIMEOUT=10
readonly SSH_NETWORK_DEFAULT_PORT=22
readonly SSH_NETWORK_BASH_PORT=2222  # Alternative SSH port for BS

# Module state variables
SSH_NETWORK_DISCOVERED_DEVICES=()
SSH_NETWORK_SSH_KEY_PATH="${HOME}/.ssh/id_rsa_bosa"
SSH_NETWORK_SSH_PUBLIC_KEY_PATH="${SSH_NETWORK_SSH_KEY_PATH}.pub"

# Module initialization
sshnetwork::init() {
    local func_name="sshnetwork::init"
    
    log::info "Initializing SSH Network module..."
    
    # Check dependencies
    sshnetwork::check_dependencies
    
    # Create necessary directories
    mkdir -p "${SSH_NETWORK_CONFIG_DIR}" || {
        errorhandler::throw "${func_name}" "Failed to create config directory" \
            "${LIB_ERROR_FILE_OPERATION}"
    }
    
    mkdir -p "${HOME}/.ssh" || {
        errorhandler::throw "${func_name}" "Failed to create SSH directory" \
            "${LIB_ERROR_FILE_OPERATION}"
    }
    
    # Create known devices file if it doesn't exist
    if [[ ! -f "${SSH_NETWORK_KNOWN_HOSTS_FILE}" ]]; then
        touch "${SSH_NETWORK_KNOWN_HOSTS_FILE}" || {
            errorhandler::throw "${func_name}" "Failed to create known devices file" \
                "${LIB_ERROR_FILE_OPERATION}"
        }
        chmod 600 "${SSH_NETWORK_KNOWN_HOSTS_FILE}"
    fi
    
    # Generate SSH keys if they don't exist
    sshnetwork::generate_ssh_keys
    
    log::success "SSH Network module initialized successfully"
}

# Check SSH Network dependencies
sshnetwork::check_dependencies() {
    local func_name="sshnetwork::check_dependencies"
    local missing_deps=()
    
    log::debug "Checking SSH Network dependencies..."

    deps::missing_tools missing_deps \
        ssh:openssh-client scp:openssh-client rsync nmap ping:iputils-ping ssh-keygen:openssh-client
    
    # Install missing dependencies based on platform
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log::warn "Missing dependencies: ${missing_deps[*]}"
        sshnetwork::install_dependencies "${missing_deps[@]}"
    else
        log::debug "All dependencies are installed"
    fi
}

# Install missing dependencies
sshnetwork::install_dependencies() {
    local func_name="sshnetwork::install_dependencies"
    local deps=("$@")
    
    log::info "Installing missing dependencies: ${deps[*]}..."
    
    if platformcheck::is_debian || platformcheck::is_ubuntu; then
        apt-get update
        apt-get install -y openssh-client rsync nmap iputils-ping
    elif platformcheck::is_alma || platformcheck::is_fedora; then
        dnf install -y openssh rsync nmap iputils
    elif platformcheck::is_macos; then
        if ! utils::has brew; then
            errorhandler::throw "${func_name}" "Homebrew is required for macOS" \
                "${LIB_ERROR_DEPENDENCY_MISSING}"
        fi
        brew install openssh rsync nmap
    else
        errorhandler::throw "${func_name}" "Unsupported platform for dependency installation" \
            "${LIB_ERROR_PLATFORM_UNSUPPORTED}"
    fi
    
    log::success "Dependencies installed successfully"
}

# Generate SSH keys for BS
sshnetwork::generate_ssh_keys() {
    local func_name="sshnetwork::generate_ssh_keys"
    
    if [[ ! -f "${SSH_NETWORK_SSH_KEY_PATH}" ]]; then
        log::info "Generating SSH keys for BS..."
        
        ssh-keygen -t rsa -b 4096 -f "${SSH_NETWORK_SSH_KEY_PATH}" -N "" -C "BS@sshnetwork" || {
            errorhandler::throw "${func_name}" "Failed to generate SSH keys" \
                "${LIB_ERROR_COMMAND_FAILED}"
        }
        
        chmod 600 "${SSH_NETWORK_SSH_KEY_PATH}"
        chmod 644 "${SSH_NETWORK_SSH_PUBLIC_KEY_PATH}"
        
        log::success "SSH keys generated: ${SSH_NETWORK_SSH_KEY_PATH}"
    else
        log::debug "SSH keys already exist"
    fi
}

# Discover SSH-enabled devices in network
sshnetwork::discover_devices() {
    local func_name="sshnetwork::discover_devices"
    local network_range="${1:-}"
    local port="${2:-${SSH_NETWORK_DEFAULT_PORT}}"
    
    if [[ -z "${network_range}" ]]; then
        # Auto-detect local network
        network_range=$(sshnetwork::get_local_network)
        if [[ -z "${network_range}" ]]; then
            errorhandler::throw "${func_name}" "Could not detect local network range" \
                "${LIB_ERROR_NETWORK}"
        fi
    fi
    
    log::info "Discovering SSH devices in network: ${network_range}"
    
    # Clear previous discoveries
    SSH_NETWORK_DISCOVERED_DEVICES=()
    
    # Use nmap to find SSH services
    local nmap_output
    nmap_output=$(utils::quiet_err nmap -p "${port}" --open -oG - "${network_range}" | grep "open/" || true)
    
    if [[ -z "${nmap_output}" ]]; then
        log::warn "No SSH devices found in network: ${network_range}"
        return "${E_ERROR}"
    fi
    
    # Parse nmap output
    while IFS= read -r line; do
        if [[ -n "${line}" ]]; then
            local ip
            ip=$(echo "${line}" | awk '{print $2}')
            
            if [[ -n "${ip}" ]]; then
                # Test SSH connectivity
                if sshnetwork::test_connection "${ip}" "${port}"; then
                    SSH_NETWORK_DISCOVERED_DEVICES+=("${ip}:${port}")
                    log::info "Found SSH device: ${ip}:${port}"
                fi
            fi
        fi
    done <<< "${nmap_output}"
    
    log::success "Discovered ${#SSH_NETWORK_DISCOVERED_DEVICES[@]} SSH devices"
    
    # Save discovered devices
    sshnetwork::save_discovered_devices
    
    return 0
}

# Get local network range
sshnetwork::get_local_network() {
    local func_name="sshnetwork::get_local_network"
    
    # Try to get network information using ip command
    if utils::has ip; then
        local subnet
        subnet=$(ip route show | grep -E "src [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | head -1 | awk '{print $1}' || true)
        
        # Маршрут без src (контейнеры, VM): берём сеть scope link
        # Route without src (containers, VMs): take the scope link network
        if [[ -z "${subnet}" ]]; then
            subnet=$(utils::quiet_err ip -4 route show scope link | head -1 | awk '{print $1}' || true)
        fi
        
        if [[ -n "${subnet}" ]]; then
            echo "${subnet}"
            return 0
        fi
    fi
    
    # Fallback to common private networks
    local common_networks=(
        "192.168.1.0/24"
        "192.168.0.0/24"
        "10.0.0.0/24"
        "172.16.0.0/24"
    )
    
    for network in "${common_networks[@]}"; do
        if utils::quiet ping -c 1 -W 1 "${network%.*}.1"; then
            echo "${network}"
            return 0
        fi
    done
    
    return "${E_ERROR}"
}

# Test SSH connection
sshnetwork::test_connection() {
    local func_name="sshnetwork::test_connection"
    local host="${1:-}"
    local port="${2:-${SSH_NETWORK_DEFAULT_PORT}}"
    
    if [[ -z "${host}" ]]; then
        errorhandler::throw "${func_name}" "Host is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::debug "Testing SSH connection to ${host}:${port}..."
    
    # Test with timeout
    utils::quiet_err timeout "${SSH_NETWORK_CONNECT_TIMEOUT}" bash -c "</dev/tcp/${host}/${port}"
    
    if [[ "$?" -eq 0 ]]; then
        log::debug "Connection successful to ${host}:${port}"
        return 0
    else
        log::debug "Connection failed to ${host}:${port}"
        return 1
    fi
}

# Save discovered devices to file
sshnetwork::save_discovered_devices() {
    local func_name="sshnetwork::save_discovered_devices"
    
    if [[ ${#SSH_NETWORK_DISCOVERED_DEVICES[@]} -eq 0 ]]; then
        return 0
    fi
    
    local timestamp
    timestamp=$(utils::log_stamp)
    
    io::files::append "${SSH_NETWORK_KNOWN_HOSTS_FILE}" "# SSH Network Discovery - ${timestamp}"
    for device in "${SSH_NETWORK_DISCOVERED_DEVICES[@]}"; do
        io::files::append "${SSH_NETWORK_KNOWN_HOSTS_FILE}" "${device}"
    done
    io::files::append "${SSH_NETWORK_KNOWN_HOSTS_FILE}" ""
    
    log::debug "Saved ${#SSH_NETWORK_DISCOVERED_DEVICES[@]} devices to known hosts file"
}

# Load known devices from file
sshnetwork::load_known_devices() {
    local func_name="sshnetwork::load_known_devices"
    
    if [[ ! -f "${SSH_NETWORK_KNOWN_HOSTS_FILE}" ]]; then
        return "${E_ERROR}"
    fi
    
    SSH_NETWORK_DISCOVERED_DEVICES=()
    
    while IFS= read -r line; do
        if [[ -n "${line}" ]] && [[ "${line}" != "#"* ]]; then
            SSH_NETWORK_DISCOVERED_DEVICES+=("${line}")
        fi
    done < "${SSH_NETWORK_KNOWN_HOSTS_FILE}"
    
    log::info "Loaded ${#SSH_NETWORK_DISCOVERED_DEVICES[@]} known devices"
    return 0
}

# Execute remote command
sshnetwork::execute_remote() {
    local func_name="sshnetwork::execute_remote"
    local host="${1:-}"
    local command="${2:-}"
    local user="${3:-$(whoami)}"
    local port="${4:-${SSH_NETWORK_DEFAULT_PORT}}"
    
    if [[ -z "${host}" ]] || [[ -z "${command}" ]]; then
        errorhandler::throw "${func_name}" "Host and command are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Executing on ${host}: ${command}"
    
    local ssh_options=(
        -o "StrictHostKeyChecking=no"
        -o "UserKnownHostsFile=/dev/null"
        -o "ConnectTimeout=${SSH_NETWORK_CONNECT_TIMEOUT}"
        -o "PasswordAuthentication=no"
        -p "${port}"
        -i "${SSH_NETWORK_SSH_KEY_PATH}"
    )
    
    local output
    output=$(ssh "${ssh_options[@]}" "${user}@${host}" "${command}" 2>&1)
    local exit_code=$?
    
    if [[ "${exit_code}" -eq 0 ]]; then
        log::success "Command executed successfully on ${host}"
        echo "${output}"
        return 0
    else
        log::error "Command failed on ${host}: ${output}"
        return "${exit_code}"
    fi
}

# Transfer file using scp
sshnetwork::transfer_file() {
    local func_name="sshnetwork::transfer_file"
    local source="${1:-}"
    local destination="${2:-}"
    local port="${3:-${SSH_NETWORK_DEFAULT_PORT}}"
    
    if [[ -z "${source}" ]] || [[ -z "${destination}" ]]; then
        errorhandler::throw "${func_name}" "Source and destination are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Transferring: ${source} -> ${destination}"
    
    local scp_options=(
        -o "StrictHostKeyChecking=no"
        -o "UserKnownHostsFile=/dev/null"
        -o "ConnectTimeout=${SSH_NETWORK_CONNECT_TIMEOUT}"
        -o "PasswordAuthentication=no"
        -P "${port}"
        -i "${SSH_NETWORK_SSH_KEY_PATH}"
        -r
    )
    
    scp "${scp_options[@]}" "${source}" "${destination}" || {
        errorhandler::throw "${func_name}" "File transfer failed" \
            "${LIB_ERROR_FILE_TRANSFER}"
    }
    
    log::success "File transfer completed"
}

# Transfer file using rsync (more efficient)
sshnetwork::transfer_file_rsync() {
    local func_name="sshnetwork::transfer_file_rsync"
    local source="${1:-}"
    local destination="${2:-}"
    local port="${3:-${SSH_NETWORK_DEFAULT_PORT}}"
    local options="${4:-}"
    
    if [[ -z "${source}" ]] || [[ -z "${destination}" ]]; then
        errorhandler::throw "${func_name}" "Source and destination are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Transferring with rsync: ${source} -> ${destination}"
    
    local rsync_options=(
        -e "ssh -p ${port} -i ${SSH_NETWORK_SSH_KEY_PATH} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
        -avz
        --timeout="${SSH_NETWORK_CONNECT_TIMEOUT}"
    )
    
    if [[ -n "${options}" ]]; then
        rsync_options+=("${options}")
    fi
    
    rsync "${rsync_options[@]}" "${source}" "${destination}" || {
        errorhandler::throw "${func_name}" "Rsync transfer failed" \
            "${LIB_ERROR_FILE_TRANSFER}"
    }
    
    log::success "Rsync transfer completed"
}

# Synchronize directories
sshnetwork::sync_directories() {
    local func_name="sshnetwork::sync_directories"
    local source_dir="${1:-}"
    local destination_dir="${2:-}"
    local host="${3:-}"
    local user="${4:-$(whoami)}"
    local port="${5:-${SSH_NETWORK_DEFAULT_PORT}}"
    
    if [[ -z "${source_dir}" ]] || [[ -z "${destination_dir}" ]] || [[ -z "${host}" ]]; then
        errorhandler::throw "${func_name}" "Source, destination, and host are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Synchronizing directories: ${source_dir} -> ${host}:${destination_dir}"
    
    local rsync_options=(
        -e "ssh -p ${port} -i ${SSH_NETWORK_SSH_KEY_PATH} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
        -avz
        --delete
        --timeout="${SSH_NETWORK_CONNECT_TIMEOUT}"
    )
    
    rsync "${rsync_options[@]}" "${source_dir}/" "${user}@${host}:${destination_dir}/" || {
        errorhandler::throw "${func_name}" "Directory synchronization failed" \
            "${LIB_ERROR_FILE_TRANSFER}"
    }
    
    log::success "Directory synchronization completed"
}

# Copy SSH public key to remote host
sshnetwork::setup_passwordless_auth() {
    local func_name="sshnetwork::setup_passwordless_auth"
    local host="${1:-}"
    local user="${2:-$(whoami)}"
    local port="${3:-${SSH_NETWORK_DEFAULT_PORT}}"
    
    if [[ -z "${host}" ]]; then
        errorhandler::throw "${func_name}" "Host is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Setting up passwordless authentication for ${user}@${host}"
    
    # Check if we can connect with key first
    if utils::quiet_err ssh -o "PasswordAuthentication=no" -o "BatchMode=yes" -p "${port}" -i "${SSH_NETWORK_SSH_KEY_PATH}" "${user}@${host}" "echo"; then
        log::info "Passwordless authentication already configured"
        return 0
    fi
    
    # Use ssh-copy-id or manual method
    if utils::has ssh-copy-id; then
        ssh-copy-id -p "${port}" -i "${SSH_NETWORK_SSH_PUBLIC_KEY_PATH}" "${user}@${host}" || {
            errorhandler::throw "${func_name}" "Failed to copy SSH key" \
                "${LIB_ERROR_COMMAND_FAILED}"
        }
    else
        # Manual method
        cat "${SSH_NETWORK_SSH_PUBLIC_KEY_PATH}" | ssh -p "${port}" "${user}@${host}" "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && chmod 700 ~/.ssh" || {
            errorhandler::throw "${func_name}" "Failed to copy SSH key manually" \
                "${LIB_ERROR_COMMAND_FAILED}"
        }
    fi
    
    log::success "Passwordless authentication configured"
}

# Execute command on multiple hosts
sshnetwork::execute_batch() {
    local func_name="sshnetwork::execute_batch"
    local hosts=("$@")
    local command=""
    
    # Last argument is the command
    if [[ ${#hosts[@]} -gt 0 ]]; then
        command="${hosts[-1]}"
        hosts=("${hosts[@]:0:${#hosts[@]}-1}")
    fi
    
    if [[ ${#hosts[@]} -eq 0 ]] || [[ -z "${command}" ]]; then
        errorhandler::throw "${func_name}" "At least one host and command are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Executing batch command on ${#hosts[@]} hosts"
    
    local results=()
    local failed_hosts=()
    
    for host_info in "${hosts[@]}"; do
        local host="${host_info%:*}"
        local port="${host_info#*:}"
        if [[ "${port}" == "${host_info}" ]]; then
            port="${SSH_NETWORK_DEFAULT_PORT}"
        fi
        
        log::info "Executing on ${host}:${port}"
        
        local output
        if output=$(sshnetwork::execute_remote "${host}" "${command}" "$(whoami)" "${port}" 2>&1); then
            results+=("${host}: SUCCESS - ${output}")
        else
            results+=("${host}: FAILED - ${output}")
            failed_hosts+=("${host}")
        fi
    done
    
    # Display results
    log::info "Batch execution results:"
    for result in "${results[@]}"; do
        echo "  ${result}"
    done
    
    if [[ ${#failed_hosts[@]} -gt 0 ]]; then
        log::warn "Failed hosts: ${failed_hosts[*]}"
        return "${E_ERROR}"
    fi
    
    return 0
}

# Get system information from remote host
sshnetwork::get_remote_info() {
    local func_name="sshnetwork::get_remote_info"
    local host="${1:-}"
    local user="${2:-$(whoami)}"
    local port="${3:-${SSH_NETWORK_DEFAULT_PORT}}"
    
    if [[ -z "${host}" ]]; then
        errorhandler::throw "${func_name}" "Host is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Getting system information from ${host}"
    
    local commands=(
        'echo "=== Hostname ==="'
        'hostname'
        'echo ""'
        'echo "=== Uptime ==="'
        'uptime'
        'echo ""'
        'echo "=== OS Info ==="'
        'uname -a'
        'echo ""'
        'echo "=== CPU Info ==="'
        'cat /proc/cpuinfo | grep "model name" | head -1'
        'echo ""'
        'echo "=== Memory Info ==="'
        'free -h'
        'echo ""'
        'echo "=== Disk Usage ==="'
        'df -h'
        'echo ""'
        'echo "=== Network Interfaces ==="'
        'ip addr show'
    )
    
    local info
    info=$(sshnetwork::execute_remote "${host}" "$(printf '%s\n' "${commands[@]}")" "${user}" "${port}")
    
    echo "${info}"
}

# Monitor network connectivity
sshnetwork::monitor_network() {
    local func_name="sshnetwork::monitor_network"
    local hosts=("$@")
    local interval="${1:-60}"
    
    if [[ ${#hosts[@]} -eq 0 ]]; then
        # Use discovered devices
        sshnetwork::load_known_devices
        hosts=("${SSH_NETWORK_DISCOVERED_DEVICES[@]}")
    fi
    
    if [[ ${#hosts[@]} -eq 0 ]]; then
        errorhandler::throw "${func_name}" "No hosts to monitor" \
            "${LIB_ERROR_INVALID_STATE}"
    fi
    
    log::info "Starting network monitoring for ${#hosts[@]} hosts (interval: ${interval}s)"
    
    while true; do
        local timestamp
        timestamp=$(utils::log_stamp)
        
        echo "[${timestamp}] Network Status Check"
        
        for host_info in "${hosts[@]}"; do
            local host="${host_info%:*}"
            local port="${host_info#*:}"
            if [[ "${port}" == "${host_info}" ]]; then
                port="${SSH_NETWORK_DEFAULT_PORT}"
            fi
            
            local status="DOWN"
            local response_time="N/A"
            
            if utils::quiet ping -c 1 -W 1 "${host}"; then
                status="UP"
                response_time=$(utils::quiet_err ping -c 1 -W 1 "${host}" | grep "time=" | sed 's/.*time=\([0-9.]*\).*/\1/' || echo "N/A")
            fi
            
            echo "  ${host}:${port} - ${status} (${response_time}ms)"
        done
        
        echo ""
        sleep "${interval}"
    done
}

# Get network topology
sshnetwork::get_topology() {
    local func_name="sshnetwork::get_topology"
    
    log::info "Analyzing network topology..."
    
    local topology_info=()
    
    # Get local network info
    if utils::has ip; then
        topology_info+=("=== Local Network Interfaces ===")
        topology_info+=("$(ip addr show)")
        topology_info+=("")
        
        topology_info+=("=== Routing Table ===")
        topology_info+=("$(ip route show)")
        topology_info+=("")
    fi
    
    # Get ARP table
    if utils::has ip; then
        topology_info+=("=== ARP Table ===")
        topology_info+=("$(ip neigh show)")
    elif utils::has arp; then
        topology_info+=("=== ARP Table ===")
        topology_info+=("$(arp -a)")
    fi
    
    # Display topology
    printf '%s\n' "${topology_info[@]}"
}

# Create SSH tunnel
sshnetwork::create_tunnel() {
    local func_name="sshnetwork::create_tunnel"
    local local_port="${1:-}"
    local remote_host="${2:-}"
    local remote_port="${3:-}"
    local ssh_host="${4:-}"
    local ssh_user="${5:-$(whoami)}"
    local ssh_port="${6:-${SSH_NETWORK_DEFAULT_PORT}}"
    
    if [[ -z "${local_port}" ]] || [[ -z "${remote_host}" ]] || \
       [[ -z "${remote_port}" ]] || [[ -z "${ssh_host}" ]]; then
        errorhandler::throw "${func_name}" "Local port, remote host, remote port, and SSH host are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Creating SSH tunnel: localhost:${local_port} -> ${remote_host}:${remote_port} via ${ssh_host}"
    
    local ssh_options=(
        -o "StrictHostKeyChecking=no"
        -o "UserKnownHostsFile=/dev/null"
        -o "PasswordAuthentication=no"
        -o "ExitOnForwardFailure=yes"
        -p "${ssh_port}"
        -i "${SSH_NETWORK_SSH_KEY_PATH}"
        -L "${local_port}:${remote_host}:${remote_port}"
        -N
        -f
    )
    
    ssh "${ssh_options[@]}" "${ssh_user}@${ssh_host}" || {
        errorhandler::throw "${func_name}" "Failed to create SSH tunnel" \
            "${LIB_ERROR_COMMAND_FAILED}"
    }
    
    log::success "SSH tunnel created: localhost:${local_port} -> ${remote_host}:${remote_port}"
}

# Close SSH tunnel
sshnetwork::close_tunnel() {
    local func_name="sshnetwork::close_tunnel"
    local local_port="${1:-}"
    
    if [[ -z "${local_port}" ]]; then
        errorhandler::throw "${func_name}" "Local port is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Closing SSH tunnel on port ${local_port}"
    
    # Find and kill the SSH process
    local ssh_pid
    ssh_pid=$(ps aux | grep "ssh.*-L.*${local_port}:" | grep -v grep | awk '{print $2}' || true)
    
    if [[ -n "${ssh_pid}" ]]; then
        utils::ignore kill "${ssh_pid}"
        log::success "SSH tunnel closed on port ${local_port}"
    else
        log::warn "No SSH tunnel found on port ${local_port}"
    fi
}

# Get active tunnels
sshnetwork::get_active_tunnels() {
    local func_name="sshnetwork::get_active_tunnels"
    
    log::info "Active SSH tunnels:"
    
    ps aux | grep "ssh.*-L" | grep -v grep | while read -r line; do
        echo "  ${line}"
    done
}

# Log network activity
sshnetwork::log_activity() {
    local func_name="sshnetwork::log_activity"
    local message="${1:-}"
    
    if [[ -z "${message}" ]]; then
        return 0
    fi
    
    local timestamp
    timestamp=$(utils::log_stamp)
    
    io::files::append "${SSH_NETWORK_LOG_FILE}" "[${timestamp}] ${message}"
}

# Get network statistics
sshnetwork::get_network_stats() {
    local func_name="sshnetwork::get_network_stats"
    local host="${1:-}"
    
    if [[ -n "${host}" ]]; then
        log::info "Getting network statistics for ${host}..."
        
        local commands=(
            'echo "=== Network Statistics ==="'
            'cat /proc/net/dev'
            'echo ""'
            'echo "=== Active Connections ==="'
            'ss -tuln'
            'echo ""'
            'echo "=== Network Services ==="'
            'systemctl list-units --type=service --state=running | grep -E "(ssh|network)"'
        )
        
        sshnetwork::execute_remote "${host}" "$(printf '%s\n' "${commands[@]}")"
    else
        # Local statistics
        log::info "Getting local network statistics..."
        
        cat << EOF
SSH Network Statistics:
  Config directory: ${SSH_NETWORK_CONFIG_DIR}
  SSH key path: ${SSH_NETWORK_SSH_KEY_PATH}
  Known devices file: ${SSH_NETWORK_KNOWN_HOSTS_FILE}
  Log file: ${SSH_NETWORK_LOG_FILE}
  Connect timeout: ${SSH_NETWORK_CONNECT_TIMEOUT}s
  Scan timeout: ${SSH_NETWORK_SCAN_TIMEOUT}s
  
Discovered devices: ${#SSH_NETWORK_DISCOVERED_DEVICES[@]}
EOF
        
        if [[ ${#SSH_NETWORK_DISCOVERED_DEVICES[@]} -gt 0 ]]; then
            echo "  Device list:"
            for device in "${SSH_NETWORK_DISCOVERED_DEVICES[@]}"; do
                echo "    - ${device}"
            done
        fi
    fi
}

# Module info
sshnetwork::info() {
    cat << EOF
SSH Network Module v1.0.0

Available functions:
  sshnetwork::init                    - Initialize module
  sshnetwork::discover_devices        - Discover SSH devices in network
  sshnetwork::test_connection         - Test SSH connectivity
  sshnetwork::execute_remote          - Execute command on remote host
  sshnetwork::transfer_file           - Transfer file using scp
  sshnetwork::transfer_file_rsync     - Transfer file using rsync
  sshnetwork::sync_directories        - Synchronize directories
  sshnetwork::setup_passwordless_auth - Setup passwordless SSH authentication
  sshnetwork::execute_batch           - Execute command on multiple hosts
  sshnetwork::get_remote_info         - Get system information from remote
  sshnetwork::monitor_network         - Monitor network connectivity
  sshnetwork::get_topology            - Get network topology information
  sshnetwork::create_tunnel           - Create SSH tunnel
  sshnetwork::close_tunnel            - Close SSH tunnel
  sshnetwork::get_active_tunnels      - List active SSH tunnels
  sshnetwork::get_network_stats       - Get network statistics
  sshnetwork::load_known_devices      - Load known devices from file

Configuration:
  Config directory: ${SSH_NETWORK_CONFIG_DIR}
  SSH key path: ${SSH_NETWORK_SSH_KEY_PATH}
  Connect timeout: ${SSH_NETWORK_CONNECT_TIMEOUT}s
  Scan timeout: ${SSH_NETWORK_SCAN_TIMEOUT}s
  Default SSH port: ${SSH_NETWORK_DEFAULT_PORT}
  BS SSH port: ${SSH_NETWORK_BASH_PORT}

Dependencies:
  openssh-client, rsync, nmap, iputils-ping
EOF
}
