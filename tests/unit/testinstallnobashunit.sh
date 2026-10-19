#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testinstallnobashunit.sh — install.sh on a machine with NO bash: dash, ash, ksh, mksh and zsh
# tests/unit/testinstallnobashunit.sh — install.sh на машине БЕЗ bash: dash, ash, ksh, mksh и zsh
#
# install.sh is "@shell posix": when no bash 4.2+ is found the trampoline leaves it in the current shell and the
# kernel loads its POSIX part (BS_KERNEL_MODE=posix). The test hides every bash behind a mount namespace
# (unshare -Urm, a file mounted over each bash path) and runs the whole life cycle in each shell:
# install --local → a second install is refused → uninstall → nothing is left, the PATH line is gone.
# A machine where the namespace cannot be made is reported, never counted as passed.
# install.sh — "@shell posix": если bash 4.2+ не найден, трамплин оставляет его в текущей оболочке, а ядро
# загружает свою POSIX-часть (BS_KERNEL_MODE=posix). Тест прячет все bash в пространстве монтирования
# (unshare -Urm, поверх каждого пути bash монтируется пустой файл) и гоняет весь жизненный цикл в каждой
# оболочке: install --local → повторная установка отклонена → uninstall → ничего не осталось, строка PATH снята.
# Если пространство не создаётся, это попадает в отчёт, а не считается пройденным.

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
run() { env -i HOME="\$H" PATH="${sb}/bin" "${sb}/bin/\$S" "${BS_PROJECT_ROOT}/install.sh" "\$@"; }
if env -i PATH="${sb}/bin" "${sb}/bin/\$S" -c 'command -v bash' >/dev/null 2>&1; then echo "BASH-STILL-THERE"; exit 3; fi
for p in /usr/bin/bash /bin/bash; do
  if [ -e "\$p" ]; then o=\$("\$p" -c 'echo BASH-STILL-RUNS' 2>/dev/null); [ "\$o" = BASH-STILL-RUNS ] && { echo BASH-STILL-RUNS; exit 3; }; fi
done
run --local --shell "\$S" > "\$H/out1" 2>&1; echo "install=\$?"
[ -x "\$H/.local/bin/bs" ] && [ -f "\$H/.local/lib/bs/bootstrap/init.sh" ] && [ -f "\$H/.local/lib/bs/.install" ] && echo files=ok
rc=\$H/.profile; [ "\$S" = zsh ] && rc=\$H/.zshrc
grep -q '.local/bin' "\$rc" 2>/dev/null && echo path=ok
run --local --shell "\$S" > "\$H/out2" 2>&1; echo "again=\$?"
grep -q 'УЖЕ УСТАНОВЛЕНО' "\$H/out2" && echo refused=ok
run --local uninstall --shell "\$S" > "\$H/out3" 2>&1; echo "uninstall=\$?"
[ ! -e "\$H/.local/lib/bs" ] && [ ! -e "\$H/.local/bin/bs" ] && echo removed=ok
if grep -q '.local/bin' "\$rc" 2>/dev/null; then echo path-left; else echo pathgone=ok; fi
RUNNER
}

main() {
    T="$(mktemp -d)"
    testframework::section "Install without bash / Установка без bash"
    if ! command -v unshare >/dev/null 2>&1 || ! command -v busybox >/dev/null 2>&1 || ! unshare -Urm true 2>/dev/null; then
        echo "skip: unshare -Urm or busybox is not available — NOT verified / недоступны unshare -Urm или busybox — НЕ проверено"
        rm -rf "${T:?}"
        testframework::summary
        return 0
    fi
    : > "${T}/nobash"; chmod +x "${T}/nobash"
    local sb="${T}/sb" tool p sh_name sh_bin out H
    mkdir -p "${sb}/bin"
    for tool in busybox printf ls cat head tail tr sed grep readlink mktemp cp mv rm chmod mkdir rmdir dirname basename wc cut od env uname id date git sort touch awk find; do
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
        testframework::assert_equal "install=0 files=ok path=ok again=1 refused=ok uninstall=0 removed=ok pathgone=ok" "${out}" "${sh_name}: the whole life cycle with no bash on the machine" || true
    done
    rm -rf "${T:?}"
    testframework::summary
}

main "$@"
