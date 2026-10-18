[↑ Documentation index](../README.md)

# Architecture

BS is a thin runtime layer: the kernel is split into a POSIX tier (any shell)
and a `bash4` tier (bash 4.2+; the other shells reach it through a re-run or
`bs call`). It consists of two entry scripts
(`boot.sh`, `bs`) with a shared POSIX prologue, a shell registry
(`bootstrap/shell.sh`), a bootstrapper (`bootstrap/init.sh`), a module loader
(`bootstrap/loader.sh`), the always-loaded `core/` modules and the on-demand
`lib/` modules. This document describes how the pieces fit together and what
happens between a script's shebang and its exit.

## Loading flow at a glance

Read top to bottom. Three layers: the **POSIX prologue** (runs in any shell),
**stages 1–2** (`boot.sh`, `bs` — bash 4.2+) and the **kernel**
(`bootstrap/init.sh` → `bootstrap/loader.sh` → `core/*`).

```
 someone starts:  ./boot.sh <script>   bs <cmd>   #!/usr/bin/env bs   sh install.sh
                  (from bash, zsh, dash, sh, ...: the user's shell does not matter)
                                          │
                                          ▼
 ┌─ POSIX PROLOGUE: the first lines of bs, boot.sh, install.sh ─────────────────┐
 │  · remember $0 (zsh changes $0 inside a sourced file)                        │
 │  · readlink -f → BS_ENTRY_DIR (entry point directory, links resolved)        │
 │  · . bootstrap/shell.sh          the shell registry, pure POSIX              │
 │  · bs_shell_host_ok ?  (this is bash 4.2+ in normal mode)                    │
 │        yes ──────────────────────────────► go on, costs nothing             │
 │        no  ─► . bootstrap/trampoline.sh                                      │
 │                 · loop guard: __BS_TRAMPOLINE                                │
 │                 · BS_HOST_BASH or bs_shell_host_find looks for bash 4.2+     │
 │                 · found     → exec bash <this same file> <same arguments>    │
 │                               (BS_ORIGIN_SHELL remembers the original shell) │
 │                 · not found → bilingual "what to install" message, exit 1   │
 └───────────────────────────────────────────────────────────────────────────────┘
                                          │ (now we are in bash 4.2+)
              ┌───────────────────────────┴───────────────────────────┐
              ▼                                                       ▼
   stage-1: boot.sh                                          stage-2: bs
    · source bootstrap/bs.sh (pre-kernel)                      (boot.sh execs into it)
    · bs::strict (prologue checked the version)                      │
    · BS_ROOT: env → next to boot.sh →                               ▼
      ~/.local/lib/bs → /usr/local/lib/bs        · BS_CALLER_PATH = the caller's PATH
      (not found → exit 2)                       · source bootstrap/bs.sh:
    · exec "$BS_ROOT/bs" "$@" ─────────────────►     bs::cli::*, bs::shell::*, bs::is_main
                                                 · bs::strict (prologue checked the version)
                                                 · BS_ROOT (own dir → ~/.local/lib/bs
                                                   → $BS_SYSTEM_PREFIX/lib/bs), BS_HOME,
                                                   BS_SILENT=1
                                                 · unset BS_INITIALIZED
                                                 · source bootstrap/init.sh ──┐
                                                 · errorhandler::setup_trap   │ (below)
                                                 · --strict-shell → BS_SHELL_STRICT=1
                                                          │
                       ┌──────────────────────────────────┴───────────────┐
                       ▼                                                  ▼
                CLI dispatcher                                     shebang mode
                help version env list doctor run                   first argument is a file,
                build init-shell shebang update                    not a command → BS_SHEBANG=1
                uninstall where ... → bs::cli::*_cmd                        │
                                                                            ▼
                                                      bs::cli::run_cmd: exec a new bash
                                                       · BS_RUN_SCRIPT=<script>
                                                       · unset BS_INITIALIZED
                                                       · source bootstrap/init.sh
                                                       · bs::strict
                                                       · source <script> [args]
                                                                            │
                                                                            ▼
                                                                your script runs
                                                                load "core/args" ...
                                                                            │
                                                                            ▼
                                         exit → EXIT trap → cleanup::__run_all (LIFO)
```

### The kernel: what `bootstrap/init.sh` does

```
 source bootstrap/init.sh
   │
   ├─ POSIX gate: not bash 4.2+ → bilingual explanation, return 1
   ├─ source bootstrap/bs.sh  (pre-kernel); BS_BOOTSTRAP_DIR
   ├─ BS_INITIALIZED set and bs::guard exists? → return 0   (idempotency)
   ├─ BS_ROOT (given, else the parent of bootstrap/ that holds the bs file)
   ├─ bs::shell::ensure_version 4   (source mode: there is no prologue)
   ├─ bs::append_local_bin_to_path   (~/.local/bin in the PATH of this process)
   ├─ BS_HOME (defaults to BS_ROOT)
   ├─ source bootstrap/loader.sh      → load and bs::load appear
   ├─ load core/prereq      bs::guard, bs::source_relative (first!)
   ├─ load core/lang        str::, arr::, map::, bs::func_name
   ├─ load core/const       error codes, colours, flags
   ├─ load core/logger      log::*
   ├─ load core/errorhandler  errorhandler::*, cleanup::add
   ├─ load core/version     BS_VERSION, bs::version::*
   ├─ load core/utils       utils::has, utils::quiet, ...
   ├─ load core/config      config::*
   ├─ load core/deps        # @depends parsing
   ├─ config::load          configuration from files and the environment
   └─ BS_INITIALIZED=1
```

### The loader: what `load "lib/group/module"` does

```
 load "lib/io/streams"
   │
   ├─ BS_ROOT set and a directory?            no  → error, return 1
   ├─ already in BS_LOADED_MODULES?           yes → return 0
   ├─ --strict-shell: does the module's @shell tier fit BS_ORIGIN_SHELL?   no → refuse
   ├─ module already in BS_LOAD_STACK?        yes → circular dependency, return 1
   ├─ push onto BS_LOAD_STACK
   ├─ for each dependency in "# @depends" → load (recursive); failure → return 1
   ├─ BS_CURRENT_FILE=<file>; source ${BS_ROOT}/lib/io/streams.sh
   ├─ pop from BS_LOAD_STACK (on error too)
   └─ BS_LOADED_MODULES[path]=1
```

## The kernel by tiers: what every shell gets

The kernel is neither "bash only" nor "POSIX only": each `core/` file carries a
`# @shell posix` or `# @shell bash4` label, and that label says where it runs.
The labels are checked by `bash .agents/skills/bs-shell-portability/scripts/tier_scan.sh`;
what was really run is in the priority table of
[shell-portability](../08-development/shell-portability.md).

| Tier | `core/` files | Runs directly in | How the other shells get it |
|---|---|---|---|
| `posix` (5) | `prereq`, `guard`, `const`, `version`, `quiet` | bash, zsh, dash, busybox ash, ksh93, mksh (verified by running) | — (they source it themselves) |
| `bash4` (9) | `lang`, `args`, `errorhandler`, `config`, `logger`, `utils`, `deps`, `calc`, `repl` | bash 4.2+ only | the entry point finds bash and re-runs itself in it (trampoline); kernel functions — the `bs call` command |

What makes it "available to all":

1. **Any shell runs `bs` and scripts with `#!/usr/bin/env bs`**: the entry-point
   prologue is POSIX and re-runs the file in bash 4.2+ when needed.
2. **The POSIX tier is sourced directly** from bash, zsh, dash, ash, ksh, mksh:
   constants, the version, `utils_has`/`utils_quiet` and the rest, the shell
   registry (`bootstrap/shell.sh`), shebang management (`bootstrap/shebang.sh`).
3. **The bridge `bs call [--load MODULE] FUNCTION [ARGS]`** calls any kernel
   function from fish, nushell and other shells with another syntax; the
   function runs in bash, the output and the exit code go back to the caller.

What the kernel does **not** promise: to run `lang`, `args`, `errorhandler` and
the other `bash4` files in dash, ash, ksh, mksh, fish or nushell. They need
associative arrays, namerefs and `=~` with `BASH_REMATCH`, which are missing or
behave differently there. Shells without a real run (nushell, oksh, osh) are
not considered verified. Files move from `bash4` to `posix` one by one (order:
`calc`, `utils`, `config`, `logger`, `deps`); `lang`, `args` and `repl` stay in
the `bash4` tier.

## Stage 0: POSIX prologue and the `trampoline`

The entry points (`bs`, `boot.sh`, `install.sh`) start with the same short
prologue that any shell can parse (dash, ash, zsh, ksh, bash). Without it
`sh install.sh`, `dash ./bs` or bash 3.2 would die with "Bad substitution"
before the first useful line.

| What | Where | Why |
|---|---|---|
| `BS_ENTRY_DIR` | prologue | the entry point directory with symlinks resolved; `BS_ROOT` and `bootstrap/` are found from it |
| `bootstrap/shell.sh` | shell registry | POSIX answers: which shell this is, can it be the host (`bs_shell_host_ok`), where bash 4.2+ is (`bs_shell_host_find`), the tier |
| `bootstrap/trampoline.sh` | re-run | `exec` into the bash found, same file and arguments; otherwise a message about what to install |
| `BS_HOST_BASH` | environment | force the bash used for the re-run |
| `BS_ORIGIN_SHELL` | environment | the shell BS was started from; `--strict-shell` uses it |
| `__BS_TRAMPOLINE` | environment | loop guard for the re-run |

In bash 4.2+ in normal mode the prologue is one test and re-runs nothing. More
on `@shell posix|bash4` tiers and shells: [shell-portability](../08-development/shell-portability.md).

## Stage 1: `boot.sh`

[boot.sh](../../../boot.sh) is a minimal pre-loader whose only job is to verify
the environment and hand control to `bs` as fast as possible:

1. **Pre-kernel namespace.** It sources `bootstrap/bs.sh` — a dependency-free,
   bash-3.2-compatible file — and enables strict mode
   (`bs::strict`). The POSIX prologue (`bs_shell_host_ok`) has already checked
   the bash version: it replaces an unsuitable bash with a re-run (trampoline)
   or exits with code `1`.
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

The [bs](../../../bs) script is the unified entry point. It starts with the POSIX
prologue (see the diagram), then enables strict mode through `bs::strict` and
performs the following:

- Takes its own directory from `BS_ENTRY_DIR` (set by the prologue), sources `bootstrap/bs.sh` (pre-kernel namespace)
  and enables `bs::strict`. The bash 4.2+ gate has already run in the prologue
  (`bs_shell_host_ok`), before anything else is loaded. It belongs to the `bash4` tier (that is how the
  kernel starts); `@shell posix` modules and the `bs call` bridge do not
  require it.
- Pulls in `BS_VERSION` from `core/version.sh` (currently `0.8.0`); `const.sh` has no number of its own.
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
  `help`, `version`, `env`, `list`, `doctor`, `run <script> [args]`, `build`,
  `init-shell`, `shebang`, `update`, `uninstall`, `where` and more (the full
  list is `bs help`); the commands live in `bootstrap/bs.sh` as `bs::cli::*`.

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
3. **Pre-kernel namespace.** Sources `bootstrap/bs.sh` and runs the shell
   version gate `bs::shell::ensure_version 4` before any kernel code loads (in
   source mode there is no prologue, so `init.sh` checks the version itself) —
   runtime detection via `BASH_VERSION`/`ZSH_VERSION`, never `$SHELL` (the
   login shell lies when sourcing from another shell).
4. **PATH tweak.** `~/.local/bin` is prepended to `PATH` once
   (`bs::append_local_bin_to_path`), which covers local installs.
5. **BS_HOME.** Defaults to `BS_ROOT` if unset.
6. **Loader.** Sources `bootstrap/loader.sh` (falling back to
   `${BS_ROOT}/loader.sh`). The loader also sources `bootstrap/bs.sh` for
   direct users, so `bs::shell::*` and friends are always available.
7. **Core modules**, loaded via `load` in a fixed order:
   - `core/prereq` — first: the core primitives `bs::guard`,
     `bs::guard_loaded` and `bs::source_relative`, available a priori to all
     other modules (modules never source `prereq.sh` manually); shell
     detection helpers previously here now live in `bootstrap/bs.sh`;
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
8. **Marker.** Exports `BS_INITIALIZED=1`. Unless `BS_SILENT=1`, prints the
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
