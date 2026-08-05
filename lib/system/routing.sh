#!/usr/bin/env bs
# shellcheck shell=bash
# routing.sh — Routing table configuration for system setup
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/guard.sh"
bs::guard "SYSTEM_ROUTING" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# @description Add static route
# @param $1 Destination network (e.g., "192.168.2.0/24")
# @param $2 Gateway IP (e.g., "192.168.1.1")
# @param $3 Interface name (optional)
# @example
#   system::routing::add "192.168.2.0/24" "192.168.1.1" "eth0"
system::routing::add() {
    local destination="${1}"
    local gateway="${2}"
    local interface="${3}"
    
    if [[ -z "${destination}" ]] || [[ -z "${gateway}" ]]; then
        log::warn "Destination network and gateway must be specified"
        return 1
    fi
    
    # Using ip command (modern approach)
    if utils::has ip; then
        if [[ -n "${interface}" ]]; then
            utils::quiet_err ip route add "${destination}" via "${gateway}" dev "${interface}" || true
        else
            utils::quiet_err ip route add "${destination}" via "${gateway}" || true
        fi
        log::info "Static route added: ${destination} via ${gateway}"
    else
        # Fallback to route command
        if [[ -n "${interface}" ]]; then
            utils::quiet_err route add -net "${destination}" gw "${gateway}" dev "${interface}" || true
        else
            utils::quiet_err route add -net "${destination}" gw "${gateway}" || true
        fi
        log::info "Static route added: ${destination} via ${gateway}"
    fi
}

# @description Delete static route
# @param $1 Destination network (e.g., "192.168.2.0/24")
# @param $2 Gateway IP (optional)
# @example
#   system::routing::delete "192.168.2.0/24" "192.168.1.1"
system::routing::delete() {
    local destination="${1}"
    local gateway="${2}"
    
    if [[ -z "${destination}" ]]; then
        log::warn "Destination network must be specified"
        return 1
    fi
    
    # Using ip command (modern approach)
    if utils::has ip; then
        if [[ -n "${gateway}" ]]; then
            utils::quiet_err ip route del "${destination}" via "${gateway}" || true
        else
            utils::quiet_err ip route del "${destination}" || true
        fi
        log::info "Static route deleted: ${destination}"
    else
        # Fallback to route command
        if [[ -n "${gateway}" ]]; then
            utils::quiet_err route del -net "${destination}" gw "${gateway}" || true
        else
            utils::quiet_err route del -net "${destination}" || true
        fi
        log::info "Static route deleted: ${destination}"
    fi
}

# @description Set default gateway
# @param $1 Gateway IP (e.g., "192.168.1.1")
# @param $2 Interface name (optional)
# @example
#   system::routing::default "192.168.1.1" "eth0"
system::routing::default() {
    local gateway="${1}"
    local interface="${2}"
    
    if [[ -z "${gateway}" ]]; then
        log::warn "Gateway IP must be specified"
        return 1
    fi
    
    # Using ip command (modern approach)
    if utils::has ip; then
        # Delete existing default route
        utils::quiet_err ip route del default || true
        
        # Add new default route
        if [[ -n "${interface}" ]]; then
            utils::quiet_err ip route add default via "${gateway}" dev "${interface}" || true
        else
            utils::quiet_err ip route add default via "${gateway}" || true
        fi
        log::info "Default gateway set to ${gateway}"
    else
        # Fallback to route command
        # Delete existing default route
        utils::quiet_err route del default || true
        
        # Add new default route
        if [[ -n "${interface}" ]]; then
            utils::quiet_err route add default gw "${gateway}" dev "${interface}" || true
        else
            utils::quiet_err route add default gw "${gateway}" || true
        fi
        log::info "Default gateway set to ${gateway}"
    fi
}

# @description Show routing table
# @example
#   system::routing::show
system::routing::show() {
    # Using ip command (modern approach)
    if utils::has ip; then
        utils::quiet_err ip route show || true
    else
        # Fallback to route command
        utils::quiet_err route -n || true
    fi
}

# @description Configure routing table
# @param $1 Table name or number
# @param $2 Action ("add", "delete", "show")
# @example
#   system::routing::table "100" "show"
system::routing::table() {
    local table="${1}"
    local action="${2:-show}"
    
    if [[ -z "${table}" ]]; then
        log::warn "Routing table name or number must be specified"
        return 1
    fi
    
    case "${action}" in
        add)
            # Add routing table entry to /etc/iproute2/rt_tables
            if [[ -w "/etc/iproute2/rt_tables" ]]; then
                # Check if table already exists
                if ! utils::quiet_err grep -q "^${table} " /etc/iproute2/rt_tables; then
                    echo "${table} custom" >> /etc/iproute2/rt_tables
                    log::info "Routing table ${table} added"
                else
                    log::info "Routing table ${table} already exists"
                fi
            else
                log::warn "Cannot write to /etc/iproute2/rt_tables"
                return 1
            fi
            ;;
        delete)
            # Remove routing table entry from /etc/iproute2/rt_tables
            if [[ -w "/etc/iproute2/rt_tables" ]]; then
                utils::quiet_err sed -i "/^${table} /d" /etc/iproute2/rt_tables || true
                log::info "Routing table ${table} removed"
            else
                log::warn "Cannot write to /etc/iproute2/rt_tables"
                return 1
            fi
            ;;
        show)
            # Show routing table
            if utils::has ip; then
                utils::quiet_err ip route show table "${table}" || true
            else
                log::warn "ip command not available"
                return 1
            fi
            ;;
        *)
            log::warn "Unknown action: ${action}"
            return 1
            ;;
    esac
}

# @description Configure policy-based routing
# @param $1 Rule description
# @param $2 Action ("add", "delete")
# @example
#   system::routing::policy "from 192.168.1.0/24 table 100" "add"
system::routing::policy() {
    local rule="${1}"
    local action="${2:-add}"
    
    if [[ -z "${rule}" ]]; then
        log::warn "Routing rule must be specified"
        return 1
    fi
    
    case "${action}" in
        add)
            # Add policy routing rule
            if utils::has ip; then
                utils::quiet_err ip rule add ${rule} || true
                log::info "Policy routing rule added: ${rule}"
            else
                log::warn "ip command not available"
                return 1
            fi
            ;;
        delete)
            # Delete policy routing rule
            if utils::has ip; then
                utils::quiet_err ip rule del ${rule} || true
                log::info "Policy routing rule deleted: ${rule}"
            else
                log::warn "ip command not available"
                return 1
            fi
            ;;
        *)
            log::warn "Unknown action: ${action}"
            return 1
            ;;
    esac
}

# @description Show policy routing rules
# @example
#   system::routing::rules
system::routing::rules() {
    # Show policy routing rules
    if utils::has ip; then
        utils::quiet_err ip rule show || true
    else
        log::warn "ip command not available"
        return 1
    fi
}

# @description Configure IPv6 routing
# @param $1 Action ("enable", "disable")
# @example
#   system::routing::ipv6 "enable"
system::routing::ipv6() {
    local action="${1:-enable}"
    
    case "${action}" in
        enable)
            # Enable IPv6 forwarding
            if [[ -w "/proc/sys/net/ipv6/conf/all/forwarding" ]]; then
                utils::quiet_err echo 1 > /proc/sys/net/ipv6/conf/all/forwarding || true
                log::info "IPv6 routing enabled"
            else
                log::warn "Cannot write to /proc/sys/net/ipv6/conf/all/forwarding"
                return 1
            fi
            ;;
        disable)
            # Disable IPv6 forwarding
            if [[ -w "/proc/sys/net/ipv6/conf/all/forwarding" ]]; then
                utils::quiet_err echo 0 > /proc/sys/net/ipv6/conf/all/forwarding || true
                log::info "IPv6 routing disabled"
            else
                log::warn "Cannot write to /proc/sys/net/ipv6/conf/all/forwarding"
                return 1
            fi
            ;;
        *)
            log::warn "Unknown action: ${action}"
            return 1
            ;;
    esac
}
