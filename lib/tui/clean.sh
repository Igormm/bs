#!/usr/bin/env bs
# shellcheck shell=bash
# lib/tui/clean.sh — `bs clean`: paste window and filter over lib/data/textclean
# lib/tui/clean.sh — `bs clean`: окно для вставки и фильтр поверх lib/data/textclean
#
# Two modes / Два режима:
#   filter — `bs clean < file`, `xclip -o | bs clean`, `bs clean file...`:
#            cleaned text to stdout, danger warnings to stderr.
#            фильтр: очищенный текст в stdout, предупреждения danger в stderr.
#   window — `bs clean` in a terminal: paste, toggle rules with 1-9 a-d,
#            Enter copies (OSC 52) and prints the result to stdout.
#            окно: вставить, переключать правила 1-9 a-d, Enter копирует
#            (OSC 52) и печатает результат в stdout.
#
# @depends lib/data/textclean, lib/tui/tui
# @tier lib
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], arithmetic command (( )), array, associative array / needs bash constructs: double-bracket [[ ]], arithmetic command (( )), array, associative array

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_TUI_CLEAN" || return 0

# Dependencies / Зависимости
bs::source_relative "../data/textclean.sh" "tui.sh"

# @global TEXTCLEAN_KEYS — Clean window: hotkey per rule, same order as TEXTCLEAN_RULES (category: constant)
# @global TEXTCLEAN_KEYS — Окно clean: клавиша правила, порядок как в TEXTCLEAN_RULES (категория: constant)
declare -ga TEXTCLEAN_KEYS=(1 2 3 4 5 6 7 8 9 a b c d)

# Window state / Состояние окна
# @global TEXTCLEAN_TUI_RAW — Clean window: pasted text as is (category: state)
# @global TEXTCLEAN_TUI_RAW — Окно clean: вставленный текст как есть (категория: state)
declare -g TEXTCLEAN_TUI_RAW=""
# @global TEXTCLEAN_TUI_OUT — Clean window: cleaned text (category: state)
# @global TEXTCLEAN_TUI_OUT — Окно clean: очищенный текст (категория: state)
declare -g TEXTCLEAN_TUI_OUT=""
# @global TEXTCLEAN_TUI_VIEW — Clean window: shown pane, clean|raw (category: state)
# @global TEXTCLEAN_TUI_VIEW — Окно clean: что показано, clean|raw (категория: state)
declare -g TEXTCLEAN_TUI_VIEW="clean"
# @global TEXTCLEAN_TUI_TOP — Clean window: first shown line (category: state)
# @global TEXTCLEAN_TUI_TOP — Окно clean: первая показанная строка (категория: state)
declare -gi TEXTCLEAN_TUI_TOP=0
# @global TEXTCLEAN_TUI_MSG — Clean window: one-shot status message (category: state)
# @global TEXTCLEAN_TUI_MSG — Окно clean: разовое сообщение статуса (категория: state)
declare -g TEXTCLEAN_TUI_MSG=""
# @global TEXTCLEAN_TUI_CONFIRM — Clean window: 1 = waiting for a second Enter on danger (category: state)
# @global TEXTCLEAN_TUI_CONFIRM — Окно clean: 1 = ждём второй Enter при danger (категория: state)
declare -gi TEXTCLEAN_TUI_CONFIRM=0

# Window / Окно

# @description Re-run the rules over the raw text / Заново прогнать правила над сырым текстом
textclean::tui::update() {
    TEXTCLEAN_TEXT="${TEXTCLEAN_TUI_RAW}"
    textclean::process
    TEXTCLEAN_TUI_OUT="${TEXTCLEAN_TEXT}"
    TEXTCLEAN_TUI_CONFIRM=0
}

# @description Add pasted text: CRLF and CR become LF (a terminal sends Enter as CR)
# @description Добавить вставленный текст: CRLF и CR становятся LF (терминал шлёт Enter как CR)
# @param $1 text / текст
textclean::tui::add() {
    local s="${1-}"
    s="${s//$'\r\n'/$'\n'}"
    s="${s//$'\r'/$'\n'}"
    TEXTCLEAN_TUI_RAW+="${s}"
    textclean::tui::update
    TEXTCLEAN_TUI_MSG="+${#s} chars / символов"
}

# @private Make a line safe to draw: tabs, ESC and control characters shown visibly
# @private Сделать строку безопасной для вывода: табы, ESC и управляющие символы видимыми
textclean::tui::__visible() {
    local s="$1"
    s="${s//$'\t'/    }"
    s="${s//$'\e'/^[}"
    s="${s//[$'\x01'-$'\x1f'$'\x7f']/?}"
    REPLY="${s}"
}

# @description Draw the window into the TUI buffer / Нарисовать окно в буфер TUI
textclean::tui::draw() {
    local -i w="${TUI_COLS}" h="${TUI_LINES}" pw lw bh nd i row shown
    local -a lines=() danger=()
    local text st line key r mark n reason
    pw=$(( w >= 90 ? 40 : (w >= 60 ? 30 : 0) ))
    lw=$(( w - pw ))
    danger=("${TEXTCLEAN_DANGER[@]}")
    nd=${#danger[@]}
    (( nd > 4 )) && nd=4
    bh=$(( h - 2 - (nd > 0 ? nd + 1 : 0) ))
    (( bh < 3 )) && bh=3

    tui::buf::clear
    tui::titlebar " bs clean — paste text here / вставьте текст " "$(tui::style bold bg:blue white)"

    # text pane / панель текста
    if [[ "${TEXTCLEAN_TUI_VIEW}" == raw ]]; then text="${TEXTCLEAN_TUI_RAW}"; else text="${TEXTCLEAN_TUI_OUT}"; fi
    [[ -n "${text}" ]] && mapfile -t lines <<< "${text}"
    n=${#lines[@]}
    (( TEXTCLEAN_TUI_TOP > n - (bh - 2) )) && TEXTCLEAN_TUI_TOP=$(( n - (bh - 2) ))
    (( TEXTCLEAN_TUI_TOP < 0 )) && TEXTCLEAN_TUI_TOP=0
    tui::box 2 1 "${lw}" "${bh}" "${TEXTCLEAN_TUI_VIEW} · ${n} lines" "$(tui::style cyan)"
    if (( n == 0 )); then
        tui::put 4 3 "Paste with Ctrl+Shift+V, Shift+Insert or the mouse." "$(tui::style dim)"
        tui::put 5 3 "Вставьте Ctrl+Shift+V, Shift+Insert или мышью." "$(tui::style dim)"
    fi
    shown=0
    for (( i = TEXTCLEAN_TUI_TOP; i < n && shown < bh - 2; i++ )); do
        textclean::tui::__visible "${lines[i]}"
        tui::put $(( 3 + shown )) 2 "${REPLY:0:$(( lw - 2 ))}"
        shown=$(( shown + 1 ))
    done

    # rules pane / панель правил
    if (( pw > 0 )); then
        tui::box 2 $(( lw + 1 )) "${pw}" "${bh}" "rules / правила" "$(tui::style cyan)"
        row=3
        for i in "${!TEXTCLEAN_RULES[@]}"; do
            (( row >= 2 + bh - 1 )) && break
            r="${TEXTCLEAN_RULES[i]}"
            key="${TEXTCLEAN_KEYS[i]}"
            if textclean::is_enabled "${r}"; then
                mark="[x]"; st="$(tui::style green)"
            else
                mark="[ ]"; st="$(tui::style gray)"
            fi
            tui::put "${row}" $(( lw + 3 )) "${key} ${mark} ${r}" "${st}"
            row=$(( row + 1 ))
        done
        if (( row + 1 < 2 + bh - 1 )); then
            tui::put $(( row + 1 )) $(( lw + 3 )) "s  save as default" "$(tui::style dim)"
        fi
    fi

    # danger lines / строки danger
    if (( nd > 0 )); then
        row=$(( 2 + bh ))
        tui::put "${row}" 1 " ⚠ dangerous commands / опасные команды (${#danger[@]}):" "$(tui::style bold red)"
        for (( i = 0; i < nd; i++ )); do
            line="${danger[i]}"
            n="${line%%$'\t'*}"; line="${line#*$'\t'}"
            reason="${line%%$'\t'*}"; line="${line#*$'\t'}"
            textclean::tui::__visible "  line ${n}: ${reason}: ${line}"
            tui::put $(( row + 1 + i )) 1 "${REPLY:0:${w}}" "$(tui::style red)"
        done
    fi

    if [[ -n "${TEXTCLEAN_TUI_MSG}" ]]; then
        tui::statusbar " ${TEXTCLEAN_TUI_MSG}" "$(tui::style bold bg:yellow black)"
    else
        tui::statusbar " Enter copy+print · Tab raw/clean · ↑↓ PgUp PgDn scroll · Ctrl+U clear · 1-9 a-d rules · Esc quit" \
            "$(tui::style reverse)"
    fi
    tui::render
}

# @private Read the rest of a paste that came without bracketed-paste markers
#   (a burst of keys) and return it in REPLY.
# @private Дочитать вставку, пришедшую без маркеров bracketed paste (пачка
#   клавиш), и вернуть её в REPLY.
textclean::tui::__burst() {
    local buf="$1" more
    while read -t 0 2>/dev/null; do
        more=""
        IFS= read -r -s -d '' -n 65536 -t 0.05 more || true
        [[ -z "${more}" ]] && break
        buf+="${more}"
    done
    REPLY="${buf}"
}

# @description Handle one key; 0 = keep going, 10 = accept, 11 = cancel
# @description Обработать клавишу; 0 — дальше, 10 — принять, 11 — отмена
textclean::tui::key() {
    local -r k="${TUI_KEY}"
    local i
    TEXTCLEAN_TUI_MSG=""
    case "${k}" in
        PASTE) textclean::tui::add "${TUI_PASTE}"; return 0 ;;
        ENTER)
            if read -t 0 2>/dev/null; then
                textclean::tui::__burst $'\n'
                textclean::tui::add "${REPLY}"
                return 0
            fi
            if [[ -z "${TEXTCLEAN_TUI_OUT}" ]]; then
                TEXTCLEAN_TUI_MSG="nothing to copy yet / пока нечего копировать"
                return 0
            fi
            if (( ${#TEXTCLEAN_DANGER[@]} > 0 && TEXTCLEAN_TUI_CONFIRM == 0 )); then
                TEXTCLEAN_TUI_CONFIRM=1
                TEXTCLEAN_TUI_MSG="dangerous commands: Enter again to copy anyway, Esc back / опасные команды: Enter ещё раз — всё равно скопировать"
                return 0
            fi
            return 10 ;;
        ESC)
            if (( TEXTCLEAN_TUI_CONFIRM == 1 )); then TEXTCLEAN_TUI_CONFIRM=0; return 0; fi
            return 11 ;;
        TAB|BTAB)
            if [[ "${TEXTCLEAN_TUI_VIEW}" == clean ]]; then TEXTCLEAN_TUI_VIEW=raw; else TEXTCLEAN_TUI_VIEW=clean; fi
            TEXTCLEAN_TUI_TOP=0 ;;
        UP)   TEXTCLEAN_TUI_TOP=$(( TEXTCLEAN_TUI_TOP - 1 )) ;;
        DOWN) TEXTCLEAN_TUI_TOP=$(( TEXTCLEAN_TUI_TOP + 1 )) ;;
        PGUP) TEXTCLEAN_TUI_TOP=$(( TEXTCLEAN_TUI_TOP - TUI_LINES / 2 )) ;;
        PGDN) TEXTCLEAN_TUI_TOP=$(( TEXTCLEAN_TUI_TOP + TUI_LINES / 2 )) ;;
        HOME) TEXTCLEAN_TUI_TOP=0 ;;
        END)  TEXTCLEAN_TUI_TOP=999999 ;;
        $'\x15')
            TEXTCLEAN_TUI_RAW=""
            textclean::tui::update
            TEXTCLEAN_TUI_MSG="cleared / очищено" ;;
        s|S)
            if read -t 0 2>/dev/null; then textclean::tui::__burst "${k}"; textclean::tui::add "${REPLY}"; return 0; fi
            if textclean::config::save; then
                TEXTCLEAN_TUI_MSG="saved / сохранено: ${REPLY}"
            else
                TEXTCLEAN_TUI_MSG="cannot write / не записать: ${REPLY}"
            fi ;;
        *)
            if read -t 0 2>/dev/null && [[ -n "${TUI_KEY_CHAR}" ]]; then
                textclean::tui::__burst "${TUI_KEY_CHAR}"
                textclean::tui::add "${REPLY}"
                return 0
            fi
            for i in "${!TEXTCLEAN_KEYS[@]}"; do
                [[ "${k}" == "${TEXTCLEAN_KEYS[i]}" ]] || continue
                textclean::toggle "${TEXTCLEAN_RULES[i]}"
                textclean::tui::update
                if textclean::is_enabled "${TEXTCLEAN_RULES[i]}"; then
                    TEXTCLEAN_TUI_MSG="${TEXTCLEAN_RULES[i]}: on — $(textclean::describe "${TEXTCLEAN_RULES[i]}")"
                else
                    TEXTCLEAN_TUI_MSG="${TEXTCLEAN_RULES[i]}: off"
                fi
                return 0
            done ;;
    esac
    return 0
}

# @description Run the paste window on /dev/tty. The cleaned text is left in
#   TEXTCLEAN_TUI_OUT. Draws only to the terminal, so stdout stays free for the result.
# @description Запустить окно вставки на /dev/tty. Очищенный текст остаётся в
#   TEXTCLEAN_TUI_OUT. Рисует только в терминал, stdout свободен для результата.
# @param $1 [initial text] / [начальный текст]
# @return 0 accepted, 1 cancelled, LIB_ERROR_DEPENDENCY without a terminal /
#   0 — принято, 1 — отмена, LIB_ERROR_DEPENDENCY без терминала
textclean::tui::run() {
    { : < /dev/tty > /dev/tty; } 2>/dev/null || return "${LIB_ERROR_DEPENDENCY}"
    local -i rc=0 out_fd in_fd
    TEXTCLEAN_TUI_RAW="${1-}"
    TEXTCLEAN_TUI_VIEW="clean"
    TEXTCLEAN_TUI_TOP=0
    TEXTCLEAN_TUI_MSG=""
    textclean::tui::update
    exec {out_fd}>&1 {in_fd}<&0 > /dev/tty < /dev/tty
    tui::init
    tui::mouse_off
    tui::paste_on
    local -i stop=0
    trap 'stop=1' INT
    while :; do
        tui::handle_resize
        textclean::tui::draw
        tui::key_read
        (( stop )) && { rc=11; break; }
        rc=0
        textclean::tui::key || rc=$?
        (( rc == 10 || rc == 11 )) && break
    done
    trap - INT
    tui::paste_off
    tui::quit
    exec 1>&"${out_fd}" 0<&"${in_fd}" {out_fd}>&- {in_fd}<&-
    (( rc == 10 ))
}

# CLI / Командная строка

# @description Usage text / Справка
textclean::cli::usage() {
    local r i=0
    cat <<'EOF'
Usage: bs clean [options] [file...]
       bs clean [options] < file

Clean text pasted from web pages and chats. Without input on stdin and
without files it opens a window: paste, toggle rules, Enter copies the
result to the clipboard (OSC 52) and prints it to stdout.
Очистка текста из веба и чатов. Без stdin и файлов открывает окно:
вставьте текст, переключайте правила, Enter копирует результат в буфер
обмена (OSC 52) и печатает его в stdout.

Rules / правила:
  -r, --rules LIST    only these rules (comma separated) / только эти
  --RULE, --no-RULE   switch one rule on/off, e.g. --unwrap --no-typography
  --all, --none       every rule on / off
  -l, --list          rules, state and descriptions / список правил

Options / опции:
  -w, --window        always open the window (stdin text is pre-filled)
  -f, --filter        never open the window
  -p, --paste         read the system clipboard as input (wl-paste, xclip,
                      xsel, pbpaste, termux-clipboard-get, powershell.exe)
  -c, --copy          also copy the result in filter mode (OSC 52)
  --no-copy           do not copy in the window
  --tab-width N       tab stop for --tabs (default 4)
  --unwrap-min N      shortest line --unwrap joins (default 50)
  --guillemets        typography also turns «» into "
  --noise RE          one more noise line pattern (ERE over the whole line)
  --no-config         ignore ~/.config/bs/clean/{rules,noise}
  --strict            exit 3 when dangerous commands are found
  -q, --quiet         no danger warnings on stderr
  -h, --help          this help

Rules in run order / правила по порядку:
EOF
    textclean::__ensure
    for r in "${TEXTCLEAN_RULES[@]}"; do
        printf '  %s %-11s %-3s %s\n' "${TEXTCLEAN_KEYS[i]}" "${r}" \
            "$( (( TEXTCLEAN_DEFAULTS[${r}] == 1 )) && printf on || printf off)" "${TEXTCLEAN_DESC_EN[${r}]}"
        i=$(( i + 1 ))
    done
    cat <<'EOF'

Examples / примеры:
  bs clean                          # window / окно
  xclip -o | bs clean > clean.txt   # filter / фильтр
  bs clean --rules ansi,trailing < log.txt
  bs clean --unwrap --no-noise --copy < article.txt
EOF
}

# @description Print rules with their current state / Вывести правила с текущим состоянием
textclean::cli::list() {
    local r
    textclean::__ensure
    for r in "${TEXTCLEAN_RULES[@]}"; do
        printf '%-11s %-3s %s / %s\n' "${r}" \
            "$(textclean::is_enabled "${r}" && printf on || printf off)" \
            "${TEXTCLEAN_DESC_EN[${r}]}" "${TEXTCLEAN_DESC_RU[${r}]}"
    done
}

# @description Print danger findings to stderr / Вывести находки danger в stderr
textclean::cli::warn() {
    local f n reason line
    for f in "${TEXTCLEAN_DANGER[@]}"; do
        n="${f%%$'\t'*}"; f="${f#*$'\t'}"
        reason="${f%%$'\t'*}"; line="${f#*$'\t'}"
        printf 'bs clean: warning: line %s: %s: %s\n' "${n}" "${reason}" "${line}" >&2
    done
}

# @description `bs clean` entry point / Точка входа `bs clean`
# @param $@ CLI arguments / аргументы командной строки
# @return 0 ok, 1 cancelled window, 2 usage error, 3 danger with --strict
# shellcheck disable=SC2034 # TEXTCLEAN_* settings are read by lib/data/textclean
textclean::cli::main() {
    local mode=auto copy="" quiet=0 strict=0 use_config=1 list=0 from_clip=0 arg name
    local -a files=() actions=()
    while (( $# > 0 )); do
        arg="$1"; shift
        case "${arg}" in
            -h|--help) textclean::cli::usage; return 0 ;;
            -l|--list) list=1 ;;
            -w|--window) mode=window ;;
            -f|--filter) mode=filter ;;
            -c|--copy) copy=1 ;;
            -p|--paste) from_clip=1 ;;
            --no-copy) copy=0 ;;
            -q|--quiet) quiet=1 ;;
            --strict) strict=1 ;;
            --no-config) use_config=0 ;;
            --guillemets) TEXTCLEAN_GUILLEMETS=1 ;;
            --all) actions+=("all") ;;
            --none) actions+=("none") ;;
            -r|--rules|--rule|--tab-width|--unwrap-min|--noise)
                (( $# > 0 )) || { printf 'bs clean: %s needs a value\n' "${arg}" >&2; return 2; }
                case "${arg}" in
                    -r|--rules|--rule) actions+=("only:$1") ;;
                    --tab-width)
                        [[ "$1" =~ ^[1-9][0-9]?$ ]] || { printf 'bs clean: --tab-width: a number 1-99\n' >&2; return 2; }
                        TEXTCLEAN_TAB_WIDTH="$1" ;;
                    --unwrap-min)
                        [[ "$1" =~ ^[0-9]{1,4}$ ]] || { printf 'bs clean: --unwrap-min: a number\n' >&2; return 2; }
                        TEXTCLEAN_UNWRAP_MIN="$1" ;;
                    --noise) TEXTCLEAN_NOISE+=("$1") ;;
                esac
                shift ;;
            --rules=*|--rule=*) actions+=("only:${arg#*=}") ;;
            --tab-width=*|--unwrap-min=*|--noise=*) set -- "${arg%%=*}" "${arg#*=}" "$@" ;;
            --no-*)
                name="${arg#--no-}"
                textclean::valid "${name}" || { printf 'bs clean: unknown option: %s\n' "${arg}" >&2; return 2; }
                actions+=("off:${name}") ;;
            --) files+=("$@"); break ;;
            --*)
                name="${arg#--}"
                textclean::valid "${name}" || { printf 'bs clean: unknown option: %s (bs clean --help)\n' "${arg}" >&2; return 2; }
                actions+=("on:${name}") ;;
            -) files+=("-") ;;
            -*) printf 'bs clean: unknown option: %s (bs clean --help)\n' "${arg}" >&2; return 2 ;;
            *) files+=("${arg}") ;;
        esac
    done

    # defaults → config → command line / умолчания → файл настроек → командная строка
    textclean::reset
    if (( use_config )); then
        textclean::config::load || printf 'bs clean: warning: bad line in %s/rules\n' "${TEXTCLEAN_CONFIG_DIR}" >&2
    fi
    local a
    for a in "${actions[@]}"; do
        case "${a}" in
            all)   textclean::set_all 1 ;;
            none)  textclean::set_all 0 ;;
            on:*)  textclean::enable "${a#on:}" ;;
            off:*) textclean::disable "${a#off:}" ;;
            only:*)
                textclean::only "${a#only:}" || {
                    local IFS=' '
                    printf 'bs clean: unknown rule in --rules: %s (known: %s)\n' "${a#only:}" "${TEXTCLEAN_RULES[*]}" >&2
                    return 2
                } ;;
        esac
    done
    if (( list )); then textclean::cli::list; return 0; fi

    # input / ввод
    local input="" f chunk have_input=0
    if (( from_clip )); then
        local prc=0
        textclean::paste || prc=$?
        if (( prc == LIB_ERROR_DEPENDENCY_MISSING )); then
            printf 'bs clean: --paste: no clipboard reader found (%s).\n' "$(textclean::paste::tools)" >&2
            printf '  Paste into the window instead: bs clean   or pipe the text in: bs clean < file\n' >&2
            printf '  Вставьте текст в окно: bs clean   или подайте его на вход: bs clean < file\n' >&2
            return 2
        elif (( prc != 0 )); then
            printf 'bs clean: --paste: cannot read the clipboard with: %s (no display? try the window: bs clean)\n' "${TEXTCLEAN_PASTE_TOOL}" >&2
            return 2
        fi
        input="${REPLY}"
        have_input=1
    elif (( ${#files[@]} > 0 )); then
        for f in "${files[@]}"; do
            if [[ "${f}" == - ]]; then
                IFS= read -r -d '' chunk || true
            else
                [[ -r "${f}" ]] || { printf 'bs clean: cannot read: %s\n' "${f}" >&2; return 2; }
                IFS= read -r -d '' chunk < "${f}" || true
            fi
            input+="${chunk}"
        done
        have_input=1
    elif [[ ! -t 0 ]]; then
        IFS= read -r -d '' input || true
        have_input=1
    fi
    if [[ "${mode}" == auto ]]; then
        if (( have_input )); then mode=filter; else mode=window; fi
    fi

    if [[ "${mode}" == window ]]; then
        local wrc=0
        textclean::tui::run "${input%$'\n'}" || wrc=$?
        if (( wrc == LIB_ERROR_DEPENDENCY )); then
            printf 'bs clean: no terminal for the window; use: bs clean < file\n' >&2
            return 2
        fi
        (( wrc == 0 )) || return 1
        [[ "${copy}" == 0 ]] || textclean::copy "${TEXTCLEAN_TUI_OUT}" \
            || printf 'bs clean: warning: cannot copy: no terminal\n' >&2
        [[ -n "${TEXTCLEAN_TUI_OUT}" ]] && printf '%s\n' "${TEXTCLEAN_TUI_OUT}"
        (( quiet )) || textclean::cli::warn
        (( strict && ${#TEXTCLEAN_DANGER[@]} > 0 )) && return 3
        return 0
    fi

    TEXTCLEAN_TEXT="${input%$'\n'}"
    textclean::process
    [[ -n "${TEXTCLEAN_TEXT}" ]] && printf '%s\n' "${TEXTCLEAN_TEXT}"
    if [[ "${copy}" == 1 ]]; then
        textclean::copy "${TEXTCLEAN_TEXT}" || printf 'bs clean: warning: cannot copy: no terminal\n' >&2
    fi
    (( quiet )) || textclean::cli::warn
    (( strict && ${#TEXTCLEAN_DANGER[@]} > 0 )) && return 3
    return 0
}
