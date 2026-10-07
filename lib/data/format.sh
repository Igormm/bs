#!/usr/bin/env bs
# shellcheck shell=bash
# lib/data/format.sh — render canonical key=value records as string/json/xml
# lib/data/format.sh — рендер канонических записей key=value в string/json/xml
#
# Contract / Контракт:
#   A method emits canonical records (one `key=value` per line, split on the
#   FIRST `=`, a blank line separates records) and pipes them to
#   `format::emit "<format>"`. The method never formats.
#   Метод выводит канонические записи (строка `key=value`, деление по ПЕРВОМУ
#   `=`, пустая строка разделяет записи) и подаёт их в `format::emit "<формат>"`.
#
# @depends core/lang, core/const
# @tier core

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_DATA_FORMAT" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/lang.sh" "../../core/const.sh"

# @global BS_OUTPUT_FORMAT — Format: selected output format (category: hook)
# @global BS_OUTPUT_FORMAT — Format: выбранный формат вывода (категория: hook)
declare -g BS_OUTPUT_FORMAT="string"
# @global BS_FORMAT_ROOT — Format: XML root element name (category: hook)
# @global BS_FORMAT_ROOT — Format: имя корневого XML-элемента (категория: hook)
declare -g BS_FORMAT_ROOT="record"

# @global FORMAT_NAMES — Format: available format names (category: constant)
# @global FORMAT_NAMES — Format: доступные имена форматов (категория: constant)
declare -ga FORMAT_NAMES=("string" "json" "xml")
# @global FORMATTERS — Format: format=render-function registry (category: constant)
# @global FORMATTERS — Format: реестр format=функция-рендер (категория: constant)
declare -gA FORMATTERS=(
    [string]="format::render::string"
    [json]="format::render::json"
    [xml]="format::render::xml"
)

# @global FORMAT_KEYS — Format: parsed record keys (category: state)
# @global FORMAT_KEYS — Format: разобранные ключи записи (категория: state)
declare -ga FORMAT_KEYS=()
# @global FORMAT_VALUES — Format: parsed record values (category: state)
# @global FORMAT_VALUES — Format: разобранные значения записи (категория: state)
declare -ga FORMAT_VALUES=()

# @description List available formats / Перечислить форматы
# @stdout formats one per line / форматы по одному в строке
format::list() {
    local f
    for f in "${FORMAT_NAMES[@]}"; do printf '%s\n' "${f}"; done
}

# @description Validate a format name / Проверить имя формата
# @param $1 Format / Формат
# @return E_SUCCESS or LIB_ERROR_INVALID_INPUT
format::validate() {
    local -r fmt="${1-}"
    is::empty "${fmt}" && return "${LIB_ERROR_INVALID_INPUT}"
    local f
    for f in "${FORMAT_NAMES[@]}"; do
        [[ "${f}" == "${fmt}" ]] && return "${E_SUCCESS}"
    done
    return "${LIB_ERROR_INVALID_INPUT}"
}

# @description Emit canonical records: key=value lines, one field per line.
# @description Вывести канонические записи: строки key=value, поле на строку.
# @param $1 Key, $2 Value, ... (pairs; a missing value = empty) /
#   Пары ключ-значение (значение можно опустить)
# @stdout canonical lines / канонические строки
format::record() {
    local key value
    while (( $# > 0 )); do
        key="${1:?key required}"; shift
        value=""
        (( $# > 0 )) && { value="${1}"; shift; }
        printf '%s=%s\n' "${key}" "${value}"
    done
}

# @description Read canonical records from stdin into arrays.
# @description Прочитать канонические записи из stdin в массивы.
#   Sets FORMAT_KEYS, FORMAT_VALUES (parallel), FORMAT_BREAKS (record starts).
#   Устанавливает FORMAT_KEYS, FORMAT_VALUES (параллельно), FORMAT_BREAKS.
# @stdin canonical records / канонические записи
format::__read() {
    FORMAT_KEYS=()
    FORMAT_VALUES=()
    local line key value
    while IFS= read -r line || is::not_empty "${line}"; do
        is::empty "${line}" && continue
        key="${line%%=*}"
        value="${line#*=}"
        FORMAT_KEYS+=("${key}")
        FORMAT_VALUES+=("${value}")
    done
}

# @description Escape a string for JSON / Экранировать строку для JSON
# @param $1 String / Строка
# @stdout escaped / экранированная
format::__json_escape() {
    local s="${1-}"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "${s}"
}

# @description Escape a string for XML / Экранировать строку для XML
# @param $1 String / Строка
# @stdout escaped / экранированная
format::__xml_escape() {
    local s="${1-}"
    # `&` in the replacement of ${var//pat/repl} is bash's "matched text" —
    # escape it as \& (bash 5.3+). / `&` в replacement — спецсимвол bash,
    # экранируется как \&.
    s="${s//&/\&amp;}"
    s="${s//</\&lt;}"
    s="${s//>/\&gt;}"
    s="${s//\"/\&quot;}"
    s="${s//\'/\&apos;}"
    printf '%s' "${s}"
}

# @description Render string: a lone field prints its value; otherwise
# `key: value` per field.
# @description Строковый вывод: единственное поле печатает значение; иначе
# `key: value` на поле.
# @stdin canonical records / канонические записи
# @stdout human text / человекочитаемый текст
format::render::string() {
    format::__read
    local -i n=${#FORMAT_KEYS[@]} i
    if (( n == 0 )); then return 0; fi
    if (( n == 1 )); then
        printf '%s\n' "${FORMAT_VALUES[0]}"
        return 0
    fi
    for (( i = 0; i < n; i++ )); do
        printf '%s: %s\n' "${FORMAT_KEYS[$i]}" "${FORMAT_VALUES[$i]}"
    done
    return 0
}

# @description Render JSON: an object for a single record, an array for many
# (records are not separated in the canonical grammar beyond blank lines, so
# every record boundary is a fresh object).
# @description Рендер JSON: объект для одной записи, массив для нескольких.
# @stdin canonical records / канонические записи
# @stdout JSON / JSON
format::render::json() {
    local -a records=()
    local cur="" line key value
    while IFS= read -r line || is::not_empty "${line}"; do
        if is::empty "${line}"; then
            if is::not_empty "${cur}"; then records+=("${cur}"); cur=""; fi
            continue
        fi
        key="${line%%=*}"; value="${line#*=}"
        is::empty "${cur}" || cur+=","
        cur+="\"$(format::__json_escape "${key}")\":\"$(format::__json_escape "${value}")\""
    done
    is::not_empty "${cur}" && records+=("${cur}")
    if (( ${#records[@]} == 0 )); then printf '{}\n'; return 0; fi
    if (( ${#records[@]} == 1 )); then printf '{%s}\n' "${records[0]}"; return 0; fi
    local out="[" i
    for (( i = 0; i < ${#records[@]}; i++ )); do
        (( i == 0 )) || out+=","
        out+="{${records[$i]}}"
    done
    printf '%s]\n' "${out}"
}

# @description Render XML: one <record>, or <records> wrapping several.
# @description Рендер XML: один <record> или <records> вокруг нескольких.
# @stdin canonical records / канонические записи
# @stdout XML / XML
format::render::xml() {
    local -a records=()
    local cur="" line key value
    local -r root="${BS_FORMAT_ROOT:-record}"
    while IFS= read -r line || is::not_empty "${line}"; do
        if is::empty "${line}"; then
            if is::not_empty "${cur}"; then records+=("${cur}"); cur=""; fi
            continue
        fi
        key="${line%%=*}"; value="${line#*=}"
        cur+="<$(format::__xml_escape "${key}")>$(format::__xml_escape "${value}")</$(format::__xml_escape "${key}")>"
    done
    is::not_empty "${cur}" && records+=("${cur}")
    if (( ${#records[@]} == 0 )); then printf '<%s/>\n' "${root}"; return 0; fi
    if (( ${#records[@]} == 1 )); then printf '<%s>%s</%s>\n' "${root}" "${records[0]}" "${root}"; return 0; fi
    local out="<records>" r
    for r in "${records[@]}"; do out+="<record>${r}</record>"; done
    printf '%s</records>\n' "${out}"
}

# @description Dispatch canonical records to the renderer for a format.
# @description Направить записи в рендерер выбранного формата.
# @param $1 Format / Формат
# @stdin canonical records / канонические записи
# @stdout rendered text / отрендеренный текст
format::emit() {
    local -r fmt="${1-}"
    format::validate "${fmt}" || return "${LIB_ERROR_INVALID_INPUT}"
    local -r fn="${FORMATTERS[${fmt}]}"
    is::function "${fn}" || return "${LIB_ERROR_INVALID_INPUT}"
    "${fn}"
}
