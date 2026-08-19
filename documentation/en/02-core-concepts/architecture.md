[↑ Documentation index](../README.md)

# Architecture

BS is a thin runtime layer over bash 4+. It consists of two entry scripts
(`boot.sh`, `bs`), a bootstrapper (`bootstrap/init.sh`), a module loader
(`bootstrap/loader.sh`), the always-loaded `core/` modules and the on-demand
`lib/` modules. This document describes how the pieces fit together and what
happens between a script's shebang and its exit.

## Loading flow at a glance

```
entry: ./boot.sh <script> [args]          entry: bs <cmd> | #!/usr/bin/env bs
            │                                        │
            ▼                                        │
  stage-1: boot.sh                                   │
    · require bash >= 4        (exit 1)              │
    · locate BS_ROOT           (exit 2 if not found) │
    · exec "${BS_ROOT}/bs" "$@" ────────────────────►│
                                                     ▼
                                          stage-2: bs
                                            · set -euo pipefail, IFS
                                            · BS_VERSION (readonly), BS_ROOT,
                                              BS_HOME, BS_SILENT=1
                                            · source bootstrap/init.sh
                                              │   · idempotent: BS_INITIALIZED
                                              │   · source bootstrap/loader.sh
                                              │   · load core: const, logger,
                                              │     errorhandler, version, utils
                                            · errorhandler::setup_trap
                                              (EXIT trap → cleanup stack)
                                                     │
                              ┌──────────────────────┴──────────────────────┐
                              ▼                                             ▼
                     CLI dispatch                                   shebang mode
                     help/version/env/list/        first arg is a file → BS_SHEBANG=1
                     doctor/run/init-shell                      │
                                                                ▼
                                              run_cmd: new bash process
                                                · unset BS_INITIALIZED
                                                · source bootstrap/init.sh
                                                · source <script> [args]
                                                                │
                                                                ▼
                                                       your script runs
                                                         load "core/args"
                                                         load "lib/io/streams"
                                                         ...
                                                                │
                                                                ▼
                                            exit → EXIT trap → cleanup::__run_all
                                            (BS_CLEANUP_STACK, LIFO order)
```

## Stage 1: `boot.sh`

[boot.sh](../../../boot.sh) is a minimal pre-loader whose only job is to verify
the environment and hand control to `bs` as fast as possible:

1. **Environment check.** Requires bash 4.0+; otherwise prints an error and
   exits with code `1`.
2. **BS_ROOT lookup**, in priority order:
   - already exported `BS_ROOT`;
   - the directory containing `boot.sh` itself, if `bs` and
     `bootstrap/init.sh` exist next to it (repository checkout);
   - the prefixes `~/.local/lib/bs` and `/usr/local/lib/bs` (installed copies).

   If nothing is found, it exits with code `2`. The same code is used when
   `${BS_ROOT}/bs` is missing or not executable.
3. **Handover.** `exec "${BS_ROOT}/bs" "$@"` replaces the process, so all
   arguments and standard streams reach stage 2 unchanged.

Exit codes: `0` — `bs` ran successfully; `1` — bash too old; `2` — framework
not found.

## Stage 2: `bs` — CLI and shebang interpreter

The [bs](../../../bs) script is the unified entry point. It runs under
`set -euo pipefail` with `IFS=$'\n\t'` and performs the following:

- Defines `readonly BS_VERSION` (currently `0.3.0`).
- Resolves `BS_ROOT` if it is not already set: first the script's own
  directory (when it contains `bootstrap/init.sh`), then
  `~/.local/lib/bs` and `/usr/local/lib/bs`.
- Exports `BS_HOME` defaulting to `BS_ROOT` (historical alias used by some
  `lib/` modules) and `BS_SILENT` defaulting to `1`, so core loading stays
  quiet and does not pollute script output.
- Sources [bootstrap/init.sh](../../../bootstrap/init.sh), which loads the
  core (see below).
- Installs the EXIT trap via `errorhandler::setup_trap`, so the cleanup stack
  (see `cleanup::add` in [core/errorhandler.sh](../../../core/errorhandler.sh))
  runs on exit.

After initialization `bs` chooses one of two modes:

- **Shebang mode.** If the first argument is a path to an existing file and is
  not one of the CLI commands, `BS_SHEBANG=1` is set and the file is executed
  through `run_cmd`. This is what makes `#!/usr/bin/env bs` work.
- **CLI mode.** Otherwise the first argument is dispatched as a command:
  `help`, `version`, `env`, `list`, `doctor`, `run <script> [args]`,
  `init-shell`.

`run_cmd` (also used by `bs run`) executes the target script in a **new bash
process**: it unsets the inherited `BS_INITIALIZED`, sources
`bootstrap/init.sh` again (so the script gets a fresh, fully initialized
environment) and then `source`s the script with its arguments.

## `bootstrap/init.sh` — core initialization

[bootstrap/init.sh](../../../bootstrap/init.sh) must be **sourced**, not
executed (it refuses to run directly). It does not enable strict mode and does
not change the caller's `IFS` — those are the entry points' responsibility.
Its steps:

1. **Idempotency.** If `BS_INITIALIZED` is already set, it returns `0`
   immediately (with a `log::debug` note when the logger is available). This
   makes repeated `source bootstrap/init.sh` calls safe.
2. **BS_ROOT resolution.** If `BS_ROOT` is unset or invalid, it is derived
   from the file's own location (the parent of `bootstrap/`), verified by the
   presence of the `bs` script. If that fails, initialization aborts with an
   error asking to set `BS_ROOT` manually.
3. **PATH tweak.** `~/.local/bin` is prepended to `PATH` once (checked against
   duplicates), which covers local installs.
4. **BS_HOME.** Defaults to `BS_ROOT` if unset.
5. **Loader.** Sources `bootstrap/loader.sh` (falling back to
   `${BS_ROOT}/loader.sh`).
6. **Core modules**, loaded via `load` in a fixed order:
   - `core/prereq` — first: the core primitives `bs::guard`,
     `bs::guard_loaded` and `bs::source_relative`, available a priori to all
     other modules (modules never source `prereq.sh` manually);
   - `core/lang` — language primitives over Bash built-ins: introspection
     (`bs::func_name`, `bs::call_stack`, `bs::type_of`), strings (`str::*`),
     collections (`arr::*`, `map::*`);
   - `core/const` — error codes (`E_SUCCESS`, `E_ERROR`, `LIB_ERROR_*`),
     color constants, framework flags (`FRAMEWORK_DEBUG`,
     `FRAMEWORK_DRY_RUN`);
   - `core/logger` — the `log::` family (`log::info`, `log::warn`,
     `log::error`, …);
   - `core/errorhandler` — `errorhandler::throw`, `errorhandler::setup_trap`,
     the cleanup stack (`cleanup::add`) and exit helpers (`bs::exit`,
     `error::exit`);
   - `core/version` — `BS_VERSION` / `BS_NAME` exports and
     `bs::version::*` helpers;
   - `core/utils` — environment helpers, including the silence idioms
     `utils::has`, `utils::quiet`, `utils::quiet_err`, `utils::ignore`,
     `utils::attempt`
     (replacements for `command -v … >/dev/null 2>&1`, `>/dev/null 2>&1`,
     `2>/dev/null`, `>/dev/null 2>&1 || true` and `2>/dev/null || true`
     respectively);
   - `core/config` — the unified configuration loader (`config::load`,
     `config::get`, `config::set`);
   - `core/deps` — module dependency parsing (`# @depends`).

[core/guard.sh](../../../core/guard.sh) is kept as a backward-compatible
wrapper around [core/prereq.sh](../../../core/prereq.sh).
7. **Marker.** Exports `BS_INITIALIZED=1`. Unless `BS_SILENT=1`, prints the
   bootstrap path.

Because `core/utils` is always loaded, every BS script can rely on
`utils::has`/`utils::quiet` and friends without an explicit `load`.

## Module loader: `bootstrap/loader.sh`

[bootstrap/loader.sh](../../../bootstrap/loader.sh) provides a single public
function:

```bash
load "core/args"        # sources ${BS_ROOT}/core/args.sh
load "lib/io/streams"   # sources ${BS_ROOT}/lib/io/streams.sh
```

`load` takes a path **relative to `BS_ROOT` without the `.sh` extension** and
`sources` the corresponding file. Internals:

- **Duplicate-load protection.** Loaded modules are recorded in the
  associative array `BS_LOADED_MODULES`; a second `load` of the same module is
  a no-op returning `0`.
- **Cycle detection.** The modules currently being loaded are kept in the
  `BS_LOAD_STACK` array. If a module is requested while it is already on the
  stack, loading fails with a `circular dependency detected` error naming the
  full chain. The stack entry is always popped afterwards, including on
  failure.
- **`# @depends` directive.** Before sourcing a module, the loader greps the
  module file for the first comment line matching `@depends`, for example:

  ```bash
  # @depends core/logger, lib/system/utils
  ```

  Each listed dependency is loaded recursively first; a failed dependency
  aborts the whole load. The list may be comma- and/or space-separated and is
  parsed with a local `IFS=' '` regardless of the caller's `IFS`.
- **Error handling.** Missing `BS_ROOT`, a non-existent module file, or a
  failed `source` all produce a diagnostic on stderr and a non-zero return
  code — `load` never `exit`s the caller.
- **Alias.** `bs::load` is kept for backward compatibility and simply
  delegates to `load`.

Note: `load` is plain `source` with bookkeeping — module files are executed in
the caller's shell, so everything they define becomes available directly.

## Script lifecycle: from shebang to exit

A typical BS script looks like this:

```bash
#!/usr/bin/env bs

load "core/args"
load "lib/io/streams"

# ... script logic ...
```

Step by step:

1. The kernel starts `bs` with the script path as the first argument.
2. `bs` detects shebang mode (`BS_SHEBANG=1`) and calls `run_cmd`.
3. `run_cmd` spawns a clean bash, unsets `BS_INITIALIZED`, sources
   `bootstrap/init.sh` (full core load) and then sources the script.
4. The script pulls in additional modules with `load`. Already-loaded modules
   cost nothing thanks to `BS_LOADED_MODULES`.
5. During execution the script may register cleanup functions with
   `cleanup::add <fn>`.
6. On exit — normal, via `bs::exit [code]`, or via `error::exit "msg" [code]` —
   the EXIT trap installed by `errorhandler::setup_trap` runs
   `cleanup::__run_all`, which executes the stack in LIFO order and clears it.

The alternative is manual embedding in a plain bash script (useful when you
cannot control the shebang):

```bash
#!/usr/bin/env bash
set -euo pipefail

source "${BS_ROOT:-$HOME/.local/lib/bs}/bootstrap/init.sh"
errorhandler::setup_trap   # optional: cleanup stack on exit

load "lib/io/streams"
```

`init.sh` resolves `BS_ROOT` from its own path, so sourcing it by absolute
path is enough — no prior exports are required.

## Convention: `core/` vs `lib/`

| | `core/` | `lib/` |
|---|---|---|
| Loading | always, by `bootstrap/init.sh` | on demand, via `load` |
| Layout | flat (`core/logger.sh`) | grouped in subdirectories (`lib/io/streams.sh`, `lib/system/info.sh`, …) |
| Role | runtime the framework itself needs: constants, logging, error handling, version, utils, argument parsing | domain functionality: I/O streams, system info, UI, network, data, status, … |
| Stability contract | safe to rely on in every BS script | load explicitly; mind `# @depends` |

Rules of thumb:

- Never `source lib/...` or `core/...` files directly — always use `load`,
  so dependency resolution and duplicate protection keep working.
- Put new framework-level machinery in `core/` only if `bootstrap/init.sh`
  should load it unconditionally; everything else belongs to `lib/<area>/`.
- Module files carry the `#!/usr/bin/env bs` shebang as a marker, but they are
  meant to be loaded via `load`, not executed directly.

## See also

- [core/errorhandler.sh](../../../core/errorhandler.sh) — cleanup stack and exit helpers
- [core/utils.sh](../../../core/utils.sh) — `utils::has`, `utils::quiet` and other environment helpers
- [examples/](../../../examples) — runnable scripts using the patterns above
