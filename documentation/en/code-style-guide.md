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
  This is the rule for `lib/` and `bash4` code; kernel code in the `bs_` namespace (`@shell posix`)
  follows the opposite one, see [12](#12-code-in-the-bs_-namespace-the-kernel-tier-shell-posix).
- Quote variable expansions: `"${var}"`, not `$var`.
- Strict mode (`set -euo pipefail` and a safe `IFS`, see
  [1.1](#11-strict-mode)) is enabled by entry points, not by modules.
- Module files must include:
  - a Source Guard against double sourcing (see [1.2](#12-module-file-structure-and-source-guard));
  - dependencies loaded via `load`, not via a direct `source lib/...` call.

## 1. Safety and reliability

### 1.1 Strict mode

Every entry point runs under strict mode: abort on error, on use of
undefined variables and on pipeline failures, plus a safe field separator:

```bash
set -euo pipefail
IFS=$'\n\t'
```

- `#!/usr/bin/env bs` scripts get strict mode from the interpreter: `bs run`
  enables `set -euo pipefail` **before** the script is sourced — no strict
  line needed (see [getting-started](../01-getting-started/README.md)).
- Plain `#!/usr/bin/env bash` entry points (`bs`, `boot.sh`, test runners)
  set it themselves — via the pre-kernel `bs::strict()`
  ([bootstrap/bs.sh](../../bootstrap/bs.sh)), via `utils::strict()`
  ([core/utils.sh](../../core/utils.sh)) or the raw line above:

```bash
#!/usr/bin/env bash
source /path/to/bootstrap/init.sh

utils::strict
```

Strict mode is enabled in entry points only, never inside library modules:
modules run in the caller's shell and must not silently change its options.

### 1.2 Module file structure and Source Guard

To prevent conflicts and side effects in multi-file projects, every module
starts with a Source Guard — a guard against re-executing the code when the
file is sourced more than once:

```bash
#!/usr/bin/env bash
# lib/my_module.sh
#
# @depends core/const, core/logger, core/utils

# Source Guard — bs::guard is provided by core/prereq.sh, which is
# autoloaded first by bootstrap/init.sh; modules must NOT source it manually
bs::guard "MY_MODULE" || return 0

# Dependencies — self-source relative to the module file (the module works
# even when sourced directly, without the loader); the @depends header
# duplicates them for load
bs::source_relative "../core/const.sh" "../core/logger.sh" "../core/utils.sh"

# Global constants and module structures
readonly MODULE_NAME="my_module"
declare -gA MODULE_CONFIG
```

`bs::guard "name"` ([core/prereq.sh](../../core/prereq.sh)) atomically checks
and sets the `__NAME_SOURCED` variable: it returns 1 if the module **has
already been loaded** (then `|| return 0` skips the rest of the file), and 0
on first load — the mark is set and the module body runs.

On the first load `__MY_MODULE_SOURCED` is undefined, so the code runs; on
subsequent loads the variable is set and `return` skips the body. Do not
hand-roll the `[[ -n "${__X_SOURCED:-}" ]] && return 0` idiom in new modules.
Do not `source core/prereq.sh` manually either — `bootstrap/init.sh` loads it
before every other module, so `bs::guard` and `bs::source_relative` are always
available a priori. The legacy `utils::guard` from `core/utils.sh` is kept as
an alias for backward compatibility.

Do not load modules with `source lib/...`. Use the `load` function
([bootstrap/loader.sh](../../bootstrap/loader.sh)): it resolves paths relative
to `BS_ROOT`, tracks already-loaded modules and detects circular dependencies.
See [section 8](#8-module-metadata-and-source-guard) for more on module metadata.

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

### 2.1 Why snake_case and not CamelCase

BS deliberately uses a single unix-like style (`lower_snake_case` +
`module::` namespaces) everywhere; CamelCase is never used:

- **Shell has no compiler.** A case typo (`System::Hw::Cpu` vs
  `system::hw::cpu`) is not caught by anything at write time. In snake_case
  a case typo is impossible by construction — everything is one register.
- **One style means zero ambiguity.** With two styles every name raises the
  question "which one here?". `system::hw::cpu_threads` already reads as a
  path — CamelCase would only add a second way to write it.
- **Ecosystem consistency.** Builtins, coreutils, and environment variables
  are all snake/SCREAMING — a newcomer reads man pages and other people's
  scripts in the same style.
- **Tooling.** A single style keeps the grammar and the naming-convention
  diagnostics of the LSP server simple.

Style matrix:

- `SCREAMING_SNAKE_CASE` — constants, `readonly`, environment variables.
- `lower_snake_case` — functions, variables, module names. No mixedCase.
- `__double_underscore` — private.

If a class-like subsystem ever appears (constructors, typed values), a
PascalCase slot can be discussed separately — until then there are no types,
so there is no CamelCase slot.

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

### 4.2 Module-level variable categories and documentation

Every variable declared outside a function (`declare -g`, `readonly`, `export`,
`: "${VAR:=...}"`) belongs to one of the categories below. The category fixes
the name mask and whether a doc snippet is required.

| # | Category | Mask | Examples | Snippet |
|---|---|---|---|---|
| 1 | Guard flags | `__<MODULE>_SOURCED` | `__ARGS_SOURCED`, `__PREREQ_SOURCED` | no — set programmatically by `bs::guard`, documented once in `core/prereq.sh` |
| 2 | Module metadata | `<MODULE>_LOADED`, `<MODULE>_VERSION` | `ARGS_LOADED`, `CORE_LANG_VERSION` | yes |
| 3 | Ephemeral (init.sh temps) | `__name__` | `__bs_src__`, `__BS_INIT_DIR__` | optional |
| 4 | Nameref locals | `__sl_*`, `__arr_*`, `__map_*`, `__b_*` | `__arr_elem`, `__sl_start` | no — function-local, shadowing-safe by design |
| 5 | Private functions | `ns::__name` | `log::__format_message` | functions, not variables |
| 6 | Private locals | `_name` | `_rc`, `_saved_stdout` | no — function-local |
| 7 | Error constants | `E_*`, `LIB_ERROR_*` | `E_ERROR`, `LIB_ERROR_INVALID_ARGS` | yes |
| 8 | Framework flags | `FRAMEWORK_*` | `FRAMEWORK_DEBUG`, `FRAMEWORK_DRY_RUN` | yes |
| 9 | Env vars | `BS_*` | `BS_ROOT`, `BS_SILENT`, `BS_CONFIG_*` | yes |
| 10 | Module hooks | `<MODULE>_*_{DIR,PATH,MOCK,FILE,TIMEOUT}` | `HW_DMI_PATH`, `LLM_MOCK_RESPONSE`, `VK_API_CACHE_DIR` | yes |
| 11 | Module constants | `readonly SCREAMING_SNAKE` | `COLOR_RESET`, `SSH_NETWORK_CONNECT_TIMEOUT` | yes |
| 12 | Module internal state | `__<MODULE>_*` | `__ARGS_TREE`, `__ARGS_FLAGS` | yes |
| 13 | Module state (public mutable) | `<MODULE>_*` (non-hook, non-readonly) | `TUI_KEY`, `TUI_MODAL_STACK`, `SSHD_WZ_VALUES` | yes |

A `: "${VAR:=...}"` declaration is always a **hook** (category 10) regardless
of the name suffix.

**Doc snippet format.** Module-level variables in categories 2, 7-11 carry a
bilingual snippet directly above the declaration:

```bash
# @global FRAMEWORK_DEBUG — framework flag (category: framework-flag); default false
# @global FRAMEWORK_DEBUG — флаг фреймворка (категория: framework-flag); по умолчанию false
declare -g FRAMEWORK_DEBUG=false
```

- The snippet starts with `# @global <NAME> —`, names the category label and
  describes the purpose/default. A reader can tell what the variable is
  without reading its users.
- Category labels (machine-readable): `guard-flag`, `module-flag`,
  `ephemeral`, `nameref`, `private-fn`, `underscore`, `error-const`,
  `framework-flag`, `env`, `hook`, `constant`, `private`, `state`.
- Categories 1, 4, 6 need no snippet (programmatic or function-local).

**Mask hygiene.** Anchored boundaries matter: `\bE_[A-Z][A-Z_]*\b` matches
`E_ERROR` but NOT the `E__` substring inside `__BS_ROOT_CANDIDATE__` (the
unbounded `E_[A-Z_]+` does). Check order matters too: anchored `__name__`
(category 3) before the open-ended `__x_y` (category 4) — `__bs_src__`
matches both masks.

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
| `cmd 2>/dev/null \|\| true`     | `utils::attempt cmd` | best-effort run, keep stdout, ignore failure |

For conditions, use the `is::*` predicates from [core/lang.sh](../../core/lang.sh)
instead of test flags — `is::empty "${var}"` instead of `[[ -z "${var}" ]]`,
`is::file "${path}"` instead of `[[ -f "${path}" ]]`, `is::command cmd` instead
of `command -v ...`, and so on (full table: [core-api.md](04-api-reference/core-api.md)).

```bash
if utils::has dnf; then
  utils::quiet dnf check-update
fi

# Use utils::ignore only where a failure genuinely does not matter
utils::ignore systemctl stop some-service
```

## 7. Framework abstractions

In addition to the basic idioms in `core/utils.sh`, the framework provides
high-level abstractions for streams, files, and processes. Use them in new
modules instead of low-level commands.

### 7.1 I/O streams

The `lib/io/streams.sh` module centralizes stream, FD, and redirection handling.

| Instead of | Use |
|------------|-----|
| `echo "$msg"` | `io::streams::print "$msg"` |
| `echo -n "$msg"` | `io::streams::printn "$msg"` |
| `printf "%s" "$data"` | `io::streams::printf "%s" "$data"` (format is a separate argument) |
| `>&2 echo` | `io::streams::eprint "$msg"` |
| `exec 1>file` | `io::streams::redirect_stdout "file"` |
| `exec 3>&1` / `exec 1>&3-` | `io::streams::save 1 saved` / `io::streams::restore "$saved" 1` |

```bash
load "lib/io/streams"

io::streams::print "safe output"
io::streams::eprint "error message"
```

Rules:
- Never pass user data as the `printf` format string.
- For dynamic file descriptors use Bash 4 syntax: `exec {fd}<file`.
- Library functions must not write to stdout unless that is their purpose;
  diagnostics go through `log::warn` / `log::error`.

### 7.2 File operations

The `lib/io/files.sh` module (FSH API) replaces direct calls to `cp`, `mv`, `rm`.

```bash
load "lib/io/files"

io::files::copy_file "src.txt" "dst.txt"
io::files::ensure_dir "my/dir" "0750"
io::files::move "old" "new"
io::files::remove "tmp"
```

Features:
- Supports `FRAMEWORK_DRY_RUN=true`: the command is only logged, not executed.
- Atomic operations via a temporary file/directory next to the target.
- Automatic backups via `BS_FILES_BACKUP_SUFFIX`.
- Cross-device move with fallback to `cp -a` + `rm -rf`.
- Error codes: `E_INVALID`, `LIB_ERROR_FILE_NOT_FOUND`, `LIB_ERROR_FILE_OPERATION`.

### 7.3 Process guard and strace debugging

The `lib/io/process.sh` module runs a command, watches for timeout and hang,
collects diagnostics, and optionally runs `strace`.

```bash
load "lib/io/process"

# 60 s timeout, consider hung after 30 s of silence
io::process::guard --timeout 60 --hang-after 30 -- ./long-task

# Also collect network strace
io::process::guard --timeout 120 --hang-after 60 --strace-net -- ./server
```

When the guard triggers, the diagnostic directory contains:
- `report.log` — snapshot of `/proc/<pid>/status`, `stack`, `fd/`, `wchan`, `ps`;
- `strace_file.log` — `strace -p <pid> -e trace=read,write,%file`;
- `strace_net.log` — `strace -p <pid> -e trace=%net` (if requested).

Rules:
- Always separate the wrapped command's arguments from the guard options with `--`.
- strace runs with `sudo -n`; if privileges are missing, diagnostics are collected
  without strace.
- Use the cleanup stack (`cleanup::add`) to clean up child processes.

## 8. Module metadata and Source Guard

### 8.1 Source Guard

Every module must guard against repeated imports. Use the shared `bs::guard`
wrapper from [core/prereq.sh](../../core/prereq.sh) — it checks the
`__NAME_SOURCED` mark and sets it in a single call:

```bash
#!/usr/bin/env bash
# lib/my_module.sh

bs::guard "MY_MODULE" || return 0
```

`core/prereq.sh` is autoloaded first by `bootstrap/init.sh`, so `bs::guard` is
always available — modules never source `prereq.sh` themselves.

[core/guard.sh](../../core/guard.sh) is kept as a backward-compatible wrapper
around `core/prereq.sh`.

Legacy variants found in older code:

```bash
# check-only helper from core/utils.sh (deprecated, alias to bs::guard_loaded)
if utils::guard "MY_MODULE"; then return 0; fi
readonly __MY_MODULE_SOURCED=1

# manual idiom in early core/ modules
[[ -n "${__CONST_SOURCED:-}" ]] && return 0
readonly __CONST_SOURCED=1
```

### 8.2 Metadata

After the Source Guard, declare the module version and load marker:

```bash
readonly MODULE_NAME="my_module"
declare -g MODULE_VERSION="1.0.0"
```

At the end of the module:

```bash
declare -g MODULE_LOADED="1"
```

### 8.3 Dependencies

If a module may be sourced outside the loader (for example, from another module
or directly by the user), use `bs::source_relative` from
[core/prereq.sh](../../core/prereq.sh) to load dependencies relative to the
module's own file:

```bash
bs::guard "MY_MODULE" || return 0

# @depends core/logger, core/errorhandler, lib/io/streams
bs::source_relative "../core/logger.sh" "../core/errorhandler.sh" "../io/streams.sh"
```

Rules:
- Do not `source core/prereq.sh` manually — it is autoloaded first by
  `bootstrap/init.sh`, so `bs::guard` and `bs::source_relative` are available
  a priori.
- Replace all dependency sources with `bs::source_relative`.
- Multiple dependencies can be passed in a single call.
- If the module is guaranteed to be loaded through `load`, use `load` and
  declare dependencies with a `# @depends` comment.

### 8.4 Loading via `load` (inside the framework)

When the module is already inside a loaded BS environment, use `load`:

```bash
# @depends core/logger, core/errorhandler, lib/io/streams
load "core/logger"
load "core/errorhandler"
load "lib/io/streams"
```

## 9. Project structure

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
├── documentation/     # Documentation (en/, ru/)
├── bs                 # The bs launcher (shebang target)
├── boot.sh            # Entry point for bootstrapping the environment
├── install.sh         # Installer
└── README.md
```

## 10. Testing and linting

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

## 11. Capability vector / Вектор возможностей

New functions in the kernel (`core/`) and library (`lib/`) must work on any
target environment of BS: GNU/Linux, macOS and FreeBSD (BSD userland),
busybox (Alpine), glibc and musl. Rules:

1. **Feature detection over OS detection.** Probe a capability, not an OS
   name. Do not write `if [[ "$(uname)" == "Darwin" ]]` to pick an
   implementation — probe the tool/behavior:
   ```bash
   if printf 'a\nb' | sed -z 's/a/X/' >/dev/null 2>&1; then SED_Z=1; fi
   if printf 'x' | grep -Pq 'x' 2>/dev/null; then GREP_P=1; fi
   ```
2. **Probe chain with fallbacks.** Any non-POSIX tool is picked through a
   probe chain (the reference is `bs_build::sha256`): `sha256sum →
   shasum -a 256 → cksum`. GNU-only tools that need fallbacks:
   `grep -P`, `sed -z`, `stat -c`, `date +%N`, `readlink -f`, `head -c`.
   BSD replacements: `shasum`, `stat -f`, `perl -0` for multiline sed.
3. **No bare GNU-only calls in the kernel.** `core/` must not call
   `grep -P`/`sed -z` directly — only through a module with a fallback
   (e.g. `regex::matches --pcre` already falls back to ERE).
4. **`/proc` and `/sys` are Linux-only.** Check `[[ -d /proc ]]` before
   reading; macOS/FreeBSD do not have them. Hardware data goes through a
   layer like `lib/system/hw` with test hooks.
5. **Version by the capability vector.** The vector:
   `kernel / arch / distro / family (ID_LIKE) / repo / userland / libc /
   bash / tools[]`. The package repository is derived from `ID_LIKE`, not
   from the distro name.
6. **Full description** — see "Portability and capability vector —
   recommendations": [documentation/en/02-core-concepts/portability.md](02-core-concepts/portability.md);
   the rules above are the canon.

## 12. Code in the `bs_` namespace (the kernel, tier `@shell posix`)

This chapter is self-contained: it is how **any kernel function** (`bootstrap/`, `core/`, `install/`, the entry points) is written or converted. A file labelled `# @shell posix` is sourced by bash, zsh, dash, busybox ash, ksh93 and mksh, and **bash does not take part in it**, so it has rules of its own. From sections 1–11 these stay in force: bilingual comments (§3), `bs_guard` (§8.1), strict mode only in entry points (§1.1), `@global` for variables (§4.2) and the capability vector (§11); these do **not** apply: `module::function` in definitions (§2), `local`, arrays and `[[ ]]` (§4.1). The models the chapter cites: [`core/data.sh`](../../core/data.sh) (the data layer), [`core/logger.sh`](../../core/logger.sh), [`core/quiet.sh`](../../core/quiet.sh), [`core/fmt.sh`](../../core/fmt.sh), [`core/calc.sh`](../../core/calc.sh), [`core/utils.sh`](../../core/utils.sh), [`core/errorhandler.sh`](../../core/errorhandler.sh), [`core/prereq.sh`](../../core/prereq.sh).

The step-by-step procedure with its checks is the skill `bs-kernel-code`; what a tier is and who checks it is `bs-shell-abstraction` and `bs-shell-portability`. This chapter holds the **rules and the reasons**. Every reason was verified by running dash, busybox ash, ksh93, mksh, zsh and bash; where a shell is missing on your machine the rule still holds (the reason is in the shell table of `shell-portability.md`).

### 12.1 What a machine checks and what a person checks

| Rule | Who watches |
|---|---|
| The file parses in dash, ash, ksh, mksh, zsh (`X -n`) | `check_posix_tier.sh`, section "parse" |
| No `[[ ]]`, `(( ))`, arrays, `declare`, `${!x}`, `${x^^}`, `=~`, `<( )`, `$'..'`, `source`, the `function` keyword, `local -x`; no `BASH_*`/`ZSH_*`/`FUNCNAME` outside the layer files | `check_posix_tier.sh`, section "syntax" |
| Every function is named `bs_…` (or `__bs_…`) and none is defined with `::` | `check_posix_tier.sh`, section "names" |
| The tier runs in `dash` with no bash in `PATH` | `check_posix_tier.sh`, section "run" |
| `local`, `[[ ]]`, `printf -v`, `echo -e`, `${x^^}`, `$'..'`, arrays | `shellcheck -s sh` (SC3043, SC3010, SC3045, SC3037, SC3059, SC3003, SC3030) |
| Every `posix` file of `core/` has a portable test | `tests/unit/testposixtierunit.sh` |
| The behaviour is the same in all six shells | `tests/unit/test<module>portableunit.sh` |
| **No machine catches:** `for w in $list` (zsh does not split), `cmd \| while read` (lost variables), `$(( ))` on big numbers, `${#s}` on non-ASCII, a mutation inside `$(...)`, `eval` with an unchecked name, clobbered temporaries | a test on "hard" values + a review against this chapter |

The `# @shell posix` label is searched in the **first 14 lines** of the file (`head -n 14` in the checker): do not push it lower.

### 12.2 Names: one namespace `bs_`

The real function is an identifier without `::`. **All** kernel code lives in one namespace: `bs_` + the old name with `::` turned into `_` and the leading `__` of private names removed. If the old name already began with `bs::`, a second `bs_` is not added.

| Old name | Real name | Note |
|---|---|---|
| `utils::has` | `bs_utils_has` | the basic rule |
| `log::info` | `bs_log_info` | |
| `calc::eval` | `bs_calc_eval` | |
| `bs::version::get` | `bs_version_get` | `bs::` is not doubled |
| `bs::guard` | `bs_guard` | |
| `cleanup::add` | `bs_cleanup_add` | the `cleanup` namespace is not a file name |
| `bs::exit` | `bs_exit` | |
| `function_exists` | `bs_function_exists` | had no `::` — just the prefix |
| `log::__timestamp` (private) | `bs_log_timestamp` | no leading `__`, marked `# @private` |
| `utils::__tmp_cleanup` (private) | `bs_utils_tmp_cleanup` | |
| `arr::push` on a real bash array | stays `arr::push` | the data layer's `bs_arr_push` is a **different** function |

Rules:

1. **The module in the name is a namespace, not a file.** `core/quiet.sh` and `core/fmt.sh` define `bs_utils_*`: that is what `utils::has` and `utils::human_size` were called before they were moved out. When choosing a name ask "what was it called before" (or "which namespace does it live in"), not "which file am I in".
2. **Forwards is mechanical, backwards is by the alias table.** `bs_utils_quiet_err` ↔ `utils::quiet_err` can only be restored from the alias block at the end of the file: the module/function border in `bs_a_b_c` cannot be guessed from the name. So the alias block is the one source of truth about old names.
3. **Check for collisions before you pick a name.** `a::b_c` and `a_b::c` both give `bs_a_b_c`. Before a new name: `grep -rn 'bs_module_name' bootstrap core install lib bs boot.sh install.sh`.
4. **Reserved prefixes:** `bs_shell_*` (the layer `bootstrap/shell.sh`), `bs_guard*`, `bs_source_*` (`core/prereq.sh`), `bs_arr_*`, `bs_map_*`, `bs_data_*`, `bs_quote` (`core/data.sh`), `bs_log_*`, `bs_utils_*`, `bs_cleanup_*`, `bs_error_*`, `bs_signal_*`, `bs_deps_*`, `bs_version_*`, `bs_const_*`, `bs_calc_*`. A new module takes a **new** namespace and stays out of others.
5. **Private** names have no leading `__` but carry `# @private` in the doc comment (examples: `bs_log_timestamp`, `bs_data_check`). A double underscore inside a name (`bs_guard__var`, `bs_source__one` in `core/prereq.sh`) passes the "names" check but is historical: new code writes `# @private` and a plain name.
6. **Verbs and order:** `bs_<namespace>_<verb>[_<object>]` (`bs_arr_push`, `bs_log_is_level_allowed`, `bs_cleanup_run_all`). Predicates are `is_`/`has_` and answer with the status, not with output (`bs_utils_has`).

**Aliases.** The old name with `::` is created by `bs_shell_alias real old::name` **at the very end of the file**, one line per function, in the order of definition (for private ones — `log::__timestamp`):

```sh
bs_shell_alias bs_utils_has utils::has
bs_shell_alias bs_log_timestamp log::__timestamp
```

What `bs_shell_alias` (`bootstrap/shell.sh`) does: in bash and zsh it defines a wrapper function `old() { real "$@"; }`, in other shells it does nothing (a `::` in a name is a parse error there). Consequences:

* **POSIX code always calls the real name.** The old name does not exist everywhere; code of the `bash4` tier and `lib/` may write `module::function`, and new code is better off with the real name (one stack frame fewer).
* **Mock by the real name in tests.** If a test redefines `log::error`, a call of `bs_log_error` from POSIX code does not notice; redefine `bs_log_error` and you intercept both paths (the alias calls the real function by name at call time).
* A call through an alias adds one frame to the call stack (`bs_error_throw` in `core/errorhandler.sh` allows for it when it looks up the caller).
* **Do not rename** existing functions or variables: the old names are the public API of `lib/` and user scripts. Retire with `# @deprecated` (example: `bs_utils_guard`).
* If a function had no `::` name before and bash4 code has no need to call it, an alias is optional; when in doubt add it: it costs one line.

### 12.3 The header and the layout of a file

```sh
#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: <что держит файл> / valid POSIX sh: <what holds the file>
# @tier core — <external commands needed>; works everywhere
#
# core/module.sh — одна строка о назначении
# core/module.sh — one line about the purpose
#
# ИМЕНА / NAMES
#   Real functions: bs_module_a, bs_module_b; in bash and zsh also module::a, module::b (the old names).
#   Настоящие функции: bs_module_a, bs_module_b; в bash и zsh — ещё и прежние module::a, module::b.

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

bs_guard MODULE || return 0

# Dependencies / Зависимости
bs_source_relative "const.sh" "data.sh"
```

The order of the parts: header → the "ИМЕНА / NAMES" block → `bs_guard` → dependencies → `@global` variables and constants → private helpers → public API → the alias block → actions at load (registration in the cleanup stack, an initial `bs_log_debug`). What the file **does** when sourced stands at the very end and stays minimal: function definitions have no side effects.

* `#!/bin/sh` and `# shellcheck shell=sh` are for editors and `shellcheck -s sh`; the file is sourced with `.`, it is not executable.
* `@shell posix — <reason> / <reason>` — the reason is bilingual and names **what holds the file**: "case, parameter expansion, mktemp; arrays come from core/data.sh". The label changes only together with the code and the test (`bs-shell-abstraction`).
* `@tier core — …` is the second axis, not to be confused with `@shell`: which *userland* the file needs (`core` | `gnu-linux`; `bs audit` shows the tier next to the GNU-only tools it finds). After the dash list the external commands the functions cannot do without: `builtins only`, `builtins and date`, `date, awk, head`, `builtins, tr and sleep`. The shorter the list, the earlier the module can be loaded.
* The "ИМЕНА / NAMES" block lists the real functions and says the old `::` names are bash/zsh aliases (models: `core/quiet.sh`, `core/logger.sh`). If the file replaces a data structure add a "ДАННЫЕ / DATA" block (`core/errorhandler.sh`: the cleanup stack is the array `bs_cleanup_stack`).
* The kernel load order is set by `bootstrap/init.sh`: `prereq → lang → const → logger → quiet → fmt → data → errorhandler → version → utils → config → deps`. A module may call only what is loaded **before** it (or check `command -v bs_log_error`). A new module is registered in `init.sh` and in the `req` list of `bs doctor` (`bs-new-core-module`).

### 12.4 The source guard

`bs_guard NAME || return 0` is the first executable line after the header (`core/quiet.sh`, `core/logger.sh`). The one exception is `core/prereq.sh`: `bs_guard` is defined in it, so it guards itself by hand.

* `NAME` is a **literal** of `A-Z 0-9 _` (`bs_guard` raises lower case with `tr`, but write upper case). For a new module, the module name in capitals: `DATA`, `QUIET`, `FMT`, `LOGGER`, `UTILS`. The existing `CORE_CALC` and `CORE_DEPS` are not renamed.
* The name must be **unique**: two different parts under one name — the second silently never loads.
* `bs_guard` returns 1 ("already loaded") and 2 ("bad name"). The `|| return 0` idiom hides the 2, so the name is never built from variables.
* The mark `__NAME_SOURCED` is made `readonly`: a second `source` in the **same process** returns at once. For tests it means every probe is a fresh process `env -i … sh probe.sh`, not a second `source`.
* `return 0` is allowed only at the top level of a sourced file. `exit` is never written in a module file.

### 12.5 Sourcing dependencies and paths

Dependencies go through `bs_source_relative "file.sh" …` (paths from the directory of the calling file), with `# @depends core/const, core/logger` in the header (`core/errorhandler.sh`). The directory of a file comes from `BS_CURRENT_FILE`: the loader and `bs_source_relative` itself set it for the time of the `.` and put the old value back (nested sources do not spoil each other). Bash also reads the call stack; in other shells there is **no other source of the directory**.

* Never compute the file's path yourself: no `$0`, no `${BASH_SOURCE[0]}`, no `$(dirname …)`. `$0` belongs to the entry-point prologue only (tag `shell-gate`).
* In probes and tests set `BS_CURRENT_FILE="/absolute/path/file.sh"` before the `.` (as `tests/unit/testdataportableunit.sh` does), otherwise in dash `bs_source_relative` stops with `BS_CURRENT_FILE is not set`.
* An optional dependency is `command -v bs_log_error >/dev/null 2>&1` at the place of use (examples: `bs_utils_error` in `core/utils.sh`, `bs_calc_log` in `core/calc.sh`), not an unconditional `bs_source_relative "logger.sh"` in a low-level module.
* A file sourced by a path from an argument goes through `bs_utils_ensure_source FILE FUNCTION` (it checks that the function appeared); add `# shellcheck disable=SC1090` with the reason.

### 12.6 Variables

**No `local`.** Reasons: it is not POSIX; ksh93 has none at all (`local: not found`); the flag acts on the whole list of names — `local -r a=1 b=2` makes `a` **and** `b` readonly (`b=3` afterwards is an error), and a slip in one name of a long `local` line goes unnoticed. So the temporaries of a function are global and carry a prefix:

* **`__bs_<module>_`**, where `<module>` is a short stable code of the file, unique across `bootstrap/`, `core/`, `install/`: `dat` (data), `log` (logger), `fmt`, `calc`, `ut` (utils), `dp` (deps), `eh` (errorhandler), `sb` (shebang), `gd` (guard), `t` (trampoline). A large function may have a code of its own (`vc`/`vo` in `core/version.sh`; `g`, `gv`, `sr`, `so` in `core/prereq.sh`).
* Check the uniqueness: `grep -rhoE '__bs_[a-z0-9]+_' bootstrap core install bs boot.sh install.sh | sort -u`.
* Public settings are `BS_*` (`BS_LOG_LEVEL`), defaulted with `: "${BS_LOG_LEVEL:=INFO}"` (the user's value is not overwritten); internal ones are `__bs_*` only.
* Initialise every variable you read **at the start of the function**: the value from the previous call is not "empty" (`__bs_dat_acc=''`, `__bs_log_text=''`).

**Global temporaries and nested calls.** This is the main price of giving up `local`:

* A function that calls another function **of the same file** shares the prefix with it; if both write one name, the inner one clobbers the outer. In `core/data.sh` `bs_arr_new` keeps the name in `__bs_dat_nn`, not in `__bs_dat_nm`, because `bs_arr_clear` inside overwrites `__bs_dat_nm`; for the same reason `bs_arr_copy` keeps `__bs_dat_src`/`__bs_dat_dst`. Before you call a helper, check which names it touches.
* Recursion and callbacks clobber variables: `f() { __x=$1; [ "$1" -gt 0 ] && f $(($1 - 1)); echo "$__x"; }` prints `0` at every level (verified). The ways out: do not recurse; keep values in the positional parameters (`bs_source_relative_from` rewrites `"$@"` with `set --`); count the depth (`__bs_dat_depth` in `bs_arr_each`, callback names `__bs_dat_cmd_<depth>`); walk a list with `for x in "$@"` — it is expanded once and does not depend on inner calls.
* "A helper's result is in a variable" is an acceptable contract if it is **named in the doc comment** ("the result is in `__bs_log_out`", "the name is in `__bs_dat_var`"), see §12.8.

**Constants** go through `bs_shell_readonly NAME=value` (`core/const.sh`), never a bare `readonly`. The reason: the loader `load` is a function, and in zsh `readonly X=1` inside a sourced file makes `X` **local** to that function (verified: after `load` the variable is gone); `bs_shell_readonly` runs `readonly -g` in zsh. A constant that has a fallback (`E_ERROR`) is read as `"${E_ERROR:-1}"`: the module may be sourced without `core/const.sh`.

**Module flags** are declared with `# @global` (§4.2) and a category; for "read by tests and other modules" add `# shellcheck disable=SC2034  # reason / причина`.

### 12.7 Constructs: allowed and forbidden

Before you write a helper by hand look at the base modules: `bs_var_*` (variables by name, checked names), `bs_str_*` (case, trim, literal replace, join), `bs_num_*` (exact integers), `bs_msg_*` (messages with a logger-less fallback), `bs_arr_*`/`bs_map_*` (data). Duplicating them is how the kernel grew five copies of the same name check.

Allowed: `case`, `[ ]`/`test`, the expansions `${v#p}`, `${v%p}`, `${v:-d}`, `${v-}`, `${v:?}`, `$(( ))` on small integers, `$( )`, `command -v`, `printf`, `while read -r`, `for x in list`, `. file`, heredocs, `trap` (inside a function), `eval` (see §12.10).

| Do not write | Write | Why (verified) |
|---|---|---|
| `[[ … ]]` | `[ … ]`, patterns with `case` | `[[` is not POSIX; "not found" in dash. Compound conditions are `[ a ] && [ b ]`, not `-a`/`-o` (ambiguous) |
| `(( … ))`, `let` | `$(( ))` inside `[ ]` or an assignment | not POSIX |
| Arrays, `declare -A`, `local -n` | `bs_arr_*`, `bs_map_*` (§12.11) | dash and ash have no arrays at all, mksh has no associative ones, and ksh93 declares them with  and zsh arrays count from 1 |
| `local`, `local -r a b` | global `__bs_<module>_…` | §12.6 |
| `${v^^}`, `${v,,}` | `tr '[:lower:]' '[:upper:]'` or `case` with `[Tt][Rr]…` (`bs_log_level_to_number`) | "Bad substitution" in dash, mksh, ksh93 |
| `${v//a/b}`, `${v:3:2}` | a `case … ${v%%"$a"*}` loop (`bs_log_replace_all`), `cut` | the substitution does not exist in dash |
| `printf -v name …` | `name=$(printf …)` | dash: "Illegal option -v"; mksh prints "-v" as text |
| `$'\033'`, `$'\n'` | `__bs_esc=$(printf '\033')` once at load | dash does not expand `$'..'` (it prints `$a<TAB>b`) |
| `echo -e`, `echo "$data"` | `printf '%s\n' "$data"` | dash prints `-e` and interprets `\t` itself; data like `-n` is taken as a flag |
| `source`, `function f {`, `==` in `[ ]`, `&>`, `\|&`, `<<<` | `.`, `f() {`, `=`, `>f 2>&1`, `2>&1 \|`, a heredoc / `printf \|` | not POSIX |
| `[[ $x =~ … ]]`, `BASH_REMATCH` | `case "$x" in pattern)` and expansions (`core/version.sh`) | not in POSIX |
| `${!name}`, `declare -f`, `type -t` | `eval` with a checked name; `command -v` (`bs_function_exists`) | §12.10 |
| `read -a`, `-p`, `-n`, `-d` | `read -r`; a prompt only if `[ -t 0 ]` (`core/calc.sh`) | the flags are not POSIX; without `-r` `read` eats backslashes |
| `$RANDOM`, `$SECONDS`, `EPOCHREALTIME`, `BASH_*` | `date`, `awk`; optional ones with a fallback (`bs_utils_now_ms` in `core/fmt.sh`) | not everywhere |
| `$(( ))` for big numbers | `awk`, `dc` | **`$(( ))` is 32-bit in mksh:** `3*1073741824` gives `-1073741824` (this is how 3 GiB overflowed in `core/fmt.sh`) |
| `$((08))`, `$((x))` from user input | strip leading zeros and check `case "$x" in ''\|*[!0-9]*)` (`bs_error_retry`) | `08` is an octal error in dash and bash but `8` in mksh |
| `${#s}` for width/cut of non-ASCII | treat it as "characters or bytes, depending on the shell" and write a test | dash and mksh count bytes, bash/zsh/ksh count characters by locale (the `bs_log_header` frame) |
| `for w in $list`, `set -- $string` | a loop over `${s%% *}` / `${s#* }`; join in a loop with an explicit separator | **zsh does not split a variable's value into words** (`set -- $v` gives `$#` = 1); and in BS scripts `IFS` is newline and tab (`bs_shell_strict`), so `"$*"` joins the words with a **newline**, not a space |
| `cmd \| while read x; do … done` writing variables | `while read … done < file` or a heredoc | in bash, dash, ash, mksh the pipeline runs in a subshell and `n` stays 0, in zsh and ksh93 it does not (`n=2`): the behaviour differs |
| An unquoted variable | `"$v"`, `"$@"` | globbing and splitting; the only exception is a deliberate `eval "$(…)"` |
| a bare `\|` in a `${x%%a\|b}` pattern | escape it: `${x%%\|*}`, or use `case` | in ksh93 a bare `\|` in `${x%%\|*}` is an alternation, not a character (found by `testdepsportableunit.sh`) |
| `while … done < <(cmd)`, `mapfile < <(cmd)` | `x=$(cmd)` and a `while read … done <<EOF` loop with `$x` in the heredoc | process substitution is not POSIX; a heredoc loop runs in the current shell, so variables survive |
| `. file arg1 arg2`, `source file "$@"` | call a function from the file: `. file; bs_function "$@"` | dash does not pass arguments to a sourced file (the positional parameters stay the caller's) |
| `case "$x" in "$prefix"*)` with a possibly empty `$prefix` | test `[ -n "$prefix" ]` before the `case` | an empty pattern `""*` matches anything: in `bs_str_ltrim` an empty CR (mksh has no built-in `printf`, the binary was missing) looped the parse forever |
| relying on a built-in `printf` | assume it is an external command in mksh (R59) | mksh has no built-in `printf`: without the binary in `PATH` every call dies "not found" |
| `exit` in a function | `return N`; `exit` only in `bs_exit`, entry points, `trampoline.sh` | `exit` in a subshell or in someone else's function kills the wrong thing |
| `trap` when a file loads | `trap` inside a function (`bs_errorhandler_setup_trap`), cleanup through `bs_cleanup_add` | `trap` **replaces** the previous handler, it does not add to it |
| `cd` in a function | `( cd -- "$d" && … )` or `$(cd -- "$d" && pwd -P)` | `cd` changes the caller's directory |
| A last line `[ … ] && command` | `if …; then …; fi` or a closing `return 0` | under `set -e` (the entry points enable it) such a function returns 1 and **ends the caller**: `f(){ [ -n "$1" ] && echo x; }; f ""` kills the script |

The code must work **both with `set -eu` and without it**: every optional parameter is `${1-}`, `${VAR:-}`; an expected non-zero status is `|| :` or an `if`. Normalise the statuses of external commands: `command -v` for a missing command returns 127 in dash and ash and 1 elsewhere, so `bs_utils_has` and `bs_function_exists` do `|| return 1`.

### 12.8 Returning values

| What you need | How | Model |
|---|---|---|
| A yes/no answer | the status only, no output | `bs_utils_has`, `bs_arr_contains` |
| One value | `stdout`, a line = `printf '%s\n'`; status 1 means "no such" | `bs_arr_get`, `bs_map_get` |
| A value on a hot path (the loader, `bs_guard`, `bs_map_has`) | an **output variable** — a `$(...)` subshell costs a fork | `bs_guard__var` → `__bs_g_var`; `bs_log_replace_all` → `__bs_log_out` |
| A value if the caller wants it | an optional "variable name" parameter; empty means `stdout` | `bs_arr_pop name [variable]` via `bs_data_ret` |
| Many values | a data-layer array whose name the caller passes | `bs_utils_split out_array string delimiters` |

* **Functions that change state and return a value (`bs_arr_pop`, `bs_arr_shift`) must not be called as `$(...)`:** the subshell changes its own copy and the real state stays (verified: `v=$(bs_arr_pop a)` returned `z` but the length of `a` stayed 3; `bs_arr_pop a v` made it 2). The doc comment of such a function says "do NOT call it as `$(...)`, take the result into a variable".
* `$(...)` cuts **trailing newlines**: a value that may end with one cannot go back through `stdout` unharmed — only through a variable.
* The name of an output variable is **checked before `eval`** (`bs_data_ret`: `case "$1" in [!A-Za-z_]*|*[!A-Za-z0-9_]*) … return 2`).
* **A function whose `stdout` is the result prints nothing extra.** `bs_log_info`, `bs_log_debug`, `bs_log_trace`, `bs_log_success` write to stdout (warning and error go to stderr), so such a `bs_log_*` inside `$(...)` spoils the result. A "returning" function reports through `bs_log_warn`/`bs_log_error` or to stderr.
* Output temporaries are documented like parameters (§12.13).

**Return codes.** `0` — success; `1` — "no / false / error" (`${E_ERROR:-1}`); `2` — a wrong call, a bad name, an invalid argument (`${E_INVALID:-2}`); the others are `LIB_ERROR_*` from `core/const.sh`. The status of a function is the status of its last command: end with an explicit `return` if the last command may return the wrong thing.

### 12.9 Errors, exit and messages

* Functions return a code and never call `exit`. Leaving is `bs_exit [code|NAME]` (it runs the cleanup) or `bs_error_exit MESSAGE [code]`; a code name (`E_<NAME>`, `LIB_ERROR_<NAME>`) is checked with `case … *[!A-Z0-9_]*` **before** `eval` (`bs_exit` in `core/errorhandler.sh`).
* `${1:?message}` is the BS idiom for a **mandatory** argument (a programmer error). It ends the script in bash, dash, ash, ksh93 and zsh, but **not in mksh**: there it prints the message and the script goes on (verified). So it is a diagnostic, not flow control. For input that can be empty through the user's fault write `[ -n "${1-}" ] || return 2`.
* Strict mode and `IFS` are enabled by the entry points through `bs_shell_strict` only. A module does not enable strict mode and **does not rely on it or on its absence** (§12.7).
* Messages: once `core/logger.sh` is loaded, `bs_log_error "…"`; in modules that load **before** the logger or must work without it (`quiet`, `data`, `fmt`, `prereq`), and in anything optional, `printf '%s\n' "…" >&2` (models: `bs_data_check`, `bs_utils_error`, `bs_calc_log`). The format is `function_name: what is wrong: value` (`bs_data: invalid name: …`).
* "Nothing to do" is not an `ERROR`: it is `return 0` (see the skill `bs-cli-noop-output`).
* Cleanup is registered with `bs_cleanup_add function` (a stack, the last added runs first), not with a `trap` on the spot. Guard the registration at load: `if command -v bs_cleanup_add >/dev/null 2>&1; then …` (the end of `core/utils.sh`).

### 12.10 `eval` safety

The layer needs `eval` for indirect names (there is no `${!x}` and no namerefs) — and it is the most dangerous place of the kernel. Exactly three cases are allowed:

1. **Reading/writing a variable whose name is built from checked parts:** `eval "__bs_dat_n=\${__bs_dat_a_${1}__n:-0}"`.
2. **An assignment by a name the caller passed:** `eval "$1=\${__bs_dat_out}"` — after a `case` check (`bs_data_ret`).
3. **Creating an alias** (`bs_shell_alias`): `eval "$2() { $1 \"\$@\"; }"` — only literals from the file itself.

Rules:

* **The name is checked before any `eval`, and refused with code 2.** The model is `bs_data_check`: `''|[!A-Za-z]*|*[!A-Za-z0-9_]*|*__*|*_` (starts with a letter, only letters/digits/`_`, no `__`, no trailing `_` — so it cannot meet the layer's internal names).
* **Only the checked name is spliced into the `eval` string; values travel by reference** `\${variable}` (expanded a second time inside `eval`), not as pasted text: `eval "…=\${__bs_dat_v}"`, not `eval "…=$value"`.
* If a value really must be pasted into code, pass it through `bs_quote` (single quotes, `'\''` inside); `eval "$(bs_arr_to_args name)"` is safe exactly because every element went through `bs_quote`.
* **Never `eval` text from a user, a file, the network or the command line.** Use an allow-list in `case` (`bs_exit` takes a code name only of `A-Z0-9_`).
* Call a function by name as `"$name" argument`, not through `eval`; check the name with `command -v` (`bs_signal_on`); for `trap "$handler" SIGNAL` add `# shellcheck disable=SC2064  # reason`.
* Escape `$` inside an `eval` string (`\$`) where it must expand **after** the name is built, and do not escape it where the name is built now: a mistake here is a silent substitution of nothing.
* A test for `eval` is mandatory: feed a "name" such as `a;touch /tmp/x` and `$(id)` and check code 2 and no side effects (`tests/unit/testdataportableunit.sh`, `bs_arr_push "bad name"`).

### 12.11 The data layer `core/data.sh`

POSIX code gets arrays and maps only from `bs_arr_*`, `bs_map_*`, `bs_quote`; `declare -a`, `declare -A`, `local -n` are forbidden. A structure name is `[A-Za-z][A-Za-z0-9_]*`, with no `__` and no trailing `_`; your own structures are named `bs_<module>_<what>` (`bs_cleanup_stack`, `bs_error_handlers`). Other modules neither read nor write the internal `__bs_dat_*` variables.

* Indexes start at 0, a negative one counts from the end; status 1 means "no such", 2 a bad name.
* To walk: `eval "$(bs_arr_to_args name)"`, then `for x in "$@"`. This **overwrites the positional parameters of the function** — do it in a function that no longer needs them (like `bs_arr_each`) or save what you need into variables.
* To drain: `while bs_arr_pop name __bs_eh_fn; do …` (`bs_cleanup_run_all`).
* The callback of `bs_arr_each name function` / `bs_map_each name function` is a **function name**, not a command line; nesting is counted.
* Do not call `bs_arr_pop`, `bs_arr_shift` as `$(...)` (§12.8).
* The price: every access is an `eval`, `bs_arr_shift` and `bs_arr_remove_at` are O(n). For hot loops keep the data in the positional parameters or a delimited string.
* A map key may hold anything (it is encoded as `_<hex>_`); the insertion order is kept; a value with a newline is read whole by `bs_map_get` to stdout, but `bs_map_keys` prints keys one per line — for keys with a newline use `bs_map_keys_to`.
* The layer cannot be called from files that load **before** `core/data.sh`.

### 12.12 Logging

After `core/logger.sh` a module reports only through `bs_log_trace|debug|info|success|warn|error|fatal`; `echo`/`printf` for user messages only where there is no logger yet (§12.9). Colour, format (`text|structured|json`), level (`BS_LOG_LEVEL`) and timestamp are set by the environment (`BS_LOG_COLOR`, `BS_LOG_FORMAT`, `BS_LOG_TIMESTAMP`) and `NO_COLOR`; a module neither reads nor changes them. The words of a message are joined with a space whatever the caller's `IFS` (`bs_log_format_message`); pass them as separate arguments or one string, do not build `"$*"`. `bs_log_fatal` returns `${E_ERROR:-1}` and does **not end** the script. A debug message at load is `bs_log_debug "…" 2>/dev/null || true`: the logger may be off.

### 12.13 Doc comments

Bilingual comments are mandatory for every public function and for a private one with a non-trivial contract. Two forms are allowed, keep to the form of the file:

```sh
# @description Проверить имя массива или словаря / Check an array or map name
# @param $1 name / имя
bs_data_check() {
```

and the two-line form (`core/quiet.sh`, `core/fmt.sh`):

```sh
# @description Check if command exists in PATH.
# @description Проверить наличие команды в PATH.
# @param $1 {string} Имя команды
# @returns 0  команда доступна
# @returns 1  команда не найдена
```

Tags: `@description`, `@param $N name`, `@returns`, `@stdout`, `@private`, `@example`, `@function` (when the documented name differs from the real one), `@deprecated`, `@global`. Rules: the description says **what the function guarantees**, it does not retell the code; every positional parameter is named; **output variables are named** ("the result is in `__bs_log_out`"); the split between codes `1` and `2` is stated; a mutating function says "do NOT call it as `$(...)`"; for mandatory parameters `${1:?}` and the word "required". Every `# shellcheck disable=…` carries a reason in two languages: `# shellcheck disable=SC2154  # присваивается через eval / assigned through eval`. Inline comments in code are "по-русски / in English", short.

### 12.14 Tests and checks

Every `posix` file of `core/` has `tests/unit/test<module>portableunit.sh`: it sources the file in every installed shell (`testframework::posix_shells`) under `env -i`, compares the answers on "hard" values (spaces, quotes, `*`, `$`, a backslash, a newline, Cyrillic, an empty string, `-n`), checks the `::` aliases in bash and zsh and honestly reports "not verified" for missing shells. Models: `testquietportableunit.sh` (minimal), `testdataportableunit.sh` (data structures), `testloggerportableunit.sh` (output). Before a commit:

```bash
for sh in dash ksh mksh zsh bash; do "$sh" -n core/module.sh; done
busybox ash -n core/module.sh
shellcheck -s sh core/module.sh
bash .agents/skills/bs-shell-abstraction/scripts/check_posix_tier.sh
bash tests/validatesyntax.sh && bash tests/validateshellcheck.sh && bash tests/validatedocscode.sh
```

### 12.15 Review checklist

- [ ] The name is `bs_<namespace>_<name>`, no collisions; the alias block is at the end; the old name is untouched
- [ ] Header: `#!/bin/sh`, `shellcheck shell=sh`, `@shell posix` with a reason (within the first 14 lines), `@tier core`
- [ ] `bs_guard NAME || return 0`, dependencies through `bs_source_relative`, no computed path
- [ ] No `local`, `[[ ]]`, `(( ))`, arrays, `printf -v`, `$'..'`, `echo -e`, `${x^^}`
- [ ] Temporaries are `__bs_<module>_`, initialised, not clobbered by a nested call; constants through `bs_shell_readonly`
- [ ] The result is a status / stdout / an output variable; a mutating function is not meant for `$(...)`
- [ ] Every `eval` has a checked name and values by reference; there is a test for a "bad name"
- [ ] Works with and without `set -eu`; no `[ ] && cmd` as the last line; no `exit`
- [ ] Messages go through `bs_log_*` (or stderr before the logger); bilingual doc comments
- [ ] The `portableunit` test in every shell, a differential run against the old implementation, `check_posix_tier.sh` OK
