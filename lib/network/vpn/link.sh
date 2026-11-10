#!/usr/bin/env bs
# shellcheck shell=bash
# lib/network/vpn/link.sh — proxy share links (vless/vmess/trojan/ss/hysteria2/
# hysteria/tuic/anytls/socks) to and from profile records
# lib/network/vpn/link.sh — ссылки прокси (vless/vmess/trojan/ss/hysteria2/
# hysteria/tuic/anytls/socks) в записи профилей и обратно
#
# A profile record is a list of "key=value" lines with the canonical keys of
# VPN_LINK_KEYS. Parsing never evaluates input: every value is cleaned of
# control characters, so a record is safe to store and to read back.
# Запись профиля — строки «ключ=значение» с каноническими ключами
# VPN_LINK_KEYS. Разбор никогда не исполняет вход: из значений убираются
# управляющие символы, поэтому запись безопасно хранить и читать обратно.
#
# @depends core/lang, core/const, lib/rfc/uri
# @tier core
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], arithmetic command (( )), array, nameref, local/declare flags / needs bash constructs: double-bracket [[ ]], arithmetic command (( )), array, nameref, local/declare flags

# Карты профиля передаются по имени (local -n): ShellCheck принимает их ключи
# за переменные — SC2154 на всю библиотеку.
# Profile maps are passed by name (local -n): ShellCheck reads their keys as
# variables — SC2154 for the whole file.
# shellcheck disable=SC2154

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_NETWORK_VPN_LINK" || return 0

# Dependencies / Зависимости
bs::source_relative "../../../core/lang.sh" "../../../core/const.sh" "../../rfc/uri.sh"

# @global VPN_LINK_KEYS — Vpn link: canonical profile keys in display order (category: constant)
# @global VPN_LINK_KEYS — Vpn link: канонические ключи профиля в порядке показа (категория: constant)
declare -ga VPN_LINK_KEYS=(name proto server port ports uuid password method \
    username flow security sni alpn fp pbk sid insecure transport path host \
    service_name obfs obfs_password up_mbps down_mbps auth congestion \
    udp_relay alter_id cipher plugin plugin_opts packet_encoding group)

# @global VPN_LINK_PROTOS — Vpn link: supported protocols (category: constant)
# @global VPN_LINK_PROTOS — Vpn link: поддерживаемые протоколы (категория: constant)
# shellcheck disable=SC2034 # читается по имени через arr::contains / read by name via arr::contains
declare -ga VPN_LINK_PROTOS=(vless vmess trojan shadowsocks hysteria2 hysteria \
    tuic anytls socks)

# @global VPN_LINK_TRANSPORTS — Vpn link: v2ray transports sing-box supports (category: constant)
# @global VPN_LINK_TRANSPORTS — Vpn link: транспорты v2ray, которые знает sing-box (категория: constant)
# shellcheck disable=SC2034 # читается по имени через arr::contains / read by name via arr::contains
declare -ga VPN_LINK_TRANSPORTS=(tcp ws grpc http httpupgrade quic)

# Base64 / Base64

# @description Decode standard or URL-safe base64, padding optional.
# @description Декодировать обычный или URL-safe base64, паддинг необязателен.
# @param $1 encoded text / закодированный текст
# @stdout decoded bytes / декодированные байты
# @return 0 ok, LIB_ERROR_INVALID_INPUT not base64, LIB_ERROR_DEPENDENCY_MISSING no decoder
vpn::link::b64decode() {
    local s="${1-}"
    s="${s//[$' \t\r\n']/}"
    s="${s//-/+}"
    s="${s//_//}"
    s="${s%%=*}"
    [[ "${s}" =~ ^[A-Za-z0-9+/]*$ ]] || return "${LIB_ERROR_INVALID_INPUT}"
    is::empty "${s}" && return "${LIB_ERROR_INVALID_INPUT}"
    case $(( ${#s} % 4 )) in
        1) return "${LIB_ERROR_INVALID_INPUT}" ;;
        2) s+="==" ;;
        3) s+="=" ;;
    esac
    # Цепочка декодеров: GNU/busybox base64 -d, BSD base64 -D, openssl
    # Decoder chain: GNU/busybox base64 -d, BSD base64 -D, openssl
    if is::command base64; then
        printf '%s' "${s}" | base64 -d 2>/dev/null && return 0
        printf '%s' "${s}" | base64 -D 2>/dev/null && return 0
    fi
    if is::command openssl; then
        printf '%s\n' "${s}" | openssl base64 -d -A 2>/dev/null && return 0
    fi
    return "${LIB_ERROR_DEPENDENCY_MISSING}"
}

# @description Encode text as standard base64 without line breaks.
# @description Закодировать текст в обычный base64 без переносов строк.
# @param $1 text / текст
# @stdout base64
vpn::link::b64encode() {
    local -r s="${1-}"
    if is::command base64; then
        printf '%s' "${s}" | base64 | tr -d '\n'
    elif is::command openssl; then
        printf '%s' "${s}" | openssl base64 -A
    else
        return "${LIB_ERROR_DEPENDENCY_MISSING}"
    fi
}

# Helpers / Хелперы

# @private
# @description Strip control characters (CR, LF, TAB, ESC …) from a value.
# @description Убрать управляющие символы (CR, LF, TAB, ESC …) из значения.
# @param $1 value / значение
# @stdout clean value / очищенное значение
vpn::link::__clean() {
    local v="${1-}"
    v="${v//[[:cntrl:]]/}"
    printf '%s' "${v}"
}

# @private
# @description Parse a query string into an associative array (decoded).
# @description Разобрать query-строку в ассоциативный массив (с декодированием).
# @param $1 query (without "?") / запрос (без «?»)
# @param $2 name of an associative array to fill / имя ассоц. массива
vpn::link::__query() {
    local -r query="${1-}"
    local -n __vl_q="${2:?array name required}"
    local pair key val
    local -a pairs=()
    IFS='&' read -ra pairs <<< "${query}"
    for pair in "${pairs[@]}"; do
        is::empty "${pair}" && continue
        key="${pair%%=*}"
        if [[ "${pair}" == *=* ]]; then val="${pair#*=}"; else val=""; fi
        key="$(uri::decode "${key}")"
        val="$(uri::decode "${val}")"
        __vl_q["${key}"]="$(vpn::link::__clean "${val}")"
    done
    return 0
}

# @private
# @description Print "key=value" for each non-empty key of a profile map, in canonical order.
# @description Вывести «ключ=значение» для каждого непустого ключа профиля, в каноническом порядке.
# @param $1 name of the associative array / имя ассоц. массива
vpn::link::__emit() {
    local -n __vl_p="${1:?array name required}"
    local key
    for key in "${VPN_LINK_KEYS[@]}"; do
        is::not_empty "${__vl_p[$key]:-}" || continue
        printf '%s=%s\n' "${key}" "$(vpn::link::__clean "${__vl_p[$key]}")"
    done
}

# @private
# @description Fill the common v2ray-style fields (security/sni/transport …) from a query map.
# @description Заполнить общие поля в стиле v2ray (security/sni/transport …) из карты query.
# @param $1 profile map name / имя карты профиля
# @param $2 query map name / имя карты query
vpn::link::__v2ray_common() {
    local -n __vl_dst="${1:?}"
    local -n __vl_src="${2:?}"
    local security="${__vl_src[security]:-}"
    [[ "${security}" == "xtls" ]] && security="tls"
    __vl_dst[security]="${security:-none}"
    __vl_dst[sni]="${__vl_src[sni]:-${__vl_src[peer]:-}}"
    __vl_dst[alpn]="${__vl_src[alpn]:-}"
    __vl_dst[fp]="${__vl_src[fp]:-}"
    __vl_dst[pbk]="${__vl_src[pbk]:-}"
    __vl_dst[sid]="${__vl_src[sid]:-}"
    __vl_dst[flow]="${__vl_src[flow]:-}"
    case "${__vl_src[allowInsecure]:-${__vl_src[insecure]:-${__vl_src[allow_insecure]:-0}}}" in
        1|true|yes) __vl_dst[insecure]=1 ;;
    esac
    local transport="${__vl_src[type]:-tcp}"
    case "${transport}" in
        h2) transport="http" ;;
        raw|"") transport="tcp" ;;
    esac
    __vl_dst[transport]="${transport}"
    # tcp + headerType=http — это http-обфускация v2ray / tcp + headerType=http is v2ray http obfuscation
    if [[ "${transport}" == "tcp" && "${__vl_src[headerType]:-}" == "http" ]]; then
        __vl_dst[transport]="http"
    fi
    __vl_dst[path]="${__vl_src[path]:-}"
    __vl_dst[host]="${__vl_src[host]:-}"
    __vl_dst[service_name]="${__vl_src[serviceName]:-${__vl_src[service_name]:-}}"
    [[ "${transport}" == "grpc" && -z "${__vl_dst[service_name]}" ]] && __vl_dst[service_name]="${__vl_src[path]:-}"
    __vl_dst[packet_encoding]="${__vl_src[packetEncoding]:-}"
    return 0
}

# @private
# @description Parse scheme://userinfo@host:port?query#name into URI_* via uri::parse, decode the name.
# @description Разобрать scheme://userinfo@host:port?query#name через uri::parse, декодировать имя.
# @param $1 link / ссылка
# @param $2 profile map name / имя карты профиля
vpn::link::__authority() {
    local -r link="$1"
    local -n __vl_a="${2:?}"
    # shellcheck disable=SC2034 # заполняет uri::parse; local — чтобы не протечь наружу / filled by uri::parse; local to not leak
    local URI_SCHEME URI_USER URI_PASSWORD URI_HOST URI_PORT URI_PATH URI_QUERY URI_FRAGMENT
    uri::parse "${link}" || return "${LIB_ERROR_INVALID_INPUT}"
    __vl_a[server]="$(vpn::link::__clean "${URI_HOST}")"
    __vl_a[port]="${URI_PORT}"
    __vl_a[name]="$(vpn::link::__clean "$(uri::decode "${URI_FRAGMENT}")")"
    VPN_LINK__USER="$(uri::decode "${URI_USER}")"
    VPN_LINK__PASS="$(uri::decode "${URI_PASSWORD}")"
    VPN_LINK__RAWUSER="${URI_USER}"
    VPN_LINK__QUERY="${URI_QUERY}"
    return 0
}

# @global VPN_LINK__USER — Vpn link: decoded userinfo user of the last link (category: state)
# @global VPN_LINK__USER — Vpn link: декодированный user последней ссылки (категория: state)
declare -g VPN_LINK__USER=""
# @global VPN_LINK__PASS — Vpn link: decoded userinfo password of the last link (category: state)
# @global VPN_LINK__PASS — Vpn link: декодированный пароль последней ссылки (категория: state)
declare -g VPN_LINK__PASS=""
# @global VPN_LINK__RAWUSER — Vpn link: raw userinfo user (category: state)
# @global VPN_LINK__RAWUSER — Vpn link: сырой user из userinfo (категория: state)
declare -g VPN_LINK__RAWUSER=""
# @global VPN_LINK__QUERY — Vpn link: raw query of the last link (category: state)
# @global VPN_LINK__QUERY — Vpn link: сырой query последней ссылки (категория: state)
declare -g VPN_LINK__QUERY=""

# Per-protocol parsers / Разбор по протоколам

# @private
vpn::link::__vless() {
    local -n __vl_p="${2:?}"
    local -A q=()
    vpn::link::__authority "$1" "${2}" || return $?
    vpn::link::__query "${VPN_LINK__QUERY}" q
    __vl_p[proto]="vless"
    __vl_p[uuid]="${VPN_LINK__USER}"
    vpn::link::__v2ray_common "${2}" q
}

# @private
vpn::link::__trojan() {
    local -n __vl_p="${2:?}"
    local -A q=()
    vpn::link::__authority "$1" "${2}" || return $?
    vpn::link::__query "${VPN_LINK__QUERY}" q
    __vl_p[proto]="trojan"
    # пароль trojan может содержать «:» — склеиваем user:password обратно
    # a trojan password may hold ":" — glue user:password back together
    __vl_p[password]="${VPN_LINK__USER}${VPN_LINK__PASS:+:${VPN_LINK__PASS}}"
    vpn::link::__v2ray_common "${2}" q
    # trojan без security= подразумевает TLS / trojan without security= implies TLS
    [[ -z "${q[security]:-}" ]] && __vl_p[security]="tls"
    return 0
}

# @private
vpn::link::__vmess() {
    local -n __vl_p="${2:?}"
    local body="${1#*://}"
    local json
    json="$(vpn::link::b64decode "${body}")" || return "${LIB_ERROR_INVALID_INPUT}"
    [[ "${json}" == *"{"* ]] || return "${LIB_ERROR_INVALID_INPUT}"
    local -A j=()
    vpn::link::__json_flat "${json}" j
    __vl_p[proto]="vmess"
    __vl_p[name]="${j[ps]:-}"
    __vl_p[server]="${j[add]:-}"
    __vl_p[port]="${j[port]:-}"
    __vl_p[uuid]="${j[id]:-}"
    __vl_p[alter_id]="${j[aid]:-0}"
    __vl_p[cipher]="${j[scy]:-auto}"
    local -A q=(
        [security]="${j[tls]:-}" [sni]="${j[sni]:-}" [alpn]="${j[alpn]:-}"
        [fp]="${j[fp]:-}" [type]="${j[net]:-tcp}" [path]="${j[path]:-}"
        [host]="${j[host]:-}" [headerType]="${j[type]:-}"
        [allowInsecure]="${j[allowInsecure]:-${j[insecure]:-0}}"
    )
    [[ "${q[security]}" == "none" ]] && q[security]=""
    vpn::link::__v2ray_common "${2}" q
    [[ "${__vl_p[alter_id]}" == "0" ]] && __vl_p[alter_id]=""
    return 0
}

# @private
# @description Flatten a one-level JSON object into a map (strings, numbers, booleans).
# @description Развернуть одноуровневый JSON-объект в карту (строки, числа, булевы).
#   Enough for vmess links; nested values are skipped.
#   Достаточно для ссылок vmess; вложенные значения пропускаются.
# @param $1 json / JSON
# @param $2 map name / имя карты
vpn::link::__json_flat() {
    local s="$1"
    local -n __vl_j="${2:?}"
    local key val
    s="${s//[$'\r\n\t']/ }"
    local -r re_str='^[[:space:],{]*"([^"\\]*)"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"(.*)$'
    local -r re_lit='^[[:space:],{]*"([^"\\]*)"[[:space:]]*:[[:space:]]*([-0-9.a-z]+)(.*)$'
    while :; do
        if [[ "${s}" =~ ${re_str} ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            s="${BASH_REMATCH[4]}"
            val="${val//\\\//\/}"
            val="${val//\\\"/\"}"
            val="${val//\\\\/\\}"
        elif [[ "${s}" =~ ${re_lit} ]]; then
            key="${BASH_REMATCH[1]}"
            val="${BASH_REMATCH[2]}"
            s="${BASH_REMATCH[3]}"
        else
            break
        fi
        __vl_j["${key}"]="$(vpn::link::__clean "${val}")"
    done
    return 0
}

# @private
vpn::link::__shadowsocks() {
    local -n __vl_p="${2:?}"
    local link="$1" body name="" decoded
    __vl_p[proto]="shadowsocks"
    body="${link#*://}"
    if [[ "${body}" == *"#"* ]]; then
        name="${body#*#}"
        body="${body%%#*}"
    fi
    if [[ "${body}" != *"@"* ]]; then
        # SIP002-legacy: ss://base64(method:password@host:port)
        decoded="$(vpn::link::b64decode "${body%%[/?]*}")" || return "${LIB_ERROR_INVALID_INPUT}"
        body="${decoded}"
        [[ "${link}" == *"?"* ]] && body+="?${link#*\?}"
        body="${body%%#*}"
        local userinfo="${body%@*}"
        body="$(uri::encode "${userinfo%%:*}"):$(uri::encode "${userinfo#*:}")@${body##*@}"
    fi
    vpn::link::__authority "ss://${body}#${name}" "${2}" || return $?
    local method password
    if is::empty "${VPN_LINK__PASS}" && [[ "${VPN_LINK__RAWUSER}" != *%3[Aa]* ]]; then
        # SIP002: userinfo = base64url(method:password)
        decoded="$(vpn::link::b64decode "${VPN_LINK__USER}")" || return "${LIB_ERROR_INVALID_INPUT}"
        method="${decoded%%:*}"
        password="${decoded#*:}"
    elif is::empty "${VPN_LINK__PASS}"; then
        method="${VPN_LINK__USER%%:*}"
        password="${VPN_LINK__USER#*:}"
    else
        method="${VPN_LINK__USER}"
        password="${VPN_LINK__PASS}"
    fi
    __vl_p[method]="$(vpn::link::__clean "${method}")"
    __vl_p[password]="$(vpn::link::__clean "${password}")"
    local -A q=()
    vpn::link::__query "${VPN_LINK__QUERY}" q
    if is::not_empty "${q[plugin]:-}"; then
        __vl_p[plugin]="${q[plugin]%%;*}"
        [[ "${q[plugin]}" == *";"* ]] && __vl_p[plugin_opts]="${q[plugin]#*;}"
    fi
    return 0
}

# @private
vpn::link::__hysteria2() {
    local -n __vl_p="${2:?}"
    local -A q=()
    vpn::link::__authority "$1" "${2}" || return $?
    vpn::link::__query "${VPN_LINK__QUERY}" q
    __vl_p[proto]="hysteria2"
    __vl_p[password]="${VPN_LINK__USER}${VPN_LINK__PASS:+:${VPN_LINK__PASS}}"
    __vl_p[security]="tls"
    __vl_p[sni]="${q[sni]:-${q[peer]:-}}"
    __vl_p[alpn]="${q[alpn]:-}"
    case "${q[insecure]:-0}" in 1|true) __vl_p[insecure]=1 ;; esac
    __vl_p[obfs]="${q[obfs]:-}"
    __vl_p[obfs_password]="${q[obfs-password]:-${q[obfs_password]:-}}"
    __vl_p[up_mbps]="${q[upmbps]:-${q[up]:-}}"
    __vl_p[down_mbps]="${q[downmbps]:-${q[down]:-}}"
    __vl_p[up_mbps]="${__vl_p[up_mbps]%%[!0-9]*}"
    __vl_p[down_mbps]="${__vl_p[down_mbps]%%[!0-9]*}"
    # Port hopping: host:443,20000-30000 или mport=20000-30000
    # Port hopping: host:443,20000-30000 or mport=20000-30000
    local port="${__vl_p[port]}" hop="${q[mport]:-}"
    if [[ "${port}" == *[,-]* ]]; then
        hop="${port}"
        port="${port%%[,-]*}"
    fi
    __vl_p[port]="${port:-443}"
    is::not_empty "${hop}" && __vl_p[ports]="${hop}"
    return 0
}

# @private
vpn::link::__hysteria() {
    local -n __vl_p="${2:?}"
    local -A q=()
    vpn::link::__authority "$1" "${2}" || return $?
    vpn::link::__query "${VPN_LINK__QUERY}" q
    __vl_p[proto]="hysteria"
    __vl_p[security]="tls"
    __vl_p[auth]="${q[auth]:-${VPN_LINK__USER}}"
    __vl_p[sni]="${q[peer]:-${q[sni]:-}}"
    __vl_p[alpn]="${q[alpn]:-}"
    case "${q[insecure]:-0}" in 1|true) __vl_p[insecure]=1 ;; esac
    __vl_p[obfs]="${q[obfsParam]:-${q[obfs]:-}}"
    [[ "${__vl_p[obfs]}" == "xplus" ]] && __vl_p[obfs]="${q[obfsParam]:-}"
    __vl_p[up_mbps]="${q[upmbps]:-${q[up]:-10}}"
    __vl_p[down_mbps]="${q[downmbps]:-${q[down]:-50}}"
    __vl_p[up_mbps]="${__vl_p[up_mbps]%%[!0-9]*}"
    __vl_p[down_mbps]="${__vl_p[down_mbps]%%[!0-9]*}"
    return 0
}

# @private
vpn::link::__tuic() {
    local -n __vl_p="${2:?}"
    local -A q=()
    vpn::link::__authority "$1" "${2}" || return $?
    vpn::link::__query "${VPN_LINK__QUERY}" q
    __vl_p[proto]="tuic"
    __vl_p[uuid]="${VPN_LINK__USER}"
    __vl_p[password]="${VPN_LINK__PASS}"
    __vl_p[security]="tls"
    __vl_p[sni]="${q[sni]:-}"
    __vl_p[alpn]="${q[alpn]:-h3}"
    case "${q[allow_insecure]:-${q[insecure]:-${q[allowInsecure]:-0}}}" in 1|true) __vl_p[insecure]=1 ;; esac
    __vl_p[congestion]="${q[congestion_control]:-${q[congestion]:-bbr}}"
    __vl_p[udp_relay]="${q[udp_relay_mode]:-native}"
    return 0
}

# @private
vpn::link::__anytls() {
    local -n __vl_p="${2:?}"
    local -A q=()
    vpn::link::__authority "$1" "${2}" || return $?
    vpn::link::__query "${VPN_LINK__QUERY}" q
    __vl_p[proto]="anytls"
    __vl_p[password]="${VPN_LINK__USER}${VPN_LINK__PASS:+:${VPN_LINK__PASS}}"
    __vl_p[security]="tls"
    __vl_p[sni]="${q[sni]:-}"
    __vl_p[fp]="${q[fp]:-}"
    __vl_p[alpn]="${q[alpn]:-}"
    case "${q[insecure]:-${q[allowInsecure]:-0}}" in 1|true) __vl_p[insecure]=1 ;; esac
    return 0
}

# @private
vpn::link::__socks() {
    local -n __vl_p="${2:?}"
    vpn::link::__authority "$1" "${2}" || return $?
    __vl_p[proto]="socks"
    if is::not_empty "${VPN_LINK__USER}" && is::empty "${VPN_LINK__PASS}"; then
        # socks://base64(user:pass)@host:port (v2rayN)
        local decoded
        if decoded="$(vpn::link::b64decode "${VPN_LINK__USER}")" && [[ "${decoded}" == *:* ]]; then
            VPN_LINK__USER="${decoded%%:*}"
            VPN_LINK__PASS="${decoded#*:}"
        fi
    fi
    __vl_p[username]="${VPN_LINK__USER}"
    __vl_p[password]="${VPN_LINK__PASS}"
    return 0
}

# Public API / Публичный API

# @description Protocol of a share link by its scheme.
# @description Протокол ссылки по её схеме.
# @param $1 link / ссылка
# @stdout protocol name / имя протокола
# @return 0 known, LIB_ERROR_INVALID_INPUT unknown scheme
vpn::link::scheme_proto() {
    local scheme="${1%%://*}"
    [[ "${1}" == *"://"* ]] || return "${LIB_ERROR_INVALID_INPUT}"
    scheme="$(str::lower "${scheme}")"
    case "${scheme}" in
        vless) printf 'vless\n' ;;
        vmess) printf 'vmess\n' ;;
        trojan) printf 'trojan\n' ;;
        ss) printf 'shadowsocks\n' ;;
        hysteria2|hy2) printf 'hysteria2\n' ;;
        hysteria|hy) printf 'hysteria\n' ;;
        tuic) printf 'tuic\n' ;;
        anytls) printf 'anytls\n' ;;
        socks|socks5) printf 'socks\n' ;;
        *) return "${LIB_ERROR_INVALID_INPUT}" ;;
    esac
}

# @description Is the line a share link this module understands?
# @description Понимает ли модуль эту строку как ссылку?
# @param $1 line / строка
# @return 0 yes, 1 no
vpn::link::is_link() {
    vpn::link::scheme_proto "${1-}" >/dev/null 2>&1
}

# @description Parse a share link into a profile record ("key=value" lines).
# @description Разобрать ссылку в запись профиля (строки «ключ=значение»).
# @param $1 link / ссылка
# @stdout profile record / запись профиля
# @return 0 ok, LIB_ERROR_INVALID_INPUT bad link or missing required fields
# @example
#   vpn::link::parse 'trojan://secret@example.com:443?sni=example.com#DE'
#   # name=DE proto=trojan server=example.com port=443 password=secret …
vpn::link::parse() {
    local link
    link="$(vpn::link::__clean "${1-}")"
    link="${link#"${link%%[![:space:]]*}"}"
    link="${link%"${link##*[![:space:]]}"}"
    local proto
    proto="$(vpn::link::scheme_proto "${link}")" || {
        printf 'неизвестная схема ссылки / unknown link scheme: %s\n' "${link%%://*}" >&2
        return "${LIB_ERROR_INVALID_INPUT}"
    }
    local -A prof=()
    local rc=0
    "vpn::link::__${proto}" "${link}" prof || rc=$?
    if (( rc != 0 )); then
        printf 'не удалось разобрать ссылку / cannot parse %s link\n' "${proto}" >&2
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    vpn::link::validate prof || return $?
    is::empty "${prof[name]:-}" && prof[name]="${prof[server]}:${prof[port]}"
    vpn::link::__emit prof
}

# @description Validate a profile map: required fields per protocol, port range.
# @description Проверить карту профиля: обязательные поля протокола, диапазон порта.
# @param $1 profile map name / имя карты профиля
# @return 0 valid, LIB_ERROR_INVALID_INPUT invalid (reason on stderr)
vpn::link::validate() {
    local -n __vl_v="${1:?map name required}"
    local -r proto="${__vl_v[proto]:-}"
    local reason=""
    if ! arr::contains VPN_LINK_PROTOS "${proto}"; then
        reason="протокол / protocol '${proto}'"
    elif is::empty "${__vl_v[server]:-}"; then
        reason="нет сервера / no server"
    elif ! is::number "${__vl_v[port]:-}" || (( __vl_v[port] < 1 || __vl_v[port] > 65535 )); then
        reason="порт / port '${__vl_v[port]:-}'"
    elif [[ "${__vl_v[server]}" =~ [[:space:]\"\\] ]]; then
        reason="сервер / server '${__vl_v[server]}'"
    else
        case "${proto}" in
            vless|vmess)
                [[ "${__vl_v[uuid]:-}" =~ ^[0-9A-Za-z-]{1,64}$ ]] || reason="uuid '${__vl_v[uuid]:-}'" ;;
            tuic)
                [[ "${__vl_v[uuid]:-}" =~ ^[0-9A-Za-z-]{1,64}$ ]] || reason="uuid '${__vl_v[uuid]:-}'" ;;
            trojan|hysteria2|anytls)
                is::not_empty "${__vl_v[password]:-}" || reason="нет пароля / no password" ;;
            shadowsocks)
                is::not_empty "${__vl_v[method]:-}" || reason="нет метода / no method"
                is::not_empty "${__vl_v[password]:-}" || [[ "${__vl_v[method]:-}" == "none" ]] || reason="нет пароля / no password" ;;
        esac
        local ports="${__vl_v[ports]:-}"
        if is::empty "${reason}" && is::not_empty "${ports}" && [[ ! "${ports}" =~ ^[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$ ]]; then
            reason="диапазон портов / port range '${ports}'"
        fi
        local transport="${__vl_v[transport]:-}"
        if is::empty "${reason}" && is::not_empty "${transport}" && ! arr::contains VPN_LINK_TRANSPORTS "${transport}"; then
            reason="транспорт не поддерживается sing-box / transport not supported by sing-box: ${transport}"
        fi
    fi
    if is::not_empty "${reason}"; then
        printf 'неверный профиль / invalid profile: %s\n' "${reason}" >&2
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    return 0
}

# @description Read a profile record ("key=value" lines) from stdin into a map.
# @description Прочитать запись профиля (строки «ключ=значение») из stdin в карту.
#   Unknown keys are ignored, values are never evaluated.
#   Незнакомые ключи пропускаются, значения никогда не исполняются.
# @param $1 map name / имя карты
vpn::link::read_record() {
    local -n __vl_r="${1:?map name required}"
    local line key
    while IFS= read -r line || is::not_empty "${line}"; do
        [[ "${line}" == *=* ]] || continue
        key="${line%%=*}"
        arr::contains VPN_LINK_KEYS "${key}" || continue
        __vl_r["${key}"]="$(vpn::link::__clean "${line#*=}")"
    done
    return 0
}

# @private
# @description Append "&key=value" (encoded) to the named query variable when value is not empty.
# @description Добавить «&ключ=значение» (с кодированием) в переменную query, если значение не пустое.
vpn::link::__qadd() {
    local -n __vl_qs="${1:?}"
    local -r key="$2" val="${3-}"
    is::empty "${val}" && return 0
    is::not_empty "${__vl_qs}" && __vl_qs+="&"
    __vl_qs+="${key}=$(uri::encode "${val}")"
}

# @private
# @description Host for a URL authority: IPv6 goes in brackets.
# @description Хост для authority: IPv6 — в квадратных скобках.
vpn::link::__host() {
    if [[ "$1" == *:* ]]; then printf '[%s]' "$1"; else printf '%s' "$1"; fi
}

# @description Build a share link from a profile record on stdin (the reverse of parse).
# @description Собрать ссылку из записи профиля на stdin (обратное к parse).
# @stdout link / ссылка
# @return 0 ok, LIB_ERROR_INVALID_INPUT invalid profile
vpn::link::build() {
    local -A p=()
    vpn::link::read_record p
    vpn::link::validate p || return $?
    local -r host="$(vpn::link::__host "${p[server]}")"
    local -r name="$(uri::encode "${p[name]:-}")"
    local qs=""
    local transport_q=""
    case "${p[proto]}" in
        vless|trojan)
            vpn::link::__qadd transport_q type "${p[transport]:-tcp}"
            if [[ "${p[transport]:-tcp}" != "tcp" ]]; then
                vpn::link::__qadd transport_q path "${p[path]:-}"
                vpn::link::__qadd transport_q host "${p[host]:-}"
                vpn::link::__qadd transport_q serviceName "${p[service_name]:-}"
            fi
            ;;
    esac
    case "${p[proto]}" in
        vless)
            vpn::link::__qadd qs encryption none
            vpn::link::__qadd qs security "${p[security]:-none}"
            vpn::link::__qadd qs flow "${p[flow]:-}"
            ;;
        trojan)
            vpn::link::__qadd qs security "${p[security]:-tls}"
            ;;
    esac
    case "${p[proto]}" in
        vless|trojan)
            vpn::link::__qadd qs sni "${p[sni]:-}"
            vpn::link::__qadd qs alpn "${p[alpn]:-}"
            vpn::link::__qadd qs fp "${p[fp]:-}"
            vpn::link::__qadd qs pbk "${p[pbk]:-}"
            vpn::link::__qadd qs sid "${p[sid]:-}"
            [[ "${p[insecure]:-0}" == 1 ]] && vpn::link::__qadd qs allowInsecure 1
            is::not_empty "${transport_q}" && qs+="${qs:+&}${transport_q}"
            ;;
    esac
    case "${p[proto]}" in
        vless)
            printf 'vless://%s@%s:%s?%s#%s\n' "$(uri::encode "${p[uuid]}")" "${host}" "${p[port]}" "${qs}" "${name}" ;;
        trojan)
            printf 'trojan://%s@%s:%s?%s#%s\n' "$(uri::encode "${p[password]}")" "${host}" "${p[port]}" "${qs}" "${name}" ;;
        vmess)
            local tls=""
            [[ "${p[security]:-none}" == "tls" ]] && tls="tls"
            local net="${p[transport]:-tcp}" htype="none"
            [[ "${net}" == "http" ]] && { net="tcp"; htype="http"; }
            local -r json="$(printf '{"v":"2","ps":"%s","add":"%s","port":"%s","id":"%s","aid":"%s","scy":"%s","net":"%s","type":"%s","host":"%s","path":"%s","tls":"%s","sni":"%s","alpn":"%s","fp":"%s"}' \
                "$(vpn::link::json_escape "${p[name]:-}")" "${p[server]}" "${p[port]}" "${p[uuid]}" \
                "${p[alter_id]:-0}" "${p[cipher]:-auto}" "${net}" "${htype}" \
                "$(vpn::link::json_escape "${p[host]:-}")" \
                "$(vpn::link::json_escape "${p[path]:-${p[service_name]:-}}")" "${tls}" \
                "$(vpn::link::json_escape "${p[sni]:-}")" "${p[alpn]:-}" "${p[fp]:-}")"
            printf 'vmess://%s\n' "$(vpn::link::b64encode "${json}")" ;;
        shadowsocks)
            local userinfo
            userinfo="$(vpn::link::b64encode "${p[method]}:${p[password]:-}")"
            userinfo="${userinfo//+/-}"; userinfo="${userinfo//\//_}"; userinfo="${userinfo%%=*}"
            is::not_empty "${p[plugin]:-}" && vpn::link::__qadd qs plugin "${p[plugin]}${p[plugin_opts]:+;${p[plugin_opts]}}"
            printf 'ss://%s@%s:%s%s#%s\n' "${userinfo}" "${host}" "${p[port]}" "${qs:+/?${qs}}" "${name}" ;;
        hysteria2)
            vpn::link::__qadd qs sni "${p[sni]:-}"
            vpn::link::__qadd qs alpn "${p[alpn]:-}"
            vpn::link::__qadd qs obfs "${p[obfs]:-}"
            vpn::link::__qadd qs obfs-password "${p[obfs_password]:-}"
            vpn::link::__qadd qs mport "${p[ports]:-}"
            [[ "${p[insecure]:-0}" == 1 ]] && vpn::link::__qadd qs insecure 1
            printf 'hysteria2://%s@%s:%s/%s#%s\n' "$(uri::encode "${p[password]}")" "${host}" "${p[port]}" "${qs:+?${qs}}" "${name}" ;;
        hysteria)
            vpn::link::__qadd qs protocol udp
            vpn::link::__qadd qs auth "${p[auth]:-}"
            vpn::link::__qadd qs peer "${p[sni]:-}"
            vpn::link::__qadd qs alpn "${p[alpn]:-}"
            vpn::link::__qadd qs upmbps "${p[up_mbps]:-}"
            vpn::link::__qadd qs downmbps "${p[down_mbps]:-}"
            vpn::link::__qadd qs obfsParam "${p[obfs]:-}"
            [[ "${p[insecure]:-0}" == 1 ]] && vpn::link::__qadd qs insecure 1
            printf 'hysteria://%s:%s?%s#%s\n' "${host}" "${p[port]}" "${qs}" "${name}" ;;
        tuic)
            vpn::link::__qadd qs sni "${p[sni]:-}"
            vpn::link::__qadd qs alpn "${p[alpn]:-}"
            vpn::link::__qadd qs congestion_control "${p[congestion]:-}"
            vpn::link::__qadd qs udp_relay_mode "${p[udp_relay]:-}"
            [[ "${p[insecure]:-0}" == 1 ]] && vpn::link::__qadd qs allow_insecure 1
            printf 'tuic://%s:%s@%s:%s?%s#%s\n' "$(uri::encode "${p[uuid]}")" "$(uri::encode "${p[password]:-}")" "${host}" "${p[port]}" "${qs}" "${name}" ;;
        anytls)
            vpn::link::__qadd qs sni "${p[sni]:-}"
            vpn::link::__qadd qs fp "${p[fp]:-}"
            [[ "${p[insecure]:-0}" == 1 ]] && vpn::link::__qadd qs insecure 1
            printf 'anytls://%s@%s:%s%s#%s\n' "$(uri::encode "${p[password]}")" "${host}" "${p[port]}" "${qs:+?${qs}}" "${name}" ;;
        socks)
            local auth=""
            is::not_empty "${p[username]:-}" && auth="$(uri::encode "${p[username]}"):$(uri::encode "${p[password]:-}")@"
            printf 'socks5://%s%s:%s#%s\n' "${auth}" "${host}" "${p[port]}" "${name}" ;;
    esac
}

# @description Escape a string for a JSON string literal (without quotes).
# @description Экранировать строку для JSON-литерала (без кавычек).
# @param $1 text / текст
# @stdout escaped text / экранированный текст
vpn::link::json_escape() {
    local s="${1-}"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    s="${s//[[:cntrl:]]/}"
    printf '%s' "${s}"
}

# @description Decode a subscription body: base64 or plain text, one link per line.
# @description Раскодировать тело подписки: base64 или текст, по ссылке в строке.
# @param $1 body / тело
# @stdout links, one per line / ссылки по одной в строке
vpn::link::subscription_links() {
    local body="${1-}" decoded line
    if ! [[ "${body}" == *"://"* ]]; then
        decoded="$(vpn::link::b64decode "${body}")" && body="${decoded}"
    fi
    while IFS= read -r line || is::not_empty "${line}"; do
        line="${line//$'\r'/}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        vpn::link::is_link "${line}" && printf '%s\n' "${line}"
    done <<< "${body}"
    return 0
}
