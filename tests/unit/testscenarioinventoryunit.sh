#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testscenarioinventoryunit.sh — bs-scenario-audit: inventory.sh
#
# The inventory runs on a fixture tree whose functions have known risk markers,
# arguments, flags and test mentions; the real project is never scanned here.
# Опись запускается на фикстуре с известными маркерами риска, аргументами,
# флагами и упоминаниями в тестах; настоящий проект здесь не сканируется.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly INVENTORY="${BS_PROJECT_ROOT}/.agents/skills/bs-scenario-audit/scripts/inventory.sh"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

T=""
OUT=""
RC=0

make_fixture() {
    T="$(mktemp -d)"
    mkdir -p "${T}/src" "${T}/tests"
    cat > "${T}/src/demo.sh" <<'EOF'
#!/usr/bin/env bash
demo::safe() {
  local -r a="${1:?a}"
  printf '%s\n' "${a}"
}

demo::wipe() {
  local dir="${1}"
  rm -rf "${dir}"
}

demo::flags() {
  case "$1" in
    --force|-f) force=1 ;;
    --name) name="$2" ;;
  esac
  utils::ignore true
}

demo::counter() {
  local n=0
  ((n++))
  echo "$@"
}

demo::__private() { rm -rf /nonexistent; }

demo::oneliner() { printf x; }
EOF
    printf 'demo::safe a\ndemo::safe b\n' > "${T}/tests/testdemo.sh"
}

run_inv() {
    RC=0
    OUT="$(bash "${INVENTORY}" --tests-dir "${T}/tests" "$@" 2>&1)" || RC=$?
}

row() { grep -F "\`$1\`" <<< "${OUT}" | head -n 1; }
has() { if grep -qF -- "$1" <<< "$2"; then testframework::assert_true "true" "$3" || true
        else testframework::assert_true "false" "$3" || true
             printf '    not found / не найдено: %s\n    in: %s\n' "$1" "$2"; fi; }
lacks() { if grep -qF -- "$1" <<< "$2"; then testframework::assert_true "false" "$3" || true
          else testframework::assert_true "true" "$3" || true; fi; }

test_rows() {
    make_fixture
    run_inv "${T}/src"
    testframework::assert_equal "0" "${RC}" "inventory exits 0"
    has "| риск | функция |" "${OUT}" "markdown header"

    local r
    r="$(row demo::safe)"
    has "| 0 |" "${r}" "safe: risk 0"
    has "| 1 |" "${r}" "safe: one argument"
    has "| 2 |" "${r}" "safe: two mentions in the tests"

    r="$(row demo::wipe)"
    has "| 5 |" "${r}" "wipe: destructive 3 + strict trap 2 = 5"
    has "destructive+strict-trap" "${r}" "wipe: markers named"
    has "| 0 |" "${r}" "wipe: no tests"

    r="$(row demo::flags)"
    has "--force|-f,--name" "${r}" "flags: case patterns collected"
    has "masking" "${r}" "flags: utils::ignore is masking"
    has "| 2 |" "${r}" "flags: highest argument is \$2"

    r="$(row demo::counter)"
    has "strict-trap" "${r}" "counter: ((n++)) is a strict-mode trap"
    has "0+@" "${r}" "counter: variadic arguments"

    has "demo::oneliner" "${OUT}" "a one-line function is listed"
    lacks "demo::__private" "${OUT}" "private functions are not listed"
    has "Функций в описи: 5, показано: 5, без тестов: 4, с риском > 0: 3" "${OUT}" "the totals line"
    rm -rf "${T:?}"
}

test_plain_names_and_unterminated() {
    make_fixture
    cat > "${T}/src/plain.sh" <<'FIXTURE'
plain_fn() {
  local x="${1}"
  rm -rf "${x}"
}
broken::fn() {
  echo never closed
FIXTURE
    printf 'call plain_fn here\n' > "${T}/tests/testplain.sh"
    run_inv "${T}/src/plain.sh"
    local r
    r="$(row plain_fn)"
    has "| 1 |" "${r}" "a function without :: is counted by the word in the tests"
    has "unterminated function broken::fn" "${OUT}" "an unterminated function is reported, not dropped silently"
    lacks "\`broken::fn\`" "${OUT}" "an unterminated function is not listed as if it were complete"
    rm -rf "${T:?}"
}

test_filters_and_csv() {
    make_fixture
    run_inv --untested "${T}/src"
    lacks "demo::safe" "${OUT}" "--untested hides the tested function"
    has "demo::wipe" "${OUT}" "--untested keeps the untested one"

    run_inv --min-risk 5 "${T}/src"
    has "demo::wipe" "${OUT}" "--min-risk 5 keeps risk 5"
    lacks "demo::safe" "${OUT}" "--min-risk 5 drops risk 0"
    lacks "demo::counter" "${OUT}" "--min-risk 5 drops risk 2"

    run_inv --csv "${T}/src"
    has "risk,function,where,lines,args,flags,markers,tests" "${OUT}" "csv header"
    has "5,demo::wipe," "${OUT}" "csv row"
    lacks "| риск |" "${OUT}" "no markdown in csv mode"
    rm -rf "${T:?}"
}

test_errors_and_read_only() {
    make_fixture
    run_inv --bogus
    testframework::assert_equal "2" "${RC}" "unknown option: exit 2"
    run_inv --min-risk abc "${T}/src"
    testframework::assert_equal "2" "${RC}" "--min-risk needs a number: exit 2"
    run_inv "${T}/does-not-exist"
    testframework::assert_equal "2" "${RC}" "missing scope: exit 2"
    has "not found" "${OUT}" "missing scope: explained"
    run_inv --help
    testframework::assert_equal "0" "${RC}" "--help exits 0"
    has "--untested" "${OUT}" "--help documents --untested"

    local before after
    before="$(find "${T}" -type f -exec sha256sum {} + | sort | sha256sum)"
    run_inv "${T}/src"
    after="$(find "${T}" -type f -exec sha256sum {} + | sort | sha256sum)"
    testframework::assert_equal "${before}" "${after}" "the inventory changes nothing"
    rm -rf "${T:?}"
}

main() {
    print_header "Scenario Inventory Unit Tests / Тесты описи bs-scenario-audit"

    testframework::init

    testframework::section "Rows / Строки описи"
    test_rows

    testframework::section "Plain names, unterminated / Имена без ::, незакрытые"
    test_plain_names_and_unterminated

    testframework::section "Filters, CSV / Фильтры, CSV"
    test_filters_and_csv

    testframework::section "Errors, read-only / Ошибки, только чтение"
    test_errors_and_read_only

    testframework::summary
}

main "$@"
