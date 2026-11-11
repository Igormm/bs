#!/usr/bin/env bs
# shellcheck shell=bash
# lib/network/vpn/tui.sh — full-screen TUI of the VPN client (servers, connection, traffic, log)
# lib/network/vpn/tui.sh — полноэкранный TUI VPN-клиента (серверы, соединение, трафик, журнал)
#
# Layout / Раскладка:
#   ┌ title: core version · state · mode · route ─────────────────────────┐
#   │ Servers (list, latency)  │ Profile (details of the selected server)  │
#   │                          │ Connection (state, speed, totals, IP)     │
#   │ Log (tail of the core log, coloured by level)                        │
#   └ statusbar: key hints or the last message ────────────────────────────┘
# The core keeps running after the TUI exits (q); Q quits and disconnects.
# Ядро продолжает работать после выхода из TUI (q); Q — выйти и отключиться.
#
# @depends lib/tui/tui, lib/network/vpn/core
# @tier gnu-linux
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], arithmetic command (( )), array, nameref, local/declare flags / needs bash constructs: double-bracket [[ ]], arithmetic command (( )), array, nameref, local/declare flags

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_NETWORK_VPN_TUI" || return 0

# Dependencies / Зависимости
bs::source_relative "../../tui/tui.sh" "core.sh"

# @global VPN_TUI_IDS — Vpn tui: visible profile ids (category: state)
# @global VPN_TUI_IDS — Vpn tui: видимые id профилей (категория: state)
declare -ga VPN_TUI_IDS=()
# @global VPN_TUI_NAME — Vpn tui: display-safe names by id (category: state)
# @global VPN_TUI_NAME — Vpn tui: безопасные для экрана имена по id (категория: state)
declare -gA VPN_TUI_NAME=()
# @global VPN_TUI_PROTO — Vpn tui: short protocol label by id (category: state)
# @global VPN_TUI_PROTO — Vpn tui: короткая метка протокола по id (категория: state)
declare -gA VPN_TUI_PROTO=()
# @global VPN_TUI_LAT — Vpn tui: latency ms by id (category: state)
# @global VPN_TUI_LAT — Vpn tui: задержка в мс по id (категория: state)
declare -gA VPN_TUI_LAT=()
# @global VPN_TUI_SEL — Vpn tui: selected row (category: state)
# @global VPN_TUI_SEL — Vpn tui: выбранная строка (категория: state)
declare -gi VPN_TUI_SEL=0
# @global VPN_TUI_TOP — Vpn tui: first visible row of the server list (category: state)
# @global VPN_TUI_TOP — Vpn tui: первая видимая строка списка серверов (категория: state)
declare -gi VPN_TUI_TOP=0
# @global VPN_TUI_FILTER — Vpn tui: name filter (category: state)
# @global VPN_TUI_FILTER — Vpn tui: фильтр по имени (категория: state)
declare -g VPN_TUI_FILTER=""
# @global VPN_TUI_STATUS — Vpn tui: last core status fields (category: state)
# @global VPN_TUI_STATUS — Vpn tui: последние поля статуса ядра (категория: state)
declare -gA VPN_TUI_STATUS=()
# @global VPN_TUI_NET — Vpn tui: traffic counters and speeds (category: state)
# @global VPN_TUI_NET — Vpn tui: счётчики и скорость трафика (категория: state)
declare -gA VPN_TUI_NET=()
# @global VPN_TUI_SPARK — Vpn tui: recent download speeds for the sparkline (category: state)
# @global VPN_TUI_SPARK — Vpn tui: недавние скорости загрузки для спарклайна (категория: state)
declare -ga VPN_TUI_SPARK=()
# @global VPN_TUI_IP — Vpn tui: last exit IP line (category: state)
# @global VPN_TUI_IP — Vpn tui: последняя строка внешнего IP (категория: state)
declare -g VPN_TUI_IP=""
# @global VPN_TUI_CURRENT — Vpn tui: server chosen by the live selector (category: state)
# @global VPN_TUI_CURRENT — Vpn tui: сервер, выбранный селектором (категория: state)
declare -g VPN_TUI_CURRENT=""
# @global VPN_TUI_LOG — Vpn tui: log lines on screen (category: state)
# @global VPN_TUI_LOG — Vpn tui: строки журнала на экране (категория: state)
declare -ga VPN_TUI_LOG=()
# @global VPN_TUI_MSG — Vpn tui: statusbar message (category: state)
# @global VPN_TUI_MSG — Vpn tui: сообщение в статус-баре (категория: state)
declare -g VPN_TUI_MSG=""
# @global VPN_TUI_MSG_LEVEL — Vpn tui: message level ok|warn|err|info (category: state)
# @global VPN_TUI_MSG_LEVEL — Vpn tui: уровень сообщения ok|warn|err|info (категория: state)
declare -g VPN_TUI_MSG_LEVEL="info"
# @global VPN_TUI_MODAL — Vpn tui: open modal (category: state)
# @global VPN_TUI_MODAL — Vpn tui: открытая модалка (категория: state)
declare -g VPN_TUI_MODAL=""
# @global VPN_TUI_M — Vpn tui: modal fields (title, text, callback, buffer …) (category: state)
# @global VPN_TUI_M — Vpn tui: поля модалки (заголовок, текст, колбэк, буфер …) (категория: state)
declare -gA VPN_TUI_M=()
# @global VPN_TUI_LINES — Vpn tui: lines of a text modal (category: state)
# @global VPN_TUI_LINES — Vpn tui: строки текстовой модалки (категория: state)
declare -ga VPN_TUI_LINES=()
# @global VPN_TUI_ITEMS — Vpn tui: rows of a list modal (category: state)
# @global VPN_TUI_ITEMS — Vpn tui: строки модалки-списка (категория: state)
declare -ga VPN_TUI_ITEMS=()
# @global VPN_TUI_BG — Vpn tui: background latency job pid (category: state)
# @global VPN_TUI_BG — Vpn tui: pid фонового замера задержки (категория: state)
declare -g VPN_TUI_BG=""
# @global VPN_TUI_ST — Vpn tui: cached SGR styles (category: state)
# @global VPN_TUI_ST — Vpn tui: кэш SGR-стилей (категория: state)
declare -gA VPN_TUI_ST=()
# @global VPN_TUI_RUN — Vpn tui: main loop flag (category: state)
# @global VPN_TUI_RUN — Vpn tui: флаг главного цикла (категория: state)
declare -gi VPN_TUI_RUN=1
# @global VPN_TUI_TICK — Vpn tui: last refresh second (category: state)
# @global VPN_TUI_TICK — Vpn tui: секунда последнего обновления (категория: state)
declare -gi VPN_TUI_TICK=0
# @global VPN_TUI_SLEEP_FD — Vpn tui: fd that never gets data, used to sleep (category: state)
# @global VPN_TUI_SLEEP_FD — Vpn tui: fd без данных для сна (категория: state)
declare -g VPN_TUI_SLEEP_FD=""

# Formatting helpers / Форматирование

# @description Human-readable byte count (B, KB, MB, GB).
# @description Объём в байтах для людей (Б, КБ, МБ, ГБ).
# @param $1 bytes / байты
# @stdout text / текст
vpn::tui::bytes() {
    local -i b="${1:-0}"
    if (( b < 1024 )); then printf '%d B' "${b}"
    elif (( b < 1048576 )); then printf '%d.%d KB' "$(( b / 1024 ))" "$(( b % 1024 * 10 / 1024 ))"
    elif (( b < 1073741824 )); then printf '%d.%d MB' "$(( b / 1048576 ))" "$(( b % 1048576 * 10 / 1048576 ))"
    else printf '%d.%02d GB' "$(( b / 1073741824 ))" "$(( b % 1073741824 * 100 / 1073741824 ))"
    fi
}

# @description Duration in seconds as 1d 02:03:04 / Длительность как 1d 02:03:04.
# @param $1 seconds / секунды
vpn::tui::duration() {
    local -i s="${1:-0}"
    local -i d=$(( s / 86400 )) h=$(( s % 86400 / 3600 )) m=$(( s % 3600 / 60 )) r=$(( s % 60 ))
    if (( d > 0 )); then printf '%dd %02d:%02d:%02d' "${d}" "${h}" "${m}" "${r}"
    else printf '%02d:%02d:%02d' "${h}" "${m}" "${r}"
    fi
}

# @description Short protocol label (VLESS·R for REALITY, HY2, SS …).
# @description Короткая метка протокола (VLESS·R для REALITY, HY2, SS …).
# @param $1 proto, $2 [security], $3 [transport]
vpn::tui::proto_label() {
    local label
    case "$1" in
        vless) label="VLESS" ;; vmess) label="VMESS" ;; trojan) label="TROJAN" ;;
        shadowsocks) label="SS" ;; hysteria2) label="HY2" ;; hysteria) label="HY1" ;;
        tuic) label="TUIC" ;; anytls) label="ANYTLS" ;; socks) label="SOCKS" ;;
        wireguard) label="WG" ;; naive) label="NAIVE" ;;
        *) label="$1" ;;
    esac
    [[ "${2-}" == "reality" ]] && label+="·R"
    case "${3-}" in ws|grpc|http|httpupgrade|xhttp) label+="·${3:0:2}" ;; esac
    printf '%s' "${label^^}"
}

# @description Drop characters a terminal draws two cells wide (emoji, flags, CJK) so columns align.
# @description Убрать символы двойной ширины (эмодзи, флаги, CJK), чтобы колонки не съезжали.
# @param $1 text / текст
# @stdout text / текст
vpn::tui::narrow() {
    local -r s="${1-}"
    local out="" c
    local -i i code
    # быстрый путь: только ASCII / fast path: ASCII only
    if [[ "${s}" =~ ^[[:print:]]*$ && "${s}" == "${s//[^ -~]/}" ]]; then
        printf '%s' "${s}"
        return 0
    fi
    for (( i = 0; i < ${#s}; i++ )); do
        c="${s:i:1}"
        printf -v code '%d' "'${c}" 2>/dev/null || code=0
        if (( code < 32 )); then continue; fi
        if (( code >= 0x1100 && code <= 0x115F )) || (( code >= 0x2E80 && code <= 0xA4CF )) \
            || (( code >= 0xAC00 && code <= 0xD7A3 )) || (( code >= 0xF900 && code <= 0xFAFF )) \
            || (( code >= 0xFE00 && code <= 0xFE6F )) || (( code >= 0xFF00 && code <= 0xFF60 )) \
            || (( code >= 0x1F000 )) || (( code == 0x200D )); then
            continue
        fi
        out+="${c}"
    done
    out="${out#"${out%%[![:space:]]*}"}"
    printf '%s' "${out}"
}

# @description Pad or cut text to N characters (by characters, not bytes).
# @description Дополнить или обрезать текст до N символов (по символам, не байтам).
# @param $1 text, $2 width
vpn::tui::fit() {
    local s="${1-}"
    local -ri w="${2:?width required}"
    if (( ${#s} > w )); then
        (( w > 1 )) && s="${s:0:w-1}…" || s="${s:0:w}"
    fi
    printf '%s%*s' "${s}" "$(( w - ${#s} ))" ""
}

# Data / Данные

# @description Reload profiles (with the filter), latencies and keep the selection on the same id.
# @description Перечитать профили (с фильтром), замеры и сохранить выбор на том же id.
vpn::tui::reload() {
    local keep="${VPN_TUI_IDS[VPN_TUI_SEL]:-}"
    VPN_TUI_IDS=()
    local id proto name server group security transport
    local -r filter="${VPN_TUI_FILTER,,}"
    while IFS=$'\t' read -r id proto name server group security transport; do
        is::empty "${id}" && continue
        if is::not_empty "${filter}" && [[ "${name,,} ${server,,} ${group,,} ${proto}" != *"${filter}"* ]]; then
            continue
        fi
        VPN_TUI_IDS+=("${id}")
        VPN_TUI_NAME["${id}"]="$(vpn::tui::narrow "${name}")"
        VPN_TUI_PROTO["${id}"]="$(vpn::tui::proto_label "${proto}" "${security}" "${transport}")"
    done < <(vpn::store::list)
    VPN_TUI_LAT=()
    local ms _t
    while IFS=$'\t' read -r id ms _t; do
        is::not_empty "${id}" && VPN_TUI_LAT["${id}"]="${ms}"
    done < <(vpn::core::latency_list)
    VPN_TUI_SEL=0
    if is::empty "${keep}"; then keep="$(vpn::settings::get active)"; fi
    local -i i
    for (( i = 0; i < ${#VPN_TUI_IDS[@]}; i++ )); do
        [[ "${VPN_TUI_IDS[i]}" == "${keep}" ]] && { VPN_TUI_SEL="${i}"; break; }
    done
    return 0
}

# @description Refresh core status, traffic, the live selection and the log tail.
# @description Обновить статус ядра, трафик, текущий выбор селектора и хвост журнала.
vpn::tui::refresh() {
    local line
    VPN_TUI_STATUS=()
    while IFS= read -r line; do
        VPN_TUI_STATUS["${line%%=*}"]="${line#*=}"
    done < <(vpn::core::status)
    if [[ "${VPN_TUI_STATUS[running]:-0}" == 1 ]]; then
        local up down conns now
        if IFS=' ' read -r up down conns < <(vpn::core::traffic 2>/dev/null); then
            now="$(vpn::core::__now_ms)"
            local -i dt=$(( now - ${VPN_TUI_NET[t]:-now} ))
            if (( dt > 0 && ${VPN_TUI_NET[t]:-0} > 0 )); then
                VPN_TUI_NET[up_speed]=$(( (up - ${VPN_TUI_NET[up]:-up}) * 1000 / dt ))
                VPN_TUI_NET[down_speed]=$(( (down - ${VPN_TUI_NET[down]:-down}) * 1000 / dt ))
                (( VPN_TUI_NET[up_speed] < 0 )) && VPN_TUI_NET[up_speed]=0
                (( VPN_TUI_NET[down_speed] < 0 )) && VPN_TUI_NET[down_speed]=0
                VPN_TUI_SPARK+=("${VPN_TUI_NET[down_speed]}")
                (( ${#VPN_TUI_SPARK[@]} > 60 )) && VPN_TUI_SPARK=("${VPN_TUI_SPARK[@]: -60}")
            fi
            VPN_TUI_NET[up]="${up}"; VPN_TUI_NET[down]="${down}"
            VPN_TUI_NET[conns]="${conns}"; VPN_TUI_NET[t]="${now}"
        fi
        VPN_TUI_CURRENT="$(vpn::core::current 2>/dev/null)"
    else
        VPN_TUI_NET=()
        VPN_TUI_SPARK=()
        VPN_TUI_CURRENT=""
    fi
    mapfile -t VPN_TUI_LOG < <(vpn::core::log_tail 40)
    # фоновый замер закончился — подтянуть результаты / background test done — pull results
    if is::not_empty "${VPN_TUI_BG}" && ! kill -0 "${VPN_TUI_BG}" 2>/dev/null; then
        wait "${VPN_TUI_BG}" 2>/dev/null
        VPN_TUI_BG=""
        vpn::tui::reload
        vpn::tui::say ok "Замер задержки завершён / latency test done"
    fi
    return 0
}

# @description Show a message in the statusbar / Показать сообщение в статус-баре.
# @param $1 level ok|warn|err|info, $2 text
vpn::tui::say() {
    VPN_TUI_MSG_LEVEL="${1:-info}"
    VPN_TUI_MSG="${2-}"
    VPN_TUI_M[msg_at]="${SECONDS}"
}

# Drawing / Отрисовка

# @private
# @description Cache SGR styles once (tui::style forks when captured).
# @description Закэшировать SGR-стили один раз (захват tui::style форкает).
vpn::tui::__styles() {
    VPN_TUI_ST[title]="$(tui::style bold white bg:blue)"
    VPN_TUI_ST[box]="$(tui::style cyan)"
    VPN_TUI_ST[box_hi]="$(tui::style bold cyan)"
    VPN_TUI_ST[key]="$(tui::style bold yellow)"
    VPN_TUI_ST[dim]="$(tui::style gray)"
    VPN_TUI_ST[text]="$(tui::style white)"
    VPN_TUI_ST[sel]="$(tui::style bold reverse cyan)"
    VPN_TUI_ST[ok]="$(tui::style bold green)"
    VPN_TUI_ST[warn]="$(tui::style bold yellow)"
    VPN_TUI_ST[err]="$(tui::style bold red)"
    VPN_TUI_ST[green]="$(tui::style green)"
    VPN_TUI_ST[yellow]="$(tui::style yellow)"
    VPN_TUI_ST[red]="$(tui::style red)"
    VPN_TUI_ST[magenta]="$(tui::style bold magenta)"
    VPN_TUI_ST[bar]="$(tui::style black bg:cyan)"
    VPN_TUI_ST[bar_ok]="$(tui::style black bg:green)"
    VPN_TUI_ST[bar_warn]="$(tui::style black bg:yellow)"
    VPN_TUI_ST[bar_err]="$(tui::style white bg:red)"
    VPN_TUI_ST[modal]="$(tui::style bold magenta)"
}

# @private
# @description Latency text and style / Текст и стиль задержки.
# @param $1 ms → REPLY text, VPN_TUI_M[lat_st] style
vpn::tui::__lat() {
    local -r ms="${1-}"
    if is::empty "${ms}"; then REPLY="   —  "; VPN_TUI_M[lat_st]="${VPN_TUI_ST[dim]}"; return 0; fi
    case "${ms}" in
        -1) REPLY=" fail "; VPN_TUI_M[lat_st]="${VPN_TUI_ST[red]}" ;;
        -2) REPLY=" bad  "; VPN_TUI_M[lat_st]="${VPN_TUI_ST[red]}" ;;
        *)
            printf -v REPLY '%4dms' "${ms}"
            if (( ms < 150 )); then VPN_TUI_M[lat_st]="${VPN_TUI_ST[green]}"
            elif (( ms < 400 )); then VPN_TUI_M[lat_st]="${VPN_TUI_ST[yellow]}"
            else VPN_TUI_M[lat_st]="${VPN_TUI_ST[red]}"
            fi ;;
    esac
}

# @private
# @description Title bar / Заголовок.
vpn::tui::__draw_title() {
    local state="○ ОТКЛЮЧЕНО" st="${VPN_TUI_ST[title]}"
    if [[ "${VPN_TUI_STATUS[running]:-0}" == 1 ]]; then
        state="● ПОДКЛЮЧЕНО"
        st="$(tui::style bold white bg:green)"
    fi
    local -r engine="${VPN_TUI_STATUS[engine]:-sing-box}"
    local ver="${VPN_SINGBOX_VERSION:-?}"
    [[ "${engine}" == "xray" ]] && ver="${VPN_XRAY_VERSION:-?}"
    local text=" ◆ BS VPN │ ${engine} ${ver} │ ${state} │ режим ${VPN_TUI_STATUS[mode]:-?} │ маршрут ${VPN_TUI_STATUS[route]:-?}"
    is::not_empty "${VPN_TUI_BG}" && text+=" │ ◷ замер…"
    tui::titlebar "${text}" "${st}"
}

# @private
# @description Server list box / Рамка списка серверов.
# @param $1 row, $2 col, $3 width, $4 height
vpn::tui::__draw_list() {
    local -ri r="$1" c="$2" w="$3" h="$4"
    local title="Серверы ${#VPN_TUI_IDS[@]}"
    is::not_empty "${VPN_TUI_FILTER}" && title+=" · фильтр: ${VPN_TUI_FILTER}"
    tui::box "${r}" "${c}" "${w}" "${h}" "${title}" "${VPN_TUI_ST[box_hi]}"
    local -ri rows=$(( h - 2 ))
    local -ri total=${#VPN_TUI_IDS[@]}
    if (( total == 0 )); then
        tui::put $(( r + 2 )) $(( c + 2 )) "Нет серверов." "${VPN_TUI_ST[dim]}"
        tui::put $(( r + 3 )) $(( c + 2 )) "i — импорт ссылки, s — подписки" "${VPN_TUI_ST[dim]}"
        return 0
    fi
    (( VPN_TUI_SEL >= total )) && VPN_TUI_SEL=$(( total - 1 ))
    (( VPN_TUI_SEL < 0 )) && VPN_TUI_SEL=0
    (( VPN_TUI_SEL < VPN_TUI_TOP )) && VPN_TUI_TOP="${VPN_TUI_SEL}"
    (( VPN_TUI_SEL >= VPN_TUI_TOP + rows )) && VPN_TUI_TOP=$(( VPN_TUI_SEL - rows + 1 ))
    local -ri name_w=$(( w - 4 - 9 - 7 ))
    local -i i idx
    local id mark name_st active="${VPN_TUI_STATUS[id]:-}" live="${VPN_TUI_CURRENT#auto:}"
    for (( i = 0; i < rows; i++ )); do
        idx=$(( VPN_TUI_TOP + i ))
        (( idx < total )) || break
        id="${VPN_TUI_IDS[idx]}"
        mark=" "
        name_st="${VPN_TUI_ST[text]}"
        if [[ "${VPN_TUI_STATUS[running]:-0}" == 1 && ( "${id}" == "${live}" || ( -z "${live}" && "${id}" == "${active}" ) ) ]]; then
            mark="●"
            name_st="${VPN_TUI_ST[ok]}"
        fi
        (( idx == VPN_TUI_SEL )) && name_st="${VPN_TUI_ST[sel]}"
        tui::put $(( r + 1 + i )) $(( c + 1 )) "${mark}$(vpn::tui::fit " ${VPN_TUI_NAME[$id]:-${id}}" "${name_w}") " "${name_st}"
        tui::put $(( r + 1 + i )) $(( c + 2 + name_w )) "$(vpn::tui::fit "${VPN_TUI_PROTO[$id]:-}" 9)" "${VPN_TUI_ST[magenta]}"
        vpn::tui::__lat "${VPN_TUI_LAT[$id]:-}"
        tui::put $(( r + 1 + i )) $(( c + 2 + name_w + 9 )) "${REPLY}" "${VPN_TUI_M[lat_st]}"
    done
    # полоса прокрутки / scrollbar
    if (( total > rows )); then
        local -i thumb=$(( VPN_TUI_TOP * (rows - 1) / (total - rows) ))
        for (( i = 0; i < rows; i++ )); do
            if (( i == thumb )); then
                tui::put $(( r + 1 + i )) $(( c + w - 1 )) "█" "${VPN_TUI_ST[box_hi]}"
            else
                tui::put $(( r + 1 + i )) $(( c + w - 1 )) "│" "${VPN_TUI_ST[box]}"
            fi
        done
    fi
}

# @private
# @description Profile details box / Рамка сведений о профиле.
vpn::tui::__draw_profile() {
    local -ri r="$1" c="$2" w="$3" h="$4"
    tui::box "${r}" "${c}" "${w}" "${h}" "Профиль" "${VPN_TUI_ST[box]}"
    local -r id="${VPN_TUI_IDS[VPN_TUI_SEL]:-}"
    is::empty "${id}" && return 0
    local -A p=()
    vpn::store::load "${id}" p 2>/dev/null || return 0
    local -a rows=(
        "id|${id}"
        "имя|$(vpn::tui::narrow "${p[name]:-}")"
        "протокол|${p[proto]:-}"
        "сервер|${p[server]:-}:${p[port]:-}${p[ports]:+ (hop ${p[ports]})}"
        "защита|${p[security]:-none}${p[sni]:+ · sni ${p[sni]}}${p[fp]:+ · ${p[fp]}}"
        "транспорт|${p[transport]:-${p[proto]}}${p[path]:+ · ${p[path]}}${p[service_name]:+ · ${p[service_name]}}"
        "группа|${p[group]:-manual}"
        "ядро|$(vpn::core::engine_for "${id}" 2>/dev/null || printf 'не подходит настройке core')"
    )
    [[ "${p[flow]:-}" ]] && rows+=("flow|${p[flow]}")
    [[ "${p[encryption]:-}" ]] && rows+=("шифрование|${p[encryption]%%.*} (VLESS)")
    [[ "${p[mode]:-}" ]] && rows+=("режим xhttp|${p[mode]}")
    [[ "${p[address]:-}" ]] && rows+=("адрес|${p[address]}${p[mtu]:+ · mtu ${p[mtu]}}")
    [[ "${p[obfs]:-}" ]] && rows+=("обфускация|${p[obfs]}")
    [[ "${p[insecure]:-0}" == 1 ]] && rows+=("внимание|сертификат не проверяется (insecure)")
    local -i i
    local -ri kw=11
    for (( i = 0; i < ${#rows[@]} && i < h - 2; i++ )); do
        tui::put $(( r + 1 + i )) $(( c + 2 )) "$(vpn::tui::fit "${rows[i]%%|*}" "${kw}")" "${VPN_TUI_ST[dim]}"
        local st="${VPN_TUI_ST[text]}"
        [[ "${rows[i]%%|*}" == "внимание" ]] && st="${VPN_TUI_ST[warn]}"
        tui::put $(( r + 1 + i )) $(( c + 2 + kw )) "$(vpn::tui::fit "${rows[i]#*|}" $(( w - kw - 4 )))" "${st}"
    done
}

# @private
# @description Sparkline of recent download speed / Спарклайн недавней скорости загрузки.
# @param $1 width → REPLY
vpn::tui::__spark() {
    local -ri w="$1"
    local -r bars="▁▂▃▄▅▆▇█"
    local -a vals=("${VPN_TUI_SPARK[@]: -${w}}")
    local -i max=1 v
    for v in "${vals[@]}"; do (( v > max )) && max="${v}"; done
    REPLY=""
    for v in "${vals[@]}"; do
        REPLY+="${bars:$(( v * 7 / max )):1}"
    done
}

# @private
# @description Connection box / Рамка соединения.
vpn::tui::__draw_conn() {
    local -ri r="$1" c="$2" w="$3" h="$4"
    tui::box "${r}" "${c}" "${w}" "${h}" "Соединение" "${VPN_TUI_ST[box]}"
    local -a rows=()
    if [[ "${VPN_TUI_STATUS[running]:-0}" != 1 ]]; then
        rows=("состояние|отключено|warn" \
            "режим|${VPN_TUI_STATUS[mode]:-}  (m — сменить)|text" \
            "маршрут|${VPN_TUI_STATUS[route]:-}  (g — сменить)|text" \
            "||text" \
            "|Enter — подключиться к выбранному|key")
    else
        local live="${VPN_TUI_CURRENT:-${VPN_TUI_STATUS[id]:-}}"
        local live_name="${VPN_TUI_NAME[${live#auto:}]:-${live}}"
        [[ "${live}" == auto:* ]] && live_name="авто → ${live_name}"
        local mode_text="${VPN_TUI_STATUS[mode]:-}"
        [[ "${mode_text}" == "proxy" ]] && mode_text+=" · socks5/http ${VPN_TUI_STATUS[listen]:-}"
        [[ "${mode_text}" == "tun" ]] && mode_text+=" · весь трафик системы"
        rows=("состояние|подключено · pid ${VPN_TUI_STATUS[pid]:-}|ok" \
            "сервер|${live_name}|text" \
            "время|$(vpn::tui::duration "${VPN_TUI_STATUS[uptime]:-0}")|text" \
            "режим|${mode_text}|text" \
            "↓ загрузка|$(vpn::tui::bytes "${VPN_TUI_NET[down_speed]:-0}")/s · всего $(vpn::tui::bytes "${VPN_TUI_NET[down]:-0}")|green" \
            "↑ отдача|$(vpn::tui::bytes "${VPN_TUI_NET[up_speed]:-0}")/s · всего $(vpn::tui::bytes "${VPN_TUI_NET[up]:-0}")|yellow" \
            "соединений|${VPN_TUI_NET[conns]:-0}|text" \
            "внешний IP|${VPN_TUI_IP:-p — узнать}|text")
        vpn::tui::__spark $(( w - 15 ))
        rows+=("трафик|${REPLY}|green")
    fi
    local -ri kw=11 vw=$(( w - 11 - 4 ))
    local -i i
    local label value style
    for (( i = 0; i < ${#rows[@]} && i < h - 2; i++ )); do
        label="${rows[i]%%|*}"
        value="${rows[i]#*|}"
        style="${value##*|}"
        value="${value%|*}"
        tui::put $(( r + 1 + i )) $(( c + 2 )) "$(vpn::tui::fit "${label}" "${kw}")" "${VPN_TUI_ST[dim]}"
        tui::put $(( r + 1 + i )) $(( c + 2 + kw )) "$(vpn::tui::fit "${value}" "${vw}")" "${VPN_TUI_ST[${style}]}"
    done
}

# @private
# @description Log box / Рамка журнала.
vpn::tui::__draw_log() {
    local -ri r="$1" c="$2" w="$3" h="$4"
    tui::box "${r}" "${c}" "${w}" "${h}" "Журнал ядра (l — весь)" "${VPN_TUI_ST[box]}"
    local -ri rows=$(( h - 2 ))
    local -i n=${#VPN_TUI_LOG[@]} i start
    start=$(( n - rows )); (( start < 0 )) && start=0
    local line st
    for (( i = start; i < n; i++ )); do
        line="${VPN_TUI_LOG[i]}"
        line="$(vpn::tui::__strip_sgr "${line}")"
        st="${VPN_TUI_ST[dim]}"
        case "${line}" in
            *FATAL*|*ERROR*) st="${VPN_TUI_ST[red]}" ;;
            *WARN*) st="${VPN_TUI_ST[yellow]}" ;;
            *INFO*) st="${VPN_TUI_ST[text]}" ;;
        esac
        tui::put $(( r + 1 + i - start )) $(( c + 2 )) "$(vpn::tui::fit "${line}" $(( w - 4 )))" "${st}"
    done
}

# @description Remove ANSI SGR sequences from a line (sing-box colours its log).
# @description Убрать SGR-последовательности из строки (sing-box раскрашивает журнал).
# @param $1 line / строка
vpn::tui::__strip_sgr() {
    local s="${1-}" out=""
    while [[ "${s}" == *$'\e['* ]]; do
        out+="${s%%$'\e['*}"
        s="${s#*$'\e['}"
        s="${s#"${s%%[!0-9;]*}"}"
        s="${s#m}"
    done
    printf '%s' "${out}${s}"
}

# @private
# @description Status bar: message for 6 s, otherwise key hints.
# @description Статус-бар: сообщение 6 с, иначе подсказки клавиш.
vpn::tui::__draw_status() {
    if is::not_empty "${VPN_TUI_MSG}" && (( SECONDS - ${VPN_TUI_M[msg_at]:-0} < 6 )); then
        local st="${VPN_TUI_ST[bar]}"
        case "${VPN_TUI_MSG_LEVEL}" in
            ok) st="${VPN_TUI_ST[bar_ok]}" ;; warn) st="${VPN_TUI_ST[bar_warn]}" ;; err) st="${VPN_TUI_ST[bar_err]}" ;;
        esac
        tui::statusbar " ${VPN_TUI_MSG}" "${st}"
        return 0
    fi
    tui::statusbar " Enter подключить  d откл  t/T тест  a авто  i импорт  s подписки  o настройки  m режим  g маршрут  e ссылка  x удалить  / поиск  ? помощь  q выход" "${VPN_TUI_ST[bar]}"
}

# @description Draw the whole frame into the buffer (no terminal output).
# @description Нарисовать весь кадр в буфер (без вывода в терминал).
vpn::tui::draw() {
    tui::buf::clear
    local -ri cols="${TUI_COLS}" lines="${TUI_LINES}"
    if (( cols < 72 || lines < 20 )); then
        tui::put 1 1 "Окно мало: нужно ≥ 72x20, сейчас ${cols}x${lines}" "${VPN_TUI_ST[warn]}"
        return 0
    fi
    vpn::tui::__draw_title
    local -i log_h=$(( lines / 4 ))
    (( log_h < 5 )) && log_h=5
    local -ri main_h=$(( lines - 2 - log_h ))
    local -i list_w=$(( cols * 46 / 100 ))
    (( list_w < 36 )) && list_w=36
    local -ri right_w=$(( cols - list_w ))
    local -i prof_h=$(( main_h / 2 ))
    (( prof_h > 11 )) && prof_h=11
    (( prof_h < 6 )) && prof_h=6
    vpn::tui::__draw_list 2 1 "${list_w}" "${main_h}"
    vpn::tui::__draw_profile 2 $(( list_w + 1 )) "${right_w}" "${prof_h}"
    vpn::tui::__draw_conn $(( 2 + prof_h )) $(( list_w + 1 )) "${right_w}" $(( main_h - prof_h ))
    vpn::tui::__draw_log $(( 2 + main_h )) 1 "${cols}" "${log_h}"
    vpn::tui::__draw_status
    is::not_empty "${VPN_TUI_MODAL}" && vpn::tui::__draw_modal
    return 0
}

# Modals / Модалки

# @private
# @description Centered modal frame; sets VPN_TUI_M[x,y,w,h].
# @description Рамка модалки по центру; задаёт VPN_TUI_M[x,y,w,h].
vpn::tui::__frame() {
    local -i w="$1" h="$2"
    (( w > TUI_COLS - 4 )) && w=$(( TUI_COLS - 4 ))
    (( h > TUI_LINES - 2 )) && h=$(( TUI_LINES - 2 ))
    local -ri x=$(( (TUI_COLS - w) / 2 + 1 )) y=$(( (TUI_LINES - h) / 2 + 1 ))
    tui::fill "${y}" "${x}" "${w}" "${h}" " " ""
    tui::box "${y}" "${x}" "${w}" "${h}" "$3" "${VPN_TUI_ST[modal]}"
    VPN_TUI_M[x]="${x}"; VPN_TUI_M[y]="${y}"; VPN_TUI_M[w]="${w}"; VPN_TUI_M[h]="${h}"
}

# @private
vpn::tui::__draw_modal() {
    local -i i
    case "${VPN_TUI_MODAL}" in
        text)
            local -i w=20 h=$(( ${#VPN_TUI_LINES[@]} + 4 ))
            local l
            for l in "${VPN_TUI_LINES[@]}"; do (( ${#l} + 6 > w )) && w=$(( ${#l} + 6 )); done
            vpn::tui::__frame "${w}" "${h}" "${VPN_TUI_M[title]:-}"
            local -i rows=$(( VPN_TUI_M[h] - 4 )) top="${VPN_TUI_M[scroll]:-0}"
            for (( i = 0; i < rows; i++ )); do
                (( top + i < ${#VPN_TUI_LINES[@]} )) || break
                tui::put $(( VPN_TUI_M[y] + 1 + i )) $(( VPN_TUI_M[x] + 2 )) \
                    "$(vpn::tui::fit "${VPN_TUI_LINES[top + i]}" $(( VPN_TUI_M[w] - 4 )))" "${VPN_TUI_ST[text]}"
            done
            tui::put $(( VPN_TUI_M[y] + VPN_TUI_M[h] - 2 )) $(( VPN_TUI_M[x] + 2 )) \
                "↑↓ прокрутка · Esc/Enter закрыть" "${VPN_TUI_ST[dim]}"
            ;;
        input)
            vpn::tui::__frame 72 7 "${VPN_TUI_M[title]:-}"
            tui::put $(( VPN_TUI_M[y] + 1 )) $(( VPN_TUI_M[x] + 2 )) "${VPN_TUI_M[prompt]:-}" "${VPN_TUI_ST[dim]}"
            local -i fw=$(( VPN_TUI_M[w] - 4 ))
            local value="${VPN_TUI_M[buf]:-}" shown
            local -i cur="${VPN_TUI_M[cur]:-0}" off=0
            (( cur > fw - 1 )) && off=$(( cur - fw + 1 ))
            shown="${value:off:fw}"
            tui::put $(( VPN_TUI_M[y] + 3 )) $(( VPN_TUI_M[x] + 2 )) "$(vpn::tui::fit "${shown}" "${fw}")" "$(tui::style underline white)"
            local ch="${value:cur:1}"
            tui::put $(( VPN_TUI_M[y] + 3 )) $(( VPN_TUI_M[x] + 2 + cur - off )) "${ch:- }" "$(tui::style reverse)"
            tui::put $(( VPN_TUI_M[y] + 5 )) $(( VPN_TUI_M[x] + 2 )) "Enter — готово · Esc — отмена · вставка из буфера работает" "${VPN_TUI_ST[dim]}"
            ;;
        confirm)
            vpn::tui::__frame $(( ${#VPN_TUI_M[text]} + 8 < 44 ? 44 : ${#VPN_TUI_M[text]} + 8 )) 7 "${VPN_TUI_M[title]:-Подтверждение}"
            tui::put $(( VPN_TUI_M[y] + 2 )) $(( VPN_TUI_M[x] + 3 )) "${VPN_TUI_M[text]}" "${VPN_TUI_ST[text]}"
            local yes_st="" no_st=""
            if [[ "${VPN_TUI_M[sel]:-1}" == 0 ]]; then yes_st="$(tui::style reverse green)"; else no_st="$(tui::style reverse red)"; fi
            tui::put $(( VPN_TUI_M[y] + 4 )) $(( VPN_TUI_M[x] + 4 )) "[ Да ]" "${yes_st}"
            tui::put $(( VPN_TUI_M[y] + 4 )) $(( VPN_TUI_M[x] + 14 )) "[ Нет ]" "${no_st}"
            ;;
        list)
            local -i h=$(( ${#VPN_TUI_ITEMS[@]} + 6 ))
            (( h < 8 )) && h=8
            vpn::tui::__frame 76 "${h}" "${VPN_TUI_M[title]:-}"
            local -i rows=$(( VPN_TUI_M[h] - 5 )) sel="${VPN_TUI_M[sel]:-0}" top=0
            (( sel >= rows )) && top=$(( sel - rows + 1 ))
            if (( ${#VPN_TUI_ITEMS[@]} == 0 )); then
                tui::put $(( VPN_TUI_M[y] + 2 )) $(( VPN_TUI_M[x] + 3 )) "${VPN_TUI_M[empty]:-Пусто}" "${VPN_TUI_ST[dim]}"
            fi
            for (( i = 0; i < rows; i++ )); do
                (( top + i < ${#VPN_TUI_ITEMS[@]} )) || break
                local st="${VPN_TUI_ST[text]}"
                (( top + i == sel )) && st="${VPN_TUI_ST[sel]}"
                tui::put $(( VPN_TUI_M[y] + 1 + i )) $(( VPN_TUI_M[x] + 2 )) \
                    "$(vpn::tui::fit " ${VPN_TUI_ITEMS[top + i]}" $(( VPN_TUI_M[w] - 4 )))" "${st}"
            done
            local tip="${VPN_TUI_M[tip_${sel}]:-}"
            is::not_empty "${tip}" && tui::put $(( VPN_TUI_M[y] + VPN_TUI_M[h] - 3 )) $(( VPN_TUI_M[x] + 2 )) \
                "$(vpn::tui::fit "${tip}" $(( VPN_TUI_M[w] - 4 )))" "${VPN_TUI_ST[yellow]}"
            tui::put $(( VPN_TUI_M[y] + VPN_TUI_M[h] - 2 )) $(( VPN_TUI_M[x] + 2 )) \
                "$(vpn::tui::fit "${VPN_TUI_M[keys]:-}" $(( VPN_TUI_M[w] - 4 )))" "${VPN_TUI_ST[dim]}"
            ;;
    esac
}

# @private
# @description Forget per-row data of the previous list modal / Забыть построчные данные прошлой модалки-списка.
vpn::tui::__list_reset() {
    local k
    for k in "${!VPN_TUI_M[@]}"; do
        case "${k}" in tip_*|set_*|sub_[0-9]*) unset "VPN_TUI_M[${k}]" ;; esac
    done
    VPN_TUI_ITEMS=()
}

# @description Open a scrollable text modal / Открыть текстовую модалку с прокруткой.
# @param $1 title, then lines / заголовок, затем строки
vpn::tui::show_text() {
    VPN_TUI_M[title]="$1"
    shift
    VPN_TUI_LINES=("$@")
    VPN_TUI_M[scroll]=0
    VPN_TUI_MODAL="text"
}

# @description Open an input modal; the callback gets the entered text.
# @description Открыть модалку ввода; колбэк получает введённый текст.
# @param $1 title, $2 prompt, $3 callback, $4 [initial value]
vpn::tui::ask() {
    VPN_TUI_M[title]="$1"; VPN_TUI_M[prompt]="$2"; VPN_TUI_M[cb]="$3"
    local -r init="${4-}"
    VPN_TUI_M[buf]="${init}"; VPN_TUI_M[cur]="${#init}"
    VPN_TUI_MODAL="input"
}

# @description Open a yes/no modal; the callback runs on "yes".
# @description Открыть модалку да/нет; колбэк выполняется при «да».
# @param $1 text, $2 callback
vpn::tui::confirm() {
    VPN_TUI_M[text]="$1"; VPN_TUI_M[cb]="$2"; VPN_TUI_M[sel]=1
    VPN_TUI_M[title]="Подтверждение"
    VPN_TUI_MODAL="confirm"
}

# @private
# @description Keys inside the open modal / Клавиши в открытой модалке.
vpn::tui::__modal_key() {
    local -r key="${TUI_KEY}"
    case "${VPN_TUI_MODAL}" in
        text)
            case "${key}" in
                UP|k) (( VPN_TUI_M[scroll] > 0 )) && VPN_TUI_M[scroll]=$(( VPN_TUI_M[scroll] - 1 )) ;;
                DOWN|j) (( VPN_TUI_M[scroll] < ${#VPN_TUI_LINES[@]} - 1 )) && VPN_TUI_M[scroll]=$(( VPN_TUI_M[scroll] + 1 )) ;;
                PGDN|' ') VPN_TUI_M[scroll]=$(( VPN_TUI_M[scroll] + 10 ))
                    (( VPN_TUI_M[scroll] >= ${#VPN_TUI_LINES[@]} )) && VPN_TUI_M[scroll]=$(( ${#VPN_TUI_LINES[@]} - 1 )) ;;
                PGUP) VPN_TUI_M[scroll]=$(( VPN_TUI_M[scroll] - 10 )); (( VPN_TUI_M[scroll] < 0 )) && VPN_TUI_M[scroll]=0 ;;
                ESC|ENTER|q|Q) VPN_TUI_MODAL="" ;;
            esac ;;
        input)
            local buf="${VPN_TUI_M[buf]:-}"
            local -i cur="${VPN_TUI_M[cur]:-0}"
            case "${key}" in
                ESC) VPN_TUI_MODAL="" ;;
                ENTER)
                    VPN_TUI_MODAL=""
                    "${VPN_TUI_M[cb]}" "${buf}" ;;
                BACKSPACE) (( cur > 0 )) && { buf="${buf:0:cur-1}${buf:cur}"; cur=$(( cur - 1 )); } ;;
                DELETE) buf="${buf:0:cur}${buf:cur+1}" ;;
                LEFT) (( cur > 0 )) && cur=$(( cur - 1 )) ;;
                RIGHT) (( cur < ${#buf} )) && cur=$(( cur + 1 )) ;;
                HOME) cur=0 ;;
                END) cur="${#buf}" ;;
                PASTE)
                    local paste="${TUI_PASTE//[$'\r\n']/ }"
                    paste="${paste%"${paste##*[![:space:]]}"}"
                    buf="${buf:0:cur}${paste}${buf:cur}"; cur=$(( cur + ${#paste} )) ;;
                *)
                    if (( ${#key} == 1 )) && [[ "${key}" != [[:cntrl:]] ]]; then
                        buf="${buf:0:cur}${key}${buf:cur}"; cur=$(( cur + 1 ))
                    fi ;;
            esac
            VPN_TUI_M[buf]="${buf}"; VPN_TUI_M[cur]="${cur}" ;;
        confirm)
            case "${key}" in
                LEFT|RIGHT|TAB|h|l) VPN_TUI_M[sel]=$(( 1 - ${VPN_TUI_M[sel]:-1} )) ;;
                y|Y|д|Д) VPN_TUI_MODAL=""; "${VPN_TUI_M[cb]}" ;;
                n|N|н|Н|ESC) VPN_TUI_MODAL="" ;;
                ENTER)
                    VPN_TUI_MODAL=""
                    [[ "${VPN_TUI_M[sel]}" == 0 ]] && "${VPN_TUI_M[cb]}" ;;
            esac ;;
        list)
            local -i sel="${VPN_TUI_M[sel]:-0}" n=${#VPN_TUI_ITEMS[@]}
            case "${key}" in
                UP|k) (( sel > 0 )) && sel=$(( sel - 1 )) ;;
                DOWN|j) (( sel < n - 1 )) && sel=$(( sel + 1 )) ;;
                ESC|q) VPN_TUI_MODAL="" ;;
                *) VPN_TUI_M[sel]="${sel}"; "${VPN_TUI_M[cb]}" "${key}" "${sel}"; return 0 ;;
            esac
            VPN_TUI_M[sel]="${sel}" ;;
    esac
    return 0
}

# Actions / Действия

# @private
# @description Show "working…" in the statusbar and paint it before a blocking step.
# @description Показать «работаю…» и нарисовать кадр перед блокирующим шагом.
vpn::tui::__busy() {
    vpn::tui::say info "◷ $1"
    vpn::tui::draw
    tui::render
}

# @private
# @description Run a step; on failure show its stderr in the statusbar.
# @description Выполнить шаг; при ошибке показать его stderr в статус-баре.
# @param $1 success text, then the command / текст успеха, затем команда
vpn::tui::__run() {
    local -r ok_text="$1"
    shift
    local err rc=0
    err="$("$@" 2>&1 >/dev/null)" || rc=$?
    if (( rc == 0 )); then
        vpn::tui::say ok "${ok_text}"
    else
        err="${err//$'\n'/ · }"
        vpn::tui::say err "${err:-ошибка ${rc} / error ${rc}}"
    fi
    return "${rc}"
}

# @private
# @description Leave the alt screen for a password prompt (sudo -v), then come back.
# @description Выйти с alt-экрана для ввода пароля (sudo -v) и вернуться.
vpn::tui::__sudo() {
    vpn::core::root_ready && return 0
    is::command sudo || return 1
    tui::quit
    printf '\nРежиму TUN нужны права root. / TUN mode needs root.\n'
    local rc=0
    sudo -v || rc=$?
    tui::init
    tui::mouse_off
    tui::paste_on
    return "${rc}"
}

# @description Connect to (or live-switch to) the selected server.
# @description Подключиться к выбранному серверу (или переключиться на лету).
vpn::tui::connect() {
    local -r id="${VPN_TUI_IDS[VPN_TUI_SEL]:-}"
    is::empty "${id}" && return 0
    if [[ "$(vpn::settings::get mode)" == "tun" ]] && ! vpn::tui::__sudo; then
        vpn::tui::say err "Нет прав root для TUN / no root for TUN"
        return 0
    fi
    vpn::tui::__busy "Подключение к ${VPN_TUI_NAME[$id]:-${id}}…"
    vpn::tui::__run "Подключено: ${VPN_TUI_NAME[$id]:-${id}}" vpn::core::switch "${id}"
    VPN_TUI_IP=""
    vpn::tui::refresh
}

# @description Disconnect / Отключиться.
vpn::tui::disconnect() {
    vpn::core::running || { vpn::tui::say info "Уже отключено / already disconnected"; return 0; }
    vpn::tui::__busy "Отключение…"
    vpn::tui::__run "Отключено / disconnected" vpn::core::stop
    VPN_TUI_IP=""
    vpn::tui::refresh
}

# @description Reconnect with the current settings / Переподключиться с текущими настройками.
vpn::tui::reconnect() {
    local id="${VPN_TUI_STATUS[id]:-$(vpn::settings::get active)}"
    is::empty "${id}" && id="${VPN_TUI_IDS[VPN_TUI_SEL]:-}"
    is::empty "${id}" && return 0
    if [[ "$(vpn::settings::get mode)" == "tun" ]] && ! vpn::tui::__sudo; then
        vpn::tui::say err "Нет прав root для TUN / no root for TUN"
        return 0
    fi
    vpn::tui::__busy "Переподключение…"
    vpn::tui::__run "Переподключено с новыми настройками" vpn::core::start "${id}"
    vpn::tui::refresh
}

# @private
# @description Offer a reconnect when settings change while connected.
# @description Предложить переподключение, если настройки изменились при работающем ядре.
vpn::tui::__maybe_reconnect() {
    vpn::core::running && vpn::tui::confirm "Применить сейчас (переподключиться)?" vpn::tui::reconnect
    return 0
}

# @description Latency of the selected server (through the core) / Задержка выбранного сервера.
vpn::tui::test_one() {
    local -r id="${VPN_TUI_IDS[VPN_TUI_SEL]:-}"
    is::empty "${id}" && return 0
    vpn::tui::__busy "Замер ${VPN_TUI_NAME[$id]:-${id}}…"
    local line ms
    line="$(vpn::core::test_real "${id}" 2>&1 | tail -n 1)"
    ms="${line##*$'\t'}"
    VPN_TUI_LAT["${id}"]="${ms}"
    case "${ms}" in
        -1) vpn::tui::say err "Сервер не ответил / no response" ;;
        -2) vpn::tui::say err "Ядро не принимает этот профиль / profile rejected by the core" ;;
        ''|*[!0-9]*) vpn::tui::say err "${line}" ;;
        *) vpn::tui::say ok "Задержка ${ms} мс" ;;
    esac
}

# @description Test every visible server in the background / Замерить все видимые серверы в фоне.
vpn::tui::test_all() {
    is::not_empty "${VPN_TUI_BG}" && { vpn::tui::say warn "Замер уже идёт / already running"; return 0; }
    (( ${#VPN_TUI_IDS[@]} > 0 )) || return 0
    ( vpn::core::test_real "${VPN_TUI_IDS[@]}" >/dev/null 2>&1 ) &
    VPN_TUI_BG=$!
    vpn::tui::say info "Замер ${#VPN_TUI_IDS[@]} серверов в фоне… / testing in background"
}

# @description Sort the visible list by latency (failed last) / Отсортировать по задержке.
vpn::tui::sort_latency() {
    local -a sorted=()
    local id
    mapfile -t sorted < <(for id in "${VPN_TUI_IDS[@]}"; do
        local ms="${VPN_TUI_LAT[$id]:-}"
        (( ${ms:-0} <= 0 )) && ms=999999
        printf '%s\t%s\n' "${ms}" "${id}"
    done | sort -n -k1,1 | cut -f2)
    VPN_TUI_IDS=("${sorted[@]}")
    VPN_TUI_SEL=0; VPN_TUI_TOP=0
    vpn::tui::say ok "Отсортировано по задержке (R — исходный порядок)"
}

# @description Toggle automatic best-server selection / Переключить автовыбор лучшего сервера.
vpn::tui::toggle_auto() {
    if [[ "$(vpn::settings::get auto_select)" == 1 ]]; then
        vpn::settings::set auto_select 0 >/dev/null
        if vpn::core::running && [[ "${VPN_TUI_CURRENT}" == auto* ]]; then
            vpn::core::switch "${VPN_TUI_STATUS[id]:-$(vpn::settings::get active)}" >/dev/null 2>&1
        fi
        vpn::tui::say info "Автовыбор выключен / auto select off"
    else
        vpn::settings::set auto_select 1 >/dev/null
        if vpn::core::running; then
            vpn::tui::__run "Автовыбор: самый быстрый сервер группы" vpn::core::switch auto
        else
            vpn::tui::say ok "Автовыбор включится при подключении / on at connect"
        fi
    fi
    vpn::tui::refresh
}

# @description Toggle proxy/TUN mode / Переключить режим proxy/TUN.
vpn::tui::toggle_mode() {
    local mode
    mode="$(vpn::settings::get mode)"
    if [[ "${mode}" == "proxy" ]]; then mode="tun"; else mode="proxy"; fi
    vpn::settings::set mode "${mode}" >/dev/null
    vpn::tui::say ok "Режим: ${mode}"
    vpn::tui::refresh
    vpn::tui::__maybe_reconnect
}

# @description Cycle the routing preset / Перебрать пресеты маршрутизации.
vpn::tui::cycle_route() {
    local -a presets=(global bypass-ru bypass-cn bypass-ir direct)
    local cur next
    cur="$(vpn::settings::get route)"
    local -i i
    next="${presets[0]}"
    for (( i = 0; i < ${#presets[@]}; i++ )); do
        [[ "${presets[i]}" == "${cur}" ]] && next="${presets[(i + 1) % ${#presets[@]}]}"
    done
    vpn::settings::set route "${next}" >/dev/null
    vpn::tui::say ok "Маршрут: ${next}"
    vpn::tui::refresh
    vpn::tui::__maybe_reconnect
}

# @private
vpn::tui::__import_cb() {
    local -r text="$1"
    is::empty "${text}" && return 0
    if [[ "${text}" =~ ^https?:// ]]; then
        # адрес подписки / a subscription URL
        VPN_TUI_M[sub_url]="${text}"
        vpn::tui::ask "Новая подписка" "Имя подписки (латиница, цифры, -):" vpn::tui::__sub_add_cb "sub$(( RANDOM % 900 + 100 ))"
        return 0
    fi
    local -a before=()
    mapfile -t before < <(vpn::store::ids)
    if vpn::tui::__run "Импортировано" vpn::store::import_text "${text}" manual; then
        local -a after=()
        mapfile -t after < <(vpn::store::ids)
        vpn::tui::say ok "Импортировано серверов: $(( ${#after[@]} - ${#before[@]} )) (дубликаты обновлены)"
    fi
    vpn::tui::reload
}

# @description Import share links (or a subscription URL) / Импорт ссылок (или адреса подписки).
vpn::tui::import() {
    vpn::tui::ask "Импорт" "Ссылка vless:// vmess:// trojan:// ss:// hy2:// tuic:// anytls:// socks:// или https-подписка:" vpn::tui::__import_cb
}

# @private
vpn::tui::__sub_add_cb() {
    local -r name="$1"
    vpn::tui::__run "Подписка добавлена" vpn::sub::add "${name}" "${VPN_TUI_M[sub_url]}" || return 0
    vpn::tui::__busy "Загрузка подписки ${name}…"
    local count
    if count="$(vpn::sub::update "${name}" 2>/dev/null)"; then
        vpn::tui::say ok "Подписка ${name}: серверов ${count}"
    else
        vpn::tui::say err "Подписка ${name}: не удалось загрузить / download failed"
    fi
    vpn::tui::reload
}

# @private
vpn::tui::__subs_fill() {
    vpn::tui::__list_reset
    local name url updated count
    while IFS=$'\t' read -r name url updated count; do
        VPN_TUI_ITEMS+=("$(vpn::tui::fit "${name}" 14) $(vpn::tui::fit "${count:-0} серв." 9) $(vpn::tui::fit "${updated:-никогда}" 17) ${url}")
        VPN_TUI_M["sub_${#VPN_TUI_ITEMS[@]}"]="${name}"
    done < <(vpn::sub::list)
}

# @private
vpn::tui::__subs_cb() {
    local -r key="$1" sel="$2"
    local -r name="${VPN_TUI_M[sub_$(( sel + 1 ))]:-}"
    case "${key}" in
        a|A|n)
            vpn::tui::ask "Новая подписка" "Адрес подписки (https://…):" vpn::tui::__sub_url_cb ;;
        u|ENTER)
            is::empty "${name}" && return 0
            vpn::tui::__busy "Обновление ${name}…"
            local count
            if count="$(vpn::sub::update "${name}" 2>/dev/null)"; then
                vpn::tui::say ok "Подписка ${name}: серверов ${count}"
            else
                vpn::tui::say err "Подписка ${name}: ошибка загрузки"
            fi
            vpn::tui::reload; vpn::tui::__subs_fill ;;
        U)
            local n
            local -i ok=0 bad=0
            while IFS=$'\t' read -r n _; do
                vpn::tui::__busy "Обновление ${n}…"
                if vpn::sub::update "${n}" >/dev/null 2>&1; then ok=$(( ok + 1 )); else bad=$(( bad + 1 )); fi
            done < <(vpn::sub::list)
            vpn::tui::say ok "Обновлено подписок: ${ok}, ошибок: ${bad}"
            vpn::tui::reload; vpn::tui::__subs_fill ;;
        x|X|DELETE)
            is::empty "${name}" && return 0
            VPN_TUI_M[sub_del]="${name}"
            vpn::tui::confirm "Удалить подписку ${name} и её серверы?" vpn::tui::__sub_del ;;
    esac
}

# @private
vpn::tui::__sub_url_cb() {
    is::empty "$1" && return 0
    VPN_TUI_M[sub_url]="$1"
    vpn::tui::ask "Новая подписка" "Имя подписки (латиница, цифры, -):" vpn::tui::__sub_add_cb "sub$(( RANDOM % 900 + 100 ))"
}

# @private
vpn::tui::__sub_del() {
    vpn::tui::__run "Подписка удалена" vpn::sub::remove "${VPN_TUI_M[sub_del]}"
    vpn::tui::reload
}

# @description Subscriptions manager / Менеджер подписок.
vpn::tui::subs() {
    vpn::tui::__subs_fill
    VPN_TUI_M[title]="Подписки"
    VPN_TUI_M[cb]="vpn::tui::__subs_cb"
    VPN_TUI_M[sel]=0
    VPN_TUI_M[empty]="Подписок нет — a, чтобы добавить"
    VPN_TUI_M[keys]="a добавить · Enter/u обновить · U обновить все · x удалить · Esc закрыть"
    VPN_TUI_MODAL="list"
}

# @private
vpn::tui::__settings_fill() {
    vpn::tui::__list_reset
    local key value
    local -i i=0
    for key in "${VPN_SETTINGS_ORDER[@]}"; do
        [[ "${key}" == "api_secret" || "${key}" == "active" ]] && continue
        value="$(vpn::settings::get "${key}")"
        case "${VPN_SETTINGS_DEFAULT[$key]%%|*}" in
            bool) [[ "${value}" == 1 ]] && value="да" || value="нет" ;;
        esac
        VPN_TUI_ITEMS+=("$(vpn::tui::fit "${key}" 16) ${value:-—}")
        VPN_TUI_M["set_${i}"]="${key}"
        VPN_TUI_M["tip_${i}"]="${VPN_SETTINGS_TIPS[$key]:-}"
        i=$(( i + 1 ))
    done
}

# @private
vpn::tui::__settings_cb() {
    local -r key="$1" sel="$2"
    local -r name="${VPN_TUI_M[set_${sel}]:-}"
    if [[ "${key}" == r ]]; then
        VPN_TUI_MODAL=""
        VPN_TUI_M[dirty]=0
        vpn::tui::reconnect
        return 0
    fi
    is::empty "${name}" && return 0
    [[ "${key}" == ENTER || "${key}" == ' ' ]] || return 0
    local -r type="${VPN_SETTINGS_DEFAULT[$name]%%|*}"
    local cur
    cur="$(vpn::settings::get "${name}")"
    case "${type}" in
        bool)
            vpn::settings::set "${name}" "$(( 1 - cur ))" >/dev/null ;;
        enum:*)
            local -a opts=()
            IFS=',' read -ra opts <<< "${type#enum:}"
            local -i i next=0
            for (( i = 0; i < ${#opts[@]}; i++ )); do
                [[ "${opts[i]}" == "${cur}" ]] && next=$(( (i + 1) % ${#opts[@]} ))
            done
            vpn::settings::set "${name}" "${opts[next]}" >/dev/null ;;
        *)
            VPN_TUI_M[set_name]="${name}"
            vpn::tui::ask "Настройка ${name}" "${VPN_SETTINGS_TIPS[$name]:-}" vpn::tui::__settings_input_cb "${cur}"
            return 0 ;;
    esac
    vpn::tui::__settings_fill
    VPN_TUI_M[dirty]=1
    vpn::tui::refresh
}

# @private
vpn::tui::__settings_input_cb() {
    if vpn::tui::__run "Сохранено: ${VPN_TUI_M[set_name]}" vpn::settings::set "${VPN_TUI_M[set_name]}" "$1"; then
        VPN_TUI_M[dirty]=1
    fi
    vpn::tui::settings
}

# @description Settings editor / Редактор настроек.
vpn::tui::settings() {
    vpn::tui::__settings_fill
    VPN_TUI_M[title]="Настройки (применяются при переподключении — r)"
    VPN_TUI_M[cb]="vpn::tui::__settings_cb"
    VPN_TUI_M[sel]="${VPN_TUI_M[sel]:-0}"
    VPN_TUI_M[empty]=""
    VPN_TUI_M[keys]="Enter — изменить · Esc — закрыть · r — переподключиться с новыми настройками"
    VPN_TUI_MODAL="list"
}

# @description Show the share link of the selected server (and a QR code if qrencode exists).
# @description Показать ссылку выбранного сервера (и QR-код, если есть qrencode).
vpn::tui::export_link() {
    local -r id="${VPN_TUI_IDS[VPN_TUI_SEL]:-}"
    is::empty "${id}" && return 0
    local link
    link="$(vpn::store::get "${id}" | vpn::link::build 2>&1)"
    local -a lines=("${link}" "")
    if is::command qrencode; then
        local -a qr=()
        mapfile -t qr < <(qrencode -t UTF8 -m 1 -- "${link}" 2>/dev/null)
        lines+=("${qr[@]}")
    else
        lines+=("(установите qrencode, чтобы видеть QR-код)")
    fi
    vpn::tui::show_text "Ссылка: ${VPN_TUI_NAME[$id]:-${id}}" "${lines[@]}"
    # OSC 52 — копирование в буфер терминала / copy to the terminal clipboard
    printf '\e]52;c;%s\a' "$(vpn::link::b64encode "${link}")"
    vpn::tui::say ok "Ссылка скопирована в буфер (OSC 52) / link copied"
}

# @private
vpn::tui::__delete_cb() {
    local -r id="${VPN_TUI_M[del_id]}"
    if [[ "${VPN_TUI_STATUS[id]:-}" == "${id}" ]] && vpn::core::running; then
        vpn::tui::say err "Сначала отключитесь (d) / disconnect first"
        return 0
    fi
    vpn::tui::__run "Удалено: ${id}" vpn::store::remove "${id}"
    vpn::tui::reload
}

# @description Delete the selected server / Удалить выбранный сервер.
vpn::tui::delete() {
    local -r id="${VPN_TUI_IDS[VPN_TUI_SEL]:-}"
    is::empty "${id}" && return 0
    VPN_TUI_M[del_id]="${id}"
    vpn::tui::confirm "Удалить ${VPN_TUI_NAME[$id]:-${id}}?" vpn::tui::__delete_cb
}

# @private
vpn::tui::__filter_cb() {
    VPN_TUI_FILTER="$1"
    VPN_TUI_TOP=0
    vpn::tui::reload
}

# @description Full log viewer / Просмотр всего журнала.
vpn::tui::log_view() {
    local -a lines=()
    local line
    while IFS= read -r line; do
        lines+=("$(vpn::tui::__strip_sgr "${line}")")
    done < <(vpn::core::log_tail 400)
    (( ${#lines[@]} == 0 )) && lines=("Журнал пуст / log is empty")
    vpn::tui::show_text "Журнал ядра: $(vpn::core::log_file)" "${lines[@]}"
    VPN_TUI_M[scroll]=$(( ${#lines[@]} > 10 ? ${#lines[@]} - 10 : 0 ))
}

# @description Find out the exit IP / Узнать внешний IP.
vpn::tui::exit_ip() {
    vpn::tui::__busy "Определяю внешний IP…"
    local ip country city org
    if IFS=' ' read -r ip country city org < <(vpn::core::exit_ip 2>/dev/null); then
        VPN_TUI_IP="${ip} · ${country} ${city//_/ } · ${org//_/ }"
        vpn::tui::say ok "Внешний IP: ${ip} (${country})"
    else
        VPN_TUI_IP="не удалось / failed"
        vpn::tui::say err "Не удалось определить IP / exit IP lookup failed"
    fi
}

# @description Help modal / Модалка справки.
vpn::tui::help() {
    vpn::tui::show_text "Справка — BS VPN" \
        "↑↓ j k PgUp PgDn Home End  — выбор сервера" \
        "Enter      — подключиться к выбранному (в группе — мгновенно, без разрыва ядра)" \
        "d          — отключиться                r — переподключиться" \
        "t          — замер задержки выбранного  T — замер всех (в фоне)" \
        "S          — сортировать по задержке     a — автовыбор быстрого сервера" \
        "i          — импорт ссылки или https-подписки (вставка из буфера работает)" \
        "s          — подписки: добавить, обновить, удалить" \
        "o          — настройки (DNS, порты, TUN, домены, реклама …)" \
        "m          — режим proxy ↔ tun          g — маршрут global/bypass-ru/cn/ir/direct" \
        "e          — ссылка и QR-код сервера    x — удалить сервер" \
        "p          — внешний IP                 l — весь журнал ядра" \
        "/          — поиск по имени/серверу     R — сбросить поиск и сортировку" \
        "?          — эта справка" \
        "q          — выйти (VPN продолжит работать)   Q — выйти и отключить" \
        "" \
        "Режим proxy: SOCKS5/HTTP на 127.0.0.1:$(vpn::settings::get listen_port) — укажите его в браузере." \
        "Режим tun: весь трафик системы идёт через туннель; нужен root (sudo)." \
        "Ядро sing-box: $(vpn::core::version sing-box 2>/dev/null || :) · $(vpn::core::bin sing-box 2>/dev/null || printf 'не установлено')" \
        "Ядро Xray (XHTTP, шифрование VLESS): $(vpn::core::version xray 2>/dev/null || :) · $(vpn::core::bin xray 2>/dev/null || printf 'не установлено')"
}

# Main loop / Главный цикл

# @description Handle one key in the main view / Обработать клавишу в основном экране.
# @return 0 continue, 1 quit
vpn::tui::key() {
    if is::not_empty "${VPN_TUI_MODAL}"; then
        local -r was="${VPN_TUI_MODAL}"
        vpn::tui::__modal_key
        # закрыли настройки после изменений — предложить применить / settings closed after changes
        if [[ "${was}" == "list" && -z "${VPN_TUI_MODAL}" && "${VPN_TUI_M[dirty]:-0}" == 1 ]]; then
            VPN_TUI_M[dirty]=0
            vpn::tui::__maybe_reconnect
        fi
        return 0
    fi
    local -ri n=${#VPN_TUI_IDS[@]}
    case "${TUI_KEY}" in
        UP|k) (( VPN_TUI_SEL > 0 )) && VPN_TUI_SEL=$(( VPN_TUI_SEL - 1 )) ;;
        DOWN|j) (( VPN_TUI_SEL < n - 1 )) && VPN_TUI_SEL=$(( VPN_TUI_SEL + 1 )) ;;
        PGUP) VPN_TUI_SEL=$(( VPN_TUI_SEL - 10 )); (( VPN_TUI_SEL < 0 )) && VPN_TUI_SEL=0 ;;
        PGDN) VPN_TUI_SEL=$(( VPN_TUI_SEL + 10 )); (( VPN_TUI_SEL >= n )) && VPN_TUI_SEL=$(( n > 0 ? n - 1 : 0 )) ;;
        HOME) VPN_TUI_SEL=0 ;;
        END) VPN_TUI_SEL=$(( n > 0 ? n - 1 : 0 )) ;;
        ENTER) vpn::tui::connect ;;
        d|D) vpn::tui::disconnect ;;
        r) vpn::tui::reconnect ;;
        R) VPN_TUI_FILTER=""; VPN_TUI_TOP=0; vpn::tui::reload; vpn::tui::say info "Поиск и сортировка сброшены" ;;
        t) vpn::tui::test_one ;;
        T) vpn::tui::test_all ;;
        S) vpn::tui::sort_latency ;;
        a|A) vpn::tui::toggle_auto ;;
        i|I) vpn::tui::import ;;
        PASTE) vpn::tui::import; VPN_TUI_M[buf]="${TUI_PASTE//[$'\r\n']/ }"; VPN_TUI_M[cur]="${#VPN_TUI_M[buf]}" ;;
        s) vpn::tui::subs ;;
        o|O|c) VPN_TUI_M[sel]=0; vpn::tui::settings ;;
        m|M) vpn::tui::toggle_mode ;;
        g|G) vpn::tui::cycle_route ;;
        e|E) vpn::tui::export_link ;;
        x|X|DELETE) vpn::tui::delete ;;
        p|P) vpn::tui::exit_ip ;;
        l|L) vpn::tui::log_view ;;
        /) vpn::tui::ask "Поиск" "Часть имени, сервера, группы или протокола (пусто — сброс):" vpn::tui::__filter_cb "${VPN_TUI_FILTER}" ;;
        '?'|F1|h|H) vpn::tui::help ;;
        q|й) return 1 ;;
        Q|Й)
            vpn::tui::__busy "Отключение…"
            vpn::core::stop
            return 1 ;;
    esac
    return 0
}

# @private
# @description Sleep up to $1 seconds, waking as soon as a key is available.
# @description Спать до $1 секунд, просыпаясь, как только есть клавиша.
vpn::tui::__wait_key() {
    local -i i steps="${1:-10}"
    for (( i = 0; i < steps; i++ )); do
        read -r -t 0 && return 0
        read -r -t 0.05 -u "${VPN_TUI_SLEEP_FD}" || :
    done
    read -r -t 0
}

# @description Run the TUI until q / Q.
# @description Запустить TUI до q / Q.
# @return 0
vpn::tui::run() {
    vpn::store::init || return $?
    VPN_SINGBOX_VERSION="$(vpn::core::version sing-box 2>/dev/null)"
    VPN_XRAY_VERSION="$(vpn::core::version xray 2>/dev/null)"
    exec {VPN_TUI_SLEEP_FD}<> <(:)
    tui::init
    tui::mouse_off
    tui::paste_on
    vpn::tui::__styles
    vpn::tui::reload
    vpn::tui::refresh
    if ! vpn::core::bin sing-box >/dev/null 2>&1; then
        if vpn::core::bin xray >/dev/null 2>&1; then
            vpn::tui::say warn "sing-box не найден: работают только профили Xray («vpn core install») / sing-box not found"
        else
            vpn::tui::say warn "Ядро не найдено: выполните «vpn core install» / core not found"
        fi
    fi
    VPN_TUI_RUN=1
    VPN_TUI_TICK="${SECONDS}"
    while (( VPN_TUI_RUN == 1 )); do
        tui::handle_resize
        vpn::tui::draw
        tui::render
        if vpn::tui::__wait_key 20; then
            tui::key_read
            vpn::tui::key || VPN_TUI_RUN=0
        fi
        if (( SECONDS != VPN_TUI_TICK )); then
            VPN_TUI_TICK="${SECONDS}"
            vpn::tui::refresh
        fi
    done
    tui::paste_off
    tui::quit
    exec {VPN_TUI_SLEEP_FD}>&-
    if is::not_empty "${VPN_TUI_BG}"; then kill "${VPN_TUI_BG}" 2>/dev/null; fi
    if vpn::core::running; then
        printf 'VPN работает в фоне (%s). Остановить: vpn disconnect\n' "$(vpn::core::status | grep '^name=' | cut -d= -f2-)"
    fi
    return 0
}
