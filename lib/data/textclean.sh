#!/usr/bin/env bs
# shellcheck shell=bash
# lib/data/textclean.sh — clean text pasted from web pages and chats, rule by rule
# lib/data/textclean.sh — очистка текста, вставленного из веба и чатов, по правилам
#
# Every cleaning step is a separate rule that can be switched on or off.
# Каждый шаг очистки — отдельное правило, которое можно включить или выключить.
#
# Rules run in a fixed order over one buffer, TEXTCLEAN_TEXT:
# Правила работают в фиксированном порядке над одним буфером TEXTCLEAN_TEXT:
#   ansi tags entities invisible markdown typography tabs noise trailing
#   dedent unwrap blank   (+ danger: a scan, it never changes the text /
#   сканер, текст не меняет)
#
# Usage / Использование:
#   load "lib/data/textclean"
#   textclean::reset                    # defaults / значения по умолчанию
#   textclean::disable typography
#   textclean::enable unwrap
#   printf '%s' "${text}" | textclean::filter
#   textclean::danger::scan             # fills TEXTCLEAN_DANGER
#
# The rules are byte-exact (UTF-8 literals are written as \x bytes), so they
# behave the same under the C and UTF-8 locales.
# Правила работают по байтам (UTF-8 записан как \x-байты), поэтому ведут себя
# одинаково в локалях C и UTF-8.
#
# @depends core/lang, core/const, core/deps
# @optdeps base64, openssl, wl-paste, xclip, xsel, pbpaste, termux-clipboard-get, powershell.exe
# @tier lib
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], arithmetic command (( )), array, associative array, regex match / needs bash constructs: double-bracket [[ ]], arithmetic command (( )), array, associative array, regex match

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_DATA_TEXTCLEAN" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/lang.sh" "../../core/const.sh" "../../core/deps.sh"

# Registry / Реестр правил

# @global TEXTCLEAN_RULES — Textclean: rule names in run order (category: constant)
# @global TEXTCLEAN_RULES — Textclean: имена правил в порядке выполнения (категория: constant)
declare -ga TEXTCLEAN_RULES=(
    ansi tags entities invisible markdown typography tabs noise
    trailing dedent unwrap blank danger
)
# @global TEXTCLEAN_DEFAULTS — Textclean: rule=0/1 default state (category: constant)
# @global TEXTCLEAN_DEFAULTS — Textclean: правило=0/1 по умолчанию (категория: constant)
declare -gA TEXTCLEAN_DEFAULTS=(
    [ansi]=1 [tags]=0 [entities]=1 [invisible]=1 [markdown]=0
    [typography]=1 [tabs]=0 [noise]=1 [trailing]=1 [dedent]=0
    [unwrap]=0 [blank]=1 [danger]=1
)
# @global TEXTCLEAN_DESC_EN — Textclean: rule descriptions, English (category: constant)
# @global TEXTCLEAN_DESC_EN — Textclean: описания правил, английский (категория: constant)
declare -gA TEXTCLEAN_DESC_EN=(
    [ansi]="ANSI escape codes and control characters, CRLF to LF"
    [tags]="HTML tags (<br>, </p> become line breaks)"
    [entities]="HTML entities: &nbsp; &amp; &#39; &#x2014;"
    [invisible]="zero-width, BOM, bidi marks; NBSP and odd spaces to space"
    [markdown]="Markdown escapes (\\_ \\*) and stray code fences"
    [typography]="smart quotes, dashes, ellipsis, bullets to ASCII"
    [tabs]="expand tabs to spaces"
    [noise]="UI noise lines: Copy, Click to expand, Show more"
    [trailing]="trailing spaces at line ends"
    [dedent]="remove common leading indentation"
    [unwrap]="join hard-wrapped paragraphs, keep lists and code"
    [blank]="collapse blank lines, trim them at both ends"
    [danger]="warn about dangerous shell commands (no changes)"
)
# @global TEXTCLEAN_DESC_RU — Textclean: rule descriptions, Russian (category: constant)
# @global TEXTCLEAN_DESC_RU — Textclean: описания правил, русский (категория: constant)
declare -gA TEXTCLEAN_DESC_RU=(
    [ansi]="ANSI-коды и управляющие символы, CRLF в LF"
    [tags]="HTML-теги (<br>, </p> становятся переводом строки)"
    [entities]="HTML-сущности: &nbsp; &amp; &#39; &#x2014;"
    [invisible]="zero-width, BOM, bidi-метки; NBSP и редкие пробелы в пробел"
    [markdown]="экранирование Markdown (\\_ \\*) и лишние ограждения кода"
    [typography]="кавычки-лапки, тире, многоточие, маркеры в ASCII"
    [tabs]="табуляция в пробелы"
    [noise]="строки интерфейса: Copy, Click to expand, Показать ещё"
    [trailing]="пробелы в конце строк"
    [dedent]="убрать общий отступ слева"
    [unwrap]="склеить разорванные абзацы, не трогая списки и код"
    [blank]="схлопнуть пустые строки, убрать их по краям"
    [danger]="предупредить об опасных командах (текст не меняет)"
)

# State / Состояние

# @global TEXTCLEAN_ON — Textclean: rule=0/1 current state (category: state)
# @global TEXTCLEAN_ON — Textclean: правило=0/1 текущее состояние (категория: state)
declare -gA TEXTCLEAN_ON=()
# @global TEXTCLEAN_TEXT — Textclean: the buffer the rules work on, no final newline (category: state)
# @global TEXTCLEAN_TEXT — Textclean: буфер правил, без финального перевода строки (категория: state)
declare -g TEXTCLEAN_TEXT=""
# @global TEXTCLEAN_DANGER — Textclean: danger findings "line<TAB>reason<TAB>text" (category: state)
# @global TEXTCLEAN_DANGER — Textclean: находки danger "строка<TAB>причина<TAB>текст" (категория: state)
declare -ga TEXTCLEAN_DANGER=()

# Settings / Настройки

# @global TEXTCLEAN_TAB_WIDTH — Textclean: tab stop for the tabs rule (category: hook)
# @global TEXTCLEAN_TAB_WIDTH — Textclean: шаг табуляции правила tabs (категория: hook)
declare -g TEXTCLEAN_TAB_WIDTH="${TEXTCLEAN_TAB_WIDTH:-4}"
# @global TEXTCLEAN_UNWRAP_MIN — Textclean: a line shorter than this ends a paragraph (category: hook)
# @global TEXTCLEAN_UNWRAP_MIN — Textclean: строка короче этого завершает абзац (категория: hook)
declare -g TEXTCLEAN_UNWRAP_MIN="${TEXTCLEAN_UNWRAP_MIN:-50}"
# @global TEXTCLEAN_GUILLEMETS — Textclean: 1 = typography also turns «» into " (category: hook)
# @global TEXTCLEAN_GUILLEMETS — Textclean: 1 = typography меняет и «» на " (категория: hook)
declare -g TEXTCLEAN_GUILLEMETS="${TEXTCLEAN_GUILLEMETS:-0}"
# @global TEXTCLEAN_CONFIG_DIR — Textclean: config directory (rules, noise) (category: hook)
# @global TEXTCLEAN_CONFIG_DIR — Textclean: каталог настроек (rules, noise) (категория: hook)
declare -g TEXTCLEAN_CONFIG_DIR="${TEXTCLEAN_CONFIG_DIR:-${XDG_CONFIG_HOME:-${HOME:-/tmp}/.config}/bs/clean}"
# @global TEXTCLEAN_NOISE — Textclean: noise line patterns, ERE over the trimmed line (category: hook)
# @global TEXTCLEAN_NOISE — Textclean: шаблоны шумовых строк, ERE по обрезанной строке (категория: hook)
declare -ga TEXTCLEAN_NOISE=(
    '[Cc]opy( code)?' '[Cc]opy to clipboard' '[Cc]opied!?' '[Cc]ode copied!?'
    '[Cc]lick to (expand|collapse|copy|show)' '[Ss]how (more|less|all)'
    '[Rr]ead more' '[Ss]ee more' '[Ee]xpand( all)?' '[Cc]ollapse( all)?'
    '[Ss]kip to content' '[Tt]ry it( yourself)?' '[Rr]un code'
    '[Сс]копировать( код)?' '[Кк]опировать' '[Сс]копировано!?'
    '[Рр]азвернуть' '[Сс]вернуть' '[Пп]оказать (ещё|еще|больше|полностью|все|всё)'
    '[Чч]итать (далее|дальше|полностью)'
)
# @global TEXTCLEAN_LANG_LABELS — Textclean: code-block language labels dropped before a noise line (category: constant)
# @global TEXTCLEAN_LANG_LABELS — Textclean: метки языка блока кода, удаляемые перед шумовой строкой (категория: constant)
declare -g TEXTCLEAN_LANG_LABELS=" bash sh shell zsh fish console terminal text plaintext python py javascript js typescript ts json yaml yml toml ini sql go rust c cpp c++ csharp java kotlin ruby php html css xml diff powershell ps1 dockerfile makefile lua perl nginx "

# Rule switches / Переключение правил

# @description Reset every rule to its default state / Сбросить правила к умолчаниям
textclean::reset() {
    local r
    TEXTCLEAN_ON=()
    for r in "${TEXTCLEAN_RULES[@]}"; do TEXTCLEAN_ON[${r}]="${TEXTCLEAN_DEFAULTS[${r}]}"; done
}

# @description List rule names in run order / Перечислить правила по порядку
# @stdout names one per line / имена по одному в строке
textclean::rules() {
    printf '%s\n' "${TEXTCLEAN_RULES[@]}"
}

# @description Check a rule name / Проверить имя правила
# @param $1 rule / правило
# @return E_SUCCESS or LIB_ERROR_INVALID_INPUT
textclean::valid() {
    [[ -n "${1-}" && -n "${TEXTCLEAN_DEFAULTS[${1}]+x}" ]] && return "${E_SUCCESS}"
    return "${LIB_ERROR_INVALID_INPUT}"
}

# @description Describe a rule / Описание правила
# @param $1 rule, $2 [en|ru] (default en) / правило, язык
# @stdout description / описание
textclean::describe() {
    local -r r="${1-}" lang="${2:-en}"
    textclean::valid "${r}" || return "${LIB_ERROR_INVALID_INPUT}"
    if [[ "${lang}" == ru ]]; then
        printf '%s\n' "${TEXTCLEAN_DESC_RU[${r}]}"
    else
        printf '%s\n' "${TEXTCLEAN_DESC_EN[${r}]}"
    fi
}

# @private Make sure TEXTCLEAN_ON is filled / Заполнить TEXTCLEAN_ON при первом обращении
textclean::__ensure() {
    (( ${#TEXTCLEAN_ON[@]} > 0 )) || textclean::reset
}

# @description Switch rules on / Включить правила
# @param $@ rule names / имена правил
# @return LIB_ERROR_INVALID_INPUT on an unknown name (nothing changes) / при неизвестном имени
textclean::enable() {
    textclean::__ensure
    local r
    for r in "$@"; do textclean::valid "${r}" || return "${LIB_ERROR_INVALID_INPUT}"; done
    for r in "$@"; do TEXTCLEAN_ON[${r}]=1; done
}

# @description Switch rules off / Выключить правила
# @param $@ rule names / имена правил
textclean::disable() {
    textclean::__ensure
    local r
    for r in "$@"; do textclean::valid "${r}" || return "${LIB_ERROR_INVALID_INPUT}"; done
    for r in "$@"; do TEXTCLEAN_ON[${r}]=0; done
}

# @description Flip a rule / Переключить правило
# @param $1 rule / правило
textclean::toggle() {
    textclean::__ensure
    textclean::valid "${1-}" || return "${LIB_ERROR_INVALID_INPUT}"
    if (( TEXTCLEAN_ON[${1}] == 1 )); then TEXTCLEAN_ON[${1}]=0; else TEXTCLEAN_ON[${1}]=1; fi
}

# @description Is a rule on? / Включено ли правило?
# @param $1 rule / правило
# @return 0 on, 1 off or unknown / 0 — включено, 1 — нет
textclean::is_enabled() {
    textclean::__ensure
    textclean::valid "${1-}" || return 1
    (( TEXTCLEAN_ON[${1}] == 1 ))
}

# @description Switch all rules on or off / Включить или выключить все правила
# @param $1 0|1
textclean::set_all() {
    local -r v="${1:?0 or 1 required}"
    local r
    for r in "${TEXTCLEAN_RULES[@]}"; do TEXTCLEAN_ON[${r}]="${v}"; done
}

# @description Keep only the listed rules on (comma or space separated)
# @description Оставить включёнными только перечисленные правила (через запятую или пробел)
# @param $@ rule lists / списки правил
textclean::only() {
    local -a list=() parts=()
    local item
    for item in "$@"; do
        IFS=$' ,\t\n' read -r -a parts <<< "${item}"
        list+=("${parts[@]}")
    done
    for item in "${list[@]}"; do textclean::valid "${item}" || return "${LIB_ERROR_INVALID_INPUT}"; done
    textclean::set_all 0
    for item in "${list[@]}"; do TEXTCLEAN_ON[${item}]=1; done
}

# @description Enabled rules, comma separated / Включённые правила через запятую
# @stdout list / список
textclean::enabled() {
    textclean::__ensure
    local r out=""
    for r in "${TEXTCLEAN_RULES[@]}"; do
        (( TEXTCLEAN_ON[${r}] == 1 )) || continue
        out+="${out:+,}${r}"
    done
    printf '%s\n' "${out}"
}

# Config / Настройки из файлов

# @description Load ${TEXTCLEAN_CONFIG_DIR}/rules and /noise when they exist.
#   rules: one "name=on|off" per line; noise: one ERE per line, added to the
#   defaults. "#" starts a comment.
# @description Загрузить ${TEXTCLEAN_CONFIG_DIR}/rules и /noise, если они есть.
#   rules: строки "имя=on|off"; noise: по одному ERE в строке, добавляются к
#   стандартным. "#" — комментарий.
# @return LIB_ERROR_INVALID_INPUT on a bad line in rules (the rest is applied) /
#   при ошибочной строке в rules (остальное применяется)
textclean::config::load() {
    textclean::__ensure
    local -r dir="${TEXTCLEAN_CONFIG_DIR}"
    local line name value rc="${E_SUCCESS}"
    if [[ -r "${dir}/rules" ]]; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            line="${line%%#*}"
            line="${line//[[:space:]]/}"
            [[ -z "${line}" ]] && continue
            name="${line%%=*}"
            value="${line#*=}"
            if ! textclean::valid "${name}" || [[ "${line}" != *=* ]]; then
                rc="${LIB_ERROR_INVALID_INPUT}"
                continue
            fi
            case "${value}" in
                on|1|yes|true)   TEXTCLEAN_ON[${name}]=1 ;;
                off|0|no|false)  TEXTCLEAN_ON[${name}]=0 ;;
                *) rc="${LIB_ERROR_INVALID_INPUT}" ;;
            esac
        done < "${dir}/rules"
    fi
    if [[ -r "${dir}/noise" ]]; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            [[ "${line}" =~ ^[[:space:]]*(#|$) ]] && continue
            TEXTCLEAN_NOISE+=("${line}")
        done < "${dir}/noise"
    fi
    return "${rc}"
}

# @description Save the current rule states to ${TEXTCLEAN_CONFIG_DIR}/rules
# @description Сохранить текущие состояния правил в ${TEXTCLEAN_CONFIG_DIR}/rules
# @stdout nothing; the path is in REPLY / ничего; путь в REPLY
# @return LIB_ERROR_FILE_OPERATION when the file cannot be written / если файл не записать
textclean::config::save() {
    textclean::__ensure
    local -r dir="${TEXTCLEAN_CONFIG_DIR}"
    local r body="# bs clean: rule=on|off (written by bs clean)"$'\n'
    for r in "${TEXTCLEAN_RULES[@]}"; do
        if (( TEXTCLEAN_ON[${r}] == 1 )); then body+="${r}=on"$'\n'; else body+="${r}=off"$'\n'; fi
    done
    REPLY="${dir}/rules"
    { mkdir -p "${dir}" && printf '%s' "${body}" > "${dir}/rules"; } 2>/dev/null \
        || return "${LIB_ERROR_FILE_OPERATION}"
}

# Helpers / Вспомогательные

# @private Split TEXTCLEAN_TEXT into the array named by $1
# @private Разбить TEXTCLEAN_TEXT в массив с именем $1
textclean::__lines() {
    local -n __tc_out="$1"
    __tc_out=()
    [[ -z "${TEXTCLEAN_TEXT}" ]] && return 0
    mapfile -t __tc_out <<< "${TEXTCLEAN_TEXT}"
}

# @private Join the array named by $1 back into TEXTCLEAN_TEXT
# @private Собрать массив с именем $1 обратно в TEXTCLEAN_TEXT
textclean::__join() {
    local -n __tc_in="$1"
    local IFS=$'\n'
    TEXTCLEAN_TEXT="${__tc_in[*]}"
}

# @private Encode a code point as UTF-8 into REPLY; 1 if it is not a valid scalar value
# @private Закодировать кодовую точку в UTF-8 в REPLY; 1, если она недопустима
textclean::__utf8() {
    local -i c="$1"
    local f
    REPLY=""
    (( c <= 0 || c > 0x10FFFF || (c >= 0xD800 && c <= 0xDFFF) )) && return 1
    if (( c < 0x80 )); then
        printf -v f '\\x%02x' "${c}"
    elif (( c < 0x800 )); then
        printf -v f '\\x%02x\\x%02x' $(( 0xC0 | c >> 6 )) $(( 0x80 | (c & 0x3F) ))
    elif (( c < 0x10000 )); then
        printf -v f '\\x%02x\\x%02x\\x%02x' $(( 0xE0 | c >> 12 )) \
            $(( 0x80 | ((c >> 6) & 0x3F) )) $(( 0x80 | (c & 0x3F) ))
    else
        printf -v f '\\x%02x\\x%02x\\x%02x\\x%02x' $(( 0xF0 | c >> 18 )) \
            $(( 0x80 | ((c >> 12) & 0x3F) )) $(( 0x80 | ((c >> 6) & 0x3F) )) $(( 0x80 | (c & 0x3F) ))
    fi
    printf -v REPLY '%b' "${f}"
    return 0
}

# @private Is the line a code fence (``` or ~~~, optional language)?
# @private Является ли строка ограждением кода (``` или ~~~, язык по желанию)?
textclean::__is_fence() {
    [[ "$1" =~ ^[[:space:]]*(\`\`\`|~~~)[A-Za-z0-9_+.#-]*[[:space:]]*$ ]]
}

# Rules / Правила

# @description ansi: drop ANSI escape sequences (CSI, OSC, DCS, two-byte ESC),
#   backspace overstrike and control characters; CRLF → LF, and for a line with
#   carriage returns keep what the terminal would show (the text after the last CR).
# @description ansi: убрать ANSI-последовательности (CSI, OSC, DCS, двухбайтные
#   ESC), забой с наложением и управляющие символы; CRLF → LF, а у строки с CR
#   оставить то, что показал бы терминал (текст после последнего CR).
textclean::rule::ansi() {
    local LC_ALL=C
    local t="${TEXTCLEAN_TEXT}" re m
    local -r e=$'\e' bel=$'\a'
    [[ "${t}" == *"${e}"* ]] && {
        # OSC/DCS/APC/PM/SOS strings, ended by BEL or ESC \ / строки до BEL или ESC \.
        re="${e}[]PX^_][^${bel}${e}]*(${bel}|${e}\\\\)"
        while [[ "${t}" =~ ${re} ]]; do m="${BASH_REMATCH[0]}"; t="${t//"${m}"/}"; done
        # CSI: ESC [ params intermediates final
        re="${e}\\[[0-?]*[ -/]*[@-~]"
        while [[ "${t}" =~ ${re} ]]; do m="${BASH_REMATCH[0]}"; t="${t//"${m}"/}"; done
        # two-byte and charset escapes / двухбайтные и выбор кодировки
        re="${e}[ -/]*[0-~]"
        while [[ "${t}" =~ ${re} ]]; do m="${BASH_REMATCH[0]}"; t="${t//"${m}"/}"; done
        t="${t//"${e}"/}"
    }
    # backspace overstrike (man pages): "a\ba" → "a" / забой с наложением
    while [[ "${t}" =~ [^$'\b\n']$'\b' ]]; do m="${BASH_REMATCH[0]}"; t="${t//"${m}"/}"; done
    t="${t//$'\r\n'/$'\n'}"
    if [[ "${t}" == *$'\r'* ]]; then
        local -a lines=()
        local i
        mapfile -t lines <<< "${t}"
        for i in "${!lines[@]}"; do
            m="${lines[i]%$'\r'}"
            lines[i]="${m##*$'\r'}"
        done
        local IFS=$'\n'
        t="${lines[*]}"
    fi
    t="${t//[$'\x01\x02\x03\x04\x05\x06\x07\x08\x0b\x0c\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x7f']/}"
    TEXTCLEAN_TEXT="${t}"
}

# @description tags: strip HTML tags and comments; <br>, </p>, </div>, </li>,
#   </tr>, </h1-6> become line breaks, <li> becomes "- ".
# @description tags: убрать HTML-теги и комментарии; <br>, </p>, </div>, </li>,
#   </tr>, </h1-6> становятся переводом строки, <li> — "- ".
textclean::rule::tags() {
    local rest="${TEXTCLEAN_TEXT}" out="" m name
    # comments first / сначала комментарии
    while [[ "${rest}" == *'<!--'*'-->'* ]]; do
        out+="${rest%%'<!--'*}"
        rest="${rest#*'<!--'}"
        rest="${rest#*'-->'}"
    done
    rest="${out}${rest}"
    out=""
    local -r re='<(/?)([A-Za-z][A-Za-z0-9]*)([[:space:]/][^<>]*)?>'
    while [[ "${rest}" =~ ${re} ]]; do
        m="${BASH_REMATCH[0]}"
        name="${BASH_REMATCH[2],,}"
        out+="${rest%%"${m}"*}"
        rest="${rest#*"${m}"}"
        case "${BASH_REMATCH[1]}${name}" in
            br|/p|/div|/li|/tr|/h[1-6]|/pre|/blockquote|/ul|/ol|/table) out+=$'\n' ;;
            li) out+="- " ;;
            td|th) [[ -n "${out}" && "${out}" != *$'\n' ]] && out+=" " ;;
        esac
    done
    TEXTCLEAN_TEXT="${out}${rest}"
}

# @global TEXTCLEAN_ENTITIES — Textclean: named HTML entity → code point (category: constant)
# @global TEXTCLEAN_ENTITIES — Textclean: имя HTML-сущности → кодовая точка (категория: constant)
declare -gA TEXTCLEAN_ENTITIES=(
    [nbsp]=160 [amp]=38 [lt]=60 [gt]=62 [quot]=34 [apos]=39
    [laquo]=171 [raquo]=187 [ldquo]=8220 [rdquo]=8221 [lsquo]=8216 [rsquo]=8217
    [sbquo]=8218 [bdquo]=8222 [mdash]=8212 [ndash]=8211 [hellip]=8230
    [bull]=8226 [middot]=183 [copy]=169 [reg]=174 [trade]=8482 [times]=215
    [divide]=247 [deg]=176 [plusmn]=177 [shy]=173 [zwj]=8205 [zwnj]=8204
    [lrm]=8206 [rlm]=8207 [ensp]=8194 [emsp]=8195 [thinsp]=8201 [minus]=8722
    [euro]=8364 [pound]=163 [yen]=165 [cent]=162 [sect]=167 [para]=182
    [larr]=8592 [rarr]=8594 [uarr]=8593 [darr]=8595 [harr]=8596
    [le]=8804 [ge]=8805 [ne]=8800 [asymp]=8776 [infin]=8734 [prime]=8242 [Prime]=8243
    [lowast]=8727 [hyphen]=8208 [dash]=8208 [Tab]=9 [NewLine]=10 [colon]=58
    [lpar]=40 [rpar]=41 [lbrack]=91 [rbrack]=93 [lcub]=123 [rcub]=125
    [ast]=42 [lowbar]=95 [num]=35 [dollar]=36 [percnt]=37 [excl]=33 [quest]=63
    [grave]=96 [bsol]=92 [verbar]=124 [vert]=124 [sol]=47 [period]=46 [comma]=44
)

# @description entities: decode HTML entities in one pass (&amp;lt; → &lt;),
#   named from TEXTCLEAN_ENTITIES, decimal &#NNN; and hex &#xHH;; unknown ones stay.
# @description entities: декодировать HTML-сущности за один проход
#   (&amp;lt; → &lt;): именованные из TEXTCLEAN_ENTITIES, &#NNN; и &#xHH;;
#   неизвестные остаются как есть.
textclean::rule::entities() {
    local rest="${TEXTCLEAN_TEXT}" out="" m body
    [[ "${rest}" == *'&'*';'* ]] || return 0
    local -r re='&(#[0-9]{1,7}|#[xX][0-9A-Fa-f]{1,6}|[A-Za-z][A-Za-z0-9]{1,31});'
    while [[ "${rest}" =~ ${re} ]]; do
        m="${BASH_REMATCH[0]}"
        body="${BASH_REMATCH[1]}"
        out+="${rest%%"${m}"*}"
        rest="${rest#*"${m}"}"
        REPLY=""
        case "${body}" in
            '#x'*|'#X'*) textclean::__utf8 "$(( 16#${body:2} ))" || REPLY="${m}" ;;
            '#'*)        textclean::__utf8 "$(( 10#${body:1} ))" || REPLY="${m}" ;;
            *)
                if [[ -n "${TEXTCLEAN_ENTITIES[${body}]+x}" ]]; then
                    textclean::__utf8 "${TEXTCLEAN_ENTITIES[${body}]}"
                else
                    REPLY="${m}"
                fi ;;
        esac
        out+="${REPLY}"
    done
    TEXTCLEAN_TEXT="${out}${rest}"
}

# @description invisible: remove zero-width characters, BOM, soft hyphen, bidi
#   marks/overrides/isolates (Trojan Source); NBSP and the other Unicode spaces
#   become a plain space, U+2028/U+2029 become a line break.
# @description invisible: убрать символы нулевой ширины, BOM, мягкий перенос,
#   bidi-метки/переопределения/изоляции (Trojan Source); NBSP и прочие
#   Unicode-пробелы — обычный пробел, U+2028/U+2029 — перевод строки.
textclean::rule::invisible() {
    local t="${TEXTCLEAN_TEXT}" ch
    [[ "${t}" == *[$'\xc2\xe2\xe3\xef']* ]] || return 0
    # removed / удаляются: ZWSP ZWNJ ZWJ LRM RLM, LRE RLE PDF LRO RLO, WJ, LRI RLI FSI PDI, BOM, SHY
    for ch in $'\xe2\x80\x8b' $'\xe2\x80\x8c' $'\xe2\x80\x8d' $'\xe2\x80\x8e' $'\xe2\x80\x8f' \
              $'\xe2\x80\xaa' $'\xe2\x80\xab' $'\xe2\x80\xac' $'\xe2\x80\xad' $'\xe2\x80\xae' \
              $'\xe2\x81\xa0' $'\xe2\x81\xa6' $'\xe2\x81\xa7' $'\xe2\x81\xa8' $'\xe2\x81\xa9' \
              $'\xef\xbb\xbf' $'\xc2\xad'; do
        t="${t//"${ch}"/}"
    done
    # to a space / в пробел: NBSP, U+2000..U+200A, NNBSP, MMSP, ideographic space
    for ch in $'\xc2\xa0' $'\xe2\x80\x80' $'\xe2\x80\x81' $'\xe2\x80\x82' $'\xe2\x80\x83' \
              $'\xe2\x80\x84' $'\xe2\x80\x85' $'\xe2\x80\x86' $'\xe2\x80\x87' $'\xe2\x80\x88' \
              $'\xe2\x80\x89' $'\xe2\x80\x8a' $'\xe2\x80\xaf' $'\xe2\x81\x9f' $'\xe3\x80\x80'; do
        t="${t//"${ch}"/ }"
    done
    t="${t//$'\xe2\x80\xa8'/$'\n'}"
    t="${t//$'\xe2\x80\xa9'/$'\n'}"
    TEXTCLEAN_TEXT="${t}"
}

# @description markdown: drop code fence lines (``` / ~~~ with an optional
#   language) and unescape Markdown backslash escapes (\_ \* \# \[ ...);
#   an escaped backslash stays one backslash.
# @description markdown: убрать строки-ограждения кода (``` / ~~~ с языком) и
#   снять экранирование Markdown (\_ \* \# \[ ...); экранированный обратный
#   слэш остаётся одним слэшем.
textclean::rule::markdown() {
    local -a lines=() kept=()
    local line
    textclean::__lines lines
    for line in "${lines[@]}"; do
        textclean::__is_fence "${line}" && continue
        kept+=("${line}")
    done
    textclean::__join kept
    local rest="${TEXTCLEAN_TEXT}" out="" m
    [[ "${rest}" == *'\'* ]] || return 0
    local -r re='\\([][\\`*_{}()#+.!|>~<-])'
    while [[ "${rest}" =~ ${re} ]]; do
        m="${BASH_REMATCH[0]}"
        out+="${rest%%"${m}"*}${BASH_REMATCH[1]}"
        rest="${rest#*"${m}"}"
    done
    TEXTCLEAN_TEXT="${out}${rest}"
}

# @description typography: “ ” „ ″ → ", ‘ ’ ‚ ′ → ', — – ‒ ― ‐ ‑ − → -,
#   … → ..., • · → -; « » → " only with TEXTCLEAN_GUILLEMETS=1.
# @description typography: “ ” „ ″ → ", ‘ ’ ‚ ′ → ', — – ‒ ― ‐ ‑ − → -,
#   … → ..., • · → -; « » → " только при TEXTCLEAN_GUILLEMETS=1.
textclean::rule::typography() {
    local t="${TEXTCLEAN_TEXT}" ch
    local -r dq='"' sq="'"
    [[ "${t}" == *[$'\xc2\xe2']* ]] || return 0
    for ch in $'\xe2\x80\x9c' $'\xe2\x80\x9d' $'\xe2\x80\x9e' $'\xe2\x80\x9f' $'\xe2\x80\xb3'; do
        t="${t//"${ch}"/${dq}}"
    done
    for ch in $'\xe2\x80\x98' $'\xe2\x80\x99' $'\xe2\x80\x9a' $'\xe2\x80\x9b' $'\xe2\x80\xb2'; do
        t="${t//"${ch}"/${sq}}"
    done
    for ch in $'\xe2\x80\x94' $'\xe2\x80\x93' $'\xe2\x80\x92' $'\xe2\x80\x95' \
              $'\xe2\x80\x90' $'\xe2\x80\x91' $'\xe2\x88\x92'; do
        t="${t//"${ch}"/-}"
    done
    t="${t//$'\xe2\x80\xa6'/...}"
    t="${t//$'\xe2\x80\xa2'/-}"
    if [[ "${TEXTCLEAN_GUILLEMETS}" == 1 ]]; then
        t="${t//$'\xc2\xab'/${dq}}"
        t="${t//$'\xc2\xbb'/${dq}}"
    fi
    TEXTCLEAN_TEXT="${t}"
}

# @description tabs: expand tabs to spaces with stops every TEXTCLEAN_TAB_WIDTH columns.
# @description tabs: заменить табуляцию пробелами с шагом TEXTCLEAN_TAB_WIDTH.
textclean::rule::tabs() {
    [[ "${TEXTCLEAN_TEXT}" == *$'\t'* ]] || return 0
    local -i w="${TEXTCLEAN_TAB_WIDTH}" col n
    (( w > 0 )) || w=4
    local -a lines=()
    local i line out head pad
    textclean::__lines lines
    for i in "${!lines[@]}"; do
        line="${lines[i]}"
        [[ "${line}" == *$'\t'* ]] || continue
        out=""
        while [[ "${line}" == *$'\t'* ]]; do
            head="${line%%$'\t'*}"
            line="${line#*$'\t'}"
            out+="${head}"
            col=${#out}
            n=$(( w - col % w ))
            printf -v pad '%*s' "${n}" ''
            out+="${pad}"
        done
        lines[i]="${out}${line}"
    done
    textclean::__join lines
}

# @private Does the trimmed line match a noise pattern? / Шумовая ли обрезанная строка?
textclean::__is_noise() {
    local -r s="$1"
    local p
    [[ -z "${s}" ]] && return 1
    for p in "${TEXTCLEAN_NOISE[@]}"; do
        [[ "${s}" =~ ^(${p})$ ]] && return 0
    done
    return 1
}

# @private Trim spaces at both ends into REPLY / Обрезать пробелы по краям в REPLY
textclean::__trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    REPLY="${s%"${s##*[![:space:]]}"}"
}

# @description noise: drop lines that are only UI noise (TEXTCLEAN_NOISE plus the
#   config file), and a code-block language label ("bash") right before one.
# @description noise: убрать строки, состоящие только из шума интерфейса
#   (TEXTCLEAN_NOISE и файл настроек), и метку языка ("bash") прямо перед ней.
textclean::rule::noise() {
    local -a lines=() kept=()
    local -i i n
    local cur next
    textclean::__lines lines
    n=${#lines[@]}
    for (( i = 0; i < n; i++ )); do
        textclean::__trim "${lines[i]}"; cur="${REPLY}"
        textclean::__is_noise "${cur}" && continue
        if (( i + 1 < n )) && [[ "${TEXTCLEAN_LANG_LABELS}" == *" ${cur,,} "* ]]; then
            textclean::__trim "${lines[i + 1]}"; next="${REPLY}"
            textclean::__is_noise "${next}" && { i=$(( i + 1 )); continue; }
        fi
        kept+=("${lines[i]}")
    done
    textclean::__join kept
}

# @description trailing: remove spaces and tabs at the end of every line.
# @description trailing: убрать пробелы и табуляцию в конце каждой строки.
textclean::rule::trailing() {
    local -a lines=()
    local i line
    textclean::__lines lines
    for i in "${!lines[@]}"; do
        line="${lines[i]}"
        lines[i]="${line%"${line##*[![:space:]]}"}"
    done
    textclean::__join lines
}

# @description dedent: remove the leading whitespace common to all non-blank lines.
# @description dedent: убрать общий для всех непустых строк отступ слева.
textclean::rule::dedent() {
    local -a lines=()
    local i line lead common="" first=1
    textclean::__lines lines
    for line in "${lines[@]}"; do
        [[ "${line}" =~ ^[[:space:]]*$ ]] && continue
        lead="${line%%[![:space:]]*}"
        if (( first )); then
            common="${lead}"; first=0
        else
            while [[ -n "${common}" && "${lead}" != "${common}"* ]]; do common="${common%?}"; done
        fi
        [[ -z "${common}" ]] && return 0
    done
    [[ -z "${common}" ]] && return 0
    for i in "${!lines[@]}"; do
        if [[ "${lines[i]}" =~ ^[[:space:]]*$ ]]; then
            lines[i]=""
        else
            lines[i]="${lines[i]#"${common}"}"
        fi
    done
    textclean::__join lines
}

# @private Does the line start a block of its own (list, heading, quote, table,
#   prompt)? / Начинает ли строка отдельный блок (список, заголовок, цитата, таблица, приглашение)?
textclean::__is_block_start() {
    local -r re='^[[:space:]]*([-*+][[:space:]]|[0-9]{1,3}[.)][[:space:]]|#{1,6}[[:space:]]|[>|]|[$][[:space:]])'
    [[ "$1" =~ ${re} ]]
}

# @private Is the line a list item? / Пункт ли списка строка?
textclean::__is_list_item() {
    local -r re='^[[:space:]]*([-*+]|[0-9]{1,3}[.)])[[:space:]]'
    [[ "$1" =~ ${re} ]]
}

# @description unwrap: join hard-wrapped prose lines into one line per paragraph.
#   A line is joined to the previous one only when the previous line is at least
#   TEXTCLEAN_UNWRAP_MIN characters long (short lines, such as commands, stay);
#   fenced and indented code, lists, headings, quotes and tables are kept, a
#   list item absorbs its indented continuation lines.
# @description unwrap: склеить разорванные строки текста в одну строку на абзац.
#   Строка присоединяется к предыдущей, только если та не короче
#   TEXTCLEAN_UNWRAP_MIN символов (короткие строки, например команды, остаются);
#   код в ограждениях и с отступом, списки, заголовки, цитаты и таблицы не
#   трогаются, пункт списка забирает свои строки-продолжения с отступом.
textclean::rule::unwrap() {
    local -a lines=() out=()
    local line prev="" body
    local -i in_fence=0 have=0 prev_len=0 min="${TEXTCLEAN_UNWRAP_MIN}"
    textclean::__lines lines
    for line in "${lines[@]}"; do
        if textclean::__is_fence "${line}"; then
            (( have )) && out+=("${prev}"); have=0
            out+=("${line}")
            in_fence=$(( 1 - in_fence ))
            continue
        fi
        if (( in_fence )) || [[ "${line}" =~ ^[[:space:]]*$ ]]; then
            (( have )) && out+=("${prev}"); have=0
            out+=("${line}")
            continue
        fi
        if [[ "${line}" == $'\t'* || "${line}" == '    '* ]] && ! (( have )); then
            out+=("${line}")
            continue
        fi
        if (( have )) && ! textclean::__is_block_start "${line}" && (( prev_len >= min )) \
            && { [[ "${line}" != $'\t'* && "${line}" != '    '* ]] || textclean::__is_list_item "${prev}"; }; then
            textclean::__trim "${line}"; body="${REPLY}"
            prev+=" ${body}"
            prev_len=${#line}
            continue
        fi
        (( have )) && out+=("${prev}")
        prev="${line}"; have=1; prev_len=${#line}
    done
    (( have )) && out+=("${prev}")
    textclean::__join out
}

# @description blank: whitespace-only lines become empty, runs of blank lines
#   collapse to one, blank lines at the start and the end are removed.
# @description blank: строки из пробелов становятся пустыми, серии пустых строк
#   схлопываются в одну, пустые строки в начале и в конце убираются.
textclean::rule::blank() {
    local -a lines=() out=()
    local line
    local -i pending=0
    textclean::__lines lines
    for line in "${lines[@]}"; do
        if [[ "${line}" =~ ^[[:space:]]*$ ]]; then
            (( ${#out[@]} > 0 )) && pending=1
            continue
        fi
        (( pending )) && out+=("")
        pending=0
        out+=("${line}")
    done
    textclean::__join out
}

# Danger / Опасные команды

# @global TEXTCLEAN_DANGER_RULES — Textclean: "reason<TAB>ERE" checks for danger (category: hook)
# @global TEXTCLEAN_DANGER_RULES — Textclean: проверки danger "причина<TAB>ERE" (категория: hook)
declare -ga TEXTCLEAN_DANGER_RULES=(
    $'sudo\t(^|[;&|(`[:space:]])sudo([[:space:]]|$)'
    $'su to root\t(^|[;&|[:space:]])su([[:space:]]+-)?([[:space:]]+root)?[[:space:]]*$'
    $'recursive rm\t(^|[;&|[:space:]])rm[[:space:]]+(-[A-Za-z]*[rR]|--recursive|.*[[:space:]]-[A-Za-z]*[rR])'
    $'rm --no-preserve-root\t--no-preserve-root'
    $'download piped to a shell\t(curl|wget|fetch)[^|]*[|][[:space:]]*(sudo[[:space:]]+)?([a-z]*sh|python[0-9.]*|perl|ruby|node)([[:space:]]|$)'
    $'decoded data piped to a shell\tbase64[^|]*-(d|-decode)[^|]*[|][[:space:]]*(sudo[[:space:]]+)?[a-z]*sh([[:space:]]|$)'
    $'make filesystem\t(^|[;&|[:space:]])mkfs(\\.[a-z0-9]+)?([[:space:]]|$)'
    $'dd to a device\t(^|[;&|[:space:]])dd[[:space:]].*of=/dev/'
    $'write to a disk device\t>[[:space:]]*/dev/(sd|hd|vd|xvd|nvme|mmcblk|disk)'
    $'world-writable chmod\tchmod[[:space:]]+(-[A-Za-z]+[[:space:]]+)*0?777'
    $'recursive chown/chmod of /\t(chown|chmod)[[:space:]]+-[A-Za-z]*R[A-Za-z]*[[:space:]]+[^[:space:]]+[[:space:]]+/([[:space:]]|$)'
    $'fork bomb\t:\\(\\)[[:space:]]*\\{'
    $'power off or reboot\t(^|[;&|[:space:]])(shutdown|reboot|poweroff|halt)([[:space:]]|$)'
    $'find -delete\tfind[[:space:]].*-delete'
    $'git force push or hard reset\tgit[[:space:]]+(push[[:space:]].*(--force|-f([[:space:]]|$))|reset[[:space:]]+--hard|clean[[:space:]]+-[A-Za-z]*f)'
    $'eval\t(^|[;&|[:space:]])eval[[:space:]]'
    $'overwrite a shell startup file\t>[[:space:]]*~?/?[^[:space:]]*\\.(bashrc|zshrc|profile|bash_profile)'
)

# @description danger: scan TEXTCLEAN_TEXT for dangerous shell commands and
#   hidden characters; fill TEXTCLEAN_DANGER with "line<TAB>reason<TAB>text".
#   The text is not changed.
# @description danger: найти в TEXTCLEAN_TEXT опасные команды и скрытые
#   символы; заполнить TEXTCLEAN_DANGER строками "строка<TAB>причина<TAB>текст".
#   Текст не меняется.
# @return 0 when something was found, 1 when clean / 0 — найдено, 1 — чисто
textclean::danger::scan() {
    TEXTCLEAN_DANGER=()
    local -a lines=()
    local -i i
    local line entry reason re
    textclean::__lines lines
    for i in "${!lines[@]}"; do
        line="${lines[i]}"
        for entry in "${TEXTCLEAN_DANGER_RULES[@]}"; do
            reason="${entry%%$'\t'*}"
            re="${entry#*$'\t'}"
            [[ "${line}" =~ ${re} ]] && TEXTCLEAN_DANGER+=("$(( i + 1 ))"$'\t'"${reason}"$'\t'"${line}")
        done
        if [[ "${line}" == *[$'\x01'-$'\x08'$'\x0b'-$'\x1f'$'\x7f']* ]]; then
            TEXTCLEAN_DANGER+=("$(( i + 1 ))"$'\t'"control characters"$'\t'"${line//[$'\x01'-$'\x1f']/?}")
        fi
        case "${line}" in
            *$'\xe2\x80\xaa'*|*$'\xe2\x80\xab'*|*$'\xe2\x80\xac'*|*$'\xe2\x80\xad'*|*$'\xe2\x80\xae'*|\
            *$'\xe2\x81\xa6'*|*$'\xe2\x81\xa7'*|*$'\xe2\x81\xa8'*|*$'\xe2\x81\xa9'*|\
            *$'\xe2\x80\x8b'*|*$'\xe2\x80\x8c'*|*$'\xe2\x80\x8d'*|*$'\xef\xbb\xbf'*)
                TEXTCLEAN_DANGER+=("$(( i + 1 ))"$'\t'"hidden Unicode characters"$'\t'"${line}") ;;
        esac
    done
    (( ${#TEXTCLEAN_DANGER[@]} > 0 ))
}

# Pipeline / Конвейер

# @description Run every enabled transforming rule over TEXTCLEAN_TEXT in order,
#   then the danger scan when it is on (TEXTCLEAN_DANGER is emptied otherwise).
# @description Прогнать включённые правила над TEXTCLEAN_TEXT по порядку, затем
#   сканер danger, если он включён (иначе TEXTCLEAN_DANGER очищается).
textclean::process() {
    textclean::__ensure
    local r
    for r in "${TEXTCLEAN_RULES[@]}"; do
        [[ "${r}" == danger ]] && continue
        (( TEXTCLEAN_ON[${r}] == 1 )) || continue
        "textclean::rule::${r}"
    done
    TEXTCLEAN_DANGER=()
    if (( TEXTCLEAN_ON[danger] == 1 )); then
        textclean::danger::scan || true
    fi
    return 0
}

# @description Clean a string and print it with a final newline (nothing for empty)
# @description Очистить строку и вывести с финальным переводом строки (пустую — никак)
# @param $1 text / текст
# @stdout cleaned text / очищенный текст
textclean::string() {
    TEXTCLEAN_TEXT="${1-}"
    TEXTCLEAN_TEXT="${TEXTCLEAN_TEXT%$'\n'}"
    textclean::process
    [[ -n "${TEXTCLEAN_TEXT}" ]] && printf '%s\n' "${TEXTCLEAN_TEXT}"
    return 0
}

# @description Read all of stdin into TEXTCLEAN_TEXT (one final newline dropped)
# @description Прочитать весь stdin в TEXTCLEAN_TEXT (один финальный перевод строки отбрасывается)
textclean::read() {
    TEXTCLEAN_TEXT=""
    IFS= read -r -d '' TEXTCLEAN_TEXT || true
    TEXTCLEAN_TEXT="${TEXTCLEAN_TEXT%$'\n'}"
}

# @description stdin → enabled rules → stdout; findings stay in TEXTCLEAN_DANGER
#   (only within the same shell, so call it without a pipe on its left side when
#   you need them: textclean::filter < file).
# @description stdin → включённые правила → stdout; находки в TEXTCLEAN_DANGER
#   (только в той же оболочке: если они нужны, вызывайте без конвейера слева:
#   textclean::filter < file).
textclean::filter() {
    textclean::read
    textclean::process
    [[ -n "${TEXTCLEAN_TEXT}" ]] && printf '%s\n' "${TEXTCLEAN_TEXT}"
    return 0
}

# Clipboard / Буфер обмена

# @description Base64 of $1 into REPLY (base64, openssl or pure bash fallback)
# @description Base64 от $1 в REPLY (base64, openssl или запасной вариант на bash)
textclean::__base64() {
    local -r s="$1"
    if deps::has base64; then
        REPLY="$(printf '%s' "${s}" | base64 | tr -d '\n')"
        return 0
    fi
    if deps::has openssl; then
        REPLY="$(printf '%s' "${s}" | openssl base64 -A)"
        return 0
    fi
    local LC_ALL=C
    local -r tbl='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local -i i n=${#s} a b c v
    local enc=""
    for (( i = 0; i < n; i += 3 )); do
        printf -v a '%d' "'${s:i:1}"
        b=0; c=0
        (( i + 1 < n )) && printf -v b '%d' "'${s:i+1:1}"
        (( i + 2 < n )) && printf -v c '%d' "'${s:i+2:1}"
        (( a &= 255, b &= 255, c &= 255 ))
        v=$(( a << 16 | b << 8 | c ))
        enc+="${tbl:v>>18&63:1}${tbl:v>>12&63:1}"
        if (( i + 1 < n )); then enc+="${tbl:v>>6&63:1}"; else enc+="="; fi
        if (( i + 2 < n )); then enc+="${tbl:v&63:1}"; else enc+="="; fi
    done
    REPLY="${enc}"
}

# @description Build the OSC 52 "set clipboard" sequence for $1 into REPLY,
#   wrapped for tmux (TMUX) and GNU screen (TERM=screen*) passthrough.
# @description Собрать OSC 52 "записать в буфер обмена" для $1 в REPLY,
#   с обёрткой для tmux (TMUX) и GNU screen (TERM=screen*).
# @param $1 text / текст
textclean::osc52() {
    textclean::__base64 "${1-}"
    local seq=$'\e]52;c;'"${REPLY}"$'\a'
    if [[ -n "${TMUX:-}" ]]; then
        seq=$'\ePtmux;\e'"${seq}"$'\e\\'
    elif [[ "${TERM:-}" == screen* ]]; then
        seq=$'\eP'"${seq}"$'\e\\'
    fi
    REPLY="${seq}"
}

# @description Copy $1 to the clipboard through the terminal (OSC 52 to /dev/tty).
# @description Скопировать $1 в буфер обмена через терминал (OSC 52 в /dev/tty).
# @param $1 text, $2 [tty path, default /dev/tty] / текст, путь к tty
# @return LIB_ERROR_FILE_OPERATION when the terminal cannot be written / если терминал недоступен
textclean::copy() {
    local -r tty="${2:-/dev/tty}"
    textclean::osc52 "${1-}"
    { printf '%s' "${REPLY}" > "${tty}"; } 2>/dev/null || return "${LIB_ERROR_FILE_OPERATION}"
}

# Reading the clipboard / Чтение буфера обмена

# @global TEXTCLEAN_PASTE_TOOLS — Textclean: clipboard readers tried in order, "tool<TAB>command" (category: hook)
# @global TEXTCLEAN_PASTE_TOOLS — Textclean: программы чтения буфера по порядку, "программа<TAB>команда" (категория: hook)
declare -ga TEXTCLEAN_PASTE_TOOLS=(
    $'wl-paste\twl-paste --no-newline'
    $'xclip\txclip -selection clipboard -o'
    $'xsel\txsel --clipboard --output'
    $'pbpaste\tpbpaste'
    $'termux-clipboard-get\ttermux-clipboard-get'
    $'powershell.exe\tpowershell.exe -NoProfile -Command Get-Clipboard'
)

# @global TEXTCLEAN_PASTE_TOOL — Textclean: reader used by the last textclean::paste (category: state)
# @global TEXTCLEAN_PASTE_TOOL — Textclean: программа последнего textclean::paste (категория: state)
declare -g TEXTCLEAN_PASTE_TOOL=""

# @description Names of the clipboard readers, space separated / Имена программ чтения буфера через пробел
# @stdout names / имена
textclean::paste::tools() {
    local entry names=""
    for entry in "${TEXTCLEAN_PASTE_TOOLS[@]}"; do names+="${names:+ }${entry%%$'\t'*}"; done
    printf '%s\n' "${names}"
}

# @description Read the system clipboard into REPLY with the first reader that is
#   installed (deps::has) and works; TEXTCLEAN_PASTE_TOOL names it. A terminal cannot be
#   asked for its clipboard (OSC 52 read is disabled almost everywhere), so a
#   reader program is needed here; copying needs none.
# @description Прочитать системный буфер обмена в REPLY первой установленной
#   (deps::has) и работающей программой; TEXTCLEAN_PASTE_TOOL — её имя. Спросить буфер у
#   терминала нельзя (чтение OSC 52 почти везде запрещено), поэтому здесь нужна
#   программа; для копирования она не нужна.
# @return 0 ok, LIB_ERROR_DEPENDENCY_MISSING when no reader is installed,
#   LIB_ERROR_DEPENDENCY when readers exist but all failed (TEXTCLEAN_PASTE_TOOL lists them) /
#   0 — успех, LIB_ERROR_DEPENDENCY_MISSING — нет ни одной программы,
#   LIB_ERROR_DEPENDENCY — программы есть, но все упали (TEXTCLEAN_PASTE_TOOL — их список)
# shellcheck disable=SC2034 # TEXTCLEAN_PASTE_TOOL is read by the caller / читает вызывающий
textclean::paste() {
    local entry tool cmd out tried=""
    local -a argv=()
    REPLY=""
    TEXTCLEAN_PASTE_TOOL=""
    for entry in "${TEXTCLEAN_PASTE_TOOLS[@]}"; do
        tool="${entry%%$'\t'*}"
        cmd="${entry#*$'\t'}"
        deps::has "${tool}" || continue
        tried+="${tried:+ }${tool}"
        IFS=' ' read -r -a argv <<< "${cmd}"
        if out="$("${argv[@]}" 2>/dev/null)"; then
            REPLY="${out//$'\r\n'/$'\n'}"
            TEXTCLEAN_PASTE_TOOL="${tool}"
            return "${E_SUCCESS}"
        fi
    done
    TEXTCLEAN_PASTE_TOOL="${tried}"
    [[ -z "${tried}" ]] && return "${LIB_ERROR_DEPENDENCY_MISSING}"
    return "${LIB_ERROR_DEPENDENCY}"
}
