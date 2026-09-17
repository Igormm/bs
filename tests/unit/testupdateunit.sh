#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testupdateunit.sh — Unit tests for `bs update` (CLI command)
# tests/unit/testupdateunit.sh — Модульные тесты для `bs update` (команда CLI)

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

test_update_basic() {
    local tmp_dir src target
    tmp_dir="$(mktemp -d)"
    src="${tmp_dir}/repo"
    target="${tmp_dir}/installed"

    # Минимальный фейковый репозиторий и установка / Fake repo and install
    mkdir -p "${src}/core" "${src}/lib/data" "${src}/bootstrap" "${target}/lib/data"
    printf '#!/usr/bin/env bash\necho fake-bs\n' > "${src}/bs"
    printf '#!/usr/bin/env bash\n' > "${src}/bootstrap/init.sh"
    printf 'old_core() { :; }\n' > "${target}/old.sh"
    printf 'new_func() { :; }\n' > "${src}/core/new.sh"
    printf 'mod_func() { :; }\n' > "${src}/lib/data/mod.sh"
    printf 'old_lib() { :; }\n' > "${target}/lib/data/old_lib.sh"

    bash "${BS_PROJECT_ROOT}/bs" update --lib "${target}" --from "${src}" >/dev/null 2>&1
    testframework::assert_equal "0" "$?" "bs update exits 0"
    testframework::assert_command "test -f '${target}/core/new.sh'" "bs update copies new core files"
    testframework::assert_command "test -f '${target}/lib/data/mod.sh'" "bs update copies lib modules"
    testframework::assert_command "test -f '${target}/bs'" "bs update copies launcher"
    testframework::assert_command "test -f '${target}/bootstrap/init.sh'" "bs update copies bootstrap"
    testframework::assert_equal "new_func() { :; }" "$(cat "${target}/core/new.sh")" "bs update copies content"

    # Повторный update — идемпотентность / Second update is idempotent
    bash "${BS_PROJECT_ROOT}/bs" update --lib "${target}" --from "${src}" >/dev/null 2>&1
    testframework::assert_equal "0" "$?" "bs update idempotent"

    rm -rf "${tmp_dir}"
}

test_update_errors() {
    local tmp_dir src missing
    tmp_dir="$(mktemp -d)"
    src="${tmp_dir}/repo"
    missing="${tmp_dir}/missing"

    mkdir -p "${src}/core" "${src}/bootstrap"
    printf 'x\n' > "${src}/core/a.sh"

    testframework::assert_false "bash '${BS_PROJECT_ROOT}/bs' sync --lib '${missing}' --from '${src}'" "bs update fails when target missing"
    testframework::assert_false "bash '${BS_PROJECT_ROOT}/bs' sync --lib '${tmp_dir}/x' --from '${tmp_dir}/not-a-repo'" "bs update fails when source is not a repo"

    rm -rf "${tmp_dir}"
}

main() {
    print_header "Update Unit Tests / Модульные тесты sync"

    testframework::init

    testframework::section "Update / Обновление"
    test_update_basic

    testframework::section "Errors / Ошибки"
    test_update_errors

    testframework::summary
}

main "$@"