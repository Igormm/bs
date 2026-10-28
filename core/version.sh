#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: версия читается разбором строки (case и подстановки параметров) вместо [[ =~ ]] и массивов / valid POSIX sh: the version is read by parsing a line (case and parameter expansion) instead of [[ =~ ]] and arrays
# @tier core — builtins only; works everywhere
# @tier core — только builtin'ы; работает везде
#
# version.sh — Framework version information / Информация о версии фреймворка
#
# ИМЕНА / NAMES
#   Real functions: bs_version_print, bs_version_get, bs_version_of,
#   bs_version_compare; in bash and zsh also bs::version::* (the old names).
#   Настоящие функции: bs_version_print, bs_version_get, bs_version_of,
#   bs_version_compare; в bash и zsh — ещё и bs::version::* (прежние имена).

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

bs_guard VERSION || return 0

# @description BS Framework Version / Версия фреймворка BS
# @export BS_VERSION The current version of BS / Текущая версия BS
# Единственный источник BS_VERSION — этот модуль; bs и const.sh только используют
# Single source of BS_VERSION is this module; bs and const.sh only use it
if [ -z "${BS_VERSION:-}" ]; then
  export BS_VERSION="0.12.0"
fi

# @global BS_NAME — Env: framework full name (category: env)
# @global BS_NAME — Env: полное имя фреймворка (категория: env)
export BS_NAME="BS (Bash Open Source Architecture) BOSA Framework"

# @global BS_CODENAME — Env: release code name (category: env)
# @global BS_CODENAME — Env: кодовое название релиза (категория: env)
: "${BS_CODENAME:=Lingoa}"
export BS_CODENAME

# @description Print version information / Вывести информацию о версии
#   Version is read via bs::version::get (function), not the raw constant.
#   Версия читается через bs::version::get (функцию), не напрямую константу.
# @example
#   bs::version::print
bs_version_print() {
    printf 'BS Framework version: %s\n' "$(bs_version_get)"
}

# @description Get version as string / Получить версию как строку
# @return Version string / Строка версии
# @example
#   version=$(bs::version::get)
bs_version_get() {
    printf '%s\n' "${BS_VERSION}"
}

# @description Get the release code name / Получить кодовое название релиза
bs_version_codename() {
    printf '%s\n' "${BS_CODENAME}"
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
bs_version_of() {
    __bs_vo_file="${1:?directory required}/core/version.sh"
    [ -f "${__bs_vo_file}" ] || return 0
    # Ищем строку: [пробелы]export[пробелы]BS_VERSION="<непустое>"
    # Looking for the line: [spaces]export[spaces]BS_VERSION="<non-empty>"
    while IFS= read -r __bs_vo_line; do
        __bs_vo_line=${__bs_vo_line#"${__bs_vo_line%%[![:space:]]*}"}
        case "${__bs_vo_line}" in
            export[[:space:]]*)
                __bs_vo_line=${__bs_vo_line#export}
                __bs_vo_line=${__bs_vo_line#"${__bs_vo_line%%[![:space:]]*}"}
                case "${__bs_vo_line}" in
                    'BS_VERSION="'?*'"'*)
                        __bs_vo_line=${__bs_vo_line#'BS_VERSION="'}
                        __bs_vo_line=${__bs_vo_line%%'"'*}
                        if [ -n "${__bs_vo_line}" ]; then
                            printf '%s\n' "${__bs_vo_line}"
                            return 0
                        fi
                        ;;
                esac
                ;;
        esac
    done < "${__bs_vo_file}"
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
bs_version_compare() {
    __bs_vc_a=${1}
    __bs_vc_b=${2}

    # У версий разное число частей (1.0 vs 1.0.1): отсутствующие части
    # считаются 0, поэтому идём, пока есть хоть одна из версий.
    # Versions have different part counts (1.0 vs 1.0.1): missing parts
    # count as 0, so we walk while either version has parts left.
    while [ -n "${__bs_vc_a}" ] || [ -n "${__bs_vc_b}" ]; do
        __bs_vc_p1=${__bs_vc_a%%.*}
        __bs_vc_p2=${__bs_vc_b%%.*}
        case "${__bs_vc_a}" in *.*) __bs_vc_a=${__bs_vc_a#*.} ;; *) __bs_vc_a='' ;; esac
        case "${__bs_vc_b}" in *.*) __bs_vc_b=${__bs_vc_b#*.} ;; *) __bs_vc_b='' ;; esac

        # Нечисловой хвост части (суффикс "1.2.0-beta", "3rc1") отбрасываем с первой
        # не-цифры: "0-beta" -> 0, "3rc1" -> 3; ведущие нули убираем (не восьмеричные);
        # пустая часть = 0. Части сравниваем как числа, а не как строки: "10" > "9".
        # The non-numeric tail of a part (a suffix like "1.2.0-beta", "3rc1") is
        # cut at the first non-digit: "0-beta" -> 0, "3rc1" -> 3; leading zeros are
        # stripped (not octal); empty = 0. Parts are compared numerically, not as
        # strings: "10" > "9".
        __bs_vc_p1=${__bs_vc_p1%%[!0-9]*}
        __bs_vc_p2=${__bs_vc_p2%%[!0-9]*}
        __bs_vc_p1=${__bs_vc_p1#"${__bs_vc_p1%%[!0]*}"}
        __bs_vc_p2=${__bs_vc_p2#"${__bs_vc_p2%%[!0]*}"}
        __bs_vc_p1=${__bs_vc_p1:-0}
        __bs_vc_p2=${__bs_vc_p2:-0}

        if [ "${__bs_vc_p1}" -gt "${__bs_vc_p2}" ]; then
            return 1
        elif [ "${__bs_vc_p1}" -lt "${__bs_vc_p2}" ]; then
            return 2
        fi
    done

    return 0
}

bs_shell_alias bs_version_print bs::version::print
bs_shell_alias bs_version_get bs::version::get
bs_shell_alias bs_version_codename bs::version::codename
bs_shell_alias bs_version_of bs::version::of
bs_shell_alias bs_version_compare bs::version::compare
