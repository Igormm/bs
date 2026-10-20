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
