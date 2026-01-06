#!/usr/bin/env bs
# security.sh — Security configuration for system setup / Конфигурация безопасности для
# настройки системы

# @description Set up firewall with basic rules / Настроить файрвол с базовыми правилами
# @param $1 Action ("enable", "disable", "status") / Действие ("enable", "disable",
# "status")
# @example
#   system::security::firewall "enable"
system::security::firewall() {
    local action="${1:-status}"
    
    # Try ufw first (Ubuntu/Debian) / Попробовать ufw сначала (Ubuntu/Debian)
    if command -v ufw >/dev/null 2>&1; then
        case "${action}" in
            enable)
                ufw --force enable 2>/dev/null || true
                log::info "UFW firewall enabled"
                ;;
            disable)
                ufw disable 2>/dev/null || true
                log::info "UFW firewall disabled"
                ;;
            status)
                ufw status 2>/dev/null || true
                ;;
            *)
                log::warn "Unknown action: ${action}"
                return 1
                ;;
        esac
    # Try firewalld (RedHat/CentOS/Fedora) / Попробовать firewalld (RedHat/CentOS/Fedora)
    elif command -v firewall-cmd >/dev/null 2>&1; then
        case "${action}" in
            enable)
                systemctl start firewalld 2>/dev/null || true
                systemctl enable firewalld 2>/dev/null || true
                log::info "Firewalld firewall enabled"
                ;;
            disable)
                systemctl stop firewalld 2>/dev/null || true
                systemctl disable firewalld 2>/dev/null || true
                log::info "Firewalld firewall disabled"
                ;;
            status)
                firewall-cmd --list-all 2>/dev/null || true
                ;;
            *)
                log::warn "Unknown action: ${action}"
                return 1
                ;;
        esac
    # Try iptables / Попробовать iptables
    elif command -v iptables >/dev/null 2>&1; then
        case "${action}" in
            enable)
                # Save current rules and enable service
                if command -v iptables-save >/dev/null 2>&1; then
                    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
                fi
                if command -v systemctl >/dev/null 2>&1; then
                    systemctl enable iptables 2>/dev/null || true
                    systemctl start iptables 2>/dev/null || true
                fi
                log::info "Iptables firewall rules saved and service enabled"
                ;;
            disable)
                # Flush rules
                iptables -F 2>/dev/null || true
                iptables -X 2>/dev/null || true
                log::info "Iptables firewall rules flushed"
                ;;
            status)
                iptables -L 2>/dev/null || true
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
    if command -v ufw >/dev/null 2>&1; then
        ufw allow in on lo 2>/dev/null || true
        ufw allow out on lo 2>/dev/null || true
    elif command -v iptables >/dev/null 2>&1; then
        iptables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
        iptables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true
    fi
    
    # Allow established connections
    if command -v ufw >/dev/null 2>&1; then
        ufw default deny incoming 2>/dev/null || true
        ufw default allow outgoing 2>/dev/null || true
    elif command -v iptables >/dev/null 2>&1; then
        iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
        iptables -P INPUT DROP 2>/dev/null || true
        iptables -P FORWARD DROP 2>/dev/null || true
        iptables -P OUTPUT ACCEPT 2>/dev/null || true
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
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${ssh_port}/tcp" 2>/dev/null || true
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --add-port="${ssh_port}/tcp" --permanent 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
    elif command -v iptables >/dev/null 2>&1; then
        iptables -A INPUT -p tcp --dport "${ssh_port}" -j ACCEPT 2>/dev/null || true
    fi
    
    # Enable SSH service
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable ssh 2>/dev/null || true
        systemctl start ssh 2>/dev/null || true
    elif command -v service >/dev/null 2>&1; then
        service ssh start 2>/dev/null || true
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
    if command -v apt >/dev/null 2>&1; then
        if [[ "${enable}" == "true" ]]; then
            # Install unattended-upgrades if not present
            if ! dpkg -l | grep -q unattended-upgrades; then
                apt install -y unattended-upgrades 2>/dev/null || true
            fi
            
            # Enable automatic updates
            echo 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";' > /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null || true
            
            log::info "Automatic security updates enabled"
        else
            # Disable automatic updates
            rm -f /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null || true
            log::info "Automatic security updates disabled"
        fi
    # For RedHat/CentOS/Fedora systems
    elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
        if [[ "${enable}" == "true" ]]; then
            # Install dnf-automatic or yum-cron if not present
            if command -v dnf >/dev/null 2>&1; then
                if ! rpm -q dnf-automatic >/dev/null 2>&1; then
                    dnf install -y dnf-automatic 2>/dev/null || true
                fi
                systemctl enable dnf-automatic.timer 2>/dev/null || true
                systemctl start dnf-automatic.timer 2>/dev/null || true
            elif command -v yum >/dev/null 2>&1; then
                if ! rpm -q yum-cron >/dev/null 2>&1; then
                    yum install -y yum-cron 2>/dev/null || true
                fi
                systemctl enable yum-cron 2>/dev/null || true
                systemctl start yum-cron 2>/dev/null || true
            fi
            
            log::info "Automatic security updates enabled"
        else
            # Disable automatic updates
            if command -v dnf >/dev/null 2>&1; then
                systemctl disable dnf-automatic.timer 2>/dev/null || true
                systemctl stop dnf-automatic.timer 2>/dev/null || true
            elif command -v yum >/dev/null 2>&1; then
                systemctl disable yum-cron 2>/dev/null || true
                systemctl stop yum-cron 2>/dev/null || true
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
        if command -v apt >/dev/null 2>&1; then
            apt install -y fail2ban 2>/dev/null || true
        elif command -v yum >/dev/null 2>&1; then
            yum install -y fail2ban 2>/dev/null || true
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y fail2ban 2>/dev/null || true
        elif command -v pacman >/dev/null 2>&1; then
            pacman -S --noconfirm fail2ban 2>/dev/null || true
        fi
        
        # Enable and start service
        if command -v systemctl >/dev/null 2>&1; then
            systemctl enable fail2ban 2>/dev/null || true
            systemctl start fail2ban 2>/dev/null || true
        fi
        
        log::info "Fail2ban enabled for intrusion prevention"
    else
        # Stop and disable service
        if command -v systemctl >/dev/null 2>&1; then
            systemctl stop fail2ban 2>/dev/null || true
            systemctl disable fail2ban 2>/dev/null || true
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
        sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs 2>/dev/null || true
        sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   7/' /etc/login.defs 2>/dev/null || true
        sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/' /etc/login.defs 2>/dev/null || true
    fi
    
    log::info "Password policies configured"
}

# @description Disable root login
# @example
#   system::security::disable_root
system::security::disable_root() {
    # Lock root password
    passwd -l root 2>/dev/null || true
    
    # Disable SSH root login
    if [[ -f "/etc/ssh/sshd_config" ]]; then
        sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config 2>/dev/null || true
        # Restart SSH service
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart ssh 2>/dev/null || true
        elif command -v service >/dev/null 2>&1; then
            service ssh restart 2>/dev/null || true
        fi
    fi
    
    log::info "Root login disabled"
}