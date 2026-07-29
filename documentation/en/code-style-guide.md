# Code Style Guide

This guide follows and extends the
[Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html),
adapted to the BS framework. It details the rules needed to produce reliable,
maintainable and safe Bash code, libraries and production scripts, with an
emphasis on what matters for team development: modularity, testing,
documentation and protection against errors.

---

## Basic principles

- Executable files start with `#!/usr/bin/env bs`. Library modules use
  `#!/usr/bin/env bash`.
- Indent with 2 spaces.
- Line length: 80 characters.
- Comments are full sentences.
- Use `[[ ... ]]` instead of `[ ... ]`, `test` and `/usr/bin/[`.
- Quote variable expansions: `"${var}"`, not `$var`.
- Module files must include:
  - strict mode (`set -euo pipefail` and a safe `IFS`, see
    [1.1](#11-strict-mode));
  - a Source Guard against double sourcing (see [1.2](#12-module-file-structure-and-source-guard));
  - dependencies loaded via `load`, not via a direct `source lib/...` call.

## 1. Safety and reliability

### 1.1 Strict mode

Every entry-point script must enable strict mode: abort on error, on use of
undefined variables and on pipeline failures, plus a safe field separator:

```bash
set -euo pipefail
IFS=$'\n\t'
```

The framework provides a helper for this — `utils::strict()`
([core/utils.sh](../../core/utils.sh)). Strict mode is enabled in entry points
only, not inside library modules: modules run in the caller's shell and must
not silently change its options.

```bash
#!/usr/bin/env bs
load "core/utils"

utils::strict
```

### 1.2 Module file structure and Source Guard

To prevent conflicts and side effects in multi-file projects, every module
starts with a Source Guard — a guard against re-executing the code when the
file is sourced more than once:

```bash
#!/usr/bin/env bash
# lib/my_module.sh

# Source Guard
if utils::guard "MY_MODULE"; then return 0; fi
readonly __MY_MODULE_SOURCED=1

# Dependencies are loaded via load (path relative to the framework root,
# without the .sh extension)
load "core/logger"

# Global constants and module structures
readonly MODULE_NAME="my_module"
declare -gA MODULE_CONFIG
```

`utils::guard "name"` ([core/utils.sh](../../core/utils.sh)) checks the
`__NAME_SOURCED` variable: it returns 0 if the module has not been loaded yet,
and 1 if it has (then the file returns immediately).

On the first load `__MY_MODULE_SOURCED` is undefined, so the code runs; on
subsequent loads the variable is set and `return` skips the body.

Do not load modules with `source lib/...`. Use the `load` function
([bootstrap/loader.sh](../../bootstrap/loader.sh)): it resolves paths relative
to `BS_ROOT`, tracks already-loaded modules and detects circular dependencies.

## 2. Naming

| Object                            | Style               | Notes                                                          | Example                       |
|-----------------------------------|---------------------|----------------------------------------------------------------|-------------------------------|
| Constants and global readonly     | SCREAMING_SNAKE_CASE | Module prefix for isolation                                    | `readonly __MYLIB_MAX_RETRIES=5` |
| Functions                         | `lower_snake_case()` | Public framework API uses a module prefix: `module::function()` | `validate_input()`, `log::info()` |
| Private functions                 | `_leading_underscore` or double colon | Visible only inside the module                      | `_helper_calculate()`, `log::__timestamp()` |
| Local variables                   | lower_snake_case    | Optional `l_` prefix for clarity                               | `l_temp_file`                 |
| Function parameters               | lower_snake_case    |                                                                | `local -r file_path="$1"`     |
| Mutable globals                   | lower_snake_case    | Not recommended; prefer getter functions or associative arrays | (avoid)                       |
| Global associative arrays         | SCREAMING_SNAKE_MAP | `declare -gA` at module scope                                  | `declare -gA CONFIG_MAP`      |

Key points: the framework uses the Source Guard pattern (`__*_SOURCED`),
namespaces public functions with a `module::` prefix, and declares
configuration in associative arrays — all of which is required for complex
scripts.

## 3. Function documentation

The Google guide recommends comments; we formalize the format for a module's
public API:

```bash
# Calculate the sum of two integers.
# Args:
#   $1: First integer (required).
#   $2: Second integer (required).
# Returns:
#   0 on success, 1 on invalid input.
# Outputs:
#   Writes the result to stdout.
add_integers() {
  local -r first="$1"
  local -r second="$2"
  # ... validation logic ...
  printf '%d\n' "$(( first + second ))"
}
```

Or DocBlock style with `@` annotations:

```bash
# @description Short description of the function.
# @param $1 First argument - description.
# @param [$2=default] Second argument with a default value.
# @returns 0 on success.
# @returns 1 on error.
# @stdout Writes the result to stdout.
# @stderr Writes errors to stderr.
# @example
#   function_name "arg1" "arg2"
# @see related_function
# @deprecated Use new_function instead.
```

### Recommended hybrid for BS

Keep the human-readable Google format as the primary text and add
`@` annotations for automatic documentation generation:

```bash
# Validate an input string against a pattern.
#
# @function validate_input
# @param $1 {string} Input string to validate
# @param $2 {regex} Pattern to check against
# @returns 0 if validation succeeds
# @returns 1 if the string does not match the pattern
# @example
#   validate_input "test@example.com" '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
validate_input() {
  local -r input="$1"
  local -r pattern="$2"
  if [[ "$input" =~ $pattern ]]; then
    return 0
  else
    return 1
  fi
}
```

### Rules

1. All public functions must be documented.
2. Use the Google format as the primary text.
3. Add `@` annotations for important metadata.
4. Required annotations: `@param`, `@returns`, `@stdout`/`@stderr`.
5. Optional: `@example`, `@see`, `@deprecated`.

## 4. Variables and data

### 4.1 Declaration and scope

- Always use `local` for variables inside functions.
- Use `local -r` for parameters and function-local constants.
- For integers and arrays: `local -i`, `local -a`.
- Global associative arrays are a powerful configuration tool. Use them
  carefully:

```bash
# Declare once at the top of the module
declare -gA SERVICE_ENDPOINTS

_init_config() {
  SERVICE_ENDPOINTS["api"]="https://api.example.com"
  SERVICE_ENDPOINTS["db"]="postgresql://localhost:5432"
}

get_endpoint() {
  local -r service_name="$1"
  # Checking that the key exists is CRITICAL
  if [[ -v "SERVICE_ENDPOINTS[${service_name}]" ]]; then
    printf '%s\n' "${SERVICE_ENDPOINTS[${service_name}]}"
  else
    log::error "Endpoint for service '${service_name}' not defined."
    return 1
  fi
}
```

## 5. Error handling and logging

The Google guide suggests plain `echo` for errors; the framework provides a
logging module ([core/logger.sh](../../core/logger.sh)) and an error-handling
module ([core/errorhandler.sh](../../core/errorhandler.sh)):

- Non-fatal errors: return meaningful exit codes (1-63) and write to stderr
  via `log::error`.
- Fatal errors: use `error::exit "message" [code]` — it logs the message,
  runs registered cleanup functions and exits. Note that `log::fatal` does
  **not** exit by itself; it returns an error code and leaves the exit
  decision to the caller.

```bash
#!/usr/bin/env bs
load "core/logger"
load "core/errorhandler"

connect() {
  local -r host="$1"
  if ! utils::quiet ping -c1 "${host}"; then
    log::error "Host ${host} is unreachable"
    return 2  # exit code for "host unreachable"
  fi
  # If this is fatal for the script:
  # error::exit "Host ${host} is unreachable" 101
}
```

## 6. Silencing output

Do not write raw redirections like `>/dev/null 2>&1` or `2>/dev/null`. Use the
idioms from [core/utils.sh](../../core/utils.sh) — they state the intent and
preserve the exit code:

| Instead of                      | Use              | Semantics                                   |
|---------------------------------|------------------|---------------------------------------------|
| `command -v cmd >/dev/null 2>&1` | `utils::has cmd` | check that a command exists in PATH         |
| `cmd >/dev/null 2>&1`           | `utils::quiet cmd` | run, suppress stdout and stderr           |
| `cmd 2>/dev/null`               | `utils::quiet_err cmd` | run, suppress stderr only             |
| `cmd >/dev/null 2>&1 \|\| true` | `utils::ignore cmd` | run and ignore the result (always returns 0) |

```bash
if utils::has dnf; then
  utils::quiet dnf check-update
fi

# Use utils::ignore only where a failure genuinely does not matter
utils::ignore systemctl stop some-service
```

## 7. Project structure

The actual layout of the BS framework:

```text
bs/
├── bootstrap/         # Bootstrap: init.sh, loader.sh (the load function)
├── core/              # Core: args, const, errorhandler, logger, utils, version
├── lib/               # Feature modules: audit, data, frameworks, integration,
│                      #   io, network, status, system, ui
├── install/           # Installation logic (actions, checks, path_manager)
├── tests/             # Tests: testframework.sh, runalltests.sh,
│                      #   unit/, integration/, ...
├── examples/          # Usage examples
├── documentation/     # Documentation (en/, ru/, archive/)
├── bs                 # The bs launcher (shebang target)
├── boot.sh            # Entry point for bootstrapping the environment
├── install.sh         # Installer
└── README.md
```

## 8. Testing and linting

Testing: use the framework's own test library
[tests/testframework.sh](../../tests/testframework.sh) — not BATS. It provides
`testframework::init`, `testframework::assert_true`, `testframework::assert_false`,
`testframework::assert_equal`, `testframework::assert_file_exists`,
`testframework::assert_command`, `testframework::section` and
`testframework::summary`. Every public function should have a unit test in
`tests/unit/`; run the whole suite with `tests/runalltests.sh`.

```bash
#!/usr/bin/env bs
# tests/unit/testmymoduleunit.sh
set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

main() {
  testframework::init
  testframework::section "Module initialization"
  testframework::assert_true '[[ -n "${BS_ROOT}" ]]' "BS_ROOT is set"
  testframework::summary
}

main "$@"
```

Linting: always run [shellcheck](https://www.shellcheck.net/) — the repository
has a [.shellcheckrc](../../.shellcheckrc) config and a
[tests/validateshellcheck.sh](../../tests/validateshellcheck.sh) script. Wire
both into CI.
