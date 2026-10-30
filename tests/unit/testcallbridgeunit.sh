#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testcallbridgeunit.sh — `bs call`: the bridge to kernel functions from any shell
# tests/unit/testcallbridgeunit.sh — `bs call`: мост к функциям ядра из любой оболочки

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly BS_BIN="${BS_PROJECT_ROOT}/bs"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# eq <expected> <actual> <message> — как в остальных тестах ярусов / the same order as in the other tier tests
eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

# Оболочки; "busybox ash" — апплет / shells; "busybox ash" is an applet
readonly -a TEST_SHELLS=("bash" "zsh" "dash" "busybox ash" "ksh" "mksh" "fish")

# in_shell <shell words> <command line> — строка выполняется оболочкой, bs найден по PATH
in_shell() {
    local -a words=()
    IFS=' ' read -ra words <<< "$1"
    # </dev/null: bash из Fedora читает ~/.bashrc, если его stdin — сокет (как у sshd), и тогда ~/.local/bin с
    # установленной старой копией bs оказывается в PATH раньше корня репозитория / Fedora's bash sources ~/.bashrc
    # when its stdin is a socket (as under sshd), and then ~/.local/bin with an installed old bs lands in PATH
    # before the repository root
    env -i HOME="${HOME}" PATH="${BS_PROJECT_ROOT}:/usr/bin:/bin" BS_SILENT=1 "${words[@]}" -c "$2" 2>&1 </dev/null
}

test_every_shell() {
    local sh_name rc out
    for sh_name in "${TEST_SHELLS[@]}"; do
        command -v "${sh_name%% *}" >/dev/null 2>&1 || { printf '  skip: %s is not installed / не установлен\n' "${sh_name}"; continue; }
        # `|| true`: под set -e упавший вызов не должен обрывать тест до диагностики / under set -e a failed call must not abort the test before the diagnostics
        out="$(in_shell "${sh_name}" 'bs call utils::human_size 1536000' || true)"
        if [[ "${out}" != "1.5 MiB" ]]; then
            # при сбое покажем сырой вывод и КАКОЙ bs запустился / on a failure show the raw output and WHICH bs was started
            printf '    diagnostics: raw=[%s] which=[%s] root=%s cwd=%s HOME=%s bs=[%s] version=[%s]\n' \
                "${out}" "$(in_shell "${sh_name}" 'command -v bs' || true)" "${BS_PROJECT_ROOT}" "$(pwd)" "${HOME}" \
                "$(ls -la "${BS_PROJECT_ROOT}/bs" 2>&1 | cut -c1-90)" \
                "$(in_shell "${sh_name}" 'bs version --full' 2>&1 | tr '\n' ' ' | cut -c1-200 || true)"
        fi
        eq "1.5 MiB" "${out}" "${sh_name}: bs call returns the function's stdout"
        rc=0; in_shell "${sh_name}" 'bs call no_such_function_xyz' >/dev/null || rc=$?
        eq "127" "${rc}" "${sh_name}: unknown function -> 127"
        rc=0; in_shell "${sh_name}" 'bs call utils::has no-such-command-xyz' >/dev/null || rc=$?
        eq "1" "${rc}" "${sh_name}: the exit code of the function is the exit code of bs call"
    done
}

test_safety() {
    local rc
    rc=0; "${BS_BIN}" call 'rm' -rf /nonexistent >/dev/null 2>&1 || rc=$?
    eq "127" "${rc}" "an external command is not a function -> 127"
    rc=0; "${BS_BIN}" call 'a;b' >/dev/null 2>&1 || rc=$?
    eq "2" "${rc}" "a name with ; is refused (2)"
    rc=0; "${BS_BIN}" call '$(id)' >/dev/null 2>&1 || rc=$?
    eq "2" "${rc}" "a name with \$( ) is refused (2)"
    rc=0; "${BS_BIN}" call --load ../etc/passwd foo >/dev/null 2>&1 || rc=$?
    eq "2" "${rc}" "a module path with .. is refused (2)"
    rc=0; "${BS_BIN}" call --load /etc/passwd foo >/dev/null 2>&1 || rc=$?
    eq "2" "${rc}" "an absolute module path is refused (2)"
    rc=0; "${BS_BIN}" call >/dev/null 2>&1 || rc=$?
    eq "2" "${rc}" "no function -> usage (2)"
}

test_load() {
    eq "1" "$("${BS_BIN}" call --load lib/system/info system::info::os 2>&1 | head -n 2 | grep -c 'Operating System')" "--load brings a library function"
    eq "1.0 KiB" "$("${BS_BIN}" call --load lib/io/streams --load lib/system/info utils::human_size 1024)" "--load can repeat"
}

main() {
    testframework::section "Every shell / Каждая оболочка"; test_every_shell
    testframework::section "Safety / Безопасность"; test_safety
    testframework::section "--load"; test_load
    testframework::summary
}

main "$@"
