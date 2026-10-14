#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testwhereunit.sh — Unit tests for `bs where` (traces of BS)
# tests/unit/testwhereunit.sh — Модульные тесты `bs where` (следы BS в системе)
#
# Every case runs in a temporary HOME with its own PATH and BS_SYSTEM_PREFIX
# (env -i), so the real installs of the machine are never visible.
# Каждый случай идёт во временном HOME со своим PATH и BS_SYSTEM_PREFIX
# (env -i): настоящие установки машины не видны.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

T=""
P="/usr/bin:/bin"
OUT=""
RC=0

sandbox() {
    T="$(mktemp -d)"
    mkdir -p "${T}/home" "${T}/sys"
    P="/usr/bin:/bin"
}

# bs where в изолированном окружении: run_where [args...]  (OUT, RC)
run_where() {
    RC=0
    OUT="$(cd "${T}" && env -i HOME="${T}/home" PATH="${P}" BS_SYSTEM_PREFIX="${T}/sys" \
        ${BS_USER_SHELL:+BS_USER_SHELL="${BS_USER_SHELL}"} \
        "${TEST_BASH}" "${BS_PROJECT_ROOT}/bs" where "$@" 2>&1)" || RC=$?
}

# Установка установщиком: install_bs [--local]
install_bs() {
    (cd "${BS_PROJECT_ROOT}" && env -i HOME="${T}/home" PATH="/usr/bin:/bin" \
        BS_SYSTEM_PREFIX="${T}/sys" "${TEST_BASH}" ./install.sh "$@" </dev/null >/dev/null 2>&1) || true
}

has() {   # has "<phrase>" "<name>"  — OUT содержит фразу
    if grep -qF -- "$1" <<< "${OUT}"; then
        testframework::assert_true "true" "$2" || true
    else
        testframework::assert_true "false" "$2" || true
        printf '    not found / не найдено: %s\n' "$1"
    fi
}
lacks() { # lacks "<phrase>" "<name>"  — OUT не содержит фразу
    if grep -qF -- "$1" <<< "${OUT}"; then
        testframework::assert_true "false" "$2" || true
        printf '    unexpectedly found / найдено, а не должно: %s\n' "$1"
    else
        testframework::assert_true "true" "$2" || true
    fi
}
tree_hash() { find "$1" -type f -exec sha256sum {} + 2>/dev/null | sort | sha256sum | cut -c1-16; }

test_isolation_and_empty() {
    sandbox
    local seen
    seen="$(env -i PATH="${P}" ${TEST_BASH} -c 'command -v bs || true')"
    testframework::assert_equal "" "${seen}" "isolation: no bs in the test PATH"

    run_where
    testframework::assert_equal "0" "${RC}" "empty system: exit 0"
    has "Запущено сейчас" "empty system: the running copy block"
    has "bs не найдена в PATH" "empty system: says that bs is not in PATH"
    has "установок не найдено" "empty system: no installs"
    has "Репозитории BS" "empty system: checkouts section"
    has "${BS_PROJECT_ROOT}" "empty system: the running checkout is listed"
    rm -rf "${T}"
}

test_local_install() {
    sandbox
    install_bs --local
    P="${T}/home/.local/bin:/usr/bin:/bin"
    run_where
    testframework::assert_equal "0" "${RC}" "local install: exit 0"
    has "wrapper → ${T}/home/.local/lib/bs" "local install: the wrapper in PATH is resolved"
    has "запускается по команде bs" "local install: marks the one that runs as bs"
    has "вид / kind:    local" "local install: kind local"
    has "версия / version $(bs::version::get)" "local install: version"
    has "установлено:" "local install: manifest data"
    has "каталог в PATH" "local install: wrapper directory is in PATH"
    has "доступна на запись" "local install: owner/writable"
    has ".bashrc:" "local install: the PATH line in .bashrc is a trace"
    has "всё согласовано" "local install: nothing looks wrong"

    # В PATH вызвавшей оболочки нет ~/.local/bin (сам bs дописывает его в PATH
    # своего процесса — это не должно скрывать проблему)
    P="/usr/bin:/bin"
    run_where
    has "bs не найдена в PATH этой оболочки" "no ~/.local/bin in the caller PATH: reported"
    has "does NOT contain ${T}/home/.local/bin" "no ~/.local/bin in the caller PATH: the PATH row says so"
    has 'export PATH="$HOME/.local/bin:$PATH"' "no ~/.local/bin in the caller PATH: the immediate fix is offered"
    # Подсказка перезагрузки — для оболочки пользователя (реестр bootstrap/shell.sh)
    # The reload hint is for the user's shell (the registry in bootstrap/shell.sh)
    has "source ~/.bashrc" "no ~/.local/bin in the caller PATH: the reload command of the user's shell"
    BS_USER_SHELL=zsh run_where
    has "source ~/.zshrc" "BS_USER_SHELL=zsh: the zsh reload command is offered"
    BS_USER_SHELL=fish run_where
    has "source ~/.config/fish/conf.d/bs.fish" "BS_USER_SHELL=fish: the fish reload command is offered"
    has 'contains -- "$HOME/.local/bin"' "BS_USER_SHELL=fish: the PATH line is in fish syntax"
    BS_USER_SHELL=nu run_where
    has "exec nu" "BS_USER_SHELL=nu: the nushell reload command is offered"
    P="/usr/bin:/bin"
    lacks "всё согласовано" "no ~/.local/bin in the caller PATH: not reported as consistent"
    P="${T}/home/.local/bin:/usr/bin:/bin"

    # Установка старее репозитория — предлагается обновление
    sed -i 's/BS_VERSION="[0-9.]*"/BS_VERSION="0.0.1"/' "${T}/home/.local/lib/bs/core/version.sh"
    run_where
    has "старее репозитория" "an install older than the checkout is flagged"
    has "./bs update --lib ${T}/home/.local/lib/bs" "the command to update it is offered"
    lacks "всё согласовано" "an outdated install is not reported as consistent"
    rm -rf "${T}"
}

test_problems() {
    sandbox
    install_bs --local
    install_bs
    sed -i 's/BS_VERSION="[0-9.]*"/BS_VERSION="0.6.0"/' "${T}/sys/lib/bs/core/version.sh"
    touch "${T}/sys/lib/bs/.install.bad" "${T}/home/.local/lib/bs/.update-old.123"
    sed -i 's|^export BS_ROOT=.*|export BS_ROOT="/nonexistent/lib/bs"|' "${T}/sys/bin/bs"
    P="${T}/home/.local/bin:${T}/sys/bin:/usr/bin:/bin"
    run_where
    testframework::assert_equal "0" "${RC}" "problems: still exit 0 (informational)"
    has "${T}/sys/lib/bs" "problems: the system install is found via BS_SYSTEM_PREFIX"
    has "вид / kind:    system" "problems: system kind"
    has "КАТАЛОГ НЕ СУЩЕСТВУЕТ" "problems: broken wrapper in PATH is flagged"
    has "остатки:" "problems: leftovers are listed"
    has ".update-old.123" "problems: the leftover name is shown"
    has "установки разных версий" "problems: versions differ"
    has "Что сделать" "problems: commands to fix are offered"
    has "bs update --lib ${T}/home/.local/lib/bs" "problems: update command for the leftovers"
    rm -rf "${T}"
}

test_foreign_orphan_badmanifest() {
    sandbox
    mkdir -p "${T}/home/.local/lib/bs"
    printf 'mine\n' > "${T}/home/.local/lib/bs/notes.txt"
    run_where
    has "НЕ установка BS" "foreign dir at the standard place is reported"
    testframework::assert_command "test -f '${T}/home/.local/lib/bs/notes.txt'" "foreign dir is left intact"
    rm -rf "${T}"

    sandbox
    install_bs --local
    rm -f "${T}/home/.local/bin/bs"
    run_where
    has "нет /" "lib without a wrapper: reported"
    has "нет обёртки" "lib without a wrapper: a problem line"
    rm -rf "${T}"

    sandbox
    install_bs --local
    printf 'this is not a manifest\n' > "${T}/home/.local/lib/bs/.install"
    run_where
    has "ПОВРЕЖДЁН" "damaged manifest is flagged"
    rm -rf "${T}"
}

test_data_and_environment() {
    sandbox
    mkdir -p "${T}/home/.cache/bs/api" "${T}/home/.config/bs"
    head -c 4000 /dev/zero > "${T}/home/.cache/bs/api/x"
    run_where
    has "${T}/home/.cache/bs" "cache directory is listed"
    has "${T}/home/.config/bs" "config directory is listed"
    has "BS_SYSTEM_PREFIX=${T}/sys" "environment: BS_SYSTEM_PREFIX is shown"
    rm -rf "${T}"
}

test_read_only_and_no_execution() {
    sandbox
    install_bs --local
    install_bs
    # Чужая «установка», которая при запуске оставила бы след
    mkdir -p "${T}/home/dev/mybs/bootstrap" "${T}/home/dev/mybs/core"
    printf '#!/bin/sh\ntouch "%s/EXECUTED"\n' "${T}" > "${T}/home/dev/mybs/bs"
    chmod +x "${T}/home/dev/mybs/bs"
    printf 'x\n' > "${T}/home/dev/mybs/bootstrap/init.sh"
    printf 'export BS_VERSION="9.9.9"\n' > "${T}/home/dev/mybs/core/version.sh"
    P="${T}/home/.local/bin:${T}/sys/bin:/usr/bin:/bin"

    local before after
    before="$(tree_hash "${T}")"
    run_where --deep
    after="$(tree_hash "${T}")"
    testframework::assert_equal "${before}" "${after}" "bs where --deep changes nothing (tree checksum)"
    testframework::assert_command "test ! -e '${T}/EXECUTED'" "no found copy of bs is executed"
    has "${T}/home/dev/mybs" "--deep finds a copy outside the standard places"
    has "9.9.9" "--deep shows the version read from the file"

    run_where
    lacks "${T}/home/dev/mybs" "without --deep the unusual place is not searched"
    rm -rf "${T}"
}

test_cli_surface() {
    sandbox
    run_where --help
    testframework::assert_equal "0" "${RC}" "--help: exit 0"
    has "Usage: bs where" "--help: usage"
    has "--deep" "--help: documents --deep"
    run_where --bogus
    testframework::assert_true "${RC} -ne 0" "unknown argument: non-zero exit"
    has "unknown argument" "unknown argument: explained"
    local help_out
    help_out="$(env -i HOME="${T}/home" PATH="${P}" ${TEST_BASH} "${BS_PROJECT_ROOT}/bs" help 2>&1)"
    testframework::assert_true "'${help_out}' =~ where" "bs help lists the where command"
    rm -rf "${T}"
}

main() {
    print_header "Where Unit Tests / Модульные тесты bs where"

    testframework::init

    testframework::section "Empty system / Пустая система"
    test_isolation_and_empty

    testframework::section "Installs / Установки"
    test_local_install
    test_problems
    test_foreign_orphan_badmanifest

    testframework::section "Data, environment / Данные, окружение"
    test_data_and_environment

    testframework::section "Read-only guarantee / Только чтение"
    test_read_only_and_no_execution

    testframework::section "CLI surface / Интерфейс"
    test_cli_surface

    testframework::summary
}

main "$@"
