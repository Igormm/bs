#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testapiunit.sh — Unit tests for lib/api/openapi
# tests/unit/testapiunit.sh — Модульные тесты lib/api/openapi

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/api/openapi"

# Isolated test dir: spec + registry + mock / Изолированный каталог теста
declare -g API_TEST_DIR=""

api_test::write_spec() {
  API_TEST_DIR="$(mktemp -d)"
  API_TEST_SPEC="${API_TEST_DIR}/petstore.json"
  API_SPEC_REGISTRY="${API_TEST_DIR}/registry.tsv"
  cat > "${API_TEST_SPEC}" <<'EOF'
{
  "openapi": "3.0.0",
  "info": {"title": "Petstore", "version": "1.0.0"},
  "servers": [{"url": "https://api.example.com/v1"}],
  "paths": {
    "/pets": {
      "get": {
        "summary": "List all pets",
        "parameters": [
          {"name": "limit", "in": "query", "schema": {"type": "integer"}},
          {"name": "tag", "in": "query", "schema": {"type": "string"}}
        ]
      },
      "post": {
        "summary": "Create a pet",
        "requestBody": {"content": {"application/json": {"schema": {"type": "object"}}}}
      }
    },
    "/pets/{petId}": {
      "get": {
        "summary": "Get a pet",
        "parameters": [
          {"name": "petId", "in": "path", "required": true, "schema": {"type": "integer"}},
          {"name": "X-Request-ID", "in": "header", "schema": {"type": "string"}}
        ]
      }
    }
  }
}
EOF
}

api_test::setup_mock() {
  API_TEST_BIN="${API_TEST_DIR}/bin"
  mkdir -p "${API_TEST_BIN}"
  API_TEST_LOG="${API_TEST_BIN}/curl.log"
  export API_TEST_LOG
  cat > "${API_TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
printf 'ARGS: %s\n' "$*" >> "${API_TEST_LOG}"
printf '{"pets":[{"id":1,"name":"Rex"}]}\n'
printf '200\n'
EOF
  chmod +x "${API_TEST_BIN}/curl"
  export PATH="${API_TEST_BIN}:${PATH}"
}

api_test::teardown_mock() {
  export PATH="${PATH#${API_TEST_BIN}:}"
}

test_spec_load() {
  api_test::write_spec
  api::spec::load petstore "${API_TEST_SPEC}" || testframework::fail "spec load failed"
  testframework::assert_equal "${API_TEST_SPEC}" "${API_SPECS[petstore]}" "spec stored under name"

  # Не-OpenAPI документ отклоняется / non-OpenAPI rejected
  local bad="${API_TEST_DIR}/notopenapi.json"
  printf '{"swagger": "2.0"}' > "${bad}"
  testframework::assert_false "api::spec::load bad ${bad}" "rejects non-OpenAPI 3.x"

  # Отсутствующий файл / missing file
  testframework::assert_false "api::spec::load ghost /no/such/file.json" "rejects missing file"

  local info
  info="$(api::spec::info petstore)"
  testframework::assert_equal "Petstore 1.0.0 — https://api.example.com/v1" "${info}" "info shows title/version/server"
}

test_paths_listing() {
  local out
  out="$(api::paths petstore)"
  testframework::assert_command "printf '%s' '${out}' | grep -q 'GET.*/pets'" "paths lists GET /pets"
  testframework::assert_command "printf '%s' '${out}' | grep -q 'POST.*/pets'" "paths lists POST /pets"
  testframework::assert_command "printf '%s' '${out}' | grep -q 'GET.*/pets/{petId}'" "paths lists path template"

  local filtered
  filtered="$(api::paths petstore --method GET)"
  testframework::assert_false "printf '%s' '${filtered}' | grep -q 'POST'" "paths --method filters to GET"
}

test_call_query_and_token() {
  api_test::setup_mock
  local body
  body="$(api::call petstore GET /pets --limit 10 --tag "a b" --token SECRET123 --json)" || testframework::fail "GET /pets failed"
  testframework::assert_command "grep -q 'https://api.example.com/v1/pets?limit=10&tag=a%20b' '${API_TEST_LOG}'" "query params url-encoded and joined"
  testframework::assert_command "grep -q 'Authorization: Bearer SECRET123' '${API_TEST_LOG}'" "token sent as Bearer"
  testframework::assert_equal '{"pets":[{"id":1,"name":"Rex"}]}' "${body}" "--json returns raw body"
  api_test::teardown_mock
}

test_call_path_and_header() {
  api_test::setup_mock
  api::call petstore GET /pets/{petId} --petId 42 --X-Request-ID abc --json || testframework::fail "GET /pets/{petId} failed"
  testframework::assert_command "grep -q '/v1/pets/42' '${API_TEST_LOG}'" "path param substituted into URL"
  testframework::assert_command "grep -q 'X-Request-ID: abc' '${API_TEST_LOG}'" "header param sent"
  api_test::teardown_mock
}

test_call_post_body() {
  api_test::setup_mock
  api::call petstore POST /pets --body '{"name":"Rex"}' --json || testframework::fail "POST failed"
  testframework::assert_command "grep -q -- '-d {\\\"name\\\":\\\"Rex\\\"}' '${API_TEST_LOG}'" "body sent via -d"
  api_test::teardown_mock
}

test_call_validation() {
  # Обязательный параметр отсутствует / required param missing
  testframework::assert_false "api::call petstore GET /pets/{petId}" "missing required petId fails"

  # Неизвестный параметр / unknown param
  testframework::assert_false "api::call petstore GET /pets --bogus 1" "unknown param fails"

  # Несуществующая схема / unknown spec
  testframework::assert_false "api::call ghost GET /pets" "unknown spec fails"
}

test_call_pretty_mode() {
  api_test::setup_mock
  local out
  out="$(api::call petstore GET /pets --limit 1 || true)"
  testframework::assert_command "printf '%s' '${out}' | jq -e '.pets[0].name == \"Rex\"'" "default mode pretty-prints JSON"
  api_test::teardown_mock
}

main() {
  print_header "API Unit Tests / Модульные тесты API"

  testframework::init

  testframework::section "Spec load / Загрузка схемы"
  test_spec_load

  testframework::section "Paths / Список операций"
  test_paths_listing

  testframework::section "Calls / Вызовы"
  test_call_query_and_token
  test_call_path_and_header
  test_call_post_body

  testframework::section "Validation / Валидация"
  test_call_validation

  testframework::section "Output / Вывод"
  test_call_pretty_mode

  rm -rf -- "${API_TEST_DIR}"
  testframework::summary
}

main "$@"