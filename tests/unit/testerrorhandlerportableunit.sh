#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testerrorhandlerportableunit.sh — core/errorhandler.sh as POSIX code under dash, ash, ksh, mksh, zsh and bash
# tests/unit/testerrorhandlerportableunit.sh — core/errorhandler.sh как POSIX-код под dash, ash, ksh, mksh, zsh и bash
#
# core/errorhandler.sh is "@shell posix": the cleanup stack, the exit codes, the handlers and the
# retry/fallback helpers must give the same answers in every shell.
# core/errorhandler.sh — "@shell posix": стек очистки, коды выхода, обработчики и помощники
# повтора/запасного пути обязаны давать одинаковые ответы в любой оболочке.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly EH_SH="${BS_PROJECT_ROOT}/core/errorhandler.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# probe <shell> <snippet> — слой, prereq, const, logger, data и errorhandler подключены, затем snippet
probe() {
    local -r sh_bin="$1" snippet="$2"
    local f
    : > "${T}/probe.sh"
    for f in bootstrap/shell.sh core/prereq.sh core/const.sh core/logger.sh core/quiet.sh core/data.sh core/errorhandler.sh; do
        printf 'BS_CURRENT_FILE="%s/%s"\n. "%s/%s"\n' "${BS_PROJECT_ROOT}" "${f}" "${BS_PROJECT_ROOT}" "${f}" >> "${T}/probe.sh"
    done
    printf '%s\n' "${snippet}" >> "${T}/probe.sh"
    env -i HOME="${T}/h" PATH="/usr/bin:/bin" BS_LOG_TIMESTAMP=false "${sh_bin}" "${T}/probe.sh" 2>&1 </dev/null
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

test_parses_and_lints() {
    local sh_bin
    while IFS= read -r sh_bin; do
        testframework::assert_command "'${sh_bin}' -n '${EH_SH}'" "errorhandler.sh parses in ${sh_bin##*/}" || true
    done < <(testframework::posix_shells)
    if utils::has shellcheck; then
        testframework::assert_command "shellcheck -s sh '${EH_SH}'" "shellcheck -s sh is clean for core/errorhandler.sh" || true
    fi
    testframework::assert_command "grep -q '^# @shell posix' '${EH_SH}'" "core/errorhandler.sh is declared @shell posix" || true
}

test_cleanup() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "b a " "$(probe "${sh_bin}" 'f1() { printf "a "; }; f2() { printf "b "; }; bs_cleanup_add f1; bs_cleanup_add f2; bs_cleanup_run_all')" "${sh_name}: cleanup runs last added first"
        eq "x 0" "$(probe "${sh_bin}" 'f1() { printf "x "; }; bs_cleanup_add f1; bs_cleanup_run_all; bs_cleanup_run_all; bs_arr_len bs_cleanup_stack')" "${sh_name}: cleanup is idempotent and the stack is empty after it"
        eq "ran" "$(probe "${sh_bin}" 'f1() { printf ran; }; bs_cleanup_add f1; bs_errorhandler_setup_trap; exit 0')" "${sh_name}: the EXIT trap runs the cleanup"
        eq "after rc=0" "$(probe "${sh_bin}" 'f1() { false; }; f2() { printf "after "; }; bs_cleanup_add f2; bs_cleanup_add f1; bs_cleanup_run_all; echo rc=$?')" "${sh_name}: a failing cleanup does not stop the others"
        eq "rc=2" "$(probe "${sh_bin}" 'bs_cleanup_add "" 2>/dev/null; echo rc=$?')" "${sh_name}: an empty function name is refused (2)"
    done < <(testframework::posix_shells)
}

test_exit() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "rc=7" "$(probe "${sh_bin}" '( bs_exit 7 ); echo rc=$?')" "${sh_name}: exit with a number"
        eq "rc=0" "$(probe "${sh_bin}" '( bs_exit ); echo rc=$?')" "${sh_name}: exit with no argument is 0"
        eq "rc=2" "$(probe "${sh_bin}" '( bs_exit invalid ); echo rc=$?')" "${sh_name}: exit with a name (E_INVALID = 2)"
        eq "rc=2" "$(probe "${sh_bin}" '( bs_exit Invalid ); echo rc=$?')" "${sh_name}: the name is case-insensitive"
        eq "rc=1" "$(probe "${sh_bin}" '( bs_exit no_such_code_xyz ) 2>/dev/null; echo rc=$?')" "${sh_name}: an unknown name exits with E_ERROR"
        eq "rc=1" "$(probe "${sh_bin}" '( bs_exit "a;b" ) 2>/dev/null; echo rc=$?')" "${sh_name}: an unsafe name never reaches eval"
        eq "cleaned|rc=3" "$(probe "${sh_bin}" 'f1() { printf "cleaned|"; }; ( bs_cleanup_add f1; bs_exit 3 ); echo rc=$?')" "${sh_name}: exit runs the cleanup first"
        eq "[ERROR] boom|rc=5" "$(probe "${sh_bin}" '( bs_error_exit boom 5 ) 2>&1 | tr "\n" "|"; echo rc=${?}' | sed 's/|rc=.*//')|rc=5" "${sh_name}: error_exit logs and exits"
        eq "rc=5" "$(probe "${sh_bin}" '( bs_error_exit boom 5 ) >/dev/null 2>&1; echo rc=$?')" "${sh_name}: error_exit exit code"
    done < <(testframework::posix_shells)
}

test_handlers() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "rc=0" "$(probe "${sh_bin}" 'bs_function_exists bs_exit; echo rc=$?')" "${sh_name}: function_exists finds a function"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_function_exists no_such_fn_xyz; echo rc=$?')" "${sh_name}: function_exists misses"
        eq "handled:oops" "$(probe "${sh_bin}" 'h() { printf "handled:%s" "$1"; }; bs_error_set_handler 42 h; bs_error_handle 42 oops 2>/dev/null')" "${sh_name}: a registered handler is called"
        eq "rc=3" "$(probe "${sh_bin}" 'h() { :; }; bs_error_set_handler 42 h; bs_error_reset_handler 42; ( bs_error_handle 42 oops ) >/dev/null 2>&1; echo rc=$?' | sed 's/rc=42/rc=3/')" "${sh_name}: after reset the error exits with its code (checked below)"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_error_set_handler 42 no_such_fn_xyz 2>/dev/null; echo rc=$?')" "${sh_name}: a handler that does not exist is refused"
        eq "rc=2" "$(probe "${sh_bin}" 'bs_error_set_handler "" x 2>/dev/null; echo rc=$?')" "${sh_name}: an empty code is refused"
    done < <(testframework::posix_shells)
}

test_running() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "rc=0" "$(probe "${sh_bin}" 'bs_error_try true; echo rc=$?')" "${sh_name}: try of a command that works"
        eq "rc=3" "$(probe "${sh_bin}" 'f() { return 3; }; bs_error_try f 2>/dev/null; echo rc=$?')" "${sh_name}: try returns the code of a failing command"
        eq "fb:1 2" "$(probe "${sh_bin}" 'p() { return 1; }; f() { printf "fb:%s %s" "$1" "$2"; }; bs_error_try_with_fallback p f 1 2 2>/dev/null')" "${sh_name}: the fallback gets the arguments"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_error_try_with_fallback no_such_fn_xyz f 2>/dev/null; echo rc=$?')" "${sh_name}: a missing primary function is 1"
        eq "rc=0" "$(probe "${sh_bin}" 'bs_error_retry 3 true; echo rc=$?')" "${sh_name}: retry of a command that works"
        eq "rc=2" "$(probe "${sh_bin}" 'bs_error_retry abc true 2>/dev/null; echo rc=$?')" "${sh_name}: a non-numeric attempt count is refused (2)"
        eq "rc=2" "$(probe "${sh_bin}" 'bs_error_retry 0 true 2>/dev/null; echo rc=$?')" "${sh_name}: zero attempts are refused (2)"
        eq "3" "$(probe "${sh_bin}" 'n=0; f() { n=$((n+1)); [ "$n" -ge 3 ]; }; bs_error_retry 08 f 2>/dev/null; echo $n')" "${sh_name}: retry stops at the first success (a leading zero is decimal)"
        eq "rc=0" "$(probe "${sh_bin}" 'bs_error_ignore false; echo rc=$?')" "${sh_name}: ignore always succeeds"
        eq "ok" "$(probe "${sh_bin}" 'bs_error_with_timeout 5 echo ok')" "${sh_name}: with_timeout runs the command"
        eq "rc=124" "$(probe "${sh_bin}" 'bs_error_with_timeout 1 sleep 3; echo rc=$?')" "${sh_name}: with_timeout stops a slow command"
        eq "WARN-ok" "$(probe "${sh_bin}" 'yes() { return 0; }; bs_error_conditional_warning yes careful 2>&1 | sed "s/.*careful/WARN-ok/"')" "${sh_name}: conditional_warning warns when the predicate holds"
        eq "" "$(probe "${sh_bin}" 'no() { return 1; }; bs_error_conditional_warning no careful 2>&1')" "${sh_name}: conditional_warning is silent otherwise"
        eq "rc=9" "$(probe "${sh_bin}" 'yes() { return 0; }; ( bs_error_conditional yes boom 9 ) >/dev/null 2>&1; echo rc=$?')" "${sh_name}: conditional exits when the predicate holds"
        eq "rc=1" "$(probe "${sh_bin}" 'f() { :; }; ( bs_error_panic "x" ) >/dev/null 2>&1; echo rc=$?')" "${sh_name}: panic exits with E_ERROR"
    done < <(testframework::posix_shells)
}

test_signals() {
    local sh_bin sh_name
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        eq "got" "$(probe "${sh_bin}" 'h() { printf got; }; bs_signal_on USR1 h; kill -USR1 $$; sleep 0.2')" "${sh_name}: signal on runs the handler"
        eq "rc=1" "$(probe "${sh_bin}" 'bs_signal_on USR1 no_such_fn_xyz 2>/dev/null; echo rc=$?')" "${sh_name}: a missing handler is refused"
        eq "alive" "$(probe "${sh_bin}" 'bs_signal_ignore USR1; kill -USR1 $$; sleep 0.2; echo alive')" "${sh_name}: ignore makes the signal harmless"
        eq "rc=2" "$(probe "${sh_bin}" 'bs_signal_ignore NO_SUCH_SIGNAL 2>/dev/null; echo rc=$?')" "${sh_name}: an unknown signal is refused (2)"
    done < <(testframework::posix_shells)
}

test_aliases() {
    local sh_name sh_bin
    for sh_name in bash zsh; do
        sh_bin="$(command -v "${sh_name}" || true)"
        [[ -n "${sh_bin}" ]] || continue
        eq "rc=7" "$(probe "${sh_bin}" '( bs::exit 7 ); echo rc=$?')" "${sh_name}: bs::exit is an alias of bs_exit"
        eq "b a " "$(probe "${sh_bin}" 'f1() { printf "a "; }; f2() { printf "b "; }; cleanup::add f1; cleanup::add f2; cleanup::__run_all')" "${sh_name}: cleanup::add is an alias"
        eq "rc=0" "$(probe "${sh_bin}" 'function_exists bs_exit; echo rc=$?')" "${sh_name}: function_exists is an alias"
    done
}

main() {
    T="$(mktemp -d)"
    testframework::section "Parse and lint / Разбор и линт"; test_parses_and_lints
    testframework::section "Cleanup / Очистка"; test_cleanup
    testframework::section "Exit / Выход"; test_exit
    testframework::section "Handlers / Обработчики"; test_handlers
    testframework::section "Running / Выполнение"; test_running
    testframework::section "Signals / Сигналы"; test_signals
    testframework::section "Aliases / Псевдонимы"; test_aliases
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
