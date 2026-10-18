#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testconstportableunit.sh — core/const.sh as POSIX code under dash, zsh and bash
# tests/unit/testconstportableunit.sh — core/const.sh как POSIX-код под dash, zsh и bash
#
# core/const.sh is "@shell posix": the constants, their read-only status and the
# helper functions must be the same in every shell.
# core/const.sh — "@shell posix": константы, их неизменяемость и функции-помощники
# обязаны быть одинаковыми в любой оболочке.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly SHELL_SH="${BS_PROJECT_ROOT}/bootstrap/shell.sh"
readonly PREREQ_SH="${BS_PROJECT_ROOT}/core/prereq.sh"
readonly CONST_SH="${BS_PROJECT_ROOT}/core/const.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> <snippet> — shell.sh и prereq.sh подключены, const.sh — как его подключает загрузчик
# probe <shell> <snippet> — shell.sh and prereq.sh sourced, const.sh the way the loader sources it
probe() {
    local -r sh_bin="$1" snippet="$2"
    printf '. "%s"\n. "%s"\nBS_CURRENT_FILE="%s"\n. "%s"\nBS_CURRENT_FILE=""\n%s\n' \
        "${SHELL_SH}" "${PREREQ_SH}" "${CONST_SH}" "${CONST_SH}" "${snippet}" > "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

installed_shells() {
    testframework::posix_shells
}

test_parses_and_lints() {
    local bin
    while IFS= read -r bin; do
        testframework::assert_command "'${bin}' -n '${CONST_SH}'" "const.sh parses in ${bin##*/}" || true
    done < <(installed_shells 2>/dev/null)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${CONST_SH}'" "shellcheck -s sh is clean for core/const.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${CONST_SH}'" "core/const.sh is declared @shell posix" || true
    testframework::assert_command "! grep -v '^#' '${CONST_SH}' | grep -E 'ZSH_|FUNCNAME|declare|local -| \\[\\[ '" "no bash-only constructs in core/const.sh" || true
}

test_constants_per_shell() {
    local bin name esc
    esc="$(printf '\033')"
    while IFS= read -r bin; do
        name="${bin##*/}"
        eq "0 1 2 3 4 5 6 7 8 9 10 100 101 102 200 201 202 203 210" \
            "$(probe "${bin}" 'echo "$E_SUCCESS $E_ERROR $E_INVALID $LIB_ERROR_INVALID_ARGS $LIB_ERROR_INVALID_INPUT $LIB_ERROR_FILE_NOT_FOUND $LIB_ERROR_PERMISSION_DENIED $LIB_ERROR_DEPENDENCY $LIB_ERROR_UNSUPPORTED_OS $LIB_ERROR_TIMEOUT $LIB_ERROR_CONFLICT $LIB_ERROR_FILE_OPERATION $LIB_ERROR_DEPENDENCY_MISSING $LIB_ERROR_PLATFORM_UNSUPPORTED $INTEGRATION_ERROR_HTTP $INTEGRATION_ERROR_LLM $INTEGRATION_ERROR_K8S $INTEGRATION_ERROR_MISSING_DEPS $MODULE_ERROR_CONFIG"')" \
            "${name}: error codes"
        eq "${esc}[0m|${esc}[0;31m|${esc}[0;97m" \
            "$(probe "${bin}" 'printf "%s|%s|%s" "$COLOR_RESET" "$COLOR_RED" "$COLOR_BRIGHT_WHITE"')" "${name}: ANSI colours hold a real ESC byte"
        eq "/-\\|:█: :/etc:/var:/tmp:/usr/local:${T}/h:[a-zA-Z0-9._-]" \
            "$(probe "${bin}" 'printf "%s:%s:%s:%s:%s:%s:%s:%s:%s" "$SPINNER_CHARS" "$PROGRESS_BLOCK" "$PROGRESS_EMPTY" "$SYS_ETC" "$SYS_VAR" "$SYS_TMP" "$SYS_USR_LOCAL" "$SYS_HOME" "$FILENAME_ALLOWED_CHARS"')" \
            "${name}: formatting, path and regex constants"
        eq "false false" "$(probe "${bin}" 'echo "$FRAMEWORK_DEBUG $FRAMEWORK_DRY_RUN"')" "${name}: framework flags default to false"
        eq "yes" "$(probe "${bin}" 'bs_guard_loaded CONST && bs_guard_loaded VERSION && echo yes')" "${name}: guard marks of CONST and the pulled-in VERSION"
        eq "${BS_VERSION}" "$(probe "${bin}" 'bs_const_version')" "${name}: bs_const_version is the version from version.sh"
        eq "unset" "$(probe "${bin}" '[ -n "${__bs_esc+x}" ] && echo leaked || echo unset')" "${name}: the ESC helper variable does not leak"
    done < <(installed_shells 2>/dev/null)
}

test_distros_per_shell() {
    local bin name
    while IFS= read -r bin; do
        name="${bin##*/}"
        case "${name}" in
            bash) eq "6 centos ubuntu" "$(probe "${bin}" 'echo "${#SUPPORTED_DISTROS[@]} ${SUPPORTED_DISTROS[1]} ${SUPPORTED_DISTROS[5]}"')" "${name}: SUPPORTED_DISTROS is an array of 6" ;;
            zsh)  eq "6 centos ubuntu" "$(probe "${bin}" 'echo "${#SUPPORTED_DISTROS[@]} ${SUPPORTED_DISTROS[2]} ${SUPPORTED_DISTROS[6]}"')" "${name}: SUPPORTED_DISTROS is an array of 6" ;;
            *)    eq "alma centos rhel fedora debian ubuntu" "$(probe "${bin}" 'echo "$SUPPORTED_DISTROS"')" "${name}: no arrays — a space-separated string" ;;
        esac
    done < <(installed_shells 2>/dev/null)
}

test_readonly_per_shell() {
    local bin name
    while IFS= read -r bin; do
        name="${bin##*/}"
        eq "readonly readonly readonly" \
            "$(probe "${bin}" '(unset E_ERROR) 2>/dev/null && printf writable || printf readonly; printf " "; (unset COLOR_RED) 2>/dev/null && printf writable || printf readonly; printf " "; (unset FILENAME_ALLOWED_CHARS) 2>/dev/null && printf writable || printf readonly')" \
            "${name}: constants are read-only"
        # из функции (так загрузчик подключает модуль) — константы всё равно глобальные
        # from a function (the way the loader sources a module) the constants are still global
        printf '. "%s"\n. "%s"\nload_it() { BS_CURRENT_FILE="%s"; . "%s"; }\nload_it\necho "$E_ERROR"\n(unset E_ERROR) 2>/dev/null && echo writable || echo readonly\n' "${SHELL_SH}" "${PREREQ_SH}" "${CONST_SH}" "${CONST_SH}" > "${T}/probe2.sh"
        eq "1 readonly" "$(env -i HOME="${T}/h" PATH="/usr/bin:/bin" "${bin}" "${T}/probe2.sh" 2>&1 | tr '\n' ' ' | sed 's/ $//')" "${name}: sourced from inside a function the constants stay global and read-only"
    done < <(installed_shells 2>/dev/null)
}

test_functions_per_shell() {
    local bin name
    while IFS= read -r bin; do
        name="${bin##*/}"
        eq "0 0 0 1 1 1 " "$(probe "${bin}" 'for c in 0 5 210; do bs_const_is_valid_error_code "$c"; printf "%s " $?; done; for c in 11 abc 999; do bs_const_is_valid_error_code "$c"; printf "%s " $?; done')" "${name}: bs_const_is_valid_error_code"
        eq "Success / Успешно|File not found / Файл не найден|Configuration error / Ошибка конфигурации|Unknown error / Неизвестная ошибка" \
            "$(probe "${bin}" 'printf "%s|%s|%s|%s" "$(bs_const_error_description 0)" "$(bs_const_error_description 5)" "$(bs_const_error_description 210)" "$(bs_const_error_description 999)"')" "${name}: bs_const_error_description"
        case "${name}" in
            bash|zsh) eq "0 1 ${BS_VERSION}" "$(probe "${bin}" 'const::is_valid_error_code 5; a=$?; const::is_valid_error_code 99; b=$?; echo "$a $b $(const::version)"')" "${name}: const::* names are aliases" ;;
            *)        eq "absent" "$(probe "${bin}" 'type const::version >/dev/null 2>&1 && echo present || echo absent')" "${name}: no const::* (the name is not valid here)" ;;
        esac
    done < <(installed_shells 2>/dev/null)
}

main() {
    print_header "core/const portable Unit Tests / Модульные тесты core/const в разных оболочках"
    testframework::init
    T="$(mktemp -d)"
    trap 'rm -rf "${T}"' EXIT
    mkdir -p "${T}/h"

    testframework::section "Parse and lint / Разбор и линтер"
    test_parses_and_lints
    testframework::section "Constants per shell / Константы по оболочкам"
    test_constants_per_shell
    testframework::section "SUPPORTED_DISTROS per shell / SUPPORTED_DISTROS по оболочкам"
    test_distros_per_shell
    testframework::section "Read-only / Неизменяемость"
    test_readonly_per_shell
    testframework::section "Functions per shell / Функции по оболочкам"
    test_functions_per_shell

    testframework::summary
}

main "$@"
