#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testtrampolineunit.sh — entry points under bash, zsh, dash, bash-as-sh
# tests/unit/testtrampolineunit.sh — точки входа под bash, zsh, dash, bash как sh
#
# `sh install.sh`, `dash ./bs`, `zsh ./bs`, bash started as `sh` (POSIX mode):
# bootstrap/trampoline.sh must re-run the entry point in a capable bash with the
# same arguments, or explain what to install. Every case runs under env -i.
# `sh install.sh`, `dash ./bs`, `zsh ./bs`, bash, запущенный как `sh` (режим
# POSIX): bootstrap/trampoline.sh обязан перезапустить точку входа в подходящем
# bash с теми же аргументами либо объяснить, что установить.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

T=""
OUT=""
RC=0

# run <interpreter> <args...>  — OUT и RC
run() {
    RC=0
    OUT="$(cd "${BS_PROJECT_ROOT}" && env -i HOME="${T}/home" PATH="/usr/bin:/bin" \
        ${RUN_ENV:-} "$@" 2>&1 </dev/null)" || RC=$?
}

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }
has() {
    if [[ "${OUT}" == *"$1"* ]]; then
        testframework::assert_true "true" "$2" || true
    else
        testframework::assert_true "false" "$2" || true
        printf '    not found / не найдено: %s\n    output / вывод:\n%s\n' "$1" "${OUT}" | head -12
    fi
}
lacks() {
    if [[ "${OUT}" == *"$1"* ]]; then
        testframework::assert_true "false" "$2" || true
        printf '    unexpectedly found / найдено, а не должно: %s\n' "$1"
    else
        testframework::assert_true "true" "$2" || true
    fi
}

shell_bin() { command -v "$1" 2>/dev/null || true; }

test_prologue_identical() {
    local f sum first=""
    for f in bs install.sh boot.sh; do
        sum="$(awk '/^# --- POSIX-пролог/{p=1} p{print} /^# --- конец пролога/{exit}' "${BS_PROJECT_ROOT}/${f}" | sha256sum | cut -c1-16)"
        testframework::assert_true "'${sum}' != 'e3b0c44298fc1c14'" "${f} has the prologue" || true
        if [[ -z "${first}" ]]; then first="${sum}"; else eq "${first}" "${sum}" "the prologue of ${f} equals the one of bs"; fi
    done
}

test_entry_points_under_shells() {
    local sh_name sh_bin
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        run "${sh_bin}" ./bs version
        eq "0" "${RC}" "${sh_name} ./bs version: exit 0"
        has "BS Framework version:" "${sh_name} ./bs version: prints the version"
        lacks "Bad substitution" "${sh_name} ./bs version: no syntax noise"
        run "${sh_bin}" ./install.sh --help
        eq "0" "${RC}" "${sh_name} ./install.sh --help: exit 0"
        has "BS installer" "${sh_name} ./install.sh --help: the usage"
        run "${sh_bin}" ./boot.sh version
        has "BS Framework version:" "${sh_name} ./boot.sh version: hands over to bs"
    done < <(testframework::posix_shells)
}

test_bash_as_sh() {
    # bash, вызванный как sh, работает в режиме POSIX — пролог перезапускает его
    # bash invoked as sh runs in POSIX mode — the prologue re-runs it
    ln -sf "$(shell_bin bash)" "${T}/sh"
    run "${T}/sh" ./bs version
    eq "0" "${RC}" "bash-as-sh ./bs version: exit 0"
    has "BS Framework version:" "bash-as-sh ./bs version: works"
    run "${T}/sh" ./install.sh --help
    has "BS installer" "bash-as-sh ./install.sh --help: works"
}

test_arguments_survive() {
    local sh_name sh_bin
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        # bs calc ведёт к dc / bs calc ends in dc
        utils::has dc || { testframework::skip "${sh_name}: an argument with spaces arrives intact" "dc is not installed / dc не установлен"; continue; }
        run "${sh_bin}" ./bs calc '2 3 + 4 *'
        eq "20" "${OUT}" "${sh_name}: an argument with spaces arrives intact"
    done < <(testframework::posix_shells 2>/dev/null)
    local dash_bin; dash_bin="$(shell_bin dash)"
    if [[ -n "${dash_bin}" ]]; then
        printf '#!/usr/bin/env bs\nload "lib/io/streams"\nio::streams::print "[$1][$2]"\n' > "${T}/args.sh"
        run "${dash_bin}" ./bs run "${T}/args.sh" 'a b' "c'd"
        eq "[a b][c'd]" "${OUT}" "dash: spaces and quotes in script arguments survive"
    fi
}

test_symlink() {
    local dash_bin; dash_bin="$(shell_bin dash)"
    [[ -n "${dash_bin}" ]] || return 0
    mkdir -p "${T}/links"
    ln -sf "${BS_PROJECT_ROOT}/bs" "${T}/links/bs"
    run "${dash_bin}" "${T}/links/bs" version
    has "BS Framework version:" "a symlinked entry point is resolved (readlink -f)"
}

test_no_host() {
    local dash_bin; dash_bin="$(shell_bin dash)"
    [[ -n "${dash_bin}" ]] || return 0
    RUN_ENV="BS_HOST_BASH=/nonexistent" run "${dash_bin}" ./bs version
    eq "1" "${RC}" "no suitable bash: exit 1"
    has "bash 4.2+" "no suitable bash: says what is needed"
    has "BS_HOST_BASH=/nonexistent" "no suitable bash: names the bad override"
    has "apk add bash" "no suitable bash: install hints (Alpine)"
    has "brew install bash" "no suitable bash: install hints (macOS)"
    lacks "Bad substitution" "no suitable bash: no syntax noise"
    RUN_ENV="BS_HOST_BASH=/nonexistent" run "${dash_bin}" ./install.sh --help
    eq "1" "${RC}" "install.sh without a suitable bash: exit 1"
    RUN_ENV=""
}

test_guards() {
    local dash_bin; dash_bin="$(shell_bin dash)"
    [[ -n "${dash_bin}" ]] || return 0
    RUN_ENV="__BS_TRAMPOLINE=1" run "${dash_bin}" ./bs version
    eq "1" "${RC}" "loop guard: stops instead of re-running forever"
    has "did not help" "loop guard: explains"
    RUN_ENV=""

    # Подключение (source) из оболочки, а не запуск файла
    printf '. "%s/bootstrap/trampoline.sh"\necho "after-source"\n' "${BS_PROJECT_ROOT}" > "${T}/src.sh"
    run "${dash_bin}" -c ". '${BS_PROJECT_ROOT}/bootstrap/trampoline.sh'; echo rc=\$?"
    has "run this file as a program" "trampoline sourced into a shell: explains, does not exec"

    printf '. "%s/bootstrap/init.sh"\necho "rc=$?"\n' "${BS_PROJECT_ROOT}" > "${T}/init_src.sh"
    run "${dash_bin}" "${T}/init_src.sh"
    has "only from bash 4.2+" "init.sh sourced from dash: a clear answer"
    lacks "Bad substitution" "init.sh sourced from dash: no syntax noise"
    local zsh_bin; zsh_bin="$(shell_bin zsh)"
    if [[ -n "${zsh_bin}" ]]; then
        run "${zsh_bin}" "${T}/init_src.sh"
        has "only from bash 4.2+" "init.sh sourced from zsh: a clear answer"
        lacks "bad substitution" "init.sh sourced from zsh: no kernel-load noise"
    fi
}

main() {
    print_header "Trampoline Unit Tests / Тесты трамплина"

    testframework::init
    T="$(mktemp -d)"
    mkdir -p "${T}/home"

    testframework::section "Prologue / Пролог"
    test_prologue_identical

    testframework::section "Entry points under other shells / Точки входа в других оболочках"
    test_entry_points_under_shells
    test_bash_as_sh
    test_arguments_survive
    test_symlink

    testframework::section "No bash, guards / Нет bash, защиты"
    test_no_host
    test_guards

    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
