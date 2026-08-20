[↑ Documentation index](../README.md)

# Core API Reference

Reference for the core modules: `core/logger.sh`, `core/errorhandler.sh`, `core/const.sh`, `core/version.sh`, `core/prereq.sh`.
For `core/args.sh` and `core/utils.sh` see the [Core utils module](../03-modules/core-utils.md).
`core/guard.sh` is kept as a backward-compatible wrapper around `core/prereq.sh`.

## Loading

In a script with the `#!/usr/bin/env bs` shebang, or after `source bootstrap/init.sh`:

```bash
#!/usr/bin/env bs
load "core/logger"       # logging
load "core/errorhandler" # error handling and cleanup stack
load "core/const"        # return codes and constants
load "core/version"      # version information
```

`load` resolves paths relative to `BS_ROOT` without the `.sh` extension and prevents duplicate loading.

---

## Source Guard — `core/prereq.sh`

Core primitives available a priori: double-source protection (`bs::guard`,
`bs::guard_loaded`) and relative sourcing (`bs::source_relative`). Autoloaded
first by `bootstrap/init.sh` — modules never source it manually.

#### `bs::guard <name>`
- Parameters: `$1` — module name (without `__` / `_SOURCED`, case-insensitive)
- Returns: 0 on first load (the `__NAME_SOURCED` mark is set), 1 if the module was already loaded
- Example: `bs::guard "my_module" || return 0`

#### `bs::guard_loaded <name>`
- Parameters: `$1` — module name
- Returns: 0 if the module is loaded, 1 otherwise
- Example: `bs::guard_loaded "logger" && echo "logger is here"`

Module template (`core/prereq.sh` is autoloaded first by `bootstrap/init.sh`,
no manual sourcing needed):

```bash
bs::guard "MY_MODULE" || return 0
bs::source_relative "../core/logger.sh" "../core/utils.sh"  # dependencies relative to the module file
```

#### `bs::source_relative <path>...`
- Parameters: `$@` — relative file paths from the caller module's directory
- Purpose: replaces the verbose idiom `source "$(dirname -- "${BASH_SOURCE[0]}")/..."`
- Example: `bs::source_relative "const.sh" "logger.sh"`

#### `bs::script_dir [index]`
- Parameters: `$1` — optional `BASH_SOURCE` index (default 1 = immediate caller)
- Returns: 0 on success, 1 if the directory cannot be resolved
- Stdout: absolute physical path (`pwd -P`) of the caller's directory
- Purpose: replaces the boilerplate `"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`.
  Available only after `core/prereq` is loaded — entry-point headers that run
  before `bootstrap/init.sh` must keep the raw idiom.
- Example: `readonly SCRIPT_DIR="$(bs::script_dir)"`

---

## Language primitives — `core/lang.sh`

The "language kernel": introspection, types, strings and collections over
pure Bash 4+ built-ins (no external commands). Autoloaded right after
`core/prereq`.

### Introspection

#### `bs::func_name [depth]`
- Stdout: name of the calling function (`FUNCNAME`), "main" at script top level; `$1` — stack depth (default 1)
- Replaces the `local func_name="my::func"` boilerplate

#### `bs::call_stack`
- Stdout: one frame per line: `function (file:line)`, caller first

#### `bs::is_function <name>` / `bs::is_defined <name>`
- Predicates: function exists (`declare -F`) / variable is set (`[[ -v ]]`)

#### `bs::type_of <name>`
- Stdout: `function | map | array | integer | string | undefined`; returns 1 when undefined

### Strings

`str::upper`, `str::lower`, `str::trim`, `str::replace <s> <old> <new>` print the
result; `str::contains`, `str::starts_with`, `str::ends_with` are predicates
(0/1). Pure parameter expansion — no `sed`/`awk` forks.

### Collections

- `arr::contains <array> <element>` — predicate, exact match
- `arr::push <array> <element>` — append in place (nameref)
- `arr::length <array>` — element count
- `arr::join <array> <sep>` — joins with a multi-char separator (unlike `"${a[*]}"` with IFS)
- `arr::from_lines <array>` — reads stdin lines into an array via `mapfile`; use `arr::from_lines arr < file` or `< <(cmd)` (a pipeline would run in a subshell and lose the array)
- `map::has <map> <key>` — predicate

All take the variable NAME (not the value), e.g. `arr::join my_tools ", "`.

### `is::` — predicates for humans

Friendly replacements for `[[ ... ]]` test flags — no need to remember that
`-n` means "non-empty" and `-f` means "regular file":

| Bare bash | BS |
|---|---|
| `[[ -z "$s" ]]` | `is::empty "$s"` |
| `[[ -n "$s" ]]` | `is::not_empty "$s"` |
| `[[ -e/-f/-d/-L "$p" ]]` | `is::exists` / `is::file` / `is::dir` / `is::symlink "$p"` |
| `[[ -s "$p" ]]` | `is::file_not_empty "$p"` |
| `[[ -x/-r/-w "$p" ]]` | `is::executable` / `is::readable` / `is::writable "$p"` |
| `[[ "$s" =~ ^[0-9]+$ ]]` | `is::number "$s"` |
| `command -v c >/dev/null 2>&1` | `is::command c` |
| `declare -F f >/dev/null 2>&1` | `is::function f` |

Negation reads naturally: `if ! is::file "${path}"; then`.

---

## Logging — `core/logger.sh`

All `log::*` functions take the message as `"$@"` (arguments are joined with spaces). A message is printed only if its level is not below `BS_LOG_LEVEL`. `log::error` and `log::fatal` write to stderr, the rest to stdout.

Level weights: `TRACE`=0, `DEBUG`=10, `INFO`=20, `SUCCESS`=25, `WARN`=30, `ERROR`=40, `FATAL`=50, `NONE`=1000 (mutes everything).

### Level functions

#### `log::trace <message...>`
- Parameters: `$@` — message text
- Returns: 0
- Example: `log::trace "Entering function with args: $*"`

#### `log::debug <message...>`
- Parameters: `$@` — message text
- Returns: 0
- Example: `log::debug "Processing item: $item"`

#### `log::info <message...>`
- Parameters: `$@` — message text
- Returns: 0
- Example: `log::info "Starting process with PID: $$"`

#### `log::success <message...>`
- Parameters: `$@` — message text
- Returns: 0
- Example: `log::success "Operation completed successfully"`

#### `log::warn <message...>`
- Parameters: `$@` — message text
- Returns: 0
- Example: `log::warn "Configuration file not found, using defaults"`

#### `log::error <message...>`
- Parameters: `$@` — message text
- Returns: 0; output goes to stderr
- Example: `log::error "Failed to connect to database: $error"`

#### `log::fatal <message...>`
- Parameters: `$@` — message text
- Returns: `E_ERROR` (or 1 if `core/const.sh` is not loaded); does **not** exit — the caller decides
- Example: `log::fatal "Critical error, cannot continue" || bs::exit "${E_ERROR}"` (or simply `error::exit "Critical error, cannot continue"`)

#### `log::print <message...>`
- Alias for `log::info` (backward compatibility)
- Parameters: `$@` — message text
- Returns: 0
- Example: `log::print "Simple message"`

### Formatting helpers

#### `log::header <text> [char]`
- Parameters: `$1` — header text (required); `$2` — underline character (optional, default `=`)
- Returns: 0
- Example: `log::header "Starting deployment"`

#### `log::list <item...>`
- Parameters: `$@` — list items, each printed with a bullet (`•` with color, `*` without)
- Returns: 0
- Example: `log::list "Item 1" "Item 2" "Item 3"`

#### `log::table <row...>`
- Parameters: `$@` — rows as `"col1|col2|col3"` strings, printed indented
- Returns: 0
- Example: `log::table "Name|Value" "Host|localhost" "Port|8080"`

#### `log::progress <current> <max> [width]`
- Parameters: `$1` — current value (required); `$2` — maximum value (required); `$3` — bar width (optional, default 50)
- Returns: 0; redraws the bar in place (`\r`), prints a newline when `current == max`
- Example: `log::progress 25 100`

#### `log::clear_line`
- Clears the current terminal line (`\r\033[K`)
- Returns: 0
- Example: `log::clear_line`

### Configuration variables

Set before loading the module (or export in the environment); defaults are applied with `:=`:

| Variable | Values | Default | Description |
|---|---|---|---|
| `BS_LOG_LEVEL` | `TRACE`, `DEBUG`, `INFO`, `SUCCESS`, `WARN`, `ERROR`, `FATAL`, `NONE` | `INFO` | Minimum level to print |
| `BS_LOG_COLOR` | `auto`, `always`, `never` | `auto` | Colors; `auto` = only when stdout is a TTY |
| `BS_LOG_FORMAT` | `text`, `json`, `structured` | `text` | Output format |
| `BS_LOG_TIMESTAMP` | `true`, `false` | `true` | Prepend `YYYY-MM-DD HH:MM:SS` timestamp |

### Output formats

- `text` — `[2026-07-29 19:24:13] INFO  message`, with ANSI colors when enabled (ERROR/FATAL in bold).
- `json` — `{"timestamp":"...","level":"INFO","message":"..."}` (message is JSON-escaped; `timestamp` key omitted when `BS_LOG_TIMESTAMP=false`).
- `structured` — `[2026-07-29 19:24:13] INFO  | message`, no colors.

---

## Error handling — `core/errorhandler.sh`

### Cleanup stack

Any module can register a cleanup function; the stack runs in LIFO order when the script exits.

#### `cleanup::add <function>`
- Parameters: `$1` — name of the cleanup function
- Returns: 0; 2 if no function name given
- Example: `cleanup::add my_cleanup_function`

#### `errorhandler::setup_trap`
- Installs the `EXIT` trap that runs the cleanup stack (`BS::__on_exit`). Entry points only.
- Returns: 0
- Example: `errorhandler::setup_trap`

#### `bs::exit [code]`
- Parameters: `$1` — exit code (optional, default 0)
- Does not return: runs the whole cleanup stack, then `exit`
- Example: `bs::exit 1`

### Reporting errors

#### `errorhandler::throw <func> <message> [code]`
- Parameters: `$1` — function name where the error occurred; `$2` — message; `$3` — error code (optional, default `E_ERROR`)
- Returns: the error code; logs via `log::error` if the logger is loaded, otherwise prints to stderr
- Example: `errorhandler::throw "my::func" "Something failed" "${LIB_ERROR_FILE_NOT_FOUND}"`

#### `error::throw <message> [code]`
- Like `errorhandler::throw`, but the caller's function name is auto-detected via `FUNCNAME` — no `local func_name="..."` boilerplate, and the name stays correct after renames
- Example: `error::throw "Something failed" "${LIB_ERROR_FILE_NOT_FOUND}"`

#### `signal::on <signal> <handler>` / `signal::ignore <signal>` / `signal::reset <signal>`
- Linguistic wrappers over `trap`: subscribe a function to a signal, ignore a signal, restore the default disposition. Names with or without `SIG` are accepted
- Returns: `E_INVALID` on unknown signal, `E_ERROR` if the handler function does not exist
- Example: `signal::on SIGINT my::cleanup`

#### `error::log <message>`
- Parameters: `$1` — message
- Returns: 0; logs the error without exiting
- Example: `error::log "Non-fatal error occurred"`

#### `error::exit <message> [code]`
- Parameters: `$1` — message; `$2` — exit code (optional, default 1)
- Does not return: logs the message and calls `bs::exit`
- Example: `error::exit "Something went wrong" 2`

#### `error::exit_with_backtrace <message> [code]`
- Parameters: `$1` — message; `$2` — exit code (optional, default 1)
- Does not return: logs the message plus a `BASH_SOURCE`/`FUNCNAME` backtrace, then exits via `bs::exit`
- Example: `error::exit_with_backtrace "Critical error occurred" 3`

#### `error::panic <message>`
- Parameters: `$1` — critical error message
- Does not return: logs `PANIC`, runs the cleanup stack, `exit 1`
- Example: `error::panic "Critical system failure"`

### Custom handlers

#### `error::handle <code> <message>`
- Parameters: `$1` — error code; `$2` — message
- Returns: handler's return code; if a function `error::handler::<code>` exists it is called with the message, otherwise falls back to `error::exit`
- Example: `error::handle 127 "Command not found"`

#### `error::set_handler <code> <function>`
- Parameters: `$1` — error code; `$2` — handler function name (must already exist)
- Returns: 0; 1 if the handler function does not exist
- Example: `error::set_handler 127 my_not_found_handler`

#### `error::reset_handler <code>`
- Parameters: `$1` — error code
- Returns: 0; removes `error::handler::<code>`
- Example: `error::reset_handler 127`

#### `function_exists <name>`
- Parameters: `$1` — function name
- Returns: 0 if the function exists, 1 otherwise
- Example: `function_exists "my::func" && my::func`

#### `error::handler::command_not_found <cmd>`
- Built-in handler: logs the missing command, suggests a package via `apt-cache`/`dnf` when available, then `error::exit ... 127`
- Example: `error::handler::command_not_found "mycommand"`

### Execution helpers

#### `error::try <cmd> [args...]`
- Parameters: `$@` — command to execute
- Returns: 0 on success; on failure logs `Command failed: ...` and returns the command's code
- Example: `error::try command_that_might_fail`

#### `error::try_with_fallback <primary> <fallback>`
- Parameters: `$1` — primary command string (run via `eval`); `$2` — fallback command string
- Returns: the fallback's code if the primary failed, otherwise 0
- Example: `error::try_with_fallback "critical_command" "fallback_command"`

#### `error::retry <max> <cmd> [args...]`
- Parameters: `$1` — max attempts; `$@` (from `$2`) — command to execute; `sleep 1` between attempts
- Returns: 0 on first success; otherwise the last failure code after logging an error
- Example: `error::retry 3 command_that_might_fail`

#### `error::ignore <cmd> [args...]`
- Parameters: `$@` — command to execute with stderr discarded and failure ignored
- Returns: 0 always (`"$@" 2>/dev/null || true`); compare `utils::ignore`, which also drops stdout
- Example: `error::ignore command_that_might_fail`

#### `error::with_timeout <seconds> <cmd> [args...]`
- Parameters: `$1` — timeout in seconds; `$@` (from `$2`) — command to execute
- Returns: the command's code (124 on timeout, per `timeout(1)`); runs without a timeout (with a warning) if `timeout` is not available
- Example: `error::with_timeout 10 long_running_command`

Note: internally this checks `command -v timeout >/dev/null 2>&1`; in your own code prefer `utils::has timeout` from `core/utils.sh`.

#### `error::conditional <condition> <message> [code]`
- Parameters: `$1` — condition string (run via `eval`); `$2` — message; `$3` — exit code (optional, default 1)
- Returns: 0 if the condition is false; otherwise exits via `error::exit`
- Example: `error::conditional "[[ -z ${config} ]]" "Config is empty" 2`

#### `error::conditional_warning <condition> <message>`
- Parameters: `$1` — condition string (run via `eval`); `$2` — warning message
- Returns: 0; logs a warning if the condition is true
- Example: `error::conditional_warning "check_deprecated_feature" "Feature is deprecated"`

---

## Constants — `core/const.sh`

### Return codes

| Constant | Value | Meaning |
|---|---|---|
| `E_SUCCESS` | 0 | Successful execution |
| `E_ERROR` | 1 | General error |
| `E_INVALID` | 2 | Invalid arguments or parameters |
| `LIB_ERROR_INVALID_ARGS` | 3 | Invalid function arguments |
| `LIB_ERROR_INVALID_INPUT` | 4 | Invalid input data format |
| `LIB_ERROR_FILE_NOT_FOUND` | 5 | File not found |
| `LIB_ERROR_PERMISSION_DENIED` | 6 | Permission denied |
| `LIB_ERROR_DEPENDENCY` | 7 | Dependency error |
| `LIB_ERROR_UNSUPPORTED_OS` | 8 | Unsupported operating system |
| `LIB_ERROR_TIMEOUT` | 9 | Operation timeout |
| `LIB_ERROR_CONFLICT` | 10 | Resource conflict |
| `LIB_ERROR_FILE_OPERATION` | 100 | File operation error |
| `LIB_ERROR_DEPENDENCY_MISSING` | 101 | Dependency missing |
| `LIB_ERROR_PLATFORM_UNSUPPORTED` | 102 | Platform unsupported |

### Global variables

- `FRAMEWORK_DEBUG=false` — debug mode flag.
- `FRAMEWORK_DRY_RUN=false` — dry-run flag (no actions executed).
- `BS_VERSION` — framework version; owned by the `bs` script (readonly), set here only if empty.

### Constant groups

- Colors: `COLOR_RESET`, `COLOR_RED`, `COLOR_GREEN`, `COLOR_YELLOW`, `COLOR_BLUE`, `COLOR_PURPLE`, `COLOR_CYAN`, `COLOR_WHITE`, `COLOR_BLACK`, plus `COLOR_BRIGHT_*` variants (ANSI escape sequences).
- Formatting: `SPINNER_CHARS='/-\|'`, `PROGRESS_BLOCK='█'`, `PROGRESS_EMPTY=' '`.
- Paths: `SYS_ETC`, `SYS_VAR`, `SYS_TMP`, `SYS_USR_LOCAL`, `SYS_HOME`.
- Validation: `SUPPORTED_DISTROS=("alma" "centos" "rhel" "fedora" "debian" "ubuntu")`, `FILENAME_ALLOWED_CHARS='[a-zA-Z0-9._-]'`.

### Functions

#### `const::is_valid_error_code <code>`
- Parameters: `$1` — error code
- Returns: `E_SUCCESS` if the code is in 0–10, `E_ERROR` otherwise
- Example: `const::is_valid_error_code 5`

#### `const::error_description <code>`
- Parameters: `$1` — error code
- Returns: 0; prints a bilingual description (codes 0–10, otherwise "Unknown error")
- Example: `const::error_description "${LIB_ERROR_FILE_NOT_FOUND}"`

#### `const::version`
- Returns: 0; prints `BS_VERSION`
- Example: `const::version`

---

## Version — `core/version.sh`

- `BS_VERSION` — current version (e.g. `0.3.0`); exported only if empty, the `bs` script owns the readonly variable.
- `BS_NAME="BS (Bash Open Source Architecture) BOSA Framework"`.

#### `bs::version::print`
- Prints `"${BS_NAME} ${BS_VERSION}"`
- Returns: 0
- Example: `bs::version::print`

#### `bs::version::get`
- Prints the version string
- Returns: 0
- Example: `version=$(bs::version::get)`

#### `bs::version::compare <ver1> <ver2>`
- Parameters: `$1`, `$2` — dotted version strings, compared numerically per part
- Returns: 0 if equal, 1 if `ver1 > ver2`, 2 if `ver1 < ver2`
- Example: `bs::version::compare "0.1.0" "0.2.0"; [[ $? -eq 2 ]] && echo "older"`

---

## Utilities — `core/utils.sh`

`core/utils.sh` provides general-purpose helpers, including the canonical silence idioms used across the framework:

- `utils::has cmd` — instead of `command -v cmd >/dev/null 2>&1`
- `utils::quiet cmd` — instead of `cmd >/dev/null 2>&1`
- `utils::quiet_err cmd` — instead of `cmd 2>/dev/null`
- `utils::ignore cmd` — instead of `cmd >/dev/null 2>&1 || true`

Full reference: [Core utils module](../03-modules/core-utils.md).
