[↑ Documentation index](../README.md)

# core/utils

General-purpose utility functions. Source: [core/utils.sh](../../../core/utils.sh).

## Availability

`core/utils` is loaded automatically by the bootstrap ([bootstrap/init.sh](../../../bootstrap/init.sh)),
so its functions are available in every module and every script after bootstrap — no explicit
`load "core/utils"` is needed.

Note: `core/utils` is loaded **last** among the core modules (`core/const`, `core/logger`,
`core/errorhandler`, `core/version`, `core/utils`). Because of that the core modules themselves
do not use `utils::*` helpers — they simply are not available yet while core is loading.

## Function reference

### utils::strict

```bash
utils::strict
```

Enables strict mode for the current shell: `set -euo pipefail` and `IFS=$'\n\t'`.
Call it in the entry point of your script. Sourced library files must not enable strict mode
on their own, so this is left to the caller.

### utils::guard

> **Deprecated.** Use `bs::guard` from [core/guard.sh](../../core/guard.sh):
> `bs::guard "foo" || return 0` — it checks the mark and sets it in one call.
> `utils::guard` is kept as a check-only alias (`bs::guard_loaded`) for
> backward compatibility.

```bash
if utils::guard "foo"; then return 0; fi
readonly __FOO_SOURCED=1
```

Source guard for hand-written modules. Returns `0` if the module has already been loaded
(caller should `return 0` immediately) and `1` if it has **not** been loaded yet
(caller should continue).
The argument is the module name without the `__` / `_SOURCED` parts; it is uppercased
internally (`foo` → `__FOO_SOURCED`).

Note: modules loaded via `load` are already protected against double loading by the loader's
`BS_LOADED_MODULES` registry; the guard is for files sourced outside the loader.

### utils::has

```bash
if utils::has dnf; then
  utils::quiet dnf check-update
fi
```

Checks that a command exists in `PATH`. Returns `0` if available, `1` otherwise.
Replaces the idiom `command -v foo >/dev/null 2>&1`.

### utils::quiet

```bash
if utils::quiet grep -q foo file; then ...; fi
```

Runs a command with both stdout and stderr fully suppressed. The command's exit code
is preserved. Replaces the idiom `cmd >/dev/null 2>&1`.

### utils::quiet_err

```bash
utils::quiet_err some_cmd
```

Runs a command suppressing only stderr; stdout stays visible. The command's exit code
is preserved. Replaces the idiom `cmd 2>/dev/null`.

### utils::ignore

```bash
utils::ignore systemctl stop myservice
```

Runs a command with output suppressed and the result ignored — always returns `0`.
Explicit replacement for `cmd >/dev/null 2>&1 || true`. Use only where failure of the
command genuinely does not matter.

### utils::ensure_source

```bash
utils::ensure_source "${ROOT_DIR}/lib/math.sh" add_integers
```

Loads a file with `source` and verifies that a required function appeared in the environment.
Returns `0` on success, `1` on any failure (missing file, failed source, function absent).
Diagnostics go to stderr. Global variables are not modified.

### utils::ensure_shell_version

```bash
utils::ensure_shell_version 4
```

Checks that the current shell (`$SHELL`) is at least the required major version
(default: `4`). Supports `bash` and `zsh`; prints an error to stderr and returns `1`
for an older or unknown shell. Prints a confirmation line to stdout on success.

### utils::detect_root

```bash
utils::detect_root
```

Detects the framework root directory and exports it as `FRAMEWORK_ROOT`. Honors a
pre-set `FRAMEWORK_ROOT` if it points to an existing directory; otherwise resolves the
caller script path (following symlinks, stepping up out of `bin/`). Reports through
`log::debug` / `log::info`.

### utils::boot_dir

```bash
utils::boot_dir
```

Sets and exports `BOOT_DIR` — the `bootstrap/` directory of the framework, resolved
relative to `core/utils.sh` itself.

## Silence idioms

One of the main purposes of `core/utils` is to replace noisy bare-shell redirection idioms
with named functions, so intent is visible at the call site:

| Bare shell                      | BS                   | Effect                                            |
|---------------------------------|----------------------|---------------------------------------------------|
| `command -v foo >/dev/null 2>&1` | `utils::has foo`     | Check command availability                        |
| `cmd >/dev/null 2>&1`           | `utils::quiet cmd`   | Suppress stdout+stderr, keep exit code            |
| `cmd 2>/dev/null`               | `utils::quiet_err cmd` | Suppress stderr only, keep exit code            |
| `cmd >/dev/null 2>&1 \|\| true` | `utils::ignore cmd`  | Suppress output and ignore failure (always `0`)   |

Example — before / after:

```bash
# bare shell
if command -v dnf >/dev/null 2>&1; then
  dnf check-update >/dev/null 2>&1
fi
systemctl daemon-reload >/dev/null 2>&1 || true

# BS
if utils::has dnf; then
  utils::quiet dnf check-update
fi
utils::ignore systemctl daemon-reload
```
