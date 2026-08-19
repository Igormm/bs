#!/usr/bin/env bs
# shellcheck shell=bash
# shellcheck disable=SC2155

# systemaudit.sh — Linux System Audit Module for BS Framework
# Модуль аудита системы Linux для фреймворка BS
#
# Description:
#   Comprehensive system auditing and security analysis for Linux systems.
#   Performs security checks, compliance validation, and system analysis.
#
# Features:
#   - Security vulnerability scanning
#   - System configuration analysis
#   - User and permission auditing
#   - Network security assessment
#   - File integrity checking
#   - Compliance reporting
#   - Automated remediation suggestions
#
# @author BS Framework
# @since 2026-01-06
# @version 1.0.0
# @depends core/const, core/logger, core/utils, core/errorhandler, lib/system/platformcheck, lib/system/processes

# Source Guard / Защита от повторной загрузки
bs::guard "AUDIT_SYSTEM" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "../../core/errorhandler.sh" "../system/platformcheck.sh" "../system/processes.sh"

# Audit configuration
readonly AUDIT_CONFIG_DIR="${HOME}/.config/systemaudit"
readonly AUDIT_REPORT_DIR="${AUDIT_CONFIG_DIR}/reports"
readonly AUDIT_CACHE_DIR="/tmp/system_audit_cache"
readonly AUDIT_BASELINE_FILE="${AUDIT_CONFIG_DIR}/baseline.json"

# Audit severity levels
readonly AUDIT_SEVERITY_CRITICAL="CRITICAL"
readonly AUDIT_SEVERITY_HIGH="HIGH"
readonly AUDIT_SEVERITY_MEDIUM="MEDIUM"
readonly AUDIT_SEVERITY_LOW="LOW"
readonly AUDIT_SEVERITY_INFO="INFO"

# Module state
AUDIT_FINDINGS=()
AUDIT_SCORE=100
AUDIT_SUMMARY=""

# Module initialization
systemaudit::init() {
    local func_name="systemaudit::init"
    
    log::info "Initializing System Audit module..."
    
    # Create necessary directories
    mkdir -p "${AUDIT_CONFIG_DIR}" || {
        errorhandler::throw "${func_name}" "Failed to create config directory" \
            "${LIB_ERROR_FILE_OPERATION}"
    }
    
    mkdir -p "${AUDIT_REPORT_DIR}" || {
        errorhandler::throw "${func_name}" "Failed to create report directory" \
            "${LIB_ERROR_FILE_OPERATION}"
    }
    
    mkdir -p "${AUDIT_CACHE_DIR}" || {
        errorhandler::throw "${func_name}" "Failed to create cache directory" \
            "${LIB_ERROR_FILE_OPERATION}"
    }
    
    # Check dependencies
    systemaudit::check_dependencies
    
    # Initialize audit components
    systemaudit::init_components
    
    log::success "System Audit module initialized successfully"
}

# Check dependencies
systemaudit::check_dependencies() {
    local func_name="systemaudit::check_dependencies"
    local missing_deps=()
    
    log::debug "Checking System Audit dependencies..."

    deps::missing_tools missing_deps \
        uname:coreutils ps:procps netstat|ss:"net-tools iproute2" lsof find:findutils awk:gawk sed
    
    # Install missing dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log::warn "Missing dependencies: ${missing_deps[*]}"
        systemaudit::install_dependencies "${missing_deps[@]}"
    else
        log::debug "All dependencies are installed"
    fi
}

# Install dependencies
systemaudit::install_dependencies() {
    local func_name="systemaudit::install_dependencies"
    local deps=("$@")
    
    log::info "Installing missing dependencies: ${deps[*]}..."
    
    if platformcheck::is_debian || platformcheck::is_ubuntu; then
        apt-get update
        apt-get install -y coreutils procps net-tools iproute2 lsof findutils gawk sed
    elif platformcheck::is_alma || platformcheck::is_fedora; then
        dnf install -y coreutils procps net-tools iproute lsof findutils gawk sed
    elif platformcheck::is_macos; then
        if ! utils::has brew; then
            errorhandler::throw "${func_name}" "Homebrew is required for macOS" \
                "${LIB_ERROR_DEPENDENCY_MISSING}"
        fi
        brew install coreutils findutils gnu-sed gawk
    else
        errorhandler::throw "${func_name}" "Unsupported platform for dependency installation" \
            "${LIB_ERROR_PLATFORM_UNSUPPORTED}"
    fi
    
    log::success "Dependencies installed successfully"
}

# Initialize audit components
systemaudit::init_components() {
    local func_name="systemaudit::init_components"
    
    log::debug "Initializing audit components..."
    
    # Initialize each audit category
    systemaudit::security::init
    systemaudit::users::init
    systemaudit::network::init
    systemaudit::filesystem::init
    systemaudit::services::init
    systemaudit::compliance::init
    
    log::debug "All audit components initialized"
}

# ============================================================================
# MAIN AUDIT FUNCTION
# Основная функция аудита
# ============================================================================

# Run comprehensive system audit
systemaudit::run() {
    local func_name="systemaudit::run"
    local audit_type="${1:-full}"
    local output_format="${2:-text}"
    
    log::info "Starting system audit (type: ${audit_type}, format: ${output_format})..."
    
    # Reset findings
    AUDIT_FINDINGS=()
    AUDIT_SCORE=100
    
    # Run audit based on type
    case "${audit_type}" in
        security)
            systemaudit::security::run
            ;;
        users)
            systemaudit::users::run
            ;;
        network)
            systemaudit::network::run
            ;;
        filesystem)
            systemaudit::filesystem::run
            ;;
        services)
            systemaudit::services::run
            ;;
        compliance)
            systemaudit::compliance::run
            ;;
        quick)
            systemaudit::run_quick
            ;;
        full)
            systemaudit::run_full
            ;;
        *)
            errorhandler::throw "${func_name}" "Unknown audit type: ${audit_type}" \
                "${LIB_ERROR_INVALID_ARGS}"
            ;;
    esac
    
    # Generate report
    systemaudit::generate_report "${output_format}"
    
    log::info "System audit completed. Score: ${AUDIT_SCORE}/100"
}

# Run quick audit
systemaudit::run_quick() {
    log::info "Running quick security audit..."
    
    systemaudit::security::check_root_login
    systemaudit::security::check_password_policy
    systemaudit::users::check_sudo_users
    systemaudit::network::check_open_ports
    systemaudit::filesystem::check_world_writable
    
    systemaudit::calculate_score
}

# Run full comprehensive audit
systemaudit::run_full() {
    log::info "Running full comprehensive audit..."
    
    # Run all audit categories
    systemaudit::security::run
    systemaudit::users::run
    systemaudit::network::run
    systemaudit::filesystem::run
    systemaudit::services::run
    systemaudit::compliance::run
    
    systemaudit::calculate_score
}

# ============================================================================
# SECURITY AUDIT
# Аудит безопасности
# ============================================================================

systemaudit::security::init() {
    # Security audit specific initialization
    return 0
}

systemaudit::security::run() {
    log::info "Running security audit..."
    
    systemaudit::security::check_root_login
    systemaudit::security::check_password_policy
    systemaudit::security::check_ssh_config
    systemaudit::security::check_firewall_status
    systemaudit::security::check_selinux_apparmor
    systemaudit::security::check_kernel_parameters
    systemaudit::security::check_suid_files
    systemaudit::security::check_world_writable_dirs
    systemaudit::security::check_processes
}

# Check root login configuration
systemaudit::security::check_root_login() {
    local finding=""
    
    if [[ -f /etc/ssh/sshd_config ]]; then
        if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config; then
            finding=$(systemaudit::create_finding \
                "Root login enabled via SSH" \
                "Root login should be disabled for security" \
                "${AUDIT_SEVERITY_HIGH}" \
                "security" \
                "Set PermitRootLogin no in /etc/ssh/sshd_config")
            AUDIT_FINDINGS+=("${finding}")
        fi
    fi
}

# Check password policy
systemaudit::security::check_password_policy() {
    local finding=""
    
    # Check password expiration
    if [[ -f /etc/login.defs ]]; then
        local pass_max_days
        pass_max_days=$(grep "^PASS_MAX_DAYS" /etc/login.defs | awk '{print $2}' || echo "99999")
        
        if [[ "${pass_max_days}" -gt 365 ]]; then
            finding=$(systemaudit::create_finding \
                "Password expiration too long" \
                "Passwords should expire within 365 days" \
                "${AUDIT_SEVERITY_MEDIUM}" \
                "security" \
                "Set PASS_MAX_DAYS to 365 or less in /etc/login.defs")
            AUDIT_FINDINGS+=("${finding}")
        fi
    fi
}

# Check SSH configuration
systemaudit::security::check_ssh_config() {
    local finding=""
    
    if [[ -f /etc/ssh/sshd_config ]]; then
        # Check for protocol version
        if ! grep -q "^Protocol 2" /etc/ssh/sshd_config; then
            finding=$(systemaudit::create_finding \
                "SSH Protocol 1 may be enabled" \
                "Only SSH Protocol 2 should be used" \
                "${AUDIT_SEVERITY_HIGH}" \
                "security" \
                "Set Protocol 2 in /etc/ssh/sshd_config")
            AUDIT_FINDINGS+=("${finding}")
        fi
        
        # Check for empty passwords
        if grep -q "^PermitEmptyPasswords yes" /etc/ssh/sshd_config; then
            finding=$(systemaudit::create_finding \
                "Empty passwords allowed via SSH" \
                "Empty passwords should be disabled" \
                "${AUDIT_SEVERITY_CRITICAL}" \
                "security" \
                "Set PermitEmptyPasswords no in /etc/ssh/sshd_config")
            AUDIT_FINDINGS+=("${finding}")
        fi
    fi
}

# Check firewall status
systemaudit::security::check_firewall_status() {
    local finding=""
    local firewall_active=false
    
    # Check UFW (Ubuntu/Debian)
    if utils::has ufw; then
        if ufw status | grep -q "Status: active"; then
            firewall_active=true
        fi
    fi
    
    # Check firewalld (RHEL/CentOS/Fedora)
    if utils::has firewall-cmd; then
        if utils::quiet_err firewall-cmd --state | grep -q "running"; then
            firewall_active=true
        fi
    fi
    
    # Check iptables
    if utils::has iptables; then
        if utils::quiet_err iptables -L | grep -q "ACCEPT\|DROP\|REJECT"; then
            firewall_active=true
        fi
    fi
    
    if [[ "${firewall_active}" == "false" ]]; then
        finding=$(systemaudit::create_finding \
            "No firewall detected" \
            "System should have a firewall enabled" \
            "${AUDIT_SEVERITY_HIGH}" \
            "security" \
            "Enable UFW, firewalld, or configure iptables")
        AUDIT_FINDINGS+=("${finding}")
    fi
}

# Check SELinux/AppArmor status
systemaudit::security::check_selinux_apparmor() {
    local finding=""
    
    # Check SELinux
    if utils::has getenforce; then
        local selinux_status
        selinux_status=$(utils::quiet_err getenforce || echo "Disabled")
        
        if [[ "${selinux_status}" == "Disabled" ]]; then
            finding=$(systemaudit::create_finding \
                "SELinux is disabled" \
                "SELinux provides mandatory access control" \
                "${AUDIT_SEVERITY_MEDIUM}" \
                "security" \
                "Enable SELinux for enhanced security")
            AUDIT_FINDINGS+=("${finding}")
        fi
    fi
    
    # Check AppArmor
    if utils::has aa-status; then
        if ! utils::quiet_err aa-status | grep -q "profiles are loaded"; then
            finding=$(systemaudit::create_finding \
                "AppArmor is not active" \
                "AppArmor provides application confinement" \
                "${AUDIT_SEVERITY_MEDIUM}" \
                "security" \
                "Enable AppArmor for enhanced security")
            AUDIT_FINDINGS+=("${finding}")
        fi
    fi
}

# Check kernel parameters
systemaudit::security::check_kernel_parameters() {
    local finding=""
    
    # Check IP forwarding
    if [[ -f /proc/sys/net/ipv4/ip_forward ]]; then
        local ip_forward
        ip_forward=$(cat /proc/sys/net/ipv4/ip_forward)
        
        if [[ "${ip_forward}" == "1" ]]; then
            finding=$(systemaudit::create_finding \
                "IP forwarding is enabled" \
                "IP forwarding should be disabled unless needed" \
                "${AUDIT_SEVERITY_LOW}" \
                "security" \
                "Set net.ipv4.ip_forward = 0 in /etc/sysctl.conf")
            AUDIT_FINDINGS+=("${finding}")
        fi
    fi
}

# Check SUID files
systemaudit::security::check_suid_files() {
    local finding=""
    
    # Find SUID files
    local suid_files
    suid_files=$(utils::quiet_err find / -type f -perm -4000 | head -20)
    
    local suid_count
    suid_count=$(echo "${suid_files}" | wc -l)
    
    if [[ "${suid_count}" -gt 10 ]]; then
        finding=$(systemaudit::create_finding \
            "High number of SUID files found: ${suid_count}" \
            "SUID files can be security risks" \
            "${AUDIT_SEVERITY_MEDIUM}" \
            "security" \
            "Review and remove unnecessary SUID permissions")
        AUDIT_FINDINGS+=("${finding}")
    fi
}

# Check world-writable directories
systemaudit::security::check_world_writable_dirs() {
    local finding=""
    
    # Find world-writable directories
    local world_writable
    world_writable=$(utils::quiet_err find / -type d -perm -o+w | grep -v "/proc\|/sys\|/tmp" | head -10)
    
    if [[ -n "${world_writable}" ]]; then
        finding=$(systemaudit::create_finding \
            "World-writable directories found" \
            "World-writable directories can be security risks" \
            "${AUDIT_SEVERITY_MEDIUM}" \
            "security" \
            "Review and fix permissions on world-writable directories")
        AUDIT_FINDINGS+=("${finding}")
    fi
}

# Check running processes
systemaudit::security::check_processes() {
    local finding=""
    
    # Check for processes running as root that shouldn't be
    local suspicious_processes
    suspicious_processes=$(ps aux | grep -E "(nc|netcat|python.*-m.*http)" | grep -v grep)
    
    if [[ -n "${suspicious_processes}" ]]; then
        finding=$(systemaudit::create_finding \
            "Potentially suspicious processes detected" \
            "Some processes may indicate compromise" \
            "${AUDIT_SEVERITY_HIGH}" \
            "security" \
            "Review running processes and investigate suspicious activity")
        AUDIT_FINDINGS+=("${finding}")
    fi
}

# ============================================================================
# USERS AUDIT
# Аудит пользователей
# ============================================================================

systemaudit::users::init() {
    # Users audit specific initialization
    return 0
}

systemaudit::users::run() {
    log::info "Running users audit..."
    
    systemaudit::users::check_sudo_users
    systemaudit::users::check_passwordless_sudo
    systemaudit::users::check_locked_accounts
    systemaudit::users::check_uid_zero
    systemaudit::users::check_home_permissions
}

# Check sudo users
systemaudit::users::check_sudo_users() {
    local finding=""
    
    # Get sudo users
    local sudo_users
    sudo_users=$(getent group sudo | cut -d: -f4 || echo "")
    
    if [[ -n "${sudo_users}" ]]; then
        local user_count
        user_count=$(echo "${sudo_users}" | tr ',' '\n' | wc -l)
        
        if [[ "${user_count}" -gt 5 ]]; then
            finding=$(systemaudit::create_finding \
                "High number of sudo users: ${user_count}" \
                "Too many users with sudo privileges" \
                "${AUDIT_SEVERITY_MEDIUM}" \
                "users" \
                "Review sudo group membership")
            AUDIT_FINDINGS+=("${finding}")
        fi
    fi
}

# Check passwordless sudo
systemaudit::users::check_passwordless_sudo() {
    local finding=""
    
    if [[ -f /etc/sudoers ]]; then
        if grep -q "NOPASSWD" /etc/sudoers; then
            finding=$(systemaudit::create_finding \
                "Passwordless sudo configuration found" \
                "Passwordless sudo reduces security" \
                "${AUDIT_SEVERITY_MEDIUM}" \
                "users" \
                "Review sudoers file and remove NOPASSWD")
            AUDIT_FINDINGS+=("${finding}")
        fi
    fi
}

# Check locked accounts
systemaudit::users::check_locked_accounts() {
    local finding=""
    
    # Check for accounts with empty passwords
    local empty_passwords
    empty_passwords=$(utils::quiet_err awk -F: '($2 == "" ) {print $1}' /etc/shadow || true)
    
    if [[ -n "${empty_passwords}" ]]; then
        finding=$(systemaudit::create_finding \
            "Accounts with empty passwords found" \
            "Empty passwords are security risks" \
            "${AUDIT_SEVERITY_CRITICAL}" \
            "users" \
            "Set passwords for all accounts")
        AUDIT_FINDINGS+=("${finding}")
    fi
}

# Check UID 0 accounts
systemaudit::users::check_uid_zero() {
    local finding=""
    
    local uid_zero
    uid_zero=$(awk -F: '($3 == 0) {print $1}' /etc/passwd | grep -v root || true)
    
    if [[ -n "${uid_zero}" ]]; then
        finding=$(systemaudit::create_finding \
            "Additional UID 0 accounts found: ${uid_zero}" \
            "Only root should have UID 0" \
            "${AUDIT_SEVERITY_CRITICAL}" \
            "users" \
            "Remove or fix UID 0 accounts")
        AUDIT_FINDINGS+=("${finding}")
    fi
}

# Check home directory permissions
systemaudit::users::check_home_permissions() {
    local finding=""
    
    # Check for world-readable home directories
    local world_readable_homes
    world_readable_homes=$(utils::quiet_err find /home -type d -perm -o+r | head -10)
    
    if [[ -n "${world_readable_homes}" ]]; then
        finding=$(systemaudit::create_finding \
            "World-readable home directories found" \
            "Home directories should not be world-readable" \
            "${AUDIT_SEVERITY_MEDIUM}" \
            "users" \
            "Fix home directory permissions")
        AUDIT_FINDINGS+=("${finding}")
    fi
}

# ============================================================================
# NETWORK AUDIT
# Аудит сети
# ============================================================================

systemaudit::network::init() {
    # Network audit specific initialization
    return 0
}

systemaudit::network::run() {
    log::info "Running network audit..."
    
    systemaudit::network::check_open_ports
    systemaudit::network::check_listening_services
    systemaudit::network::check_ip_forwarding
    systemaudit::network::check_icmp_redirects
}

# Check open ports
systemaudit::network::check_open_ports() {
    local finding=""
    
    # Get listening ports
    local listening_ports
    if utils::has ss; then
        listening_ports=$(ss -tuln | grep LISTEN | wc -l)
    elif utils::has netstat; then
        listening_ports=$(netstat -tuln | grep LISTEN | wc -l)
    else
        listening_ports=0
    fi
    
    if [[ "${listening_ports}" -gt 20 ]]; then
        finding=$(systemaudit::create_finding \
            "High number of listening ports: ${listening_ports}" \
            "Too many open ports increase attack surface" \
            "${AUDIT_SEVERITY_LOW}" \
            "network" \
            "Review and close unnecessary ports")
        AUDIT_FINDINGS+=("${finding}")
    fi
    
    # Check for insecure services
    local insecure_ports
    if utils::has ss; then
        insecure_ports=$(ss -tuln | grep -E ":23|:21|:135|:139|:445" | wc -l)
    elif utils::has netstat; then
        insecure_ports=$(netstat -tuln | grep -E ":23|:21|:135|:139|:445" | wc -l)
    else
        insecure_ports=0
    fi
    
    if [[ "${insecure_ports}" -gt 0 ]]; then
        finding=$(systemaudit::create_finding \
            "Insecure services detected on network ports" \
            "Telnet, FTP, and SMB services are insecure" \
            "${AUDIT_SEVERITY_HIGH}" \
            "network" \
            "Disable insecure services")
        AUDIT_FINDINGS+=("${finding}")
    fi
}

# Check listening services
systemaudit::network::check_listening_services() {
    local finding=""
    
    # Check for services that shouldn't be exposed
    local exposed_services
    if utils::has ss; then
        exposed_services=$(ss -tuln | grep -E "0.0.0.0|:::" | wc -l)
    elif utils::has netstat; then
        exposed_services=$(netstat -tuln | grep -E "0.0.0.0|:::" | wc -l)
    else
        exposed_services=0
    fi
    
    if [[ "${exposed_services}" -gt 10 ]]; then
        finding=$(systemaudit::create_finding \
            "Many services exposed to all interfaces" \
            "Services should bind to specific interfaces when possible" \
            "${AUDIT_SEVERITY_MEDIUM}" \
            "network" \
            "Configure services to bind to specific interfaces")
        AUDIT_FINDINGS+=("${finding}")
    fi
}

# Check IP forwarding
systemaudit::network::check_ip_forwarding() {
    local finding=""
    
    # This is already checked in security audit, but let's verify again
    if [[ -f /proc/sys/net/ipv4/ip_forward ]]; then
        local ip_forward
        ip_forward=$(cat /proc/sys/net/ipv4/ip_forward)
        
        if [[ "${ip_forward}" == "1" ]]; then
            finding=$(systemaudit::create_finding \
                "IPv4 forwarding is enabled" \
                "May indicate router configuration or security issue" \
                "${AUDIT_SEVERITY_LOW}" \
                "network" \
                "Disable if not needed: echo 0 > /proc/sys/net/ipv4/ip_forward")
            AUDIT_FINDINGS+=("${finding}")
        fi
    fi
}

# Check ICMP redirects
systemaudit::network::check_icmp_redirects() {
    local finding=""
    
    # Check for ICMP redirect acceptance
    if [[ -f /proc/sys/net/ipv4/conf/all/accept_redirects ]]; then
        local icmp_redirects
        icmp_redirects=$(cat /proc/sys/net/ipv4/conf/all/accept_redirects)
        
        if [[ "${icmp_redirects}" == "1" ]]; then
            finding=$(systemaudit::create_finding \
                "ICMP redirects are enabled" \
                "ICMP redirects can be used for MITM attacks" \
                "${AUDIT_SEVERITY_MEDIUM}" \
                "network" \
                "Disable ICMP redirects in sysctl.conf")
            AUDIT_FINDINGS+=("${finding}")
        fi
    fi
}

# ============================================================================
# FILESYSTEM AUDIT
# Аудит файловой системы
# ============================================================================

systemaudit::filesystem::init() {
    # Filesystem audit specific initialization
    return 0
}

systemaudit::filesystem::run() {
    log::info "Running filesystem audit..."
    
    systemaudit::filesystem::check_world_writable
    systemaudit::filesystem::check_suid_files
    systemaudit::filesystem::check_sticky_bits
    systemaudit::filesystem::check_dot_files
}

# Check world-writable files
systemaudit::filesystem::check_world_writable() {
    local finding=""
    
    # Find world-writable files (excluding /proc, /sys, /tmp)
    local world_writable_files
    world_writable_files=$(utils::quiet_err find / -type f -perm -o+w | \
        grep -v "/proc\|/sys\|/tmp\|/dev/shm" | head -20)
    
    if [[ -n "${world_writable_files}" ]]; then
        finding=$(systemaudit::create_finding \
            "World-writable files found" \
            "World-writable files can be modified by any user" \
            "${AUDIT_SEVERITY_MEDIUM}" \
            "filesystem" \
            "Review and fix permissions on world-writable files")
        AUDIT_FINDINGS+=("${finding}")
    fi
}

# Check SUID files (already done in security, but more detailed here)
systemaudit::filesystem::check_suid_files() {
    local finding=""
    
    # Get detailed SUID file information
    local suid_files
    suid_files=$(utils::quiet_err find / -type f -perm -4000 -ls | head -10)
    
    if [[ -n "${suid_files}" ]]; then
        # This is informational - SUID files are normal but should be monitored
        finding=$(systemaudit::create_finding \
            "SUID files present in system" \
            "SUID files allow elevated privilege execution" \
            "${AUDIT_SEVERITY_INFO}" \
            "filesystem" \
            "Regularly audit SUID files for changes")
        AUDIT_FINDINGS+=("${finding}")
    fi
}

# Check sticky bits
systemaudit::filesystem::check_sticky_bits() {
    local finding=""
    
    # Check for directories without sticky bit that should have it
    local public_dirs=("/tmp" "/var/tmp")
    
    for dir in "${public_dirs[@]}"; do
        if [[ -d "${dir}" ]]; then
            local perms
            perms=$(utils::quiet_err stat -c %a "${dir}" || echo "000")
            
            if [[ "${perms}" != "17""${perms#???}" ]]; then
                finding=$(systemaudit::create_finding \
                    "Directory ${dir} missing sticky bit" \
                    "Sticky bit prevents users from deleting others' files" \
                    "${AUDIT_SEVERITY_HIGH}" \
                    "filesystem" \
                    "Set sticky bit: chmod +t ${dir}")
                AUDIT_FINDINGS+=("${finding}")
            fi
        fi
    done
}

# Check dot files in home directories
systemaudit::filesystem::check_dot_files() {
    local finding=""
    
    # Check for .rhosts and .netrc files
    local dot_files
    dot_files=$(utils::quiet_err find /home -name ".rhosts" -o -name ".netrc")
    
    if [[ -n "${dot_files}" ]]; then
        finding=$(systemaudit::create_finding \
            "Legacy authentication files found" \
            ".rhosts and .netrc files are insecure" \
            "${AUDIT_SEVERITY_HIGH}" \
            "filesystem" \
            "Remove .rhosts and .netrc files")
        AUDIT_FINDINGS+=("${finding}")
    fi
}

# ============================================================================
# SERVICES AUDIT
# Аудит служб
# ============================================================================

systemaudit::services::init() {
    # Services audit specific initialization
    return 0
}

systemaudit::services::run() {
    log::info "Running services audit..."
    
    systemaudit::services::check_running_services
    systemaudit::services::check_inetd_services
    systemaudit::services::check_service_permissions
}

# Check running services
systemaudit::services::check_running_services() {
    local finding=""
    
    # Check for unnecessary services
    local unnecessary_services=("telnet" "ftp" "rsh" "rlogin" "rexec")
    
    for service in "${unnecessary_services[@]}"; do
        if system::processes::is_running "${service}"; then
            finding=$(systemaudit::create_finding \
                "Unnecessary service running: ${service}" \
                "Legacy services are insecure" \
                "${AUDIT_SEVERITY_HIGH}" \
                "services" \
                "Disable and remove ${service} service")
            AUDIT_FINDINGS+=("${finding}")
        fi
    done
}

# Check inetd services
systemaudit::services::check_inetd_services() {
    local finding=""
    
    # Check for inetd configuration
    if [[ -f /etc/inetd.conf ]]; then
        local active_services
        active_services=$(grep -v "^#" /etc/inetd.conf | grep -v "^$" | wc -l)
        
        if [[ "${active_services}" -gt 0 ]]; then
            finding=$(systemaudit::create_finding \
                "Inetd services configured" \
                "Inetd services are legacy and insecure" \
                "${AUDIT_SEVERITY_MEDIUM}" \
                "services" \
                "Disable inetd services")
            AUDIT_FINDINGS+=("${finding}")
        fi
    fi
}

# Check service permissions
systemaudit::services::check_service_permissions() {
    local finding=""
    
    # Check systemd service files
    if [[ -d /etc/systemd/system ]]; then
        local world_writable_services
        world_writable_services=$(utils::quiet_err find /etc/systemd/system -type f -perm -o+w)
        
        if [[ -n "${world_writable_services}" ]]; then
            finding=$(systemaudit::create_finding \
                "World-writable service files found" \
                "Service files should not be world-writable" \
                "${AUDIT_SEVERITY_HIGH}" \
                "services" \
                "Fix service file permissions")
            AUDIT_FINDINGS+=("${finding}")
        fi
    fi
}

# ============================================================================
# COMPLIANCE AUDIT
# Аудит соответствия
# ============================================================================

systemaudit::compliance::init() {
    # Compliance audit specific initialization
    return 0
}

systemaudit::compliance::run() {
    log::info "Running compliance audit..."
    
    systemaudit::compliance::check_password_complexity
    systemaudit::compliance::check_audit_logging
    systemaudit::compliance::check_updates
    systemaudit::compliance::check_cis_benchmarks
}

# Check password complexity
systemaudit::compliance::check_password_complexity() {
    local finding=""
    
    if [[ -f /etc/security/pwquality.conf ]]; then
        local minlen
        minlen=$(grep "^minlen" /etc/security/pwquality.conf | awk '{print $3}' || echo "0")
        
        if [[ "${minlen}" -lt 8 ]]; then
            finding=$(systemaudit::create_finding \
                "Password minimum length too short: ${minlen}" \
                "Passwords should be at least 8 characters" \
                "${AUDIT_SEVERITY_MEDIUM}" \
                "compliance" \
                "Set minlen = 8 in /etc/security/pwquality.conf")
            AUDIT_FINDINGS+=("${finding}")
        fi
    fi
}

# Check audit logging
systemaudit::compliance::check_audit_logging() {
    local finding=""
    
    # Check if auditd is running
    if ! system::processes::is_running auditd; then
        finding=$(systemaudit::create_finding \
            "Audit daemon not running" \
            "Audit logging is required for security compliance" \
            "${AUDIT_SEVERITY_HIGH}" \
            "compliance" \
            "Start auditd service: systemctl start auditd")
        AUDIT_FINDINGS+=("${finding}")
    fi
}

# Check system updates
systemaudit::compliance::check_updates() {
    local finding=""
    
    # This is a basic check - in production, you'd want more sophisticated update checking
    local last_update
    last_update=$(utils::quiet_err stat -c %Y /var/cache/apt/pkgcache.bin || echo "0")
    local current_time
    current_time=$(utils::now_s)
    local days_since_update
    days_since_update=$(( (current_time - last_update) / 86400 ))
    
    if [[ "${days_since_update}" -gt 30 ]]; then
        finding=$(systemaudit::create_finding \
            "System packages not updated in ${days_since_update} days" \
            "Regular updates are required for security" \
            "${AUDIT_SEVERITY_HIGH}" \
            "compliance" \
            "Run system updates")
        AUDIT_FINDINGS+=("${finding}")
    fi
}

# Check CIS benchmarks (simplified)
systemaudit::compliance::check_cis_benchmarks() {
    local finding=""
    
    # Check for prelink
    if utils::has prelink; then
        finding=$(systemaudit::create_finding \
            "Prelink is installed" \
            "Prelink can interfere with security features" \
            "${AUDIT_SEVERITY_MEDIUM}" \
            "compliance" \
            "Remove prelink: apt-get remove prelink")
        AUDIT_FINDINGS+=("${finding}")
    fi
    
    # Check for unnecessary compilers
    if utils::has gcc; then
        finding=$(systemaudit::create_finding \
            "Compiler tools are installed" \
            "Compilers should not be on production systems" \
            "${AUDIT_SEVERITY_LOW}" \
            "compliance" \
            "Remove compiler tools from production systems")
        AUDIT_FINDINGS+=("${finding}")
    fi
}

# ============================================================================
# UTILITY FUNCTIONS
# Вспомогательные функции
# ============================================================================

# Create audit finding
systemaudit::create_finding() {
    local title="${1:-}"
    local description="${2:-}"
    local severity="${3:-${AUDIT_SEVERITY_INFO}}"
    local category="${4:-general}"
    local recommendation="${5:-}"
    local timestamp="$(utils::log_stamp)"
    
    local finding="{"
    finding="${finding} \"timestamp\": \"${timestamp}\","
    finding="${finding} \"title\": \"${title}\","
    finding="${finding} \"description\": \"${description}\","
    finding="${finding} \"severity\": \"${severity}\","
    finding="${finding} \"category\": \"${category}\","
    finding="${finding} \"recommendation\": \"${recommendation}\""
    finding="${finding} }"
    
    echo "${finding}"
}

# Calculate audit score
systemaudit::calculate_score() {
    local func_name="systemaudit::calculate_score"
    
    local initial_score=100
    local deductions=0
    
    for finding_json in "${AUDIT_FINDINGS[@]}"; do
        local severity
        severity=$(echo "${finding_json}" | sed 's/.*"severity": "\([^"]*\)".*/\1/')
        
        case "${severity}" in
            "${AUDIT_SEVERITY_CRITICAL}")
                deductions=$((deductions + 25))
                ;;
            "${AUDIT_SEVERITY_HIGH}")
                deductions=$((deductions + 15))
                ;;
            "${AUDIT_SEVERITY_MEDIUM}")
                deductions=$((deductions + 5))
                ;;
            "${AUDIT_SEVERITY_LOW}")
                deductions=$((deductions + 2))
                ;;
            *)
                deductions=$((deductions + 1))
                ;;
        esac
    done
    
    AUDIT_SCORE=$((initial_score - deductions))
    
    if [[ "${AUDIT_SCORE}" -lt 0 ]]; then
        AUDIT_SCORE=0
    fi
    
    # Generate summary
    if [[ "${AUDIT_SCORE}" -ge 90 ]]; then
        AUDIT_SUMMARY="Excellent security posture"
    elif [[ "${AUDIT_SCORE}" -ge 80 ]]; then
        AUDIT_SUMMARY="Good security posture with minor issues"
    elif [[ "${AUDIT_SCORE}" -ge 70 ]]; then
        AUDIT_SUMMARY="Acceptable security posture with some concerns"
    elif [[ "${AUDIT_SCORE}" -ge 60 ]]; then
        AUDIT_SUMMARY="Poor security posture requiring attention"
    else
        AUDIT_SUMMARY="Critical security issues requiring immediate action"
    fi
}

# Generate audit report
systemaudit::generate_report() {
    local func_name="systemaudit::generate_report"
    local format="${1:-text}"
    local timestamp="$(date '+%Y%m%d_%H%M%S')"
    local report_file="${AUDIT_REPORT_DIR}/audit_${timestamp}.${format}"
    
    case "${format}" in
        json)
            systemaudit::generate_json_report "${report_file}"
            ;;
        csv)
            systemaudit::generate_csv_report "${report_file}"
            ;;
        xml)
            systemaudit::generate_xml_report "${report_file}"
            ;;
        *)
            systemaudit::generate_text_report "${report_file}"
            ;;
    esac
    
    log::info "Audit report generated: ${report_file}"
}

# Generate text report
systemaudit::generate_text_report() {
    local report_file="${1:-}"
    
    {
        echo "================================================================================"
        echo "SYSTEM AUDIT REPORT"
        echo "Generated: $(date)"
        echo "================================================================================"
        echo ""
        echo "SUMMARY:"
        echo "  Score: ${AUDIT_SCORE}/100"
        echo "  Assessment: ${AUDIT_SUMMARY}"
        echo "  Total Findings: ${#AUDIT_FINDINGS[@]}"
        echo ""
        echo "FINDINGS BY SEVERITY:"
        
        # Count by severity
        local critical_count=0
        local high_count=0
        local medium_count=0
        local low_count=0
        local info_count=0
        
        for finding_json in "${AUDIT_FINDINGS[@]}"; do
            local severity
            severity=$(echo "${finding_json}" | sed 's/.*"severity": "\([^"]*\)".*/\1/')
            
            case "${severity}" in
                "${AUDIT_SEVERITY_CRITICAL}")
                    ((critical_count++))
                    ;;
                "${AUDIT_SEVERITY_HIGH}")
                    ((high_count++))
                    ;;
                "${AUDIT_SEVERITY_MEDIUM}")
                    ((medium_count++))
                    ;;
                "${AUDIT_SEVERITY_LOW}")
                    ((low_count++))
                    ;;
                *)
                    ((info_count++))
                    ;;
            esac
        done
        
        echo "  Critical: ${critical_count}"
        echo "  High: ${high_count}"
        echo "  Medium: ${medium_count}"
        echo "  Low: ${low_count}"
        echo "  Info: ${info_count}"
        echo ""
        echo "DETAILED FINDINGS:"
        echo "================================================================================"
        
        local index=1
        for finding_json in "${AUDIT_FINDINGS[@]}"; do
            echo "Finding ${index}:"
            echo "  Title: $(echo "${finding_json}" | sed 's/.*"title": "\([^"]*\)".*/\1/')"
            echo "  Severity: $(echo "${finding_json}" | sed 's/.*"severity": "\([^"]*\)".*/\1/')"
            echo "  Category: $(echo "${finding_json}" | sed 's/.*"category": "\([^"]*\)".*/\1/')"
            echo "  Description: $(echo "${finding_json}" | sed 's/.*"description": "\([^"]*\)".*/\1/')"
            echo "  Recommendation: $(echo "${finding_json}" | sed 's/.*"recommendation": "\([^"]*\)".*/\1/')"
            echo "  Timestamp: $(echo "${finding_json}" | sed 's/.*"timestamp": "\([^"]*\)".*/\1/')"
            echo "--------------------------------------------------------------------------------"
            ((index++))
        done
        
        echo ""
        echo "END OF REPORT"
        echo "================================================================================"
    } > "${report_file}"
}

# Generate JSON report
systemaudit::generate_json_report() {
    local report_file="${1:-}"
    
    {
        echo "{"
        echo "  \"audit\": {"
        echo "    \"timestamp\": \"$(utils::log_stamp)\","
        echo "    \"score\": ${AUDIT_SCORE},"
        echo "    \"summary\": \"${AUDIT_SUMMARY}\","
        echo "    \"total_findings\": ${#AUDIT_FINDINGS[@]},"
        echo "    \"findings\": ["
        
        local first=true
        for finding_json in "${AUDIT_FINDINGS[@]}"; do
            if [[ "${first}" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            echo -n "      ${finding_json}"
        done
        
        echo ""
        echo "    ]"
        echo "  }"
        echo "}"
    } > "${report_file}"
}

# Generate CSV report
systemaudit::generate_csv_report() {
    local report_file="${1:-}"
    
    {
        echo "timestamp,severity,category,title,description,recommendation"
        
        for finding_json in "${AUDIT_FINDINGS[@]}"; do
            local timestamp
            timestamp=$(echo "${finding_json}" | sed 's/.*"timestamp": "\([^"]*\)".*/\1/')
            local severity
            severity=$(echo "${finding_json}" | sed 's/.*"severity": "\([^"]*\)".*/\1/')
            local category
            category=$(echo "${finding_json}" | sed 's/.*"category": "\([^"]*\)".*/\1/')
            local title
            title=$(echo "${finding_json}" | sed 's/.*"title": "\([^"]*\)".*/\1/')
            local description
            description=$(echo "${finding_json}" | sed 's/.*"description": "\([^"]*\)".*/\1/')
            local recommendation
            recommendation=$(echo "${finding_json}" | sed 's/.*"recommendation": "\([^"]*\)".*/\1/')
            
            echo "\"${timestamp}\",\"${severity}\",\"${category}\",\"${title}\",\"${description}\",\"${recommendation}\""
        done
    } > "${report_file}"
}

# Generate XML report
systemaudit::generate_xml_report() {
    local report_file="${1:-}"
    
    {
        echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        echo "<audit>"
        echo "  <timestamp>$(utils::log_stamp)</timestamp>"
        echo "  <score>${AUDIT_SCORE}</score>"
        echo "  <summary>${AUDIT_SUMMARY}</summary>"
        echo "  <total_findings>${#AUDIT_FINDINGS[@]}</total_findings>"
        echo "  <findings>"
        
        local index=1
        for finding_json in "${AUDIT_FINDINGS[@]}"; do
            echo "    <finding id=\"${index}\">"
            echo "      <timestamp>$(echo "${finding_json}" | sed 's/.*"timestamp": "\([^"]*\)".*/\1/')</timestamp>"
            echo "      <severity>$(echo "${finding_json}" | sed 's/.*"severity": "\([^"]*\)".*/\1/')</severity>"
            echo "      <category>$(echo "${finding_json}" | sed 's/.*"category": "\([^"]*\)".*/\1/')</category>"
            echo "      <title>$(echo "${finding_json}" | sed 's/.*"title": "\([^"]*\)".*/\1/')</title>"
            echo "      <description>$(echo "${finding_json}" | sed 's/.*"description": "\([^"]*\)".*/\1/')</description>"
            echo "      <recommendation>$(echo "${finding_json}" | sed 's/.*"recommendation": "\([^"]*\)".*/\1/')</recommendation>"
            echo "    </finding>"
            ((index++))
        done
        
        echo "  </findings>"
        echo "</audit>"
    } > "${report_file}"
}

# ============================================================================
# BASELINE MANAGEMENT
# Управление базовыми показателями
# ============================================================================

# Create baseline
systemaudit::create_baseline() {
    local func_name="systemaudit::create_baseline"
    
    log::info "Creating security baseline..."
    
    local baseline="{"
    baseline="${baseline} \"timestamp\": \"$(utils::log_stamp)\","
    baseline="${baseline} \"hostname\": \"$(hostname)\","
    baseline="${baseline} \"kernel\": \"$(uname -r)\","
    baseline="${baseline} \"users\": $(getent passwd | wc -l),"
    baseline="${baseline} \"listening_ports\": $(utils::quiet_err ss -tuln | grep LISTEN | wc -l || echo 0),"
    baseline="${baseline} \"suid_files\": $(utils::quiet_err find / -type f -perm -4000 | wc -l || echo 0),"
    baseline="${baseline} \"world_writable_files\": $(utils::quiet_err find / -type f -perm -o+w | wc -l || echo 0)"
    baseline="${baseline} }"
    
    echo "${baseline}" > "${AUDIT_BASELINE_FILE}"
    
    log::success "Baseline created: ${AUDIT_BASELINE_FILE}"
}

# Compare with baseline
systemaudit::compare_baseline() {
    local func_name="systemaudit::compare_baseline"
    
    if [[ ! -f "${AUDIT_BASELINE_FILE}" ]]; then
        log::warn "No baseline found. Create baseline first."
        return "${E_ERROR}"
    fi
    
    log::info "Comparing current state with baseline..."
    
    # This would implement detailed baseline comparison
    # For now, just show that baseline exists
    log::info "Baseline comparison would show changes since baseline creation"
}

# ============================================================================
# MODULE INFO
# Информация о модуле
# ============================================================================

systemaudit::info() {
    cat << EOF
System Audit Module v1.0.0

Available Functions:
  systemaudit::init                          - Initialize module
  systemaudit::run [type] [format]           - Run system audit
  systemaudit::run_quick                     - Run quick security audit
  systemaudit::run_full                      - Run full comprehensive audit
  systemaudit::create_baseline               - Create security baseline
  systemaudit::compare_baseline              - Compare with baseline
  
Audit Types:
  security      - Security vulnerability scanning
  users         - User and permission auditing
  network       - Network security assessment
  filesystem    - File system security analysis
  services      - Services and processes audit
  compliance    - Compliance and best practices
  quick         - Quick security overview
  full          - Comprehensive audit (default)

Output Formats:
  text          - Human readable text report (default)
  json          - JSON format for automation
  csv           - CSV format for spreadsheets
  xml           - XML format for integration

Severity Levels:
  CRITICAL      - Immediate action required
  HIGH          - Significant security risk
  MEDIUM        - Moderate security concern
  LOW           - Minor security issue
  INFO          - Informational finding

Configuration:
  Config directory: ${AUDIT_CONFIG_DIR}
  Report directory: ${AUDIT_REPORT_DIR}
  Cache directory: ${AUDIT_CACHE_DIR}
  Baseline file: ${AUDIT_BASELINE_FILE}

Usage:
  systemaudit::run "security" "json"
  systemaudit::run "full" "text"
  systemaudit::create_baseline
  systemaudit::compare_baseline
EOF
}
