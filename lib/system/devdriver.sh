#!/usr/bin/env bs
# shellcheck shell=bash
# lib/system/devdriver.sh — shared helpers for devicectl drivers: build the
# params/snapshot TSV from a driver's parameter catalogue and its get()
# lib/system/devdriver.sh — общие помощники драйверов devicectl: строят TSV
# params/snapshot из каталога параметров драйвера и его get()
#
# A catalogue-driven driver defines:
#   driver::<name>::__catalog [args…] -> TSV param<TAB>type<TAB>default<TAB>choices<TAB>tip
#   driver::<name>::get <handle> <param> -> current value
# and then implements params/snapshot as one-liners:
#   driver::<name>::params()   { devdriver::params   <name> "$1" "" ; }
#   driver::<name>::snapshot() { devdriver::snapshot <name> "$1" "" ; }
# Драйвер с каталогом задаёт __catalog и get, а params/snapshot делегирует сюда.
#
# @depends core/lang
# @tier core
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], local/declare flags, process substitution / needs bash constructs: double-bracket [[ ]], local/declare flags, process substitution

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_SYSTEM_DEVDRIVER" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/lang.sh"

# @private Разобрать строку каталога, сохраняя пустые поля. IFS=$'\t' read склеивает
# соседние табы (таб — пробельный символ IFS), и пустой choices/default сдвигал колонки.
# @private Split a catalogue row keeping empty fields. IFS=$'\t' read merges adjacent
# tabs (tab is IFS whitespace), so an empty choices/default shifted the columns.
# @param $1 row param<TAB>type<TAB>default<TAB>choices<TAB>tip
# Sets the caller's param, type, dflt, choices, tip (dynamic scope).
devdriver::__split() {
    local rest="$1"
    param="${rest%%$'\t'*}"; rest="${rest#*$'\t'}"
    type="${rest%%$'\t'*}";  rest="${rest#*$'\t'}"
    dflt="${rest%%$'\t'*}";  rest="${rest#*$'\t'}"
    choices="${rest%%$'\t'*}"; rest="${rest#*$'\t'}"
    tip="${rest}"
}

# @description Параметры устройства по каталогу драйвера: к каждой строке каталога
# добавляется текущее значение из driver::<name>::get.
# @description Device parameters from the driver's catalogue: each catalogue row
# gets the current value from driver::<name>::get.
# @param $1 driver name / имя драйвера
# @param $2 handle
# @param $3 fallback value when get fails / значение, если get упал
# @param $@ extra args passed to __catalog (e.g. device kind) / доп. аргументы для __catalog
# @stdout TSV param<TAB>type<TAB>current<TAB>default<TAB>choices<TAB>tip
devdriver::params() {
    local -r name="$1" handle="$2" fallback="$3"
    shift 3
    local line param type dflt choices tip cur
    while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        devdriver::__split "${line}"
        cur="$("driver::${name}::get" "${handle}" "${param}")" || cur="${fallback}"
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${param}" "${type}" "${cur}" "${dflt}" "${choices}" "${tip}"
    done < <("driver::${name}::__catalog" "$@")
    return 0
}

# @description Снимок всех параметров устройства по каталогу драйвера.
# @description Snapshot of all device parameters from the driver's catalogue.
# @param $1 driver name / имя драйвера
# @param $2 handle
# @param $3 fallback value when get fails / значение, если get упал
# @param $@ extra args passed to __catalog / доп. аргументы для __catalog
# @stdout TSV param<TAB>value
devdriver::snapshot() {
    local -r name="$1" handle="$2" fallback="$3"
    shift 3
    local line param type dflt choices tip cur
    while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        devdriver::__split "${line}"
        cur="$("driver::${name}::get" "${handle}" "${param}" 2>/dev/null)" || cur="${fallback}"
        printf '%s\t%s\n' "${param}" "${cur}"
    done < <("driver::${name}::__catalog" "$@")
    return 0
}
