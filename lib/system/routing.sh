#!/usr/bin/env bs
# shellcheck shell=bash
# routing.sh — Routing table configuration for system setup
# @depends core/const, core/logger, core/utils, lib/io/files

# Source Guard / Защита от повторной загрузки
bs::guard "SYSTEM_ROUTING" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "../io/files.sh"

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
    
    if is::empty "${destination}" || is::empty "${gateway}"; then
        log::warn "Destination network and gateway must be specified"
        return "${E_ERROR}"
    fi
    
    # Using ip command (modern approach)
    if utils::has ip; then
        if is::not_empty "${interface}"; then
            utils::attempt ip route add "${destination}" via "${gateway}" dev "${interface}"
        else
            utils::attempt ip route add "${destination}" via "${gateway}"
        fi
        log::info "Static route added: ${destination} via ${gateway}"
    else
        # Fallback to route command
        if is::not_empty "${interface}"; then
            utils::attempt route add -net "${destination}" gw "${gateway}" dev "${interface}"
        else
            utils::attempt route add -net "${destination}" gw "${gateway}"
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
    
    if is::empty "${destination}"; then
        log::warn "Destination network must be specified"
        return "${E_ERROR}"
    fi
    
    # Using ip command (modern approach)
    if utils::has ip; then
        if is::not_empty "${gateway}"; then
            utils::attempt ip route del "${destination}" via "${gateway}"
        else
            utils::attempt ip route del "${destination}"
        fi
        log::info "Static route deleted: ${destination}"
    else
        # Fallback to route command
        if is::not_empty "${gateway}"; then
            utils::attempt route del -net "${destination}" gw "${gateway}"
        else
            utils::attempt route del -net "${destination}"
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
    
    if is::empty "${gateway}"; then
        log::warn "Gateway IP must be specified"
        return "${E_ERROR}"
    fi
    
    # Using ip command (modern approach)
    if utils::has ip; then
        # Delete existing default route
        utils::attempt ip route del default
        
        # Add new default route
        if is::not_empty "${interface}"; then
            utils::attempt ip route add default via "${gateway}" dev "${interface}"
        else
            utils::attempt ip route add default via "${gateway}"
        fi
        log::info "Default gateway set to ${gateway}"
    else
        # Fallback to route command
        # Delete existing default route
        utils::attempt route del default
        
        # Add new default route
        if is::not_empty "${interface}"; then
            utils::attempt route add default gw "${gateway}" dev "${interface}"
        else
            utils::attempt route add default gw "${gateway}"
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
        utils::attempt ip route show
    else
        # Fallback to route command
        utils::attempt route -n
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
    
    if is::empty "${table}"; then
        log::warn "Routing table name or number must be specified"
        return "${E_ERROR}"
    fi
    
    case "${action}" in
        add)
            # Add routing table entry to /etc/iproute2/rt_tables
            if is::writable "/etc/iproute2/rt_tables"; then
                # Check if table already exists
                if ! utils::quiet_err grep -q "^${table} " /etc/iproute2/rt_tables; then
                    io::files::append /etc/iproute2/rt_tables "${table} custom"
                    log::info "Routing table ${table} added"
                else
                    log::info "Routing table ${table} already exists"
                fi
            else
                log::warn "Cannot write to /etc/iproute2/rt_tables"
                return "${E_ERROR}"
            fi
            ;;
        delete)
            # Remove routing table entry from /etc/iproute2/rt_tables
            if is::writable "/etc/iproute2/rt_tables"; then
                utils::attempt sed -i "/^${table} /d" /etc/iproute2/rt_tables
                log::info "Routing table ${table} removed"
            else
                log::warn "Cannot write to /etc/iproute2/rt_tables"
                return "${E_ERROR}"
            fi
            ;;
        show)
            # Show routing table
            if utils::has ip; then
                utils::attempt ip route show table "${table}"
            else
                log::warn "ip command not available"
                return "${E_ERROR}"
            fi
            ;;
        *)
            log::warn "Unknown action: ${action}"
            return "${E_ERROR}"
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
    
    if is::empty "${rule}"; then
        log::warn "Routing rule must be specified"
        return "${E_ERROR}"
    fi
    
    case "${action}" in
        add)
            # Add policy routing rule
            if utils::has ip; then
                utils::attempt ip rule add ${rule}
                log::info "Policy routing rule added: ${rule}"
            else
                log::warn "ip command not available"
                return "${E_ERROR}"
            fi
            ;;
        delete)
            # Delete policy routing rule
            if utils::has ip; then
                utils::attempt ip rule del ${rule}
                log::info "Policy routing rule deleted: ${rule}"
            else
                log::warn "ip command not available"
                return "${E_ERROR}"
            fi
            ;;
        *)
            log::warn "Unknown action: ${action}"
            return "${E_ERROR}"
            ;;
    esac
}

# @description Show policy routing rules
# @example
#   system::routing::rules
system::routing::rules() {
    # Show policy routing rules
    if utils::has ip; then
        utils::attempt ip rule show
    else
        log::warn "ip command not available"
        return "${E_ERROR}"
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
            if is::writable "/proc/sys/net/ipv6/conf/all/forwarding"; then
                utils::attempt echo 1 > /proc/sys/net/ipv6/conf/all/forwarding
                log::info "IPv6 routing enabled"
            else
                log::warn "Cannot write to /proc/sys/net/ipv6/conf/all/forwarding"
                return "${E_ERROR}"
            fi
            ;;
        disable)
            # Disable IPv6 forwarding
            if is::writable "/proc/sys/net/ipv6/conf/all/forwarding"; then
                utils::attempt echo 0 > /proc/sys/net/ipv6/conf/all/forwarding
                log::info "IPv6 routing disabled"
            else
                log::warn "Cannot write to /proc/sys/net/ipv6/conf/all/forwarding"
                return "${E_ERROR}"
            fi
            ;;
        *)
            log::warn "Unknown action: ${action}"
            return "${E_ERROR}"
            ;;
    esac
}
