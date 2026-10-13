#!/usr/bin/env bs
# shellcheck shell=bash
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], arithmetic command (( )), array, local/declare flags / needs bash constructs: double-bracket [[ ]], arithmetic command (( )), array, local/declare flags
# security.sh — Security configuration for system setup / Конфигурация безопасности для
# настройки системы
# @depends core/const, core/logger, core/utils, lib/io/files

# Source Guard / Защита от повторной загрузки
bs::guard "SYSTEM_SECURITY" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "../io/files.sh"

# @description Run one privileged step; log and return E_ERROR when it fails / Выполнить
# один привилегированный шаг; при сбое записать ошибку и вернуть E_ERROR
# @param $1 Step description / Описание шага
# @param $@ Command with arguments / Команда с аргументами
system::security::__step() {
    local -r desc="${1}"
    shift
    if ! utils::quiet "$@"; then
        log::error "Step failed: ${desc}"
        return "${E_ERROR}"
    fi
    return 0
}

# @description Add an iptables rule once (checks with -C first) / Добавить правило
# iptables один раз (сначала проверка -C)
# @param $@ Rule specification without the -A chain prefix / Описание правила без -A
system::security::__iptables_ensure() {
    local -r chain="${1}"
    shift
    if utils::quiet iptables -C "${chain}" "$@"; then
        return 0
    fi
    system::security::__step "iptables -A ${chain} $*" iptables -A "${chain}" "$@"
}

# @description Set up firewall with basic rules / Настроить файрвол с базовыми правилами
# @param $1 Action ("enable", "disable", "status") / Действие ("enable", "disable",
# "status")
# Env: BS_IPTABLES_RULES — where "enable" saves iptables rules (default
# /etc/iptables/rules.v4) / куда "enable" сохраняет правила iptables
# @return 0 on success, E_ERROR when a step fails or no firewall is available / 0 при
# успехе, E_ERROR при сбое шага или без файрвола
# @example
#   system::security::firewall "enable"
system::security::firewall() {
    local action="${1:-status}"

    case "${action}" in
        enable|disable|status) ;;
        *)
            log::warn "Unknown action: ${action}"
            return "${E_ERROR}"
            ;;
    esac

    # Try ufw first (Ubuntu/Debian) / Попробовать ufw сначала (Ubuntu/Debian)
    if utils::has ufw; then
        case "${action}" in
            enable)
                system::security::__step "ufw enable" ufw --force enable || return "${E_ERROR}"
                log::info "UFW firewall enabled"
                ;;
            disable)
                system::security::__step "ufw disable" ufw disable || return "${E_ERROR}"
                log::info "UFW firewall disabled"
                ;;
            status)
                ufw status
                ;;
        esac
    # Try firewalld (RedHat/CentOS/Fedora) / Попробовать firewalld (RedHat/CentOS/Fedora)
    elif utils::has firewall-cmd; then
        case "${action}" in
            enable)
                system::security::__step "start firewalld" systemctl start firewalld || return "${E_ERROR}"
                system::security::__step "enable firewalld" systemctl enable firewalld || return "${E_ERROR}"
                log::info "Firewalld firewall enabled"
                ;;
            disable)
                system::security::__step "stop firewalld" systemctl stop firewalld || return "${E_ERROR}"
                system::security::__step "disable firewalld" systemctl disable firewalld || return "${E_ERROR}"
                log::info "Firewalld firewall disabled"
                ;;
            status)
                firewall-cmd --list-all
                ;;
        esac
    # Try iptables / Попробовать iptables
    elif utils::has iptables; then
        case "${action}" in
            enable)
                # Save current rules and enable service / Сохранить правила и включить сервис
                local rules_file="${BS_IPTABLES_RULES:-/etc/iptables/rules.v4}"
                if utils::has iptables-save; then
                    if ! iptables-save > "${rules_file}" 2>/dev/null; then
                        log::warn "Could not save iptables rules to ${rules_file}"
                    fi
                fi
                if utils::has systemctl; then
                    system::security::__step "enable iptables" systemctl enable iptables || return "${E_ERROR}"
                    system::security::__step "start iptables" systemctl start iptables || return "${E_ERROR}"
                fi
                log::info "Iptables firewall rules saved and service enabled"
                ;;
            disable)
                # Policies first: flushing rules under "-P INPUT DROP" cuts off every
                # connection, including the SSH session that runs this
                # Сначала политики: сброс правил при "-P INPUT DROP" рвёт все соединения,
                # включая SSH-сессию, из которой это запущено
                system::security::__step "iptables -P INPUT ACCEPT" iptables -P INPUT ACCEPT || return "${E_ERROR}"
                system::security::__step "iptables -P FORWARD ACCEPT" iptables -P FORWARD ACCEPT || return "${E_ERROR}"
                system::security::__step "iptables -P OUTPUT ACCEPT" iptables -P OUTPUT ACCEPT || return "${E_ERROR}"
                system::security::__step "iptables -F" iptables -F || return "${E_ERROR}"
                system::security::__step "iptables -X" iptables -X || return "${E_ERROR}"
                log::info "Iptables firewall rules flushed"
                ;;
            status)
                iptables -L
                ;;
        esac
    else
        log::warn "No supported firewall found"
        return "${E_ERROR}"
    fi
}

# @description Configure basic firewall rules
# @example
#   system::security::firewall_rules
system::security::firewall_rules() {
    if utils::has ufw; then
        # Allow loopback / Разрешить loopback
        system::security::__step "ufw allow in on lo" ufw allow in on lo || return "${E_ERROR}"
        system::security::__step "ufw allow out on lo" ufw allow out on lo || return "${E_ERROR}"
        # Default policy / Политика по умолчанию
        system::security::__step "ufw default deny incoming" ufw default deny incoming || return "${E_ERROR}"
        system::security::__step "ufw default allow outgoing" ufw default allow outgoing || return "${E_ERROR}"
    elif utils::has iptables; then
        # Rules are added once (-C check): a repeated call must not duplicate them
        # Правила добавляются один раз (проверка -C): повторный вызов не дублирует их
        system::security::__iptables_ensure INPUT -i lo -j ACCEPT || return "${E_ERROR}"
        system::security::__iptables_ensure OUTPUT -o lo -j ACCEPT || return "${E_ERROR}"
        # Allow established connections / Разрешить установленные соединения
        system::security::__iptables_ensure INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT || return "${E_ERROR}"
        system::security::__step "iptables -P INPUT DROP" iptables -P INPUT DROP || return "${E_ERROR}"
        system::security::__step "iptables -P FORWARD DROP" iptables -P FORWARD DROP || return "${E_ERROR}"
        system::security::__step "iptables -P OUTPUT ACCEPT" iptables -P OUTPUT ACCEPT || return "${E_ERROR}"
    else
        log::warn "No supported firewall found"
        return "${E_ERROR}"
    fi

    log::info "Basic firewall rules configured"
}

# @description Set up SSH security
# @param $1 SSH port (default: 22)
# @example
#   system::security::ssh 22
system::security::ssh() {
    local ssh_port="${1:-22}"

    if [[ ! "${ssh_port}" =~ ^[0-9]+$ ]] || (( ssh_port < 1 || ssh_port > 65535 )); then
        log::error "Invalid SSH port: ${ssh_port}"
        return "${E_INVALID}"
    fi

    # Allow SSH through firewall
    if utils::has ufw; then
        system::security::__step "ufw allow ${ssh_port}/tcp" ufw allow "${ssh_port}/tcp" || return "${E_ERROR}"
    elif utils::has firewall-cmd; then
        system::security::__step "firewall-cmd add port" firewall-cmd --add-port="${ssh_port}/tcp" --permanent || return "${E_ERROR}"
        system::security::__step "firewall-cmd reload" firewall-cmd --reload || return "${E_ERROR}"
    elif utils::has iptables; then
        system::security::__iptables_ensure INPUT -p tcp --dport "${ssh_port}" -j ACCEPT || return "${E_ERROR}"
    fi

    # Enable SSH service: the unit is "ssh" on Debian and "sshd" on RedHat
    # Включить SSH: юнит "ssh" в Debian и "sshd" в RedHat
    if utils::has systemctl; then
        if ! utils::quiet systemctl enable ssh && ! utils::quiet systemctl enable sshd; then
            log::error "Step failed: enable ssh/sshd service"
            return "${E_ERROR}"
        fi
        if ! utils::quiet systemctl start ssh && ! utils::quiet systemctl start sshd; then
            log::error "Step failed: start ssh/sshd service"
            return "${E_ERROR}"
        fi
    elif utils::has service; then
        if ! utils::quiet service ssh start && ! utils::quiet service sshd start; then
            log::error "Step failed: start ssh/sshd service"
            return "${E_ERROR}"
        fi
    fi

    log::info "SSH security configured on port ${ssh_port}"
}

# @description Configure automatic security updates
# @param $1 "true" to enable, "false" to disable
# Env: BS_APT_CONF_DIR — apt.conf.d directory (default /etc/apt/apt.conf.d) /
# каталог apt.conf.d
# @example
#   system::security::auto_updates "true"
system::security::auto_updates() {
    local enable="${1:-false}"

    # For Debian/Ubuntu systems
    if utils::has apt; then
        local conf="${BS_APT_CONF_DIR:-/etc/apt/apt.conf.d}/20auto-upgrades"
        if [[ "${enable}" == "true" ]]; then
            # Install unattended-upgrades if not present (status "ii", not leftover
            # config "rc") / Установить unattended-upgrades, если нет (статус "ii", а не
            # остатки конфигурации "rc")
            local pkg_state
            pkg_state="$(utils::attempt dpkg-query -W -f='${db:Status-Abbrev}' unattended-upgrades)"
            if [[ "${pkg_state}" != ii* ]]; then
                system::security::__step "install unattended-upgrades" apt install -y unattended-upgrades || return "${E_ERROR}"
            fi

            # Enable automatic updates
            if ! printf '%s\n%s\n' \
                'APT::Periodic::Update-Package-Lists "1";' \
                'APT::Periodic::Unattended-Upgrade "1";' > "${conf}" 2>/dev/null; then
                log::error "Cannot write ${conf}"
                return "${E_ERROR}"
            fi

            log::info "Automatic security updates enabled"
        else
            # Disable automatic updates
            if is::exists "${conf}"; then
                system::security::__step "remove ${conf}" rm -f "${conf}" || return "${E_ERROR}"
            fi
            log::info "Automatic security updates disabled"
        fi
    # For RedHat/CentOS/Fedora systems
    elif utils::has yum || utils::has dnf; then
        if [[ "${enable}" == "true" ]]; then
            # Install dnf-automatic or yum-cron if not present
            if utils::has dnf; then
                if ! utils::quiet rpm -q dnf-automatic; then
                    system::security::__step "install dnf-automatic" dnf install -y dnf-automatic || return "${E_ERROR}"
                fi
                system::security::__step "enable dnf-automatic.timer" systemctl enable dnf-automatic.timer || return "${E_ERROR}"
                system::security::__step "start dnf-automatic.timer" systemctl start dnf-automatic.timer || return "${E_ERROR}"
            elif utils::has yum; then
                if ! utils::quiet rpm -q yum-cron; then
                    system::security::__step "install yum-cron" yum install -y yum-cron || return "${E_ERROR}"
                fi
                system::security::__step "enable yum-cron" systemctl enable yum-cron || return "${E_ERROR}"
                system::security::__step "start yum-cron" systemctl start yum-cron || return "${E_ERROR}"
            fi

            log::info "Automatic security updates enabled"
        else
            # Disable automatic updates
            if utils::has dnf; then
                system::security::__step "disable dnf-automatic.timer" systemctl disable dnf-automatic.timer || return "${E_ERROR}"
                system::security::__step "stop dnf-automatic.timer" systemctl stop dnf-automatic.timer || return "${E_ERROR}"
            elif utils::has yum; then
                system::security::__step "disable yum-cron" systemctl disable yum-cron || return "${E_ERROR}"
                system::security::__step "stop yum-cron" systemctl stop yum-cron || return "${E_ERROR}"
            fi
            log::info "Automatic security updates disabled"
        fi
    else
        log::warn "Automatic security updates not supported on this system"
        return "${E_ERROR}"
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
        if ! utils::has fail2ban-client; then
            if utils::has apt; then
                system::security::__step "install fail2ban" apt install -y fail2ban || return "${E_ERROR}"
            elif utils::has dnf; then
                system::security::__step "install fail2ban" dnf install -y fail2ban || return "${E_ERROR}"
            elif utils::has yum; then
                system::security::__step "install fail2ban" yum install -y fail2ban || return "${E_ERROR}"
            elif utils::has pacman; then
                system::security::__step "install fail2ban" pacman -S --noconfirm fail2ban || return "${E_ERROR}"
            else
                log::error "fail2ban is not installed and no package manager was found"
                return "${E_ERROR}"
            fi
        fi

        # Enable and start service
        if utils::has systemctl; then
            system::security::__step "enable fail2ban" systemctl enable fail2ban || return "${E_ERROR}"
            system::security::__step "start fail2ban" systemctl start fail2ban || return "${E_ERROR}"
        fi

        log::info "Fail2ban enabled for intrusion prevention"
    else
        # Stop and disable service: "not installed" is fine, "still running" is not
        # Остановить и отключить сервис: «не установлен» — нормально, «всё ещё работает» — нет
        if utils::has systemctl; then
            utils::ignore systemctl stop fail2ban
            utils::ignore systemctl disable fail2ban
            if utils::quiet systemctl is-active --quiet fail2ban; then
                log::error "fail2ban is still active after stop"
                return "${E_ERROR}"
            fi
        fi

        log::info "Fail2ban disabled"
    fi
}

# @description Configure password policies
# Env: BS_PAM_DIR (default /etc/pam.d), BS_LOGIN_DEFS (default /etc/login.defs) /
# каталог PAM и путь login.defs
# @example
#   system::security::password_policy
system::security::password_policy() {
    local -r pam_dir="${BS_PAM_DIR:-/etc/pam.d}"
    local -r login_defs="${BS_LOGIN_DEFS:-/etc/login.defs}"

    # Set password complexity requirements
    if is::file "${pam_dir}/common-password"; then
        # For Debian/Ubuntu systems
        if ! grep -q "pam_pwquality.so" "${pam_dir}/common-password"; then
            io::files::append "${pam_dir}/common-password" "password requisite pam_pwquality.so retry=3 minlen=8 difok=3 ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1"
        fi
    elif is::file "${pam_dir}/system-auth"; then
        # For RedHat/CentOS systems: add the pwquality line BEFORE pam_unix; the old
        # code replaced the pam_unix line, so passwords could no longer be changed
        # Для RedHat/CentOS: строка pwquality добавляется ПЕРЕД pam_unix; прежний код
        # заменял строку pam_unix, и пароли переставали меняться
        if ! grep -q "pam_pwquality.so" "${pam_dir}/system-auth"; then
            if ! sed -i --follow-symlinks '0,/^password.*pam_unix\.so/s//password    requisite     pam_pwquality.so try_first_pass local_users_only retry=3 authtok_type=\n&/' "${pam_dir}/system-auth"; then
                log::error "Cannot update ${pam_dir}/system-auth"
                return "${E_ERROR}"
            fi
        fi
    fi

    # Set password expiration
    if is::file "${login_defs}"; then
        local key value
        for key in PASS_MAX_DAYS:90 PASS_MIN_DAYS:7 PASS_WARN_AGE:14; do
            value="${key#*:}"
            key="${key%%:*}"
            if grep -q "^${key}\b" "${login_defs}"; then
                system::security::__step "set ${key}" sed -i "s/^${key}.*/${key}   ${value}/" "${login_defs}" || return "${E_ERROR}"
            else
                io::files::append "${login_defs}" "${key}   ${value}"
            fi
        done
    fi

    log::info "Password policies configured"
}

# @description Check that a non-root account in sudo/wheel/admin exists / Проверить, что
# есть не-root учётная запись в группе sudo/wheel/admin
system::security::__has_admin_user() {
    local grp members member
    local -a list=()
    for grp in sudo wheel admin; do
        members="$(utils::attempt getent group "${grp}")"
        members="${members##*:}"
        [[ -n "${members}" ]] || continue
        IFS=',' read -ra list <<< "${members}"
        for member in "${list[@]}"; do
            if [[ -n "${member}" && "${member}" != "root" ]]; then
                return 0
            fi
        done
    done
    return 1
}

# @description Disable root login. Refuses when no other administrator exists (would
# lock everybody out); rolls the sshd config back if "sshd -t" rejects it / Отключить
# вход root. Отказывает, если нет другого администратора (иначе блокировка для всех);
# откатывает конфиг sshd, если "sshd -t" его не принял
# Env: BS_SSHD_MAIN (default /etc/ssh/sshd_config), BS_SSHD_BIN (default sshd)
# @example
#   system::security::disable_root
system::security::disable_root() {
    local -r sshd_config="${BS_SSHD_MAIN:-/etc/ssh/sshd_config}"
    local -r sshd_bin="${BS_SSHD_BIN:-sshd}"

    if ! system::security::__has_admin_user; then
        log::error "No non-root user in sudo/wheel/admin: refusing to disable root (lockout)"
        return "${E_ERROR}"
    fi

    # Disable SSH root login
    if is::file "${sshd_config}"; then
        local -r backup="${sshd_config}.bs-bak.$$"
        system::security::__step "backup ${sshd_config}" cp -p "${sshd_config}" "${backup}" || return "${E_ERROR}"
        if grep -qE '^[[:space:]]*PermitRootLogin' "${sshd_config}"; then
            sed -i -E 's/^[[:space:]]*PermitRootLogin.*/PermitRootLogin no/' "${sshd_config}" || {
                utils::ignore rm -f "${backup}"
                log::error "Cannot edit ${sshd_config}"
                return "${E_ERROR}"
            }
        else
            # First value wins in sshd_config: put it on top, outside any Match block
            # В sshd_config действует первое значение: ставим наверх, вне блоков Match
            sed -i '1i PermitRootLogin no' "${sshd_config}" || {
                utils::ignore rm -f "${backup}"
                log::error "Cannot edit ${sshd_config}"
                return "${E_ERROR}"
            }
        fi
        if utils::has "${sshd_bin}" && ! utils::quiet "${sshd_bin}" -t -f "${sshd_config}"; then
            utils::ignore cp -p "${backup}" "${sshd_config}"
            utils::ignore rm -f "${backup}"
            log::error "sshd rejected the edited config; ${sshd_config} restored"
            return "${E_ERROR}"
        fi
        utils::ignore rm -f "${backup}"
        # Restart SSH service: the unit is "ssh" on Debian and "sshd" on RedHat
        if utils::has systemctl; then
            if ! utils::quiet systemctl restart ssh && ! utils::quiet systemctl restart sshd; then
                log::error "Step failed: restart ssh/sshd service"
                return "${E_ERROR}"
            fi
        elif utils::has service; then
            if ! utils::quiet service ssh restart && ! utils::quiet service sshd restart; then
                log::error "Step failed: restart ssh/sshd service"
                return "${E_ERROR}"
            fi
        fi
    fi

    # Lock root password last: all earlier steps are reversible by root itself
    # Пароль root блокируем последним: все прежние шаги root может откатить сам
    system::security::__step "passwd -l root" passwd -l root || return "${E_ERROR}"

    log::info "Root login disabled"
}
