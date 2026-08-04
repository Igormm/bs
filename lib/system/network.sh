#!/usr/bin/env bs
# network.sh — Network configuration for system setup / Конфигурация сети для настройки
# системы
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/guard.sh"
bs::guard "SYSTEM_NETWORK" || return 0

# Зависимости / Dependencies
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/const.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/logger.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/utils.sh"

# @description Configure network interface / Настроить сетевой интерфейс
# @param $1 Interface name (e.g., "eth0", "wlan0") / Имя интерфейса (например, "eth0",
# "wlan0")
# @param $2 Action ("up", "down", "restart") / Действие ("up", "down", "restart")
# @example
#   system::network::interface "eth0" "up"
system::network::interface() {
    local interface="${1}"
    local action="${2:-up}"
    
    if [[ -z "${interface}" ]]; then
        log::warn "Interface name not specified"
        return 1
    fi
    
    # Using ip command (modern approach) / Использование команды ip (современный подход)
    if utils::has ip; then
        case "${action}" in
            up)
                utils::quiet_err ip link set "${interface}" up || true
                log::info "Interface ${interface} brought up"
                ;;
            down)
                utils::quiet_err ip link set "${interface}" down || true
                log::info "Interface ${interface} brought down"
                ;;
            restart)
                utils::quiet_err ip link set "${interface}" down || true
                sleep 1
                utils::quiet_err ip link set "${interface}" up || true
                log::info "Interface ${interface} restarted"
                ;;
            *)
                log::warn "Unknown action: ${action}"
                return 1
                ;;
        esac
    else
        # Fallback to ifconfig / Резервный вариант ifconfig
        case "${action}" in
            up)
                utils::quiet_err ifconfig "${interface}" up || true
                log::info "Interface ${interface} brought up"
                ;;
            down)
                utils::quiet_err ifconfig "${interface}" down || true
                log::info "Interface ${interface} brought down"
                ;;
            restart)
                utils::quiet_err ifconfig "${interface}" down || true
                sleep 1
                utils::quiet_err ifconfig "${interface}" up || true
                log::info "Interface ${interface} restarted"
                ;;
            *)
                log::warn "Unknown action: ${action}"
                return 1
                ;;
        esac
    fi
}

# @description Set static IP address for an interface / Установить статический IP адрес
# для интерфейса
# @param $1 Interface name / Имя интерфейса
# @param $2 IP address with CIDR (e.g., "192.168.1.100/24") / IP адрес с CIDR (например,
# "192.168.1.100/24")
# @example
#   system::network::static_ip "eth0" "192.168.1.100/24"
system::network::static_ip() {
    local interface="${1}"
    local ip_address="${2}"
    
    if [[ -z "${interface}" ]] || [[ -z "${ip_address}" ]]; then
        log::warn "Interface name and IP address must be specified"
        return 1
    fi
    
    # Using ip command / Использование команды ip
    if utils::has ip; then
        utils::quiet_err ip addr add "${ip_address}" dev "${interface}" || true
        log::info "Static IP ${ip_address} assigned to ${interface}"
    else
        # Fallback to ifconfig / Резервный вариант ifconfig
        # Extract IP and netmask from CIDR / Извлечь IP и маску сети из CIDR
        local ip=$(echo "${ip_address}" | cut -d'/' -f1)
        local cidr=$(echo "${ip_address}" | cut -d'/' -f2)
        
        # Convert CIDR to netmask (simplified) / Преобразовать CIDR в маску сети
        # (упрощенно)
        local netmask="255.255.255.0"
        if [[ "${cidr}" -eq 16 ]]; then
            netmask="255.255.0.0"
        elif [[ "${cidr}" -eq 8 ]]; then
            netmask="255.0.0.0"
        fi
        
        utils::quiet_err ifconfig "${interface}" "${ip}" netmask "${netmask}" || true
        log::info "Static IP ${ip} with netmask ${netmask} assigned to ${interface}"
    fi
}

# @description Set default gateway / Установить шлюз по умолчанию
# @param $1 Gateway IP address / IP адрес шлюза
# @example
#   system::network::gateway "192.168.1.1"
system::network::gateway() {
    local gateway="${1}"
    
    if [[ -z "${gateway}" ]]; then
        log::warn "Gateway IP address not specified"
        return 1
    fi
    
    # Using ip command / Использование команды ip
    if utils::has ip; then
        utils::quiet_err ip route add default via "${gateway}" || true
        log::info "Default gateway set to ${gateway}"
    else
        # Fallback to route / Резервный вариант route
        utils::quiet_err route add default gw "${gateway}" || true
        log::info "Default gateway set to ${gateway}"
    fi
}

# @description Configure DNS servers / Настроить DNS серверы
# @param $@ DNS server IP addresses / IP адреса DNS серверов
# @example
#   system::network::dns "8.8.8.8" "8.8.4.4"
system::network::dns() {
    if [[ $# -eq 0 ]]; then
        log::warn "At least one DNS server must be specified"
        return 1
    fi
    
    # Create or overwrite resolv.conf / Создать или перезаписать resolv.conf
    local resolv_conf="/etc/resolv.conf"
    if [[ -w "${resolv_conf}" ]]; then
        # Clear existing nameservers / Очистить существующие nameserver
        utils::quiet_err sed -i '/^nameserver/d' "${resolv_conf}" || true
        
        # Add new nameservers / Добавить новые nameserver
        for dns in "$@"; do
            echo "nameserver ${dns}" >> "${resolv_conf}"
        done
        
        log::info "DNS servers configured: $*"
    else
        log::warn "Cannot write to ${resolv_conf}"
        return 1
    fi
}

# @description List network interfaces / Показать сетевые интерфейсы
# @example
#   system::network::list_interfaces
system::network::list_interfaces() {
    if utils::has ip; then
        utils::quiet_err ip link show | awk -F': ' '/^[0-9]+: / {print $2}' | grep -v 'lo'
    else
        # Fallback to ifconfig / Резервный вариант ifconfig
        utils::quiet_err ifconfig -a | awk '/^[a-zA-Z]/ {print $1}' | grep -v 'lo' | sed 's/://'
    fi
}

# @description Show network interface status / Показать статус сетевого интерфейса
# @param $1 Interface name / Имя интерфейса
# @example
#   system::network::status "eth0"
system::network::status() {
    local interface="${1:-}"
    
    if [[ -n "${interface}" ]]; then
        if utils::has ip; then
            utils::quiet_err ip addr show "${interface}" || true
        else
            utils::quiet_err ifconfig "${interface}" || true
        fi
    else
        if utils::has ip; then
            utils::quiet_err ip addr show || true
        else
            utils::quiet_err ifconfig || true
        fi
    fi
}