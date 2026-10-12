#!/usr/bin/env bs
# shellcheck shell=bash
# routing.sh — Routing table configuration for system setup
# @depends core/const, core/logger, core/utils, lib/io/files

# Source Guard / Защита от повторной загрузки
bs::guard "SYSTEM_ROUTING" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "../io/files.sh" "../data/format.sh"

# @private Run a routing command; log its output on failure (success is silent)
# @private Выполнить команду маршрутизации; при ошибке записать её вывод (успех молчит)
# @param $@ Command and arguments / Команда и аргументы
# @return 0 on success, E_ERROR otherwise / 0 при успехе, иначе E_ERROR
system::routing::__run() {
    local out
    if out="$("$@" 2>&1)"; then
        return 0
    fi
    log::error "Command failed / Команда не удалась: $* ${out:+(${out})}"
    return "${E_ERROR}"
}

# @description Add static route
# @param $1 Destination network (e.g., "192.168.2.0/24")
# @param $2 Gateway IP (e.g., "192.168.1.1")
# @param $3 Interface name (optional)
# @example
#   system::routing::add "192.168.2.0/24" "192.168.1.1" "eth0"
system::routing::add() {
    local destination="${1:-}"
    local gateway="${2:-}"
    local interface="${3:-}"
    
    if is::empty "${destination}" || is::empty "${gateway}"; then
        log::warn "Destination network and gateway must be specified"
        return "${E_ERROR}"
    fi
    
    # Using ip command (modern approach)
    if utils::has ip; then
        if is::not_empty "${interface}"; then
            system::routing::__run ip route add "${destination}" via "${gateway}" dev "${interface}" || return "${E_ERROR}"
        else
            system::routing::__run ip route add "${destination}" via "${gateway}" || return "${E_ERROR}"
        fi
        log::info "Static route added: ${destination} via ${gateway}"
    else
        # Fallback to route command
        if is::not_empty "${interface}"; then
            system::routing::__run route add -net "${destination}" gw "${gateway}" dev "${interface}" || return "${E_ERROR}"
        else
            system::routing::__run route add -net "${destination}" gw "${gateway}" || return "${E_ERROR}"
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
    local destination="${1:-}"
    local gateway="${2:-}"
    
    if is::empty "${destination}"; then
        log::warn "Destination network must be specified"
        return "${E_ERROR}"
    fi
    
    # Using ip command (modern approach)
    if utils::has ip; then
        if is::not_empty "${gateway}"; then
            system::routing::__run ip route del "${destination}" via "${gateway}" || return "${E_ERROR}"
        else
            system::routing::__run ip route del "${destination}" || return "${E_ERROR}"
        fi
        log::info "Static route deleted: ${destination}"
    else
        # Fallback to route command
        if is::not_empty "${gateway}"; then
            system::routing::__run route del -net "${destination}" gw "${gateway}" || return "${E_ERROR}"
        else
            system::routing::__run route del -net "${destination}" || return "${E_ERROR}"
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
    local gateway="${1:-}"
    local interface="${2:-}"
    
    if is::empty "${gateway}"; then
        log::warn "Gateway IP must be specified"
        return "${E_ERROR}"
    fi
    
    # Using ip command (modern approach)
    if utils::has ip; then
        # replace — атомарно: при неверном шлюзе прежний маршрут по умолчанию
        # не теряется (del + add оставлял систему без маршрута)
        # replace is atomic: with a bad gateway the previous default route is
        # kept (del + add left the system without a route)
        if is::not_empty "${interface}"; then
            system::routing::__run ip route replace default via "${gateway}" dev "${interface}" || return "${E_ERROR}"
        else
            system::routing::__run ip route replace default via "${gateway}" || return "${E_ERROR}"
        fi
        log::info "Default gateway set to ${gateway}"
    else
        # Fallback to route command
        # Delete existing default route
        # Старого маршрута может не быть: удаление — best-effort
        # There may be no old route: the removal is best-effort
        utils::attempt route del default
        
        # Add new default route
        if is::not_empty "${interface}"; then
            system::routing::__run route add default gw "${gateway}" dev "${interface}" || return "${E_ERROR}"
        else
            system::routing::__run route add default gw "${gateway}" || return "${E_ERROR}"
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
        utils::attempt ip route show | format::emit_lines route
    else
        # Fallback to route command
        utils::attempt route -n | format::emit_lines route
    fi
}

# @description Configure routing table
# @param $1 Table name or number
# @param $2 Action ("add", "delete", "show")
# @example
#   system::routing::table "100" "show"
system::routing::table() {
    local table="${1:-}"
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
                case "${table}" in
                    0|253|254|255|unspec|default|main|local)
                        log::error "Reserved routing table can not be removed: ${table}"
                        return "${E_ERROR}"
                        ;;
                esac
                # Точное совпадение первого поля (число или имя), не regex
                # Exact match of the first field (number or name), not a regex
                local rt_tmp
                rt_tmp="$(mktemp)" || return "${E_ERROR}"
                if ! awk -v t="${table}" '/^#/ || ($1 != t && $2 != t)' /etc/iproute2/rt_tables > "${rt_tmp}" \
                    || ! cat -- "${rt_tmp}" > /etc/iproute2/rt_tables; then
                    utils::ignore rm -f -- "${rt_tmp}"
                    log::error "Failed to update /etc/iproute2/rt_tables"
                    return "${E_ERROR}"
                fi
                utils::ignore rm -f -- "${rt_tmp}"
                log::info "Routing table ${table} removed"
            else
                log::warn "Cannot write to /etc/iproute2/rt_tables"
                return "${E_ERROR}"
            fi
            ;;
        show)
            # Show routing table
            if utils::has ip; then
                utils::attempt ip route show table "${table}" | format::emit_lines route
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
    local rule="${1:-}"
    local action="${2:-add}"
    
    if is::empty "${rule}"; then
        log::warn "Routing rule must be specified"
        return "${E_ERROR}"
    fi

    # Делим правило по пробелам явно: в bs run IFS = перевод строки/табуляция,
    # и неявное деление "${rule}" оставило бы одно слово
    # Split the rule on spaces explicitly: in bs run IFS is newline/tab, and
    # implicit splitting of "${rule}" would leave a single word
    local -a rule_args=()
    IFS=' ' read -ra rule_args <<< "${rule}"
    
    case "${action}" in
        add)
            # Add policy routing rule
            if utils::has ip; then
                system::routing::__run ip rule add "${rule_args[@]}" || return "${E_ERROR}"
                log::info "Policy routing rule added: ${rule}"
            else
                log::warn "ip command not available"
                return "${E_ERROR}"
            fi
            ;;
        delete)
            # Delete policy routing rule
            if utils::has ip; then
                system::routing::__run ip rule del "${rule_args[@]}" || return "${E_ERROR}"
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
        utils::attempt ip rule show | format::emit_lines rule
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
