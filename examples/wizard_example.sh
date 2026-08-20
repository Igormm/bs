#!/usr/bin/env bs
# shellcheck shell=bash
# examples/wizard_example.sh — Interactive setup wizard demo
# examples/wizard_example.sh — Демо интерактивного установщика
#
# Rounded Unicode menus with arrow-key navigation, multi-select checkboxes,
# live system info and a progress bar — pure BS framework, no external TUI libs.
# Скруглённые меню со стрелками, мультивыбор, живые данные о системе и
# прогресс-бар — чистый BS, без внешних TUI-библиотек.

set -euo pipefail

load "core/args"
load "lib/ui/presentation"
load "lib/system/hw"

args::flag fast
args::flag_describe fast "Skip the progress animation / Пропустить анимацию прогресса"
args::require "$@"

# ==========================================
# Wizard engine / Движок визарда
# ==========================================

# @private Show the cursor again on any exit (panic-safe).
wiz::__restore_cursor() {
    printf '\033[?25h'
}

# @private Draw a frame rule: ╭────╮ / ├────┤ / ╰────╯
# @param $1 Inner width, $2 Left, $3 Right (mid is always ─)
wiz::__rule() {
    local -r inner="$1" left="$2" right="$3"
    local line
    printf -v line '%*s' "${inner}" ''
    printf '%s%s%s\n' "${left}" "${line// /─}" "${right}"
}

# @private Display width of a string (emoji count as 2 cells).
# @private Ширина строки на экране (эмодзи считаются за 2 клетки).
wiz::__disp_width() {
    local s="$1" w=0 c blen i
    for ((i = 0; i < ${#s}; i++)); do
        c="${s:i:1}"
        blen=$(LC_ALL=C printf '%s' "$c" | wc -c)
        if (( blen >= 4 )); then (( w += 2 )); else (( w += 1 )); fi
    done
    printf '%s' "$w"
}

# @private Draw one frame row, padded by DISPLAY width.
# @param $1 Inner width, $2 Content, $3 [optional] ANSI color code
wiz::__row() {
    local -r inner="$1" content="$2" color="${3:-}"
    local w
    w="$(wiz::__disp_width "${content}")"
    if is::not_empty "${color}"; then
        printf '│\033[%sm%s\033[0m' "${color}" "${content}"
    else
        printf '│%s' "${content}"
    fi
    printf '%*s│\n' "$((inner - w))" ''
}

# @private Read one key, decoding arrow escapes / Прочитать клавишу (со стрелками).
# @stdout "up" | "down" | "enter" | "space" | the literal key
wiz::__read_key() {
    local key
    IFS= read -rsn1 key
    if [[ "${key}" == $'\e' ]]; then
        local seq
        IFS= read -rsn2 -t 0.1 seq || true
        case "${seq}" in
            '[A') printf 'up' ;;
            '[B') printf 'down' ;;
            *) printf 'esc' ;;
        esac
        return
    fi
    case "${key}" in
        '') printf 'enter' ;;
        ' ') printf 'space' ;;
        *) printf '%s' "${key}" ;;
    esac
}

# @description Single-choice rounded menu / Меню с одним выбором.
#   Result goes into the named variable (nameref) / Результат — в переменную.
# @param $1 Output variable: selected index (0-based)
# @param $2 Title / Заголовок
# @param $@ Items / Пункты
wiz::menu() {
    local -n __wiz_out="${1:?output variable required}"
    local -r title="${2:?title required}"
    shift 2
    local -a items=("$@")

    local max=0 i w
    for i in "${items[@]}" "${title}"; do
        w="$(wiz::__disp_width "  ▶ ${i}")"
        (( w > max )) && max=${w}
    done
    local -r inner=$((max + 4))

    local selected=0
    while true; do
        printf '\033[H\033[J'  # cursor home + clear below
        wiz::__rule "${inner}" '╭' '╮'
        wiz::__row "${inner}" "  ${title}"
        wiz::__rule "${inner}" '├' '┤'
        for i in "${!items[@]}"; do
            if (( i == selected )); then
                wiz::__row "${inner}" "  ▶ ${items[i]}" 36
            else
                wiz::__row "${inner}" "    ${items[i]}"
            fi
        done
        wiz::__rule "${inner}" '╰' '╯'
        printf '  ↑/↓ + Enter\n'

        case "$(wiz::__read_key)" in
            up)    (( selected = (selected - 1 + ${#items[@]}) % ${#items[@]} )) ;;
            down)  (( selected = (selected + 1) % ${#items[@]} )) ;;
            enter) break ;;
        esac
    done

    __wiz_out=${selected}
}

# @description Multi-choice rounded menu / Меню с множественным выбором.
#   Space toggles, Enter confirms / Пробел — переключить, Enter — готово.
# @param $1 Output variable: selected indices joined by space
# @param $2 Title / Заголовок
# @param $@ Items / Пункты
wiz::multi_menu() {
    local -n __wiz_out="${1:?output variable required}"
    local -r title="${2:?title required}"
    shift 2
    local -a items=("$@")
    local -a checked=()
    local i
    for i in "${!items[@]}"; do checked+=(0); done

    local max=0 w
    for i in "${items[@]}" "${title}"; do
        w="$(wiz::__disp_width "  ● ${i}")"
        (( w > max )) && max=${w}
    done
    local -r inner=$((max + 4))

    local selected=0
    while true; do
        printf '\033[H\033[J'
        wiz::__rule "${inner}" '╭' '╮'
        wiz::__row "${inner}" "  ${title}"
        wiz::__rule "${inner}" '├' '┤'
        for i in "${!items[@]}"; do
            local mark='○'
            (( ${checked[i]} == 1 )) && mark='●'
            if (( i == selected )); then
                wiz::__row "${inner}" "  ${mark} ${items[i]}" 36
            else
                wiz::__row "${inner}" "  ${mark} ${items[i]}"
            fi
        done
        wiz::__rule "${inner}" '╰' '╯'
        printf '  ↑/↓ + Space — toggle, Enter — done / Пробел — выбор, Enter — готово\n'

        case "$(wiz::__read_key)" in
            up)    (( selected = (selected - 1 + ${#items[@]}) % ${#items[@]} )) ;;
            down)  (( selected = (selected + 1) % ${#items[@]} )) ;;
            space) (( checked[selected] = 1 - checked[selected] )) ;;
            enter) break ;;
        esac
    done

    local -a picked_idx=()
    for i in "${!items[@]}"; do
        (( ${checked[i]} == 1 )) && picked_idx+=("${i}")
    done
    __wiz_out="${picked_idx[*]:-}"
}

# ==========================================
# The wizard itself / Сам визард
# ==========================================

main() {
    signal::on EXIT wiz::__restore_cursor
    signal::on INT wiz::__restore_cursor
    printf '\033[?25l\033[2J'   # hide cursor, clear screen

    presentation::title "B S   W I Z A R D"

    # --- Welcome with live system info / Приветствие с живыми данными
    local -r model="$(system::hw::cpu_model)"
    local -r cores="$(system::hw::cpu_threads)"
    local -r ram="$(system::hw::mem_total)"

    presentation::boxed "Добро пожаловать! / Welcome!
Это установщик на чистом BS / This installer runs on pure BS

CPU:  ${model}
Cores: ${cores}    RAM: ${ram} MiB" round

    printf '  Enter — начать / to start'
    wiz::__read_key >/dev/null

    # --- Step 1: profile / Шаг 1: профиль
    local profile
    wiz::menu profile "Шаг 1/3 — Выбери профиль / Choose profile" \
        "🚀 Developer" "💻 Desktop" "🪶  Minimal"

    local -a profiles=("Developer" "Desktop" "Minimal")

    # --- Step 2: features / Шаг 2: компоненты
    local picked
    wiz::multi_menu picked "Шаг 2/3 — Компоненты / Features" \
        "🔧 system::hw — hardware info" \
        "📦 packages — package manager" \
        "🌐 network — network setup" \
        "🎨 ui — themes and prompts"

    # --- Step 3: summary / Шаг 3: сводка
    printf '\033[H\033[J'
    presentation::boxed "Шаг 3/3 — Сводка / Summary

Profile:   ${profiles[${profile}]}
Features:  ${picked:-none}" round
    printf '\n'

    # --- Fake install with progress bar / «Установка» с прогресс-баром
    if args::flag_get fast >/dev/null 2>&1; then
        :
    else
        local step
        for step in $(seq 0 10 100); do
            presentation::progress "${step}" 100 30
            sleep 0.1
        done
    fi

    printf '\n\n'
    presentation::success "Готово! Визард завершён / Wizard finished"
}

main "$@"
