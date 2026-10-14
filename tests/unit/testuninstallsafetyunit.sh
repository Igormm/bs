#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testuninstallsafetyunit.sh — negative scenarios of `bs uninstall`, `bs version --full`, `bs env`
# tests/unit/testuninstallsafetyunit.sh — негативные сценарии `bs uninstall`, `bs version --full`, `bs env`
#
# Everything runs in mktemp -d with its own HOME, PATH and BS_SYSTEM_PREFIX:
# a real install of the user (~/.local, /usr/local) is never visible or touched.
# Всё выполняется в mktemp -d со своими HOME, PATH и BS_SYSTEM_PREFIX:
# настоящая установка пользователя (~/.local, /usr/local) не видна и не трогается.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly BS_CLI="${BS_UPDATE_TEST_CLI:-${BS_PROJECT_ROOT}/bs}"
REAL_HOME="${HOME}"
readonly REAL_HOME

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

T=""
OUT=""
RC=0
RAW=""

# Песочница: HOME, PATH (только bin песочницы + системные), префикс system.
# Sandbox: HOME, PATH (sandbox bin + system dirs only), system prefix.
sandbox() {
    T="$(mktemp -d)"
    mkdir -p "${T}/home" "${T}/bin" "${T}/sys" "${T}/tmpd"
}

make_src() {
    local -r dir="$1" ver="${2:-9.9.9}"
    mkdir -p "${dir}/core" "${dir}/lib" "${dir}/bootstrap"
    printf '#!/usr/bin/env bash\ncase "${1:-}" in version) echo "BS Framework version: %s";; esac\n' "${ver}" > "${dir}/bs"
    printf '#!/usr/bin/env bash\n' > "${dir}/bootstrap/init.sh"
    printf '#!/usr/bin/env bash\n' > "${dir}/bootstrap/loader.sh"
    printf 'export BS_VERSION="%s"\n' "${ver}" > "${dir}/core/version.sh"
    printf 'mod_%s\n' "${ver}" > "${dir}/lib/mod.sh"
}

make_inst() {
    make_src "$@"
    printf 'mode=custom\n' > "$1/.install"
}

# Обёртка bs, как у install.sh / a bs wrapper like install.sh writes
make_wrapper() {
    printf '#!/usr/bin/env bash\nexport BS_ROOT="%s"\nexec "${BS_ROOT}/bs" "$@"\n' "$2" > "$1"
    chmod +x "$1"
}

# Контрольная сумма дерева (имена + содержимое) / tree checksum (names + content)
tree_sum() {
    (cd "$1" && find . -type f -o -type l | LC_ALL=C sort | while IFS= read -r f; do
        printf '%s %s\n' "${f}" "$(cksum < "${f}" 2>/dev/null || echo L)"
    done | cksum)
}

# Запуск bs в песочнице: OUT = stdout+stderr, RC = код выхода.
# Run bs in the sandbox: OUT = stdout+stderr, RC = exit code.
run_bs() {
    OUT="$(cd "${T}" && env -u BS_ROOT -u BS_HOME -u BS_INITIALIZED -u SUDO_USER \
        HOME="${T}/home" PATH="${T}/bin:/usr/bin:/bin" BS_SYSTEM_PREFIX="${T}/sys" TMPDIR="${T}/tmpd" \
        "${TEST_BASH}" "${BS_CLI}" "$@" 2>&1 </dev/null)" && RC=0 || RC=$?
    RAW="${OUT}"
    OUT="$(flatten_boxes "${OUT}")"
}

# Склеить строки, перенесённые рамкой по 58 символов, и снять бордюры: тесты
# ищут фразы, а не позиции переноса. RAW хранит вывод как есть.
# Re-join lines the box wrapped at 58 characters and strip the borders: tests
# look for phrases, not wrap positions. RAW keeps the output as printed.
flatten_boxes() {
    local line content res=""
    while IFS= read -r line; do
        if [[ "${line}" == '│'* ]]; then
            content="${line#│}"
            content="${content%│}"
            if (( ${#content} >= 58 )); then
                res+="${content}"
            else
                content="${content%"${content##*[! ]}"}"
                res+="${content}"$'\n'
            fi
        else
            res+="${line}"$'\n'
        fi
    done <<< "$1"
    printf '%s' "${res}"
}

# y/n: содержит ли текст фразу (без grep-метасимволов) / does text contain the phrase
has() { if [[ "$1" == *"$2"* ]]; then printf 'y'; else printf 'n'; fi; }
eq()  { testframework::assert_equal "$1" "$2" "$3" || true; }
chk_cmd()  { testframework::assert_command "$1" "$2" || true; }
chk_true() { testframework::assert_true "$1" "$2" || true; }
leftovers() { find "$1" -maxdepth 1 \( -name '.update.*' -o -name '.update-old.*' -o -name '.update-lock' \) | wc -l | tr -d ' '; }

test_isolation() {
    sandbox
    local path_seen
    path_seen="$(env HOME="${T}/home" PATH="${T}/bin:/usr/bin:/bin" ${TEST_BASH} -c 'command -v bs || true')"
    eq "" "${path_seen}" "isolation: no bs in the test PATH"
    eq "n" "$(has ":${T}/bin:/usr/bin:/bin:" "${REAL_HOME}/.local/bin")" "isolation: real ~/.local/bin is not in the test PATH"
    rm -rf "${T}"
}

make_real_copy() {
    mkdir -p "$1"
    cp -a "${BS_PROJECT_ROOT}/bootstrap" "${BS_PROJECT_ROOT}/core" "${BS_PROJECT_ROOT}/lib" "${BS_PROJECT_ROOT}/bs" "$1/"
}

test_uninstall_missing() {
    sandbox
    make_inst "${T}/sys/lib/bs" 0.6.0
    local before; before="$(tree_sum "${T}/sys/lib/bs")"
    run_bs uninstall --local
    eq "1" "${RC}" "13: --local with a system-only install exits 1"
    eq "y" "$(has "${OUT}" "локальной установки нет")" "13: says there is no local install"
    eq "y" "$(has "${OUT}" "НИЧЕГО НЕ УДАЛЕНО")" "13: nothing removed box"
    eq "y" "$(has "${OUT}" "bs uninstall --system")" "13: suggests bs uninstall --system"
    eq "${before}" "$(tree_sum "${T}/sys/lib/bs")" "13: system install untouched"
    eq "y" "$(has "${RAW}" "Запущен / Running: bs ")" "13: running-copy summary present"
    rm -rf "${T}/sys"
    run_bs uninstall
    eq "1" "${RC}" "13: nothing installed exits 1"
    eq "y" "$(has "${OUT}" "УДАЛЯТЬ НЕЧЕГО")" "13: box title"
    rm -rf "${T}"
}

test_uninstall_foreign() {
    sandbox
    mkdir -p "${T}/foreign/lib"
    printf 'mine\n' > "${T}/foreign/lib/mine.txt"
    printf 'x\n' > "${T}/foreign/data"
    local before; before="$(tree_sum "${T}/foreign")"
    run_bs uninstall --lib "${T}/foreign"
    eq "1" "${RC}" "13: foreign directory exits 1"
    eq "y" "$(has "${OUT}" "не установка BS")" "13: explains it is not a BS install"
    eq "${before}" "$(tree_sum "${T}/foreign")" "13: foreign directory untouched"

    make_inst "${T}/repo" 0.8.0
    mkdir -p "${T}/repo/.git"
    before="$(tree_sum "${T}/repo")"
    run_bs uninstall --lib "${T}/repo"
    eq "1" "${RC}" "13: source checkout exits 1"
    eq "y" "$(has "${OUT}" "исходный репозиторий")" "13: explains it is a checkout"
    eq "${before}" "$(tree_sum "${T}/repo")" "13: checkout untouched"

    # Файл вместо каталога / a file instead of a directory
    printf 'x\n' > "${T}/afile"
    run_bs uninstall --lib "${T}/afile"
    eq "1" "${RC}" "13: a file as --lib exits 1"
    testframework::assert_command "test -f '${T}/afile'" "13: the file is untouched" || true
    rm -rf "${T}"
}

test_uninstall_wrapper() {
    sandbox
    make_inst "${T}/pre/lib/bs" 0.6.0
    mkdir -p "${T}/pre/bin"
    printf '#!/bin/sh\necho somebody elses bs\n' > "${T}/pre/bin/bs"
    run_bs uninstall --lib "${T}/pre/lib/bs"
    eq "0" "${RC}" "13: install with a foreign wrapper is removed (exit 0)"
    eq "y" "$(has "${OUT}" "обёртка не от этой установки")" "13: warns the wrapper is not ours"
    testframework::assert_command "test -f '${T}/pre/bin/bs'" "13: the foreign wrapper is left in place" || true
    testframework::assert_command "test ! -e '${T}/pre/lib/bs'" "13: the install itself is removed" || true

    make_inst "${T}/ok/lib/bs" 0.6.0
    mkdir -p "${T}/ok/bin"
    make_wrapper "${T}/ok/bin/bs" "${T}/ok/lib/bs"
    run_bs uninstall --lib "${T}/ok/lib/bs"
    eq "0" "${RC}" "13: install with its own wrapper is removed"
    testframework::assert_command "test ! -e '${T}/ok/bin/bs' && test ! -e '${T}/ok/bin'" "13: own wrapper and the empty bin dir removed" || true
    rm -rf "${T}"
}

test_uninstall_no_rights() {
    if (( EUID == 0 )); then
        testframework::assert_true "true" "skipped: running as root" || true
        return 0
    fi
    sandbox
    make_inst "${T}/sys/lib/bs" 0.6.0
    mkdir -p "${T}/sys/bin"
    make_wrapper "${T}/sys/bin/bs" "${T}/sys/lib/bs"
    chmod 555 "${T}/sys/lib" "${T}/sys/bin"
    local before; before="$(tree_sum "${T}/sys")"
    run_bs uninstall --system
    chmod 755 "${T}/sys/lib" "${T}/sys/bin"
    eq "1" "${RC}" "13: no rights and no terminal exits 1"
    eq "y" "$(has "${OUT}" "sudo bs uninstall --system")" "13: keeps the sudo hint"
    eq "${before}" "$(tree_sum "${T}/sys")" "13: nothing removed (wrapper stays with its lib)"
    rm -rf "${T}"
}

test_uninstall_self() {
    sandbox
    make_real_copy "${T}/prefix/lib/bs"
    mkdir -p "${T}/prefix/bin"
    make_wrapper "${T}/prefix/bin/bs" "${T}/prefix/lib/bs"
    OUT="$(cd "${T}" && env -u BS_HOME -u BS_INITIALIZED -u SUDO_USER HOME="${T}/home" PATH="${T}/prefix/bin:/usr/bin:/bin" \
        BS_SYSTEM_PREFIX="${T}/sys" "${TEST_BASH}" "${T}/prefix/bin/bs" uninstall --lib "${T}/prefix/lib/bs" 2>&1 </dev/null)" && RC=0 || RC=$?
    eq "0" "${RC}" "13: removing the copy that runs exits 0"
    eq "y" "$(has "${OUT}" "удаляется копия, из которой запущен bs")" "13: announces that the running copy is removed"
    eq "y" "$(has "${OUT%%$'\n'*}" "Запущен / Running: bs ")" "13: first line names the running copy"
    testframework::assert_command "test ! -e '${T}/prefix/lib/bs' && test ! -e '${T}/prefix/bin/bs'" "13: lib and wrapper are gone" || true
    rm -rf "${T}"
}

# bs version --full / bs env на странных входах
test_version_env_odd() {
    sandbox
    make_real_copy "${T}/real/lib/bs"
    head -c 300 /dev/urandom > "${T}/real/lib/bs/.install"
    local bsx="${T}/real/lib/bs/bs"
    OUT="$(cd "${T}" && env -u BS_ROOT -u BS_HOME -u BS_INITIALIZED HOME="${T}/home" PATH="/usr/bin:/bin" ${TEST_BASH} "${bsx}" version --full 2>&1 </dev/null)" && RC=0 || RC=$?
    eq "0" "${RC}" "13: version --full with a corrupt manifest exits 0"
    eq "y" "$(has "${OUT}" "манифест повреждён")" "13: version --full reports the corrupt manifest"
    OUT="$(cd "${T}" && env -u BS_ROOT -u BS_HOME -u BS_INITIALIZED HOME="${T}/home" PATH="/usr/bin:/bin" ${TEST_BASH} "${bsx}" env 2>&1 </dev/null)" && RC=0 || RC=$?
    eq "0" "${RC}" "13: env with a corrupt manifest exits 0"
    eq "y" "$(has "${OUT}" "манифест повреждён")" "13: env reports the corrupt manifest"

    rm -f "${T}/real/lib/bs/.install"
    OUT="$(cd "${T}" && env -u BS_ROOT -u BS_HOME -u BS_INITIALIZED HOME="${T}/home" PATH="/usr/bin:/bin" ${TEST_BASH} "${bsx}" version --full 2>&1 </dev/null)" && RC=0 || RC=$?
    eq "y" "$(has "${OUT}" "no manifest")" "13: version --full without a manifest says so"

    # Исходный репозиторий без git в PATH / a checkout with no git in PATH
    mkdir -p "${T}/tools"
    local f n
    for f in /usr/bin/*; do
        n="${f##*/}"
        [[ "${n}" == "git" ]] || ln -sf "${f}" "${T}/tools/${n}"
    done
    OUT="$(cd "${T}" && env -u BS_ROOT -u BS_HOME -u BS_INITIALIZED HOME="${T}/home" PATH="${T}/tools" "$(command -v bash)" "${BS_CLI}" version --full 2>&1 </dev/null)" && RC=0 || RC=$?
    eq "0" "${RC}" "13: version --full of a checkout without git exits 0"
    if [[ -e "${BS_PROJECT_ROOT}/.git" ]]; then
        eq "y" "$(has "${OUT}" "git not available")" "13: version --full says git is unavailable"
    fi
    run_bs version --bogus
    eq "1" "${RC}" "13: version with a bad argument exits 1"
    rm -rf "${T}"
}

main() {
    print_header "Uninstall Safety Unit Tests / Негативные сценарии bs uninstall"
    testframework::init

    testframework::section "Isolation / Изоляция"
    test_isolation
    testframework::section "Missing installs / Нет установок"
    test_uninstall_missing
    testframework::section "Foreign directories / Чужие каталоги"
    test_uninstall_foreign
    testframework::section "Wrappers / Обёртки"
    test_uninstall_wrapper
    testframework::section "No rights / Нет прав"
    test_uninstall_no_rights
    testframework::section "Self removal / Удаление себя"
    test_uninstall_self
    testframework::section "version --full, env"
    test_version_env_odd

    testframework::summary
}

main "$@"
