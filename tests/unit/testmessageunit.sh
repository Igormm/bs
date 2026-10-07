#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testmessageunit.sh — Unit tests for lib/ui/elements/message
# tests/unit/testmessageunit.sh — Модульные тесты для lib/ui/elements/message

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Flatten the TUI buffer into a single string ordered by row and column.
__buffer_to_string() {
    local key
    local -a sorted=()
    while IFS= read -r key; do
        sorted+=("${key}")
    done < <(printf '%s\n' "${!TUI_BUF[@]}" | sort -t',' -k1,1n -k2,2n)
    for key in "${sorted[@]}"; do
        printf '%s' "${TUI_BUF[${key}]}"
    done
}

# Test info/success/warn/error variants produce output containing the text.
test_message_levels() {
    local level flat
    for level in info success warning error; do
        tui::buf::clear
        ui::elements::message::draw "${level}" "${level} message text"
        flat="$(__buffer_to_string)"
        if printf '%s' "${flat}" | grep -q "${level} message text"; then
            testframework::assert_true "true" "${level} output contains message text"
        else
            testframework::assert_true "false" "${level} output contains message text"
        fi
    done
}

# Test that empty message is safe and still renders a box.
test_message_empty_safe() {
    tui::buf::clear
    ui::elements::message::draw info ""
    local flat
    flat="$(__buffer_to_string)"
    testframework::assert_true "${#flat} -gt 0" "empty message still renders a box"
}

main() {
    print_header "UI Elements Message Unit Tests / Модульные тесты сообщений"

    testframework::init

    testframework::section "Module Loading / Загрузка модуля"
    load "lib/ui/elements/message"
    testframework::assert_true "$(declare -f ui::elements::message::draw >/dev/null && printf true || printf false)" "message module loaded"

    testframework::section "Message Levels / Уровни сообщений"
    test_message_levels

    testframework::section "Empty Message / Пустое сообщение"
    test_message_empty_safe

    testframework::summary
}

main "$@"
