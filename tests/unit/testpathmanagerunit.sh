#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testpathmanagerunit.sh — install/path_manager.sh: bs_remove_path_entry never loses the rc file
# tests/unit/testpathmanagerunit.sh — install/path_manager.sh: bs_remove_path_entry не теряет rc-файл

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""
readonly LINE='export PATH="$HOME/.local/bin:$PATH"'

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

# run_remove <rc> [shim-dir] — bs_remove_path_entry in a clean bash; prints rc=<code>
run_remove() {
    local -r rc_file="$1" shim="${2:-}"
    printf '. "%s/bootstrap/shell.sh"\n. "%s/core/prereq.sh"\n. "%s/core/quiet.sh"\n. "%s/install/path_manager.sh"\nbs_remove_path_entry "%s" >/dev/null 2>&1; echo "rc=$?"\n' \
        "${BS_PROJECT_ROOT}" "${BS_PROJECT_ROOT}" "${BS_PROJECT_ROOT}" "${BS_PROJECT_ROOT}" "${rc_file}" > "${T}/run.sh"
    env -i HOME="${T}/h" PATH="${shim:+${shim}:}/usr/bin:/bin" TMPDIR="${T}" bash "${T}/run.sh" 2>&1
}

test_removes_line() {
    printf 'a\n%s\nb\n' "${LINE}" > "${T}/rc1"
    eq "$(run_remove "${T}/rc1")" "rc=0" "remove: success rc"
    eq "$(tr '\n' ' ' < "${T}/rc1")" "a b " "remove: only the exact line is gone"
    printf '%s\n' "${LINE}" > "${T}/rc2"
    eq "$(run_remove "${T}/rc2")" "rc=0" "remove: file of only that line, rc"
    eq "$(wc -c < "${T}/rc2" | tr -d ' ')" "0" "remove: file of only that line becomes empty"
}

test_grep_failure_keeps_rc() {
    mkdir -p "${T}/shim"
    printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = "-Fvx" ] && exit 2; done\nexec /usr/bin/grep "$@"\n' > "${T}/shim/grep"
    chmod +x "${T}/shim/grep"
    printf 'a\n%s\nb\n' "${LINE}" > "${T}/rc3"
    eq "$(run_remove "${T}/rc3" "${T}/shim")" "rc=1" "grep failure: returns 1"
    eq "$(grep -c -F -x -- "${LINE}" "${T}/rc3")/$(wc -l < "${T}/rc3" | tr -d ' ')" "1/3" "grep failure: rc file is untouched"
}

main() {
    T="$(mktemp -d)"
    testframework::section "Remove / Удаление"; test_removes_line
    testframework::section "grep failure / Сбой grep"; test_grep_failure_keeps_rc
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
