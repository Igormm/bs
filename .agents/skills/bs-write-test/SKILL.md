---
name: bs-write-test
description: Write a BS framework unit or integration test using the custom testframework.sh asserts and auto-discovery conventions
type: prompt
whenToUse: When the user asks to add tests, write a unit test for a module, or fix/extend existing tests in tests/
arguments:
  - target_module
---

Write tests for `$target_module` using the project's own test framework (`tests/testframework.sh` — NOT BATS). Look at `tests/unit/testloggerunit.sh` for a living example.

## Unit test skeleton

Place at `tests/unit/test<module>unit.sh` — files in `tests/unit/` are auto-discovered by `tests/runalltests.sh`:

```bash
#!/usr/bin/env bs
# shellcheck shell=bash
set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

main() {
    print_header "MyModule Unit Tests / Модульные тесты mymodule"
    testframework::init

    testframework::section "Module Loading / Загрузка модуля"
    load "core/mymodule"
    testframework::assert_true "${MYMODULE_LOADED:-}" "Module loaded"

    testframework::section "Function behavior / Поведение функции"
    local result
    result="$(mymodule::do_thing "input")"
    testframework::assert_equal "expected" "${result}" "do_thing returns expected value"

    testframework::summary
}

main "$@"
```

## Targeted coverage / Таргетированное покрытие

For a module with many public functions, generate a skeleton test with one
test function per public function (auto-extracts `@example` doc blocks as
initial assertions):

```bash
bash .agents/skills/bs-write-test/scripts/gen_test_skeleton.sh core/lang.sh --write
```

- Generates `tests/unit/test<module>unit.sh`, one `test_<fn>()` per public
  function (`ns::fn` → `test_ns_fn`), private `::__` functions are skipped.
- Functions with a runnable `# @example` get a real `assert_equal` call;
  the rest get a `assert_true "false"` TODO that fails until filled in.
- `|| true` after each test call keeps the run alive so the summary shows
  every TODO. The generated file is a RED skeleton — fill in inputs and
  expected values, then re-run. Do not commit it unfilled.
- Without `--write` the skeleton goes to stdout.

## Assert API (tests/testframework.sh)

- `testframework::init` / `testframework::summary` — summary exits 1 on failures.
- `testframework::assert_true "<condition>" "name"` — eval'd as `[[ ... ]]`.
- `testframework::assert_false "<command>" "name"` — expects the command to fail.
- `testframework::assert_equal "expected" "actual" "name"`.
- `testframework::assert_file_exists "path" "name"`.
- `testframework::assert_command "<command>" "name"`.
- `testframework::section "..."`, `print_header "..."` — output structure; headers bilingual ru/en.

## Rules

- Test files are entry points: strict mode `set -euo pipefail` IS required here (unlike modules).
- Every new public function should get at least one test (AGENTS.md requirement).
- Tests run via `bash <script>`, so never rely on executable bits.
- Integration/system tests go to `tests/{integration,network,audit,status,data,frameworks}/`, not `unit/`.
- Destructive root tests must be registered in the `ROOT_TESTS` list in `tests/runalltests.sh`; they only run with `--with-root` as root. Do not add new ones unless the user explicitly asks.
- Always finish by running: `bash tests/validatesyntax.sh && bash tests/runalltests.sh`.
