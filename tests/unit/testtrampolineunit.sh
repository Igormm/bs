#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testtrampolineunit.sh — entry points under bash, zsh, dash, bash-as-sh
# tests/unit/testtrampolineunit.sh — точки входа под bash, zsh, dash, bash как sh
#
# `sh install.sh`, `dash ./bs`, `zsh ./bs`, bash started as `sh` (POSIX mode):
# bootstrap/trampoline.sh must re-run the entry point in a capable bash with the
# same arguments, or explain what to install. The `bs` commands that already live
# in bootstrap/cli.sh are the exception: they stay in the current shell and never
# start bash. Every case runs under env -i.
# `sh install.sh`, `dash ./bs`, `zsh ./bs`, bash, запущенный как `sh` (режим
# POSIX): bootstrap/trampoline.sh обязан перезапустить точку входа в подходящем
# bash с теми же аргументами либо объяснить, что установить. Исключение —
# команды `bs`, которые уже есть в bootstrap/cli.sh: они остаются в текущей
# оболочке и bash не запускают.

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

# POSIX-команда не ищет bash и не перезапускается в нём, даже когда bash есть.
# Обёртка bash в PATH оставляет след при каждом запуске: пустой след — bash не звали.
# A POSIX command neither searches for bash nor re-runs in it, even when bash is
# installed. A bash wrapper on PATH leaves a trace on every start: an empty trace
# means bash was not called.
test_posix_commands_stay_native() {
    local dash_bin zsh_bin real_bash
    dash_bin="$(shell_bin dash)"
    real_bash="$(shell_bin bash)"
    [[ -n "${dash_bin}" && -n "${real_bash}" ]] || return 0

    local wrap="${T}/bash-wrap" calls="${T}/bash-calls"
    mkdir -p "${wrap}"
    cat > "${wrap}/bash" <<EOF
#!/bin/sh
printf '%s\n' called >> '${calls}'
exec '${real_bash}' "\$@"
EOF
    chmod +x "${wrap}/bash"

    call_entry() {
        local interp=$1 entry=$2; shift 2
        : > "${calls}"
        RC=0
        OUT="$(cd "${BS_PROJECT_ROOT}" && env -i HOME="${T}/home" \
            PATH="${wrap}:/usr/bin:/bin" "${interp}" "${entry}" "$@" 2>&1 </dev/null)" || RC=$?
    }
    no_bash() {
        if [[ -s "${calls}" ]]; then
            testframework::assert_true "false" "$1" || true
            printf '    bash was called / bash вызван: %s\n' "$(head -n 1 "${calls}")"
        else
            testframework::assert_true "true" "$1" || true
        fi
    }
    bash_used() {
        if [[ -s "${calls}" ]]; then
            testframework::assert_true "true" "$1" || true
        else
            testframework::assert_true "false" "$1" || true
            printf '    bash was not called / bash не вызван\n'
        fi
    }

    call_entry "${dash_bin}" ./bs version
    eq "0" "${RC}" "dash: bs version exit 0"
    has "BS Framework version:" "dash: bs version prints the version"
    no_bash "dash: bs version does not start bash"

    call_entry "${dash_bin}" ./bs version --full
    eq "0" "${RC}" "dash: bs version --full exit 0"
    no_bash "dash: bs version --full does not start bash"

    call_entry "${dash_bin}" ./bs help
    eq "0" "${RC}" "dash: bs help exit 0"
    has "BS Framework" "dash: bs help prints the usage"
    no_bash "dash: bs help does not start bash"

    call_entry "${dash_bin}" ./bs help version
    eq "0" "${RC}" "dash: bs help version exit 0"
    no_bash "dash: help of a POSIX command does not start bash"

    call_entry "${dash_bin}" ./bs
    eq "0" "${RC}" "dash: bs with no arguments exit 0"
    has "BS Framework" "dash: bs with no arguments prints the usage"
    no_bash "dash: bs with no arguments does not start bash"

    call_entry "${dash_bin}" ./bs list
    eq "0" "${RC}" "dash: bs list exit 0"
    has "Available modules:" "dash: bs list prints modules"
    no_bash "dash: bs list does not start bash"

    call_entry "${dash_bin}" ./bs calc '2 3 + 4 *'
    eq "0" "${RC}" "dash: bs calc exit 0"
    eq "20" "${OUT}" "dash: bs calc computes in the POSIX kernel"
    no_bash "dash: bs calc does not start bash"

    call_entry "${dash_bin}" ./bs call bs_utils_human_size 1536000
    eq "0" "${RC}" "dash: bs call with no --load exit 0"
    eq "1.5 MiB" "${OUT}" "dash: bs call with no --load works"
    bash_used "dash: bs call with no --load keeps the full kernel (bash)"

    call_entry "${dash_bin}" ./bs call --load core/fmt bs_utils_human_size 1536000
    eq "0" "${RC}" "dash: bs call --load core/... exit 0"
    eq "1.5 MiB" "${OUT}" "dash: bs call --load core/... works"
    no_bash "dash: bs call --load core/... does not start bash"

    call_entry "${dash_bin}" ./bs call --load core/fmt utils::human_size 1536000
    eq "0" "${RC}" "dash: bs call of a :: alias exit 0"
    eq "1.5 MiB" "${OUT}" "dash: bs call of a :: alias works"
    bash_used "dash: a :: alias reaches bash where the shell cannot define it"

    call_entry "${dash_bin}" ./bs where --help
    eq "0" "${RC}" "dash: bs where --help exit 0"
    no_bash "dash: bs where --help does not start bash"

    call_entry "${dash_bin}" ./bs uninstall --help
    eq "0" "${RC}" "dash: bs uninstall --help exit 0"
    no_bash "dash: bs uninstall --help does not start bash"

    call_entry "${dash_bin}" ./bs update --help
    eq "0" "${RC}" "dash: bs update --help exit 0"
    no_bash "dash: bs update --help does not start bash"

    call_entry "${dash_bin}" ./boot.sh version
    eq "0" "${RC}" "dash: boot.sh version exit 0"
    has "BS Framework version:" "dash: boot.sh version hands over to bs"
    no_bash "dash: boot.sh version does not start bash"

    # bash-слой по-прежнему получает управление: lib/ и run/build
    # The bash layer still gets control: lib/ and run/build
    call_entry "${dash_bin}" ./bs build --help
    eq "0" "${RC}" "dash: bs build --help exit 0"
    has "Usage: bs build" "dash: bs build --help prints the usage"
    bash_used "dash: bs build reaches bash"

    call_entry "${dash_bin}" ./bs help build
    eq "0" "${RC}" "dash: bs help build exit 0"
    has "Usage: bs build" "dash: bs help build prints the usage"
    bash_used "dash: help of a bash-layer command reaches bash"

    call_entry "${dash_bin}" ./bs doctor --capabilities
    eq "0" "${RC}" "dash: bs doctor --capabilities exit 0"
    bash_used "dash: bs doctor --capabilities reaches bash"

    call_entry "${dash_bin}" ./bs call --load lib/io/streams io::streams::print hi
    eq "0" "${RC}" "dash: bs call --load lib/... exit 0"
    eq "hi" "${OUT}" "dash: bs call --load lib/... works"
    bash_used "dash: bs call --load lib/... reaches bash"

    call_entry "${dash_bin}" ./bs run /nonexistent
    eq "2" "${RC}" "dash: bs run of a missing script exits 2"
    bash_used "dash: bs run reaches bash"

    call_entry "${dash_bin}" ./install.sh --help
    eq "0" "${RC}" "dash: install.sh --help exit 0"
    has "BS installer" "dash: install.sh --help prints the usage"
    bash_used "dash: install.sh still re-runs in bash"

    # Явный BS_HOST_BASH главнее оптимизации: он по-прежнему уводит в bash.
    # An explicit BS_HOST_BASH wins over the optimisation: it still goes to bash.
    : > "${calls}"
    RC=0
    OUT="$(cd "${BS_PROJECT_ROOT}" && env -i HOME="${T}/home" BS_HOST_BASH="${wrap}/bash" \
        PATH="${wrap}:/usr/bin:/bin" "${dash_bin}" ./bs version 2>&1 </dev/null)" || RC=$?
    eq "0" "${RC}" "explicit BS_HOST_BASH: bs version exit 0"
    bash_used "explicit BS_HOST_BASH still reaches bash"

    # bash, запущенный как sh: POSIX-команда остаётся здесь, install.sh — нет.
    # bash started as sh: a POSIX command stays here, install.sh does not.
    ln -sf "${real_bash}" "${T}/sh"
    call_entry "${T}/sh" ./bs version
    eq "0" "${RC}" "bash-as-sh: bs version exit 0"
    has "BS Framework version:" "bash-as-sh: bs version works in POSIX mode"
    no_bash "bash-as-sh: bs version does not re-run in bash"

    call_entry "${T}/sh" ./install.sh --help
    eq "0" "${RC}" "bash-as-sh: install.sh --help exit 0"
    bash_used "bash-as-sh: install.sh still re-runs in bash"

    zsh_bin="$(shell_bin zsh)"
    if [[ -n "${zsh_bin}" ]]; then
        call_entry "${zsh_bin}" ./bs version
        eq "0" "${RC}" "zsh: bs version exit 0"
        no_bash "zsh: bs version does not start bash"
    fi
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

    # init.sh — POSIX: из dash и zsh он подключается и грузит POSIX-часть ядра (BS_KERNEL_MODE=posix);
    # без подсказки о каталоге из dash он говорит, что задать
    # init.sh is POSIX: from dash and zsh it loads the POSIX part of the kernel (BS_KERNEL_MODE=posix);
    # with no hint about the directory, dash says what to set
    printf '. "%s/bootstrap/init.sh"\necho "rc=$?"\n' "${BS_PROJECT_ROOT}" > "${T}/init_src.sh"
    run "${dash_bin}" "${T}/init_src.sh"
    has "set BS_BOOTSTRAP_DIR, BS_ENTRY_DIR or BS_ROOT" "init.sh sourced from dash without a directory hint: says what to set"
    lacks "Bad substitution" "init.sh sourced from dash: no syntax noise"
    printf 'BS_ENTRY_DIR="%s"\nBS_SILENT=1\n. "%s/bootstrap/init.sh"\necho "mode=$BS_KERNEL_MODE rc=$?"\n' "${BS_PROJECT_ROOT}" "${BS_PROJECT_ROOT}" > "${T}/init_src2.sh"
    run "${dash_bin}" "${T}/init_src2.sh"
    has "mode=posix rc=0" "init.sh sourced from dash with BS_ENTRY_DIR: the POSIX part of the kernel loads"
    lacks "Bad substitution" "init.sh sourced from dash with BS_ENTRY_DIR: no syntax noise"
    local zsh_bin; zsh_bin="$(shell_bin zsh)"
    if [[ -n "${zsh_bin}" ]]; then
        run "${zsh_bin}" "${T}/init_src.sh"
        has "BS bootstrap initialized from" "init.sh sourced from zsh: the kernel loads (its directory comes from %x)"
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

    testframework::section "POSIX commands stay native / POSIX-команды остаются в своей оболочке"
    test_posix_commands_stay_native

    testframework::section "No bash, guards / Нет bash, защиты"
    test_no_host
    test_guards

    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
