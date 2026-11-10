#!/usr/bin/env bs
# shellcheck shell=bash
# lib/network/vpn/singbox.sh — sing-box (>= 1.12) JSON config from profiles and settings
# lib/network/vpn/singbox.sh — JSON-конфиг sing-box (>= 1.12) из профилей и настроек
#
# Pure bash JSON rendering, no jq: outbounds for every supported protocol
# (TLS, REALITY, uTLS, v2ray transports, port hopping, obfuscation), proxy
# and TUN inbounds, DNS with split resolving, routing presets with remote
# rule-sets, selector/urltest groups and the Clash API for live control.
# JSON собирается на чистом bash без jq: outbound для каждого протокола (TLS,
# REALITY, uTLS, транспорты v2ray, port hopping, обфускация), входы proxy и
# TUN, DNS с раздельным резолвингом, пресеты маршрутизации с удалёнными
# rule-set, группы selector/urltest и Clash API для управления на лету.
#
# @depends core/lang, core/const, lib/network/vpn/link, lib/network/vpn/store
# @tier core
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], arithmetic command (( )), array, nameref, local/declare flags / needs bash constructs: double-bracket [[ ]], arithmetic command (( )), array, nameref, local/declare flags

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_NETWORK_VPN_SINGBOX" || return 0

# Dependencies / Зависимости
bs::source_relative "../../../core/lang.sh" "../../../core/const.sh" "link.sh" "store.sh"

# @global VPN_SINGBOX_VERSION — Vpn singbox: target core version, empty = newest (category: hook)
# @global VPN_SINGBOX_VERSION — Vpn singbox: целевая версия ядра, пусто = новейшая (категория: hook)
declare -g VPN_SINGBOX_VERSION="${VPN_SINGBOX_VERSION:-}"

# @global VPN_SINGBOX_RULESET_BASE — Vpn singbox: base URL of SagerNet rule-set branches (category: hook)
# @global VPN_SINGBOX_RULESET_BASE — Vpn singbox: базовый URL веток rule-set SagerNet (категория: hook)
declare -g VPN_SINGBOX_RULESET_BASE="${BS_VPN_RULESET_BASE:-https://raw.githubusercontent.com/SagerNet}"

# JSON helpers / JSON-хелперы

# @private
# @description "key":"value" when value is not empty / "ключ":"значение", если значение не пустое.
vpn::singbox::__s() {
    is::empty "${2-}" && return 0
    printf '"%s":"%s"' "$1" "$(vpn::link::json_escape "$2")"
}

# @private
# @description "key":number when value is a number / "ключ":число, если значение — число.
vpn::singbox::__n() {
    is::number "${2-}" || return 0
    printf '"%s":%d' "$1" "$(( 10#$2 ))"
}

# @private
# @description "key":true when value is 1 / "ключ":true, если значение 1.
vpn::singbox::__b() {
    [[ "${2-}" == 1 ]] || return 0
    printf '"%s":true' "$1"
}

# @private
# @description "key":raw-json when raw is not empty / "ключ":сырой-json, если не пусто.
vpn::singbox::__r() {
    is::empty "${2-}" && return 0
    printf '"%s":%s' "$1" "$2"
}

# @private
# @description Join non-empty fields into a JSON object / Склеить непустые поля в JSON-объект.
vpn::singbox::__obj() {
    local out="" f
    for f in "$@"; do
        is::empty "${f}" && continue
        out+="${out:+,}${f}"
    done
    printf '{%s}' "${out}"
}

# @private
# @description Join non-empty raw items into a JSON array / Склеить непустые элементы в JSON-массив.
vpn::singbox::__arr() {
    local out="" f
    for f in "$@"; do
        is::empty "${f}" && continue
        out+="${out:+,}${f}"
    done
    printf '[%s]' "${out}"
}

# @private
# @description CSV to a JSON string array; empty CSV gives nothing.
# @description CSV в JSON-массив строк; пустой CSV — ничего.
vpn::singbox::__csv() {
    is::empty "${1-}" && return 0
    local -a items=()
    local item out=""
    IFS=',' read -ra items <<< "$1"
    for item in "${items[@]}"; do
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        is::empty "${item}" && continue
        out+="${out:+,}\"$(vpn::link::json_escape "${item}")\""
    done
    is::empty "${out}" && return 0
    printf '[%s]' "${out}"
}

# @description Is the target core version >= the given one? Empty target = newest.
# @description Целевая версия ядра >= заданной? Пустая цель = новейшая.
# @param $1 version (X.Y) / версия
# @return 0 yes, 1 no
vpn::singbox::version_ge() {
    local -r want="${1:?version required}" have="${VPN_SINGBOX_VERSION:-}"
    [[ "${have}" =~ ^([0-9]+)\.([0-9]+) ]] || return 0
    local -ri hmaj="${BASH_REMATCH[1]}" hmin="${BASH_REMATCH[2]}"
    [[ "${want}" =~ ^([0-9]+)\.([0-9]+) ]] || return 0
    local -ri wmaj="${BASH_REMATCH[1]}" wmin="${BASH_REMATCH[2]}"
    (( hmaj > wmaj || (hmaj == wmaj && hmin >= wmin) ))
}

# Outbound pieces / Части outbound

# @private
# @description TLS object of a profile (empty when the profile has no TLS).
# @description Объект TLS профиля (пусто, если у профиля нет TLS).
# @param $1 profile map name / имя карты профиля
vpn::singbox::__tls() {
    local -n __vs_t="${1:?}"
    local -r security="${__vs_t[security]:-none}" proto="${__vs_t[proto]}"
    case "${security}" in
        tls|reality) : ;;
        *) return 0 ;;
    esac
    local alpn="${__vs_t[alpn]:-}"
    if is::empty "${alpn}"; then
        case "${proto}" in
            hysteria2|tuic) alpn="h3" ;;
            hysteria) alpn="hysteria" ;;
        esac
    fi
    local fp="${__vs_t[fp]:-}"
    [[ "${security}" == "reality" && -z "${fp}" ]] && fp="chrome"
    # uTLS неприменим к QUIC-протоколам / uTLS does not apply to QUIC protocols
    case "${proto}" in hysteria2|hysteria|tuic) fp="" ;; esac
    local utls="" reality=""
    is::not_empty "${fp}" && utls="$(vpn::singbox::__obj '"enabled":true' "$(vpn::singbox::__s fingerprint "${fp}")")"
    if [[ "${security}" == "reality" ]]; then
        reality="$(vpn::singbox::__obj '"enabled":true' \
            "$(vpn::singbox::__s public_key "${__vs_t[pbk]:-}")" \
            "$(vpn::singbox::__s short_id "${__vs_t[sid]:-}")")"
    fi
    vpn::singbox::__obj '"enabled":true' \
        "$(vpn::singbox::__s server_name "${__vs_t[sni]:-}")" \
        "$(vpn::singbox::__b insecure "${__vs_t[insecure]:-0}")" \
        "$(vpn::singbox::__r alpn "$(vpn::singbox::__csv "${alpn}")")" \
        "$(vpn::singbox::__r utls "${utls}")" \
        "$(vpn::singbox::__r reality "${reality}")"
}

# @private
# @description V2Ray transport object (empty for plain tcp).
# @description Объект транспорта V2Ray (пусто для обычного tcp).
# @param $1 profile map name / имя карты профиля
vpn::singbox::__transport() {
    local -n __vs_tr="${1:?}"
    local -r transport="${__vs_tr[transport]:-tcp}"
    local path="${__vs_tr[path]:-}" host="${__vs_tr[host]:-}"
    case "${transport}" in
        ws)
            # ?ed=2048 в пути — early data в стиле Xray / ?ed=2048 in path is Xray-style early data
            local early=""
            if [[ "${path}" =~ [?\&]ed=([0-9]+) ]]; then
                early="${BASH_REMATCH[1]}"
                path="${path%%\?*}"
            fi
            local headers=""
            is::not_empty "${host}" && headers="$(vpn::singbox::__obj "$(vpn::singbox::__s Host "${host}")")"
            vpn::singbox::__obj '"type":"ws"' \
                "$(vpn::singbox::__s path "${path:-/}")" \
                "$(vpn::singbox::__r headers "${headers}")" \
                "$(vpn::singbox::__n max_early_data "${early}")" \
                "$(is::not_empty "${early}" && printf '"early_data_header_name":"Sec-WebSocket-Protocol"')"
            ;;
        grpc)
            vpn::singbox::__obj '"type":"grpc"' "$(vpn::singbox::__s service_name "${__vs_tr[service_name]:-}")" ;;
        http)
            vpn::singbox::__obj '"type":"http"' \
                "$(vpn::singbox::__r host "$(vpn::singbox::__csv "${host}")")" \
                "$(vpn::singbox::__s path "${path}")" ;;
        httpupgrade)
            vpn::singbox::__obj '"type":"httpupgrade"' \
                "$(vpn::singbox::__s host "${host}")" \
                "$(vpn::singbox::__s path "${path:-/}")" ;;
        quic)
            printf '{"type":"quic"}' ;;
    esac
    return 0
}

# @private
# @description Port hopping list "443,20000-30000" as sing-box server_ports ["443:443","20000:30000"].
# @description Список port hopping «443,20000-30000» как server_ports sing-box.
vpn::singbox::__ports() {
    is::empty "${1-}" && return 0
    local -a items=()
    local item out=""
    IFS=',' read -ra items <<< "$1"
    for item in "${items[@]}"; do
        [[ "${item}" == *-* ]] || item="${item}-${item}"
        out+="${out:+,}\"${item/-/:}\""
    done
    printf '[%s]' "${out}"
}

# @description Render one profile as a sing-box outbound object.
# @description Отрисовать один профиль как объект outbound sing-box.
# @param $1 profile map name / имя карты профиля
# @param $2 tag / тег
# @stdout JSON object / JSON-объект
# @return 0 ok, LIB_ERROR_INVALID_INPUT invalid profile
vpn::singbox::outbound() {
    local -n __vs_o="${1:?map name required}"
    local -r tag="${2:?tag required}"
    vpn::link::validate "${1}" || return $?
    local -r proto="${__vs_o[proto]}"
    local -r tls="$(vpn::singbox::__tls "${1}")"
    local -r transport="$(vpn::singbox::__transport "${1}")"
    local -r head="$(vpn::singbox::__s type "${proto}"),$(vpn::singbox::__s tag "${tag}"),$(vpn::singbox::__s server "${__vs_o[server]}")"
    local -r port="$(vpn::singbox::__n server_port "${__vs_o[port]}")"
    case "${proto}" in
        vless)
            vpn::singbox::__obj "${head}" "${port}" \
                "$(vpn::singbox::__s uuid "${__vs_o[uuid]}")" \
                "$(vpn::singbox::__s flow "${__vs_o[flow]:-}")" \
                "$(vpn::singbox::__s packet_encoding "${__vs_o[packet_encoding]:-xudp}")" \
                "$(vpn::singbox::__r tls "${tls}")" \
                "$(vpn::singbox::__r transport "${transport}")" ;;
        vmess)
            vpn::singbox::__obj "${head}" "${port}" \
                "$(vpn::singbox::__s uuid "${__vs_o[uuid]}")" \
                "$(vpn::singbox::__s security "${__vs_o[cipher]:-auto}")" \
                "$(vpn::singbox::__n alter_id "${__vs_o[alter_id]:-}")" \
                "$(vpn::singbox::__s packet_encoding "${__vs_o[packet_encoding]:-}")" \
                "$(vpn::singbox::__r tls "${tls}")" \
                "$(vpn::singbox::__r transport "${transport}")" ;;
        trojan)
            vpn::singbox::__obj "${head}" "${port}" \
                "$(vpn::singbox::__s password "${__vs_o[password]}")" \
                "$(vpn::singbox::__r tls "${tls}")" \
                "$(vpn::singbox::__r transport "${transport}")" ;;
        shadowsocks)
            vpn::singbox::__obj "${head}" "${port}" \
                "$(vpn::singbox::__s method "${__vs_o[method]}")" \
                "$(vpn::singbox::__s password "${__vs_o[password]:-}")" \
                "$(vpn::singbox::__s plugin "${__vs_o[plugin]:-}")" \
                "$(vpn::singbox::__s plugin_opts "${__vs_o[plugin_opts]:-}")" ;;
        hysteria2)
            local obfs="" ports_json
            ports_json="$(vpn::singbox::__ports "${__vs_o[ports]:-}")"
            if is::not_empty "${__vs_o[obfs]:-}"; then
                obfs="$(vpn::singbox::__obj "$(vpn::singbox::__s type "${__vs_o[obfs]}")" \
                    "$(vpn::singbox::__s password "${__vs_o[obfs_password]:-}")")"
            fi
            vpn::singbox::__obj "${head}" \
                "$(is::empty "${ports_json}" && printf '%s' "${port}")" \
                "$(vpn::singbox::__r server_ports "${ports_json}")" \
                "$(vpn::singbox::__n up_mbps "${__vs_o[up_mbps]:-}")" \
                "$(vpn::singbox::__n down_mbps "${__vs_o[down_mbps]:-}")" \
                "$(vpn::singbox::__r obfs "${obfs}")" \
                "$(vpn::singbox::__s password "${__vs_o[password]}")" \
                "$(vpn::singbox::__r tls "${tls}")" ;;
        hysteria)
            vpn::singbox::__obj "${head}" "${port}" \
                "$(vpn::singbox::__n up_mbps "${__vs_o[up_mbps]:-10}")" \
                "$(vpn::singbox::__n down_mbps "${__vs_o[down_mbps]:-50}")" \
                "$(vpn::singbox::__s obfs "${__vs_o[obfs]:-}")" \
                "$(vpn::singbox::__s auth_str "${__vs_o[auth]:-}")" \
                "$(vpn::singbox::__r tls "${tls}")" ;;
        tuic)
            vpn::singbox::__obj "${head}" "${port}" \
                "$(vpn::singbox::__s uuid "${__vs_o[uuid]}")" \
                "$(vpn::singbox::__s password "${__vs_o[password]:-}")" \
                "$(vpn::singbox::__s congestion_control "${__vs_o[congestion]:-bbr}")" \
                "$(vpn::singbox::__s udp_relay_mode "${__vs_o[udp_relay]:-native}")" \
                "$(vpn::singbox::__r tls "${tls}")" ;;
        anytls)
            vpn::singbox::__obj "${head}" "${port}" \
                "$(vpn::singbox::__s password "${__vs_o[password]}")" \
                "$(vpn::singbox::__r tls "${tls}")" ;;
        socks)
            vpn::singbox::__obj "${head}" "${port}" '"version":"5"' \
                "$(vpn::singbox::__s username "${__vs_o[username]:-}")" \
                "$(vpn::singbox::__s password "${__vs_o[password]:-}")" ;;
    esac
}

# Config sections / Секции конфига

# @private
# @description A DNS server object from a setting ("local", IP, udp://, tls://, https://…).
# @description Объект DNS-сервера из настройки («local», IP, udp://, tls://, https://…).
# @param $1 value, $2 tag, $3 [detour]
vpn::singbox::__dns_server() {
    local -r value="$1" tag="$2" detour="${3-}"
    if [[ "${value}" == "local" ]]; then
        vpn::singbox::__obj '"type":"local"' "$(vpn::singbox::__s tag "${tag}")"
        return 0
    fi
    local type="udp" rest="${value}" path=""
    if [[ "${value}" =~ ^([a-z0-9]+)://(.*)$ ]]; then
        type="${BASH_REMATCH[1]}"
        rest="${BASH_REMATCH[2]}"
    fi
    if [[ "${rest}" == */* ]]; then
        path="/${rest#*/}"
        rest="${rest%%/*}"
    fi
    local server="${rest}" port=""
    if [[ "${rest}" =~ ^\[(.*)\](:([0-9]+))?$ ]]; then
        server="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[3]}"
    elif [[ "${rest}" =~ ^([^:]+):([0-9]+)$ ]]; then
        server="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
    fi
    local resolver=""
    # домен сервера DNS резолвится прямым DNS / a domain-named DNS server is resolved by direct DNS
    if [[ ! "${server}" =~ ^[0-9.]+$ && "${server}" != *:* && "${tag}" != "dns-direct" ]]; then
        resolver='"domain_resolver":"dns-direct"'
    fi
    vpn::singbox::__obj "$(vpn::singbox::__s type "${type}")" \
        "$(vpn::singbox::__s tag "${tag}")" \
        "$(vpn::singbox::__s server "${server}")" \
        "$(vpn::singbox::__n server_port "${port}")" \
        "$( [[ "${type}" == "https" || "${type}" == "h3" ]] && vpn::singbox::__s path "${path}")" \
        "$(vpn::singbox::__s detour "${detour}")" \
        "${resolver}"
}

# @private
# @description Rule-set tags of a routing preset / Теги rule-set пресета маршрутизации.
# @param $1 route preset / пресет
# @stdout tags, space separated / теги через пробел
vpn::singbox::__preset_sets() {
    case "$1" in
        bypass-ru) printf 'geosite-category-ru geoip-ru' ;;
        bypass-cn) printf 'geosite-cn geoip-cn' ;;
        bypass-ir) printf 'geosite-category-ir geoip-ir' ;;
    esac
}

# @private
# @description Remote rule-set definition / Описание удалённого rule-set.
# @param $1 tag
vpn::singbox::__rule_set() {
    local -r tag="$1"
    local repo="sing-geosite"
    [[ "${tag}" == geoip-* ]] && repo="sing-geoip"
    local fetch='"download_detour":"proxy"'
    vpn::singbox::version_ge 1.14 && fetch='"http_client":"bs-fetch"'
    vpn::singbox::__obj '"type":"remote"' '"format":"binary"' \
        "$(vpn::singbox::__s tag "${tag}")" \
        "$(vpn::singbox::__s url "${VPN_SINGBOX_RULESET_BASE}/${repo}/rule-set/${tag}.srs")" \
        "${fetch}" '"update_interval":"1d"'
}

# @private
# @description JSON string array from words / JSON-массив строк из слов.
vpn::singbox::__words() {
    local out="" w
    for w in "$@"; do
        out+="${out:+,}\"$(vpn::link::json_escape "${w}")\""
    done
    printf '[%s]' "${out}"
}

# @description Render the full client config for a set of profiles.
# @description Отрисовать полный конфиг клиента для набора профилей.
#   The first id is the selected server; all ids go into the "proxy" selector
#   (switchable live via the Clash API) and, with two or more, into "auto"
#   (urltest). Settings come from vpn::settings::get.
#   Первый id — выбранный сервер; все id идут в селектор «proxy»
#   (переключается на лету через Clash API) и, если их два и больше, — в
#   «auto» (urltest). Настройки берутся из vpn::settings::get.
# @param $@ profile ids, the selected one first / id профилей, выбранный первым
# @stdout JSON config / JSON-конфиг
# @return 0 ok, LIB_ERROR_INVALID_ARGS no ids, LIB_ERROR_INVALID_INPUT bad profile
vpn::singbox::config() {
    (( $# > 0 )) || {
        printf 'не выбран профиль / no profile selected\n' >&2
        return "${LIB_ERROR_INVALID_ARGS}"
    }
    local -r selected="$1"
    local -a ids=("$@")
    local -A s=()
    local key
    for key in "${VPN_SETTINGS_ORDER[@]}"; do
        s["${key}"]="$(vpn::settings::get "${key}")"
    done
    s[api_secret]="$(vpn::settings::secret)"

    # outbounds / выходы
    local -a obs=()
    local id ob
    for id in "${ids[@]}"; do
        local -A p=()
        vpn::store::load "${id}" p || return $?
        ob="$(vpn::singbox::outbound p "${id}")" || return $?
        obs+=("${ob}")
        unset p
    done
    local -r ids_json="$(vpn::singbox::__words "${ids[@]}")"
    local auto="" default="${selected}" members="${ids_json}"
    if (( ${#ids[@]} > 1 )); then
        auto="$(vpn::singbox::__obj '"type":"urltest"' '"tag":"auto"' \
            "\"outbounds\":${ids_json}" "$(vpn::singbox::__s url "${s[test_url]}")" \
            '"interval":"3m"' '"tolerance":50')"
        members="$(vpn::singbox::__words auto "${ids[@]}")"
        [[ "${s[auto_select]}" == 1 ]] && default="auto"
    fi
    local -r selector="$(vpn::singbox::__obj '"type":"selector"' '"tag":"proxy"' \
        "\"outbounds\":${members}" "$(vpn::singbox::__s default "${default}")" \
        '"interrupt_exist_connections":true')"

    # inbounds / входы
    local listen="127.0.0.1"
    [[ "${s[allow_lan]}" == 1 ]] && listen="0.0.0.0"
    local -a ins=()
    ins+=("$(vpn::singbox::__obj '"type":"mixed"' '"tag":"mixed-in"' \
        "$(vpn::singbox::__s listen "${listen}")" \
        "$(vpn::singbox::__n listen_port "${s[listen_port]}")" \
        "$(vpn::singbox::__b set_system_proxy "${s[system_proxy]}")")")
    if [[ "${s[mode]}" == "tun" ]]; then
        local addr='["172.19.0.1/30"]'
        [[ "${s[ipv6]}" == 1 ]] && addr='["172.19.0.1/30","fdfe:dcba:9876::1/126"]'
        ins+=("$(vpn::singbox::__obj '"type":"tun"' '"tag":"tun-in"' \
            '"interface_name":"bs-tun"' "\"address\":${addr}" \
            "$(vpn::singbox::__n mtu "${s[tun_mtu]}")" '"auto_route":true' \
            "$(vpn::singbox::__b strict_route "${s[strict_route]}")" \
            "$(vpn::singbox::__s stack "${s[tun_stack]}")")")
    fi

    # rule-sets / наборы правил
    local -a sets=()
    local preset_sets
    preset_sets="$(vpn::singbox::__preset_sets "${s[route]}")"
    is::not_empty "${preset_sets}" && IFS=' ' read -ra sets <<< "${preset_sets}"
    [[ "${s[block_ads]}" == 1 ]] && sets+=("geosite-category-ads-all")
    local -a set_defs=()
    local tag
    for tag in "${sets[@]}"; do
        set_defs+=("$(vpn::singbox::__rule_set "${tag}")")
    done

    # route rules / правила маршрутизации
    local -a rules=('{"action":"sniff"}' '{"protocol":"dns","action":"hijack-dns"}' \
        '{"ip_is_private":true,"outbound":"direct"}')
    local list
    list="$(vpn::singbox::__csv "${s[block_domains]}")"
    is::not_empty "${list}" && rules+=("{\"domain_suffix\":${list},\"action\":\"reject\"}")
    [[ "${s[block_ads]}" == 1 ]] && rules+=('{"rule_set":["geosite-category-ads-all"],"action":"reject"}')
    list="$(vpn::singbox::__csv "${s[proxy_domains]}")"
    is::not_empty "${list}" && rules+=("{\"domain_suffix\":${list},\"outbound\":\"proxy\"}")
    list="$(vpn::singbox::__csv "${s[direct_domains]}")"
    is::not_empty "${list}" && rules+=("{\"domain_suffix\":${list},\"outbound\":\"direct\"}")
    local direct_sets=""
    if is::not_empty "${preset_sets}"; then
        local -a pw=()
        IFS=' ' read -ra pw <<< "${preset_sets}"
        direct_sets="$(vpn::singbox::__words "${pw[@]}")"
        [[ "${s[route]}" == "bypass-ru" ]] && rules+=('{"domain_suffix":["ru","su","xn--p1ai"],"outbound":"direct"}')
        rules+=("{\"rule_set\":${direct_sets},\"outbound\":\"direct\"}")
    fi
    local final="proxy"
    [[ "${s[route]}" == "direct" ]] && final="direct"

    # DNS / DNS
    local -a dns_rules=()
    list="$(vpn::singbox::__csv "${s[direct_domains]}")"
    is::not_empty "${list}" && dns_rules+=("{\"domain_suffix\":${list},\"server\":\"dns-direct\"}")
    if is::not_empty "${preset_sets}"; then
        local -a gs=()
        local w
        for w in "${pw[@]}"; do [[ "${w}" == geosite-* ]] && gs+=("${w}"); done
        (( ${#gs[@]} > 0 )) && dns_rules+=("{\"rule_set\":$(vpn::singbox::__words "${gs[@]}"),\"server\":\"dns-direct\"}")
        [[ "${s[route]}" == "bypass-ru" ]] && dns_rules+=('{"domain_suffix":["ru","su","xn--p1ai"],"server":"dns-direct"}')
    fi
    local dns_final="dns-remote"
    [[ "${final}" == "direct" ]] && dns_final="dns-direct"
    local strategy=""
    [[ "${s[ipv6]}" == 0 ]] && strategy='"strategy":"ipv4_only"'
    local -r dns="$(vpn::singbox::__obj \
        "\"servers\":$(vpn::singbox::__arr "$(vpn::singbox::__dns_server "${s[dns_remote]}" dns-remote proxy)" \
            "$(vpn::singbox::__dns_server "${s[dns_direct]}" dns-direct)")" \
        "$( (( ${#dns_rules[@]} > 0 )) && printf '"rules":%s' "$(vpn::singbox::__arr "${dns_rules[@]}")")" \
        "\"final\":\"${dns_final}\"" "${strategy}")"

    local -r state="$(vpn::store::state)"
    local -r route="$(vpn::singbox::__obj \
        "\"rules\":$(vpn::singbox::__arr "${rules[@]}")" \
        "$( (( ${#set_defs[@]} > 0 )) && printf '"rule_set":%s' "$(vpn::singbox::__arr "${set_defs[@]}")")" \
        "\"final\":\"${final}\"" '"auto_detect_interface":true' \
        '"default_domain_resolver":"dns-direct"')"
    local http_clients=""
    if (( ${#set_defs[@]} > 0 )) && vpn::singbox::version_ge 1.14; then
        http_clients='"http_clients":[{"tag":"bs-fetch","detour":"proxy"}]'
    fi
    local -r experimental="$(vpn::singbox::__obj \
        "\"clash_api\":$(vpn::singbox::__obj "\"external_controller\":\"127.0.0.1:${s[api_port]}\"" \
            "$(vpn::singbox::__s secret "${s[api_secret]}")")" \
        "\"cache_file\":$(vpn::singbox::__obj '"enabled":true' "$(vpn::singbox::__s path "${state}/cache.db")")")"

    vpn::singbox::__obj \
        "\"log\":$(vpn::singbox::__obj "$(vpn::singbox::__s level "${s[log_level]}")" '"timestamp":true')" \
        "\"dns\":${dns}" \
        "\"inbounds\":$(vpn::singbox::__arr "${ins[@]}")" \
        "\"outbounds\":$(vpn::singbox::__arr "${selector}" "${auto}" "${obs[@]}" '{"type":"direct","tag":"direct"}')" \
        "\"route\":${route}" \
        "${http_clients}" \
        "\"experimental\":${experimental}"
    printf '\n'
}

# @description Minimal config for latency tests: outbounds + Clash API, no inbounds.
# @description Минимальный конфиг для замера задержки: outbound + Clash API, без входов.
# @param $1 api port / порт API
# @param $@ profile ids (after the port) / id профилей (после порта)
# @stdout JSON config / JSON-конфиг
vpn::singbox::test_config() {
    local -r api_port="${1:?api port required}"
    shift
    local -a obs=()
    local id ob
    for id in "$@"; do
        local -A p=()
        vpn::store::load "${id}" p 2>/dev/null || continue
        ob="$(vpn::singbox::outbound p "${id}" 2>/dev/null)" || continue
        obs+=("${ob}")
        unset p
    done
    vpn::singbox::__obj '"log":{"level":"error"}' \
        '"dns":{"servers":[{"type":"local","tag":"dns-direct"}]}' \
        "\"outbounds\":$(vpn::singbox::__arr "${obs[@]}" '{"type":"direct","tag":"direct"}')" \
        '"route":{"final":"direct","default_domain_resolver":"dns-direct"}' \
        "\"experimental\":{\"clash_api\":{\"external_controller\":\"127.0.0.1:${api_port}\"}}"
    printf '\n'
}
