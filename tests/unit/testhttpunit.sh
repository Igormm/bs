#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testhttpunit.sh — Unit tests for lib/integration/http
# tests/unit/testhttpunit.sh — Модульные тесты HTTP-клиента BS

set -euo pipefail

# Подключаем тестовый фреймворк / Source test framework
readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Инициализируем BS / Initialize BS
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Подключаем тестируемый модуль / Load module under test
load "lib/integration/http"

main() {
    print_header "HTTP Client Unit Tests"
    print_header "Модульные тесты HTTP-клиента"

    testframework::init

    local tmp_dir
    tmp_dir="$(mktemp -d)"

    # ==========================================
    # backend detection
    # ==========================================
    testframework::section "backend detection"

    if utils::has curl || utils::has wget; then
        testframework::assert_command "source ${BS_PROJECT_ROOT}/lib/integration/http.sh; __http::backend" "backend returns curl or wget"
    else
        testframework::assert_command "! source ${BS_PROJECT_ROOT}/lib/integration/http.sh; __http::backend" "backend fails without curl/wget"
    fi

    # ==========================================
    # http::get
    # ==========================================
    testframework::section "http::get"

    local response
    response="$(http::get "https://api.github.com" 2>/dev/null || true)"
    if [[ -n "${response}" ]]; then
        testframework::assert_command "printf '%s' '${response}' | grep -q 'current_user_url'" "http::get fetches github api"
    else
        testframework::assert_true "true" "http::get skipped (network unavailable)"
    fi

    # ==========================================
    # http::post dry-run
    # ==========================================
    testframework::section "http::post dry-run"

    export FRAMEWORK_DRY_RUN=true
    local rc=0
    http::post "https://example.com" '{"x":1}' || rc=$?
    testframework::assert_equal "0" "${rc}" "http::post dry-run returns 0"
    unset FRAMEWORK_DRY_RUN

    # ==========================================
    # http::download dry-run
    # ==========================================
    testframework::section "http::download dry-run"

    export FRAMEWORK_DRY_RUN=true
    rc=0
    http::download "https://example.com/file" "${tmp_dir}/file" || rc=$?
    testframework::assert_equal "0" "${rc}" "http::download dry-run returns 0"
    testframework::assert_false "test -f '${tmp_dir}/file'" "http::download dry-run does not create file"
    unset FRAMEWORK_DRY_RUN

    # ==========================================
    # http::retry
    # ==========================================
    testframework::section "http::retry"

    local retry_script="${tmp_dir}/retry.sh"
    cat > "${retry_script}" <<'EOF'
#!/usr/bin/env bash
if [[ -f /tmp/bs_http_retry_marker ]]; then
  echo "ok"
  rm -f /tmp/bs_http_retry_marker
  exit 0
else
  touch /tmp/bs_http_retry_marker
  exit 1
fi
EOF
    chmod +x "${retry_script}"

    rc=0
    http::retry 2 0.1 "${retry_script}" > "${tmp_dir}/retry.out" || rc=$?
    testframework::assert_equal "0" "${rc}" "http::retry succeeds on second attempt"
    testframework::assert_equal "ok" "$(cat "${tmp_dir}/retry.out")" "http::retry returns command output"

    # ==========================================
    # http::request missing deps
    # ==========================================
    testframework::section "http::request validation"

    rc=0
    http::request "" "https://example.com" || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "http::request requires method"

    rc=0
    http::request "GET" "" || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "http::request requires URL"

    # ==========================================
    # Cleanup and summary
    # ==========================================
    rm -rf "${tmp_dir}"

    testframework::summary
}

main "$@"
