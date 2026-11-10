#!/usr/bin/env bs
# shellcheck shell=bash
# lib/network/vpn/store.sh — VPN client storage: profiles, settings, subscriptions
# lib/network/vpn/store.sh — хранилище VPN-клиента: профили, настройки, подписки
#
# Layout / Раскладка:
#   ${BS_VPN_HOME}/profiles/<id>.conf   profile records ("key=value", see link.sh)
#   ${BS_VPN_HOME}/profiles/.order      profile ids in display order
#   ${BS_VPN_HOME}/subs/<name>.conf     subscriptions (url, updated, count)
#   ${BS_VPN_HOME}/settings.conf        client settings (VPN_SETTINGS_DEFAULT keys)
#   ${BS_VPN_STATE}/                    runtime: config.json, pid, log, cache
# Files are never sourced: every read goes through a key whitelist.
# Файлы никогда не исполняются (source): чтение идёт через белый список ключей.
#
# @depends core/lang, core/const, lib/network/vpn/link
# @tier core
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], arithmetic command (( )), array, nameref, local/declare flags / needs bash constructs: double-bracket [[ ]], arithmetic command (( )), array, nameref, local/declare flags

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_NETWORK_VPN_STORE" || return 0

# Dependencies / Зависимости
bs::source_relative "../../../core/lang.sh" "../../../core/const.sh" "link.sh"

# @global VPN_SETTINGS_ORDER — Vpn store: settings keys in display order (category: constant)
# @global VPN_SETTINGS_ORDER — Vpn store: ключи настроек в порядке показа (категория: constant)
declare -ga VPN_SETTINGS_ORDER=(mode route auto_select listen_port allow_lan \
    system_proxy tun_stack tun_mtu strict_route ipv6 dns_remote dns_direct \
    block_ads direct_domains proxy_domains block_domains log_level api_port \
    test_url active api_secret)

# @global VPN_SETTINGS_DEFAULT — Vpn store: type|default per setting (category: constant)
# @global VPN_SETTINGS_DEFAULT — Vpn store: тип|значение по умолчанию на настройку (категория: constant)
declare -gA VPN_SETTINGS_DEFAULT=(
    [mode]='enum:proxy,tun|proxy'
    [route]='enum:global,bypass-ru,bypass-cn,bypass-ir,direct|global'
    [auto_select]='bool|0'
    [listen_port]='port|2080'
    [allow_lan]='bool|0'
    [system_proxy]='bool|0'
    [tun_stack]='enum:mixed,system,gvisor|mixed'
    [tun_mtu]='int|9000'
    [strict_route]='bool|1'
    [ipv6]='bool|1'
    [dns_remote]='dns|https://1.1.1.1/dns-query'
    [dns_direct]='dns|local'
    [block_ads]='bool|0'
    [direct_domains]='domains|'
    [proxy_domains]='domains|'
    [block_domains]='domains|'
    [log_level]='enum:trace,debug,info,warn,error|info'
    [api_port]='port|9090'
    [test_url]='url|https://www.gstatic.com/generate_204'
    [active]='id|'
    [api_secret]='secret|'
)

# @global VPN_SETTINGS_TIPS — Vpn store: one-line Russian tip per setting (category: constant)
# @global VPN_SETTINGS_TIPS — Vpn store: однострочная подсказка на настройку (категория: constant)
declare -gA VPN_SETTINGS_TIPS=(
    [mode]='proxy — локальный SOCKS/HTTP-прокси; tun — весь трафик системы через туннель (нужен root)'
    [route]='global — всё через VPN; bypass-ru/cn/ir — сайты страны напрямую; direct — всё напрямую'
    [auto_select]='1 — автоматически выбирать самый быстрый сервер группы (urltest)'
    [listen_port]='Порт локального прокси (SOCKS5 + HTTP на одном порту)'
    [allow_lan]='1 — прокси доступен из локальной сети (слушать 0.0.0.0)'
    [system_proxy]='1 — прописать прокси в системные настройки (GNOME/KDE/macOS)'
    [tun_stack]='Сетевой стек TUN: mixed — баланс, system — быстрее, gvisor — совместимее'
    [tun_mtu]='MTU интерфейса TUN; 9000 — по умолчанию sing-box, 1500 — при проблемах'
    [strict_route]='1 — запретить утечки мимо туннеля (kill switch в режиме TUN)'
    [ipv6]='1 — пускать IPv6 через туннель; 0 — только IPv4'
    [dns_remote]='DNS для проксируемых доменов (https://, tls://, udp:// или IP)'
    [dns_direct]='DNS для прямых доменов: local — системный, либо адрес'
    [block_ads]='1 — блокировать рекламу и трекеры (geosite-category-ads-all)'
    [direct_domains]='Домены через запятую, которые всегда идут напрямую'
    [proxy_domains]='Домены через запятую, которые всегда идут через VPN'
    [block_domains]='Домены через запятую, которые блокируются'
    [log_level]='Подробность журнала ядра'
    [api_port]='Порт Clash API ядра (статистика, переключение серверов)'
    [test_url]='HTTPS-адрес для проверки задержки серверов (http:// ядро не принимает)'
    [active]='Выбранный профиль'
    [api_secret]='Секрет Clash API (генерируется автоматически)'
)

# @global VPN_SETTINGS_DNS_RE — Vpn store: DNS server setting pattern (category: constant)
# @global VPN_SETTINGS_DNS_RE — Vpn store: шаблон настройки DNS-сервера (категория: constant)
readonly VPN_SETTINGS_DNS_RE='^((https|tls|udp|tcp|quic|h3)://)?[]A-Za-z0-9.:_[-]+(/[A-Za-z0-9._/-]*)?$'

# Paths / Пути

# @description Configuration directory (profiles, settings, subscriptions).
# @description Каталог конфигурации (профили, настройки, подписки).
# @stdout path / путь
vpn::store::home() {
    printf '%s\n' "${BS_VPN_HOME:-${XDG_CONFIG_HOME:-${HOME}/.config}/bs/vpn}"
}

# @description Runtime state directory (generated config, pid, log, cache).
# @description Каталог состояния (сгенерированный конфиг, pid, журнал, кэш).
# @stdout path / путь
vpn::store::state() {
    printf '%s\n' "${BS_VPN_STATE:-${XDG_STATE_HOME:-${HOME}/.local/state}/bs/vpn}"
}

# @description Create the storage directories with private permissions.
# @description Создать каталоги хранилища с приватными правами.
# @return 0 ok, LIB_ERROR_FILE_OPERATION cannot create
vpn::store::init() {
    local home state
    home="$(vpn::store::home)"
    state="$(vpn::store::state)"
    ( umask 077; mkdir -p "${home}/profiles" "${home}/subs" "${state}" ) || {
        printf 'не удалось создать / cannot create: %s\n' "${home}" >&2
        return "${LIB_ERROR_FILE_OPERATION}"
    }
    return 0
}

# @private
# @description Write stdin to a file atomically (tmp + mv), mode 600.
# @description Записать stdin в файл атомарно (tmp + mv), права 600.
# @param $1 target / цель
vpn::store::__write() {
    local -r target="${1:?target required}"
    local -r tmp="${target}.tmp.$$"
    ( umask 077; cat > "${tmp}" ) && mv -f "${tmp}" "${target}" && return 0
    rm -f "${tmp}"
    printf 'не удалось записать / cannot write: %s\n' "${target}" >&2
    return "${LIB_ERROR_FILE_OPERATION}"
}

# Profiles / Профили

# @description Is the string a valid profile id ([a-z0-9][a-z0-9._-]*, up to 64)?
# @description Допустимый ли id профиля ([a-z0-9][a-z0-9._-]*, до 64)?
# @param $1 id
# @return 0 yes, 1 no
vpn::store::valid_id() {
    [[ "${1-}" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]]
}

# @private
# @description Path of a profile file / Путь файла профиля.
vpn::store::__pfile() {
    printf '%s/profiles/%s.conf\n' "$(vpn::store::home)" "$1"
}

# @description Make a readable id from a name: ASCII slug, unique among profiles.
# @description Сделать читаемый id из имени: ASCII-slug, уникальный среди профилей.
# @param $1 name / имя
# @param $2 fallback (e.g. proto-server) / запасной вариант
# @stdout id
vpn::store::slug() {
    local s="${1-}"
    local LC_ALL=C
    s="$(str::lower "${s}")"
    s="${s//[^a-z0-9._-]/-}"
    while [[ "${s}" == *--* ]]; do s="${s//--/-}"; done
    s="${s#[-._]}"; s="${s#[-._]}"
    s="${s%[-._]}"
    s="${s:0:40}"
    if is::empty "${s}" || ! vpn::store::valid_id "${s}"; then
        s="$(str::lower "${2:-profile}")"
        s="${s//[^a-z0-9._-]/-}"
        s="${s#[-._]}"
        s="${s:0:40}"
        vpn::store::valid_id "${s}" || s="profile"
    fi
    local id="${s}"
    local -i n=2
    while is::file "$(vpn::store::__pfile "${id}")"; do
        id="${s}-${n}"
        n=$(( n + 1 ))
    done
    printf '%s\n' "${id}"
}

# @description Ordered profile ids (all or one group).
# @description Упорядоченные id профилей (все или одной группы).
# @param $1 [optional] group / группа
# @stdout ids, one per line / id по одному в строке
vpn::store::ids() {
    local -r group="${1-}"
    local -r dir="$(vpn::store::home)/profiles"
    is::dir "${dir}" || return 0
    local -A seen=()
    local -a ids=()
    local id f
    if is::file "${dir}/.order"; then
        while IFS= read -r id; do
            vpn::store::valid_id "${id}" || continue
            is::file "${dir}/${id}.conf" || continue
            map::has seen "${id}" && continue
            seen["${id}"]=1
            ids+=("${id}")
        done < "${dir}/.order"
    fi
    for f in "${dir}"/*.conf; do
        is::file "${f}" || continue
        id="${f##*/}"; id="${id%.conf}"
        map::has seen "${id}" && continue
        seen["${id}"]=1
        ids+=("${id}")
    done
    for id in "${ids[@]}"; do
        if is::not_empty "${group}"; then
            [[ "$(vpn::store::field "${id}" group)" == "${group}" ]] || continue
        fi
        printf '%s\n' "${id}"
    done
}

# @description Does a profile exist? / Существует ли профиль?
# @param $1 id
# @return 0 yes, 1 no
vpn::store::exists() {
    vpn::store::valid_id "${1-}" && is::file "$(vpn::store::__pfile "$1")"
}

# @description Print a profile record / Вывести запись профиля.
# @param $1 id
# @stdout record / запись
# @return 0 ok, LIB_ERROR_FILE_NOT_FOUND no such profile
vpn::store::get() {
    local -r id="${1-}"
    if ! vpn::store::exists "${id}"; then
        printf 'нет профиля / no profile: %s\n' "${id}" >&2
        return "${LIB_ERROR_FILE_NOT_FOUND}"
    fi
    cat "$(vpn::store::__pfile "${id}")"
}

# @description Load a profile into an associative array.
# @description Загрузить профиль в ассоциативный массив.
# @param $1 id
# @param $2 map name / имя карты
# @return 0 ok, LIB_ERROR_FILE_NOT_FOUND no such profile
vpn::store::load() {
    local -r id="${1-}"
    vpn::store::exists "${id}" || {
        printf 'нет профиля / no profile: %s\n' "${id}" >&2
        return "${LIB_ERROR_FILE_NOT_FOUND}"
    }
    vpn::link::read_record "${2:?map name required}" < "$(vpn::store::__pfile "${id}")"
}

# @description One field of a profile / Одно поле профиля.
# @param $1 id, $2 key
# @stdout value / значение
vpn::store::field() {
    local -r id="${1-}" key="${2:?key required}"
    vpn::store::exists "${id}" || return "${LIB_ERROR_FILE_NOT_FOUND}"
    local line
    while IFS= read -r line; do
        if [[ "${line}" == "${key}="* ]]; then
            printf '%s\n' "${line#*=}"
            return 0
        fi
    done < "$(vpn::store::__pfile "${id}")"
    return 0
}

# @private
# @description Identity of a server (proto|server|port|credential) for de-duplication.
# @description Идентичность сервера (proto|server|port|секрет) для устранения дублей.
vpn::store::__identity() {
    local -n __vs_m="${1:?}"
    printf '%s|%s|%s|%s%s' "${__vs_m[proto]:-}" "${__vs_m[server]:-}" "${__vs_m[port]:-}" \
        "${__vs_m[uuid]:-}" "${__vs_m[password]:-}${__vs_m[auth]:-}"
}

# @description Save a profile record from stdin; updates a duplicate in the same group.
# @description Сохранить запись профиля из stdin; дубликат в той же группе обновляется.
# @param $1 [optional] group (default: the record's group or "manual") / группа
# @param $2 [optional] id to overwrite / id для перезаписи
# @stdout id of the saved profile / id сохранённого профиля
# @return 0 ok, LIB_ERROR_INVALID_INPUT invalid record
vpn::store::add() {
    local group="${1-}" id="${2-}"
    local -A p=()
    vpn::link::read_record p
    is::empty "${group}" && group="${p[group]:-manual}"
    p[group]="$(str::lower "${group}")"
    p[group]="${p[group]//[^a-z0-9._-]/-}"
    vpn::link::validate p || return $?
    is::empty "${p[name]:-}" && p[name]="${p[server]}:${p[port]}"
    vpn::store::init || return $?
    if is::empty "${id}"; then
        local -r ident="$(vpn::store::__identity p)"
        local other
        while IFS= read -r other; do
            local -A o=()
            vpn::store::load "${other}" o 2>/dev/null || continue
            if [[ "$(vpn::store::__identity o)" == "${ident}" ]]; then
                id="${other}"
                break
            fi
            unset o
        done < <(vpn::store::ids "${p[group]}")
    fi
    if is::empty "${id}"; then
        id="$(vpn::store::slug "${p[name]}" "${p[proto]}-${p[server]}")"
        printf '%s\n' "${id}" >> "$(vpn::store::home)/profiles/.order"
    fi
    vpn::store::valid_id "${id}" || {
        printf 'неверный id / invalid id: %s\n' "${id}" >&2
        return "${LIB_ERROR_INVALID_ARGS}"
    }
    vpn::link::__emit p | vpn::store::__write "$(vpn::store::__pfile "${id}")" || return $?
    printf '%s\n' "${id}"
}

# @description Import one share link as a profile.
# @description Импортировать одну ссылку как профиль.
# @param $1 link / ссылка
# @param $2 [optional] group / группа
# @stdout id
vpn::store::import() {
    local -r link="${1:?link required}" group="${2:-manual}"
    local record
    record="$(vpn::link::parse "${link}")" || return $?
    printf '%s\n' "${record}" | vpn::store::add "${group}"
}

# @description Import every link of a text (plain or base64 subscription body).
# @description Импортировать все ссылки текста (обычного или base64 тела подписки).
# @param $1 text / текст
# @param $2 [optional] group / группа
# @stdout imported ids / импортированные id
# @return 0 at least one imported, LIB_ERROR_INVALID_INPUT none
vpn::store::import_text() {
    local -r text="${1-}" group="${2:-manual}"
    local link
    local -i ok=0 bad=0
    while IFS= read -r link; do
        if vpn::store::import "${link}" "${group}" 2>/dev/null; then
            ok=$(( ok + 1 ))
        else
            bad=$(( bad + 1 ))
        fi
    done < <(vpn::link::subscription_links "${text}")
    (( bad > 0 )) && printf 'пропущено ссылок / links skipped: %d\n' "${bad}" >&2
    (( ok > 0 )) || return "${LIB_ERROR_INVALID_INPUT}"
    return 0
}

# @description Remove a profile / Удалить профиль.
# @param $1 id
# @return 0 ok, LIB_ERROR_FILE_NOT_FOUND no such profile
vpn::store::remove() {
    local -r id="${1-}"
    vpn::store::exists "${id}" || {
        printf 'нет профиля / no profile: %s\n' "${id}" >&2
        return "${LIB_ERROR_FILE_NOT_FOUND}"
    }
    rm -f "$(vpn::store::__pfile "${id}")"
    local -r order="$(vpn::store::home)/profiles/.order"
    if is::file "${order}"; then
        grep -vxF -- "${id}" "${order}" | vpn::store::__write "${order}"
    fi
    [[ "$(vpn::settings::get active)" == "${id}" ]] && vpn::settings::set active ""
    return 0
}

# @description Change one field of a profile (validated).
# @description Изменить одно поле профиля (с проверкой).
# @param $1 id, $2 key, $3 value
# @return 0 ok, LIB_ERROR_INVALID_ARGS unknown key, LIB_ERROR_INVALID_INPUT invalid result
vpn::store::set_field() {
    local -r id="${1-}" key="${2:?key required}" value="${3-}"
    arr::contains VPN_LINK_KEYS "${key}" || {
        printf 'неизвестное поле / unknown field: %s\n' "${key}" >&2
        return "${LIB_ERROR_INVALID_ARGS}"
    }
    local -A p=()
    vpn::store::load "${id}" p || return $?
    p["${key}"]="$(vpn::link::__clean "${value}")"
    vpn::link::validate p || return $?
    vpn::link::__emit p | vpn::store::__write "$(vpn::store::__pfile "${id}")"
}

# @description List profiles as TSV / Список профилей в TSV.
# @param $1 [optional] group / группа
# @stdout id<TAB>proto<TAB>name<TAB>server:port<TAB>group<TAB>security<TAB>transport
vpn::store::list() {
    local id
    while IFS= read -r id; do
        local -A p=()
        vpn::store::load "${id}" p 2>/dev/null || continue
        printf '%s\t%s\t%s\t%s:%s\t%s\t%s\t%s\n' "${id}" "${p[proto]:-}" "${p[name]:-}" \
            "${p[server]:-}" "${p[port]:-}" "${p[group]:-manual}" \
            "${p[security]:-}" "${p[transport]:-}"
        unset p
    done < <(vpn::store::ids "${1-}")
}

# @description Distinct profile groups in order of first appearance.
# @description Различные группы профилей в порядке первого появления.
# @stdout groups / группы
vpn::store::groups() {
    local -A seen=()
    local id g
    while IFS= read -r id; do
        g="$(vpn::store::field "${id}" group)"
        g="${g:-manual}"
        map::has seen "${g}" && continue
        seen["${g}"]=1
        printf '%s\n' "${g}"
    done < <(vpn::store::ids)
}

# Settings / Настройки

# @private
vpn::settings::__file() {
    printf '%s/settings.conf\n' "$(vpn::store::home)"
}

# @description Setting value (stored or default).
# @description Значение настройки (сохранённое или по умолчанию).
# @param $1 key / ключ
# @stdout value / значение
# @return 0 ok, LIB_ERROR_INVALID_ARGS unknown key
vpn::settings::get() {
    local -r key="${1:?key required}"
    map::has VPN_SETTINGS_DEFAULT "${key}" || {
        printf 'неизвестная настройка / unknown setting: %s\n' "${key}" >&2
        return "${LIB_ERROR_INVALID_ARGS}"
    }
    local -r file="$(vpn::settings::__file)"
    local line
    if is::file "${file}"; then
        while IFS= read -r line; do
            if [[ "${line}" == "${key}="* ]]; then
                printf '%s\n' "${line#*=}"
                return 0
            fi
        done < "${file}"
    fi
    printf '%s\n' "${VPN_SETTINGS_DEFAULT[$key]#*|}"
}

# @description Validate a setting value against its type.
# @description Проверить значение настройки по её типу.
# @param $1 key, $2 value
# @return 0 valid, LIB_ERROR_INVALID_INPUT invalid, LIB_ERROR_INVALID_ARGS unknown key
vpn::settings::validate() {
    local -r key="${1:?key required}" value="${2-}"
    map::has VPN_SETTINGS_DEFAULT "${key}" || return "${LIB_ERROR_INVALID_ARGS}"
    local -r type="${VPN_SETTINGS_DEFAULT[$key]%%|*}"
    local ok=1
    case "${type}" in
        bool) [[ "${value}" == 0 || "${value}" == 1 ]] || ok=0 ;;
        int) is::number "${value}" && (( value >= 576 && value <= 65535 )) || ok=0 ;;
        port) is::number "${value}" && (( value >= 1 && value <= 65535 )) || ok=0 ;;
        enum:*)
            local -a opts=()
            IFS=',' read -ra opts <<< "${type#enum:}"
            arr::contains opts "${value}" || ok=0 ;;
        dns)
            [[ "${value}" == "local" || "${value}" =~ ${VPN_SETTINGS_DNS_RE} ]] || ok=0 ;;
        domains)
            [[ -z "${value}" || "${value}" =~ ^[A-Za-z0-9.*_-]+(,[A-Za-z0-9.*_-]+)*$ ]] || ok=0 ;;
        # sing-box подменяет http:// в замере задержки на свой URL — только https
        # sing-box replaces http:// in the delay test with its own URL — https only
        url) [[ "${value}" =~ ^https://[^[:space:]\"\\]+$ ]] || ok=0 ;;
        id) [[ -z "${value}" ]] || vpn::store::valid_id "${value}" || ok=0 ;;
        secret) [[ "${value}" =~ ^[A-Za-z0-9_-]*$ ]] || ok=0 ;;
    esac
    if (( ok == 0 )); then
        printf 'неверное значение / invalid value for %s: %s\n' "${key}" "${value}" >&2
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    return 0
}

# @description Store a setting (validated) / Сохранить настройку (с проверкой).
# @param $1 key, $2 value
# @return 0 ok, LIB_ERROR_INVALID_INPUT / LIB_ERROR_INVALID_ARGS
vpn::settings::set() {
    local -r key="${1:?key required}" value="${2-}"
    vpn::settings::validate "${key}" "${value}" || return $?
    vpn::store::init || return $?
    local -r file="$(vpn::settings::__file)"
    {
        if is::file "${file}"; then
            grep -v "^${key}=" "${file}" || true
        fi
        printf '%s=%s\n' "${key}" "${value}"
    } | vpn::store::__write "${file}"
}

# @description All settings as "key=value" in display order.
# @description Все настройки как «ключ=значение» в порядке показа.
# @stdout lines / строки
vpn::settings::list() {
    local key
    for key in "${VPN_SETTINGS_ORDER[@]}"; do
        [[ "${key}" == "api_secret" ]] && continue
        printf '%s=%s\n' "${key}" "$(vpn::settings::get "${key}")"
    done
}

# @description Clash API secret; generated and stored on first use.
# @description Секрет Clash API; генерируется и сохраняется при первом обращении.
# @stdout secret / секрет
vpn::settings::secret() {
    local s
    s="$(vpn::settings::get api_secret)"
    if is::empty "${s}"; then
        local -i i
        local -r abc='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
        for (( i = 0; i < 32; i++ )); do
            s+="${abc:RANDOM % ${#abc}:1}"
        done
        vpn::settings::set api_secret "${s}" >/dev/null || return $?
    fi
    printf '%s\n' "${s}"
}

# Subscriptions / Подписки

# @private
vpn::sub::__file() {
    printf '%s/subs/%s.conf\n' "$(vpn::store::home)" "$1"
}

# @description Add or replace a subscription / Добавить или заменить подписку.
# @param $1 name ([a-z0-9._-]) / имя
# @param $2 url (http/https/file) / адрес
# @return 0 ok, LIB_ERROR_INVALID_INPUT bad name or url
vpn::sub::add() {
    local -r name="${1-}" url="${2-}"
    vpn::store::valid_id "${name}" || {
        printf 'имя подписки: строчные латинские буквы, цифры, ._- / subscription name: [a-z0-9._-]: %s\n' "${name}" >&2
        return "${LIB_ERROR_INVALID_INPUT}"
    }
    [[ "${url}" =~ ^(https?|file)://[^[:space:]\"\\]+$ ]] || {
        printf 'неверный адрес подписки / invalid subscription url: %s\n' "${url}" >&2
        return "${LIB_ERROR_INVALID_INPUT}"
    }
    vpn::store::init || return $?
    printf 'url=%s\nupdated=\ncount=0\n' "${url}" | vpn::store::__write "$(vpn::sub::__file "${name}")"
}

# @description Subscription field (url, updated, count) / Поле подписки.
# @param $1 name, $2 key
# @stdout value / значение
vpn::sub::get() {
    local -r file="$(vpn::sub::__file "${1-}")" key="${2:?key required}"
    is::file "${file}" || return "${LIB_ERROR_FILE_NOT_FOUND}"
    local line
    while IFS= read -r line; do
        [[ "${line}" == "${key}="* ]] && { printf '%s\n' "${line#*=}"; return 0; }
    done < "${file}"
    return 0
}

# @description List subscriptions as TSV / Список подписок в TSV.
# @stdout name<TAB>url<TAB>updated<TAB>count
vpn::sub::list() {
    local -r dir="$(vpn::store::home)/subs"
    is::dir "${dir}" || return 0
    local f name
    for f in "${dir}"/*.conf; do
        is::file "${f}" || continue
        name="${f##*/}"; name="${name%.conf}"
        printf '%s\t%s\t%s\t%s\n' "${name}" "$(vpn::sub::get "${name}" url)" \
            "$(vpn::sub::get "${name}" updated)" "$(vpn::sub::get "${name}" count)"
    done
}

# @description Remove a subscription and its profiles / Удалить подписку и её профили.
# @param $1 name / имя
vpn::sub::remove() {
    local -r name="${1-}"
    local -r file="$(vpn::sub::__file "${name}")"
    is::file "${file}" || {
        printf 'нет подписки / no subscription: %s\n' "${name}" >&2
        return "${LIB_ERROR_FILE_NOT_FOUND}"
    }
    local id
    while IFS= read -r id; do
        vpn::store::remove "${id}"
    done < <(vpn::store::ids "${name}")
    rm -f "${file}"
}

# @description Download a URL to stdout (curl, wget; file:// read directly).
# @description Скачать URL в stdout (curl, wget; file:// читается напрямую).
# @param $1 url
# @param $2 [optional] user agent
# @return 0 ok, LIB_ERROR_DEPENDENCY_MISSING no downloader, other — download failed
vpn::sub::fetch() {
    local -r url="${1:?url required}" ua="${2:-bs-vpn/1.0}"
    if [[ "${url}" == file://* ]]; then
        cat -- "${url#file://}"
        return $?
    fi
    if is::command curl; then
        curl -fsSL --max-time 30 --retry 2 -A "${ua}" -- "${url}"
    elif is::command wget; then
        wget -q -T 30 -U "${ua}" -O - -- "${url}"
    else
        printf 'нужен curl или wget / curl or wget required\n' >&2
        return "${LIB_ERROR_DEPENDENCY_MISSING}"
    fi
}

# @description Update a subscription: fetch, replace its profiles, keep the active one if it still exists.
# @description Обновить подписку: скачать, заменить профили, сохранить активный, если он остался.
# @param $1 name / имя
# @stdout number of imported profiles / число импортированных профилей
# @return 0 ok, LIB_ERROR_FILE_NOT_FOUND no subscription, LIB_ERROR_INVALID_INPUT no links
vpn::sub::update() {
    local -r name="${1-}"
    local url body
    url="$(vpn::sub::get "${name}" url)" || {
        printf 'нет подписки / no subscription: %s\n' "${name}" >&2
        return "${LIB_ERROR_FILE_NOT_FOUND}"
    }
    body="$(vpn::sub::fetch "${url}")" || {
        printf 'не удалось скачать подписку / download failed: %s\n' "${name}" >&2
        return "${LIB_ERROR_INVALID_INPUT}"
    }
    local links
    links="$(vpn::link::subscription_links "${body}")"
    if is::empty "${links}"; then
        printf 'в подписке нет ссылок / no links in subscription: %s\n' "${name}" >&2
        return "${LIB_ERROR_INVALID_INPUT}"
    fi
    # Сначала импорт (дубли обновятся на месте), затем удаление исчезнувших
    # Import first (duplicates update in place), then drop the vanished ones
    local -a before=() after=()
    mapfile -t before < <(vpn::store::ids "${name}")
    local link id
    while IFS= read -r link; do
        id="$(vpn::store::import "${link}" "${name}" 2>/dev/null)" && after+=("${id}")
    done <<< "${links}"
    for id in "${before[@]}"; do
        arr::contains after "${id}" || vpn::store::remove "${id}"
    done
    printf 'url=%s\nupdated=%s\ncount=%d\n' "${url}" "$(date '+%Y-%m-%d %H:%M')" "${#after[@]}" \
        | vpn::store::__write "$(vpn::sub::__file "${name}")"
    printf '%d\n' "${#after[@]}"
}
