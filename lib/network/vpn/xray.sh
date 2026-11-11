#!/usr/bin/env bs
# shellcheck shell=bash
# lib/network/vpn/xray.sh — Xray-core JSON config from profiles and settings (second core)
# lib/network/vpn/xray.sh — JSON-конфиг Xray-core из профилей и настроек (второе ядро)
#
# Xray is used for what sing-box cannot do: the XHTTP (splithttp) transport
# and VLESS encryption (mlkem768x25519plus). Profiles become outbounds tagged
# "p:<id>"; one balancer "proxy" holds them all, so the server is switched live
# through the API (balancer override), and "auto" is the leastPing strategy
# fed by the observatory. Statistics go through the StatsService API.
# Xray нужен для того, чего нет в sing-box: транспорт XHTTP (splithttp) и
# шифрование VLESS (mlkem768x25519plus). Профили становятся outbound с тегом
# «p:<id>»; один балансировщик «proxy» держит их все, поэтому сервер меняется
# на лету через API (override балансировщика), а «auto» — стратегия leastPing
# по данным observatory. Статистика — через API StatsService.
#
# Profile tags carry the "p:" prefix because balancer selectors match tag
# prefixes: an id like "d" would otherwise also select "direct".
# У тегов профилей префикс «p:»: селекторы балансировщика сравнивают префиксы,
# и id вроде «d» иначе выбрал бы и «direct».
#
# @depends core/lang, core/const, lib/network/vpn/link, lib/network/vpn/store, lib/network/vpn/singbox
# @tier core
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], arithmetic command (( )), array, nameref, local/declare flags / needs bash constructs: double-bracket [[ ]], arithmetic command (( )), array, nameref, local/declare flags

# Карты профиля передаются по имени (local -n): ShellCheck принимает их ключи
# за переменные — SC2154 на всю библиотеку.
# Profile maps are passed by name (local -n): ShellCheck reads their keys as
# variables — SC2154 for the whole file.
# shellcheck disable=SC2154

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_NETWORK_VPN_XRAY" || return 0

# Dependencies / Зависимости
bs::source_relative "../../../core/lang.sh" "../../../core/const.sh" "link.sh" "store.sh" "singbox.sh"

# @global VPN_XRAY_GEO — Vpn xray: 1 when geoip.dat/geosite.dat are available to the core (category: hook)
# @global VPN_XRAY_GEO — Vpn xray: 1, если ядру доступны geoip.dat/geosite.dat (категория: hook)
declare -g VPN_XRAY_GEO="${VPN_XRAY_GEO:-0}"

# @global VPN_XRAY_PROTOS — Vpn xray: protocols Xray can dial (category: constant)
# @global VPN_XRAY_PROTOS — Vpn xray: протоколы, к которым умеет подключаться Xray (категория: constant)
# shellcheck disable=SC2034 # читается по имени через arr::contains / read by name via arr::contains
declare -ga VPN_XRAY_PROTOS=(vless vmess trojan shadowsocks socks wireguard)

# @global VPN_XRAY_PRIVATE_NETS — Vpn xray: private ranges that always go direct (category: constant)
# @global VPN_XRAY_PRIVATE_NETS — Vpn xray: частные сети, всегда напрямую (категория: constant)
declare -ga VPN_XRAY_PRIVATE_NETS=(10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 127.0.0.0/8 \
    169.254.0.0/16 100.64.0.0/10 fc00::/7 fe80::/10 ::1/128)

# @description Outbound tag of a profile / Тег outbound профиля.
# @param $1 id
vpn::xray::tag() {
    printf 'p:%s' "${1:?id required}"
}

# @description Can Xray dial this profile? (protocol, transport, no sing-box-only features)
# @description Может ли Xray подключиться к этому профилю? (протокол, транспорт, без возможностей только sing-box)
# @param $1 profile map name / имя карты профиля
# @return 0 yes, 1 no
vpn::xray::supports() {
    local -n __vx_s="${1:?map name required}"
    arr::contains VPN_XRAY_PROTOS "${__vx_s[proto]:-}" || return 1
    [[ "$(vpn::link::core_need "${1}")" != "sing-box" ]]
}

# Stream settings / Настройки потока

# @private
# @description streamSettings of a profile: transport + TLS/REALITY.
# @description streamSettings профиля: транспорт + TLS/REALITY.
# @param $1 profile map name / имя карты профиля
vpn::xray::__stream() {
    local -n __vx_t="${1:?}"
    local -r transport="${__vx_t[transport]:-tcp}" security="${__vx_t[security]:-none}"
    local net="" settings=""
    local -r path="${__vx_t[path]:-}" host="${__vx_t[host]:-}"
    case "${transport}" in
        tcp) net="raw" ;;
        ws)
            net="ws"
            settings="\"wsSettings\":$(vpn::singbox::__obj "$(vpn::singbox::__s path "${path:-/}")" "$(vpn::singbox::__s host "${host}")")" ;;
        grpc)
            net="grpc"
            settings="\"grpcSettings\":$(vpn::singbox::__obj "$(vpn::singbox::__s serviceName "${__vx_t[service_name]:-}")")" ;;
        httpupgrade)
            net="httpupgrade"
            settings="\"httpupgradeSettings\":$(vpn::singbox::__obj "$(vpn::singbox::__s path "${path:-/}")" "$(vpn::singbox::__s host "${host}")")" ;;
        xhttp)
            net="xhttp"
            # extra проверен vpn::link::validate как JSON-объект / extra is checked as a JSON object by vpn::link::validate
            settings="\"xhttpSettings\":$(vpn::singbox::__obj "$(vpn::singbox::__s path "${path:-/}")" \
                "$(vpn::singbox::__s host "${host}")" "$(vpn::singbox::__s mode "${__vx_t[mode]:-auto}")" \
                "$(vpn::singbox::__r extra "${__vx_t[extra]:-}")")" ;;
        *)
            printf 'транспорт %s не поддерживается Xray / transport not supported by Xray\n' "${transport}" >&2
            return "${LIB_ERROR_INVALID_INPUT}" ;;
    esac
    local tls=""
    case "${security}" in
        tls)
            tls="\"tlsSettings\":$(vpn::singbox::__obj \
                "$(vpn::singbox::__s serverName "${__vx_t[sni]:-}")" \
                "$(vpn::singbox::__r alpn "$(vpn::singbox::__csv "${__vx_t[alpn]:-}")")" \
                "$(vpn::singbox::__s fingerprint "${__vx_t[fp]:-}")" \
                "$(vpn::singbox::__s pinnedPeerCertSha256 "${__vx_t[pcs]:-}")" \
                "$(vpn::singbox::__s verifyPeerCertByName "${__vx_t[vcn]:-}")" \
                "$( [[ "${__vx_t[insecure]:-0}" == 1 && -z "${__vx_t[pcs]:-}" ]] && printf '"allowInsecure":true')")" ;;
        reality)
            tls="\"realitySettings\":$(vpn::singbox::__obj \
                "$(vpn::singbox::__s serverName "${__vx_t[sni]:-}")" \
                "$(vpn::singbox::__s fingerprint "${__vx_t[fp]:-chrome}")" \
                "$(vpn::singbox::__s publicKey "${__vx_t[pbk]:-}")" \
                "$(vpn::singbox::__s shortId "${__vx_t[sid]:-}")" \
                "$(vpn::singbox::__s spiderX "${__vx_t[spx]:-}")" \
                "$(vpn::singbox::__s mldsa65Verify "${__vx_t[pqv]:-}")")" ;;
    esac
    local sec="none"
    [[ "${security}" == "tls" || "${security}" == "reality" ]] && sec="${security}"
    vpn::singbox::__obj "$(vpn::singbox::__s network "${net}")" "$(vpn::singbox::__s security "${sec}")" \
        "${tls}" "${settings}"
}

# @description Render one profile as an Xray outbound object.
# @description Отрисовать один профиль как объект outbound Xray.
# @param $1 profile map name / имя карты профиля
# @param $2 tag / тег
# @stdout JSON object / JSON-объект
# @return 0 ok, LIB_ERROR_INVALID_INPUT invalid profile or not supported by Xray
vpn::xray::outbound() {
    local -n __vx_o="${1:?map name required}"
    local -r tag="${2:?tag required}"
    vpn::link::validate "${1}" || return $?
    vpn::xray::supports "${1}" || {
        printf 'профиль не поддерживается Xray / profile not supported by Xray: %s\n' "${__vx_o[proto]}" >&2
        return "${LIB_ERROR_INVALID_INPUT}"
    }
    local -r proto="${__vx_o[proto]}"
    local -r head="$(vpn::singbox::__s tag "${tag}"),$(vpn::singbox::__s protocol "${proto}")"
    local -r addr="$(vpn::singbox::__s address "${__vx_o[server]}"),$(vpn::singbox::__n port "${__vx_o[port]}")"
    local stream=""
    case "${proto}" in
        vless|vmess|trojan)
            stream="$(vpn::xray::__stream "${1}")" || return $? ;;
    esac
    case "${proto}" in
        vless)
            local -r user="$(vpn::singbox::__obj "$(vpn::singbox::__s id "${__vx_o[uuid]}")" \
                "$(vpn::singbox::__s encryption "${__vx_o[encryption]:-none}")" \
                "$(vpn::singbox::__s flow "${__vx_o[flow]:-}")")"
            vpn::singbox::__obj "${head}" \
                "\"settings\":{\"vnext\":[{${addr},\"users\":[${user}]}]}" \
                "\"streamSettings\":${stream}" ;;
        vmess)
            local -r user="$(vpn::singbox::__obj "$(vpn::singbox::__s id "${__vx_o[uuid]}")" \
                "$(vpn::singbox::__s security "${__vx_o[cipher]:-auto}")")"
            vpn::singbox::__obj "${head}" \
                "\"settings\":{\"vnext\":[{${addr},\"users\":[${user}]}]}" \
                "\"streamSettings\":${stream}" ;;
        trojan)
            vpn::singbox::__obj "${head}" \
                "\"settings\":{\"servers\":[$(vpn::singbox::__obj "${addr}" "$(vpn::singbox::__s password "${__vx_o[password]}")")]}" \
                "\"streamSettings\":${stream}" ;;
        shadowsocks)
            vpn::singbox::__obj "${head}" \
                "\"settings\":{\"servers\":[$(vpn::singbox::__obj "${addr}" \
                    "$(vpn::singbox::__s method "${__vx_o[method]}")" \
                    "$(vpn::singbox::__s password "${__vx_o[password]:-}")" '"uot":true')]}" ;;
        socks)
            local users=""
            if is::not_empty "${__vx_o[username]:-}"; then
                users="\"users\":[$(vpn::singbox::__obj "$(vpn::singbox::__s user "${__vx_o[username]}")" \
                    "$(vpn::singbox::__s pass "${__vx_o[password]:-}")")]"
            fi
            vpn::singbox::__obj "${head}" \
                "\"settings\":{\"servers\":[$(vpn::singbox::__obj "${addr}" "${users}")]}" ;;
        wireguard)
            local endpoint="${__vx_o[server]}"
            [[ "${endpoint}" == *:* ]] && endpoint="[${endpoint}]"
            local reserved=""
            is::not_empty "${__vx_o[reserved]:-}" && reserved="[${__vx_o[reserved]}]"
            local -r peer="$(vpn::singbox::__obj "$(vpn::singbox::__s publicKey "${__vx_o[peer_key]}")" \
                "$(vpn::singbox::__s preSharedKey "${__vx_o[psk]:-}")" \
                "$(vpn::singbox::__s endpoint "${endpoint}:${__vx_o[port]}")" \
                "$(vpn::singbox::__n keepAlive "${__vx_o[keepalive]:-}")")"
            vpn::singbox::__obj "${head}" "\"settings\":$(vpn::singbox::__obj \
                "$(vpn::singbox::__s secretKey "${__vx_o[private_key]}")" \
                "\"address\":$(vpn::singbox::__csv "$(vpn::singbox::__prefixes "${__vx_o[address]}")")" \
                "\"peers\":[${peer}]" \
                "$(vpn::singbox::__n mtu "${__vx_o[mtu]:-}")" \
                "$(vpn::singbox::__r reserved "${reserved}")" '"noKernelTun":true')" ;;
    esac
}

# Config sections / Секции конфига

# @private
# @description Xray name server from a DNS setting (https://, tcp://, udp://, IP, local).
# @description DNS-сервер Xray из настройки (https://, tcp://, udp://, IP, local).
#   DoT (tls://) has no Xray client: DoH on the same host is used instead.
#   У Xray нет клиента DoT (tls://): вместо него — DoH на том же хосте.
# @param $1 value / значение
vpn::xray::__dns() {
    local v="${1-}"
    case "${v}" in
        local) v="localhost" ;;
        udp://*) v="${v#udp://}" ;;
        tls://*) v="${v#tls://}"; v="https://${v%%/*}/dns-query" ;;
        h3://*) v="https://${v#h3://}" ;;
        quic://*) v="quic+local://${v#quic://}" ;;
    esac
    printf '"%s"' "$(vpn::link::json_escape "${v}")"
}

# @private
# @description Domain list setting (CSV) as Xray "domain:" matchers.
# @description Список доменов из настройки (CSV) как матчеры Xray «domain:».
vpn::xray::__domains() {
    is::empty "${1-}" && return 0
    local -a items=() words=()
    local item
    IFS=',' read -ra items <<< "$1"
    for item in "${items[@]}"; do
        item="${item//[[:space:]]/}"
        item="${item#\*.}"
        is::empty "${item}" && continue
        words+=("domain:${item}")
    done
    (( ${#words[@]} > 0 )) && vpn::singbox::__words "${words[@]}"
    return 0
}

# @private
# @description geosite/geoip codes of a routing preset / Коды geosite/geoip пресета маршрутизации.
# @param $1 route preset / пресет
# @stdout "geosite-code geoip-code"
vpn::xray::__preset_codes() {
    case "$1" in
        bypass-ru) printf 'category-ru ru' ;;
        bypass-cn) printf 'cn cn' ;;
        bypass-ir) printf 'category-ir ir' ;;
    esac
}

# @description Render the full Xray client config for a set of profiles.
# @description Отрисовать полный конфиг клиента Xray для набора профилей.
#   The first id is the selected server. Every profile joins the balancer
#   "proxy"; the selection is fixed at start with a balancer override (see
#   vpn::core::start), "auto" removes the override and leastPing decides.
#   Первый id — выбранный сервер. Все профили входят в балансировщик «proxy»;
#   выбор закрепляется при старте override (см. vpn::core::start), «auto»
#   снимает override, и решает leastPing.
# @param $@ profile ids, the selected one first / id профилей, выбранный первым
# @stdout JSON config / JSON-конфиг
# @return 0 ok, LIB_ERROR_INVALID_ARGS no ids, LIB_ERROR_INVALID_INPUT bad profile
vpn::xray::config() {
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

    local -a obs=() tags=()
    local id ob
    for id in "${ids[@]}"; do
        local -A p=()
        vpn::store::load "${id}" p || return $?
        ob="$(vpn::xray::outbound p "$(vpn::xray::tag "${id}")")" || return $?
        obs+=("${ob}")
        tags+=("$(vpn::xray::tag "${id}")")
        unset p
    done
    local -r tags_json="$(vpn::singbox::__words "${tags[@]}")"

    local listen="127.0.0.1"
    [[ "${s[allow_lan]}" == 1 ]] && listen="0.0.0.0"
    # socks-вход Xray принимает и HTTP-прокси на том же порту / Xray's socks inbound also serves HTTP on the same port
    local -r inbound="$(vpn::singbox::__obj '"tag":"mixed-in"' '"protocol":"socks"' \
        "$(vpn::singbox::__s listen "${listen}")" "$(vpn::singbox::__n port "${s[listen_port]}")" \
        '"settings":{"udp":true,"auth":"noauth"}' \
        '"sniffing":{"enabled":true,"destOverride":["http","tls","quic"],"routeOnly":true}')"

    # правила маршрутизации / routing rules
    local -a rules=("{\"type\":\"field\",\"ip\":$(vpn::singbox::__words "${VPN_XRAY_PRIVATE_NETS[@]}"),\"outboundTag\":\"direct\"}")
    local list
    list="$(vpn::xray::__domains "${s[block_domains]}")"
    is::not_empty "${list}" && rules+=("{\"type\":\"field\",\"domain\":${list},\"outboundTag\":\"block\"}")
    [[ "${s[block_ads]}" == 1 && "${VPN_XRAY_GEO}" == 1 ]] \
        && rules+=('{"type":"field","domain":["geosite:category-ads-all"],"outboundTag":"block"}')
    list="$(vpn::xray::__domains "${s[proxy_domains]}")"
    is::not_empty "${list}" && rules+=("{\"type\":\"field\",\"domain\":${list},\"balancerTag\":\"proxy\"}")
    list="$(vpn::xray::__domains "${s[direct_domains]}")"
    is::not_empty "${list}" && rules+=("{\"type\":\"field\",\"domain\":${list},\"outboundTag\":\"direct\"}")
    local strategy="AsIs" codes
    codes="$(vpn::xray::__preset_codes "${s[route]}")"
    local -a direct_dns=()
    if is::not_empty "${codes}"; then
        local site="${codes% *}" ip="${codes#* }"
        if [[ "${s[route]}" == "bypass-ru" ]]; then
            rules+=('{"type":"field","domain":["domain:ru","domain:su","domain:xn--p1ai"],"outboundTag":"direct"}')
            direct_dns+=("domain:ru" "domain:su" "domain:xn--p1ai")
        fi
        # без geo-файлов остаются только доменные зоны / without geo files only the domain zones remain
        if [[ "${VPN_XRAY_GEO}" == 1 ]]; then
            rules+=("{\"type\":\"field\",\"domain\":[\"geosite:${site}\"],\"outboundTag\":\"direct\"}")
            rules+=("{\"type\":\"field\",\"ip\":[\"geoip:${ip}\"],\"outboundTag\":\"direct\"}")
            direct_dns+=("geosite:${site}")
            strategy="IPIfNonMatch"
        fi
    fi
    if [[ "${s[route]}" == "direct" ]]; then
        rules+=('{"type":"field","network":"tcp,udp","outboundTag":"direct"}')
    else
        rules+=('{"type":"field","network":"tcp,udp","balancerTag":"proxy"}')
    fi

    local balancer_strategy='{"type":"random"}' observatory=""
    if (( ${#ids[@]} > 1 )); then
        balancer_strategy='{"type":"leastPing"}'
        observatory="\"observatory\":$(vpn::singbox::__obj "\"subjectSelector\":${tags_json}" \
            "$(vpn::singbox::__s probeURL "${s[test_url]}")" '"probeInterval":"3m"' '"enableConcurrency":true')"
    fi
    local -r balancer="$(vpn::singbox::__obj '"tag":"proxy"' "\"selector\":${tags_json}" \
        "\"strategy\":${balancer_strategy}" "$(vpn::singbox::__s fallbackTag "$(vpn::xray::tag "${selected}")")")"
    local -r routing="$(vpn::singbox::__obj "$(vpn::singbox::__s domainStrategy "${strategy}")" \
        "\"rules\":$(vpn::singbox::__arr "${rules[@]}")" "\"balancers\":[${balancer}]")"

    # DNS: удалённый для всего, прямой — для прямых доменов / remote for everything, direct for direct domains
    local -a dns_servers=("$(vpn::xray::__dns "${s[dns_remote]}")")
    list="$(vpn::xray::__domains "${s[direct_domains]}")"
    if is::not_empty "${list}" || (( ${#direct_dns[@]} > 0 )); then
        local -a dd=()
        is::not_empty "${list}" && { list="${list#[}"; list="${list%]}"; dd+=("${list}"); }
        (( ${#direct_dns[@]} > 0 )) && { local w; w="$(vpn::singbox::__words "${direct_dns[@]}")"; w="${w#[}"; dd+=("${w%]}"); }
        local -r dd_json="[$(IFS=','; printf '%s' "${dd[*]}")]"
        dns_servers+=("{\"address\":$(vpn::xray::__dns "${s[dns_direct]}"),\"domains\":${dd_json},\"skipFallback\":true}")
    fi
    local query="UseIP"
    [[ "${s[ipv6]}" == 0 ]] && query="UseIPv4"
    local -r dns="$(vpn::singbox::__obj "\"servers\":$(vpn::singbox::__arr "${dns_servers[@]}")" \
        "$(vpn::singbox::__s queryStrategy "${query}")")"

    local level
    case "${s[log_level]}" in
        trace) level="debug" ;;
        warn) level="warning" ;;
        *) level="${s[log_level]}" ;;
    esac

    vpn::singbox::__obj \
        "\"log\":$(vpn::singbox::__obj "$(vpn::singbox::__s loglevel "${level}")" '"access":"none"')" \
        "\"api\":{\"tag\":\"api\",\"listen\":\"127.0.0.1:${s[api_port]}\",\"services\":[\"StatsService\",\"RoutingService\"]}" \
        '"stats":{}' \
        '"policy":{"system":{"statsOutboundUplink":true,"statsOutboundDownlink":true}}' \
        "\"dns\":${dns}" \
        "\"inbounds\":[${inbound}]" \
        "\"outbounds\":$(vpn::singbox::__arr "${obs[@]}" '{"tag":"direct","protocol":"freedom"}' '{"tag":"block","protocol":"blackhole"}')" \
        "\"routing\":${routing}" \
        "${observatory}"
    printf '\n'
}

# @description Config for latency tests: one local SOCKS inbound per profile, routed to its outbound.
# @description Конфиг для замера задержки: по локальному SOCKS-входу на профиль, ведущему в его outbound.
#   Ports go from the base up in the order of the ids that rendered; VPN_XRAY_TEST_IDS lists them.
#   Порты идут от базового по порядку отрисованных id; их список — в VPN_XRAY_TEST_IDS.
# @param $1 base port / базовый порт
# @param $@ profile ids (after the port) / id профилей (после порта)
# @stdout JSON config / JSON-конфиг
vpn::xray::test_config() {
    local -ri base="${1:?base port required}"
    shift
    local -a obs=() ins=() rules=()
    local id ob tag
    local -i port="${base}"
    VPN_XRAY_TEST_IDS=()
    for id in "$@"; do
        local -A p=()
        vpn::store::load "${id}" p 2>/dev/null || continue
        tag="$(vpn::xray::tag "${id}")"
        ob="$(vpn::xray::outbound p "${tag}" 2>/dev/null)" || continue
        obs+=("${ob}")
        ins+=("{\"tag\":\"in:${id}\",\"protocol\":\"socks\",\"listen\":\"127.0.0.1\",\"port\":${port},\"settings\":{\"udp\":false}}")
        rules+=("{\"type\":\"field\",\"inboundTag\":[\"in:${id}\"],\"outboundTag\":\"${tag}\"}")
        VPN_XRAY_TEST_IDS+=("${id}")
        port=$(( port + 1 ))
        unset p
    done
    vpn::singbox::__obj '"log":{"loglevel":"error","access":"none"}' \
        "\"inbounds\":$(vpn::singbox::__arr "${ins[@]}")" \
        "\"outbounds\":$(vpn::singbox::__arr "${obs[@]}" '{"tag":"direct","protocol":"freedom"}')" \
        "\"routing\":{\"rules\":$(vpn::singbox::__arr "${rules[@]}")}"
    printf '\n'
}

# @global VPN_XRAY_TEST_IDS — Vpn xray: ids of the last test config, in port order (category: state)
# @global VPN_XRAY_TEST_IDS — Vpn xray: id последнего тестового конфига по порядку портов (категория: state)
declare -ga VPN_XRAY_TEST_IDS=()
