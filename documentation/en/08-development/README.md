[↑ Documentation index](../README.md)

# Development guide

How to write a BS module, add tests, and run the pre-commit checks.

## Writing a module

### Location and naming

Library modules live in `lib/<group>/<name>.sh`. Existing groups:
`audit`, `data`, `frameworks`, `integration`, `io`, `network`, `status`,
`system`, `ui`. Core machinery (logger, args, utils, error handler) lives in
`core/`.

Public functions are named `<group>::<module>::<func>` — for example
`system::distro::detect()` in
[lib/system/distro.sh](../../../lib/system/distro.sh) or `io::streams::print()`
in [lib/io/streams.sh](../../../lib/io/streams.sh). Private helpers get a
double underscore before the function name: `io::streams::__is_fd()`.

### File skeleton

```bash
#!/usr/bin/env bs
# lib/system/foo.sh — Short description of the module
#
# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# Source Guard / Защита от повторной загрузки
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/guard.sh"
bs::guard "SYSTEM_FOO" || return 0
```

Key points:

- The shebang is `#!/usr/bin/env bs` (ShellCheck runs with `-s bash` because of
  this, see [tests/validateshellcheck.sh](../../../tests/validateshellcheck.sh)).
- A module must not call `set -euo pipefail` or change `IFS` — that is the
  entry point's job (see [Strict mode](#strict-mode)).
- The source guard prevents double execution when the file is sourced twice.
  Use the `bs::guard` wrapper from [core/guard.sh](../../../core/guard.sh):
  it atomically checks the `__SYSTEM_FOO_SOURCED` mark and sets it; it returns
  1 if the module was already loaded (then `|| return 0` fires). The manual
  `[[ -n "${__X_SOURCED:-}" ]] && return 0` idiom and the check-only
  `utils::guard` helper are deprecated and kept for backward compatibility.

### Dependencies

The loader ([bootstrap/loader.sh](../../../bootstrap/loader.sh)) parses a
`# @depends` comment in the module file and loads the listed modules first,
with cycle detection:

```bash
# @depends core/logger, lib/system/utils
```

Dependencies are module paths relative to `BS_ROOT`, without the `.sh`
extension, comma-separated. Additionally, every module self-sources its
dependencies right after the Source Guard — with paths relative to its own
file — so the module also works when sourced directly, bypassing the loader:

```bash
bs::guard "SYSTEM_FOO" || return 0

# Зависимости / Dependencies
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/const.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/logger.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/utils.sh"
```

An entry script then loads the module with:

```bash
#!/usr/bin/env bs
load "lib/system/foo"
```

Do not `source lib/...` paths by hand in user scripts — `load` tracks loaded
modules in `BS_LOADED_MODULES` and skips duplicates.

### Docstring format

Public functions are documented with `@`-annotations directly above the
function (the hybrid style from the
[code style guide](../../archive/code-style-guide.md)):

```bash
# @description Check if a package is installed / Проверить, установлен ли пакет
# @param $1 Package name / Имя пакета
# @return 0 if installed, 1 if not / 0 если установлен, 1 если нет
# @example
#   if system::distro::is_package_installed "curl"; then
#       echo "curl is installed"
#   fi
system::distro::is_package_installed() {
```

Required annotations: `@description`, `@param` per argument, `@return` /
`@returns`. Optional: `@example`, `@private` (marks internal helpers),
`@see`, `@deprecated`. Prose may be bilingual `English / Русский`, as in the
existing lib modules.

## Silence idioms

Never write bare `/dev/null` redirections in module code — use the wrappers
from [core/utils.sh](../../../core/utils.sh). They make intent explicit and
keep the exit code semantics visible:

| Instead of | Use | Notes |
|---|---|---|
| `command -v cmd >/dev/null 2>&1` | `utils::has cmd` | in `if` conditions |
| `cmd >/dev/null 2>&1` | `utils::quiet cmd` | exit code preserved |
| `cmd 2>/dev/null` | `utils::quiet_err cmd` | exit code preserved |
| `cmd >/dev/null 2>&1 \|\| true` | `utils::ignore cmd` | failure truly irrelevant |

Real usage — [lib/system/distro.sh](../../../lib/system/distro.sh):

```bash
if utils::has lsb_release; then
    DISTRO_ID=$(utils::quiet_err lsb_release -si | tr '[:upper:]' '[:lower:]')
fi

# dnf|yum)
#     utils::quiet rpm -q "${package}"
```

`utils::ignore` is for cases where a failure genuinely does not matter; do not
use it to hide errors that the caller might care about.

## Strict mode

`set -euo pipefail` and `IFS=$'\n\t'` are set **only in entry points** —
executable scripts such as `bs`, `boot.sh`, and the test runners under
`tests/` — never inside sourced modules. Every module header states this
explicitly:

```bash
# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points
```

Rationale: a sourced module must not change the caller's shell options as a
side effect. Module code is written to work both with and without strict mode
(quote variables, use `"${var:-default}"`, check exit codes explicitly). A
`utils::strict()` helper exists in [core/utils.sh:17](../../../core/utils.sh)
for entry points that prefer a function call over the raw `set` line.

## Adding a test

1. Create a file in the matching `tests/` directory — unit tests go to
   `tests/unit/test<name>unit.sh` (see
   [tests/unit/testloaderunit.sh](../../../tests/unit/testloaderunit.sh) for a
   template). Other directories: `integration`, `data`, `frameworks`,
   `network`, `status`, `audit`, `demos`.
2. Skeleton:

   ```bash
   #!/usr/bin/env bs
   # tests/unit/testfoounit.sh — Unit tests for lib/system/foo

   set -euo pipefail

   readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

   source "${TEST_SCRIPT_DIR}/../testframework.sh"

   export BS_SILENT=1
   source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
   export BS_HOME="${BS_PROJECT_ROOT}"

   main() {
       print_header "Foo Unit Tests"
       testframework::init

       testframework::section "Load"
       testframework::assert_command 'load "lib/system/foo"' "Load lib/system/foo"
       testframework::assert_true "true" "example assertion"

       testframework::summary
   }

   main "$@"
   ```

   Assertions available from
   [tests/testframework.sh](../../../tests/testframework.sh):
   `testframework::assert_true`, `testframework::assert_false`,
   `testframework::assert_equal`, `testframework::assert_file_exists`,
   `testframework::assert_command`.
3. No registration needed:
   [tests/runalltests.sh](../../../tests/runalltests.sh) runs every `*.sh` it
   finds in the test directories.

## Pre-commit checks

Run the same three scripts that CI runs
([.github/workflows/ci.yml](../../../.github/workflows/ci.yml)):

```bash
bash tests/validatesyntax.sh       # bash -n over all files
bash tests/validateshellcheck.sh   # ShellCheck, error severity must pass
bash tests/runalltests.sh          # full test suite
```

Notes:

- `validateshellcheck.sh` exits 0 when ShellCheck is not installed locally —
  CI installs it, so check warnings manually if you changed tricky code.
- `runalltests.sh --with-root` additionally runs destructive/root-requiring
  tests; only do that as root on a disposable system.
- CI runs the test suite in containers covering bash 5.x (ubuntu, debian,
  almalinux 9) and bash 4.4 (almalinux 8) — the framework minimum. Do not use
  features newer than bash 4.4 in modules.
