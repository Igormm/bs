#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testguardunit.sh — Unit tests for core/guard compatibility shim
# tests/unit/testguardunit.sh — Модульные тесты для совместимой обёртки core/guard

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

export BS_SILENT=1
export BS_HOME="${BS_PROJECT_ROOT}"
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

# Test that bs::guard is available after bootstrap initialization.
# Проверяем, что bs::guard доступен после инициализации бутстрапа.
test_guard_available() {
    testframework::assert_command 'declare -f bs::guard >/dev/null' "bs::guard is defined after init"
}

# Test bs::guard_loaded returns 1 before guard and 0 after.
# Проверяем, что bs::guard_loaded возвращает 1 до guard и 0 после.
test_guard_loaded() {
    local guard_name="GUARDUNIT_LOADED_CHECK"

    if bs::guard_loaded "${guard_name}"; then
        testframework::assert_true "1 -eq 2" "guard_loaded returns 1 before bs::guard"
    else
        testframework::assert_true "0 -eq 0" "guard_loaded returns 1 before bs::guard"
    fi

    bs::guard "${guard_name}"

    if bs::guard_loaded "${guard_name}"; then
        testframework::assert_true "0 -eq 0" "guard_loaded returns 0 after bs::guard"
    else
        testframework::assert_true "1 -eq 2" "guard_loaded returns 0 after bs::guard"
    fi
}

# Test bs::source_relative loads a file relative to its caller's directory.
# Проверяем, что bs::source_relative загружает файл относительно каталога вызывающего скрипта.
test_source_relative() {
    local tmp_dir
    tmp_dir="$(mktemp -d)"

    cat > "${tmp_dir}/relative.sh" <<'EOF'
test_guardunit_fixture::hello() { printf 'hello from source_relative\n'; }
EOF

    cat > "${tmp_dir}/helper.sh" <<'EOF'
bs::source_relative "./relative.sh"
EOF

    source "${tmp_dir}/helper.sh"

    testframework::assert_equal "hello from source_relative" "$(test_guardunit_fixture::hello)" "source_relative loads relative file"

    rm -rf "${tmp_dir}"
}

# Test that sourcing core/guard directly more than once is a no-op.
# Проверяем, что повторный source core/guard ничего не делает.
test_guard_double_source() {
    local guard_file="${BS_PROJECT_ROOT}/core/guard.sh"

    testframework::assert_command "source '${guard_file}'" "first direct source of core/guard succeeds"
    testframework::assert_equal "1" "${__GUARD_SOURCED:-}" "__GUARD_SOURCED is set after sourcing core/guard"

    testframework::assert_command "source '${guard_file}'" "second direct source of core/guard is a no-op"
    testframework::assert_equal "1" "${__GUARD_SOURCED}" "__GUARD_SOURCED stays set after second source"
}

# Test bs::guard sets the sourced mark and is idempotent.
# Проверяем, что bs::guard ставит метку загрузки и идемпотентен.
test_guard_sets_mark() {
    local guard_name="GUARDUNIT_IDEMPOTENT"
    local rc=0

    bs::guard "${guard_name}" || rc=$?
    testframework::assert_equal "0" "${rc}" "bs::guard returns 0 on first call"

    if bs::guard_loaded "${guard_name}"; then
        testframework::assert_true "0 -eq 0" "bs::guard marks module as sourced"
    else
        testframework::assert_true "1 -eq 2" "bs::guard marks module as sourced"
    fi

    rc=0
    bs::guard "${guard_name}" || rc=$?
    testframework::assert_equal "1" "${rc}" "bs::guard returns 1 on repeated call"

    if bs::guard_loaded "${guard_name}"; then
        testframework::assert_true "0 -eq 0" "module stays sourced after repeated call"
    else
        testframework::assert_true "1 -eq 2" "module stays sourced after repeated call"
    fi
}

main() {
    print_header "Core Guard Unit Tests / Модульные тесты core/guard"

    testframework::init

    testframework::section "bs::guard availability / Доступность bs::guard"
    test_guard_available

    testframework::section "bs::guard_loaded / Проверка загруженности"
    test_guard_loaded

    testframework::section "bs::source_relative / Относительная загрузка"
    test_source_relative

    testframework::section "core/guard double-source / Двойной source"
    test_guard_double_source

    testframework::section "bs::guard idempotency / Идемпотентность"
    test_guard_sets_mark

    testframework::summary
}

main "$@"
