#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testlangdocunit.sh — Unit tests for lib/data/langdoc module
# tests/unit/testlangdocunit.sh — Модульные тесты для модуля lib/data/langdoc

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/data/langdoc"

test_parse_basic() {
    local tmp_file
    tmp_file="$(mktemp)"
    cat > "${tmp_file}" <<'EOF'
#!/usr/bin/env bs
# Module header comment — not attached to any function.

# @description Add two numbers / Сложить два числа.
#   Second line of description.
# @param $1 First number / Первое число
# @param $2 Second number / Второе число
# @return 0 ok, 1 error
# @stdout the sum / сумма
# @example
#   add 2 3
add() {
  printf '%s\n' "$(( $1 + $2 ))"
}

plain() { :; }
EOF

    local json
    json="$(langdoc::parse_file "${tmp_file}")"
    testframework::assert_equal "1" "$(printf '%s\n' "${json}" | jq -s 'length')" "langdoc parses only documented functions"
    testframework::assert_equal "add" "$(printf '%s\n' "${json}" | jq -s -r '.[0].name')" "langdoc function name"
    testframework::assert_equal "true" "$(printf '%s\n' "${json}" | jq -s -r '.[0].file | startswith("/tmp/")')" "langdoc file reference"
    testframework::assert_equal "Add two numbers / Сложить два числа.
Second line of description." "$(printf '%s\n' "${json}" | jq -s -r '.[0].description')" "langdoc description with continuation"
    testframework::assert_equal "2" "$(printf '%s\n' "${json}" | jq -s -r '.[0].params | length')" "langdoc params count"
    testframework::assert_equal '$1' "$(printf '%s\n' "${json}" | jq -s -r '.[0].params[0].name')" "langdoc param name"
    testframework::assert_equal "First number / Первое число" "$(printf '%s\n' "${json}" | jq -s -r '.[0].params[0].desc')" "langdoc param desc"
    testframework::assert_equal "0 ok, 1 error" "$(printf '%s\n' "${json}" | jq -s -r '.[0].returns')" "langdoc returns"
    testframework::assert_equal "the sum / сумма" "$(printf '%s\n' "${json}" | jq -s -r '.[0].stdout')" "langdoc stdout"
    testframework::assert_equal "add 2 3" "$(printf '%s\n' "${json}" | jq -s -r '.[0].example')" "langdoc example"
    testframework::assert_equal "false" "$(printf '%s\n' "${json}" | jq -s -r '.[0].deprecated')" "langdoc deprecated flag"

    rm -f "${tmp_file}"
}

test_parse_function_keyword() {
    local tmp_file
    tmp_file="$(mktemp)"
    cat > "${tmp_file}" <<'EOF'
# @description Wrapped in function keyword / Объявлена через function.
function wrapped() {
  :
}
EOF

    local json
    json="$(langdoc::parse_file "${tmp_file}")"
    testframework::assert_equal "wrapped" "$(printf '%s\n' "${json}" | jq -s -r '.[0].name')" "langdoc parses 'function name() {'"

    rm -f "${tmp_file}"
}

test_parse_escaping() {
    local tmp_file
    tmp_file="$(mktemp)"
    cat > "${tmp_file}" <<'EOF'
# @description Has "quotes", back\slash and $vars in docs.
quoted() { :; }
EOF

    local json
    json="$(langdoc::parse_file "${tmp_file}")"
    testframework::assert_equal "Has \"quotes\", back\\slash and \$vars in docs." \
        "$(printf '%s\n' "${json}" | jq -s -r '.[0].description')" "langdoc escapes JSON specials"
    testframework::assert_command "printf '%s\n' '${json}' | jq -se '.[0].name == \"quoted\"'" "langdoc output is valid JSON"

    rm -f "${tmp_file}"
}

test_parse_deprecated() {
    local tmp_file
    tmp_file="$(mktemp)"
    cat > "${tmp_file}" <<'EOF'
# @description Old function.
# @deprecated use new::fn instead
old_fn() { :; }
EOF

    local json
    json="$(langdoc::parse_file "${tmp_file}")"
    testframework::assert_equal "true" "$(printf '%s\n' "${json}" | jq -s -r '.[0].deprecated')" "langdoc deprecated tag"

    rm -f "${tmp_file}"
}

test_index_real_tree() {
    local json tmp_file
    tmp_file="$(mktemp)"
    langdoc::parse_file "${BS_PROJECT_ROOT}/core/lang.sh" > "${tmp_file}"
    testframework::assert_command "jq -se 'map(.name) | index(\"arr::slice\")' '${tmp_file}'" "langdoc indexes arr::slice from core/lang.sh"
    testframework::assert_command "jq -se 'map(.name) | index(\"bs::__slice_bounds\")' '${tmp_file}'" "langdoc indexes private helpers too"
    testframework::assert_command "jq -se '.[] | select(.name == \"arr::slice\") | .params | length >= 2' '${tmp_file}'" "langdoc arr::slice has params"
    rm -f "${tmp_file}"
}

main() {
    print_header "Langdoc Unit Tests / Модульные тесты langdoc"

    testframework::init

    if ! is::command jq; then
        echo "  SKIP: jq not available — langdoc tests skipped"
        testframework::summary
        return 0
    fi

    testframework::section "Parsing / Разбор"
    test_parse_basic
    test_parse_function_keyword
    test_parse_escaping
    test_parse_deprecated

    testframework::section "Real tree / Реальное дерево"
    test_index_real_tree

    testframework::summary
}

main "$@"