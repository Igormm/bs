#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testbsnobashunit.sh — the bs command on a machine with NO bash: ash, dash, ksh, mksh and zsh
# tests/unit/testbsnobashunit.sh — команда bs на машине БЕЗ bash: ash, dash, ksh, mksh и zsh
#
# The `bs` entry point is "@shell posix": with no bash 4.2+ it stays in the current shell and serves the
# commands that are POSIX already (help, version, env, list, calc, init-shell, shebang, call); the others answer that they need bash,
# with exit code 1. Every bash is hidden behind a mount namespace (unshare -Urm). A machine where the
# namespace cannot be made is reported, never counted as passed.
# Точка входа `bs` — "@shell posix": без bash 4.2+ она остаётся в текущей оболочке и обслуживает команды,
# которые уже на POSIX (help, version, env, list, calc); остальные отвечают, что им нужен bash, с кодом 1.
# Все bash спрятаны через пространство монтирования (unshare -Urm). Если пространство не создаётся,
# это попадает в отчёт, а не считается пройденным.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

T=""

# hide_script <sandbox> — the script that runs INSIDE the namespace: masks bash, then the life cycle in "$1"
write_runner() {
    local -r sb="$1"
    local bash_paths c
    bash_paths="$(for c in /usr/local/bin/bash /opt/homebrew/bin/bash /opt/local/bin/bash /usr/pkg/bin/bash /usr/bin/bash /bin/bash "$(readlink -f "$(command -v bash)")"; do [[ -e "${c}" ]] && echo "${c}"; done | sort -u | tr '\n' ' ')"
    cat > "${T}/runner.sh" <<RUNNER
#!/bin/sh
# usage: runner.sh <shell-name> <home>
BASH_PATHS="${bash_paths}"
for b in \${BASH_PATHS}; do
  [ -e "\$b" ] && mount --bind "${T}/nobash" "\$b" 2>/dev/null
done
S=\$1; H=\$2
run() { env -i HOME="\$H" PATH="${sb}/bin" "${sb}/bin/\$S" "${BS_PROJECT_ROOT}/bs" "\$@"; }
if env -i PATH="${sb}/bin" "${sb}/bin/\$S" -c 'command -v bash' >/dev/null 2>&1; then echo "BASH-STILL-THERE"; exit 3; fi
for p in /usr/bin/bash /bin/bash; do
  if [ -e "\$p" ]; then o=\$("\$p" -c 'echo BASH-STILL-RUNS' 2>/dev/null); [ "\$o" = BASH-STILL-RUNS ] && { echo BASH-STILL-RUNS; exit 3; }; fi
done
echo "version=\$(run version 2>&1 | head -n 1)"
echo "help=\$(run help 2>&1 | head -n 1 | cut -d' ' -f1-3)"
echo "list=\$(run list 2>&1 | tail -n 1 | sed 's/^[0-9]* modules$/N modules/')"
echo "calc=\$(run calc '2 3 + 7 *' 2>&1 | head -n 1)"
echo "init-shell=\$(run init-shell dash 2>&1 | head -n 1 | cut -d' ' -f1-4)"
echo "shebang=\$(run shebang line --mode portable 2>&1 | head -n 1 | cut -c1-2)"
echo "call=\$(run call bs_utils_human_size 1536000 2>&1)"
run doctor > "\$H/doctor.txt" 2>&1; echo "doctor=\$?"
grep -q 'требует bash 4.2+' "\$H/doctor.txt" && echo doctor-says-bash
run nonsense > "\$H/bad.txt" 2>&1; echo "unknown=\$?"
RUNNER
}

main() {
    T="$(mktemp -d)"
    testframework::section "The bs command without bash / Команда bs без bash"
    if ! command -v unshare >/dev/null 2>&1 || ! command -v busybox >/dev/null 2>&1 || ! unshare -Urm true 2>/dev/null; then
        echo "skip: unshare -Urm or busybox is not available — NOT verified / недоступны unshare -Urm или busybox — НЕ проверено"
        rm -rf "${T:?}"
        testframework::summary
        return 0
    fi
    : > "${T}/nobash"; chmod +x "${T}/nobash"
    local sb="${T}/sb" tool p sh_name sh_bin out H
    mkdir -p "${sb}/bin"
    for tool in busybox printf ls cat head tail tr sed grep readlink mktemp cp mv rm chmod mkdir rmdir dirname basename wc cut od env uname id date git sort touch awk find dc; do
        p="$(PATH="/usr/bin:/bin" type -P "${tool}" 2>/dev/null || true)"
        [[ -n "${p}" && "${p}" == /* ]] && ln -sf "${p}" "${sb}/bin/${tool}"
    done
    ln -sf "$(command -v busybox)" "${sb}/bin/ash"
    for sh_name in dash ksh mksh zsh; do
        p="$(PATH="/usr/bin:/bin" type -P "${sh_name}" 2>/dev/null || true)"
        [[ -n "${p}" && "${p}" == /* ]] && ln -sf "${p}" "${sb}/bin/${sh_name}"
    done
    write_runner "${sb}"
    for sh_name in ash dash ksh mksh zsh; do
        if [[ ! -x "${sb}/bin/${sh_name}" ]]; then echo "skip: ${sh_name} is not installed — NOT verified / не установлен — НЕ проверено" >&2; continue; fi
        H="${T}/home-${sh_name}"; mkdir -p "${H}"
        out="$(timeout 300 unshare -Urm busybox sh "${T}/runner.sh" "${sh_name}" "${H}" 2>&1 | tr '\n' ' ' | sed 's/ $//')" || true
        testframework::assert_equal "version=BS Framework version: 0.8.0 help=BS Framework 0.8.0 list=N modules calc=35 init-shell=# BS for dash shebang=#! call=1.5 MiB doctor=1 doctor-says-bash unknown=1" "${out}" "${sh_name}: version, help, list, calc work; doctor and an unknown command fail clearly" || true
    done
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
