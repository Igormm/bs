#!/usr/bin/env bs
# shellcheck shell=bash
# lib/ui/wizard.sh — full-screen wizard engine: centered frames, menus,
# checkboxes, y/n, editable text/password input, intro, framed errors
# lib/ui/wizard.sh — движок полноэкранных визардов: центрированные рамки,
# меню, чекбоксы, да/нет, редактируемый текстовый/парольный ввод,
# вступление, рамки ошибок
#
# Self-contained raw-ANSI engine (no lib/tui): centered frames with Unicode
# borders, safe key reading (arrows/digits/q, a lone ESC is a safe no-op),
# terminal restored on any exit. All raw escapes live ONLY in the named
# __esc/__sgr/__sgr_reset/__frame_col/__goto helpers (class D1 in
# bs-check-ansi). Used by examples/ai_user_wizard.sh and
# examples/opencode_serve_wizard.sh.
# Полностью автономный raw-ANSI движок (без lib/tui): центрированные рамки
# с юникод-бордюрами, безопасное чтение клавиш (стрелки/цифры/q, одиночный
# ESC — безопасный no-op), терминал восстанавливается при любом выходе.
# Сырые эскейпы живут ТОЛЬКО в именованных помощниках __esc/__sgr/
# __sgr_reset/__frame_col/__goto (класс D1 в bs-check-ansi). Используется
# визардами examples/ai_user_wizard.sh и examples/opencode_serve_wizard.sh.
#
# Usage / Использование:
#   load "lib/ui/wizard"
#   wizard::intro "Что это / WHAT" "строка1" "строка2" ...
#   wizard::ask_input var "Имя / Name" "default" "пояснение / desc"
#   wizard::ask_pass var "пояснение / desc"
#   wizard::menu var "Заголовок / Title" "desc" "Пункт 1" "Пункт 2"
#   wizard::multi_menu var "Заголовок / Title" "desc" "A" "B"
#   wizard::yn var "Вопрос / Question" "desc"
#   wizard::box "ЗАГОЛОВОК / TITLE" "строка1
#   строка2" "подсказка / hint"
#   wizard::alert "сообщение / message"       # рамка + ждать клавишу
#   wizard::fail "сообщение / message"        # рамка + exit 1
#   pass="$(wizard::gen_pass)"
#
# @depends core/lang, core/utils

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_UI_WIZARD" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/lang.sh" "../../core/utils.sh"

# @global __WIZ_COL — Wizard: frame column (0-based) (category: state)
# @global __WIZ_ROW — Wizard: frame row (category: state)
# @global __WIZ_LINES — Wizard: terminal lines (category: state)
# @global __WIZ_COLS — Wizard: terminal columns (category: state)
# @global __WIZ_COL — Визард: столбец рамки (с 0) (категория: state)
# @global __WIZ_ROW — Визард: строка рамки (категория: state)
# @global __WIZ_LINES — Визард: строки терминала (категория: state)
# @global __WIZ_COLS — Визард: колонки терминала (категория: state)
declare -g __WIZ_COL=0 __WIZ_ROW=0 __WIZ_LINES=24 __WIZ_COLS=80

# @private Restore the terminal on any exit (panic-safe).
# @private Восстановить терминал при любом выходе.
wizard::__restore() {
    wizard::__sgr_reset
    wizard::__esc '?25h'
    wizard::__esc '?1049l'
}

# @private Enter the alternate screen buffer (clean full-screen redraws).
# @private Войти в альтернативный буфер (чистая перерисовка на весь экран).
wizard::__enter_alt() {
    wizard::__esc '?1049h'
    wizard::__esc '?25l'
    wizard::__esc '2J'
}

# @private Terminal width from the real tty (ioctl), clamped to the box range.
# @private Ширина терминала из реального tty (ioctl), ограничена диапазоном рамки.
wizard::__box_width() {
    local -i tw=80
    local size
    if is::command stty && size="$(stty size 2>/dev/null)"; then
        tw="${size##* }"
    elif is::command tput; then
        tw="$(tput cols 2>/dev/null || printf 80)"
    fi
    tw=$(( tw - 4 ))
    (( tw > 76 )) && tw=76
    # Минимума 44 НЕТ: рамка (inner+2) должна влезать в терминал, иначе
    # строки переносятся — правая сторона отваливается, низ плывёт.
    # NO 44 floor: the frame (inner+2) must fit the terminal, otherwise
    # lines wrap — the right side falls off and the bottom drifts.
    (( tw < 4 )) && tw=4
    printf '%d' "${tw}"
}

wizard::__term_size() {
    local size
    __WIZ_LINES=24
    __WIZ_COLS=80
    if is::command stty && size="$(stty size 2>/dev/null)"; then
        __WIZ_LINES="${size%% *}"
        __WIZ_COLS="${size##* }"
    elif is::command tput; then
        __WIZ_COLS="$(tput cols 2>/dev/null || printf 80)"
        __WIZ_LINES="$(tput lines 2>/dev/null || printf 24)"
    fi
}

# @private Clear and position the cursor at the center of a frame.
# @private Очистить экран и поставить курсор в центр рамки.
# @param $1 Frame width / Ширина рамки
# @param $2 Frame height / Высота рамки
wizard::__frame_begin() {
    local -r width="$1" height="$2"
    wizard::__term_size
    __WIZ_COL=$(( (__WIZ_COLS - width) / 2 ))
    (( __WIZ_COL < 0 )) && __WIZ_COL=0
    local -i row=$(( (__WIZ_LINES - height) / 2 ))
    (( row < 0 )) && row=0
    __WIZ_ROW="${row}"
    wizard::__esc '2J'
    wizard::__goto "$((row + 1))" "$((__WIZ_COL + 1))"
}

# @private ANSI primitives / ANSI-примитивы
#   Сырые эскейпы живут ТОЛЬКО здесь, в именованных помощниках; остальной
#   код их не содержит (класс D1 в bs-check-ansi).
#   Raw escapes live ONLY here, in named helpers; the rest of the code has
#   none (class D1 in bs-check-ansi).

# @private ANSI sequence builder / Сборка ANSI-последовательности
# @param $1 Код без префикса ESC[ / code without the ESC[ prefix (напр. / e.g. "34m", "2J")
wizard::__esc() {
    printf '\033[%s' "${1}"
}

# @private SGR style on / SGR-стиль вкл (например / e.g. "34" = blue/синий)
#   'm' добавляем здесь — коды передаются БЕЗ суффикса, иначе терминал
#   глотает следующие символы как параметры SGR.
#   'm' is appended here — codes are passed WITHOUT the suffix, otherwise
#   the terminal eats the following characters as SGR parameters.
wizard::__sgr() {
    wizard::__esc "${1}m"
}

# @private Reset styles / Сброс стилей
wizard::__sgr_reset() {
    printf '\033[0m'
}

# @private Jump to the frame column / Переход в столбец рамки
wizard::__frame_col() {
    printf '\033[%dG' "$((__WIZ_COL + 1))"
}

# @private Cursor to row/col (1-based) / Курсор к строке/колонке (с 1)
wizard::__goto() {
    printf '\033[%d;%dH' "$1" "$2"
}

# @private Blue frame border "│" / Синий бордюр рамки "│"
wizard::__border() {
    wizard::__sgr 34
    printf '│'
    wizard::__sgr_reset
}

# @private Display width of a string (wide chars count as 2 cells).
#   Pure bash: ${#var} counts UTF-8 CHARACTERS (not bytes) with no fork at
#   all — the earlier wc -m version still forked once per row, and the
#   original per-char `printf|wc -c` loop forked per character (~5-15 ms
#   per row). Box glyphs (▶ ○ ● ✓ ╭ ╰) are 3-byte, 1-cell chars, so
#   chars == cells. Wide East-Asian chars would need a table lookup.
# @private Ширина строки на экране (широкие символы — 2 клетки).
#   Чистый bash: ${#var} считает UTF-8 СИМВОЛЫ (не байты) вообще без
#   форков — wc -m всё ещё форкал раз на строку, а исходный цикл
#   `printf|wc -c` — на каждый символ (~5-15 мс на строку). Символы рамки
#   (▶ ○ ● ✓ ╭ ╰) — 3-байтные, 1 клетка: символы == клетки.
wizard::__disp_width() {
    printf '%d' "${#1}"
}

# @private Frame rule: ╭────╮ / ├────┤ / ╰────╯
# @private Линия рамки: ╭────╮ / ├────┤ / ╰────╯
wizard::__rule() {
    local -r inner="$1" left="$2" right="$3"
    local line
    printf -v line '%*s' "${inner}" ''
    wizard::__frame_col
    wizard::__sgr 34
    printf '%s%s%s' "${left}" "${line// /─}" "${right}"
    wizard::__sgr_reset
    printf '\n'
}

# @private Frame row with padding (ANSI-aware width). Content longer than the
#   inner width is truncated with "…" so the frame never breaks.
# @private Строка рамки с паддингом (ширина с учётом ANSI). Контент длиннее
#   внутренней ширины обрезается с "…" — рамка никогда не рвётся.
# @param $1 Inner width, $2 Content, $3 [optional] ANSI color code
wizard::__row() {
    local -r inner="$1" content="$2" color="${3:-}"
    local text="${content}"
    if (( ${#text} > inner )); then
        # Truncate by char count (chars == cells for box glyphs).
        # Обрезаем по числу символов (символы == клетки для глифов рамки).
        text="${text:0:$((inner - 1))}…"
    fi
    wizard::__frame_col
    wizard::__border
    if is::not_empty "${color}"; then
        wizard::__sgr "${color}"
        printf '%s' "${text}"
        wizard::__sgr_reset
    else
        printf '%s' "${text}"
    fi
    printf '%*s' "$((inner - ${#text}))" ''
    wizard::__border
    printf '\n'
}

# @private Multi-line text inside a frame.
# @private Многострочный текст внутри рамки.
wizard::__text() {
    local -r inner="$1"
    local line
    while IFS= read -r line; do
        wizard::__row "${inner}" "${line}"
    done <<< "${2}"
}

# @private Green title row.
# @private Строка-заголовок зелёным.
wizard::__title_row() {
    local -r inner="$1" title="$2"
    wizard::__row "${inner}" "${title}" "1;32"
}

# @private Dim hint row.
# @private Затемнённая подсказка.
wizard::__hint() {
    wizard::__row "$1" "$2" "90"
}

# @private Read one key, decoding arrows + digits + q + editing keys.
# @private Прочитать клавишу: стрелки + цифры + q + клавиши редактирования.
# @stdout up|down|left|right|enter|space|backspace|del|q|1..9|char|esc
wizard::__read_key() {
    local key
    IFS= read -rsn1 key
    if [[ "${key}" == $'\e' ]]; then
        local seq
        IFS= read -rsn2 -t 0.1 seq || true
        case "${seq}" in
            '[A') printf 'up' ;;
            '[B') printf 'down' ;;
            '[C') printf 'right' ;;
            '[D') printf 'left' ;;
            '[3'|'[2') IFS= read -rsn1 -t 0.1 || true; printf 'del' ;;
            *) printf 'esc' ;;
        esac
        return
    fi
    case "${key}" in
        '') printf 'enter' ;;
        $'\x7f'|$'\x08') printf 'backspace' ;;
        ' ') printf 'space' ;;
        q|Q) printf 'q' ;;
        [1-9]) printf '%s' "${key}" ;;
        *) printf '%s' "${key}" ;;
    esac
}

# @description Generic framed screen: title + body lines + hint.
# @description Универсальная рамка: заголовок + строки + подсказка.
# @param $1 Title / Заголовок
# @param $2 Text (multi-line) / Текст (многострочный)
# @param $3 [optional] Hint row / Строка-подсказка
wizard::box() {
    local -r inner="$(wizard::__box_width)" title="$1" text="$2" hint="${3:-}"
    local -i lines=0
    while IFS= read -r _; do lines=$((lines + 1)); done <<< "${text}"
    wizard::__frame_begin $((inner + 2)) $((lines + 4))
    wizard::__rule "${inner}" '╭' '╮'
    wizard::__title_row "${inner}" "${title}"
    wizard::__rule "${inner}" '├' '┤'
    wizard::__text "${inner}" "${text}"
    wizard::__rule "${inner}" '╰' '╯'
    if is::not_empty "${hint}"; then
        wizard::__hint "${inner}" "${hint}"
    fi
}

# @description Welcome screen: what the wizard does and what you get.
# @description Вступление: что делает визард и что вы получите.
# @param $1 Title / Заголовок
# @param $@ Body lines / Строки тела
# @return 0 start / начать, 1 cancelled / отмена
wizard::intro() {
    local -r title="$1"
    shift
    local -r inner="$(wizard::__box_width)"
    local -a lines=("$@")
    while true; do
        wizard::__frame_begin $((inner + 2)) $(( ${#lines[@]} + 4 ))
        wizard::__rule "${inner}" '╭' '╮'
        wizard::__title_row "${inner}" "${title}"
        wizard::__rule "${inner}" '├' '┤'
        local line
        for line in "${lines[@]}"; do
            wizard::__row "${inner}" "${line}"
        done
        wizard::__rule "${inner}" '╰' '╯'
        wizard::__hint "${inner}" "  Enter — начать / to start · q — отмена / cancel"

        case "$(wizard::__read_key)" in
            enter|y|Y) return 0 ;;
            q)         return 1 ;;
        esac
    done
}

# @description Single-choice menu with arrows, digits 1-9, q to cancel.
# @description Меню с одним выбором: стрелки, цифры 1-9, q — отмена.
# @param $1 Output variable: selected index (0-based), 99 = cancelled
# @param $2 Title / Заголовок
# @param $3 [optional] Explanation row / Строка-пояснение
# @param $@ Items / Пункты
wizard::menu() {
    local -n __wiz_out="${1:?output variable required}"
    local -r title="${2:?title required}"
    local -r desc="${3:-}"
    shift 3
    local -a items=("$@")
    local -r inner="$(wizard::__box_width)"
    local -i frame_h=$(( ${#items[@]} + 5 ))
    is::not_empty "${desc}" && frame_h=$(( frame_h + 1 ))

    local selected=0
    while true; do
        wizard::__frame_begin $((inner + 2)) ${frame_h}
        wizard::__rule "${inner}" '╭' '╮'
        wizard::__title_row "${inner}" "${title}"
        if is::not_empty "${desc}"; then
            wizard::__hint "${inner}" "${desc}"
        fi
        wizard::__rule "${inner}" '├' '┤'
        for i in "${!items[@]}"; do
            if (( i == selected )); then
                wizard::__row "${inner}" "  ▶ ${items[i]}" "36"
            else
                wizard::__row "${inner}" "    ${items[i]}"
            fi
        done
        wizard::__rule "${inner}" '╰' '╯'
        wizard::__hint "${inner}" "  ↑/↓, 1-9 — выбор, Enter — OK, q — отмена"

        local key
        key="$(wizard::__read_key)"
        case "${key}" in
            up)   selected=$(( (selected - 1 + ${#items[@]}) % ${#items[@]} )) ;;
            down) selected=$(( (selected + 1) % ${#items[@]} )) ;;
            enter) break ;;
            q)    __wiz_out=99; return 0 ;;
            [1-9])
                if (( key >= 1 && key <= ${#items[@]} )); then
                    __wiz_out=$((key - 1)); return 0
                fi
                ;;
        esac
    done

    __wiz_out=${selected}
}

# @description Multi-choice menu (checkboxes): Space toggles, Enter confirms.
# @description Меню множественного выбора (чекбоксы): Space — выбор, Enter — ОК.
# @param $1 Output variable: indices joined by space, "q" = cancelled
# @param $2 Title / Заголовок
# @param $3 [optional] Explanation row / Строка-пояснение
# @param $@ Items / Пункты
wizard::multi_menu() {
    local -n __wiz_out="${1:?output variable required}"
    local -r title="${2:?title required}"
    local -r desc="${3:-}"
    shift 3
    local -a items=("$@")
    local -a checked=()
    local i
    for i in "${!items[@]}"; do checked+=(0); done
    local -r inner="$(wizard::__box_width)"
    local -i frame_h=$(( ${#items[@]} + 5 ))
    is::not_empty "${desc}" && frame_h=$(( frame_h + 1 ))

    local selected=0
    while true; do
        wizard::__frame_begin $((inner + 2)) ${frame_h}
        wizard::__rule "${inner}" '╭' '╮'
        wizard::__title_row "${inner}" "${title}"
        if is::not_empty "${desc}"; then
            wizard::__hint "${inner}" "${desc}"
        fi
        wizard::__rule "${inner}" '├' '┤'
        for i in "${!items[@]}"; do
            local mark='○'
            (( checked[i] == 1 )) && mark='●'
            if (( i == selected )); then
                wizard::__row "${inner}" "  ${mark} ${items[i]}" "36"
            else
                wizard::__row "${inner}" "  ${mark} ${items[i]}"
            fi
        done
        wizard::__rule "${inner}" '╰' '╯'
        wizard::__hint "${inner}" "  ↑/↓ — ход, Space — выбор, Enter — ОК, q — отмена"

        case "$(wizard::__read_key)" in
            up)    selected=$(( (selected - 1 + ${#items[@]}) % ${#items[@]} )) ;;
            down)  selected=$(( (selected + 1) % ${#items[@]} )) ;;
            space) checked[selected]=$(( 1 - checked[selected] )) ;;
            enter) break ;;
            q)     __wiz_out="q"; return 0 ;;
        esac
    done

    local -a picked_idx=()
    for i in "${!items[@]}"; do
        (( checked[i] == 1 )) && picked_idx+=("${i}")
    done
    __wiz_out="${picked_idx[*]:-}"
}

# @description Yes/No question inside a frame (with optional body lines).
# @description Вопрос Да/Нет в рамке (с опциональными строками тела).
# @param $1 Output variable: y|n|q
# @param $2 Question / Вопрос
# @param $3 [optional] Body lines / Строки тела
wizard::yn() {
    local -n __wiz_out="${1:?output variable required}"
    local -r question="$2" desc="${3:-}"
    local -r inner="$(wizard::__box_width)"
    local -i frame_h=6
    local -i desc_lines=0
    if is::not_empty "${desc}"; then
        while IFS= read -r _; do desc_lines=$((desc_lines + 1)); done <<< "${desc}"
        frame_h=$(( frame_h + desc_lines + 1 ))
    fi

    while true; do
        wizard::__frame_begin $((inner + 2)) ${frame_h}
        wizard::__rule "${inner}" '╭' '╮'
        wizard::__title_row "${inner}" "${question}"
        if is::not_empty "${desc}"; then
            wizard::__text "${inner}" "${desc}"
            wizard::__row "${inner}" ""
        fi
        wizard::__row "${inner}" "    Да / Yes"
        wizard::__row "${inner}" "    Нет / No"
        wizard::__rule "${inner}" '╰' '╯'
        wizard::__hint "${inner}" "  y/n или 1/2 — ответ, q — отмена"

        case "$(wizard::__read_key)" in
            y|Y|1) __wiz_out="y"; return 0 ;;
            n|N|2) __wiz_out="n"; return 0 ;;
            q)     __wiz_out="q"; return 0 ;;
        esac
    done
}

# @description Text input with a default value and inline editing
# (backspace, ←/→, printable chars only — control sequences never land in
# the value).
# @description Текстовый ввод со значением по умолчанию и редактированием
# (backspace, ←/→, только печатные символы — управляющие последовательности
# в значение не попадают).
# @param $1 Output variable / Выходная переменная
# @param $2 Prompt / Приглашение
# @param $3 Default / Значение по умолчанию
# @param $4 [optional] Explanation row / Строка-пояснение
wizard::ask_input() {
    local -n __wiz_out="${1:?output variable required}"
    local -r prompt="$2" default="${3:-}" desc="${4:-}"
    # Поле стартует ПУСТЫМ: дефолт — только при пустом вводе на Enter
    # (семантика оригинала; предзаполнение заставляло стирать дефолт).
    # The field starts EMPTY: the default applies only on an empty Enter
    # (original semantics; pre-filling forced erasing the default).
    local answer=""
    local -i cur=0
    local -r inner="$(wizard::__box_width)"
    local -i frame_h=8
    is::not_empty "${desc}" && frame_h=$(( frame_h + 1 ))
    # строка ввода зависит от наличия пояснения / input row shifts with the desc
    local -i input_row=6
    is::not_empty "${desc}" && input_row=7

    while true; do
        wizard::__frame_begin $((inner + 2)) ${frame_h}
        wizard::__rule "${inner}" '╭' '╮'
        wizard::__title_row "${inner}" "${prompt}"
        if is::not_empty "${desc}"; then
            wizard::__hint "${inner}" "${desc}"
        fi
        wizard::__row "${inner}" ""
        wizard::__row "${inner}" "  Введите / Enter [${default}]: " "33"
        wizard::__row "${inner}" ""
        wizard::__row "${inner}" "  ${answer}" "33"
        wizard::__hint "${inner}" "  Enter — ОК · ←/→ — курсор · Backspace — удалить · q — отмена"
        wizard::__rule "${inner}" '╰' '╯'
        # курсор в конец текущего значения / cursor to the end of the value
        wizard::__goto $((__WIZ_ROW + input_row)) $((__WIZ_COL + 2 + cur))

        local key
        key="$(wizard::__read_key)"
        case "${key}" in
            enter) break ;;
            q)     __wiz_out="q"; return 0 ;;
            backspace)
                (( cur > 0 )) || continue
                answer="${answer:0:$((cur - 1))}${answer:${cur}}"
                cur=$(( cur - 1 ))
                ;;
            left)  (( cur > 0 )) && cur=$(( cur - 1 )) ;;
            right) (( cur < ${#answer} )) && cur=$(( cur + 1 )) ;;
            up|down|del|esc) : ;;
            *)
                # только печатный символ: без ALT+/CTRL+/SHIFT+-комбинаций
                # printable char only: no ALT+/CTRL+/SHIFT+ combos
                if [[ "${key}" =~ ^[[:print:]]+$ ]] && [[ "${key}" != *[[:space:]]* ]] && [[ "${key}" != *+* ]]; then
                    answer="${answer:0:${cur}}${key}${answer:${cur}}"
                    cur=$(( cur + 1 ))
                fi
                ;;
        esac
    done

    if is::empty "${answer}"; then
        __wiz_out="${default}"
    else
        __wiz_out="${answer}"
    fi
}

# @description Hidden password input with confirmation (retries until match).
#   Masked ● for every char; q cancels; empty password = no password.
# @description Скрытый ввод пароля с подтверждением (до совпадения).
#   Маска ● на каждый символ; q — отмена; пустой пароль = без пароля.
# @param $1 Output variable / Выходная переменная
# @param $2 [optional] Explanation row / Строка-пояснение
wizard::ask_pass() {
    local -n __wiz_out="${1:?output variable required}"
    local -r desc="${2:-}"
    local -r inner="$(wizard::__box_width)"
    local -i frame_h=8
    is::not_empty "${desc}" && frame_h=$(( frame_h + 1 ))
    # строки ввода зависят от наличия пояснения / input rows shift with the desc
    local -i pass_row=6
    is::not_empty "${desc}" && pass_row=7
    local pass1="" pass2=""
    local -i cur1=0 cur2=0 field=1
    local m1 m2

    while true; do
        # маска из ● на каждый символ / ● mask per character
        printf -v m1 '%*s' "${#pass1}" ''
        m1="${m1// /●}"
        printf -v m2 '%*s' "${#pass2}" ''
        m2="${m2// /●}"

        wizard::__frame_begin $((inner + 2)) ${frame_h}
        wizard::__rule "${inner}" '╭' '╮'
        wizard::__title_row "${inner}" "Пароль сервера / Server password"
        if is::not_empty "${desc}"; then
            wizard::__hint "${inner}" "${desc}"
        fi
        wizard::__row "${inner}" ""
        wizard::__hint "${inner}" "  Ввод скрыт / Input is hidden"
        wizard::__row "${inner}" ""
        wizard::__row "${inner}" "  Пароль / Password: ${m1}" "33"
        wizard::__row "${inner}" "  Повторите / Repeat: ${m2}" "33"
        wizard::__rule "${inner}" '╰' '╯'
        wizard::__hint "${inner}" "  Enter — следующее поле · Backspace — удалить · q — отмена"
        # курсор на активное поле / cursor to the active field
        if (( field == 1 )); then
            wizard::__goto $((__WIZ_ROW + pass_row)) $((__WIZ_COL + 21 + cur1))
        else
            wizard::__goto $((__WIZ_ROW + pass_row + 1)) $((__WIZ_COL + 22 + cur2))
        fi

        local key
        key="$(wizard::__read_key)"
        case "${key}" in
            q) __wiz_out="q"; return 0 ;;
            enter)
                if (( field == 1 )); then
                    if is::empty "${pass1}"; then
                        # пустой пароль = без пароля / empty = no password
                        __wiz_out=""
                        return 0
                    fi
                    field=2
                    cur2=${#pass2}
                else
                    if [[ "${pass1}" == "${pass2}" ]]; then
                        __wiz_out="${pass1}"
                        return 0
                    fi
                    # не совпали — рамка ошибки, Enter — повторить
                    # mismatch — error frame, Enter — retry
                    wizard::__row "${inner}" "  Пароли не совпали / Passwords do not match" "31"
                    wizard::__row "${inner}" "  Enter — повторить / to retry" "90"
                    IFS= read -rsn1 || true
                    pass1=""; pass2=""
                    cur1=0; cur2=0; field=1
                fi
                ;;
            backspace)
                if (( field == 1 )); then
                    (( cur1 > 0 )) || continue
                    pass1="${pass1:0:$((cur1 - 1))}${pass1:${cur1}}"
                    cur1=$(( cur1 - 1 ))
                else
                    (( cur2 > 0 )) || continue
                    pass2="${pass2:0:$((cur2 - 1))}${pass2:${cur2}}"
                    cur2=$(( cur2 - 1 ))
                fi
                ;;
            left)
                if (( field == 1 )); then
                    (( cur1 > 0 )) && cur1=$(( cur1 - 1 ))
                else
                    (( cur2 > 0 )) && cur2=$(( cur2 - 1 ))
                fi
                ;;
            right)
                if (( field == 1 )); then
                    (( cur1 < ${#pass1} )) && cur1=$(( cur1 + 1 ))
                else
                    (( cur2 < ${#pass2} )) && cur2=$(( cur2 + 1 ))
                fi
                ;;
            up|down|del|esc) : ;;
            *)
                if [[ "${key}" =~ ^[[:print:]]+$ ]] && [[ "${key}" != *[[:space:]]* ]] && [[ "${key}" != *+* ]]; then
                    if (( field == 1 )); then
                        pass1="${pass1:0:${cur1}}${key}${pass1:${cur1}}"
                        cur1=$(( cur1 + 1 ))
                    else
                        pass2="${pass2:0:${cur2}}${key}${pass2:${cur2}}"
                        cur2=$(( cur2 + 1 ))
                    fi
                fi
                ;;
        esac
    done
}

# @private Generate a password / Сгенерировать пароль
# @stdout password / пароль
wizard::gen_pass() {
    if is::command openssl; then
        openssl rand -base64 18 | tr '+/' '_-'
    else
        tr -dc 'A-Za-z0-9_-' < /dev/urandom | head -c 18
        printf '\n'
    fi
}

# @description Framed notice; waits for a key, does not exit.
# @description Рамка-уведомление; ждёт клавишу, не выходит.
# @param $1 Message / Сообщение
# @param $2 [optional] Title (default: "Ошибка / Error") / Заголовок
# @return 0 continue, 1 cancelled (q) / 0 продолжить, 1 отмена (q)
wizard::alert() {
    local -r inner="$(wizard::__box_width)" msg="$1" title="${2:-Ошибка / Error}"
    local -i lines=0
    while IFS= read -r _; do lines=$((lines + 1)); done <<< "${msg}"
    wizard::__frame_begin $((inner + 2)) $((lines + 4))
    wizard::__rule "${inner}" '╭' '╮'
    wizard::__title_row "${inner}" "${title}"
    wizard::__text "${inner}" "${msg}"
    wizard::__rule "${inner}" '╰' '╯'
    wizard::__hint "${inner}" "  Enter — продолжить / continue · q — отмена / cancel"
    case "$(wizard::__read_key)" in
        q) return 1 ;;
        *) return 0 ;;
    esac
}

# @description Framed error; exits with 1.
# @description Рамка-ошибка; выход с кодом 1.
# @param $1 Message / Сообщение
wizard::fail() {
    local -r inner="$(wizard::__box_width)" msg="$1"
    local -i lines=0
    while IFS= read -r _; do lines=$((lines + 1)); done <<< "${msg}"
    wizard::__frame_begin $((inner + 2)) $((lines + 4))
    wizard::__rule "${inner}" '╭' '╮'
    wizard::__title_row "${inner}" "Ошибка / Error"
    wizard::__text "${inner}" "${msg}"
    wizard::__rule "${inner}" '╰' '╯'
    exit 1
}