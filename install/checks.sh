#!/usr/bin/env bash
# @tier core — bash 4+ only (gated by bootstrap/bs.sh), works everywhere
# @tier core — только bash 4+ (гейт в bootstrap/bs.sh), работает везде
# @shell bash4 — installer code: runs in bash 4.2+, writes PATH/rc for the shell of the USER (bootstrap/shell.sh)
# @shell bash4 — код установщика: исполняется в bash 4.2+, пишет PATH/rc для оболочки ПОЛЬЗОВАТЕЛЯ (bootstrap/shell.sh)

# Environment checking functions for the installer

# Check if already installed
is_already_installed() {
  is::dir "${TARGET_LIB}" && is::file "${TARGET_BIN}"
}

# Имя интерпретатора, который исполняет установщик (по реестру оболочек).
# Это НЕ оболочка пользователя: пользовательская — bs_shell_user.
# The interpreter that runs the installer (from the shell registry). This is
# NOT the user's shell: that one is bs_shell_user.
get_current_shell_name() {
    bs_shell_family
}

# check_shell_environment
#
# Установщик исполняется только в bash 4.2+: точка входа сама перезапускается
# в нём (bootstrap/trampoline.sh), а гейт bootstrap/bs.sh отсекает старые
# версии. Здесь остаётся проверка целостности — и оболочка ПОЛЬЗОВАТЕЛЯ, для
# которой дальше настраиваются PATH и подсказки.
# The installer runs only in bash 4.2+: the entry point re-runs itself in it
# (bootstrap/trampoline.sh) and the bootstrap/bs.sh gate rejects old versions.
# What remains is an integrity check. The USER's shell (PATH and hints are set
# up for it) is computed later and lazily — after the arguments are parsed,
# because --shell can set it.
check_shell_environment() {
    local shell_name
    shell_name="$(get_current_shell_name)"

    if ! bs_shell_host_ok; then
        printf "ERROR: установщик исполняется в '%s', а нужен bash 4.2+ / the installer runs in '%s', bash 4.2+ is needed\n" \
            "${shell_name}" "${shell_name}" >&2
        printf "Запустите / Run: bash %s\n" "$0" >&2
        exit 1
    fi

    # Сохраняем для других функций
    readonly CURRENT_SHELL="$shell_name"
}
