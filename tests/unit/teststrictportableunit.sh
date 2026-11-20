#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/teststrictportableunit.sh — core/strict.sh (entry-point strict mode) under dash, ash, ksh, mksh, zsh and bash
# tests/unit/teststrictportableunit.sh — core/strict.sh (строгий режим точки входа) под dash, ash, ksh, mksh, zsh и bash
#
# core/strict.sh is "@shell posix": strict::enable must give the same guarantees in every shell —
# errexit/nounset, pipefail where the shell has it, the entry-point IFS, EXIT cleanup everywhere,
# an ERR backtrace where the shell has ERR, and honest per-shell differences in strict::status.
# core/strict.sh — "@shell posix": strict::enable обязан давать одинаковые гарантии в любой оболочке —
# errexit/nounset, pipefail где он есть, IFS точки входа, EXIT-очистка везде, ERR-трассировка где
# оболочка умеет ERR, и честные различия оболочек в strict::status.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly STRICT_SH="${BS_PROJECT_ROOT}/core/strict.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> <snippet> — слой, prereq, errorhandler (тянет зависимости) и strict подключены
# probe <shell> <snippet> — the layer, prereq, errorhandler (pulls its deps) and strict are sourced
probe() {
    local -r sh_bin="$1" snippet="$2"
    local f
    : > "${T}/probe.sh"
    for f in bootstrap/shell.sh core/prereq.sh core/errorhandler.sh core/strict.sh; do
        printf 'BS_CURRENT_FILE="%s/%s"\n. "%s/%s"\n' "${BS_PROJECT_ROOT}" "${f}" "${BS_PROJECT_ROOT}" "${f}" >> "${T}/probe.sh"
    done
    printf '%s\n' "${snippet}" >> "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" "${sh_bin}" "${T}/probe.sh" 2>&1
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

# probe_has <shell> <snippet> <pattern> — yes/no; the probe may exit non-zero (that is
# the point of half the checks), so the output is captured BEFORE grep: under the
# test's own pipefail a "probe | grep -q && printf yes" pipeline would die on the probe's code
probe_has() {
    local out
    out="$(probe "$1" "$2" || true)"
    if grep -q "$3" <<< "${out}"; then printf yes; else printf no; fi
}

# has_cap <shell> <snippet> — yes/no, the capability is probed independently of the module
has_cap() {
    local -r sh_bin="$1" snippet="$2"
    if env -i PATH="/usr/bin:/bin" "${sh_bin}" -c "${snippet}" >/dev/null 2>&1; then
        printf yes
    else
        printf no
    fi
}

test_parses_and_lints() {
    local sh_bin
    while IFS= read -r sh_bin; do
        testframework::assert_command "'${sh_bin}' -n '${STRICT_SH}'" "strict.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh --severity=error '${STRICT_SH}'" "shellcheck -s sh has no errors for core/strict.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${STRICT_SH}'" "core/strict.sh is declared @shell posix" || true
}

test_flags_and_ifs() {
    local sh_bin sh_name cap
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "" "$(probe "${sh_bin}" 'bs_strict_enable; false; echo unreachable' | grep unreachable)" "${sh_name}: errexit stops the script on a failure"
        eq "" "$(probe "${sh_bin}" 'bs_strict_enable; printf "%s" "$__bs_strict_no_such_var"; echo unreachable' | grep unreachable)" "${sh_name}: nounset stops the script on an unset variable"
        eq "ifs-ok" "$(probe "${sh_bin}" 'bs_strict_enable; case "$IFS" in "$(printf "\n\t")") printf ifs-ok ;; esac')" "${sh_name}: IFS is newline+tab"
        cap="$(has_cap "${sh_bin}" '(set -o pipefail) 2>/dev/null')"
        if [[ "${cap}" = yes ]]; then
            eq "" "$(probe "${sh_bin}" 'bs_strict_enable; false | cat; echo unreachable' | grep unreachable)" "${sh_name}: pipefail catches the left side of a pipe"
            eq "pipefail=on" "$(probe "${sh_bin}" 'bs_strict_enable; bs_strict_status | grep "^pipefail="')" "${sh_name}: status reports pipefail=on"
        else
            eq "unreachable" "$(probe "${sh_bin}" 'bs_strict_enable; false | cat; echo unreachable' | grep unreachable)" "${sh_name}: without pipefail the pipe succeeds (honest shell limit)"
            eq "pipefail=unsupported" "$(probe "${sh_bin}" 'bs_strict_enable; bs_strict_status | grep "^pipefail="')" "${sh_name}: status reports pipefail=unsupported"
        fi
        eq "errexit=on" "$(probe "${sh_bin}" 'bs_strict_enable; bs_strict_status | grep "^errexit="')" "${sh_name}: status reports errexit=on"
        eq "nounset=on" "$(probe "${sh_bin}" 'bs_strict_enable; bs_strict_status | grep "^nounset="')" "${sh_name}: status reports nounset=on"
    done < <(testframework::posix_shells)
}

test_traps_and_cleanup() {
    local sh_bin sh_name cap
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "done cleaned" "$(probe "${sh_bin}" 'bs_strict_enable; marker_fn() { printf " cleaned"; }; bs_cleanup_add marker_fn; printf done')" "${sh_name}: the EXIT trap runs the cleanup stack on success"
        eq "yes" "$(probe_has "${sh_bin}" 'bs_strict_enable; marker_fn() { printf cleaned; }; bs_cleanup_add marker_fn; false' cleaned)" "${sh_name}: the cleanup runs on a failure too"
        eq "alive" "$(probe "${sh_bin}" 'bs_strict_enable; if false; then echo bad; fi; echo alive' | grep -o alive)" "${sh_name}: a conditional failure does not trigger the traps"
        eq "handled alive" "$(probe "${sh_bin}" 'bs_strict_enable; false || printf "handled "; echo alive' | tr -d "\n" | grep -o "handled alive")" "${sh_name}: a handled failure (||) keeps the script alive"
        eq "" "$(probe "${sh_bin}" 'bs_strict_enable; marker_fn() { printf cleaned; }; bs_cleanup_add marker_fn; kill -TERM $$; echo unreachable' | grep unreachable)" "${sh_name}: TERM ends the script (code 143) and the cleanup runs"
        cap="$(has_cap "${sh_bin}" '(trap ":" ERR) 2>/dev/null')"
        if [[ "${cap}" = yes ]]; then
            eq "yes" "$(probe_has "${sh_bin}" 'bs_strict_enable; false' Backtrace)" "${sh_name}: the ERR trap reports a backtrace"
            eq "yes" "$(probe_has "${sh_bin}" 'bs_strict_enable; bs_strict_status' 'traps=.*ERR')" "${sh_name}: status lists the ERR trap"
        else
            eq "" "$(probe "${sh_bin}" 'bs_strict_enable; false' | grep Backtrace)" "${sh_name}: no ERR trap in this shell — no backtrace (honest)"
        fi
        eq "ok" "$(probe "${sh_bin}" 'bs_strict_enable; bs_strict_enable; printf ok')" "${sh_name}: a repeated enable is safe"
    done < <(testframework::posix_shells)
}

test_debug() {
    local sh_bin sh_name cap
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        # Способность оболочки: переживает ли set -x из функции возврат (mksh/zsh — нет)
        # Shell capability: does set -x from a function survive its return (mksh/zsh: no)
        if env -i PATH="/usr/bin:/bin" "${sh_bin}" -c 'f() { set -x; }; f; echo marker' 2>&1 | grep "^+" | grep -q marker; then
            cap=yes
        else
            cap=no
        fi
        if [[ "${cap}" = yes ]]; then
            eq "yes" "$(probe_has "${sh_bin}" 'BS_DEBUG=1; bs_strict_enable; echo traced' '^+')" "${sh_name}: BS_DEBUG=1 turns on set -x tracing"
            eq "debug=on" "$(probe "${sh_bin}" 'BS_DEBUG=1; bs_strict_enable; bs_strict_status' | grep "^debug=")" "${sh_name}: status reports debug=on"
        else
            eq "debug=off" "$(probe "${sh_bin}" 'BS_DEBUG=1; bs_strict_enable; bs_strict_status' | grep "^debug=")" "${sh_name}: xtrace is function-local here — status honestly reports debug=off"
        fi
        eq "" "$(probe "${sh_bin}" 'bs_strict_enable; echo traced' | grep "^+")" "${sh_name}: without BS_DEBUG there is no tracing"
    done < <(testframework::posix_shells)
}

test_aliases() {
    local sh_bin
    for sh_bin in bash zsh; do
        command -v "${sh_bin}" >/dev/null 2>&1 || continue
        eq "ok" "$(probe "${sh_bin}" 'strict::enable; strict::status >/dev/null; printf ok')" "${sh_bin}: strict::* aliases work"
    done
}

main() {
    T="$(mktemp -d)"
    mkdir -p "${T}/h"
    testframework::section "Parses and lints / Разбор и линт"; test_parses_and_lints
    testframework::section "Flags and IFS / Флаги и IFS"; test_flags_and_ifs
    testframework::section "Traps and cleanup / Ловушки и очистка"; test_traps_and_cleanup
    testframework::section "Debug / Отладка"; test_debug
    testframework::section "Aliases / Псевдонимы"; test_aliases
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
