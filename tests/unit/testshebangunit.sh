#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testshebangunit.sh — Unit tests for bootstrap/shebang.sh and `bs shebang`
# tests/unit/testshebangunit.sh — Модульные тесты bootstrap/shebang.sh и `bs shebang`

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly SHEBANG_SH="${BS_PROJECT_ROOT}/bootstrap/shebang.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

T=""

eq() { testframework::assert_equal "$1" "$2" "$3" || true; }

# run_in <shell> <snippet> — snippet runs after sourcing shebang.sh
run_in() {
    local -r sh_bin="$1" snippet="$2"
    printf '. "%s"\n%s\n' "${SHEBANG_SH}" "${snippet}" > "${T}/probe.sh"
    env -i HOME="${T}" PATH="/usr/bin:/bin" ${PROBE_ENV:-} "${sh_bin}" "${T}/probe.sh" 2>&1
}

test_in_every_shell() {
    local sh_name sh_bin
    while IFS= read -r sh_bin; do
        sh_name="${sh_bin##*/}"
        testframework::assert_command "'${sh_bin}' -n '${SHEBANG_SH}'" "parses in ${sh_name}" || true
        eq "$(run_in "${sh_bin}" 'bs_shebang_line portable bs')" '#!/usr/bin/env bs' "${sh_name}: portable line"
        eq "$(run_in "${sh_bin}" 'bs_shebang_parse "#! /bin/bash -e"')" '/bin/bash -e' "${sh_name}: parse"
        eq "$(run_in "${sh_bin}" 'bs_shebang_works "#!/nonexistent/env bs" >/dev/null || echo broken')" 'broken' "${sh_name}: missing interpreter is broken"
        eq "$(run_in "${sh_bin}" 'bs_shebang_works "#!/usr/bin/env sh" && echo ok')" 'ok' "${sh_name}: env + sh works"
        eq "$(run_in "${sh_bin}" 'bs_shebang_works "#!/usr/bin/env no-such-prog-xyz" >/dev/null || echo broken')" 'broken' "${sh_name}: env + missing program is broken"
    done < <(testframework::posix_shells)
}

test_termux_detection() {
    eq "$(PROBE_ENV='PREFIX=/data/data/com.termux/files/usr' run_in bash 'bs_shebang_is_termux && echo yes')" 'yes' "PREFIX of Termux"
    eq "$(PROBE_ENV='TERMUX_VERSION=0.118' run_in bash 'bs_shebang_is_termux && echo yes')" 'yes' "TERMUX_VERSION"
    eq "$(run_in bash 'bs_shebang_is_termux || echo no')" 'no' "not Termux"
}

test_is_for() {
    eq "$(run_in bash 'bs_shebang_is_for "#!/usr/bin/env bs" bs && echo y')" 'y' "env bs"
    eq "$(run_in bash 'bs_shebang_is_for "#!/home/u/.local/bin/bs" bs && echo y')" 'y' "absolute bs"
    eq "$(run_in bash 'bs_shebang_is_for "#!/usr/bin/env bash" bs || echo n')" 'n' "bash is not bs"
}

test_rewrite_keeps_body_and_mode() {
    printf '#!/usr/bin/env bs\necho one\necho two' > "${T}/s.sh"
    chmod 750 "${T}/s.sh"
    run_in bash 'bs_shebang_rewrite "'"${T}"'/s.sh" "#!/data/x/env bs"' >/dev/null
    eq "$(head -n1 "${T}/s.sh")" '#!/data/x/env bs' "first line replaced"
    eq "$(tail -n +2 "${T}/s.sh" | tr '\n' '|')" 'echo one|echo two' "body kept"
    eq "$(stat -c %a "${T}/s.sh")" '750' "mode kept"
    printf 'no shebang\n' > "${T}/n.sh"
    run_in bash 'bs_shebang_rewrite "'"${T}"'/n.sh" "#!/x"' >/dev/null || true
    eq "$(cat "${T}/n.sh")" 'no shebang' "file without #! is not touched"
}

test_hardening() {
    # flags are never dropped: lines with extra arguments are not "for bs"
    eq "$(run_in bash 'bs_shebang_is_for "#!/usr/bin/env -S bs --flag" bs || echo n')" 'n' "env -S bs --flag is skipped"
    eq "$(run_in bash 'bs_shebang_is_for "#!/bin/sh -c bs" bs || echo n')" 'n' "sh -c bs is skipped"
    # CRLF: the CR is not part of the program name
    printf '#!/usr/bin/env sh\r\necho x\r\n' > "${T}/crlf.sh"
    eq "$(run_in bash 'bs_shebang_read "'"${T}"'/crlf.sh"')" '#!/usr/bin/env sh' "CRLF: CR is dropped"
    # a leading "-" in the file name
    ( cd "${T}" && printf '#!/usr/bin/env bs\nbody\n' > ./-n && run_in bash 'bs_shebang_rewrite -n "#!/x/env bs"' >/dev/null )
    eq "$(head -n1 "${T}/-n")" '#!/x/env bs' "file named -n is rewritten"
    eq "$(ls "${T}" | grep -c shebang\\.)" '0' "no temporary file is left"
    # a symlink is rewritten through to its target
    printf '#!/usr/bin/env bs\necho t\n' > "${T}/target.sh"; ln -sf target.sh "${T}/link.sh"
    run_in bash 'bs_shebang_rewrite "'"${T}"'/link.sh" "#!/y/env bs"' >/dev/null
    eq "$(head -n1 "${T}/target.sh")" '#!/y/env bs' "symlink: the target is rewritten"
    eq "$([[ -L "${T}/link.sh" ]] && echo link)" 'link' "symlink: the link is still a link"
    # abs mode: an interpreter that is itself a script with a broken shebang is broken
    printf '#!/nonexistent/bash\n' > "${T}/inner"; chmod +x "${T}/inner"
    eq "$(run_in bash 'bs_shebang_works "#!'"${T}"'/inner" >/dev/null || echo broken')" 'broken' "nested broken shebang is reported"
    # check on a missing path fails
    testframework::assert_false "'${BS_PROJECT_ROOT}/bs' shebang check '${T}/nope' >/dev/null 2>&1" "check: missing path -> exit 1" || true
}

test_fix() {
    local envp
    envp="$(run_in bash 'bs_shebang_env_path')"
    # Termux-like: env is not where the file says -> env of this machine
    printf '#!/nonexistent/env bash\necho a\n' > "${T}/f1.sh"
    run_in bash 'bs_shebang_fix "'"${T}"'/f1.sh"' >/dev/null
    eq "$(head -n1 "${T}/f1.sh")" "#!${envp} bash" "fix: broken env path is replaced"
    # a working line is not touched
    printf '#!/usr/bin/env sh\necho b\n' > "${T}/f2.sh"
    run_in bash 'bs_shebang_fix "'"${T}"'/f2.sh"' >/dev/null
    eq "$(head -n1 "${T}/f2.sh")" '#!/usr/bin/env sh' "fix: a working line is kept"
    # /bin/sh missing -> the sh found in PATH
    printf '#!/nonexistent/sh\necho c\n' > "${T}/f3.sh"
    run_in bash 'bs_shebang_fix "'"${T}"'/f3.sh"' >/dev/null
    eq "$(head -n1 "${T}/f3.sh" | sed 's|^#!||' | xargs basename)" 'sh' "fix: sh interpreter is taken from PATH"
    local newsh
    newsh="$(head -n1 "${T}/f3.sh" | sed 's|^#!||')"
    eq "$([[ -x "${newsh}" ]] && echo yes)" 'yes' "fix: the new interpreter exists"
    # lines with flags and non-scripts are left alone
    printf '#!/nonexistent/env -S bash -e\n' > "${T}/f4.sh"
    run_in bash 'bs_shebang_fix "'"${T}"'/f4.sh"' >/dev/null
    eq "$(head -n1 "${T}/f4.sh")" '#!/nonexistent/env -S bash -e' "fix: a line with flags is kept"
    printf 'plain\n' > "${T}/f5.sh"
    run_in bash 'bs_shebang_fix "'"${T}"'/f5.sh"' >/dev/null
    eq "$(cat "${T}/f5.sh")" 'plain' "fix: a file without #! is kept"
}

test_cli() {
    local bs_bin="${BS_PROJECT_ROOT}/bs"
    printf '#!/usr/bin/env bs\necho hi\n' > "${T}/c.sh"
    printf '#!/usr/bin/env bash\necho other\n' > "${T}/o.sh"
    eq "$("${bs_bin}" shebang line --mode portable)" '#!/usr/bin/env bs' "bs shebang line"
    "${bs_bin}" shebang set --mode abs --prog bs --dry-run "${T}" >/dev/null 2>&1 || true
    eq "$(head -n1 "${T}/c.sh")" '#!/usr/bin/env bs' "--dry-run changes nothing"
    printf '#!/nonexistent/env bs\n' > "${T}/b.sh"
    testframework::assert_false "'${bs_bin}' shebang check '${T}/b.sh' >/dev/null 2>&1" "check: broken shebang -> exit 1" || true
    "${bs_bin}" shebang set --mode portable "${T}/b.sh" >/dev/null 2>&1
    eq "$(head -n1 "${T}/b.sh")" '#!/usr/bin/env bs' "set repairs it"
    testframework::assert_command "'${bs_bin}' shebang check '${T}/b.sh' >/dev/null 2>&1" "check: repaired -> exit 0" || true
    "${bs_bin}" shebang set --mode portable "${T}/o.sh" >/dev/null 2>&1
    eq "$(head -n1 "${T}/o.sh")" '#!/usr/bin/env bash' "other programs are not touched"
}

main() {
    T="$(mktemp -d)"
    testframework::section "Every shell / Каждая оболочка"; test_in_every_shell
    testframework::section "Termux"; test_termux_detection
    testframework::section "is_for"; test_is_for
    testframework::section "rewrite"; test_rewrite_keeps_body_and_mode
    testframework::section "bs shebang"; test_cli
    testframework::section "Hardening / Устойчивость"; test_hardening
    testframework::section "bs_shebang_fix"; test_fix
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
