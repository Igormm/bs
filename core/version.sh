#!/usr/bin/env bash
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], arithmetic command (( )), array, local/declare flags / needs bash constructs: double-bracket [[ ]], arithmetic command (( )), array, local/declare flags
#
# version.sh — Framework version information / Информация о версии фреймворка
#

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

bs::guard "VERSION" || return 0

# @description BS Framework Version / Версия фреймворка BS
# @export BS_VERSION The current version of BS / Текущая версия BS
# Единственный источник BS_VERSION — этот модуль; bs и const.sh только используют
# Single source of BS_VERSION is this module; bs and const.sh only use it
if is::empty "${BS_VERSION:-}"; then
  export BS_VERSION="0.7.4"
fi

# @global BS_NAME — Env: framework full name (category: env)
# @global BS_NAME — Env: полное имя фреймворка (категория: env)
export BS_NAME="BS (Bash Open Source Architecture) BOSA Framework"

# @description Print version information / Вывести информацию о версии
#   Version is read via bs::version::get (function), not the raw constant.
#   Версия читается через bs::version::get (функцию), не напрямую константу.
# @example
#   bs::version::print
bs::version::print() {
    printf 'BS Framework version: %s\n' "$(bs::version::get)"
}

# @description Get version as string / Получить версию как строку
# @return Version string / Строка версии
# @example
#   version=$(bs::version::get)
bs::version::get() {
    printf '%s\n' "${BS_VERSION}"
}

# @description Version of another BS directory (a repository, an installed
#   copy, a downloaded source). It only READS core/version.sh: no code from
#   that directory is run.
# @description Версия другого каталога BS (репозитория, установленной копии,
#   скачанного источника). Только ЧИТАЕТ core/version.sh: код из этого
#   каталога не запускается.
# @param $1 BS directory / Каталог BS
# @stdout Version string; empty if the directory has no readable version
# @return 0 always
# @example
#   installed=$(bs::version::of "$HOME/.local/lib/bs")
bs::version::of() {
    local -r file="${1:?directory required}/core/version.sh"
    local -r re='^[[:space:]]*export[[:space:]]+BS_VERSION="([^"]+)"'
    local line
    [[ -f "${file}" ]] || return 0
    while IFS= read -r line; do
        if [[ "${line}" =~ ${re} ]]; then
            printf '%s\n' "$(bs::regex::group 1)"
            return 0
        fi
    done < "${file}"
    return 0
}

# @description Compare versions / Сравнить версии
# @param $1 First version / Первая версия
# @param $2 Second version / Вторая версия
# @return 0 if equal, 1 if first > second, 2 if first < second
# @example
#   rc=0; bs::version::compare "0.1.0" "0.2.0" || rc=$?   # the result is the exit code, not stdout
#   if (( rc == 2 )); then
#       echo "First version is older"
#   fi
bs::version::compare() {
    local -r ver1="${1}"
    local -r ver2="${2}"

    # Split versions into arrays (локальный IFS, глобальный не трогаем)
    # Split versions into arrays (local IFS, global IFS untouched)
    local IFS='.'
    local -a v1_parts v2_parts
    read -ra v1_parts <<< "${ver1}"
    read -ra v2_parts <<< "${ver2}"

    # У версий разное число частей (1.0 vs 1.0.1): отсутствующие части
    # считаются 0, поэтому сравниваем до самой длинной версии.
    # Versions have different part counts (1.0 vs 1.0.1): missing parts
    # count as 0, so we compare up to the longest version.
    local -i max_parts
    if [[ ${#v1_parts[@]} -gt ${#v2_parts[@]} ]]; then
        max_parts=${#v1_parts[@]}
    else
        max_parts=${#v2_parts[@]}
    fi

    # Части сравниваем как числа, а не как строки: иначе "10" < "9".
    # Parts are compared numerically, not as strings: otherwise "10" < "9".
    local -i i
    for ((i=0; i<max_parts; i++)); do
        local part1="${v1_parts[i]:-0}"
        local part2="${v2_parts[i]:-0}"

        # Нечисловой хвост части (суффикс "1.2.0-beta", "3rc1") отбрасываем с первой
        # не-цифры: "0-beta" -> 0, "3rc1" -> 3; пустая часть = 0.
        # The non-numeric tail of a part (a suffix like "1.2.0-beta", "3rc1") is
        # cut at the first non-digit: "0-beta" -> 0, "3rc1" -> 3; empty = 0.
        part1="${part1%%[!0-9]*}"
        part2="${part2%%[!0-9]*}"
        part1="${part1:-0}"
        part2="${part2:-0}"

        if [[ 10#${part1} -gt 10#${part2} ]]; then
            return 1
        elif [[ 10#${part1} -lt 10#${part2} ]]; then
            return 2
        fi
    done

    return 0
}