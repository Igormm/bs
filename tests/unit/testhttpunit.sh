#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testhttpunit.sh — Unit tests for lib/integration/http
# tests/unit/testhttpunit.sh — Модульные тесты HTTP-клиента BS

set -euo pipefail

# Подключаем тестовый фреймворк / Source test framework
readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Инициализируем BS / Initialize BS
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Подключаем тестируемый модуль / Load module under test
load "lib/integration/http"

main() {
    print_header "HTTP Client Unit Tests / Модульные тесты HTTP-клиента"

    testframework::init

    local tmp_dir
    tmp_dir="$(mktemp -d)"

    # ==========================================
    # backend detection
    # ==========================================
    testframework::section "Backend detection / Определение бэкенда"

    if utils::has curl || utils::has wget; then
        testframework::assert_command "source ${BS_PROJECT_ROOT}/lib/integration/http.sh; __http::backend" "backend returns curl or wget"
    else
        testframework::assert_command "! source ${BS_PROJECT_ROOT}/lib/integration/http.sh; __http::backend" "backend fails without curl/wget"
    fi

    # ==========================================
    # http::get
    # ==========================================
    testframework::section "http::get / HTTP GET"

    # Fake curl in PATH: no network is touched / Подставной curl в PATH: сеть не используется
    local fakebin="${tmp_dir}/fakebin"
    mkdir -p "${fakebin}"
    cat > "${fakebin}/curl" <<'FAKE'
#!/bin/sh
case "$*" in
  *notfound*) printf 'missing\n404' ;;
  *boom*) exit 7 ;;
  *) printf '{"current_user_url":"x"}\n200' ;;
esac
FAKE
    chmod +x "${fakebin}/curl"
    local old_path="${PATH}"
    PATH="${fakebin}:${PATH}"

    local response rc=0
    response="$(http::get "https://example.test/ok")" || rc=$?
    testframework::assert_equal "0" "${rc}" "http::get returns 0 on HTTP 200"
    testframework::assert_equal '{"current_user_url":"x"}' "${response}" "http::get prints the body without the status line"

    rc=0
    response="$(http::get "https://example.test/notfound")" || rc=$?
    testframework::assert_equal "${INTEGRATION_ERROR_HTTP}" "${rc}" "http::get returns error on HTTP 404"
    testframework::assert_equal "missing" "${response}" "http::get still prints the 404 body"

    rc=0
    http::get "https://example.test/boom" >/dev/null || rc=$?
    testframework::assert_equal "${INTEGRATION_ERROR_HTTP}" "${rc}" "http::get returns error when curl fails"
    PATH="${old_path}"

    # ==========================================
    # http::post dry-run
    # ==========================================
    testframework::section "http::post dry-run / Сухой прогон http::post"

    export FRAMEWORK_DRY_RUN=true
    rc=0
    http::post "https://example.com" '{"x":1}' || rc=$?
    testframework::assert_equal "0" "${rc}" "http::post dry-run returns 0"
    unset FRAMEWORK_DRY_RUN

    # ==========================================
    # http::download dry-run
    # ==========================================
    testframework::section "http::download dry-run / Сухой прогон http::download"

    export FRAMEWORK_DRY_RUN=true
    rc=0
    http::download "https://example.com/file" "${tmp_dir}/file" || rc=$?
    testframework::assert_equal "0" "${rc}" "http::download dry-run returns 0"
    testframework::assert_false "test -f '${tmp_dir}/file'" "http::download dry-run does not create file"
    unset FRAMEWORK_DRY_RUN

    # ==========================================
    # http::retry
    # ==========================================
    testframework::section "http::retry / Повторные попытки"

    local retry_script="${tmp_dir}/retry.sh"
    cat > "${retry_script}" <<'EOF'
#!/usr/bin/env bash
marker="$(dirname "$0")/retry_marker"
if [[ -f "${marker}" ]]; then
  echo "ok"
  rm -f "${marker}"
  exit 0
else
  touch "${marker}"
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
    testframework::section "http::request validation / Валидация запроса"

    rc=0
    http::request "" "https://example.com" || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "http::request requires method"

    rc=0
    http::request "GET" "" || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "http::request requires URL"

    # ==========================================
    # Cleanup and summary
    # ==========================================
    rm -rf "${tmp_dir:?}"

    testframework::summary
}

main "$@"
