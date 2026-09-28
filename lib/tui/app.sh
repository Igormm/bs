#!/usr/bin/env bs
# shellcheck shell=bash
# lib/tui/app.sh — declarative TUI apps: windows, buttons, modals, bindings
# lib/tui/app.sh — декларативные TUI-приложения: окна, кнопки, модалки, биндинги

# @depends lib/tui/tui
# @tier core

# Source Guard
bs::guard "LIB_TUI_APP" || return 0

# Dependencies
bs::source_relative "tui.sh"

# ==========================================
# High-level app layer on top of lib/tui.
#
# A beginner-friendly way to build small terminal UIs without writing the
# main loop, key dispatch and modal plumbing by hand:
#
#   load "lib/tui/app"
#   main() {
#       tui::app::window main "Hello" 2 2 30 9
#       tui::app::button main greet "Say hello" 3 4
#       tui::app::on greet app::say_hello
#       tui::app::statusbar "Tab — next button, Enter — press, q — quit"
#       tui::app::run
#   }
#   main "$@"
#
# The app layer provides: windows (titled boxes), buttons with keyboard
# focus, global key bindings, message/input/confirm modals, a statusbar
# and the main loop. Explicit bindings always win over default keys.
#
# Высокоуровневый слой поверх lib/tui. Позволяет новичкам собирать
# небольшие TUI без ручного цикла, диспатча клавиш и модалок:
# окна (рамки с заголовком), кнопки с фокусом, глобальные биндинги
# клавиш, модалки сообщения/ввода/подтверждения, статус-бар и цикл.
# Явные биндинги всегда имеют приоритет над клавишами по умолчанию.
#
# Default keys / Клавиши по умолчанию:
#   TAB/стрелки — следующий/предыдущий фокус кнопки (если кнопки есть)
#   ENTER        — нажать кнопку под фокусом (если не забиндено)
#   q            — выйти из приложения (если не забиндено)
#   ESC          — закрыть открытую модалку
# ==========================================

# @global TUI_APP_WINDOWS — Tui: window registry (category: state)
# @global TUI_APP_WINDOWS — Tui: реестр окон (категория: state)
declare -gA TUI_APP_WINDOWS=()
# @global TUI_APP_BUTTONS — Tui: button registry (category: state)
# @global TUI_APP_BUTTONS — Tui: реестр кнопок (категория: state)
declare -gA TUI_APP_BUTTONS=()
# @global TUI_APP_CALLBACKS — Tui: button press callbacks (category: state)
# @global TUI_APP_CALLBACKS — Tui: колбэки нажатия кнопок (категория: state)
declare -gA TUI_APP_CALLBACKS=()
# @global TUI_APP_BINDINGS — Tui: key -> callback map (category: state)
# @global TUI_APP_BINDINGS — Tui: карта клавиша -> колбэк (категория: state)
declare -gA TUI_APP_BINDINGS=()
# @global TUI_APP_DRAW_HOOKS — Tui: extra draw callbacks (category: state)
# @global TUI_APP_DRAW_HOOKS — Tui: дополнительные draw-колбэки (категория: state)
declare -ga TUI_APP_DRAW_HOOKS=()
# @global TUI_APP_FOCUS_ORDER — Tui: button focus order (category: state)
# @global TUI_APP_FOCUS_ORDER — Tui: порядок фокуса кнопок (категория: state)
declare -ga TUI_APP_FOCUS_ORDER=()
# @global TUI_APP_FOCUS — Tui: focused button id (category: state)
# @global TUI_APP_FOCUS — Tui: id кнопки под фокусом (категория: state)
declare -g TUI_APP_FOCUS=""
# @global TUI_APP_STOP — Tui: quit flag (category: state)
# @global TUI_APP_STOP — Tui: флаг выхода (категория: state)
declare -gi TUI_APP_STOP=0
# @global TUI_APP_MODAL — Tui: active modal name (category: state)
# @global TUI_APP_MODAL — Tui: имя активной модалки (категория: state)
declare -g TUI_APP_MODAL=""
# @global TUI_APP_MODAL_TITLE — Tui: modal title (category: state)
# @global TUI_APP_MODAL_TITLE — Tui: заголовок модалки (категория: state)
declare -g TUI_APP_MODAL_TITLE=""
# @global TUI_APP_MODAL_TEXT — Tui: modal message text (category: state)
# @global TUI_APP_MODAL_TEXT — Tui: текст сообщения модалки (категория: state)
declare -g TUI_APP_MODAL_TEXT=""
# @global TUI_APP_MODAL_SUBMIT — Tui: input modal submit callback (category: state)
# @global TUI_APP_MODAL_SUBMIT — Tui: колбэк подтверждения ввода (категория: state)
declare -g TUI_APP_MODAL_SUBMIT=""
# @global TUI_APP_MODAL_CANCEL — Tui: input modal cancel callback (category: state)
# @global TUI_APP_MODAL_CANCEL — Tui: колбэк отмены ввода (категория: state)
declare -g TUI_APP_MODAL_CANCEL=""
# @global TUI_APP_MODAL_YES — Tui: confirm modal yes callback (category: state)
# @global TUI_APP_MODAL_YES — Tui: колбэк «да» подтверждения (категория: state)
declare -g TUI_APP_MODAL_YES=""
# @global TUI_APP_MODAL_CLOSE — Tui: message modal close callback (category: state)
# @global TUI_APP_MODAL_CLOSE — Tui: колбэк закрытия сообщения (категория: state)
declare -g TUI_APP_MODAL_CLOSE=""
# @global TUI_APP_INPUT — Tui: input modal buffer (category: state)
# @global TUI_APP_INPUT — Tui: буфер ввода модалки (категория: state)
declare -g TUI_APP_INPUT=""
# @global TUI_APP_INPUT_CURSOR — Tui: input modal cursor (category: state)
# @global TUI_APP_INPUT_CURSOR — Tui: курсор ввода модалки (категория: state)
declare -gi TUI_APP_INPUT_CURSOR=0
# @global TUI_APP_CONFIRM_SEL — Tui: confirm modal selection (category: state)
# @global TUI_APP_CONFIRM_SEL — Tui: выбор модалки подтверждения (категория: state)
declare -gi TUI_APP_CONFIRM_SEL=0
# @global TUI_APP_STATUS — Tui: statusbar text (category: state)
# @global TUI_APP_STATUS — Tui: текст статус-бара (категория: state)
declare -g TUI_APP_STATUS=""

# @private
# @description Reset all app state (also before run in tests).
# @description Сбросить всё состояние приложения (и перед run в тестах).
tui::app::__reset() {
    TUI_APP_WINDOWS=()
    TUI_APP_BUTTONS=()
    TUI_APP_CALLBACKS=()
    TUI_APP_BINDINGS=()
    TUI_APP_DRAW_HOOKS=()
    TUI_APP_FOCUS_ORDER=()
    TUI_APP_FOCUS=""
    TUI_APP_STOP=0
    TUI_APP_MODAL=""
    TUI_APP_INPUT=""
    TUI_APP_INPUT_CURSOR=0
    TUI_APP_CONFIRM_SEL=0
    TUI_APP_STATUS=""
    TUI_APP_MODAL_TITLE=""
    TUI_APP_MODAL_TEXT=""
    TUI_APP_MODAL_SUBMIT=""
    TUI_APP_MODAL_CANCEL=""
    TUI_APP_MODAL_YES=""
    TUI_APP_MODAL_CLOSE=""
    return "${E_SUCCESS:-0}"
}

# @description Declare a titled window (box).
# @description Объявить окно (рамку с заголовком).
# @param $1 id, $2 title, $3 row, $4 col, $5 width, $6 height, $7 [style]
tui::app::window() {
    local -r id="${1:?window id required}" title="${2:-}"
    local -r row="${3:-2}" col="${4:-2}" w="${5:-40}" h="${6:-10}" style="${7-}"
    TUI_APP_WINDOWS["${id}"]="${title}"$'\t'"${row}"$'\t'"${col}"$'\t'"${w}"$'\t'"${h}"$'\t'"${style}"
    return "${E_SUCCESS:-0}"
}

# @description Declare a button inside a window. Row/col are relative to the
# @description window's top-left corner (border excluded).
# @description Объявить кнопку внутри окна. row/col — относительно левого
# @description верхнего угла окна (рамка не входит).
# @param $1 window id, $2 button id, $3 label, $4 row, $5 col
tui::app::button() {
    local -r win="${1:?window id required}" id="${2:?button id required}"
    local -r label="${3:?label required}" row="${4:-0}" col="${5:-0}"
    if is::empty "${TUI_APP_WINDOWS["${win}"]:-}"; then
        log::warn "tui::app::button: unknown window \"${win}\", declare it with tui::app::window first"
    fi
    TUI_APP_BUTTONS["${id}"]="${win}"$'\t'"${label}"$'\t'"${row}"$'\t'"${col}"
    TUI_APP_FOCUS_ORDER+=("${id}")
    return "${E_SUCCESS:-0}"
}

# @description Set the button press callback.
# @description Задать колбэк нажатия кнопки.
# @param $1 button id, $2 callback
tui::app::on() {
    local -r id="${1:?button id required}" cb="${2:?callback required}"
    if is::empty "${TUI_APP_BUTTONS["${id}"]:-}"; then
        log::warn "tui::app::on: unknown button \"${id}\", declare it with tui::app::button first"
    fi
    TUI_APP_CALLBACKS["${id}"]="${cb}"
    return "${E_SUCCESS:-0}"
}

# @description Bind keys (pipe-separated) to a callback with optional args.
# @description Explicit bindings always win over the default keys.
# @description Привязать клавиши (через |) к колбэку с опциональными
# @description аргументами. Явные биндинги всегда приоритетнее клавиш
# @description по умолчанию.
# @param $1 keys e.g. "up|k|ц", $2 callback, $@ [args passed to callback]
tui::app::bind() {
    local -r keys="${1:?keys required}" cb="${2:?callback required}"
    shift 2
    local argstr="${cb}"
    local arg
    for arg in "$@"; do
        if [[ "${arg}" == *$'\x1e'* ]]; then
            log::warn "tui::app::bind: argument contains the record separator, splitting may break"
        fi
        argstr+=$'\x1e'"${arg}"
    done
    local key
    local IFS='|'
    for key in ${keys}; do
        TUI_APP_BINDINGS["${key}"]="${argstr}"
    done
    return "${E_SUCCESS:-0}"
}

# @description Set the initial button focus.
# @description Установить начальный фокус кнопки.
# @param $1 button id
tui::app::focus() {
    local -r id="${1:?button id required}"
    if is::empty "${TUI_APP_BUTTONS["${id}"]:-}"; then
        log::warn "tui::app::focus: unknown button \"${id}\", declare it with tui::app::button first"
    fi
    TUI_APP_FOCUS="${id}"
    return "${E_SUCCESS:-0}"
}

# @description Set the statusbar text.
# @description Задать текст статус-бара.
# @param $1 text
tui::app::statusbar() {
    local -r text="${1:-}"
    TUI_APP_STATUS="${text}"
    return "${E_SUCCESS:-0}"
}

# @description Register an extra draw callback (custom content such as a
# @description list). Called after windows/buttons, before the statusbar.
# @description Зарегистрировать дополнительный draw-колбэк (произвольный
# @description контент, например список). Вызывается после окон/кнопок.
# @param $1 callback
tui::app::draw_hook() {
    local -r cb="${1:?callback required}"
    TUI_APP_DRAW_HOOKS+=("${cb}")
    return "${E_SUCCESS:-0}"
}

# @description Open a message dialog. Enter/Esc/q closes it, then the
# @description optional close callback runs.
# @description Открыть модалку сообщения. Enter/Esc/q закрывают её, затем
# @description выполняется необязательный колбэк закрытия.
# @param $1 title, $2 text, $3 [on close callback]
tui::app::message_modal() {
    local -r title="${1:?title required}" text="${2:-}" close_cb="${3-}"
    TUI_APP_MODAL="message"
    TUI_APP_MODAL_TITLE="${title}"
    TUI_APP_MODAL_TEXT="${text}"
    TUI_APP_MODAL_CLOSE="${close_cb}"
    return "${E_SUCCESS:-0}"
}

# @description Open an input modal. On Enter the submit callback runs with
# @description the text as $1; on Esc the cancel callback (if any) runs.
# @description Открыть модалку ввода. По Enter вызывается колбэк
# @description подтверждения с текстом в $1; по Esc — колбэк отмены.
# @param $1 title, $2 on submit callback, $3 [on cancel callback],
# @param $4 [prefill text]
tui::app::input_modal() {
    local -r title="${1:?title required}" submit="${2:?submit callback required}"
    local -r cancel="${3-}" prefill="${4-}"
    TUI_APP_MODAL="input"
    TUI_APP_MODAL_TITLE="${title}"
    TUI_APP_MODAL_SUBMIT="${submit}"
    TUI_APP_MODAL_CANCEL="${cancel}"
    TUI_APP_INPUT="${prefill}"
    TUI_APP_INPUT_CURSOR=${#prefill}
    return "${E_SUCCESS:-0}"
}

# @description Open a Yes/No confirm modal. Enter/y activates the selected
# @description option, Esc/n cancels, Left/Right/Tab switches the option.
# @description Открыть модалку подтверждения Да/Нет. Enter/y активируют
# @description выбранный вариант, Esc/n отменяют, ←/→/Tab переключают.
# @param $1 title, $2 text, $3 on yes callback, $4 [on cancel callback]
tui::app::confirm_modal() {
    local -r title="${1:?title required}" text="${2:-}"
    local -r yes_cb="${3:?yes callback required}" cancel_cb="${4-}"
    TUI_APP_MODAL="confirm"
    TUI_APP_MODAL_TITLE="${title}"
    TUI_APP_MODAL_TEXT="${text}"
    TUI_APP_MODAL_YES="${yes_cb}"
    TUI_APP_MODAL_CANCEL="${cancel_cb}"
    TUI_APP_CONFIRM_SEL=0
    return "${E_SUCCESS:-0}"
}

# @description Close the active modal.
# @description Закрыть активную модалку.
tui::app::close_modal() {
    TUI_APP_MODAL=""
    TUI_APP_INPUT=""
    TUI_APP_INPUT_CURSOR=0
    TUI_APP_CONFIRM_SEL=0
    return "${E_SUCCESS:-0}"
}

# @description Request the app loop to stop (call from a callback).
# @description Попросить цикл приложения остановиться (вызов из колбэка).
tui::app::quit() {
    TUI_APP_STOP=1
    return "${E_SUCCESS:-0}"
}

# @private
# @description Draw all windows, buttons, statusbar and the active modal.
# @description Нарисовать окна, кнопки, статус-бар и активную модалку.
tui::app::__draw() {
    local wid data title row col w h style
    for wid in "${!TUI_APP_WINDOWS[@]}"; do
        data="${TUI_APP_WINDOWS["${wid}"]}"
        IFS=$'\t' read -r title row col w h style <<< "${data}"
        local box_style="${style:-$(tui::style bold magenta)}"
        tui::box "${row}" "${col}" "${w}" "${h}" "${title}" "${box_style}"
    done

    local id bdata win label brow bcol
    for id in "${TUI_APP_FOCUS_ORDER[@]}"; do
        bdata="${TUI_APP_BUTTONS["${id}"]:-}"
        is::empty "${bdata}" && continue
        IFS=$'\t' read -r win label brow bcol <<< "${bdata}"
        data="${TUI_APP_WINDOWS["${win}"]:-}"
        is::empty "${data}" && continue
        IFS=$'\t' read -r title row col w h style <<< "${data}"
        local abs_r=$(( row + brow )) abs_c=$(( col + bcol ))
        local st
        if [[ "${id}" == "${TUI_APP_FOCUS}" ]]; then
            st="$(tui::style bold reverse cyan)"
        else
            st="$(tui::style cyan)"
        fi
        tui::put "${abs_r}" "${abs_c}" "[ ${label} ]" "${st}"
    done
    return 0
}

# @private
# @description Draw the active modal.
# @description Нарисовать активную модалку.
tui::app::__draw_modal() {
    local -i w=56 h=7
    local st
    st="$(tui::style bold cyan)"
    case "${TUI_APP_MODAL}" in
        message)
            tui::center "${w}" "${h}"
            tui::box "${TUI_CENTER_Y}" "${TUI_CENTER_X}" "${w}" "${h}" \
                "${TUI_APP_MODAL_TITLE}" "${st}"
            tui::put $(( TUI_CENTER_Y + 2 )) $(( TUI_CENTER_X + 2 )) \
                "${TUI_APP_MODAL_TEXT:0:$(( w - 4 ))}"
            tui::put $(( TUI_CENTER_Y + 4 )) $(( TUI_CENTER_X + w / 2 - 3 )) \
                "[ OK ]" "$(tui::style reverse green)"
            ;;
        input)
            tui::center "${w}" 5
            tui::box "${TUI_CENTER_Y}" "${TUI_CENTER_X}" "${w}" 5 \
                "${TUI_APP_MODAL_TITLE}" "${st}"
            tui::put $(( TUI_CENTER_Y + 2 )) $(( TUI_CENTER_X + 2 )) "▸"
            tui::input $(( TUI_CENTER_Y + 2 )) $(( TUI_CENTER_X + 4 )) $(( w - 6 )) \
                "${TUI_APP_INPUT}" "${TUI_APP_INPUT_CURSOR}"
            ;;
        confirm)
            tui::confirm "${TUI_APP_MODAL_TITLE}" "${TUI_APP_MODAL_TEXT}" \
                "${TUI_APP_CONFIRM_SEL}"
            ;;
    esac
    return 0
}

# @private
# @description Move focus to the next/previous button (cyclic).
# @description Переместить фокус на следующую/предыдущую кнопку (циклично).
# @param $1 direction: next|prev
tui::app::__focus_move() {
    local -r dir="${1:-next}"
    local -i n=${#TUI_APP_FOCUS_ORDER[@]}
    (( n == 0 )) && return 0
    local -i cur=0 i
    if is::not_empty "${TUI_APP_FOCUS}"; then
        for (( i = 0; i < n; i++ )); do
            if [[ "${TUI_APP_FOCUS_ORDER[${i}]}" == "${TUI_APP_FOCUS}" ]]; then
                cur="${i}"
                break
            fi
        done
    fi
    if [[ "${dir}" == "prev" ]]; then
        cur=$(( (cur + n - 1) % n ))
    else
        cur=$(( (cur + 1) % n ))
    fi
    TUI_APP_FOCUS="${TUI_APP_FOCUS_ORDER[${cur}]}"
    return 0
}

# @private
# @description Handle one key in the input modal.
# @description Обработать одну клавишу в модалке ввода.
tui::app::__key_input() {
    case "${TUI_KEY}" in
        ENTER)
            local text="${TUI_APP_INPUT}"
            tui::app::close_modal
            "${TUI_APP_MODAL_SUBMIT}" "${text}"
            ;;
        ESC)
            tui::app::close_modal
            is::not_empty "${TUI_APP_MODAL_CANCEL}" && "${TUI_APP_MODAL_CANCEL}"
            ;;
        BACKSPACE)
            if (( TUI_APP_INPUT_CURSOR > 0 )); then
                TUI_APP_INPUT="${TUI_APP_INPUT:0:${TUI_APP_INPUT_CURSOR}-1}${TUI_APP_INPUT:${TUI_APP_INPUT_CURSOR}}"
                TUI_APP_INPUT_CURSOR=$(( TUI_APP_INPUT_CURSOR - 1 ))
            fi
            ;;
        LEFT)
            if (( TUI_APP_INPUT_CURSOR > 0 )); then
                TUI_APP_INPUT_CURSOR=$(( TUI_APP_INPUT_CURSOR - 1 ))
            fi
            ;;
        RIGHT)
            if (( TUI_APP_INPUT_CURSOR < ${#TUI_APP_INPUT} )); then
                TUI_APP_INPUT_CURSOR=$(( TUI_APP_INPUT_CURSOR + 1 ))
            fi
            ;;
        *)
            case "${TUI_KEY}" in
                ENTER|ESC|BACKSPACE|LEFT|RIGHT|UP|DOWN|TAB|UNKNOWN) return 0 ;;
            esac
            [[ "${#TUI_KEY}" -eq 1 ]] || return 0
            TUI_APP_INPUT="${TUI_APP_INPUT:0:${TUI_APP_INPUT_CURSOR}}${TUI_KEY}${TUI_APP_INPUT:${TUI_APP_INPUT_CURSOR}}"
            TUI_APP_INPUT_CURSOR=$(( TUI_APP_INPUT_CURSOR + 1 ))
            ;;
    esac
    return 0
}

# @description Dispatch one key to the app (used by run; testable directly).
# @description Передать одну клавишу приложению (используется run; можно
# @description вызывать напрямую в тестах).
# @param $1 key (same names as TUI_KEY)
tui::app::key() {
    TUI_KEY="${1:-}"
    case "${TUI_APP_MODAL}" in
        message)
            case "${TUI_KEY}" in
                ENTER|ESC|q|Q|й|Й)
                    tui::app::close_modal
                    is::not_empty "${TUI_APP_MODAL_CLOSE}" && "${TUI_APP_MODAL_CLOSE}"
                    ;;
            esac
            return 0
            ;;
        input)
            tui::app::__key_input
            return 0
            ;;
        confirm)
            case "${TUI_KEY}" in
                ENTER)
                    tui::app::close_modal
                    if (( TUI_APP_CONFIRM_SEL == 0 )); then
                        "${TUI_APP_MODAL_YES}"
                    else
                        is::not_empty "${TUI_APP_MODAL_CANCEL}" && "${TUI_APP_MODAL_CANCEL}"
                    fi
                    ;;
                ESC|n|N|н|Н)
                    tui::app::close_modal
                    is::not_empty "${TUI_APP_MODAL_CANCEL}" && "${TUI_APP_MODAL_CANCEL}"
                    ;;
                y|Y|д|Д)
                    tui::app::close_modal
                    "${TUI_APP_MODAL_YES}"
                    ;;
                LEFT|RIGHT|TAB)
                    TUI_APP_CONFIRM_SEL=$(( 1 - TUI_APP_CONFIRM_SEL ))
                    ;;
            esac
            return 0
            ;;
    esac

    # Явные биндинги имеют приоритет / Explicit bindings take precedence
    if is::not_empty "${TUI_APP_BINDINGS["${TUI_KEY}"]:-}"; then
        local bdata="${TUI_APP_BINDINGS["${TUI_KEY}"]}"
        local bcb="${bdata%%$'\x1e'*}"
        local -a barg=()
        if [[ "${bdata}" == *$'\x1e'* ]]; then
            IFS=$'\x1e' read -ra barg <<< "${bdata#*$'\x1e'}"
        fi
        "${bcb}" "${barg[@]}"
        return 0
    fi

    case "${TUI_KEY}" in
        q|Q|й|Й) tui::app::quit ;;
        TAB) tui::app::__focus_move next ;;
        UP|LEFT) tui::app::__focus_move prev ;;
        DOWN|RIGHT) tui::app::__focus_move next ;;
        ENTER)
            if is::not_empty "${TUI_APP_FOCUS}" && is::not_empty "${TUI_APP_CALLBACKS["${TUI_APP_FOCUS}"]:-}"; then
                "${TUI_APP_CALLBACKS["${TUI_APP_FOCUS}"]}"
            fi
            ;;
    esac
    return 0
}

# @description Run the app loop (init, draw, key dispatch, quit).
# @description Запустить цикл приложения (init, отрисовка, диспатч, выход).
tui::app::run() {
    tui::init
    TUI_APP_STOP=0
    while (( TUI_APP_STOP == 0 )); do
        tui::handle_resize
        tui::buf::clear
        tui::app::__draw
        local hook
        for hook in "${TUI_APP_DRAW_HOOKS[@]}"; do
            is::function "${hook}" && "${hook}"
        done
        if is::not_empty "${TUI_APP_STATUS}"; then
            tui::statusbar "  ${TUI_APP_STATUS}" "$(tui::style bg_black white)"
        fi
        tui::app::__draw_modal
        tui::render
        tui::key_read
        tui::app::key "${TUI_KEY}"
    done
    tui::quit
    return 0
}