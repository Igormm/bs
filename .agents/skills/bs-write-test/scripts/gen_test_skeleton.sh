#!/usr/bin/env bash
# shellcheck shell=bash
# .agents/skills/bs-write-test/scripts/gen_test_skeleton.sh — generate a unit-test skeleton covering every public function of a module
# .agents/skills/bs-write-test/scripts/gen_test_skeleton.sh — сгенерировать скелет юнит-теста на каждую публичную функцию модуля

# Scans a module for public functions (ns::fn() at column 0, no __ private
# prefix), extracts their @example doc blocks, and emits a unit test file
# with one test function per module function.
# Сканирует модуль на публичные функции (ns::fn() в колонке 0, без приватного
# префикса __), извлекает их @example блоки и выдаёт файл юнит-теста
# с одной тест-функцией на каждую функцию модуля.

# Usage / Использование:
#   bash scripts/gen_test_skeleton.sh core/lang.sh            # stdout
#   bash scripts/gen_test_skeleton.sh core/lang.sh --write    # write tests/unit/testlangunit.sh
#   bash scripts/gen_test_skeleton.sh lib/io/files            # module path without .sh works too

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

usage() {
    sed -n 's/^# //p; s/^#$//p' "${BASH_SOURCE[0]}" | sed -n '/Usage/,/--write/p'
    exit 1
}

[[ $# -ge 1 ]] || usage
local_write=0
module_arg="${1}"
if [[ "${2:-}" == "--write" ]]; then
    local_write=1
fi

module_arg="${module_arg%.sh}"
module_file="${BS_PROJECT_ROOT}/${module_arg}.sh"
[[ -f "${module_file}" ]] || { echo "error: module not found: ${module_file}" >&2; exit 1; }

module_name="$(basename "${module_arg}")"
test_file="tests/unit/test${module_name}unit.sh"
test_path="${BS_PROJECT_ROOT}/${test_file}"
if [[ "${local_write}" -eq 1 && -e "${test_path}" ]]; then
    echo "error: ${test_path} already exists — refuse to overwrite tracked tests" >&2
    echo "error: ${test_path} уже существует — не перезаписываю существующие тесты" >&2
    exit 1
fi
tmp_out="$(mktemp)"

mapfile -t funcs < <(grep -nE '^[a-z_][a-z0-9_]*::[a-z0-9_:]+\(\) *\{' "${module_file}" | grep -v '::__' || true)
[[ ${#funcs[@]} -gt 0 ]] || { echo "error: no public functions found in ${module_file}" >&2; exit 1; }

extract_example() {
    local line="${1}"
    local example_line=0
    local i
    for ((i = line - 1; i >= 1; i--)); do
        local l
        l="$(sed -n "${i}p" "${module_file}")"
        [[ "${l}" == "# @example" ]] && example_line="${i}" && break
        [[ "${l}" == "#"* ]] && continue
        break
    done
    if [[ "${example_line}" -eq 0 ]]; then
        printf ''
        return
    fi
    local text=""
    for ((i = example_line + 1; i < line; i++)); do
        local l
        l="$(sed -n "${i}p" "${module_file}")"
        if [[ "${l}" == "#   "* ]]; then
            text="$(printf '%s' "${l}" | sed 's/^#   //')"
            break
        fi
        [[ "${l}" == "#"* ]] && continue
        break
    done
    # Skip pseudo-code examples (if/for/while/… ) — they are not runnable
    # Пропускаем примеры-псевдокод (if/for/while/… ) — они не исполняемы
    case "${text}" in
        *'...'* | if\ * | for\ * | while\ * | case\ *) text="" ;;
    esac
    # Strip a trailing comment outside quotes — it would break $(...) capture
    # Срезаем хвостовой комментарий вне кавычек — он сломал бы захват $(...)
    local stripped=""
    local in_quotes=0
    local ch
    local j
    for ((j = 0; j < ${#text}; j++)); do
        ch="${text:j:1}"
        if [[ "${ch}" == '"' ]]; then
            in_quotes=$((1 - in_quotes))
            stripped+="${ch}"
        elif [[ "${ch}" == "#" && "${in_quotes}" -eq 0 ]]; then
            break
        else
            stripped+="${ch}"
        fi
    done
    text="$(printf '%s' "${stripped}" | sed 's/[[:space:]]*$//')"
    printf '%s' "${text}"
}

sanitize() {
    printf '%s' "${1}" | sed 's/::/_/g'
}

{
    printf '%s\n' "#!/usr/bin/env bs"
    printf '%s\n' "# shellcheck shell=bash"
    printf '%s\n' "# ${test_file} — Unit tests for ${module_arg} (auto-generated skeleton)"
    printf '%s\n' "# ${test_file} — Модульные тесты для ${module_arg} (автосгенерированный скелет)"
    printf '%s\n' ""
    printf '%s\n' "set -euo pipefail"
    printf '%s\n' ""
    printf '%s\n' 'readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"'
    printf '%s\n' 'readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"'
    printf '%s\n' ""
    printf '%s\n' 'source "${TEST_SCRIPT_DIR}/../testframework.sh"'
    printf '%s\n' 'export BS_SILENT=1'
    printf '%s\n' 'source "${BS_PROJECT_ROOT}/bootstrap/init.sh"'
    printf '%s\n' 'export BS_HOME="${BS_PROJECT_ROOT}"'
    printf '%s\n' ""
    printf '%s\n' "load \"${module_arg}\""
    printf '%s\n' ""
    printf '%s\n' "# One test function per public function / По одной тест-функции на публичную функцию"
    printf '%s\n' "# Fill in inputs and expected values / Заполните входные данные и ожидаемые значения"
    printf '%s\n' ""

    for entry in "${funcs[@]}"; do
        lineno="${entry%%:*}"
        fn="${entry#*:}"
        fn="${fn%%(*}"
        fn="$(printf '%s' "${fn}" | sed 's/ *$//')"
        example="$(extract_example "${lineno}")"
        test_fn="test_$(sanitize "${fn}")"

        printf '%s\n' "${test_fn}() {"
        printf '%s\n' "    # ${fn}"
        if [[ -n "${example}" ]]; then
            printf '%s\n' "    # @example ${example}"
            printf '%s\n' "    local result"
            printf '%s\n' "    result=\"\$(${example})\" || true"
            printf '%s\n' '    testframework::assert_equal "expected" "${result}" "'"${fn}"' @example behavior"'
        else
            printf '%s\n' "    # TODO: call ${fn} with representative inputs and assert"
            printf '%s\n' '    testframework::assert_true "false" "'"${fn}"' needs a real assertion"'
        fi
        printf '%s\n' "}"
        printf '%s\n' ""
    done

    printf '%s\n' "main() {"
    printf '%s\n' '    print_header "'"${module_name}"' Unit Tests / Модульные тесты '"${module_name}"'"'
    printf '%s\n' ""
    printf '%s\n' '    testframework::init'
    printf '%s\n' ""
    printf '%s\n' '    testframework::section "Module Loading / Загрузка модуля"'
    printf '%s\n' '    testframework::assert_command "load '"${module_arg}"'" "Module loads / Модуль загружается"'
    printf '%s\n' ""
    for entry in "${funcs[@]}"; do
        fn="${entry#*:}"
        fn="${fn%%(*}"
        fn="$(printf '%s' "${fn}" | sed 's/ *$//')"
        printf '%s\n' '    testframework::section "'"${fn}"'"'
        # || true keeps the run going so every TODO shows up in the summary
        # || true не прерывает прогон — все TODO видны в сводке
        printf '%s\n' '    test_'"$(sanitize "${fn}")"' || true'
        printf '%s\n' ""
    done
    printf '%s\n' '    testframework::summary'
    printf '%s\n' "}"
    printf '%s\n' ""
    printf '%s\n' 'main "$@"'
} > "${tmp_out}"

if [[ "${local_write}" -eq 1 ]]; then
    mv "${tmp_out}" "${test_path}"
    echo "generated: ${test_path}"
else
    cat "${tmp_out}"
    rm -f "${tmp_out}"
fi
echo "public functions covered: ${#funcs[@]}" >&2