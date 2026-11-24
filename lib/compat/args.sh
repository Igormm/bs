#!/usr/bin/env bs
# shellcheck shell=bash
# @shell bash4 — настоящие массивы bash ARGS_PARAMS, ARGS_FLAGS, ARGS_REST / the real bash arrays ARGS_PARAMS, ARGS_FLAGS, ARGS_REST
#
# lib/compat/args.sh — мост совместимости: args::parse с массивами bash
# lib/compat/args.sh — compatibility bridge: args::parse with bash arrays
#
# Ядро (core/args.sh, @shell posix) держит результат разбора в слое данных (bs_args_params,
# bs_args_parsed, bs_args_rest). Скрипты и примеры читают после args::parse настоящие массивы
# bash — ${ARGS_PARAMS[0]}, ${ARGS_FLAGS[name]}, ${ARGS_REST[@]} — поэтому args::parse,
# args::reset и args::require живут здесь, вне ядра: они вызывают ядро и копируют результат
# в эти массивы. init.sh подключает этот файл в bash.
# The kernel (core/args.sh, @shell posix) keeps the parse result in the data layer
# (bs_args_params, bs_args_parsed, bs_args_rest). Scripts and examples read real bash arrays
# after args::parse — ${ARGS_PARAMS[0]}, ${ARGS_FLAGS[name]}, ${ARGS_REST[@]} — so args::parse,
# args::reset and args::require live here, outside the kernel: they call the kernel and copy
# the result into those arrays. init.sh loads this file in bash.

bs::guard "COMPAT_ARGS" || return 0

# @global ARGS_PARAMS — Args: parsed positional parameters (category: constant)
# @global ARGS_PARAMS — Args: разобранные позиционные параметры (категория: constant)
declare -g -a ARGS_PARAMS=()

# @global ARGS_FLAGS — Args: parsed flags map (category: constant)
# @global ARGS_FLAGS — Args: карта разобранных флагов (категория: constant)
declare -g -A ARGS_FLAGS=()

# @global ARGS_REST — Args: remaining arguments after parsing (category: constant)
# @global ARGS_REST — Args: остаток аргументов после разбора (категория: constant)
declare -g -a ARGS_REST=()

# @private
# @description Скопировать результат разбора из слоя данных в массивы bash
# @description Copy the parse result from the data layer into the bash arrays
args::__sync() {
    local k v
    ARGS_PARAMS=()
    ARGS_FLAGS=()
    ARGS_REST=()
    eval "$(bs_arr_to_args bs_args_params)"
    ARGS_PARAMS=("$@")
    eval "$(bs_arr_to_args bs_args_rest)"
    ARGS_REST=("$@")
    bs_map_keys_to bs_args_parsed bs_args_pk
    eval "$(bs_arr_to_args bs_args_pk)"
    for k in "$@"; do
        bs_map_get_to bs_args_parsed "${k}" v
        ARGS_FLAGS["${k}"]="${v}"
    done
}

# @description Сбросить объявления и результаты разбора / Reset declarations and parse results
args::reset() {
    bs_args_reset
    args::__sync
}

# @description Проверить аргументы по объявленному дереву; результат — ARGS_PARAMS, ARGS_FLAGS, ARGS_REST
# @description Validate arguments against the declared tree; the result is ARGS_PARAMS, ARGS_FLAGS, ARGS_REST
# @param $@ arguments / аргументы
# @return 0 ok or help printed, E_INVALID on a bad argument / 0 или help, E_INVALID при ошибке
args::parse() {
    local rc=0
    bs_args_parse "$@" || rc=$?
    args::__sync
    return "${rc}"
}

# @description Все CLI-значения флага, по одному на строку / All CLI values of a flag, one per line
# @param $1 canonical flag name
args::flag_get_all() {
    bs_args_flag_get_all "$@"
}

# @description Скопировать CLI-значения флага в caller-named массив / Copy CLI flag values into a caller-named array
# @param $1 canonical flag name
# @param $2 caller array name
args::flag_values() {
    local name="${1:-}" array_name="${2:-}" i value count
    case "$array_name" in
        ''|[0-9]*|__bs_*|*[!A-Za-z0-9_]*)
            log::error "args::flag_values: invalid array name: ${array_name}"
            return "${E_INVALID:-2}"
            ;;
    esac

    bs_arr_clear bs_args_selected
    if bs_map_has bs_args_flag_repeat "$name"; then
        bs_data_len_of bs_args_repeat_names
        count=$__bs_dat_n
        for (( i=0; i<count; i++ )); do
            bs_data_get_at bs_args_repeat_names "$i"
            if [[ "$__bs_dat_cur" == "$name" ]]; then
                bs_data_get_at bs_args_repeat_values "$i"
                bs_arr_push bs_args_selected "$__bs_dat_cur"
            fi
        done
    elif bs_map_has bs_args_parsed "$name"; then
        bs_map_get_to bs_args_parsed "$name" value
        bs_arr_push bs_args_selected "$value"
    fi

    bs_arr_to_args_to bs_args_selected __bs_args_fv_args
    eval "$__bs_args_fv_args"
    if ! eval "${array_name}=(\"\$@\")"; then
        log::error "args::flag_values: cannot assign array: ${array_name}"
        return "${E_INVALID:-2}"
    fi
    return "${E_SUCCESS:-0}"
}

# @description Разбор + выход: ошибка → bs::exit invalid, help → bs::exit success
# @description Parse + exit: an error → bs::exit invalid, help → bs::exit success
# @param $@ arguments / аргументы
args::require() {
    args::parse "$@" || bs::exit invalid
    if [[ "${ARGS_HELP_REQUESTED:-0}" == "1" ]]; then
        bs::exit success
    fi
    return "${E_SUCCESS:-0}"
}
