#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testmathunit.sh — Unit tests for lib/math (C-backed evaluator)
# tests/unit/testmathunit.sh — Модульные тесты для lib/math (вычислитель на C)

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/math/math"

main() {
    print_header "Math Unit Tests / Модульные тесты math"

    testframework::init

    if ! utils::has cc && ! utils::has gcc; then
        echo "  SKIP: no C compiler (cc/gcc) — math tests skipped"
        testframework::summary
        return 0
    fi

    # Изолированный кэш / Isolated cache
    export MATH_CACHE_DIR="$(mktemp -d)/bs-math-cache"

    testframework::section "Arithmetic / Арифметика"
    testframework::assert_equal "14" "$(math::calc "2 + 3 * 4")" "precedence"
    testframework::assert_equal "4" "$(math::calc "2 * 2")" "multiplication"
    testframework::assert_equal "2.5" "$(math::calc "5.0 / 2")" "float division"
    testframework::assert_equal "1" "$(math::calc "10 % 3")" "modulo"

    testframework::section "math.h / Математические функции"
    testframework::assert_equal "1024" "$(math::calc "pow(2, 10)")" "pow"
    testframework::assert_equal "12" "$(math::calc "sqrt(144)")" "sqrt"
    testframework::assert_equal "0.5" "$(math::calc "sin(PI / 6)")" "sin with PI"
    testframework::assert_equal "1" "$(math::calc "cos(0)")" "cos"
    testframework::assert_equal "2.30258509299405" "$(math::calc "log(10)")" "ln(10)"
    testframework::assert_equal "3" "$(math::calc "log10(1000)")" "log10"
    testframework::assert_equal "5" "$(math::calc "hypot(3, 4)")" "hypot"
    testframework::assert_equal "2" "$(math::calc "cbrt(8)")" "cbrt"
    testframework::assert_equal "3.5" "$(math::calc "floor(3.9) + 0.5")" "floor composition"

    testframework::section "Helpers / Хелперы"
    testframework::assert_equal "180" "$(math::calc "deg(rad(180))")" "deg/rad roundtrip"
    testframework::assert_equal "3" "$(math::calc "clamp(5, 0, 3)")" "clamp high"
    testframework::assert_equal "5" "$(math::calc "lerp(0, 10, 0.5)")" "lerp middle"
    testframework::assert_equal "-1" "$(math::calc "sign(-42)")" "sign negative"
    testframework::assert_equal "1.414" "$(math::calc "roundn(sqrt(2), 3)")" "roundn"
    testframework::assert_equal "1" "$(math::calc "TAU / TAU")" "TAU constant"

    testframework::section "Variables / Переменные"
    testframework::assert_equal "5" "$(math::calc "hypot(x, y)" x=3 y=4)" "named variables"
    testframework::assert_equal "10" "$(math::calc "x * 2" x=5)" "single variable"
    testframework::assert_equal "42" "$(math::calc "answer" answer=42)" "plain variable"

    testframework::section "Heredoc / Тройные кавычки"
    local out
    out="$(math::eval <<'EOF'
roundn(sqrt(2), 3) * 1000
EOF
)"
    testframework::assert_equal "1414" "${out}" "math::eval heredoc multi"
    out="$(math::eval a=2 b=3 <<'EOF'
pow(a, b)
EOF
)"
    testframework::assert_equal "8" "${out}" "math::eval heredoc with variables"

    testframework::section "Format / Формат"
    testframework::assert_equal "3.1429" "$(math::calc "22.0 / 7.0" --format "%.4f")" "custom format"
    testframework::assert_equal "3" "$(math::calc "22.0 / 7.0" --format "%.0f")" "integer format"

    testframework::section "Errors / Ошибки"
    testframework::assert_false "math::calc '2 +'" "invalid expression fails"
    testframework::assert_false "math::calc ''" "empty expression fails"
    testframework::assert_false "math::calc 'x + 1' 'bad name=1'" "invalid variable name fails"

    testframework::section "Cache / Кэш"
    local cache_count
    cache_count="$(ls "${MATH_CACHE_DIR}" | wc -l)"
    math::calc "2 + 2" >/dev/null
    math::calc "2 + 2" >/dev/null
    local cache_after
    cache_after="$(ls "${MATH_CACHE_DIR}" | wc -l)"
    # Первый вызов добавил один бинарник, второй переиспользовал его
    testframework::assert_equal "$(( cache_count + 1 ))" "${cache_after}" "math::calc reuses cached binary"

    testframework::summary
}

main "$@"