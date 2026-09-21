#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testosagentunit.sh — Unit tests for lib/integration/osagent
# tests/unit/testosagentunit.sh — Модульные тесты lib/integration/osagent

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/integration/osagent"

test_permissions() {
  local out
  out="$(osagent::permissions)"
  testframework::assert_command "printf '%s' '${out}' | grep -q 'allow:'" "permissions shows allow policy"
  testframework::assert_command "printf '%s' '${out}' | grep -q 'exec:'" "permissions shows exec policy"
  testframework::assert_command "printf '%s' '${out}' | grep -q 'tools:'" "permissions lists tools"
}

test_tools_schema() {
  local schema names
  schema="$(osagent::tools::schema)"
  testframework::assert_command "printf '%s' '${schema}' | jq -e 'type == \"array\"'" "schema is a JSON array"
  testframework::assert_command "printf '%s' '${schema}' | jq -e 'any(.name == \"hw.get\")'" "schema includes hw.get"
  testframework::assert_command "printf '%s' '${schema}' | jq -e 'any(.name == \"osagent.exec\")'" "schema includes osagent.exec"
  names="$(osagent::tools::names)"
  testframework::assert_command "printf '%s' '${names}' | grep -q 'platform.facts'" "names includes platform.facts"
}

test_context() {
  local ctx
  ctx="$(osagent::context)"
  testframework::assert_command "printf '%s' '${ctx}' | jq -e '.platform.kernel == \"linux\"'" "context has platform facts"
  testframework::assert_command "printf '%s' '${ctx}' | jq -e '.tier != null'" "context has tier"
}

test_deny_by_default() {
  # osagent.exec запрещён по умолчанию / exec denied by default
  testframework::assert_false "osagent::exec osagent.exec '{\"command\":\"true\"}'" "osagent.exec denied by default"

  # api.call с не-GET методом запрещён / non-GET api.call denied
  testframework::assert_false "osagent::exec api.call '{\"spec\":\"x\",\"method\":\"POST\",\"path\":\"/y\"}'" "api.call POST denied"

  # Неизвестный инструмент / unknown tool
  testframework::assert_false "osagent::exec bogus '{}'" "unknown tool fails"
}

test_read_tools() {
  local out
  out="$(osagent::exec platform.facts '{}')"
  testframework::assert_command "printf '%s' '${out}' | grep -q 'kernel'" "platform.facts dumps facts"

  out="$(osagent::exec files.read "{\"path\":\"${BS_PROJECT_ROOT}/AGENTS.md\"}")"
  testframework::assert_command "printf '%s' '${out}' | grep -q 'BS Framework'" "files.read reads a file"

  # Нет такого файла / missing file
  testframework::assert_false "osagent::exec files.read '{\"path\":\"/no/such/file\"}'" "files.read rejects missing file"
}

test_dry_run() {
  FRAMEWORK_DRY_RUN=true
  osagent::exec platform.facts '{}' || testframework::fail "dry-run exec failed"
  FRAMEWORK_DRY_RUN=false
}

test_ask_tool_round() {
  local out
  export LLM_MOCK_RESPONSE='{"choices":[{"message":{"content":"{\"tool\":\"platform.facts\",\"args\":{}}"}}]}'
  out="$(osagent::ask "Факты?" --json)" || testframework::fail "ask tool round failed"
  testframework::assert_command "printf '%s' '${out}' | jq -e '.tool == \"platform.facts\"'" "ask executes requested tool"
  testframework::assert_command "printf '%s' '${out}' | jq -e '.result | length > 0'" "tool result captured"
}

test_ask_answer_round() {
  local out
  export LLM_MOCK_RESPONSE='{"choices":[{"message":{"content":"{\"answer\":\"42\"}"}}]}'
  out="$(osagent::ask "Сколько?" 2>/dev/null)"
  testframework::assert_equal "42" "${out}" "ask prints final answer"
}

main() {
  print_header "OSAgent Unit Tests / Модульные тесты ОС-агента"

  testframework::init

  testframework::section "Policy / Политика"
  test_permissions

  testframework::section "Tools / Инструменты"
  test_tools_schema

  testframework::section "Context / Контекст"
  test_context

  testframework::section "Security / Безопасность"
  test_deny_by_default

  testframework::section "Read tools / Чтение"
  test_read_tools

  testframework::section "Dry-run / Сухой прогон"
  test_dry_run

  testframework::section "Ask / Вопрос"
  test_ask_tool_round
  test_ask_answer_round

  testframework::summary
}

main "$@"