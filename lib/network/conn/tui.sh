#!/usr/bin/env bs
# shellcheck shell=bash
# lib/network/conn/tui.sh — full-screen TUI for network connections (interfaces, NetworkManager profiles, Wi-Fi)
# lib/network/conn/tui.sh — полноэкранный TUI сетевых подключений (интерфейсы, профили NetworkManager, Wi-Fi)
#
# Layout / Раскладка:
#   ┌ title: host · NetworkManager · default route ───────────────────────┐
#   │ Interfaces | Profiles (Tab) │ Details of the selected row           │
#   │                             │ Traffic (speed, totals, sparkline)    │
#   └ statusbar: key hints or the last message ───────────────────────────┘
# Wi-Fi (w) opens a list of visible networks; Enter connects, asking for the
# password when the network is protected and not saved yet.
# Wi-Fi (w) открывает список видимых сетей; Enter подключает и спрашивает
# пароль, если сеть защищена и ещё не сохранена.
#
# @depends lib/tui/tui, lib/network/conn/core
# @tier gnu-linux
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], arithmetic command (( )), array, nameref, local/declare flags / needs bash constructs: double-bracket [[ ]], arithmetic command (( )), array, nameref, local/declare flags

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_NETWORK_CONN_TUI" || return 0

# Dependencies / Зависимости
bs::source_relative "../../tui/tui.sh" "core.sh"

# @global NET_TUI_VIEW — Net tui: left pane, if (interfaces) or nm (profiles) (category: state)
# @global NET_TUI_VIEW — Net tui: левая панель, if (интерфейсы) или nm (профили) (категория: state)
declare -g NET_TUI_VIEW="if"
# @global NET_TUI_IFS — Net tui: interface names in list order (category: state)
# @global NET_TUI_IFS — Net tui: имена интерфейсов в порядке списка (категория: state)
declare -ga NET_TUI_IFS=()
# @global NET_TUI_KIND — Net tui: interface kind by name (category: state)
# @global NET_TUI_KIND — Net tui: вид интерфейса по имени (категория: state)
declare -gA NET_TUI_KIND=()
# @global NET_TUI_STATE — Net tui: interface state by name (category: state)
# @global NET_TUI_STATE — Net tui: состояние интерфейса по имени (категория: state)
declare -gA NET_TUI_STATE=()
# @global NET_TUI_IP4 — Net tui: first IPv4 by interface (category: state)
# @global NET_TUI_IP4 — Net tui: первый IPv4 по интерфейсу (категория: state)
declare -gA NET_TUI_IP4=()
# @global NET_TUI_PROF — Net tui: profile rows "name<TAB>uuid<TAB>type<TAB>device<TAB>active" (category: state)
# @global NET_TUI_PROF — Net tui: строки профилей «имя<TAB>uuid<TAB>тип<TAB>устройство<TAB>активен» (категория: state)
declare -ga NET_TUI_PROF=()
# @global NET_TUI_SEL — Net tui: selected row per view (category: state)
# @global NET_TUI_SEL — Net tui: выбранная строка по панели (категория: state)
declare -gA NET_TUI_SEL=([if]=0 [nm]=0)
# @global NET_TUI_TOP — Net tui: first visible row per view (category: state)
# @global NET_TUI_TOP — Net tui: первая видимая строка по панели (категория: state)
declare -gA NET_TUI_TOP=([if]=0 [nm]=0)
# @global NET_TUI_DETAIL — Net tui: key=value details of the selected interface (category: state)
# @global NET_TUI_DETAIL — Net tui: сведения key=value о выбранном интерфейсе (категория: state)
declare -ga NET_TUI_DETAIL=()
# @global NET_TUI_DETAIL_OF — Net tui: interface the details belong to (category: state)
# @global NET_TUI_DETAIL_OF — Net tui: интерфейс, к которому относятся сведения (категория: state)
declare -g NET_TUI_DETAIL_OF=""
# @global NET_TUI_CNT — Net tui: last byte counters "rx tx ms" by interface (category: state)
# @global NET_TUI_CNT — Net tui: последние счётчики «rx tx мс» по интерфейсу (категория: state)
declare -gA NET_TUI_CNT=()
# @global NET_TUI_SPEED — Net tui: speeds "rx tx" in bytes/s by interface (category: state)
# @global NET_TUI_SPEED — Net tui: скорость «rx tx» в байт/с по интерфейсу (категория: state)
declare -gA NET_TUI_SPEED=()
# @global NET_TUI_HIST — Net tui: recent rx speeds by interface, space separated (category: state)
# @global NET_TUI_HIST — Net tui: недавние скорости приёма по интерфейсу через пробел (категория: state)
declare -gA NET_TUI_HIST=()
# @global NET_TUI_INFO — Net tui: title facts (host, nm, route) (category: state)
# @global NET_TUI_INFO — Net tui: сведения для заголовка (хост, nm, маршрут) (категория: state)
declare -gA NET_TUI_INFO=()
# @global NET_TUI_WIFI — Net tui: Wi-Fi rows "inuse<TAB>ssid<TAB>signal<TAB>security<TAB>chan" (category: state)
# @global NET_TUI_WIFI — Net tui: строки Wi-Fi «inuse<TAB>ssid<TAB>сигнал<TAB>защита<TAB>канал» (категория: state)
declare -ga NET_TUI_WIFI=()
# @global NET_TUI_MSG — Net tui: statusbar message (category: state)
# @global NET_TUI_MSG — Net tui: сообщение в статус-баре (категория: state)
declare -g NET_TUI_MSG=""
# @global NET_TUI_MSG_LEVEL — Net tui: message level ok|warn|err|info (category: state)
# @global NET_TUI_MSG_LEVEL — Net tui: уровень сообщения ok|warn|err|info (категория: state)
declare -g NET_TUI_MSG_LEVEL="info"
# @global NET_TUI_MODAL — Net tui: open modal: text|input|confirm|wifi (category: state)
# @global NET_TUI_MODAL — Net tui: открытая модалка: text|input|confirm|wifi (категория: state)
declare -g NET_TUI_MODAL=""
# @global NET_TUI_M — Net tui: modal fields (title, text, callback, buffer …) (category: state)
# @global NET_TUI_M — Net tui: поля модалки (заголовок, текст, колбэк, буфер …) (категория: state)
declare -gA NET_TUI_M=()
# @global NET_TUI_LINES — Net tui: lines of a text modal (category: state)
# @global NET_TUI_LINES — Net tui: строки текстовой модалки (категория: state)
declare -ga NET_TUI_LINES=()
# @global NET_TUI_ST — Net tui: cached SGR styles (category: state)
# @global NET_TUI_ST — Net tui: кэш SGR-стилей (категория: state)
declare -gA NET_TUI_ST=()
# @global NET_TUI_RUN — Net tui: main loop flag (category: state)
# @global NET_TUI_RUN — Net tui: флаг главного цикла (категория: state)
declare -gi NET_TUI_RUN=1
# @global NET_TUI_TICK — Net tui: last refresh second (category: state)
# @global NET_TUI_TICK — Net tui: секунда последнего обновления (категория: state)
declare -gi NET_TUI_TICK=0
# @global NET_TUI_SLEEP_FD — Net tui: fd that never gets data, used to sleep (category: state)
# @global NET_TUI_SLEEP_FD — Net tui: fd без данных для сна (категория: state)
declare -g NET_TUI_SLEEP_FD=""

# Formatting helpers / Форматирование

# @description Human-readable byte count (B, KB, MB, GB).
# @description Объём в байтах для людей (Б, КБ, МБ, ГБ).
# @param $1 bytes / байты
network::conn::tui::bytes() {
    local -i b="${1:-0}"
    if (( b < 1024 )); then printf '%d B' "${b}"
    elif (( b < 1048576 )); then printf '%d.%d KB' "$(( b / 1024 ))" "$(( b % 1024 * 10 / 1024 ))"
    elif (( b < 1073741824 )); then printf '%d.%d MB' "$(( b / 1048576 ))" "$(( b % 1048576 * 10 / 1048576 ))"
    else printf '%d.%02d GB' "$(( b / 1073741824 ))" "$(( b % 1073741824 * 100 / 1073741824 ))"
    fi
}

# @description Pad or cut text to N characters (by characters, not bytes).
# @description Дополнить или обрезать текст до N символов (по символам, не байтам).
# @param $1 text, $2 width
network::conn::tui::fit() {
    local s="${1-}"
    local -ri w="${2:?width required}"
    (( w > 0 )) || return 0
    if (( ${#s} > w )); then
        if (( w > 1 )); then s="${s:0:w-1}…"; else s="${s:0:w}"; fi
    fi
    printf '%s%*s' "${s}" "$(( w - ${#s} ))" ""
}

# @description Sparkline of numbers scaled to their maximum / Спарклайн чисел относительно их максимума.
# @param $1 width, then numbers / ширина, затем числа
# @stdout bars / столбики
network::conn::tui::spark() {
    local -ri w="${1:?width required}"
    shift
    local -r bars="▁▂▃▄▅▆▇█"
    local -a vals=("$@")
    (( ${#vals[@]} > w )) && vals=("${vals[@]: -w}")
    local -i max=1 v
    for v in "${vals[@]}"; do (( v > max )) && max="${v}"; done
    local out=""
    for v in "${vals[@]}"; do out+="${bars:$(( v * 7 / max )):1}"; done
    printf '%s' "${out}"
}

# @description Wi-Fi signal (0–100) as four bars / Сигнал Wi-Fi (0–100) четырьмя делениями.
# @param $1 percent / проценты
network::conn::tui::bars() {
    local -i s="${1:-0}"
    if (( s >= 75 )); then printf '▂▄▆█'
    elif (( s >= 50 )); then printf '▂▄▆_'
    elif (( s >= 25 )); then printf '▂▄__'
    else printf '▂___'
    fi
}

# @private
# @description Milliseconds since the epoch (EPOCHREALTIME, no fork) / Миллисекунды с эпохи (EPOCHREALTIME, без форка).
network::conn::tui::__now_ms() {
    local t="${EPOCHREALTIME:-}"
    if [[ -z "${t}" ]]; then printf '%d' "$(( SECONDS * 1000 ))"; return 0; fi
    t="${t/,/.}"
    local frac="${t#*.}000"
    printf '%d' "$(( ${t%.*} * 1000 + 10#${frac:0:3} ))"
}

# Data / Данные

# @description Re-read interfaces, profiles and title facts; keep the selection on the same row id.
# @description Перечитать интерфейсы, профили и сведения заголовка; сохранить выбор на том же id.
network::conn::tui::reload() {
    local -r keep_if="${NET_TUI_IFS[${NET_TUI_SEL[if]}]:-}"
    local keep_nm="${NET_TUI_PROF[${NET_TUI_SEL[nm]}]:-}"
    keep_nm="${keep_nm#*$'\t'}"
    keep_nm="${keep_nm%%$'\t'*}"
    NET_TUI_IFS=()
    NET_TUI_KIND=()
    NET_TUI_STATE=()
    NET_TUI_IP4=()
    local name kind state _mac _mtu addr
    while IFS=$'\t' read -r name kind state _mac _mtu; do
        [[ -n "${name}" ]] || continue
        NET_TUI_IFS+=("${name}")
        NET_TUI_KIND["${name}"]="${kind}"
        NET_TUI_STATE["${name}"]="${state}"
    done < <(network::conn::list)
    if is::command ip; then
        while IFS=' ' read -r name addr; do
            [[ -n "${name}" && -z "${NET_TUI_IP4[${name}]:-}" ]] && NET_TUI_IP4["${name}"]="${addr}"
        done < <(ip -o -4 addr show 2>/dev/null | awk '{print $2, $4}')
    fi
    NET_TUI_PROF=()
    if [[ "${NET_TUI_INFO[nm]:-0}" == 1 ]]; then
        mapfile -t NET_TUI_PROF < <(network::conn::nm::profiles | LC_ALL=C sort -t $'\t' -k5,5r -k1,1)
    fi
    local -i i
    NET_TUI_SEL[if]=0
    for (( i = 0; i < ${#NET_TUI_IFS[@]}; i++ )); do
        [[ "${NET_TUI_IFS[i]}" == "${keep_if}" ]] && { NET_TUI_SEL[if]="${i}"; break; }
    done
    if [[ -n "${keep_nm}" ]]; then
        NET_TUI_SEL[nm]=0
        for (( i = 0; i < ${#NET_TUI_PROF[@]}; i++ )); do
            [[ "${NET_TUI_PROF[i]}" == *$'\t'"${keep_nm}"$'\t'* ]] && { NET_TUI_SEL[nm]="${i}"; break; }
        done
    fi
    local dev gw _m
    NET_TUI_INFO[route]=""
    if IFS=$'\t' read -r dev gw _m < <(network::conn::gateways); then
        NET_TUI_INFO[route]="${gw} (${dev})"
    fi
    NET_TUI_DETAIL_OF=""
    return 0
}

# @description Sample byte counters of every interface and update speeds and history.
# @description Снять счётчики байтов всех интерфейсов и обновить скорость и историю.
network::conn::tui::sample() {
    local name rx tx prx ptx pt now
    local -i dt srx stx
    now="$(network::conn::tui::__now_ms)"
    for name in "${NET_TUI_IFS[@]}"; do
        IFS=' ' read -r rx tx <<< "$(network::conn::stats "${name}")"
        if [[ -n "${NET_TUI_CNT[${name}]:-}" ]]; then
            IFS=' ' read -r prx ptx pt <<< "${NET_TUI_CNT[${name}]}"
            dt=$(( now - pt ))
            if (( dt > 0 )); then
                srx=$(( (rx - prx) * 1000 / dt )); stx=$(( (tx - ptx) * 1000 / dt ))
                (( srx < 0 )) && srx=0
                (( stx < 0 )) && stx=0
                NET_TUI_SPEED["${name}"]="${srx} ${stx}"
                local -a hist=()
                IFS=' ' read -r -a hist <<< "${NET_TUI_HIST[${name}]:-}"
                hist+=("${srx}")
                (( ${#hist[@]} > 120 )) && hist=("${hist[@]: -120}")
                NET_TUI_HIST["${name}"]="${hist[*]}"
            fi
        fi
        NET_TUI_CNT["${name}"]="${rx} ${tx} ${now}"
    done
}

# @private
# @description Interface the right pane is about (selected interface or the profile's device).
# @description Интерфейс, о котором правая панель (выбранный или устройство профиля).
network::conn::tui::__focus_if() {
    if [[ "${NET_TUI_VIEW}" == nm ]]; then
        local _n _u _t dev _a
        IFS=$'\t' read -r _n _u _t dev _a <<< "${NET_TUI_PROF[${NET_TUI_SEL[nm]}]:-}"
        [[ "${dev}" == "--" ]] && dev=""
        printf '%s' "${dev}"
    else
        printf '%s' "${NET_TUI_IFS[${NET_TUI_SEL[if]}]:-}"
    fi
}

# @description Load details of the focused interface when it changed (or when forced).
# @description Загрузить сведения о текущем интерфейсе, если он сменился (или принудительно).
# @param $1 [force] 1 — reload even if unchanged
network::conn::tui::details() {
    local ifc
    ifc="$(network::conn::tui::__focus_if)"
    [[ "${1:-0}" == 1 || "${ifc}" != "${NET_TUI_DETAIL_OF}" ]] || return 0
    NET_TUI_DETAIL_OF="${ifc}"
    NET_TUI_DETAIL=()
    [[ -n "${ifc}" ]] || return 0
    mapfile -t NET_TUI_DETAIL < <(network::conn::show "${ifc}" 2>/dev/null)
}

# @description Show a message in the statusbar / Показать сообщение в статус-баре.
# @param $1 level ok|warn|err|info, $2 text
network::conn::tui::say() {
    NET_TUI_MSG_LEVEL="${1:-info}"
    NET_TUI_MSG="${2-}"
    NET_TUI_M[msg_at]="${SECONDS}"
}

# Drawing / Отрисовка

# @private
# @description Cache SGR styles once (tui::style forks when captured).
# @description Закэшировать SGR-стили один раз (захват tui::style форкает).
network::conn::tui::__styles() {
    NET_TUI_ST[title]="$(tui::style bold white bg:blue)"
    NET_TUI_ST[box]="$(tui::style cyan)"
    NET_TUI_ST[box_hi]="$(tui::style bold cyan)"
    NET_TUI_ST[dim]="$(tui::style gray)"
    NET_TUI_ST[text]="$(tui::style white)"
    NET_TUI_ST[sel]="$(tui::style bold reverse cyan)"
    NET_TUI_ST[ok]="$(tui::style bold green)"
    NET_TUI_ST[warn]="$(tui::style bold yellow)"
    NET_TUI_ST[err]="$(tui::style bold red)"
    NET_TUI_ST[green]="$(tui::style green)"
    NET_TUI_ST[yellow]="$(tui::style yellow)"
    NET_TUI_ST[red]="$(tui::style red)"
    NET_TUI_ST[magenta]="$(tui::style magenta)"
    NET_TUI_ST[tab]="$(tui::style bold black bg:cyan)"
    NET_TUI_ST[bar]="$(tui::style black bg:cyan)"
    NET_TUI_ST[bar_ok]="$(tui::style black bg:green)"
    NET_TUI_ST[bar_warn]="$(tui::style black bg:yellow)"
    NET_TUI_ST[bar_err]="$(tui::style white bg:red)"
    NET_TUI_ST[modal]="$(tui::style bold magenta)"
    NET_TUI_ST[input]="$(tui::style underline white)"
    NET_TUI_ST[cursor]="$(tui::style reverse)"
    NET_TUI_ST[yes]="$(tui::style reverse green)"
    NET_TUI_ST[no]="$(tui::style reverse red)"
}

# @private
# @description Style name for a state / Имя стиля для состояния.
# @param $1 state → REPLY
network::conn::tui::__state_style() {
    case "${1-}" in
        up|activated|yes) REPLY="ok" ;;
        down|unavailable|no) REPLY="red" ;;
        dormant|lowerlayerdown|activating|connecting*) REPLY="yellow" ;;
        *) REPLY="dim" ;;
    esac
}

# @private
# @description Title bar / Заголовок.
network::conn::tui::__draw_title() {
    local nm="NetworkManager: нет"
    [[ "${NET_TUI_INFO[nm]:-0}" == 1 ]] && nm="NetworkManager: да"
    local route="${NET_TUI_INFO[route]:-нет}"
    tui::titlebar " ◆ BS NET │ ${NET_TUI_INFO[host]:-} │ ${nm} │ маршрут по умолчанию: ${route}" "${NET_TUI_ST[title]}"
}

# @private
# @description Scrollbar on the right border of a list box / Полоса прокрутки на правой рамке списка.
# @param $1 row, $2 col, $3 rows, $4 total, $5 top
network::conn::tui::__scroll() {
    local -ri r="$1" c="$2" rows="$3" total="$4" top="$5"
    (( total > rows )) || return 0
    local -ri thumb=$(( top * (rows - 1) / (total - rows) ))
    local -i i
    for (( i = 0; i < rows; i++ )); do
        if (( i == thumb )); then
            tui::put $(( r + i )) "${c}" "█" "${NET_TUI_ST[box_hi]}"
        else
            tui::put $(( r + i )) "${c}" "│" "${NET_TUI_ST[box]}"
        fi
    done
}

# @private
# @description Clamp the selection and the viewport of the current view; sets REPLY to the visible rows.
# @description Ограничить выбор и окно текущей панели; REPLY — видимые строки.
# @param $1 total, $2 rows
network::conn::tui::__clamp() {
    local -ri total="$1" rows="$2"
    local -r v="${NET_TUI_VIEW}"
    local -i sel="${NET_TUI_SEL[${v}]}" top="${NET_TUI_TOP[${v}]}"
    (( sel >= total )) && sel=$(( total - 1 ))
    (( sel < 0 )) && sel=0
    (( sel < top )) && top="${sel}"
    (( sel >= top + rows )) && top=$(( sel - rows + 1 ))
    (( top < 0 )) && top=0
    NET_TUI_SEL["${v}"]="${sel}"
    NET_TUI_TOP["${v}"]="${top}"
}

# @private
# @description Left pane: tabs and the interface or profile list / Левая панель: вкладки и список.
# @param $1 row, $2 col, $3 width, $4 height
network::conn::tui::__draw_list() {
    local -ri r="$1" c="$2" w="$3" h="$4"
    tui::box "${r}" "${c}" "${w}" "${h}" "" "${NET_TUI_ST[box_hi]}"
    # вкладки в верхней рамке / tabs on the top border
    local t_if=" Интерфейсы ${#NET_TUI_IFS[@]} " t_nm=" Профили ${#NET_TUI_PROF[@]} "
    if [[ "${NET_TUI_VIEW}" == if ]]; then
        tui::put "${r}" $(( c + 2 )) "${t_if}" "${NET_TUI_ST[tab]}"
        tui::put "${r}" $(( c + 3 + ${#t_if} )) "${t_nm}" "${NET_TUI_ST[dim]}"
    else
        tui::put "${r}" $(( c + 2 )) "${t_if}" "${NET_TUI_ST[dim]}"
        tui::put "${r}" $(( c + 3 + ${#t_if} )) "${t_nm}" "${NET_TUI_ST[tab]}"
    fi
    local -ri rows=$(( h - 2 ))
    if [[ "${NET_TUI_VIEW}" == if ]]; then
        network::conn::tui::__draw_ifs "${r}" "${c}" "${w}" "${rows}"
    else
        network::conn::tui::__draw_profiles "${r}" "${c}" "${w}" "${rows}"
    fi
}

# @private
network::conn::tui::__draw_ifs() {
    local -ri r="$1" c="$2" w="$3" rows="$4"
    local -ri total=${#NET_TUI_IFS[@]}
    if (( total == 0 )); then
        tui::put $(( r + 2 )) $(( c + 2 )) "Интерфейсы не найдены." "${NET_TUI_ST[dim]}"
        return 0
    fi
    network::conn::tui::__clamp "${total}" "${rows}"
    local -ri sel="${NET_TUI_SEL[if]}" top="${NET_TUI_TOP[if]}"
    local -i name_w=$(( w - 34 ))
    (( name_w < 6 )) && name_w=6
    local -i i idx
    local n st dot dot_st
    for (( i = 0; i < rows; i++ )); do
        idx=$(( top + i ))
        (( idx < total )) || break
        n="${NET_TUI_IFS[idx]}"
        network::conn::tui::__state_style "${NET_TUI_STATE[${n}]:-}"
        dot_st="${NET_TUI_ST[${REPLY}]}"
        dot="○"
        [[ "${NET_TUI_STATE[${n}]:-}" == up ]] && dot="●"
        st="${NET_TUI_ST[text]}"
        if (( idx == sel )); then st="${NET_TUI_ST[sel]}"; dot_st="${st}"; fi
        tui::put $(( r + 1 + i )) $(( c + 1 )) " ${dot}" "${dot_st}"
        tui::put $(( r + 1 + i )) $(( c + 3 )) " $(network::conn::tui::fit "${n}" "${name_w}")" "${st}"
        tui::put $(( r + 1 + i )) $(( c + 4 + name_w )) " $(network::conn::tui::fit "${NET_TUI_KIND[${n}]:-}" 9)" "${NET_TUI_ST[magenta]}"
        tui::put $(( r + 1 + i )) $(( c + 14 + name_w )) " $(network::conn::tui::fit "${NET_TUI_IP4[${n}]:-}" 18)" "${NET_TUI_ST[dim]}"
    done
    network::conn::tui::__scroll $(( r + 1 )) $(( c + w - 1 )) "${rows}" "${total}" "${top}"
}

# @private
network::conn::tui::__draw_profiles() {
    local -ri r="$1" c="$2" w="$3" rows="$4"
    if [[ "${NET_TUI_INFO[nm]:-0}" != 1 ]]; then
        tui::put $(( r + 2 )) $(( c + 2 )) "NetworkManager не запущен." "${NET_TUI_ST[warn]}"
        tui::put $(( r + 3 )) $(( c + 2 )) "Профили и Wi-Fi работают через nmcli." "${NET_TUI_ST[dim]}"
        tui::put $(( r + 4 )) $(( c + 2 )) "Интерфейсы (Tab) доступны и без него." "${NET_TUI_ST[dim]}"
        return 0
    fi
    local -ri total=${#NET_TUI_PROF[@]}
    if (( total == 0 )); then
        tui::put $(( r + 2 )) $(( c + 2 )) "Профилей нет. w — подключиться к Wi-Fi." "${NET_TUI_ST[dim]}"
        return 0
    fi
    network::conn::tui::__clamp "${total}" "${rows}"
    local -ri sel="${NET_TUI_SEL[nm]}" top="${NET_TUI_TOP[nm]}"
    local -i name_w=$(( w - 28 ))
    (( name_w < 6 )) && name_w=6
    local -i i idx
    local name _uuid type dev active st dot dot_st
    for (( i = 0; i < rows; i++ )); do
        idx=$(( top + i ))
        (( idx < total )) || break
        IFS=$'\t' read -r name _uuid type dev active <<< "${NET_TUI_PROF[idx]}"
        [[ "${dev}" == "--" ]] && dev=""
        dot="○"; dot_st="${NET_TUI_ST[dim]}"
        [[ "${active}" == yes ]] && { dot="●"; dot_st="${NET_TUI_ST[ok]}"; }
        st="${NET_TUI_ST[text]}"
        if (( idx == sel )); then st="${NET_TUI_ST[sel]}"; dot_st="${st}"; fi
        type="${type#802-3-}"; type="${type#802-11-}"
        tui::put $(( r + 1 + i )) $(( c + 1 )) " ${dot}" "${dot_st}"
        tui::put $(( r + 1 + i )) $(( c + 3 )) " $(network::conn::tui::fit "${name}" "${name_w}")" "${st}"
        tui::put $(( r + 1 + i )) $(( c + 4 + name_w )) " $(network::conn::tui::fit "${type}" 9)" "${NET_TUI_ST[magenta]}"
        tui::put $(( r + 1 + i )) $(( c + 14 + name_w )) " $(network::conn::tui::fit "${dev}" 11)" "${NET_TUI_ST[dim]}"
    done
    network::conn::tui::__scroll $(( r + 1 )) $(( c + w - 1 )) "${rows}" "${total}" "${top}"
}

# @private
# @description Rows "label|value|style" of the details pane / Строки «метка|значение|стиль» панели сведений.
#   Fills the array named by $1.
# @param $1 array name / имя массива
network::conn::tui::__detail_rows() {
    local -n __out="$1"
    __out=()
    if [[ "${NET_TUI_VIEW}" == nm ]]; then
        local name uuid type dev active
        IFS=$'\t' read -r name uuid type dev active <<< "${NET_TUI_PROF[${NET_TUI_SEL[nm]}]:-}"
        [[ -n "${uuid}" ]] || return 0
        [[ "${dev}" == "--" ]] && dev=""
        local act="выключен" act_st="red"
        [[ "${active}" == yes ]] && { act="включён"; act_st="ok"; }
        __out+=("профиль|${name}|text" "состояние|${act}|${act_st}" "тип|${type}|text" "uuid|${uuid}|dim" "устройство|${dev:-—}|text" "||text")
    fi
    local line k v
    local -a in4=() in6=() gws=()
    local -A d=()
    for line in "${NET_TUI_DETAIL[@]}"; do
        k="${line%%=*}"; v="${line#*=}"
        case "${k}" in
            inet) in4+=("${v}") ;;
            inet6) in6+=("${v}") ;;
            gateway) gws+=("${v}") ;;
            *) d["${k}"]="${v}" ;;
        esac
    done
    [[ -n "${d[name]:-}" ]] || return 0
    network::conn::tui::__state_style "${d[state]:-}"
    local link="${d[state]:-?}"
    [[ "${d[admin]:-}" == down ]] && link+=" (выключен)"
    [[ "${d[carrier]:-}" == 0 && "${d[admin]:-}" == up ]] && link+=" · нет кабеля/связи"
    __out+=("интерфейс|${d[name]} · ${d[kind]:-}|text" "состояние|${link}|${REPLY}")
    __out+=("MAC|${d[mac]:-—}|text")
    local mtu="${d[mtu]:-}"
    [[ -n "${d[speed]:-}" ]] && mtu+=" · ${d[speed]} Мбит/с"
    [[ -n "${d[driver]:-}" ]] && mtu+=" · ${d[driver]}"
    __out+=("MTU|${mtu}|text")
    local a
    if (( ${#in4[@]} == 0 )); then
        if is::command ip || is::command ifconfig; then __out+=("IPv4|—|dim"); else __out+=("IPv4|нужна утилита ip|dim"); fi
    fi
    for a in "${in4[@]}"; do __out+=("IPv4|${a}|green"); done
    for a in "${in6[@]}"; do __out+=("IPv6|${a}|text"); done
    for a in "${gws[@]}"; do __out+=("шлюз|${a}|text"); done
    local managed="вручную (ip link)"
    [[ "${d[managed]:-}" == networkmanager ]] && managed="NetworkManager"
    __out+=("управление|${managed}|dim")
}

# @private
# @description Details box / Рамка сведений.
network::conn::tui::__draw_details() {
    local -ri r="$1" c="$2" w="$3" h="$4"
    tui::box "${r}" "${c}" "${w}" "${h}" "Сведения" "${NET_TUI_ST[box]}"
    local -a rows=()
    network::conn::tui::__detail_rows rows
    if (( ${#rows[@]} == 0 )); then
        tui::put $(( r + 2 )) $(( c + 2 )) "Нет сведений: у профиля нет устройства." "${NET_TUI_ST[dim]}"
        return 0
    fi
    local -ri kw=12 vw=$(( w - 12 - 4 ))
    local -i i
    local label value style
    for (( i = 0; i < ${#rows[@]} && i < h - 2; i++ )); do
        label="${rows[i]%%|*}"
        value="${rows[i]#*|}"
        style="${value##*|}"
        value="${value%|*}"
        tui::put $(( r + 1 + i )) $(( c + 2 )) "$(network::conn::tui::fit "${label}" "${kw}")" "${NET_TUI_ST[dim]}"
        tui::put $(( r + 1 + i )) $(( c + 2 + kw )) "$(network::conn::tui::fit "${value}" "${vw}")" "${NET_TUI_ST[${style}]:-${NET_TUI_ST[text]}}"
    done
}

# @private
# @description Traffic box of the focused interface / Рамка трафика текущего интерфейса.
network::conn::tui::__draw_traffic() {
    local -ri r="$1" c="$2" w="$3" h="$4"
    local ifc
    ifc="$(network::conn::tui::__focus_if)"
    tui::box "${r}" "${c}" "${w}" "${h}" "Трафик${ifc:+ · ${ifc}}" "${NET_TUI_ST[box]}"
    [[ -n "${ifc}" ]] || return 0
    local rx tx srx stx _t
    IFS=' ' read -r rx tx _t <<< "${NET_TUI_CNT[${ifc}]:-0 0 0}"
    IFS=' ' read -r srx stx <<< "${NET_TUI_SPEED[${ifc}]:-0 0}"
    local -ri kw=12 vw=$(( w - 12 - 4 ))
    tui::put $(( r + 1 )) $(( c + 2 )) "$(network::conn::tui::fit "↓ приём" "${kw}")" "${NET_TUI_ST[dim]}"
    tui::put $(( r + 1 )) $(( c + 2 + kw )) "$(network::conn::tui::fit "$(network::conn::tui::bytes "${srx}")/s · всего $(network::conn::tui::bytes "${rx}")" "${vw}")" "${NET_TUI_ST[green]}"
    (( h > 3 )) || return 0
    tui::put $(( r + 2 )) $(( c + 2 )) "$(network::conn::tui::fit "↑ отдача" "${kw}")" "${NET_TUI_ST[dim]}"
    tui::put $(( r + 2 )) $(( c + 2 + kw )) "$(network::conn::tui::fit "$(network::conn::tui::bytes "${stx}")/s · всего $(network::conn::tui::bytes "${tx}")" "${vw}")" "${NET_TUI_ST[yellow]}"
    (( h > 4 )) || return 0
    local -a hist=()
    IFS=' ' read -r -a hist <<< "${NET_TUI_HIST[${ifc}]:-}"
    (( ${#hist[@]} > 0 )) || return 0
    local -i i
    local -r line="$(network::conn::tui::spark "${vw}" "${hist[@]}")"
    for (( i = 3; i < h - 1; i++ )); do
        # верхние строки рамки пустые, спарклайн — в последней / sparkline sits on the last row
        (( i == h - 2 )) || continue
        tui::put $(( r + i )) $(( c + 2 )) "$(network::conn::tui::fit "приём" "${kw}")" "${NET_TUI_ST[dim]}"
        tui::put $(( r + i )) $(( c + 2 + kw )) "${line}" "${NET_TUI_ST[green]}"
    done
}

# @private
# @description Status bar: message for 6 s, otherwise key hints / Статус-бар: сообщение 6 с, иначе подсказки.
network::conn::tui::__draw_status() {
    if [[ -n "${NET_TUI_MSG}" ]] && (( SECONDS - ${NET_TUI_M[msg_at]:-0} < 6 )); then
        local st="${NET_TUI_ST[bar]}"
        case "${NET_TUI_MSG_LEVEL}" in
            ok) st="${NET_TUI_ST[bar_ok]}" ;; warn) st="${NET_TUI_ST[bar_warn]}" ;; err) st="${NET_TUI_ST[bar_err]}" ;;
        esac
        tui::statusbar " ${NET_TUI_MSG}" "${st}"
        return 0
    fi
    if [[ "${NET_TUI_VIEW}" == if ]]; then
        tui::statusbar " Tab профили  Enter вкл/выкл  u поднять  d опустить  w Wi-Fi  r обновить  ? помощь  q выход" "${NET_TUI_ST[bar]}"
    else
        tui::statusbar " Tab интерфейсы  Enter включить/выключить профиль  w Wi-Fi  r обновить  ? помощь  q выход" "${NET_TUI_ST[bar]}"
    fi
}

# @description Draw the whole frame into the buffer (no terminal output).
# @description Нарисовать весь кадр в буфер (без вывода в терминал).
network::conn::tui::draw() {
    tui::buf::clear
    local -ri cols="${TUI_COLS}" lines="${TUI_LINES}"
    if (( cols < 72 || lines < 16 )); then
        tui::put 1 1 "Окно мало: нужно ≥ 72x16, сейчас ${cols}x${lines}" "${NET_TUI_ST[warn]}"
        return 0
    fi
    network::conn::tui::details
    network::conn::tui::__draw_title
    local -ri main_h=$(( lines - 2 ))
    local -i list_w=$(( cols * 48 / 100 ))
    (( list_w < 40 )) && list_w=40
    local -ri right_w=$(( cols - list_w ))
    local -ri traf_h=6
    network::conn::tui::__draw_list 2 1 "${list_w}" "${main_h}"
    network::conn::tui::__draw_details 2 $(( list_w + 1 )) "${right_w}" $(( main_h - traf_h ))
    network::conn::tui::__draw_traffic $(( 2 + main_h - traf_h )) $(( list_w + 1 )) "${right_w}" "${traf_h}"
    network::conn::tui::__draw_status
    [[ -n "${NET_TUI_MODAL}" ]] && network::conn::tui::__draw_modal
    return 0
}

# Modals / Модалки

# @private
# @description Centered modal frame; sets NET_TUI_M[x,y,w,h] / Рамка модалки по центру.
network::conn::tui::__frame() {
    local -i w="$1" h="$2"
    (( w > TUI_COLS - 4 )) && w=$(( TUI_COLS - 4 ))
    (( h > TUI_LINES - 2 )) && h=$(( TUI_LINES - 2 ))
    local -ri x=$(( (TUI_COLS - w) / 2 + 1 )) y=$(( (TUI_LINES - h) / 2 + 1 ))
    tui::fill "${y}" "${x}" "${w}" "${h}" " " ""
    tui::box "${y}" "${x}" "${w}" "${h}" "$3" "${NET_TUI_ST[modal]}"
    NET_TUI_M[x]="${x}"; NET_TUI_M[y]="${y}"; NET_TUI_M[w]="${w}"; NET_TUI_M[h]="${h}"
}

# @private
network::conn::tui::__draw_modal() {
    local -i i
    case "${NET_TUI_MODAL}" in
        text)
            local -i w=20 h=$(( ${#NET_TUI_LINES[@]} + 4 ))
            local l
            for l in "${NET_TUI_LINES[@]}"; do (( ${#l} + 6 > w )) && w=$(( ${#l} + 6 )); done
            network::conn::tui::__frame "${w}" "${h}" "${NET_TUI_M[title]:-}"
            local -i rows=$(( NET_TUI_M[h] - 4 )) top="${NET_TUI_M[scroll]:-0}"
            for (( i = 0; i < rows; i++ )); do
                (( top + i < ${#NET_TUI_LINES[@]} )) || break
                tui::put $(( NET_TUI_M[y] + 1 + i )) $(( NET_TUI_M[x] + 2 )) \
                    "$(network::conn::tui::fit "${NET_TUI_LINES[top + i]}" $(( NET_TUI_M[w] - 4 )))" "${NET_TUI_ST[text]}"
            done
            tui::put $(( NET_TUI_M[y] + NET_TUI_M[h] - 2 )) $(( NET_TUI_M[x] + 2 )) "↑↓ прокрутка · Esc/Enter закрыть" "${NET_TUI_ST[dim]}"
            ;;
        input)
            network::conn::tui::__frame 64 7 "${NET_TUI_M[title]:-}"
            tui::put $(( NET_TUI_M[y] + 1 )) $(( NET_TUI_M[x] + 2 )) "${NET_TUI_M[prompt]:-}" "${NET_TUI_ST[dim]}"
            local -i fw=$(( NET_TUI_M[w] - 4 ))
            local value="${NET_TUI_M[buf]:-}" shown
            # пароль не показываем / never show a password
            if [[ "${NET_TUI_M[mask]:-0}" == 1 && "${NET_TUI_M[reveal]:-0}" != 1 ]]; then
                value="${value//?/•}"
            fi
            local -i cur="${NET_TUI_M[cur]:-0}" off=0
            (( cur > fw - 1 )) && off=$(( cur - fw + 1 ))
            shown="${value:off:fw}"
            tui::put $(( NET_TUI_M[y] + 3 )) $(( NET_TUI_M[x] + 2 )) "$(network::conn::tui::fit "${shown}" "${fw}")" "${NET_TUI_ST[input]}"
            local ch="${value:cur:1}"
            tui::put $(( NET_TUI_M[y] + 3 )) $(( NET_TUI_M[x] + 2 + cur - off )) "${ch:- }" "${NET_TUI_ST[cursor]}"
            local hint="Enter — готово · Esc — отмена"
            [[ "${NET_TUI_M[mask]:-0}" == 1 ]] && hint+=" · Ctrl+R — показать"
            tui::put $(( NET_TUI_M[y] + 5 )) $(( NET_TUI_M[x] + 2 )) "${hint}" "${NET_TUI_ST[dim]}"
            ;;
        confirm)
            local -i cw=$(( ${#NET_TUI_M[text]} + 8 ))
            (( cw < 44 )) && cw=44
            network::conn::tui::__frame "${cw}" 7 "${NET_TUI_M[title]:-Подтверждение}"
            tui::put $(( NET_TUI_M[y] + 2 )) $(( NET_TUI_M[x] + 3 )) "${NET_TUI_M[text]}" "${NET_TUI_ST[text]}"
            local yes_st="" no_st=""
            if [[ "${NET_TUI_M[sel]:-1}" == 0 ]]; then yes_st="${NET_TUI_ST[yes]}"; else no_st="${NET_TUI_ST[no]}"; fi
            tui::put $(( NET_TUI_M[y] + 4 )) $(( NET_TUI_M[x] + 4 )) "[ Да ]" "${yes_st}"
            tui::put $(( NET_TUI_M[y] + 4 )) $(( NET_TUI_M[x] + 14 )) "[ Нет ]" "${no_st}"
            ;;
        wifi)
            local -i h=$(( ${#NET_TUI_WIFI[@]} + 5 ))
            (( h < 8 )) && h=8
            network::conn::tui::__frame 70 "${h}" "Wi-Fi · ${#NET_TUI_WIFI[@]} сетей"
            local -i rows=$(( NET_TUI_M[h] - 4 )) sel="${NET_TUI_M[wsel]:-0}" top=0
            (( sel >= rows )) && top=$(( sel - rows + 1 ))
            if (( ${#NET_TUI_WIFI[@]} == 0 )); then
                tui::put $(( NET_TUI_M[y] + 2 )) $(( NET_TUI_M[x] + 3 )) "Сети не найдены. R — повторить поиск." "${NET_TUI_ST[dim]}"
            fi
            local -i sw=$(( NET_TUI_M[w] - 4 - 2 - 5 - 5 - 14 ))
            local inuse ssid signal sec _ch st mark
            for (( i = 0; i < rows; i++ )); do
                (( top + i < ${#NET_TUI_WIFI[@]} )) || break
                IFS=$'\t' read -r inuse ssid signal sec _ch <<< "${NET_TUI_WIFI[top + i]}"
                st="${NET_TUI_ST[text]}"
                mark=" "
                [[ "${inuse}" == '*' ]] && { mark="●"; st="${NET_TUI_ST[ok]}"; }
                (( top + i == sel )) && st="${NET_TUI_ST[sel]}"
                tui::put $(( NET_TUI_M[y] + 1 + i )) $(( NET_TUI_M[x] + 2 )) \
                    "${mark} $(network::conn::tui::fit "${ssid}" "${sw}") $(network::conn::tui::bars "${signal}") $(printf '%3s%%' "${signal}") $(network::conn::tui::fit "${sec/#--/открытая}" 13)" "${st}"
            done
            tui::put $(( NET_TUI_M[y] + NET_TUI_M[h] - 2 )) $(( NET_TUI_M[x] + 2 )) \
                "Enter подключить · R поиск · o/f радио вкл/выкл · Esc закрыть" "${NET_TUI_ST[dim]}"
            ;;
    esac
}

# @description Open a scrollable text modal / Открыть текстовую модалку с прокруткой.
# @param $1 title, then lines / заголовок, затем строки
network::conn::tui::show_text() {
    NET_TUI_M[title]="$1"
    shift
    NET_TUI_LINES=("$@")
    NET_TUI_M[scroll]=0
    NET_TUI_MODAL="text"
}

# @description Open an input modal; the callback gets the entered text.
# @description Открыть модалку ввода; колбэк получает введённый текст.
# @param $1 title, $2 prompt, $3 callback, $4 [initial value], $5 [mask 1 — password]
network::conn::tui::ask() {
    NET_TUI_M[title]="$1"; NET_TUI_M[prompt]="$2"; NET_TUI_M[cb]="$3"
    local -r init="${4-}"
    NET_TUI_M[buf]="${init}"; NET_TUI_M[cur]="${#init}"
    NET_TUI_M[mask]="${5:-0}"; NET_TUI_M[reveal]=0
    NET_TUI_MODAL="input"
}

# @description Open a yes/no modal; the callback runs on "yes".
# @description Открыть модалку да/нет; колбэк выполняется при «да».
# @param $1 text, $2 callback, then callback args / текст, колбэк, затем его аргументы
network::conn::tui::confirm() {
    NET_TUI_M[text]="$1"; NET_TUI_M[cb]="$2"; NET_TUI_M[sel]=1
    shift 2
    NET_TUI_M[cb_args]="$(printf '%q ' "$@")"
    NET_TUI_M[title]="Подтверждение"
    NET_TUI_MODAL="confirm"
}

# @private
# @description Keys inside the open modal / Клавиши в открытой модалке.
network::conn::tui::__modal_key() {
    local -r key="${TUI_KEY}"
    case "${NET_TUI_MODAL}" in
        text)
            case "${key}" in
                UP|k) (( NET_TUI_M[scroll] > 0 )) && NET_TUI_M[scroll]=$(( NET_TUI_M[scroll] - 1 )) ;;
                DOWN|j) (( NET_TUI_M[scroll] < ${#NET_TUI_LINES[@]} - 1 )) && NET_TUI_M[scroll]=$(( NET_TUI_M[scroll] + 1 )) ;;
                ESC|ENTER|q|Q) NET_TUI_MODAL="" ;;
            esac ;;
        input)
            local buf="${NET_TUI_M[buf]:-}"
            local -i cur="${NET_TUI_M[cur]:-0}"
            case "${key}" in
                ESC) NET_TUI_MODAL=""; NET_TUI_M[buf]=""; return 0 ;;
                ENTER)
                    NET_TUI_MODAL=""
                    NET_TUI_M[buf]=""
                    "${NET_TUI_M[cb]}" "${buf}"
                    return 0 ;;
                CTRL_R|$'\x12') NET_TUI_M[reveal]=$(( 1 - ${NET_TUI_M[reveal]:-0} )) ;;
                BACKSPACE) (( cur > 0 )) && { buf="${buf:0:cur-1}${buf:cur}"; cur=$(( cur - 1 )); } ;;
                DELETE) buf="${buf:0:cur}${buf:cur+1}" ;;
                LEFT) (( cur > 0 )) && cur=$(( cur - 1 )) ;;
                RIGHT) (( cur < ${#buf} )) && cur=$(( cur + 1 )) ;;
                HOME) cur=0 ;;
                END) cur="${#buf}" ;;
                PASTE)
                    local paste="${TUI_PASTE//[$'\r\n']/}"
                    buf="${buf:0:cur}${paste}${buf:cur}"; cur=$(( cur + ${#paste} )) ;;
                *)
                    if (( ${#key} == 1 )) && [[ "${key}" != [[:cntrl:]] ]]; then
                        buf="${buf:0:cur}${key}${buf:cur}"; cur=$(( cur + 1 ))
                    fi ;;
            esac
            NET_TUI_M[buf]="${buf}"; NET_TUI_M[cur]="${cur}" ;;
        confirm)
            case "${key}" in
                LEFT|RIGHT|TAB|h|l) NET_TUI_M[sel]=$(( 1 - ${NET_TUI_M[sel]:-1} )) ;;
                y|Y|д|Д) NET_TUI_MODAL=""; network::conn::tui::__confirm_run ;;
                n|N|н|Н|ESC) NET_TUI_MODAL="" ;;
                ENTER)
                    NET_TUI_MODAL=""
                    [[ "${NET_TUI_M[sel]}" == 0 ]] && network::conn::tui::__confirm_run ;;
            esac ;;
        wifi) network::conn::tui::__wifi_key "${key}" ;;
    esac
    return 0
}

# @private
# @description Run the confirm callback with its saved arguments / Выполнить колбэк подтверждения с аргументами.
network::conn::tui::__confirm_run() {
    local -a args=()
    eval "args=(${NET_TUI_M[cb_args]:-})"
    "${NET_TUI_M[cb]}" "${args[@]}"
}

# Actions / Действия

# @private
# @description Show "working…" in the statusbar and paint it before a blocking step.
# @description Показать «работаю…» и нарисовать кадр перед блокирующим шагом.
network::conn::tui::__busy() {
    network::conn::tui::say info "◷ $1"
    network::conn::tui::draw
    tui::render
}

# @private
# @description Run a step; on failure show its stderr in the statusbar.
# @description Выполнить шаг; при ошибке показать его stderr в статус-баре.
# @param $1 success text, then the command / текст успеха, затем команда
network::conn::tui::__run() {
    local -r ok_text="$1"
    shift
    local err rc=0
    err="$("$@" 2>&1 >/dev/null)" || rc=$?
    if (( rc == 0 )); then
        network::conn::tui::say ok "${ok_text}"
    else
        err="${err//$'\n'/ · }"
        network::conn::tui::say err "${err:-ошибка ${rc} / error ${rc}}"
    fi
    return "${rc}"
}

# @private
# @description Leave the alt screen for a password prompt (sudo -v), then come back.
# @description Выйти с alt-экрана для ввода пароля (sudo -v) и вернуться.
network::conn::tui::__sudo() {
    network::conn::root_ready && return 0
    is::command sudo || return 1
    tui::paste_off
    tui::quit
    printf '\nИзменение интерфейса без NetworkManager требует root. / Changing a link without NetworkManager needs root.\n'
    local rc=0
    sudo -v || rc=$?
    tui::init
    tui::mouse_off
    tui::paste_on
    return "${rc}"
}

# @private
# @description Bring a link up or down, asking for sudo when needed / Поднять или опустить интерфейс, при нужде спросив sudo.
# @param $1 up|down, $2 interface
network::conn::tui::__link() {
    local -r act="$1" ifc="$2"
    if ! network::conn::nm::manages "${ifc}" && ! network::conn::tui::__sudo; then
        network::conn::tui::say err "Нужны права root (sudo) / root required"
        return 1
    fi
    if [[ "${act}" == up ]]; then
        network::conn::tui::__busy "Поднимаю ${ifc}…"
        network::conn::tui::__run "${ifc}: поднят / up" network::conn::up "${ifc}"
    else
        network::conn::tui::__busy "Опускаю ${ifc}…"
        network::conn::tui::__run "${ifc}: опущен / down" network::conn::down "${ifc}"
    fi
    network::conn::tui::reload
    network::conn::tui::details 1
}

# @description Bring the selected interface up / Поднять выбранный интерфейс.
network::conn::tui::link_up() {
    local -r ifc="$(network::conn::tui::__focus_if)"
    [[ -n "${ifc}" ]] || return 0
    network::conn::tui::__link up "${ifc}"
}

# @description Bring the selected interface down (asks first) / Опустить выбранный интерфейс (с подтверждением).
network::conn::tui::link_down() {
    local -r ifc="$(network::conn::tui::__focus_if)"
    [[ -n "${ifc}" ]] || return 0
    local warn=""
    [[ "${NET_TUI_INFO[route]:-}" == *"(${ifc})" ]] && warn=" Это маршрут по умолчанию: связь пропадёт."
    network::conn::tui::confirm "Опустить ${ifc}?${warn}" network::conn::tui::__link down "${ifc}"
}

# @description Enter on the interface list: toggle the link / Enter в списке интерфейсов: переключить.
network::conn::tui::toggle_link() {
    local -r ifc="$(network::conn::tui::__focus_if)"
    [[ -n "${ifc}" ]] || return 0
    if [[ "${NET_TUI_STATE[${ifc}]:-}" == up ]] || network::conn::admin_up "${ifc}"; then
        network::conn::tui::link_down
    else
        network::conn::tui::link_up
    fi
}

# @private
network::conn::tui::__profile_set() {
    local -r act="$1" uuid="$2" name="$3"
    if [[ "${act}" == up ]]; then
        network::conn::tui::__busy "Включаю «${name}»…"
        network::conn::tui::__run "«${name}» включён / activated" network::conn::nm::up "${uuid}"
    else
        network::conn::tui::__busy "Выключаю «${name}»…"
        network::conn::tui::__run "«${name}» выключен / deactivated" network::conn::nm::down "${uuid}"
    fi
    network::conn::tui::reload
    network::conn::tui::details 1
}

# @description Enter on the profile list: activate, or deactivate after confirmation.
# @description Enter в списке профилей: включить или (после подтверждения) выключить.
network::conn::tui::toggle_profile() {
    local name uuid _t _d active
    IFS=$'\t' read -r name uuid _t _d active <<< "${NET_TUI_PROF[${NET_TUI_SEL[nm]}]:-}"
    [[ -n "${uuid}" ]] || return 0
    if [[ "${active}" == yes ]]; then
        network::conn::tui::confirm "Выключить «${name}»?" network::conn::tui::__profile_set down "${uuid}" "${name}"
    else
        network::conn::tui::__profile_set up "${uuid}" "${name}"
    fi
}

# @description Scan Wi-Fi and open the network list / Найти сети Wi-Fi и открыть их список.
# @param $1 [rescan] yes|auto
network::conn::tui::wifi() {
    if [[ "${NET_TUI_INFO[nm]:-0}" != 1 ]]; then
        network::conn::tui::say warn "Wi-Fi: нужен NetworkManager (nmcli) / NetworkManager required"
        return 0
    fi
    network::conn::tui::__busy "Поиск сетей Wi-Fi…"
    mapfile -t NET_TUI_WIFI < <(network::conn::wifi::scan "${1:-auto}" 2>/dev/null)
    NET_TUI_M[wsel]=0
    NET_TUI_MODAL="wifi"
    network::conn::tui::say info "Найдено сетей: ${#NET_TUI_WIFI[@]}"
}

# @private
# @description Keys in the Wi-Fi list / Клавиши в списке Wi-Fi.
network::conn::tui::__wifi_key() {
    local -i sel="${NET_TUI_M[wsel]:-0}" n=${#NET_TUI_WIFI[@]}
    case "$1" in
        UP|k) (( sel > 0 )) && sel=$(( sel - 1 )) ;;
        DOWN|j) (( sel < n - 1 )) && sel=$(( sel + 1 )) ;;
        R|r) NET_TUI_MODAL=""; network::conn::tui::wifi yes; return 0 ;;
        o|O) network::conn::tui::__run "Wi-Fi включён / radio on" network::conn::wifi::radio on ;;
        f|F) network::conn::tui::__run "Wi-Fi выключен / radio off" network::conn::wifi::radio off ;;
        ESC|q) NET_TUI_MODAL="" ;;
        ENTER)
            (( n > 0 )) || return 0
            local _in ssid _sig sec _ch
            IFS=$'\t' read -r _in ssid _sig sec _ch <<< "${NET_TUI_WIFI[sel]}"
            NET_TUI_MODAL=""
            NET_TUI_M[ssid]="${ssid}"
            if [[ "${sec}" == "--" ]] || network::conn::wifi::known "${ssid}"; then
                network::conn::tui::__wifi_join ""
            else
                network::conn::tui::ask "Wi-Fi · ${ssid}" "Пароль сети (${sec}):" network::conn::tui::__wifi_join "" 1
            fi
            return 0 ;;
    esac
    NET_TUI_M[wsel]="${sel}"
}

# @private
# @description Connect to NET_TUI_M[ssid] with the given password / Подключиться к NET_TUI_M[ssid] с паролем.
network::conn::tui::__wifi_join() {
    local -r ssid="${NET_TUI_M[ssid]:-}"
    [[ -n "${ssid}" ]] || return 0
    network::conn::tui::__busy "Подключаюсь к «${ssid}»…"
    network::conn::tui::__run "Подключено к «${ssid}» / connected" network::conn::wifi::connect "${ssid}" "${1-}"
    network::conn::tui::reload
    network::conn::tui::details 1
}

# @description Help modal / Модалка справки.
network::conn::tui::help() {
    network::conn::tui::show_text "Справка — BS NET" \
        "↑↓ j k PgUp PgDn Home End — выбор строки" \
        "Tab        — интерфейсы ↔ профили NetworkManager" \
        "Enter      — интерфейс: поднять/опустить · профиль: включить/выключить" \
        "u / d      — поднять / опустить выбранный интерфейс" \
        "w          — сети Wi-Fi: Enter подключить, R искать снова, o/f радио" \
        "r          — перечитать всё" \
        "?          — эта справка          q — выход" \
        "" \
        "Сведения берутся из /sys/class/net и /proc/net/route; адреса — через ip." \
        "Интерфейсы под NetworkManager переключаются через nmcli, остальные —" \
        "через «ip link set» (нужен root: TUI спросит пароль sudo)." \
        "Пароль Wi-Fi уходит в nmcli аргументом командной строки."
}

# Main loop / Главный цикл

# @private
# @description Move the selection by N rows in the current view / Сдвинуть выбор на N строк.
network::conn::tui::__move() {
    local -r v="${NET_TUI_VIEW}"
    local -i n=${#NET_TUI_IFS[@]}
    [[ "${v}" == nm ]] && n=${#NET_TUI_PROF[@]}
    local -i s=$(( NET_TUI_SEL[${v}] + $1 ))
    (( s >= n )) && s=$(( n - 1 ))
    (( s < 0 )) && s=0
    NET_TUI_SEL["${v}"]="${s}"
}

# @description Handle one key in the main view / Обработать клавишу в основном экране.
# @return 0 continue, 1 quit
network::conn::tui::key() {
    if [[ -n "${NET_TUI_MODAL}" ]]; then
        network::conn::tui::__modal_key
        return 0
    fi
    case "${TUI_KEY}" in
        UP|k) network::conn::tui::__move -1 ;;
        DOWN|j) network::conn::tui::__move 1 ;;
        PGUP) network::conn::tui::__move -10 ;;
        PGDN) network::conn::tui::__move 10 ;;
        HOME) network::conn::tui::__move -100000 ;;
        END) network::conn::tui::__move 100000 ;;
        TAB|LEFT|RIGHT)
            if [[ "${NET_TUI_VIEW}" == if ]]; then NET_TUI_VIEW="nm"; else NET_TUI_VIEW="if"; fi ;;
        ENTER|' ')
            if [[ "${NET_TUI_VIEW}" == if ]]; then network::conn::tui::toggle_link; else network::conn::tui::toggle_profile; fi ;;
        u|U) network::conn::tui::link_up ;;
        d|D) network::conn::tui::link_down ;;
        w|W) network::conn::tui::wifi ;;
        r|R) network::conn::tui::reload; network::conn::tui::details 1; network::conn::tui::say ok "Обновлено / refreshed" ;;
        '?'|F1|h|H) network::conn::tui::help ;;
        q|Q|й|Й|ESC) return 1 ;;
    esac
    return 0
}

# @private
# @description Sleep up to $1 × 50 ms, waking as soon as a key is available.
# @description Спать до $1 × 50 мс, просыпаясь, как только есть клавиша.
network::conn::tui::__wait_key() {
    local -i i steps="${1:-10}"
    for (( i = 0; i < steps; i++ )); do
        read -r -t 0 && return 0
        read -r -t 0.05 -u "${NET_TUI_SLEEP_FD}" || :
    done
    read -r -t 0
}

# @description Collect title facts: host name and NetworkManager / Собрать сведения заголовка: хост и NetworkManager.
network::conn::tui::probe() {
    NET_TUI_INFO[host]="${HOSTNAME:-$(uname -n 2>/dev/null)}"
    NET_TUI_INFO[nm]=0
    network::conn::nm::available && NET_TUI_INFO[nm]=1
    return 0
}

# @description Run the TUI until q / Запустить TUI до q.
# @param $1 [view] if|nm|wifi — start view / начальная панель
# @return 0
network::conn::tui::run() {
    local -r start="${1:-if}"
    network::conn::tui::probe
    exec {NET_TUI_SLEEP_FD}<> <(:)
    tui::init
    tui::mouse_off
    tui::paste_on
    network::conn::tui::__styles
    network::conn::tui::reload
    network::conn::tui::sample
    case "${start}" in
        nm) NET_TUI_VIEW="nm" ;;
        wifi) network::conn::tui::wifi ;;
    esac
    is::command ip || network::conn::tui::say warn "Нет утилиты ip (iproute2): адреса IPv4 и up/down без NetworkManager недоступны"
    NET_TUI_RUN=1
    NET_TUI_TICK="${SECONDS}"
    local -i reload_at="${SECONDS}"
    while (( NET_TUI_RUN == 1 )); do
        tui::handle_resize
        network::conn::tui::draw
        tui::render
        if network::conn::tui::__wait_key 20; then
            tui::key_read
            network::conn::tui::key || NET_TUI_RUN=0
        fi
        if (( SECONDS != NET_TUI_TICK )); then
            NET_TUI_TICK="${SECONDS}"
            network::conn::tui::sample
            # состояние и адреса — раз в 3 с / states and addresses every 3 s
            if (( SECONDS - reload_at >= 3 )) && [[ -z "${NET_TUI_MODAL}" ]]; then
                reload_at="${SECONDS}"
                network::conn::tui::reload
            fi
        fi
    done
    tui::paste_off
    tui::quit
    exec {NET_TUI_SLEEP_FD}>&-
    return 0
}
