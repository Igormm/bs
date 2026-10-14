#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testauditcoreutilsunit.sh — audit regressions for core/utils
# tests/unit/testauditcoreutilsunit.sh — регрессии аудита для core/utils
#   - реестр временных файлов не доверяет чужому/подложенному файлу;
#   - utils::detect_root возвращает корень фреймворка, а не core/.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Дочерний bs-процесс: свой PID, своя подготовка реестра, затем обычный выход
# (EXIT-trap запускает cleanup). $1 — каталог TMPDIR, $2 — код подготовки.
# A child bs process: its own PID, its own registry setup, then a normal exit
# (the EXIT trap runs cleanup). $1 TMPDIR, $2 setup code.
run_child() {
    local -r tmpdir="$1" setup="$2"
    env -i HOME="${tmpdir}" PATH="/usr/bin:/bin" TMPDIR="${tmpdir}/tmp" BS_SILENT=1 \
        BS_ROOT="${BS_PROJECT_ROOT}" bash -c '
        source "$1/bootstrap/init.sh"
        errorhandler::setup_trap
        reg="$TMPDIR/bs-tmp-registry.$$"
        eval "$2"
    ' _ "${BS_PROJECT_ROOT}" "${setup}" >/dev/null 2>&1 || true
}

# Подложенный симлинк-реестр: cleanup не удаляет перечисленное в нём
# A planted symlink registry: cleanup does not delete what it lists
test_registry_symlink_ignored() {
    local t
    t="$(mktemp -d)"
    mkdir -p "${t}/tmp" "${t}/victim"
    printf 'precious\n' > "${t}/victim/data.txt"
    printf '%s\n' "${t}/victim" > "${t}/list"
    run_child "${t}" 'ln -s "'"${t}"'/list" "$reg"'
    testframework::assert_file_exists "${t}/victim/data.txt" "a symlink registry does not delete what it lists"
    rm -rf "${t:?}"
}

# Реестр нашего владельца: удаляются только пути внутри его каталога
# A registry of ours: only paths inside its own directory are removed
test_registry_scope() {
    local t
    t="$(mktemp -d)"
    mkdir -p "${t}/tmp/junk" "${t}/victim"
    printf 'precious\n' > "${t}/victim/data.txt"
    printf '%s\n%s\n%s\n' "${t}/victim" "${t}/tmp/../victim" "${t}/tmp/junk" > "${t}/list"
    run_child "${t}" 'cp "'"${t}"'/list" "$reg"'
    testframework::assert_file_exists "${t}/victim/data.txt" "paths outside the registry directory are not removed"
    testframework::assert_command "test ! -e '${t}/tmp/junk'" "registered paths inside TMPDIR are removed"
    rm -rf "${t:?}"
}

# utils::tempfile отказывает, если реестр — симлинк, и не пишет по ссылке
# utils::tempfile refuses when the registry is a symlink and never writes through it
test_tempfile_refuses_symlink_registry() {
    local t out rc=0
    t="$(mktemp -d)"
    mkdir -p "${t}/tmp"
    : > "${t}/target"
    out="$(env -u BS_INITIALIZED TMPDIR="${t}/tmp" bash -c '
        source "$1/bootstrap/init.sh"
        ln -s "$2/target" "$TMPDIR/bs-tmp-registry.$$"
        UTILS_TMP_REGISTRY="$TMPDIR/bs-tmp-registry.$$"
        utils::tempfile 2>/dev/null
        echo "rc=$?"
    ' _ "${BS_PROJECT_ROOT}" "${t}" 2>&1)" || rc=$?
    testframework::assert_equal "rc=1" "${out##*$'\n'}" "tempfile returns 1 for a symlink registry"
    testframework::assert_equal "0" "$(wc -c < "${t}/target" | tr -d ' ')" "nothing is appended through the symlink"
    testframework::assert_command "test -z \"\$(ls -A '${t}/tmp' | grep -v bs-tmp-registry)\"" "the rejected temp path is removed"
    rm -rf "${t:?}"
}

# Обычная работа: tempfile регистрирует, cleanup удаляет
# Normal use: tempfile registers, cleanup removes
test_tempfile_normal() {
    local p
    p="$(utils::tempfile audit)"
    testframework::assert_file_exists "${p}" "tempfile creates the file"
    utils::__tmp_cleanup
    testframework::assert_command "test ! -e '${p}'" "cleanup removes the registered file"
}

# detect_root: корень фреймворка, а не core/
# detect_root: the framework root, not core/
test_detect_root() {
    local out
    out="$(env -u FRAMEWORK_ROOT -u BS_INITIALIZED bash -c '
        source "$1/bootstrap/init.sh"
        utils::detect_root >/dev/null
        printf "%s" "${FRAMEWORK_ROOT}"
    ' _ "${BS_PROJECT_ROOT}" 2>/dev/null)"
    testframework::assert_equal "${BS_PROJECT_ROOT}" "${out}" "utils::detect_root returns the framework root"
}

main() {
    print_header "Audit: core/utils / Аудит: core/utils"
    testframework::init

    testframework::section "Temp registry / Реестр временных файлов"
    test_registry_symlink_ignored
    test_registry_scope
    test_tempfile_refuses_symlink_registry
    test_tempfile_normal

    testframework::section "detect_root"
    test_detect_root

    testframework::summary
}

main "$@"
