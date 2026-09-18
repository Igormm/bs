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

    testframework::section "Locale / Локаль"
    # Вывод не зависит от LC_NUMERIC: всегда точка, никогда запятая
    # Output is locale-independent: always ".", never ","
    local test_locale=""
    local candidate
    for candidate in "ru_RU.utf8" "ru_RU.UTF-8" "ru_RU" "de_DE.utf8" "de_DE.UTF-8" "de_DE"; do
        if locale -a 2>/dev/null | grep -Fqx "${candidate}"; then
            test_locale="${candidate}"
            break
        fi
    done

    local loc_out=""
    if [[ -n "${test_locale}" ]]; then
        loc_out="$(LC_ALL='' LC_NUMERIC="${test_locale}" math::calc "1.0 / 2")"
        testframework::assert_equal "0.5" "${loc_out}" "decimal separator '.' under ${test_locale}"
    else
        # Нет локали с запятой — проверяем printf сгенерированного C напрямую
        # No comma locale available — check the generated C printf directly
        local bin_check
        bin_check="$(__math::build "" "1.0 / 2" "%.15g")"
        loc_out="$("${bin_check}")"
        testframework::assert_equal "0.5" "${loc_out}" "manual printf check uses '.'"
    fi

    testframework::section "Security / Безопасность"
    # Значение переменной встраивается в C-исходник — только числовой
    # литерал; инъекция C-кода через значение должна отклоняться
    # Variable values are embedded into the C source — numeric literals
    # only; C-code injection via a value must be rejected
    local inj_out=""
    local inj_rc=0
    local inj_err
    inj_err="$(mktemp)"
    if inj_out="$(math::calc "x" "x=1; system(\"echo pwned\"); //" 2>"${inj_err}")"; then
        inj_rc=0
    else
        inj_rc=$?
    fi
    rm -f "${inj_err}"
    local was_rejected="no"
    [[ ${inj_rc} -ne 0 ]] && was_rejected="yes"
    testframework::assert_equal "yes" "${was_rejected}" "injection attempt rejected (rc=${inj_rc})"
    # "pwned" не должен появиться в stdout: system() не выполняется
    # "pwned" must not appear on stdout: system() never runs
    local has_pwned="no"
    [[ "${inj_out}" == *pwned* ]] && has_pwned="yes"
    testframework::assert_equal "no" "${has_pwned}" "no pwned output"

    local val_rc=0
    if math::calc "x" "x=abc" >/dev/null 2>&1; then
        val_rc=0
    else
        val_rc=$?
    fi
    local val_rejected="no"
    [[ ${val_rc} -ne 0 ]] && val_rejected="yes"
    testframework::assert_equal "yes" "${val_rejected}" "non-numeric value rejected"
    testframework::assert_equal "-700" "$(math::calc "x * 2" "x=-3.5e2")" "numeric literal forms accepted"

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