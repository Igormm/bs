#!/usr/bin/env bs
# distrologic.sh — Distribution-specific logic for BS / Логика для конкретного
# дистрибутива для BS
#
# This module provides functions to handle distribution-specific operations / Этот модуль
# предоставляет функции для выполнения операций, специфичных для дистрибутива
#
# Usage / Использование:
#   load "lib/system/distrologic"
#   system::distrologic::pkg_install_debian "curl"
#   system::distrologic::service_manage_systemd "nginx" "start"
# @depends core/const, core/logger, core/utils, lib/system/distro

# Source Guard / Защита от повторной загрузки
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/guard.sh"
bs::guard "SYSTEM_DISTROLOGIC" || return 0

# Зависимости / Dependencies
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/const.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/logger.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/utils.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/distro.sh"

# @description Install package on Debian-based systems / Установить пакет в системах на
# базе Debian
# @param $@ Package names / Имена пакетов
# @example
#   system::distrologic::pkg_install_debian "curl" "wget"
system::distrologic::pkg_install_debian() {
    if system::distro::is_family "debian"; then
        apt-get update
        apt-get install -y "$@"
    else
        log::warn "Not a Debian-based system"
        return 1
    fi
}

# @description Install package on Fedora/RHEL systems / Установить пакет в системах
# Fedora/RHEL
# @param $@ Package names / Имена пакетов
# @example
#   system::distrologic::pkg_install_fedora "curl" "wget"
system::distrologic::pkg_install_fedora() {
    if system::distro::is_family "redhat"; then
        local pkg_manager
        if utils::has dnf; then
            pkg_manager="dnf"
        elif utils::has yum; then
            pkg_manager="yum"
        else
            log::error "No supported package manager found"
            return 1
        fi

        ${pkg_manager} install -y "$@"
    else
        log::warn "Not a RedHat-based system"
        return 1
    fi
}

# @description Install package on Arch Linux systems / Установить пакет в системах Arch
# Linux
# @param $@ Package names / Имена пакетов
# @example
#   system::distrologic::pkg_install_arch "curl" "wget"
system::distrologic::pkg_install_arch() {
    if system::distro::is_family "arch"; then
        pacman -S --noconfirm "$@"
    else
        log::warn "Not an Arch-based system"
        return 1
    fi
}

# @description Install package on openSUSE systems / Установить пакет в системах openSUSE
# @param $@ Package names / Имена пакетов
# @example
#   system::distrologic::pkg_install_suse "curl" "wget"
system::distrologic::pkg_install_suse() {
    if system::distro::is_family "suse"; then
        zypper install -y "$@"
    else
        log::warn "Not a SUSE-based system"
        return 1
    fi
}

# @description Install package on ALT Linux systems / Установить пакет в системах ALT
# Linux
# @param $@ Package names / Имена пакетов
# @example
#   system::distrologic::pkg_install_alt "curl" "wget"
system::distrologic::pkg_install_alt() {
    # ALT Linux uses apt-rpm package manager
    if [[ "${DISTRO_ID}" == *"alt"* ]]; then
        apt-get update
        apt-get install -y "$@"
    else
        log::warn "Not an ALT Linux system"
        return 1
    fi
}

# @description Remove package on Debian-based systems / Удалить пакет в системах на базе
# Debian
# @param $@ Package names / Имена пакетов
# @example
#   system::distrologic::pkg_remove_debian "curl"
system::distrologic::pkg_remove_debian() {
    if system::distro::is_family "debian"; then
        apt-get remove -y "$@"
    else
        log::warn "Not a Debian-based system"
        return 1
    fi
}

# @description Remove package on Fedora/RHEL systems / Удалить пакет в системах
# Fedora/RHEL
# @param $@ Package names / Имена пакетов
# @example
#   system::distrologic::pkg_remove_fedora "curl"
system::distrologic::pkg_remove_fedora() {
    if system::distro::is_family "redhat"; then
        local pkg_manager
        if utils::has dnf; then
            pkg_manager="dnf"
        elif utils::has yum; then
            pkg_manager="yum"
        else
            log::error "No supported package manager found"
            return 1
        fi

        ${pkg_manager} remove -y "$@"
    else
        log::warn "Not a RedHat-based system"
        return 1
    fi
}

# @description Update all packages on any system / Обновить все пакеты в любой системе
# @example
#   system::distrologic::pkg_update_all
system::distrologic::pkg_update_all() {
    case "${DISTRO_FAMILY}" in
        "debian")
            apt-get update && apt-get upgrade -y
            ;;
        "redhat")
            if utils::has dnf; then
                dnf check-update && dnf upgrade -y
            else
                yum check-update && yum update -y
            fi
            ;;
        "arch")
            pacman -Syu --noconfirm
            ;;
        "suse")
            zypper refresh && zypper update -y
            ;;
        "alpine")
            apk update && apk upgrade
            ;;
        *)
            log::warn "Unknown distribution family: ${DISTRO_FAMILY}"
            return 1
            ;;
    esac
}

# @description Search for a package on any system / Поиск пакета в любой системе
# @param $1 Package name / Имя пакета
# @example
#   system::distrologic::pkg_search_cross "curl"
system::distrologic::pkg_search_cross() {
    local package="${1}"
    
    case "${DISTRO_FAMILY}" in
        "debian")
            apt-cache search "${package}"
            ;;
        "redhat")
            if utils::has dnf; then
                dnf search "${package}"
            else
                yum search "${package}"
            fi
            ;;
        "arch")
            pacman -Ss "${package}"
            ;;
        "suse")
            zypper search "${package}"
            ;;
        "alpine")
            apk search "${package}"
            ;;
        *)
            log::warn "Unknown distribution family: ${DISTRO_FAMILY}"
            return 1
            ;;
    esac
}

# @description Clean package cache on any system / Очистить кэш пакетов в любой системе
# @example
#   system::distrologic::pkg_clean_all
system::distrologic::pkg_clean_all() {
    case "${DISTRO_FAMILY}" in
        "debian")
            apt-get autoremove -y && apt-get autoclean
            ;;
        "redhat")
            if utils::has dnf; then
                dnf autoremove -y && dnf clean all
            else
                yum autoremove -y && yum clean all
            fi
            ;;
        "arch")
            pacman -Sc --noconfirm
            ;;
        "suse")
            zypper clean --all
            ;;
        "alpine")
            apk cache clean
            ;;
        *)
            log::warn "Unknown distribution family: ${DISTRO_FAMILY}"
            return 1
            ;;
    esac
}

# @description Detect service manager used by the system / Определить менеджер сервисов,
# используемый системой
# @example
#   manager=$(system::distrologic::service_manager_detect)
system::distrologic::service_manager_detect() {
    if utils::has systemctl; then
        echo "systemd"
    elif [[ -d /etc/init.d ]]; then
        echo "sysvinit"
    elif utils::has initctl; then
        echo "upstart"
    elif utils::has rc-service; then
        echo "openrc"
    else
        echo "unknown"
    fi
}

# @description Manage service using systemd / Управление сервисом с помощью systemd
# @param $1 Service name / Имя сервиса
# @param $2 Action (start|stop|restart|status|enable|disable) / Действие
# @example
#   system::distrologic::service_manage_systemd "nginx" "start"
system::distrologic::service_manage_systemd() {
    local service="${1}"
    local action="${2}"
    
    if [[ "$(system::distrologic::service_manager_detect)" == "systemd" ]]; then
        systemctl "${action}" "${service}"
    else
        log::warn "systemd not available"
        return 1
    fi
}

# @description Manage service using SysV init / Управление сервисом с помощью SysV init
# @param $1 Service name / Имя сервиса
# @param $2 Action (start|stop|restart|status) / Действие
# @example
#   system::distrologic::service_manage_sysvinit "nginx" "start"
system::distrologic::service_manage_sysvinit() {
    local service="${1}"
    local action="${2}"
    
    if [[ -f "/etc/init.d/${service}" ]]; then
        "/etc/init.d/${service}" "${action}"
    else
        log::warn "Service ${service} not found in /etc/init.d/"
        return 1
    fi
}

# @description Manage service using OpenRC / Управление сервисом с помощью OpenRC
# @param $1 Service name / Имя сервиса
# @param $2 Action (start|stop|restart|status|enable|disable) / Действие
# @example
#   system::distrologic::service_manage_openrc "nginx" "start"
system::distrologic::service_manage_openrc() {
    local service="${1}"
    local action="${2}"
    
    if utils::has rc-service; then
        rc-service "${service}" "${action}"
        if [[ "${action}" == "enable" ]] || [[ "${action}" == "disable" ]]; then
            rc-update "${action}" "${service}"
        fi
    else
        log::warn "OpenRC not available"
        return 1
    fi
}

# @description Mask a service (make it impossible to start) / Замаскировать сервис
# (сделать невозможным запуск)
# @param $1 Service name / Имя сервиса
# @example
#   system::distrologic::service_mask "unwanted-service"
system::distrologic::service_mask() {
    local service="${1}"
    
    if [[ "$(system::distrologic::service_manager_detect)" == "systemd" ]]; then
        systemctl mask "${service}"
    else
        log::warn "Service masking only supported with systemd"
        return 1
    fi
}

# @description Unmask a service / Снять маску с сервиса
# @param $1 Service name / Имя сервиса
# @example
#   system::distrologic::service_unmask "unwanted-service"
system::distrologic::service_unmask() {
    local service="${1}"
    
    if [[ "$(system::distrologic::service_manager_detect)" == "systemd" ]]; then
        systemctl unmask "${service}"
    else
        log::warn "Service unmasking only supported with systemd"
        return 1
    fi
}

# @description Configure network using NetworkManager (nmcli) / Настроить сеть с помощью
# NetworkManager (nmcli)
# @param $@ nmcli arguments / Аргументы nmcli
# @example
# system::distrologic::network_configure_nmcli "con modify" "eth0"
# "connection.autoconnect" "yes"
system::distrologic::network_configure_nmcli() {
    if utils::has nmcli; then
        nmcli "$@"
    else
        log::warn "nmcli not available"
        return 1
    fi
}

# @description Configure network using netplan / Настроить сеть с помощью netplan
# @param $1 Netplan configuration file path / Путь к файлу конфигурации netplan
# @example
#   system::distrologic::network_configure_netplan "/etc/netplan/01-config.yaml"
system::distrologic::network_configure_netplan() {
    local config_file="${1}"
    
    if utils::has netplan; then
        if [[ -f "${config_file}" ]]; then
            netplan apply
        else
            log::warn "Netplan config file not found: ${config_file}"
            return 1
        fi
    else
        log::warn "netplan not available"
        return 1
    fi
}

# @description Configure SELinux / Настроить SELinux
# @param $1 SELinux command (setenforce, restorecon, etc.) / Команда SELinux
# @param $@ Additional arguments / Дополнительные аргументы
# @example
#   system::distrologic::security_configure_selinux "setenforce" "0"
system::distrologic::security_configure_selinux() {
    local cmd="${1}"
    shift
    
    if utils::has "se${cmd}"; then
        "se${cmd}" "$@"
    elif [[ -f /usr/sbin/sestatus ]] && [[ "${cmd}" == "setenforce" ]]; then
        /usr/sbin/sestatus -v | grep -q "SELinux status:.*enabled" && /usr/sbin/setenforce "$@"
    else
        log::warn "SELinux command 'se${cmd}' not available"
        return 1
    fi
}

# @description Configure AppArmor / Настроить AppArmor
# @param $1 Action (enable|disable|complain|enforce) / Действие
# @param $2 Profile name (optional) / Имя профиля (опционально)
# @example
#   system::distrologic::security_configure_apparmor "enforce" "nginx"
system::distrologic::security_configure_apparmor() {
    local action="${1}"
    local profile="${2:-}"
    
    if utils::has apparmor_parser; then
        case "${action}" in
            "enable")
                if [[ -n "${profile}" ]]; then
                    utils::quiet_err ln -s "/etc/apparmor.d/${profile}" "/etc/apparmor.d/force-enabled/${profile}" || :
                fi
                systemctl start apparmor
                ;;
            "disable")
                if [[ -n "${profile}" ]]; then
                    utils::quiet_err rm -f "/etc/apparmor.d/force-enabled/${profile}" || :
                fi
                ;;
            "complain")
                if [[ -n "${profile}" ]]; then
                    aa-complain "${profile}"
                fi
                ;;
            "enforce")
                if [[ -n "${profile}" ]]; then
                    aa-enforce "${profile}"
                fi
                ;;
            *)
                log::warn "Unknown AppArmor action: ${action}"
                return 1
                ;;
        esac
    else
        log::warn "AppArmor not available"
        return 1
    fi
}

# @description Configure firewall using firewalld / Настроить firewall с помощью firewalld
# @param $@ firewall-cmd arguments / Аргументы firewall-cmd
# @example
#   system::distrologic::security_firewalld_setup "--permanent" "--add-port=80/tcp"
system::distrologic::security_firewalld_setup() {
    if utils::has firewall-cmd; then
        firewall-cmd "$@"
        if [[ "$*" == *"--permanent"* ]]; then
            firewall-cmd --reload
        fi
    else
        log::warn "firewall-cmd not available"
        return 1
    fi
}

# @description Configure firewall using UFW / Настроить firewall с помощью UFW
# @param $@ UFW arguments / Аргументы UFW
# @example
#   system::distrologic::security_ufw_setup "allow" "80/tcp"
system::distrologic::security_ufw_setup() {
    if utils::has ufw; then
        ufw "$@"
    else
        log::warn "ufw not available"
        return 1
    fi
}

# @description Configure firewall using iptables / Настроить firewall с помощью iptables
# @param $@ iptables arguments / Аргументы iptables
# @example
# system::distrologic::security_iptables_setup "-A" "INPUT" "-p" "tcp" "--dport" "80"
# "-j" "ACCEPT"
system::distrologic::security_iptables_setup() {
    if utils::has iptables; then
        iptables "$@"
    else
        log::warn "iptables not available"
        return 1
    fi
}

# @description Configure timezone / Настроить часовой пояс
# @param $1 Timezone (e.g., "Europe/Moscow") / Часовой пояс
# @example
#   system::distrologic::time_sync_systemd "Europe/Moscow"
system::distrologic::time_sync_systemd() {
    local timezone="${1}"
    
    if utils::has timedatectl; then
        timedatectl set-timezone "${timezone}"
    else
        log::warn "timedatectl not available"
        return 1
    fi
}

# @description Sync hardware clock / Синхронизировать аппаратные часы
# @example
#   system::distrologic::hwclock_sync
system::distrologic::hwclock_sync() {
    if utils::has hwclock; then
        # Sync hardware clock to system clock
        hwclock --systohc
    else
        log::warn "hwclock not available"
        return 1
    fi
}

# @description Configure sudo / Настроить sudo
# @param $1 Username / Имя пользователя
# @example
#   system::distrologic::sudo_configure "username"
system::distrologic::sudo_configure() {
    local username="${1}"
    
    if utils::has usermod; then
        case "${DISTRO_FAMILY}" in
            "debian")
                usermod -aG sudo "${username}"
                ;;
            "redhat")
                usermod -aG wheel "${username}"
                ;;
            *)
                log::warn "Automatic sudo group configuration not supported for ${DISTRO_FAMILY}"
                return 1
                ;;
        esac
    else
        log::warn "usermod not available"
        return 1
    fi
}

# @description Configure system limits via sysctl / Настроить системные лимиты через
# sysctl
# @param $1 Parameter name / Имя параметра
# @param $2 Parameter value / Значение параметра
# @example
#   system::distrologic::sysctl_configure "net.core.somaxconn" "1024"
system::distrologic::sysctl_configure() {
    local param="${1}"
    local value="${2}"
    
    if utils::has sysctl; then
        sysctl -w "${param}=${value}"
    else
        log::warn "sysctl not available"
        return 1
    fi
}

# @description Make sysctl parameter persistent / Сделать параметр sysctl постоянным
# @param $1 Parameter name / Имя параметра
# @param $2 Parameter value / Значение параметра
# @example
#   system::distrologic::sysctl_persist "net.core.somaxconn" "1024"
system::distrologic::sysctl_persist() {
    local param="${1}"
    local value="${2}"
    local config_file="/etc/sysctl.conf"
    
    # Add to sysctl.conf to persist after reboot (idempotent) / Добавить в sysctl.conf
    # для сохранения после перезагрузки (идемпотентно)
    local line="${param} = ${value}"
    if [[ -f "${config_file}" ]] && utils::quiet_err grep -Fqx "${line}" "${config_file}"; then
        log::info "sysctl parameter already persistent: ${line}"
        return 0
    fi
    echo "${line}" >> "${config_file}"
}

# @description Format filesystem as ext4 / Форматировать файловую систему в ext4
# @param $1 Device path / Путь к устройству
# @example
#   system::distrologic::fs_format_ext4 "/dev/sdb1"
system::distrologic::fs_format_ext4() {
    local device="${1}"
    
    if utils::has mkfs.ext4; then
        mkfs.ext4 "${device}"
    else
        log::warn "mkfs.ext4 not available"
        return 1
    fi
}

# @description Format filesystem as XFS / Форматировать файловую систему в XFS
# @param $1 Device path / Путь к устройству
# @example
#   system::distrologic::fs_format_xfs "/dev/sdb1"
system::distrologic::fs_format_xfs() {
    local device="${1}"
    
    if utils::has mkfs.xfs; then
        mkfs.xfs "${device}"
    else
        log::warn "mkfs.xfs not available"
        return 1
    fi
}

# @description Check filesystem / Проверить файловую систему
# @param $1 Device path / Путь к устройству
# @example
#   system::distrologic::fs_check "/dev/sdb1"
system::distrologic::fs_check() {
    local device="${1}"
    
    # Determine filesystem type / Определить тип файловой системы
    local fs_type=""
    if utils::has blkid; then
        fs_type=$(utils::quiet_err blkid -o value -s TYPE "${device}")
    fi
    # Fallback to findmnt / Резервный вариант findmnt
    if [[ -z "${fs_type}" ]] && utils::has findmnt; then
        fs_type=$(utils::quiet_err findmnt -n -o FSTYPE "${device}")
    fi
    # Fallback to df -T / Резервный вариант df -T
    if [[ -z "${fs_type}" ]]; then
        fs_type=$(utils::quiet_err df -T "${device}" | awk 'NR==2 {print $2}')
    fi
    
    case "${fs_type}" in
        ext2|ext3|ext4)
            if utils::has "fsck.${fs_type}"; then
                "fsck.${fs_type}" -f "${device}"
            else
                log::warn "e2fsck not available"
                return 1
            fi
            ;;
        xfs)
            if utils::has xfs_repair; then
                xfs_repair "${device}"
            else
                log::warn "xfs_repair not available"
                return 1
            fi
            ;;
        btrfs)
            if utils::has btrfs; then
                btrfs check "${device}"
            else
                log::warn "btrfs not available"
                return 1
            fi
            ;;
        *)
            if [[ -n "${fs_type}" ]]; then
                log::warn "Unknown filesystem type '${fs_type}', using generic fsck"
            fi
            if utils::has fsck; then
                fsck -f "${device}"
            else
                log::warn "fsck not available"
                return 1
            fi
            ;;
    esac
}

# @description Install packages based on current distribution / Установить пакеты в
# зависимости от текущего дистрибутива
# @param $@ Package names / Имена пакетов
# @example
#   system::distrologic::pkg_install_cross "curl" "wget"
system::distrologic::pkg_install_cross() {
    case "${DISTRO_FAMILY}" in
        "debian")
            system::distro::install_package "$@"
            ;;
        "redhat")
            system::distro::install_package "$@"
            ;;
        "arch")
            pacman -S --noconfirm "$@"
            ;;
        "suse")
            zypper install -y "$@"
            ;;
        "alpine")
            apk add "$@"
            ;;
        *)
            log::warn "Unsupported distribution family: ${DISTRO_FAMILY}"
            return 1
            ;;
    esac
}