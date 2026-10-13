#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testshellstrictunit.sh — bs --strict-shell: the tier of a lib/ module against the shell bs was started from
# tests/unit/testshellstrictunit.sh — bs --strict-shell: tier модуля lib/ против оболочки, из которой запущен bs
#
# Without the flag the trampoline lets any shell use any module. With
# --strict-shell (or BS_SHELL_STRICT=1) a module runs only when its "# @shell"
# tier fits the origin shell: posix — from any, bash4 — from bash 4.2+, any other
# word — from the shell of that name. core/ (the kernel) is always allowed.
# Без флага трамплин даёт любой оболочке любой модуль. С --strict-shell (или
# BS_SHELL_STRICT=1) модуль исполняется, только если его tier "# @shell"
# подходит исходной оболочке. core/ (ядро) разрешено всегда.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
source "${BS_PROJECT_ROOT}/bootstrap/shell.sh"

T=""
OUT=""
RC=0

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }
has() {
    if [[ "${OUT}" == *"$1"* ]]; then testframework::assert_true "true" "$2" || true
    else testframework::assert_true "false" "$2" || true; printf '    not found / не найдено: %s\n    output: %s\n' "$1" "${OUT}" | head -6; fi
}
allows() { if bs_shell_tier_allows "$1" "$2"; then echo yes; else echo no; fi; }

# run <env...> -- <interpreter> <args...>
run() {
    local -a envs=()
    while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done
    shift
    RC=0
    OUT="$(cd "${BS_PROJECT_ROOT}" && env -i HOME="${T}/home" PATH="/usr/bin:/bin" "${envs[@]}" "$@" 2>&1 </dev/null)" || RC=$?
}

test_rules() {
    eq "yes" "$(allows posix dash)" "posix is allowed from dash"
    eq "yes" "$(allows posix zsh)" "posix is allowed from zsh"
    eq "yes" "$(allows bash4 bash)" "bash4 is allowed from bash"
    eq "no" "$(allows bash4 dash)" "bash4 is refused from dash"
    eq "no" "$(allows bash4 zsh)" "bash4 is refused from zsh"
    eq "no" "$(allows bash4 sh)" "bash4 is refused from sh"
    eq "yes" "$(allows zsh zsh)" "a zsh tier is allowed from zsh"
    eq "no" "$(allows zsh bash)" "a zsh tier is refused from bash"
    eq "yes" "$(allows zsh,bash4 bash)" "a list: bash4 covers bash"
    eq "yes" "$(allows zsh,bash4 zsh)" "a list: zsh covers zsh"
    eq "no" "$(allows nu fish)" "a nu tier is refused from fish"
    eq "no" "$(allows '' dash)" "no tier means bash4: refused from dash"
}

test_synonyms() {
    local w
    for w in sh shell posix; do eq "posix" "$(bs_shell_tier_word "${w}")" "tier word ${w} = posix"; done
    for w in bash bash4; do eq "bash4" "$(bs_shell_tier_word "${w}")" "tier word ${w} = bash4"; done
    for w in fs fish; do eq "fish" "$(bs_shell_tier_word "${w}")" "tier word ${w} = fish"; done
    for w in nu nushell; do eq "nu" "$(bs_shell_tier_word "${w}")" "tier word ${w} = nu"; done
    eq "zsh" "$(bs_shell_tier_word zsh)" "tier word zsh stays"
    eq "weird" "$(bs_shell_tier_word weird)" "an unknown tier word stays as is"
    eq "yes" "$(allows sh dash)" "tier sh = posix: allowed from dash"
    eq "yes" "$(allows shell zsh)" "tier shell = posix: allowed from zsh"
    eq "yes" "$(allows nushell nu)" "tier nushell: allowed from nu"
    eq "yes" "$(allows nu nushell)" "tier nu: allowed from the origin nushell"
    eq "yes" "$(allows fs fish)" "tier fs: allowed from fish"
    eq "yes" "$(allows fish fs)" "tier fish: allowed from the origin fs"
    eq "no" "$(allows nushell fish)" "tier nushell: refused from fish"
    eq "yes" "$(allows bash bash)" "tier bash: allowed from bash"
    eq "no" "$(allows bash dash)" "tier bash: refused from dash"
    eq "yes" "$(allows fs,nushell nu)" "a list of synonyms"
}

test_file_tier() {
    printf '#!/bin/sh\n# @shell posix — fine\necho a\n' > "${T}/a.sh"
    printf '#!/bin/bash\n# @shell zsh,bash4 — both\n' > "${T}/b.sh"
    printf '#!/bin/bash\necho nothing\n' > "${T}/c.sh"
    eq "posix" "$(bs_shell_file_tier "${T}/a.sh")" "file_tier: posix"
    eq "zsh,bash4" "$(bs_shell_file_tier "${T}/b.sh")" "file_tier: a list"
    eq "bash4" "$(bs_shell_file_tier "${T}/c.sh")" "file_tier: no annotation = bash4"
    eq "bash4" "$(bs_shell_file_tier "${T}/missing.sh")" "file_tier: a missing file = bash4"
    eq "posix" "$(bs_shell_file_tier "${BS_PROJECT_ROOT}/bootstrap/shell.sh")" "file_tier: bootstrap/shell.sh"
}

test_cli() {
    printf '#!/usr/bin/env bs\nload "lib/io/streams"\nio::streams::print "ran"\n' > "${T}/s.sh"
    local sh_name sh_bin
    for sh_name in dash zsh; do
        sh_bin="$(command -v "${sh_name}" || true)"
        [[ -n "${sh_bin}" ]] || { printf '  skip: %s is not installed\n' "${sh_name}"; continue; }
        run -- "${sh_bin}" ./bs run "${T}/s.sh"
        eq "ran" "${OUT}" "${sh_name} without the flag: the module runs through the trampoline"
        run -- "${sh_bin}" ./bs --strict-shell run "${T}/s.sh"
        eq "1" "${RC}" "${sh_name} --strict-shell: exit 1"
        has "lib/io/streams" "${sh_name} --strict-shell: names the module"
        has "@shell bash4" "${sh_name} --strict-shell: names the tier"
        has "'${sh_name}'" "${sh_name} --strict-shell: names the origin shell"
        has "--strict-shell" "${sh_name} --strict-shell: bilingual hint" 
        run BS_SHELL_STRICT=1 -- "${sh_bin}" ./bs run "${T}/s.sh"
        eq "1" "${RC}" "${sh_name} BS_SHELL_STRICT=1: exit 1"
    done
    run -- bash ./bs --strict-shell run "${T}/s.sh"
    eq "ran" "${OUT}" "bash --strict-shell: bash 4.2+ is allowed"
    run -- bash ./bs --strict-shell version
    has "BS Framework version:" "--strict-shell does not block core/ and the commands"
    local dash_bin; dash_bin="$(command -v dash || true)"
    if [[ -n "${dash_bin}" ]]; then
        run -- "${dash_bin}" ./bs --strict-shell version
        eq "0" "${RC}" "dash --strict-shell version: the kernel is always allowed"
    fi
}

main() {
    print_header "Strict Shell Unit Tests / Тесты --strict-shell"

    testframework::init
    T="$(mktemp -d)"
    mkdir -p "${T}/home"

    testframework::section "Rules / Правила"
    test_rules
    testframework::section "Synonyms / Синонимы"
    test_synonyms
    testframework::section "File tier / Tier файла"
    test_file_tier
    testframework::section "bs --strict-shell"
    test_cli

    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
