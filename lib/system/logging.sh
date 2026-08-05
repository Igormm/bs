#!/usr/bin/env bs
# logging.sh — Logging configuration for system setup / Конфигурация логирования для
# настройки системы
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/guard.sh"
bs::guard "SYSTEM_LOGGING" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# @description Configure system logging / Настроить системное логирование
# @param $1 Log level (e.g., "info", "warn", "error") / Уровень логирования (например,
# "info", "warn", "error")
# @example
#   system::logging::configure "info"
system::logging::configure() {
    local log_level="${1:-info}"
    
    # For systemd-based systems / Для систем на базе systemd
    if utils::has journalctl; then
        # Set log level for journald / Установить уровень логирования для journald
        if [[ -f "/etc/systemd/journald.conf" ]]; then
            utils::quiet_err sed -i "s/^#MaxLevelStore=.*/MaxLevelStore=${log_level}/" /etc/systemd/journald.conf || true
            utils::quiet_err sed -i "s/^#MaxLevelSyslog=.*/MaxLevelSyslog=${log_level}/" /etc/systemd/journald.conf || true
            # Restart journald to apply changes / Перезапустить journald для применения
            # изменений
            if utils::has systemctl; then
                utils::quiet_err systemctl restart systemd-journald || true
            fi
        fi
        log::info "System logging configured with level: ${log_level}"
    else
        # For sysvinit systems with rsyslog / Для систем sysvinit с rsyslog
        if [[ -f "/etc/rsyslog.conf" ]]; then
            # Set log level in rsyslog / Установить уровень логирования в rsyslog
            utils::quiet_err sed -i "s/^\$SystemLogRateLimitInterval.*/\$SystemLogRateLimitInterval 0/" /etc/rsyslog.conf || true
            # Restart rsyslog to apply changes / Перезапустить rsyslog для применения
            # изменений
            if utils::has systemctl; then
                utils::quiet_err systemctl restart rsyslog || true
            elif utils::has service; then
                utils::quiet_err service rsyslog restart || true
            fi
        fi
        log::info "RSyslog configured"
    fi
}

# @description Set up log rotation / Настроить ротацию логов
# @param $1 Log file path / Путь к файлу лога
# @param $2 Rotation frequency ("daily", "weekly", "monthly") / Частота ротации ("daily",
# "weekly", "monthly")
# @param $3 Number of rotations to keep / Количество ротаций для хранения
# @example
#   system::logging::rotate "/var/log/myapp.log" "daily" 7
system::logging::rotate() {
    local log_file="${1}"
    local frequency="${2:-weekly}"
    local keep="${3:-4}"
    
    if [[ -z "${log_file}" ]]; then
        log::warn "Log file path not specified"
        return 1
    fi
    
    # Create logrotate configuration
    local config_file="/etc/logrotate.d/bosa_$(basename "${log_file}" .log)"
    
    cat > "${config_file}" << EOF
${log_file} {
    ${frequency}
    rotate ${keep}
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF
    
    log::info "Log rotation configured for ${log_file}: ${frequency}, keep ${keep} rotations"
}

# @description View system logs
# @param $1 Number of lines to show (default: 50)
# @param $2 Service name (optional)
# @example
#   system::logging::view 100 "sshd"
system::logging::view() {
    local lines="${1:-50}"
    local service="${2}"
    
    # For systemd-based systems
    if utils::has journalctl; then
        if [[ -n "${service}" ]]; then
            utils::quiet_err journalctl -u "${service}" -n "${lines}" -f || true
        else
            utils::quiet_err journalctl -n "${lines}" -f || true
        fi
    else
        # For sysvinit systems
        local log_file="/var/log/messages"
        if [[ -n "${service}" ]]; then
            # Try to find service-specific log
            if [[ -f "/var/log/${service}.log" ]]; then
                log_file="/var/log/${service}.log"
            fi
        fi
        
        if [[ -f "${log_file}" ]]; then
            utils::quiet_err tail -n "${lines}" "${log_file}" || true
        else
            log::warn "Log file ${log_file} not found"
            return 1
        fi
    fi
}

# @description Set up remote logging
# @param $1 Remote log server IP
# @param $2 Remote log server port (default: 514)
# @example
#   system::logging::remote "192.168.1.100" 514
system::logging::remote() {
    local server_ip="${1}"
    local server_port="${2:-514}"
    
    if [[ -z "${server_ip}" ]]; then
        log::warn "Remote log server IP not specified"
        return 1
    fi
    
    # For rsyslog
    if [[ -f "/etc/rsyslog.conf" ]]; then
        # Add remote logging configuration
        echo "*.* @${server_ip}:${server_port}" >> /etc/rsyslog.conf
        
        # Restart rsyslog to apply changes
        if utils::has systemctl; then
            utils::quiet_err systemctl restart rsyslog || true
        elif utils::has service; then
            utils::quiet_err service rsyslog restart || true
        fi
        
        log::info "Remote logging configured to ${server_ip}:${server_port}"
    else
        log::warn "RSyslog configuration file not found"
        return 1
    fi
}

# @description Configure audit logging
# @param $1 "true" to enable, "false" to disable
# @example
#   system::logging::audit "true"
system::logging::audit() {
    local enable="${1:-false}"
    
    if [[ "${enable}" == "true" ]]; then
        # Install auditd if not present
        if utils::has apt; then
            utils::quiet_err apt install -y auditd || true
        elif utils::has yum; then
            utils::quiet_err yum install -y audit || true
        elif utils::has dnf; then
            utils::quiet_err dnf install -y audit || true
        fi
        
        # Enable and start auditd service
        if utils::has systemctl; then
            utils::quiet_err systemctl enable auditd || true
            utils::quiet_err systemctl start auditd || true
        fi
        
        # Basic audit rules
        cat > /etc/audit/rules.d/BS.rules << EOF
# BS audit rules
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity
-w /etc/sudoers -p wa -k priv_actions
-w /etc/sudoers.d/ -p wa -k priv_actions
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/log/tallylog -p wa -k logins
EOF
        
        # Load audit rules
        if utils::has augenrules; then
            utils::quiet_err augenrules --load || true
        fi
        
        log::info "Audit logging enabled"
    else
        # Stop and disable auditd service
        if utils::has systemctl; then
            utils::quiet_err systemctl stop auditd || true
            utils::quiet_err systemctl disable auditd || true
        fi
        
        # Remove BS audit rules
        utils::quiet_err rm -f /etc/audit/rules.d/BS.rules || true
        
        log::info "Audit logging disabled"
    fi
}

# @description Set up log file permissions
# @param $1 Log file path
# @param $2 Permissions (default: "640")
# @param $3 Owner (default: "root")
# @param $4 Group (default: "adm" or "root")
# @example
#   system::logging::permissions "/var/log/myapp.log" "640" "myuser" "adm"
system::logging::permissions() {
    local log_file="${1}"
    local permissions="${2:-640}"
    local owner="${3:-root}"
    local group="${4}"
    
    if [[ -z "${log_file}" ]]; then
        log::warn "Log file path not specified"
        return 1
    fi
    
    # Set default group if not specified
    if [[ -z "${group}" ]]; then
        if utils::quiet getent group adm; then
            group="adm"
        else
            group="root"
        fi
    fi
    
    # Set permissions
    if [[ -f "${log_file}" ]]; then
        utils::quiet_err chmod "${permissions}" "${log_file}" || true
        utils::quiet_err chown "${owner}:${group}" "${log_file}" || true
        log::info "Permissions set for ${log_file}: ${permissions}, owner: ${owner}, group: ${group}"
    else
        log::warn "Log file ${log_file} not found"
        return 1
    fi
}

# @description Clean old log files
# @param $1 Directory path (default: "/var/log")
# @param $2 Age in days (default: 30)
# @example
#   system::logging::clean "/var/log" 30
system::logging::clean() {
    local directory="${1:-/var/log}"
    local age="${2:-30}"
    
    if [[ ! -d "${directory}" ]]; then
        log::warn "Directory ${directory} not found"
        return 1
    fi
    
    # Find and remove old log files
    utils::quiet_err find "${directory}" -name "*.log.*" -type f -mtime +${age} -delete || true
    
    log::info "Old log files cleaned from ${directory} (older than ${age} days)"
}