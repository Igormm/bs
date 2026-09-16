#!/usr/bin/env bs
# shellcheck shell=bash
# tests/integration/testbuild.sh — Integration tests for `bs build`
# tests/integration/testbuild.sh — Интеграционные тесты команды `bs build`
#
# Безопасный прогон: standalone-файлы и кэш создаются в temp-каталогах,
# XDG_CACHE_HOME изолируется — реальный ~/.cache не трогается.
# Safe run: standalone files and cache go to temp dirs; XDG_CACHE_HOME is
# isolated so the real ~/.cache is never touched.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly BS_LAUNCHER="${BS_PROJECT_ROOT}/bs"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

readonly TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/bs_build_test.XXXXXX")"
trap 'rm -rf "${TMP_ROOT}"' EXIT

# Тестовое приложение: минимальный bs-скрипт / Minimal BS app for the build
mk_test_app() {
    local app="$1"
    cat > "${app}" <<'APP'
#!/usr/bin/env bs
# shellcheck shell=bash
set -euo pipefail
load "core/utils"
main() {
    printf 'build-ok %s\n' "$(utils::stamp)"
    if utils::has bash; then
        printf 'bash-found\n'
    fi
}
main "$@"
APP
}

# Сборка standalone командой bs build / Build a standalone via `bs build`
run_build() {
    local out="$1"
    shift
    bash "${BS_LAUNCHER}" build "$@" --output "${out}" 2>&1
}

test_build_basic() {
    local app out rc=0 build_out
    app="${TMP_ROOT}/hello.sh"
    out="${TMP_ROOT}/hello.standalone.sh"
    mk_test_app "${app}"

    build_out="$(run_build "${out}" "${app}")" || rc=$?
    testframework::assert_equal "0" "${rc}" "bs build exits 0"

    testframework::assert_file_exists "${out}" "standalone file created"
    testframework::assert_command "test -x '${out}'" "standalone file is executable"
    testframework::assert_true "'${build_out}' =~ Built" "build prints success message"

    if grep -q '^#__BS_BUILD_PAYLOAD__$' "${out}"; then
        testframework::assert_true "true" "payload marker present"
    else
        testframework::assert_true "false" "payload marker present"
    fi
}

test_build_run_first_and_cache() {
    local app out cache app_out rc1=0 rc2=1
    app="${TMP_ROOT}/hello2.sh"
    out="${TMP_ROOT}/hello2.standalone.sh"
    cache="${TMP_ROOT}/cache"
    mk_test_app "${app}"
    run_build "${out}" "${app}" >/dev/null || true

    app_out="$(env XDG_CACHE_HOME="${cache}" "${out}")" || rc1=$?
    testframework::assert_equal "0" "${rc1}" "standalone runs (first run extracts)"

    testframework::assert_true "'${app_out}' =~ build-ok" "app output is correct"
    testframework::assert_true "'${app_out}' =~ bash-found" "framework function (utils::has) works"

    if [[ -d "${cache}/bs" ]] && [[ -x "$(echo "${cache}/bs"/*/bs | head -n 1)" ]]; then
        testframework::assert_true "true" "framework extracted to isolated cache"
    else
        testframework::assert_true "false" "framework extracted to isolated cache"
    fi

    rc2=1
    env XDG_CACHE_HOME="${cache}" "${out}" >/dev/null 2>&1 && rc2=0 || true
    testframework::assert_equal "0" "${rc2}" "standalone runs from cache (second run)"
}

test_build_runs_real_example() {
    local out cache app_out rc=0
    out="${TMP_ROOT}/sysdiag.standalone.sh"
    cache="${TMP_ROOT}/cache2"

    run_build "${out}" "${BS_PROJECT_ROOT}/examples/sysdiag.sh" >/dev/null || rc=$?
    testframework::assert_equal "0" "${rc}" "bs build examples/sysdiag.sh exits 0"

    app_out="$(env XDG_CACHE_HOME="${cache}" "${out}" quick 2>&1)" || rc=$?
    testframework::assert_equal "0" "${rc}" "built sysdiag quick runs"

    testframework::assert_true "'${app_out}' =~ Модель\ CPU" "built sysdiag prints hardware table"
}

test_build_invalid_args() {
    local rc=0 out
    out="${TMP_ROOT}/nope.standalone.sh"
    run_build "${out}" "/nonexistent/path/script.sh" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "1" "${rc}" "build with missing script exits 1"

    rc=0
    bash "${BS_LAUNCHER}" build --bogus >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "1" "${rc}" "build with unknown flag exits 1"
}

test_build_rejects_broken_script() {
    local app out rc=0
    app="${TMP_ROOT}/broken.sh"
    out="${TMP_ROOT}/broken.standalone.sh"
    printf '#!/usr/bin/env bs\nif [[; then\n' > "${app}"

    run_build "${out}" "${app}" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "1" "${rc}" "build rejects script with bash syntax errors"
    testframework::assert_false "test -f '${out}'" "no output file on failed build"
}

test_build_help() {
    local rc=0 out
    out="$(bash "${BS_LAUNCHER}" build --help 2>&1)" || rc=$?
    testframework::assert_equal "0" "${rc}" "build --help exits 0"
    testframework::assert_true "'${out}' =~ bs\ build" "help mentions usage"
}

main() {
    print_header "bs build Integration Tests / Интеграционные тесты bs build"

    testframework::init

    testframework::section "bs build / Сборка standalone"
    test_build_basic
    test_build_run_first_and_cache
    test_build_runs_real_example

    testframework::section "Error handling / Обработка ошибок"
    test_build_invalid_args
    test_build_rejects_broken_script
    test_build_help

    testframework::summary
}

main "$@"