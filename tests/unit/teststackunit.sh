#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/teststackunit.sh — unit tests for lib/ts/stack
# tests/unit/teststackunit.sh — модульные тесты lib/ts/stack

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/ts/stack"

main() {
  print_header "TS Stack Unit Tests / Модульные тесты ts::stack"
  testframework::init

  local tmp
  tmp="$(mktemp -d)"
  export TS_STACK_STATE="${tmp}/state"
  export TS_STACK_NAME="thriller-test"

  testframework::section "Load / Загрузка"
  testframework::assert_true "${TS_STACK_LOADED:-}" "module loaded"

  testframework::section "init / Каркас"
  ts::stack::init "${tmp}/app"
  testframework::assert_file_exists "${tmp}/app/bs-stack.ini" "ini written"
  testframework::assert_file_exists "${tmp}/app/apps/api/index.ts" \
    "api stub written"
  testframework::assert_file_exists "${tmp}/app/fixtures/health.json" \
    "health fixture"
  testframework::assert_file_exists "${tmp}/app/public/index.html" \
    "public page"

  testframework::section "cfg / ini"
  local port
  port="$(ts::stack::__cfg "${tmp}/app/bs-stack.ini" api port 9)"
  testframework::assert_equal "8787" "${port}" "ini api port"

  testframework::section "up/status/down / Жизненный цикл"
  export TS_STACK_API_CMD="sleep 30"
  export TS_STACK_WEB_CMD=""
  ts::stack::up "${tmp}/emptyproj"
  local st pid
  st="$(ts::stack::status)"
  testframework::assert_true "'${st}' =~ api.alive=yes" "api alive after up"
  pid="$(cat "${TS_STACK_STATE}/${TS_STACK_NAME}/api.pid")"
  testframework::assert_command "kill -0 ${pid}" "api pid is a process"

  ts::stack::down
  st="$(ts::stack::status)"
  testframework::assert_true "'${st}' =~ api.alive=no" "api dead after down"
  testframework::assert_false "kill -0 ${pid}" "pid gone"

  ts::stack::down
  testframework::assert_true "true" "down is idempotent"

  testframework::section "logs missing / нет лога"
  local rc=0
  ts::stack::logs web >/dev/null 2>&1 || rc=$?
  testframework::assert_equal "${LIB_ERROR_FILE_NOT_FOUND}" "${rc}" \
    "logs web missing"

  rm -rf -- "${tmp}"
  testframework::summary
}

main "$@"
