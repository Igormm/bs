#!/usr/bin/env bs
# shellcheck shell=bash
# lib/network/conn/core.sh — network connections: interfaces, addresses, routes, NetworkManager profiles, Wi-Fi
# lib/network/conn/core.sh — сетевые подключения: интерфейсы, адреса, маршруты, профили NetworkManager, Wi-Fi
#
# Data comes from sysfs (/sys/class/net) and procfs (/proc/net/route), so the
# interface list works with no tools at all. `ip` adds addresses and link
# up/down; `nmcli` (a running NetworkManager) adds connection profiles and Wi-Fi.
# Данные берутся из sysfs (/sys/class/net) и procfs (/proc/net/route), поэтому
# список интерфейсов работает без утилит. `ip` добавляет адреса и up/down;
# `nmcli` (запущенный NetworkManager) — профили подключений и Wi-Fi.
#
# Usage / Использование:
#   load "lib/network/conn/core"
#   network::conn::list                  # name<TAB>type<TAB>state<TAB>mac<TAB>mtu
#   network::conn::show eth0             # key=value
#   network::conn::up wlan0              # nmcli device connect | ip link set up
#   network::conn::nm::profiles          # name<TAB>uuid<TAB>type<TAB>device<TAB>active
#   network::conn::wifi::scan            # inuse<TAB>ssid<TAB>signal<TAB>security<TAB>chan
#   network::conn::wifi::connect "Home" "secret"
#
# Test hooks / Хуки для тестов: BS_NET_SYS, BS_NET_PROC, BS_NET_RESOLV.
#
# @depends core/lang, core/utils
# @tier gnu-linux
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], arithmetic command (( )), array, nameref, local/declare flags / needs bash constructs: double-bracket [[ ]], arithmetic command (( )), array, nameref, local/declare flags

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_NETWORK_CONN_CORE" || return 0

# Dependencies / Зависимости
bs::source_relative "../../../core/lang.sh" "../../../core/utils.sh"

# @global LIB_NETWORK_CONN_CORE_VERSION — Module version (category: module-flag)
# @global LIB_NETWORK_CONN_CORE_VERSION — Версия модуля (категория: module-flag)
declare -g LIB_NETWORK_CONN_CORE_VERSION="0.1.0"

# Paths / Пути

# @description sysfs network class directory (test hook BS_NET_SYS).
# @description Каталог класса net в sysfs (хук для тестов BS_NET_SYS).
network::conn::__sys() { printf '%s' "${BS_NET_SYS:-/sys/class/net}"; }

# @private
# @description Read the first line of a file, empty when missing / Первая строка файла, пусто если нет.
# @param $1 path / путь
network::conn::__read() {
    local line=""
    [[ -r "$1" ]] && { IFS= read -r line < "$1" || :; }
    printf '%s' "${line}"
}

# Interfaces / Интерфейсы

# @description Interface names, one per line, sorted (lo first).
# @description Имена интерфейсов по строке, отсортированы (lo первым).
# @stdout names / имена
network::conn::names() {
    local -r sys="$(network::conn::__sys)"
    local d n
    local -a found=()
    for d in "${sys}"/*; do
        [[ -e "${d}" ]] || continue
        n="${d##*/}"
        [[ "${n}" == "bonding_masters" ]] && continue
        found+=("${n}")
    done
    (( ${#found[@]} > 0 )) || return 0
    printf '%s\n' "${found[@]}" | LC_ALL=C sort | awk '$0=="lo"{print;next}{a[++n]=$0}END{for(i=1;i<=n;i++)print a[i]}'
}

# @description Kind of interface: loopback, wifi, ethernet, bridge, bond, vlan, wireguard, tun, veth, virtual …
# @description Вид интерфейса: loopback, wifi, ethernet, bridge, bond, vlan, wireguard, tun, veth, virtual …
# @param $1 interface / интерфейс
# @stdout kind / вид
network::conn::kind() {
    local -r ifc="${1:?interface required}"
    local -r d="$(network::conn::__sys)/${ifc}"
    local devtype="" line
    if [[ -r "${d}/uevent" ]]; then
        while IFS= read -r line; do
            [[ "${line}" == DEVTYPE=* ]] && devtype="${line#DEVTYPE=}"
        done < "${d}/uevent"
    fi
    local -r type="$(network::conn::__read "${d}/type")"
    if [[ "${type}" == 772 || "${ifc}" == lo ]]; then printf 'loopback'; return 0; fi
    if [[ -d "${d}/wireless" || -d "${d}/phy80211" || "${devtype}" == wlan ]]; then printf 'wifi'; return 0; fi
    case "${devtype}" in
        bridge|bond|vlan|wireguard|macvlan|ipvlan|vxlan|veth|gre|ppp|wwan|dsa) printf '%s' "${devtype}"; return 0 ;;
    esac
    [[ -d "${d}/bridge" ]] && { printf 'bridge'; return 0; }
    [[ -d "${d}/bonding" ]] && { printf 'bond'; return 0; }
    [[ -e "${d}/tun_flags" ]] && { printf 'tun'; return 0; }
    case "${ifc}" in
        veth*) printf 'veth'; return 0 ;;
        wg*) printf 'wireguard'; return 0 ;;
        docker*|br-*|virbr*) printf 'bridge'; return 0 ;;
    esac
    case "${type}" in
        1) if [[ -e "${d}/device" ]]; then printf 'ethernet'; else printf 'virtual'; fi ;;
        65534) printf 'tun' ;;
        512) printf 'ppp' ;;
        768|769|776|778) printf 'tunnel' ;;
        *) printf 'other' ;;
    esac
}

# @description Operational state: up, down, dormant, unknown … (lowercase).
# @description Рабочее состояние: up, down, dormant, unknown … (строчными).
# @param $1 interface / интерфейс
network::conn::state() {
    local -r d="$(network::conn::__sys)/${1:?interface required}"
    local st
    st="$(network::conn::__read "${d}/operstate")"
    # loopback и tun часто «unknown», хотя подняты: смотрим флаг IFF_UP
    # loopback and tun often report "unknown" while up: check the IFF_UP flag
    if [[ "${st}" == unknown || -z "${st}" ]]; then
        local flags
        flags="$(network::conn::__read "${d}/flags")"
        if [[ "${flags}" == 0x* ]] && (( flags & 1 )); then st="up"; else st="${st:-unknown}"; fi
    fi
    printf '%s' "${st}"
}

# @description Admin state from IFF_UP: 1 when the link is set up / Административно поднят (IFF_UP): 1 или 0.
# @param $1 interface / интерфейс
network::conn::admin_up() {
    local flags
    flags="$(network::conn::__read "$(network::conn::__sys)/${1:?interface required}/flags")"
    [[ "${flags}" == 0x* ]] && (( flags & 1 ))
}

# @description Byte counters as "rx tx" / Счётчики байтов как «rx tx».
# @param $1 interface / интерфейс
network::conn::stats() {
    local -r d="$(network::conn::__sys)/${1:?interface required}/statistics"
    local rx tx
    rx="$(network::conn::__read "${d}/rx_bytes")"
    tx="$(network::conn::__read "${d}/tx_bytes")"
    printf '%s %s' "${rx:-0}" "${tx:-0}"
}

# @description All interfaces as TSV: name, kind, state, mac, mtu ("--" when empty).
# @description Все интерфейсы в TSV: имя, вид, состояние, mac, mtu («--», если пусто).
# @stdout TSV
network::conn::list() {
    local -r sys="$(network::conn::__sys)"
    local n mac mtu
    while IFS= read -r n; do
        [[ -n "${n}" ]] || continue
        mac="$(network::conn::__read "${sys}/${n}/address")"
        mtu="$(network::conn::__read "${sys}/${n}/mtu")"
        printf '%s\t%s\t%s\t%s\t%s\n' "${n}" "$(network::conn::kind "${n}")" "$(network::conn::state "${n}")" "${mac:---}" "${mtu:---}"
    done < <(network::conn::names)
}

# @description Addresses of an interface: "inet 10.0.0.2/24" / "inet6 fe80::1/64", one per line.
# @description Адреса интерфейса: «inet 10.0.0.2/24» / «inet6 fe80::1/64», по строке.
#   Uses `ip`, falls back to `ifconfig`; prints nothing without both.
#   Использует `ip`, иначе `ifconfig`; без них ничего не выводит.
# @param $1 interface / интерфейс
network::conn::addrs() {
    local -r ifc="${1:?interface required}"
    if is::command ip; then
        ip -o addr show dev "${ifc}" 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="inet"||$i=="inet6"){print $i" "$(i+1); break}}'
    elif is::command ifconfig; then
        ifconfig "${ifc}" 2>/dev/null | awk '
            $1=="inet" {a=$2; sub(/^addr:/,"",a); m=""; for(i=3;i<=NF;i++){ if($i=="netmask"){m=$(i+1)} if($i ~ /^Mask:/){m=substr($i,6)} }
                        if(m!=""){n=0; split(m,o,"."); for(j=1;j<=4;j++){v=o[j]+0; while(v>0){n+=v%2; v=int(v/2)}} a=a"/"n} print "inet "a }
            $1=="inet6" {a=$2; p=""; for(i=3;i<=NF;i++) if($i=="prefixlen") p=$(i+1); if(a ~ /^addr:/){a=$3} print "inet6 "a (p!=""?"/"p:"")}'
    else
        # без утилит: только IPv6 из procfs / no tools: IPv6 only, from procfs
        network::conn::__inet6_proc "${ifc}"
    fi
    return 0
}

# @private
# @description IPv6 addresses from /proc/net/if_inet6 (no tools needed), compressed form.
# @description IPv6-адреса из /proc/net/if_inet6 (без утилит), в сжатой записи.
# @param $1 interface / интерфейс
network::conn::__inet6_proc() {
    local -r f="${BS_NET_PROC:-/proc/net}/if_inet6"
    [[ -r "${f}" ]] || return 0
    local hex _idx plen _scope _flags dev
    while IFS=$' \t' read -r hex _idx plen _scope _flags dev; do
        [[ "${dev}" == "$1" && ${#hex} == 32 ]] || continue
        printf 'inet6 %s/%d\n' "$(network::conn::__ip6 "${hex}")" "$(( 16#${plen} ))"
    done < "${f}"
}

# @private
# @description 32 hex digits → compressed IPv6 text (RFC 5952) / 32 hex-цифры → сжатая запись IPv6 (RFC 5952).
# @param $1 hex
network::conn::__ip6() {
    local -r h="$1"
    local -a g=()
    local -i i best=-1 best_len=0 run=-1 len=0
    for (( i = 0; i < 8; i++ )); do
        printf -v 'g[i]' '%x' "$(( 16#${h:i*4:4} ))"
    done
    for (( i = 0; i <= 8; i++ )); do
        if (( i < 8 )) && [[ "${g[i]}" == 0 ]]; then
            (( run < 0 )) && run="${i}" len=0
            len=$(( len + 1 ))
        else
            if (( run >= 0 && len > best_len && len > 1 )); then best="${run}"; best_len="${len}"; fi
            run=-1
        fi
    done
    local out=""
    for (( i = 0; i < 8; i++ )); do
        if (( i == best )); then
            out+="::"
            i=$(( i + best_len - 1 ))
            continue
        fi
        [[ -n "${out}" && "${out}" != *:: ]] && out+=":"
        out+="${g[i]}"
    done
    printf '%s' "${out}"
}

# @private
# @description Little-endian hex IPv4 from /proc/net/route to dotted form / Hex IPv4 (little-endian) → точечная запись.
# @param $1 hex (8 chars) → stdout
network::conn::__hex_ip() {
    local -r h="${1:?hex required}"
    printf '%d.%d.%d.%d' "$(( 16#${h:6:2} ))" "$(( 16#${h:4:2} ))" "$(( 16#${h:2:2} ))" "$(( 16#${h:0:2} ))"
}

# @description Default IPv4 routes as TSV: interface, gateway, metric (lowest metric first).
# @description Маршруты по умолчанию IPv4 в TSV: интерфейс, шлюз, метрика (меньшая метрика первой).
# @param $1 [interface] only this one / только этот интерфейс
network::conn::gateways() {
    local -r want="${1-}" route="${BS_NET_PROC:-/proc/net}/route"
    [[ -r "${route}" ]] || return 0
    local ifc dest gw flags _rc _use metric _rest
    {
        while IFS=$' \t' read -r ifc dest gw flags _rc _use metric _rest; do
            [[ "${dest}" == 00000000 && "${ifc}" != Iface ]] || continue
            [[ -z "${want}" || "${ifc}" == "${want}" ]] || continue
            # RTF_UP (0x1) обязателен / RTF_UP must be set
            (( 16#${flags} & 1 )) || continue
            printf '%s\t%s\t%s\n' "${ifc}" "$(network::conn::__hex_ip "${gw}")" "${metric}"
        done < "${route}"
    } | sort -t $'\t' -k3,3n
}

# @description DNS servers from resolv.conf, one per line / DNS-серверы из resolv.conf, по строке.
network::conn::dns() {
    local -r f="${BS_NET_RESOLV:-/etc/resolv.conf}"
    [[ -r "${f}" ]] || return 0
    local key val _rest
    while IFS=$' \t' read -r key val _rest; do
        [[ "${key}" == nameserver && -n "${val}" ]] && printf '%s\n' "${val}"
    done < "${f}"
    return 0
}

# @description Details of an interface as key=value lines.
# @description Сведения об интерфейсе строками key=value.
#   Keys: name kind state admin carrier mac mtu speed driver rx tx inet inet6 gateway managed.
#   inet/inet6/gateway repeat for every address/route.
# @param $1 interface / интерфейс
network::conn::show() {
    local -r ifc="${1:?interface required}"
    local -r d="$(network::conn::__sys)/${ifc}"
    [[ -e "${d}" ]] || { printf 'network::conn::show: нет интерфейса / no interface: %s\n' "${ifc}" >&2; return 1; }
    local rx tx speed driver="" carrier
    IFS=' ' read -r rx tx <<< "$(network::conn::stats "${ifc}")"
    speed="$(network::conn::__read "${d}/speed" 2>/dev/null)"
    [[ "${speed}" =~ ^[0-9]+$ ]] || speed=""
    [[ -L "${d}/device/driver" ]] && driver="$(readlink "${d}/device/driver")" && driver="${driver##*/}"
    carrier="$(network::conn::__read "${d}/carrier" 2>/dev/null)"
    printf 'name=%s\nkind=%s\nstate=%s\n' "${ifc}" "$(network::conn::kind "${ifc}")" "$(network::conn::state "${ifc}")"
    if network::conn::admin_up "${ifc}"; then printf 'admin=up\n'; else printf 'admin=down\n'; fi
    printf 'carrier=%s\nmac=%s\nmtu=%s\nspeed=%s\ndriver=%s\nrx=%s\ntx=%s\n' "${carrier}" \
        "$(network::conn::__read "${d}/address")" "$(network::conn::__read "${d}/mtu")" "${speed}" "${driver}" "${rx}" "${tx}"
    local fam addr
    while IFS=' ' read -r fam addr; do
        [[ -n "${fam}" ]] && printf '%s=%s\n' "${fam}" "${addr}"
    done < <(network::conn::addrs "${ifc}")
    local _i gw _m
    while IFS=$'\t' read -r _i gw _m; do
        [[ -n "${gw}" ]] && printf 'gateway=%s\n' "${gw}"
    done < <(network::conn::gateways "${ifc}")
    if network::conn::nm::manages "${ifc}"; then printf 'managed=networkmanager\n'; else printf 'managed=\n'; fi
}

# Privileges / Привилегии

# @description Is root available without a prompt (root or passwordless sudo)?
# @description Есть ли root без запроса пароля (root или sudo без пароля)?
network::conn::root_ready() {
    (( EUID == 0 )) && return 0
    is::command sudo && sudo -n true 2>/dev/null
}

# @private
# @description Run a command as root (directly or sudo -n) / Выполнить команду от root (напрямую или sudo -n).
network::conn::__priv() {
    if (( EUID == 0 )); then "$@"; return $?; fi
    if is::command sudo && sudo -n true 2>/dev/null; then sudo -n "$@"; return $?; fi
    printf 'нужны права root (sudo) / root required (sudo): %s\n' "$*" >&2
    return 126
}

# @private
# @description Refuse names that are not interface names / Отклонить строки, не похожие на имя интерфейса.
network::conn::__valid_ifname() {
    [[ "${1-}" =~ ^[A-Za-z0-9_.:@-]{1,15}$ && "${1}" != -* ]] || {
        printf 'неверное имя интерфейса / bad interface name: %s\n' "${1-}" >&2
        return 2
    }
}

# @description Bring an interface up: nmcli when NetworkManager manages it, else `ip link set up`.
# @description Поднять интерфейс: nmcli, если им управляет NetworkManager, иначе `ip link set up`.
# @param $1 interface / интерфейс
network::conn::up() {
    local -r ifc="${1:?interface required}"
    network::conn::__valid_ifname "${ifc}" || return $?
    if network::conn::nm::manages "${ifc}"; then
        nmcli device connect "${ifc}"
        return $?
    fi
    is::command ip || { printf 'нет утилиты ip (iproute2) / ip (iproute2) not found\n' >&2; return 127; }
    network::conn::__priv ip link set dev "${ifc}" up
}

# @description Bring an interface down: nmcli when NetworkManager manages it, else `ip link set down`.
# @description Опустить интерфейс: nmcli, если им управляет NetworkManager, иначе `ip link set down`.
# @param $1 interface / интерфейс
network::conn::down() {
    local -r ifc="${1:?interface required}"
    network::conn::__valid_ifname "${ifc}" || return $?
    if network::conn::nm::manages "${ifc}"; then
        nmcli device disconnect "${ifc}"
        return $?
    fi
    is::command ip || { printf 'нет утилиты ip (iproute2) / ip (iproute2) not found\n' >&2; return 127; }
    network::conn::__priv ip link set dev "${ifc}" down
}

# NetworkManager / NetworkManager

# @description Is NetworkManager running and nmcli present? / Запущен ли NetworkManager и есть ли nmcli?
network::conn::nm::available() {
    is::command nmcli || return 1
    [[ "$(nmcli -t -f RUNNING general 2>/dev/null)" == running ]]
}

# @description Split one terse nmcli line (":" separated, "\:" escaped) into TSV; empty fields become "--".
# @description Разбить строку nmcli -t (разделитель «:», экранирование «\:») в TSV; пустые поля — «--».
#   No field is ever empty, so `IFS=$'\t' read` (tab is IFS whitespace and collapses) keeps columns.
#   Пустых полей нет, поэтому `IFS=$'\t' read` (таб — пробельный IFS и схлопывается) не сдвигает колонки.
# @param $1 line / строка
# @stdout TSV
network::conn::nm::split() {
    local -r s="${1-}"
    local out="" fld="" c
    local -i i esc=0
    for (( i = 0; i < ${#s}; i++ )); do
        c="${s:i:1}"
        if (( esc )); then fld+="${c}"; esc=0; continue; fi
        case "${c}" in
            '\') esc=1 ;;
            ':') out+="${fld:---}"$'\t'; fld="" ;;
            $'\t') fld+=' ' ;;
            *) fld+="${c}" ;;
        esac
    done
    printf '%s\n' "${out}${fld:---}"
}

# @description Does NetworkManager manage this device? / Управляет ли NetworkManager этим устройством?
# @param $1 interface / интерфейс
network::conn::nm::manages() {
    network::conn::nm::available || return 1
    local line dev state
    while IFS= read -r line; do
        IFS=$'\t' read -r dev state <<< "$(network::conn::nm::split "${line}")"
        if [[ "${dev}" == "$1" ]]; then
            [[ "${state}" != unmanaged* ]]
            return $?
        fi
    done < <(nmcli -t -f DEVICE,STATE device status 2>/dev/null)
    return 1
}

# @description NetworkManager connection profiles as TSV: name, uuid, type, device (-- none), active (yes/no).
# @description Профили подключений NetworkManager в TSV: имя, uuid, тип, устройство (-- нет), активен (yes/no).
network::conn::nm::profiles() {
    network::conn::nm::available || return 0
    local line
    while IFS= read -r line; do
        [[ -n "${line}" ]] && network::conn::nm::split "${line}"
    done < <(nmcli -t -f NAME,UUID,TYPE,DEVICE,ACTIVE connection show 2>/dev/null)
}

# @description Activate a profile by uuid or name / Включить профиль по uuid или имени.
# @param $1 uuid|name
network::conn::nm::up() {
    local -r id="${1:?profile required}"
    network::conn::nm::available || { printf 'NetworkManager не запущен / not running\n' >&2; return 1; }
    nmcli connection up "$(network::conn::nm::__id_kind "${id}")" "${id}"
}

# @description Deactivate a profile by uuid or name / Выключить профиль по uuid или имени.
# @param $1 uuid|name
network::conn::nm::down() {
    local -r id="${1:?profile required}"
    network::conn::nm::available || { printf 'NetworkManager не запущен / not running\n' >&2; return 1; }
    nmcli connection down "$(network::conn::nm::__id_kind "${id}")" "${id}"
}

# @private
# @description "uuid" for a UUID, "id" for a name (so a name like "up" is never read as a keyword).
# @description «uuid» для UUID, «id» для имени (чтобы имя вроде «up» не читалось как ключевое слово).
network::conn::nm::__id_kind() {
    if [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        printf 'uuid'
    else
        printf 'id'
    fi
}

# Wi-Fi / Wi-Fi

# @description Visible Wi-Fi networks as TSV: inuse (*|--), ssid, signal %, security (-- open), channel; in use first, then strongest; one row per SSID.
# @description Видимые сети Wi-Fi в TSV: inuse (*|--), ssid, сигнал %, защита (-- открытая), канал; текущая первой, потом сильные; по строке на SSID.
# @param $1 [rescan] yes|no|auto (default auto)
network::conn::wifi::scan() {
    network::conn::nm::available || { printf 'Wi-Fi: нужен NetworkManager (nmcli) / NetworkManager (nmcli) required\n' >&2; return 1; }
    local -r rescan="${1:-auto}"
    local line
    local -A seen=()
    local inuse ssid signal sec chan
    while IFS=$'\t' read -r inuse ssid signal sec chan; do
        [[ -n "${ssid}" && "${ssid}" != "--" ]] || continue
        [[ -n "${seen[${ssid}]:-}" ]] && continue
        seen["${ssid}"]=1
        [[ "${inuse}" == *'*'* ]] && inuse='*' || inuse='--'
        printf '%s\t%s\t%s\t%s\t%s\n' "${inuse}" "${ssid}" "${signal}" "${sec}" "${chan}"
    done < <(
        while IFS= read -r line; do
            [[ -n "${line}" ]] && network::conn::nm::split "${line}"
        done < <(nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY,CHAN device wifi list --rescan "${rescan}" 2>/dev/null) \
            | LC_ALL=C sort -t $'\t' -k1,1r -k3,3nr
    )
}

# @description Connect to a Wi-Fi network (saved profile is reused when there is no password).
# @description Подключиться к сети Wi-Fi (без пароля используется сохранённый профиль).
#   The password reaches nmcli as an argument, the way `nmcli device wifi connect` takes it.
#   Пароль передаётся nmcli аргументом — так его принимает `nmcli device wifi connect`.
# @param $1 ssid, $2 [password], $3 [interface]
network::conn::wifi::connect() {
    local -r ssid="${1:?ssid required}" pass="${2-}" ifc="${3-}"
    network::conn::nm::available || { printf 'Wi-Fi: нужен NetworkManager (nmcli) / NetworkManager (nmcli) required\n' >&2; return 1; }
    local -a cmd=(nmcli device wifi connect "${ssid}")
    [[ -n "${pass}" ]] && cmd+=(password "${pass}")
    if [[ -n "${ifc}" ]]; then
        network::conn::__valid_ifname "${ifc}" || return $?
        cmd+=(ifname "${ifc}")
    fi
    "${cmd[@]}"
}

# @description Is a saved NetworkManager profile there for this SSID? / Есть ли сохранённый профиль для этого SSID?
# @param $1 ssid
network::conn::wifi::known() {
    local name _u type _rest
    while IFS=$'\t' read -r name _u type _rest; do
        [[ "${name}" == "$1" && "${type}" == *wireless* ]] && return 0
    done < <(network::conn::nm::profiles)
    return 1
}

# @description Turn the Wi-Fi radio on or off / Включить или выключить радио Wi-Fi.
# @param $1 on|off
network::conn::wifi::radio() {
    case "${1-}" in
        on|off) ;;
        *) printf 'network::conn::wifi::radio: on|off\n' >&2; return 2 ;;
    esac
    network::conn::nm::available || { printf 'Wi-Fi: нужен NetworkManager (nmcli) / NetworkManager (nmcli) required\n' >&2; return 1; }
    nmcli radio wifi "$1"
}
