#!/usr/bin/env bs
# shellcheck shell=bash
# network.sh — Network configuration for system setup / Конфигурация сети для настройки
# системы
# @depends core/const, core/logger, core/utils, lib/io/files

# Source Guard / Защита от повторной загрузки
bs::guard "SYSTEM_NETWORK" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "../io/files.sh" "../data/format.sh"

# @private Run a network command; log success, or the output on failure
# @private Выполнить сетевую команду; записать успех или вывод при ошибке
# @param $1 Success message / Сообщение об успехе
# @param $@ Command and arguments / Команда и аргументы
# @return 0 on success, E_ERROR otherwise / 0 при успехе, иначе E_ERROR
system::network::__run() {
    local -r message="${1:?message required}"
    shift
    local out
    if out="$("$@" 2>&1)"; then
        log::info "${message}"
        return 0
    fi
    log::error "Command failed / Команда не удалась: $* ${out:+(${out})}"
    return "${E_ERROR}"
}

# @private Dotted netmask for a prefix length 0..32
# @private Маска сети в виде a.b.c.d для длины префикса 0..32
# @param $1 Prefix length / Длина префикса
# @stdout Netmask / Маска сети
# @return 0 ok, 1 invalid prefix / 1 неверный префикс
system::network::__netmask() {
    local -r prefix="${1:-}"
    [[ "${prefix}" =~ ^[0-9]+$ ]] || return 1
    local -i bits=$(( 10#${prefix} )) i octet
    (( bits <= 32 )) || return 1
    local -a octets=()
    for (( i = 0; i < 4; i++ )); do
        if (( bits >= 8 )); then
            octet=255; bits=$(( bits - 8 ))
        elif (( bits > 0 )); then
            octet=$(( 256 - (1 << (8 - bits)) )); bits=0
        else
            octet=0
        fi
        octets+=("${octet}")
    done
    printf '%s.%s.%s.%s\n' "${octets[@]}"
}

# @description Configure network interface / Настроить сетевой интерфейс
# @param $1 Interface name (e.g., "eth0", "wlan0") / Имя интерфейса (например, "eth0",
# "wlan0")
# @param $2 Action ("up", "down", "restart") / Действие ("up", "down", "restart")
# @example
#   system::network::interface "eth0" "up"
system::network::interface() {
    local interface="${1:-}"
    local action="${2:-up}"
    
    if is::empty "${interface}"; then
        log::warn "Interface name not specified"
        return "${E_INVALID}"
    fi
    
    # Using ip command (modern approach) / Использование команды ip (современный подход)
    if utils::has ip; then
        case "${action}" in
            up)
                system::network::__run "Interface ${interface} brought up" ip link set "${interface}" up || return "${E_ERROR}"
                ;;
            down)
                system::network::__run "Interface ${interface} brought down" ip link set "${interface}" down || return "${E_ERROR}"
                ;;
            restart)
                utils::attempt ip link set "${interface}" down
                sleep 1
                system::network::__run "Interface ${interface} restarted" ip link set "${interface}" up || return "${E_ERROR}"
                ;;
            *)
                log::warn "Unknown action: ${action}"
                return "${E_INVALID}"
                ;;
        esac
    else
        # Fallback to ifconfig / Резервный вариант ifconfig
        case "${action}" in
            up)
                system::network::__run "Interface ${interface} brought up" ifconfig "${interface}" up || return "${E_ERROR}"
                ;;
            down)
                system::network::__run "Interface ${interface} brought down" ifconfig "${interface}" down || return "${E_ERROR}"
                ;;
            restart)
                utils::attempt ifconfig "${interface}" down
                sleep 1
                system::network::__run "Interface ${interface} restarted" ifconfig "${interface}" up || return "${E_ERROR}"
                ;;
            *)
                log::warn "Unknown action: ${action}"
                return "${E_INVALID}"
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
    local interface="${1:-}"
    local ip_address="${2:-}"
    
    if is::empty "${interface}" || is::empty "${ip_address}"; then
        log::warn "Interface name and IP address must be specified"
        return "${E_INVALID}"
    fi
    
    # Using ip command / Использование команды ip
    if utils::has ip; then
        system::network::__run "Static IP ${ip_address} assigned to ${interface}" ip addr add "${ip_address}" dev "${interface}" || return "${E_ERROR}"
    else
        # Fallback to ifconfig / Резервный вариант ifconfig
        # Extract IP and netmask from CIDR / Извлечь IP и маску сети из CIDR
        local ip=$(echo "${ip_address}" | cut -d'/' -f1)
        local cidr=$(echo "${ip_address}" | cut -d'/' -f2)
        
        # CIDR -> маска сети; без "/N" считаем /24
        # CIDR -> netmask; without "/N" assume /24
        if [[ "${ip_address}" != */* ]]; then cidr=24; fi
        local netmask
        netmask="$(system::network::__netmask "${cidr}")" || {
            log::warn "Invalid prefix length: ${cidr}"
            return "${E_INVALID}"
        }
        
        system::network::__run "Static IP ${ip} with netmask ${netmask} assigned to ${interface}" ifconfig "${interface}" "${ip}" netmask "${netmask}" || return "${E_ERROR}"
    fi
}

# @description Set default gateway / Установить шлюз по умолчанию
# @param $1 Gateway IP address / IP адрес шлюза
# @example
#   system::network::gateway "192.168.1.1"
system::network::gateway() {
    local gateway="${1:-}"
    
    if is::empty "${gateway}"; then
        log::warn "Gateway IP address not specified"
        return "${E_INVALID}"
    fi
    
    # Using ip command / Использование команды ip
    if utils::has ip; then
        system::network::__run "Default gateway set to ${gateway}" ip route add default via "${gateway}" || return "${E_ERROR}"
    else
        # Fallback to route / Резервный вариант route
        system::network::__run "Default gateway set to ${gateway}" route add default gw "${gateway}" || return "${E_ERROR}"
    fi
}

# @description Configure DNS servers / Настроить DNS серверы
# @param $@ DNS server IP addresses / IP адреса DNS серверов
# @example
#   system::network::dns "8.8.8.8" "8.8.4.4"
system::network::dns() {
    if [[ $# -eq 0 ]]; then
        log::warn "At least one DNS server must be specified"
        return "${E_INVALID}"
    fi
    
    # Create or overwrite resolv.conf / Создать или перезаписать resolv.conf
    # Путь переопределяется для тестов / The path is overridable for tests
    local resolv_conf="${BS_RESOLV_CONF:-/etc/resolv.conf}"
    if is::writable "${resolv_conf}"; then
        if [[ "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]; then
            log::info "[DRY-RUN] DNS servers would be set in ${resolv_conf}: $*"
            return "${E_SUCCESS}"
        fi
        # Новое содержимое собираем заранее и пишем одним разом (с сохранением
        # symlink): при сбое старые nameserver не пропадают, а dry-run ничего не трогает
        # The new content is built first and written in one go (keeps a
        # symlink): on failure the old nameservers stay, and dry-run touches nothing
        local dns content
        content="$(utils::attempt awk '!/^nameserver/' "${resolv_conf}")" || content=""
        for dns in "$@"; do
            content+="${content:+$'\n'}nameserver ${dns}"
        done
        if ! printf '%s\n' "${content}" > "${resolv_conf}"; then
            log::error "Failed to write ${resolv_conf}"
            return "${E_ERROR}"
        fi

        log::info "DNS servers configured: $*"
    else
        log::warn "Cannot write to ${resolv_conf}"
        return "${E_ERROR}"
    fi
}

# @description List network interfaces / Показать сетевые интерфейсы
# @example
#   system::network::list_interfaces
system::network::list_interfaces() {
    local names=""
    if utils::has ip; then
        # Имя без суффикса "@ifN" (veth/vlan); исключается ровно "lo", а не всё с "lo" в имени (wlo1)
        # Name without the "@ifN" suffix (veth/vlan); exactly "lo" is skipped, not every name containing "lo" (wlo1)
        names="$(utils::quiet_err ip link show | awk -F': ' '/^[0-9]+: / {n = $2; sub(/@.*/, "", n); if (n != "lo") print n}')"
    else
        # Fallback to ifconfig / Резервный вариант ifconfig
        names="$(utils::quiet_err ifconfig -a | awk '/^[a-zA-Z]/ {n = $1; sub(/:$/, "", n); if (n != "lo") print n}')"
    fi
    local name
    while IFS= read -r name; do
        is::empty "${name}" && continue
        format::record iface "${name}"
        printf '\n'
    done <<< "${names}" | format::emit "${BS_OUTPUT_FORMAT:-string}"
}

# @description Get the primary IPv4 address (of an interface, or the first
# global one). / Получить основной IPv4-адрес (интерфейса или первый глобальный).
# @description Output follows BS_OUTPUT_FORMAT (string default = bare address).
# @param $1 [optional] Interface name / Имя интерфейса
# @stdout address in the selected format / адрес в выбранном формате
# @example
#   system::network::ip            # 192.168.1.100
#   system::network::ip eth0       # 192.168.1.100
#   BS_OUTPUT_FORMAT=json system::network::ip eth0
system::network::ip() {
    local -r interface="${1:-}"
    local ip=""
    if utils::has ip; then
        if is::not_empty "${interface}"; then
            ip="$(utils::quiet_err ip -4 -o addr show dev "${interface}" 2>/dev/null \
                | awk '{print $4}' | cut -d/ -f1 | head -n1)"
        else
            ip="$(utils::quiet_err ip -4 -o addr show scope global 2>/dev/null \
                | awk '{print $4}' | cut -d/ -f1 | head -n1)"
        fi
    elif utils::has ifconfig; then
        if is::not_empty "${interface}"; then
            ip="$(utils::quiet_err ifconfig "${interface}" 2>/dev/null \
                | awk '/inet /{print $2; exit}')"
        fi
    fi
    if is::empty "${ip}"; then
        log::warn "No IPv4 address found${interface:+ for ${interface}}"
        return "${LIB_ERROR_FILE_NOT_FOUND}"
    fi
    format::record ip "${ip}" | format::emit "${BS_OUTPUT_FORMAT:-string}"
}

# @description Show network interface status / Показать статус сетевого интерфейса
# @param $1 Interface name / Имя интерфейса
# @example
#   system::network::status "eth0"
system::network::status() {
    local interface="${1:-}"
    
    if is::not_empty "${interface}"; then
        if utils::has ip; then
            utils::attempt ip addr show "${interface}" | format::emit_lines status
        else
            utils::attempt ifconfig "${interface}" | format::emit_lines status
        fi
    else
        if utils::has ip; then
            utils::attempt ip addr show | format::emit_lines status
        else
            utils::attempt ifconfig | format::emit_lines status
        fi
    fi
}