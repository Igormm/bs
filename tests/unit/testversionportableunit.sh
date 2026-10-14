#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testversionportableunit.sh — core/version.sh as POSIX code under dash, zsh and bash
# tests/unit/testversionportableunit.sh — core/version.sh как POSIX-код под dash, zsh и bash
#
# core/version.sh is "@shell posix": parsing, the version line reader and the
# comparison must give the same answers in every shell.
# core/version.sh — "@shell posix": разбор, чтение строки версии и сравнение
# обязаны давать одинаковые ответы в любой оболочке.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly SHELL_SH="${BS_PROJECT_ROOT}/bootstrap/shell.sh"
readonly PREREQ_SH="${BS_PROJECT_ROOT}/core/prereq.sh"
readonly VERSION_SH="${BS_PROJECT_ROOT}/core/version.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> <snippet> — shell.sh, prereq.sh и version.sh подключены, затем snippet
probe() {
    local -r sh_bin="$1" snippet="$2"
    printf '. "%s"\n. "%s"\n. "%s"\n%s\n' "${SHELL_SH}" "${PREREQ_SH}" "${VERSION_SH}" "${snippet}" > "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

installed_shells() {
    local n
    for n in bash zsh dash; do
        command -v "${n}" 2>/dev/null || printf 'skip: %s is not installed / не установлен\n' "${n}" >&2
    done
}

test_parses_and_lints() {
    local bin
    while IFS= read -r bin; do
        testframework::assert_command "'${bin}' -n '${VERSION_SH}'" "version.sh parses in ${bin##*/}" || true
    done < <(installed_shells 2>/dev/null)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${VERSION_SH}'" "shellcheck -s sh is clean for core/version.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${VERSION_SH}'" "core/version.sh is declared @shell posix" || true
    testframework::assert_command "! grep -v '^#' '${VERSION_SH}' | grep -E 'BASH_|ZSH_|FUNCNAME|declare| \\[\\[ |is::empty'" "no shell-specific constructs in core/version.sh" || true
}

test_compare_per_shell() {
    local bin name case_
    # "первая вторая ожидаемый-код": 0 равны, 1 первая больше, 2 первая меньше
    # "first second expected-code": 0 equal, 1 first greater, 2 first lower
    local -a table=(
        "0.3.0 0.3.0 0" "0.3.0 0.10.0 2" "0.10.0 0.3.0 1" "1.0 1.0.0 0" "1.0.1 1.0 1"
        "2.0.0 1.9.9 1" "1.2.3rc1 1.2.9 2" "0.8.0-rc1 0.8.0 0" "v0.10.0 0.9.0 1"
        "01.08.0 1.8.0 0" "1.09 1.9 0" "1..2 1.0.2 0" "10.0 9.0 1" "0 0.0.0 0"
    )
    while IFS= read -r bin; do
        name="${bin##*/}"
        local got="" want=""
        for case_ in "${table[@]}"; do
            local a b w
            IFS=' ' read -r a b w <<< "${case_}"
            got+="$(probe "${bin}" "bs_version_compare '${a}' '${b}'; echo \$?") "
            want+="${w} "
        done
        eq "${want}" "${got}" "${name}: bs_version_compare, ${#table[@]} cases (parts compared as numbers, suffix cut, leading zeros decimal)"
    done < <(installed_shells 2>/dev/null)
}

test_get_print_per_shell() {
    local bin name
    while IFS= read -r bin; do
        name="${bin##*/}"
        eq "${BS_VERSION}" "$(probe "${bin}" 'bs_version_get')" "${name}: bs_version_get is BS_VERSION from the file"
        eq "BS Framework version: ${BS_VERSION}" "$(probe "${bin}" 'bs_version_print')" "${name}: bs_version_print"
        eq "9.9.9" "$(probe "${bin}" 'BS_VERSION=9.9.9; bs_version_get')" "${name}: an exported BS_VERSION wins over the default"
        eq "1" "$(probe "${bin}" 'bs_guard_loaded VERSION && echo 1')" "${name}: the module sets its guard mark"
    done < <(installed_shells 2>/dev/null)
}

test_of_per_shell() {
    local bin name
    mkdir -p "${T}/v1/core" "${T}/v2/core" "${T}/v3/core" "${T}/v4/core"
    printf 'touch "%s/executed"\nexport BS_VERSION="9.8.7"\n' "${T}" > "${T}/v1/core/version.sh"
    printf '  \texport   BS_VERSION="1.2.3"   # trailing\n' > "${T}/v2/core/version.sh"
    printf 'exportBS_VERSION="5"\nexport BS_VERSION=""\nBS_VERSION="6"\nexport BS_VERSION=7\n' > "${T}/v3/core/version.sh"
    printf '# comment\nexport BS_NAME="x"\nexport BS_VERSION="4.5.6"\nexport BS_VERSION="7.7.7"\n' > "${T}/v4/core/version.sh"
    while IFS= read -r bin; do
        name="${bin##*/}"
        eq "9.8.7" "$(probe "${bin}" "bs_version_of '${T}/v1'")" "${name}: bs_version_of reads another directory"
        testframework::assert_command "test ! -e '${T}/executed'" "${name}: bs_version_of runs no code from that directory" || true
        eq "1.2.3" "$(probe "${bin}" "bs_version_of '${T}/v2'")" "${name}: indentation and trailing text are tolerated"
        eq "" "$(probe "${bin}" "bs_version_of '${T}/v3'")" "${name}: near-misses (no space, empty, no export, no quotes) give nothing"
        eq "4.5.6" "$(probe "${bin}" "bs_version_of '${T}/v4'")" "${name}: the first matching line wins"
        eq "" "$(probe "${bin}" "bs_version_of '${T}/missing'")" "${name}: a missing directory is empty, status 0"
        eq "${BS_VERSION}" "$(probe "${bin}" "bs_version_of '${BS_PROJECT_ROOT}'")" "${name}: the repository version equals BS_VERSION"
    done < <(installed_shells 2>/dev/null)
}

test_namespaced_aliases() {
    local bin name
    while IFS= read -r bin; do
        name="${bin##*/}"
        case "${name}" in
            bash|zsh) eq "2 ${BS_VERSION}" "$(probe "${bin}" 'bs::version::compare 0.1.0 0.2.0; r=$?; echo "$r $(bs::version::get)"')" "${name}: bs::version::* are aliases" ;;
            *)        eq "absent" "$(probe "${bin}" 'type bs::version::get >/dev/null 2>&1 && echo present || echo absent')" "${name}: no bs::version::* (the name is not valid here)" ;;
        esac
    done < <(installed_shells 2>/dev/null)
}

main() {
    print_header "core/version portable Unit Tests / Модульные тесты core/version в разных оболочках"
    testframework::init
    T="$(mktemp -d)"
    trap 'rm -rf "${T}"' EXIT
    mkdir -p "${T}/h"

    testframework::section "Parse and lint / Разбор и линтер"
    test_parses_and_lints
    testframework::section "bs_version_compare per shell / bs_version_compare по оболочкам"
    test_compare_per_shell
    testframework::section "get and print / get и print"
    test_get_print_per_shell
    testframework::section "bs_version_of per shell / bs_version_of по оболочкам"
    test_of_per_shell
    testframework::section "bs::version::* aliases / Псевдонимы bs::version::*"
    test_namespaced_aliases

    testframework::summary
}

main "$@"
