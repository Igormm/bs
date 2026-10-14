#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testshelltierunit.sh — the @shell tier annotation and its scanner
# tests/unit/testshelltierunit.sh — аннотация @shell (tier) и её сканер
#
# .agents/skills/bs-shell-portability/scripts/tier_scan.sh compares the declared
# "# @shell <tier>" with the constructs of a file; `posix` files must parse in
# dash, bash and zsh. The repository must stay consistent with its annotations.
# tier_scan.sh сверяет объявленный "# @shell <tier>" с конструкциями файла;
# файлы `posix` обязаны разбираться в dash, bash и zsh. Репозиторий должен
# оставаться согласованным со своими аннотациями.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly SCAN="${BS_PROJECT_ROOT}/.agents/skills/bs-shell-portability/scripts/tier_scan.sh"
readonly PROBE="${BS_PROJECT_ROOT}/.agents/skills/bs-shell-portability/scripts/probe_shells.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

T=""
eq() { testframework::assert_equal "$1" "$2" "$3" || true; }
ok() { testframework::assert_true "$1" "$2" || true; }

test_fixtures() {
    printf '#!/bin/sh\n# @shell posix\nif [ -n "$x" ]; then echo ok; fi\n' > "${T}/good.sh"
    printf '#!/bin/sh\n# @shell posix\nif [[ -n "$x" ]]; then echo a; fi\n' > "${T}/bad_bracket.sh"
    printf '#!/bin/sh\n# @shell posix\na=(1 2)\necho "${a[0]}"\n' > "${T}/bad_array.sh"
    printf '#!/bin/sh\n# @shell posix\nbs::x() { echo a; }\n' > "${T}/bad_name.sh"
    printf '#!/bin/sh\n# @shell posix\necho "a [[ b ]] c"\nmsg="uses ${arr[0]} in text"\n' > "${T}/string_only.sh"
    printf '#!/usr/bin/env bash\n# @shell bash4\ndeclare -A m\nm[k]=v\n' > "${T}/real_bash.sh"
    printf '#!/usr/bin/env bash\n# @shell bash4\necho hi\n' > "${T}/plain.sh"
    printf '#!/usr/bin/env bash\necho hi\n' > "${T}/none.sh"

    local f
    for f in bad_bracket bad_array bad_name; do
        bash "${SCAN}" --check "${T}/${f}.sh" >/dev/null 2>&1 && eq "1" "0" "${f}: a posix file with a bashism fails --check" || eq "1" "1" "${f}: a posix file with a bashism fails --check"
    done
    local out
    out="$(bash "${SCAN}" "${T}/bad_bracket.sh")"
    ok "'${out}' == *VIOLATION* && '${out}' == *'double-bracket'* " "the violation names the construct"
    out="$(bash "${SCAN}" "${T}/bad_name.sh")"
    ok "'${out}' == *'\"::\" in a function name'* " "the violation names the :: function name"
    bash "${SCAN}" --check "${T}/good.sh" >/dev/null 2>&1 && eq "0" "0" "a clean posix file passes --check" || eq "0" "1" "a clean posix file passes --check"
    bash "${SCAN}" --check "${T}/string_only.sh" >/dev/null 2>&1 && eq "0" "0" "constructs inside strings do not fail a posix file" || eq "0" "1" "constructs inside strings do not fail a posix file"
    out="$(bash "${SCAN}" --list "${T}/real_bash.sh")"
    ok "'${out}' == *bash4*bash4*ok* " "a bash4 file with a real array/assoc is consistent"
    out="$(bash "${SCAN}" --list "${T}/plain.sh")"
    ok "'${out}' == *could-be-posix* " "a bash4 file without bashisms is reported as could-be-posix"
    out="$(bash "${SCAN}" --list "${T}/none.sh")"
    ok "'${out}' == *unannotated* " "a file without annotation is reported (default bash4)"
}

test_repository() {
    local out rc=0
    out="$(bash "${SCAN}" --check "${BS_PROJECT_ROOT}/bootstrap" "${BS_PROJECT_ROOT}/install" \
        "${BS_PROJECT_ROOT}/install.sh" "${BS_PROJECT_ROOT}/boot.sh" "${BS_PROJECT_ROOT}/bs" 2>&1)" || rc=$?
    eq "0" "${rc}" "the repository: annotations and constructs agree (no VIOLATION)"
    ok "'${out}' == *'bootstrap/shell.sh'*posix*ok* " "bootstrap/shell.sh is declared posix and consistent"
    ok "'${out}' == *'bootstrap/trampoline.sh'*posix*ok* " "bootstrap/trampoline.sh is declared posix and consistent"

    # Каждый posix-файл репозитория разбирается во всех установленных оболочках
    local f sh_name sh_bin
    while IFS= read -r f; do
        for sh_name in bash zsh dash; do
            sh_bin="$(command -v "${sh_name}" || true)"
            [[ -n "${sh_bin}" ]] || continue
            testframework::assert_command "'${sh_bin}' -n '${f}'" "${f#"${BS_PROJECT_ROOT}"/} parses in ${sh_name}" || true
        done
    done < <(grep -rlE '^# @shell posix' "${BS_PROJECT_ROOT}/bootstrap" "${BS_PROJECT_ROOT}/core" "${BS_PROJECT_ROOT}/lib" "${BS_PROJECT_ROOT}/install" 2>/dev/null | sort)

    # Каждая аннотация @shell несёт описание после тире
    local bad=0 line
    while IFS= read -r line; do
        [[ "${line}" =~ ^[^:]+:[0-9]+:#\ @shell\ [a-z0-9]+\ —\ .+ ]] || { bad=$(( bad + 1 )); printf '    no description / нет описания: %s\n' "${line}"; }
    done < <(grep -rnE '^# @shell ' "${BS_PROJECT_ROOT}/bootstrap" "${BS_PROJECT_ROOT}/core" "${BS_PROJECT_ROOT}/lib" "${BS_PROJECT_ROOT}/install" "${BS_PROJECT_ROOT}/bs" "${BS_PROJECT_ROOT}/install.sh" "${BS_PROJECT_ROOT}/boot.sh" 2>/dev/null)
    eq "0" "${bad}" "every # @shell annotation has a description after the dash"
}

test_probe() {
    local out
    out="$(bash "${PROBE}" --tsv bash 2>/dev/null)"
    ok "'${out}' == *'assoc array'*ok* " "probe: bash has associative arrays"
    ok "'${out}' == *'nameref'*ok* " "probe: bash has namerefs"
    if command -v dash >/dev/null 2>&1; then
        out="$(bash "${PROBE}" --tsv dash 2>/dev/null)"
        ok "'${out}' == *'indexed array'*no* " "probe: dash has no arrays"
        ok "'${out}' == *'name with :: (a::b)'*no* " "probe: dash rejects :: in function names"
    fi
    if command -v zsh >/dev/null 2>&1; then
        out="$(bash "${PROBE}" --tsv zsh 2>/dev/null)"
        ok "'${out}' == *'nameref (local -n)'*no* " "probe: this zsh has no namerefs"
        ok "'${out}' == *'assoc array'*ok* " "probe: zsh has associative arrays"
    fi
}

main() {
    print_header "Shell Tier Unit Tests / Тесты tier-аннотации @shell"

    testframework::init
    T="$(mktemp -d)"

    testframework::section "Scanner on fixtures / Сканер на образцах"
    test_fixtures
    testframework::section "The repository / Репозиторий"
    test_repository
    testframework::section "Probe / Проба"
    test_probe

    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
