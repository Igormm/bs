#!/usr/bin/env bs
# security.sh — Security configuration for system setup / Конфигурация безопасности для
# настройки системы
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/guard.sh"
bs::guard "SYSTEM_SECURITY" || return 0

# Зависимости / Dependencies
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/const.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/logger.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/utils.sh"

# @description Set up firewall with basic rules / Настроить файрвол с базовыми правилами
# @param $1 Action ("enable", "disable", "status") / Действие ("enable", "disable",
# "status")
# @example
#   system::security::firewall "enable"
system::security::firewall() {
    local action="${1:-status}"
    
    # Try ufw first (Ubuntu/Debian) / Попробовать ufw сначала (Ubuntu/Debian)
    if utils::has ufw; then
        case "${action}" in
            enable)
                utils::ignore ufw --force enable
                log::info "UFW firewall enabled"
                ;;
            disable)
                utils::ignore ufw disable
                log::info "UFW firewall disabled"
                ;;
            status)
                utils::ignore ufw status
                ;;
            *)
                log::warn "Unknown action: ${action}"
                return 1
                ;;
        esac
    # Try firewalld (RedHat/CentOS/Fedora) / Попробовать firewalld (RedHat/CentOS/Fedora)
    elif utils::has firewall-cmd; then
        case "${action}" in
            enable)
                utils::ignore systemctl start firewalld
                utils::ignore systemctl enable firewalld
                log::info "Firewalld firewall enabled"
                ;;
            disable)
                utils::ignore systemctl stop firewalld
                utils::ignore systemctl disable firewalld
                log::info "Firewalld firewall disabled"
                ;;
            status)
                utils::ignore firewall-cmd --list-all
                ;;
            *)
                log::warn "Unknown action: ${action}"
                return 1
                ;;
        esac
    # Try iptables / Попробовать iptables
    elif utils::has iptables; then
        case "${action}" in
            enable)
                # Save current rules and enable service
                if utils::has iptables-save; then
                    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
                fi
                if utils::has systemctl; then
                    utils::ignore systemctl enable iptables
                    utils::ignore systemctl start iptables
                fi
                log::info "Iptables firewall rules saved and service enabled"
                ;;
            disable)
                # Flush rules
                utils::ignore iptables -F
                utils::ignore iptables -X
                log::info "Iptables firewall rules flushed"
                ;;
            status)
                utils::ignore iptables -L
                ;;
            *)
                log::warn "Unknown action: ${action}"
                return 1
                ;;
        esac
    else
        log::warn "No supported firewall found"
        return 1
    fi
}

# @description Configure basic firewall rules
# @example
#   system::security::firewall_rules
system::security::firewall_rules() {
    # Allow loopback
    if utils::has ufw; then
        utils::ignore ufw allow in on lo
        utils::ignore ufw allow out on lo
    elif utils::has iptables; then
        utils::ignore iptables -A INPUT -i lo -j ACCEPT
        utils::ignore iptables -A OUTPUT -o lo -j ACCEPT
    fi
    
    # Allow established connections
    if utils::has ufw; then
        utils::ignore ufw default deny incoming
        utils::ignore ufw default allow outgoing
    elif utils::has iptables; then
        utils::ignore iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        utils::ignore iptables -P INPUT DROP
        utils::ignore iptables -P FORWARD DROP
        utils::ignore iptables -P OUTPUT ACCEPT
    fi
    
    log::info "Basic firewall rules configured"
}

# @description Set up SSH security
# @param $1 SSH port (default: 22)
# @example
#   system::security::ssh 22
system::security::ssh() {
    local ssh_port="${1:-22}"
    
    # Allow SSH through firewall
    if utils::has ufw; then
        utils::ignore ufw allow "${ssh_port}/tcp"
    elif utils::has firewall-cmd; then
        utils::ignore firewall-cmd --add-port="${ssh_port}/tcp" --permanent
        utils::ignore firewall-cmd --reload
    elif utils::has iptables; then
        utils::ignore iptables -A INPUT -p tcp --dport "${ssh_port}" -j ACCEPT
    fi
    
    # Enable SSH service
    if utils::has systemctl; then
        utils::ignore systemctl enable ssh
        utils::ignore systemctl start ssh
    elif utils::has service; then
        utils::ignore service ssh start
    fi
    
    log::info "SSH security configured on port ${ssh_port}"
}

# @description Configure automatic security updates
# @param $1 "true" to enable, "false" to disable
# @example
#   system::security::auto_updates "true"
system::security::auto_updates() {
    local enable="${1:-false}"
    
    # For Debian/Ubuntu systems
    if utils::has apt; then
        if [[ "${enable}" == "true" ]]; then
            # Install unattended-upgrades if not present
            if ! dpkg -l | grep -q unattended-upgrades; then
                utils::ignore apt install -y unattended-upgrades
            fi
            
            # Enable automatic updates
            echo 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";' > /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null || true
            
            log::info "Automatic security updates enabled"
        else
            # Disable automatic updates
            utils::ignore rm -f /etc/apt/apt.conf.d/20auto-upgrades
            log::info "Automatic security updates disabled"
        fi
    # For RedHat/CentOS/Fedora systems
    elif utils::has yum || utils::has dnf; then
        if [[ "${enable}" == "true" ]]; then
            # Install dnf-automatic or yum-cron if not present
            if utils::has dnf; then
                if ! utils::quiet rpm -q dnf-automatic; then
                    utils::ignore dnf install -y dnf-automatic
                fi
                utils::ignore systemctl enable dnf-automatic.timer
                utils::ignore systemctl start dnf-automatic.timer
            elif utils::has yum; then
                if ! utils::quiet rpm -q yum-cron; then
                    utils::ignore yum install -y yum-cron
                fi
                utils::ignore systemctl enable yum-cron
                utils::ignore systemctl start yum-cron
            fi
            
            log::info "Automatic security updates enabled"
        else
            # Disable automatic updates
            if utils::has dnf; then
                utils::ignore systemctl disable dnf-automatic.timer
                utils::ignore systemctl stop dnf-automatic.timer
            elif utils::has yum; then
                utils::ignore systemctl disable yum-cron
                utils::ignore systemctl stop yum-cron
            fi
            log::info "Automatic security updates disabled"
        fi
    else
        log::warn "Automatic security updates not supported on this system"
        return 1
    fi
}

# @description Set up fail2ban for intrusion prevention
# @param $1 "true" to enable, "false" to disable
# @example
#   system::security::fail2ban "true"
system::security::fail2ban() {
    local enable="${1:-false}"
    
    if [[ "${enable}" == "true" ]]; then
        # Install fail2ban if not present
        if utils::has apt; then
            utils::ignore apt install -y fail2ban
        elif utils::has yum; then
            utils::ignore yum install -y fail2ban
        elif utils::has dnf; then
            utils::ignore dnf install -y fail2ban
        elif utils::has pacman; then
            utils::ignore pacman -S --noconfirm fail2ban
        fi
        
        # Enable and start service
        if utils::has systemctl; then
            utils::ignore systemctl enable fail2ban
            utils::ignore systemctl start fail2ban
        fi
        
        log::info "Fail2ban enabled for intrusion prevention"
    else
        # Stop and disable service
        if utils::has systemctl; then
            utils::ignore systemctl stop fail2ban
            utils::ignore systemctl disable fail2ban
        fi
        
        log::info "Fail2ban disabled"
    fi
}

# @description Configure password policies
# @example
#   system::security::password_policy
system::security::password_policy() {
    # Set password complexity requirements
    if [[ -f "/etc/pam.d/common-password" ]]; then
        # For Debian/Ubuntu systems
        if ! grep -q "pam_pwquality.so" /etc/pam.d/common-password; then
            echo "password requisite pam_pwquality.so retry=3 minlen=8 difok=3 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1" >> /etc/pam.d/common-password
        fi
    elif [[ -f "/etc/pam.d/system-auth" ]]; then
        # For RedHat/CentOS systems
        if ! grep -q "pam_pwquality.so" /etc/pam.d/system-auth; then
            sed -i 's/password.*pam_unix.so/password    requisite     pam_pwquality.so try_first_pass local_users_only retry=3 authtok_type=/' /etc/pam.d/system-auth
        fi
    fi
    
    # Set password expiration
    if [[ -f "/etc/login.defs" ]]; then
        utils::ignore sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
        utils::ignore sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   7/' /etc/login.defs
        utils::ignore sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/' /etc/login.defs
    fi
    
    log::info "Password policies configured"
}

# @description Disable root login
# @example
#   system::security::disable_root
system::security::disable_root() {
    # Lock root password
    utils::ignore passwd -l root
    
    # Disable SSH root login
    if [[ -f "/etc/ssh/sshd_config" ]]; then
        utils::ignore sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
        # Restart SSH service
        if utils::has systemctl; then
            utils::ignore systemctl restart ssh
        elif utils::has service; then
            utils::ignore service ssh restart
        fi
    fi
    
    log::info "Root login disabled"
}