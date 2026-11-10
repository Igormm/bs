#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testdevdriverunit.sh — unit tests for devdriver:: (lib/system/devdriver)
# tests/unit/testdevdriverunit.sh — юнит-тесты devdriver:: (lib/system/devdriver)

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/system/devdriver"

# Фейковый драйвер с каталогом / fake catalogue-driven driver.
# __catalog принимает kind: при "wide" добавляет третий параметр.
driver::fake::__catalog() {
    printf 'alpha\tbool\t0\t0,1\tfirst\n'
    printf 'beta\tint\t5\t\tsecond\n'
    [[ "${1:-}" == "wide" ]] && printf 'gamma\tstring\t\t\tthird\n'
    return 0
}
driver::fake::get() {
    case "$2" in
        alpha) printf '1' ;;
        beta)  printf '%s-7' "$1" ;;
        *) return 2 ;;
    esac
}

main() {
    print_header "devdriver Unit Tests / Юнит-тесты devdriver"
    testframework::init

    testframework::section "params / параметры"
    local out
    out="$(devdriver::params fake dev0 "?")"
    testframework::assert_equal $'alpha\tbool\t1\t0\t0,1\tfirst\nbeta\tint\tdev0-7\t5\t\tsecond' "${out}" "params adds current value after type"
    out="$(devdriver::params fake dev0 "?" wide)"
    testframework::assert_equal $'gamma\tstring\t?\t\t\tthird' "$(tail -n1 <<< "${out}")" "catalog args pass through; failed get -> fallback"
    testframework::assert_equal "3" "$(wc -l <<< "${out}" | tr -d ' ')" "one row per catalogue entry"

    testframework::section "snapshot / снимок"
    out="$(devdriver::snapshot fake dev1 "unknown" wide)"
    testframework::assert_equal $'alpha\t1\nbeta\tdev1-7\ngamma\tunknown' "${out}" "snapshot is param<TAB>value with fallback"

    testframework::summary
}

main "$@"
