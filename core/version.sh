#!/usr/bin/env bash
#
# version.sh — Framework version information / Информация о версии фреймворка
#

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# Core prerequisites
# Load core prerequisites if not already available
if ! declare -f bs::guard >/dev/null 2>&1; then
    source "$(dirname -- "${BASH_SOURCE[0]}")/prereq.sh"
fi
bs::guard "VERSION" || return 0

# @description BS Framework Version / Версия фреймворка BS
# @export BS_VERSION The current version of BS / Текущая версия BS
# Владелец переменной — скрипт bs (readonly); здесь задаём только если пусто
# Owner of the variable is the bs script (readonly); set here only if empty
if [[ -z "${BS_VERSION:-}" ]]; then
  export BS_VERSION="0.3.0"
fi

# @description BS Framework Name / Имя фреймворка BS
# @export BS_NAME The name of the BS framework / Имя фреймворка BS
export BS_NAME="BS (Bash Open Source Architecture) BOSA Framework"

# @description Print version information / Вывести информацию о версии
# @example
#   bs::version::print
bs::version::print() {
    printf '%s %s\n' "${BS_NAME}" "${BS_VERSION}"
}

# @description Get version as string / Получить версию как строку
# @return Version string / Строка версии
# @example
#   version=$(BS::version::get)
bs::version::get() {
    printf '%s\n' "${BS_VERSION}"
}

# @description Compare versions / Сравнить версии
# @param $1 First version / Первая версия
# @param $2 Second version / Вторая версия
# @return 0 if equal, 1 if first > second, 2 if first < second
# @example
#   if [[ $(BS::version::compare "0.1.0" "0.2.0") -eq 2 ]]; then
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

    # Determine max number of parts to compare
    local -i max_parts
    if [[ ${#v1_parts[@]} -gt ${#v2_parts[@]} ]]; then
        max_parts=${#v1_parts[@]}
    else
        max_parts=${#v2_parts[@]}
    fi

    # Compare each part numerically
    local -i i
    for ((i=0; i<max_parts; i++)); do
        local part1="${v1_parts[i]:-0}"
        local part2="${v2_parts[i]:-0}"

        # Ensure both parts are numeric for comparison
        part1="${part1//[^0-9]/0}"
        part2="${part2//[^0-9]/0}"

        if [[ 10#${part1} -gt 10#${part2} ]]; then
            return 1
        elif [[ 10#${part1} -lt 10#${part2} ]]; then
            return 2
        fi
    done

    # If we get here, versions are equal
    return 0
}