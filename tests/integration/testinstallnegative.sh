#!/usr/bin/env bs
# shellcheck shell=bash
# tests/integration/testinstallnegative.sh — Installer negative scenarios
# tests/integration/testinstallnegative.sh — Негативные сценарии установщика
#
# БЕЗОПАСНОСТЬ / SAFETY: каждый сценарий живёт в своём каталоге внутри
# mktemp -d: HOME=$E/home, BS_SYSTEM_PREFIX=$E/sys, PATH=/usr/bin:/bin.
# Реальные ~/.local, /usr/local и PATH пользователя не затрагиваются.
# Every scenario lives in its own mktemp -d directory: HOME=$E/home,
# BS_SYSTEM_PREFIX=$E/sys, PATH=/usr/bin:/bin. The real ~/.local, /usr/local
# and the user's PATH are never touched. Root is not required (cases that
# rely on permission bits are skipped under root).
#
# BS_INSTALLER=<path> — прогнать тесты против другой копии install.sh (для
# проверки «падал бы до фикса»); BS_TEST_ONLY=<regex> — только подходящие тесты.
# BS_INSTALLER=<path> runs the tests against another install.sh copy (to
# prove a test fails before a fix); BS_TEST_ONLY=<regex> selects tests.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly INSTALLER="${BS_INSTALLER:-${BS_PROJECT_ROOT}/install.sh}"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Упавшая проверка не должна обрывать прогон: итог даёт testframework::summary.
# A failed assertion must not abort the run: testframework::summary decides.
set +e

readonly TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/bs_install_neg.XXXXXX")"
# Часть сценариев делает каталоги недоступными — вернуть права перед rm.
# Some scenarios make directories unreadable — restore modes before rm.
trap 'chmod -R u+rwX "${TMP_ROOT}" 2>/dev/null || true; rm -rf "${TMP_ROOT}"' EXIT

IS_ROOT=0
[[ "$(id -u)" -eq 0 ]] && IS_ROOT=1

E=""      # каталог текущего сценария / current scenario directory
OUT=""    # вывод последнего запуска / output of the last run
RC=0      # код выхода последнего запуска / exit code of the last run
INST_PATH="/usr/bin:/bin"

# Новое изолированное окружение: $E/home, $E/sys
new_env() {
    E="$(mktemp -d "${TMP_ROOT}/e.XXXXXX")"
    mkdir -p "${E}/home" "${E}/sys"
    INST_PATH="/usr/bin:/bin"
}

# Запуск установщика: run [VAR=val ...] -- args...   (OUT, RC)
run() {
    local -a envs=()
    while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done
    shift
    RC=0
    OUT="$(cd "${E}" && env -i HOME="${E}/home" PATH="${INST_PATH}" BS_SYSTEM_PREFIX="${E}/sys" \
        "${envs[@]}" "${TEST_BASH}" "${INSTALLER}" "$@" 2>&1)" || RC=$?
}

# Копия источника установщика (для сломанных источников) в $E/src
mk_src() {
    mkdir -p "${E}/src"
    cp -a "${BS_PROJECT_ROOT}/install.sh" "${BS_PROJECT_ROOT}/install" \
          "${BS_PROJECT_ROOT}/bootstrap" "${BS_PROJECT_ROOT}/core" \
          "${BS_PROJECT_ROOT}/lib" "${BS_PROJECT_ROOT}/bs" "${E}/src/"
}

# Проверки / Assertions
# Вывод без рамок и переносов: фраза может быть разорвана рамкой.
# Output without frame borders and line breaks: a frame may split a phrase.
flat() {
    local s="${OUT//│/}"
    s="${s//$'\n'/ }"
    while [[ "${s}" == *"  "* ]]; do s="${s//  / }"; done
    printf '%s' "${s}"
}
has() {   # has "<phrase>" "<name>"  — OUT содержит фразу
    if grep -qF -- "$1" <<< "$(flat)"; then
        testframework::assert_true "true" "$2"
    else
        testframework::assert_true "false" "$2"
        printf '    phrase not found / фраза не найдена: %s\n    output / вывод:\n%s\n' "$1" "${OUT}" | head -30
    fi
}
lacks() {  # lacks "<phrase>" "<name>"
    if grep -qF -- "$1" <<< "$(flat)"; then
        testframework::assert_true "false" "$2"
    else
        testframework::assert_true "true" "$2"
    fi
}
rc_is() { testframework::assert_equal "$1" "${RC}" "$2"; }
exists()  { testframework::assert_command "test -e '$1' -o -L '$1'" "$2"; }
absent()  { testframework::assert_command "test ! -e '$1' -a ! -L '$1'" "$2"; }
unchanged() {   # unchanged <file> <cksum-before> <name>
    local now
    now="$(cksum < "$1" 2>/dev/null || echo missing)"
    testframework::assert_equal "$2" "${now}" "$3"
}

# --------------------------------------------------------------------------
# 4. Чужие файлы / Foreign files
# --------------------------------------------------------------------------

t_foreign_lib_install() {
    new_env
    local pre="${E}/pre"
    mkdir -p "${pre}/lib/bs"; echo precious > "${pre}/lib/bs/data.txt"
    run PREFIX="${pre}" -- --local install
    rc_is 1 "foreign TARGET_LIB: install refused (exit 1)"
    has "не установка BS" "foreign TARGET_LIB: RU explanation"
    has "is not a BS install" "foreign TARGET_LIB: EN explanation"
    has "nothing was deleted" "foreign TARGET_LIB: says nothing was deleted"
    testframework::assert_command "grep -qx precious '${pre}/lib/bs/data.txt'" "foreign TARGET_LIB: user data intact"
    absent "${pre}/bin/bs" "foreign TARGET_LIB: no wrapper created"
}

t_source_like_lib_install() {
    new_env
    local pre="${E}/pre"
    mkdir -p "${pre}/lib/bs/.git" "${pre}/lib/bs/bootstrap"; touch "${pre}/lib/bs/bootstrap/init.sh" "${pre}/lib/bs/bs"
    run PREFIX="${pre}" -- --local
    rc_is 1 "checkout-like TARGET_LIB (.git): install refused"
    has "исходный репозиторий" "checkout-like TARGET_LIB: reason is named"
    exists "${pre}/lib/bs/.git" "checkout-like TARGET_LIB: .git survives"

    new_env; pre="${E}/pre"
    mkdir -p "${pre}/lib/bs/tests" "${pre}/lib/bs/bootstrap"; touch "${pre}/lib/bs/bootstrap/init.sh" "${pre}/lib/bs/bs"
    run PREFIX="${pre}" -- --local
    rc_is 1 "TARGET_LIB with tests/: install refused"
    exists "${pre}/lib/bs/tests" "TARGET_LIB with tests/ survives"
}

t_symlink_and_file_lib_install() {
    new_env
    local pre="${E}/pre"
    mkdir -p "${pre}/lib" "${E}/real"; echo keep > "${E}/real/f"
    ln -s "${E}/real" "${pre}/lib/bs"
    run PREFIX="${pre}" -- --local
    rc_is 1 "symlink TARGET_LIB: install refused"
    has "символическая ссылка" "symlink TARGET_LIB: reason is named"
    testframework::assert_command "grep -qx keep '${E}/real/f'" "symlink TARGET_LIB: link target intact"

    new_env; pre="${E}/pre"
    mkdir -p "${pre}/lib"; echo i-am-a-file > "${pre}/lib/bs"
    run PREFIX="${pre}" -- --local
    rc_is 1 "file in place of TARGET_LIB: install refused"
    testframework::assert_command "grep -qx i-am-a-file '${pre}/lib/bs'" "file in place of TARGET_LIB intact"
}

t_foreign_bin_install() {
    new_env
    local pre="${E}/pre"
    mkdir -p "${pre}/bin"; printf '#!/bin/sh\necho mine\n' > "${pre}/bin/bs"
    local before; before="$(cksum < "${pre}/bin/bs")"
    run PREFIX="${pre}" -- --local
    rc_is 1 "foreign TARGET_BIN: install refused (exit 1)"
    has "не wrapper BS" "foreign TARGET_BIN: RU explanation"
    has "not a BS wrapper" "foreign TARGET_BIN: EN explanation"
    unchanged "${pre}/bin/bs" "${before}" "foreign TARGET_BIN: file not overwritten"
    absent "${pre}/lib/bs" "foreign TARGET_BIN: no lib created"
}

t_other_wrapper_install() {
    new_env
    run PREFIX="${E}/a" -- --local
    rc_is 0 "setup: install A"
    local before; before="$(cksum < "${E}/a/bin/bs")"
    run PREFIX="${E}/b" BIN_DIR="${E}/a/bin" -- --local
    rc_is 1 "wrapper of another live install: install refused"
    has "wrapper другой установки" "wrapper of another install: explained"
    has "bs update --lib ${E}/a/lib/bs" "wrapper of another install: exact update command"
    unchanged "${E}/a/bin/bs" "${before}" "wrapper of install A not overwritten"
    absent "${E}/b/lib/bs" "install B was not started"
}

t_stale_wrapper_install() {
    new_env
    mkdir -p "${E}/pre/bin"
    printf '#!/usr/bin/env bash\nexport BS_ROOT="/nonexistent/lib/bs"\nexec "${BS_ROOT}/bs" "$@"\n' > "${E}/pre/bin/bs"
    run PREFIX="${E}/pre" -- --local
    rc_is 0 "stale BS wrapper: install proceeds"
    has "несуществующую" "stale BS wrapper: reported"
    testframework::assert_command "grep -q 'export BS_ROOT=\"${E}/pre/lib/bs\"' '${E}/pre/bin/bs'" "stale wrapper now points to the new lib"
}

t_uninstall_foreign_lib() {
    new_env
    local pre="${E}/pre"
    mkdir -p "${pre}/lib/bs"; echo precious > "${pre}/lib/bs/data.txt"
    run PREFIX="${pre}" -- --local uninstall
    rc_is 0 "uninstall of a foreign TARGET_LIB: harmless no-op (exit 0)"
    has "УДАЛЯТЬ НЕЧЕГО / NOTHING TO REMOVE" "uninstall of a foreign TARGET_LIB: frame title"
    has "не удаляю" "uninstall of a foreign TARGET_LIB: reason"
    testframework::assert_command "grep -qx precious '${pre}/lib/bs/data.txt'" "uninstall keeps the foreign directory"
}

t_uninstall_foreign_bin() {
    new_env
    run -- --local
    printf '#!/bin/sh\necho mine\n' > "${E}/home/.local/bin/bs"
    local before; before="$(cksum < "${E}/home/.local/bin/bs")"
    run -- --local uninstall
    rc_is 0 "uninstall with a foreign wrapper: exit 0"
    has "ЧАСТЬ НЕ УДАЛЕНА / PART LEFT IN PLACE" "uninstall with a foreign wrapper: frame"
    has "не wrapper BS" "uninstall with a foreign wrapper: reason"
    unchanged "${E}/home/.local/bin/bs" "${before}" "uninstall keeps the foreign wrapper"
    absent "${E}/home/.local/lib/bs" "uninstall still removes the BS lib"
}

t_uninstall_other_wrapper() {
    new_env
    run PREFIX="${E}/a" -- --local
    local before; before="$(cksum < "${E}/a/bin/bs")"
    run PREFIX="${E}/b" BIN_DIR="${E}/a/bin" -- --local uninstall
    rc_is 0 "uninstall: wrapper of another install is not ours (exit 0)"
    has "wrapper другой установки" "uninstall: another install's wrapper explained"
    unchanged "${E}/a/bin/bs" "${before}" "uninstall keeps the wrapper of install A"
    exists "${E}/a/lib/bs/bs" "install A lib intact"
}

# --------------------------------------------------------------------------
# 1. Права записи вместо EUID / Write access instead of EUID
# --------------------------------------------------------------------------

t_unwritable_system() {
    (( IS_ROOT )) && { printf "  ⊘ Skipping: running as root (permission bits do not apply)\n"; return 0; }
    new_env
    mkdir -p "${E}/ro"; chmod 555 "${E}/ro"
    run BS_SYSTEM_PREFIX="${E}/ro" -- install
    rc_is 1 "system install without write access exits 1"
    has "Нет прав записи" "no write access: RU reason"
    has "No write permission" "no write access: EN reason"
    has "sudo ./install.sh" "no write access: sudo hint"
    has "./install.sh --local" "no write access: --local hint"
    absent "${E}/ro/bin" "no write access: nothing created"
    chmod 755 "${E}/ro"
}

t_writable_prefix_without_root() {
    new_env
    run PATH="${INST_PATH}" PREFIX="${E}/opt/x" -- install
    rc_is 0 "user-writable PREFIX installs without root"
    exists "${E}/opt/x/bin/bs" "custom PREFIX: wrapper created"
    # Scenario 7: BIN_DIR вне PATH — подсказка (не только для --local)
    has "нет в PATH" "custom PREFIX: BIN_DIR-not-in-PATH hint (RU)"
    has "is not in PATH" "custom PREFIX: BIN_DIR-not-in-PATH hint (EN)"
    has "export PATH=\"${E}/opt/x/bin" "custom PREFIX: exact export line"
    testframework::assert_command "grep -qx 'mode=custom' '${E}/opt/x/lib/bs/.install'" "custom PREFIX: manifest mode=custom"
    absent "${E}/home/.bashrc" "custom (non-local) install does not touch .bashrc"
    # BIN_DIR в PATH — подсказки нет
    new_env
    INST_PATH="${E}/opt/x/bin:/usr/bin:/bin"
    run PREFIX="${E}/opt/x" -- install
    rc_is 0 "install with BIN_DIR in PATH exits 0"
    lacks "нет в PATH" "no PATH hint when BIN_DIR is already in PATH"
}

t_unwritable_custom_prefix() {
    (( IS_ROOT )) && { printf "  ⊘ Skipping: running as root\n"; return 0; }
    new_env
    mkdir -p "${E}/ro"; chmod 555 "${E}/ro"
    run PREFIX="${E}/ro/deep/x" -- install
    rc_is 1 "unwritable custom PREFIX exits 1"
    has "ближайший существующий каталог: ${E}/ro" "unwritable custom PREFIX: names the nearest existing dir"
    has "PREFIX=" "unwritable custom PREFIX: suggests another PREFIX"
    chmod 755 "${E}/ro"
}

# --------------------------------------------------------------------------
# 2. sudo --local / HOME
# --------------------------------------------------------------------------

t_sudo_local_refused() {
    new_env
    run BS_INSTALL_FAKE_EUID=0 SUDO_USER=alice BS_INSTALL_SUDO_HOME="${E}/home" -- --local
    rc_is 1 "sudo --local into the sudo user's home: refused"
    has "Запустите без sudo" "sudo --local: RU hint"
    has "Run without sudo" "sudo --local: EN hint"
    absent "${E}/home/.local" "sudo --local refusal: nothing installed"
    absent "${E}/home/.config" "sudo --local refusal: bootstrap did not touch the user's home"
}

t_sudo_local_root_home() {
    new_env
    mkdir -p "${E}/rootenv"
    run HOME="${E}/rootenv" BS_INSTALL_FAKE_EUID=0 SUDO_USER=alice BS_INSTALL_SUDO_HOME="${E}/alice" -- --local
    rc_is 0 "sudo --local with root's own HOME: continues"
    has "а не для пользователя alice" "sudo --local with root HOME: RU notice"
    has "not to user alice" "sudo --local with root HOME: EN notice"
    exists "${E}/rootenv/.local/bin/bs" "installed into root's HOME"
}

t_home_problems() {
    new_env
    RC=0
    OUT="$(env -i PATH="/usr/bin:/bin" BS_SYSTEM_PREFIX="${E}/sys" ${TEST_BASH} "${INSTALLER}" --local 2>&1)" || RC=$?
    rc_is 1 "HOME unset: exit 1"
    has "HOME не задан" "HOME unset: RU explanation"
    lacks "unbound variable" "HOME unset: no raw unbound variable"

    run HOME= -- --local
    rc_is 1 "HOME empty: exit 1"
    has "HOME is unset or empty" "HOME empty: EN explanation"

    run HOME="${E}/nonexistent" -- --local
    rc_is 1 "HOME is not a directory: exit 1"
    absent "${E}/nonexistent" "HOME missing: installer did not create it"

    (( IS_ROOT )) && return 0
    mkdir -p "${E}/rohome"; chmod 555 "${E}/rohome"
    run HOME="${E}/rohome" -- --local
    rc_is 1 "read-only HOME: exit 1"
    has "Нет прав записи" "read-only HOME: explained"
    chmod 755 "${E}/rohome"
}

# --------------------------------------------------------------------------
# 3, 5, 6. Уже установлено, полуустановка, другая установка
# --------------------------------------------------------------------------

t_already_installed() {
    new_env
    run -- --local
    local before; before="$(cksum < "${E}/home/.local/lib/bs/.install")"
    run -- --local
    rc_is 1 "second install exits 1"
    has "УЖЕ УСТАНОВЛЕНО / ALREADY INSTALLED" "already installed: bilingual frame"
    has "bs update --local" "already installed: update command"
    has "uninstall" "already installed: uninstall option"
    has "PREFIX=" "already installed: another-PREFIX option"
    has "version" "already installed: shows the version"
    unchanged "${E}/home/.local/lib/bs/.install" "${before}" "already installed: install untouched"

    # Совет должен быть выполнимым: команда из репозитория не требует PATH
    # The advice must be runnable: the repository command needs no PATH
    has "bs update --local" "already installed: the installed-copy command is listed"
    has "Установлена та же версия" "already installed: the same version is reported"
    has "не найдена в PATH" "already installed: tells that bs is not in the PATH of this shell"
    has "update --local" "already installed: the repository command is listed"

    # bs в PATH этой оболочки — предупреждения нет
    INST_PATH="/usr/bin:/bin:${E}/home/.local/bin" run -- --local
    rc_is 1 "bs is in PATH: still refuses to reinstall"
    lacks "не найдена в PATH" "bs in PATH: no PATH warning"

    # В PATH раньше идёт чужой bs — предупреждение о другой копии
    mkdir -p "${E}/other"
    printf '#!/bin/sh\nexit 0\n' > "${E}/other/bs"; chmod +x "${E}/other/bs"
    INST_PATH="${E}/other:/usr/bin:/bin" run -- --local
    has "запускается другая копия" "another bs first in PATH: the notice names it"
    has "${E}/other/bs" "another bs first in PATH: its path is printed"

    # Установленная версия старее / новее источника
    sed -i 's/BS_VERSION="[0-9.]*"/BS_VERSION="0.0.1"/' "${E}/home/.local/lib/bs/core/version.sh"
    INST_PATH="/usr/bin:/bin" run -- --local
    has "Доступно обновление" "older install: an update is announced"
    has "0.0.1 →" "older install: shows installed → source"
    sed -i 's/BS_VERSION="[0-9.]*"/BS_VERSION="99.0.0"/' "${E}/home/.local/lib/bs/core/version.sh"
    run -- --local
    has "НОВЕЕ этого источника" "newer install: a downgrade warning"
}

t_half_install() {
    new_env
    run -- --local
    rm -f "${E}/home/.local/bin/bs"
    run -- --local
    rc_is 0 "lib without wrapper: repaired"
    has "НЕПОЛНАЯ УСТАНОВКА" "lib without wrapper: frame"
    has "lib без wrapper" "lib without wrapper: names what was found"
    exists "${E}/home/.local/bin/bs" "lib without wrapper: wrapper recreated"

    rm -rf "${E}/home/.local/lib/bs"
    run -- --local
    rc_is 0 "wrapper without lib: repaired"
    has "без lib" "wrapper without lib: names what was found"
    exists "${E}/home/.local/lib/bs/bs" "wrapper without lib: lib recreated"
    local v_out
    v_out="$(env -i HOME="${E}/home" "${E}/home/.local/bin/bs" version 2>&1)"
    testframework::assert_command "grep -q 'BS Framework version' <<< '${v_out}'" "repaired install runs"
}

t_other_install_notice() {
    new_env
    run PREFIX="${E}/sys" -- install
    rc_is 0 "setup: system-like install"
    local before; before="$(cksum < "${E}/sys/bin/bs")"
    INST_PATH="${E}/sys/bin:/usr/bin:/bin"
    run -- --local
    rc_is 0 "local install next to a system one: exit 0"
    has "ЕСТЬ ДРУГАЯ УСТАНОВКА / ANOTHER INSTALL EXISTS" "other install: frame"
    has "system: ${E}/sys/lib/bs" "other install: names the found install"
    has "version" "other install: shows versions"
    has "запускает ДРУГУЮ копию" "other install: PATH order consequence (other copy wins)"
    has "./install.sh uninstall" "other install: removal command"
    unchanged "${E}/sys/bin/bs" "${before}" "system wrapper untouched by local install"

    new_env
    run PREFIX="${E}/sys" -- install
    INST_PATH="${E}/home/.local/bin:${E}/sys/bin:/usr/bin:/bin"
    run -- --local
    has "запускает НОВУЮ копию" "other install: PATH order consequence (new copy wins)"
}

# --------------------------------------------------------------------------
# 7. PATH
# --------------------------------------------------------------------------

t_local_custom_bindir_path() {
    new_env
    run BIN_DIR="${E}/cbin" -- --local
    rc_is 0 "local install with custom BIN_DIR: exit 0"
    has "АВТО-НАСТРОЙКА PATH НЕ ВЫПОЛНЕНА" "custom BIN_DIR: auto setup skipped, explained"
    has "export PATH=\"${E}/cbin" "custom BIN_DIR: exact hint"
    testframework::assert_command "! grep -qs '.local/bin' '${E}/home/.bashrc'" "custom BIN_DIR: .bashrc not touched with a wrong line"
}

t_rc_readonly_on_install() {
    (( IS_ROOT )) && { printf "  ⊘ Skipping: running as root\n"; return 0; }
    new_env
    : > "${E}/home/.bashrc"; chmod 444 "${E}/home/.bashrc"
    run -- --local
    rc_is 0 "read-only .bashrc does not abort a finished install"
    has "не удалось записать" "read-only .bashrc: RU explanation"
    has "export PATH=" "read-only .bashrc: shows the line to add"
    exists "${E}/home/.local/bin/bs" "read-only .bashrc: install is complete"
}

t_rc_symlink_uninstall() {
    new_env
    mkdir -p "${E}/dot"; : > "${E}/dot/bashrc"; ln -s "${E}/dot/bashrc" "${E}/home/.bashrc"
    run -- --local
    testframework::assert_command "grep -qx 'export PATH=\"\$HOME/.local/bin:\$PATH\"' '${E}/dot/bashrc'" "setup: line written through the symlink"
    run -- --local uninstall
    rc_is 0 "uninstall with a symlinked .bashrc: exit 0"
    testframework::assert_command "test -L '${E}/home/.bashrc'" ".bashrc stays a symlink"
    testframework::assert_command "! grep -q '.local/bin' '${E}/dot/bashrc'" "PATH line removed from the symlink target"
}

t_uninstall_keeps_std_path_line() {
    new_env
    run -- --local
    run BIN_DIR="${E}/cbin" LIB_DIR="${E}/clib" -- --local
    run BIN_DIR="${E}/cbin" LIB_DIR="${E}/clib" -- --local uninstall
    rc_is 0 "uninstall of a custom copy: exit 0"
    has "PATH-строка в rc-файлах оставлена" "custom uninstall keeps the PATH line: explained"
    testframework::assert_command "grep -q '.local/bin' '${E}/home/.bashrc'" "PATH line of the standard local install survives"
    exists "${E}/home/.local/bin/bs" "standard local install survives"
}

# --------------------------------------------------------------------------
# 8. Транзакционность / Transactional install
# --------------------------------------------------------------------------

t_transaction_fresh_failure() {
    (( IS_ROOT )) && { printf "  ⊘ Skipping: running as root (cp ignores modes)\n"; return 0; }
    new_env; mk_src
    chmod 000 "${E}/src/lib/io"
    RC=0
    OUT="$(env -i HOME="${E}/home" PATH="/usr/bin:/bin" BS_SYSTEM_PREFIX="${E}/sys" ${TEST_BASH} "${E}/src/install.sh" --local 2>&1)" || RC=$?
    chmod 755 "${E}/src/lib/io"
    rc_is 1 "copy failure: exit 1"
    has "Установка не выполнена" "copy failure: RU ERROR"
    has "Install failed" "copy failure: EN ERROR"
    has "Причина / Reason: cp:" "copy failure: real reason shown"
    absent "${E}/home/.local/lib/bs" "copy failure: no half-installed lib"
    absent "${E}/home/.local/bin/bs" "copy failure: no wrapper"
    testframework::assert_equal "" "$(ls -A "${E}/home/.local/lib")" "copy failure: no temporary leftovers"
}

t_transaction_keeps_previous() {
    (( IS_ROOT )) && { printf "  ⊘ Skipping: running as root\n"; return 0; }
    new_env; mk_src
    run -- --local
    echo mark > "${E}/home/.local/lib/bs/MARK"
    rm -f "${E}/home/.local/bin/bs"          # полуустановка → переустановка / half → reinstall
    chmod 000 "${E}/src/lib/io"
    RC=0
    OUT="$(env -i HOME="${E}/home" PATH="/usr/bin:/bin" BS_SYSTEM_PREFIX="${E}/sys" ${TEST_BASH} "${E}/src/install.sh" --local 2>&1)" || RC=$?
    chmod 755 "${E}/src/lib/io"
    rc_is 1 "failed reinstall: exit 1"
    has "Прежняя установка не тронута" "failed reinstall: says the previous install is untouched"
    exists "${E}/home/.local/lib/bs/MARK" "failed reinstall: previous lib is intact"
    testframework::assert_equal "bs" "$(ls -A "${E}/home/.local/lib")" "failed reinstall: no temporary leftovers"
}

# --------------------------------------------------------------------------
# 9. Неполный источник / Incomplete source
# --------------------------------------------------------------------------

t_incomplete_source() {
    new_env; mk_src
    rm -rf "${E}/src/lib" "${E}/src/bs" "${E}/src/core/logger.sh"
    RC=0
    OUT="$(env -i HOME="${E}/home" PATH="/usr/bin:/bin" BS_SYSTEM_PREFIX="${E}/sys" ${TEST_BASH} "${E}/src/install.sh" --local 2>&1)" || RC=$?
    rc_is 1 "incomplete source: exit 1"
    has "Источник установщика неполон" "incomplete source: RU ERROR"
    has "The installer source is incomplete" "incomplete source: EN ERROR"
    has "- lib/" "incomplete source: names lib/"
    has "- bs" "incomplete source: names bs"
    has "- core/logger.sh" "incomplete source: names core/logger.sh"
    absent "${E}/home/.local" "incomplete source: nothing installed"
}

# --------------------------------------------------------------------------
# Пути / Paths
# --------------------------------------------------------------------------

t_bad_paths() {
    new_env
    run PREFIX="relative/dir" -- --local
    rc_is 1 "relative PREFIX: refused"
    has "абсолютным" "relative PREFIX: explained"

    run PREFIX="${E}/we\$ird" -- --local
    rc_is 1 "PREFIX with \$: refused"
    has "запрещённые символы" "PREFIX with \$: explained"

    run BIN_DIR="${E}/same" LIB_DIR="${E}/same" -- --local
    rc_is 1 "BIN_DIR == LIB_DIR: refused"
    has "совпадают" "BIN_DIR == LIB_DIR: explained"
    absent "${E}/same" "bad paths: nothing created"
}

# --------------------------------------------------------------------------
# 11. Удаление: не тот вид / Uninstall of the wrong kind
# --------------------------------------------------------------------------

t_uninstall_local_when_only_system() {
    new_env
    run PREFIX="${E}/sys" -- install
    local before; before="$(cksum < "${E}/sys/bin/bs")"
    run -- --local uninstall
    rc_is 0 "--local uninstall with only a system install: exit 0"
    has "УДАЛЯТЬ НЕЧЕГО / NOTHING TO REMOVE" "wrong kind: frame"
    has "есть системная установка" "wrong kind: RU pointer"
    has "a system install exists" "wrong kind: EN pointer"
    has "sudo ./install.sh uninstall" "wrong kind: exact command"
    unchanged "${E}/sys/bin/bs" "${before}" "wrong kind: system install untouched"
}

t_uninstall_system_when_only_local() {
    new_env
    run -- --local
    # Явно системный (PREFIX = системный префикс), а есть только local.
    # Explicit system target while only a local install exists.
    run PREFIX="${E}/sys" -- uninstall
    rc_is 0 "system uninstall with only a local install: exit 0"
    has "но есть локальная установка" "wrong kind: RU pointer to the local install"
    has "./install.sh --local uninstall" "wrong kind: exact command"
    exists "${E}/home/.local/lib/bs/bs" "wrong kind: local install untouched"
}

t_uninstall_nothing() {
    new_env
    run -- uninstall
    rc_is 0 "nothing installed: exit 0"
    has "не установлена" "nothing installed: RU"
    has "is not installed" "nothing installed: EN"
    has "${E}/sys/lib/bs" "nothing installed: names the checked system path"
}

t_uninstall_partial() {
    new_env
    run -- --local
    rm -rf "${E}/home/.local/lib/bs"
    run -- --local uninstall
    rc_is 0 "wrapper without lib: uninstall exit 0"
    absent "${E}/home/.local/bin/bs" "wrapper without lib: wrapper removed"

    new_env
    run -- --local
    rm -f "${E}/home/.local/bin/bs"
    run -- --local uninstall
    rc_is 0 "lib without wrapper: uninstall exit 0"
    absent "${E}/home/.local/lib/bs" "lib without wrapper: lib removed"
    has "No wrapper" "lib without wrapper: says no wrapper"
}

t_uninstall_unwritable() {
    (( IS_ROOT )) && { printf "  ⊘ Skipping: running as root\n"; return 0; }
    new_env
    run PREFIX="${E}/sys" -- install
    chmod 555 "${E}/sys/bin" "${E}/sys/lib"
    run PREFIX="${E}/sys" -- uninstall
    chmod 755 "${E}/sys/bin" "${E}/sys/lib"
    rc_is 1 "uninstall without write access: exit 1"
    has "Нет прав записи" "uninstall without write access: explained"
    has "sudo" "uninstall without write access: sudo hint"
    exists "${E}/sys/lib/bs/bs" "uninstall without write access: lib intact"
}

# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

t_help_and_unknown() {
    new_env
    run -- --help
    rc_is 0 "--help exits 0"
    has "Установщик BS" "usage: RU"
    has "BS_SYSTEM_PREFIX" "usage: documents BS_SYSTEM_PREFIX"
    has "bs update" "usage: points to bs update"
    has "never overwrites or deletes foreign files" "usage: EN safety note"
    run -- --bogus
    rc_is 1 "unknown argument exits 1"
    has "Unknown argument" "unknown argument: EN"
}

main() {
    print_header "Installer Negative Scenarios / Негативные сценарии установщика"
    testframework::init

    local -a tests=(
        t_foreign_lib_install t_source_like_lib_install t_symlink_and_file_lib_install
        t_foreign_bin_install t_other_wrapper_install t_stale_wrapper_install
        t_uninstall_foreign_lib t_uninstall_foreign_bin t_uninstall_other_wrapper
        t_unwritable_system t_writable_prefix_without_root t_unwritable_custom_prefix
        t_sudo_local_refused t_sudo_local_root_home t_home_problems
        t_already_installed t_half_install t_other_install_notice
        t_local_custom_bindir_path t_rc_readonly_on_install t_rc_symlink_uninstall
        t_uninstall_keeps_std_path_line
        t_transaction_fresh_failure t_transaction_keeps_previous
        t_incomplete_source t_bad_paths
        t_uninstall_local_when_only_system t_uninstall_system_when_only_local
        t_uninstall_nothing t_uninstall_partial t_uninstall_unwritable
        t_help_and_unknown
    )
    local t
    for t in "${tests[@]}"; do
        if [[ -n "${BS_TEST_ONLY:-}" && ! "${t}" =~ ${BS_TEST_ONLY} ]]; then
            continue
        fi
        testframework::section "${t}"
        "${t}"
    done

    testframework::summary
}

main "$@"
