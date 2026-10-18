[↑ Developer guide](README.md)

# Shell portability

BS must be usable from most shells, not only bash and zsh. This page is the
design behind branch `fix/kernel-security-p0`; the working rules for authors
are in the skill `.agents/skills/bs-shell-portability/SKILL.md`.

## Three shells, not one

| Role | Meaning | Who decides |
|---|---|---|
| **host** | the interpreter that executes BS code | always bash ≥ 4.2 (found by the trampoline) |
| **user shell** | where the person types commands; whose rc file gets PATH | `--shell`, `BS_USER_SHELL`, parent process, login shell |
| **script shell** | the shebang of a user script (`#!/usr/bin/env bs`) | the script |

The kernel and `lib/` need arrays, namerefs, `[[ ]]`, `local -r`. They stay
bash. What is made shell-independent is everything *around* them: entry
points, installer, PATH setup, checks, uninstall, `bs where`.

## Access modes

- **exec** — `bs ...` from any shell. The entry point starts with a POSIX
  prologue; if the interpreter is not bash ≥ 4 (or bash in POSIX mode) it
  sources `bootstrap/trampoline.sh`, which finds a capable bash and
  `exec`s the same file with the same arguments.
- **source** — `source bootstrap/init.sh`. Only bash 4.2+. Elsewhere it answers
  with a bilingual message instead of `Bad substitution`.
- **call** — `bs call [--load MODULE] FUNCTION [ARGS]`: the bridge for shells
  with another syntax (fish, nushell, dash, ash, ksh). A kernel or module
  function runs in the bash that `bs` starts; its stdout and stderr are yours,
  and its exit code becomes the exit code of `bs call`. Only an existing
  function with a valid name runs (`rm`, `a;b`, `$(id)` are refused), a module
  path is only `core/...` or `lib/...` without `..`. Example: `bs call
  utils::human_size 1536000`; from fish: `set size (bs call utils::human_size
  1536000)`.
- **trampoline** — the mechanism of the first mode. `BS_HOST_BASH=/path`
  overrides the search (an invalid value is an error, never a silent fallback).
  With no bash 4.2+ it prints install hints (apk/apt/dnf/brew) and exits 1.

## Tiers

Two independent axes:

- `@tier core | gnu-linux` — what *userland* the module needs (unchanged).
- `@shell posix | bash4` — what *language* the file is written in. Absent means
  `bash4`. The line carries a bilingual reason after the dash:
  `# @shell bash4 — arrays and [[ ]] are used`.

Per user, the effective result is `platform::get shell_tier`:

| tier | meaning |
|---|---|
| `native` | the user's shell is bash 4.2+; BS can be sourced |
| `hosted` | another shell; BS works as the `bs` command run by a found bash |
| `unsupported` | no bash 4.2+ on the machine |

A dependency that cannot be removed is not hidden: the module is `bash4` and
says why in the annotation.

## The shell registry — `bootstrap/shell.sh`

POSIX code. Functions are named `bs_shell_*` (dash rejects `::` in names);
`bs::shell::*` aliases are created by `eval` in bash/zsh only. It knows the
families `bash zsh dash ash sh ksh mksh oksh osh fish nu` and answers:
`family`, `user`, `rc_file`, `path_line`, `reload_hint`, `fresh_flags`,
`all_rc_files`, `host_find`, `tier`, `tier_desc`.

| shell | rc file | PATH line |
|---|---|---|
| bash | `~/.bashrc` | `export PATH="$HOME/.local/bin:$PATH"` |
| zsh | `${ZDOTDIR:-~}/.zshrc` | same |
| dash, ash, sh, ksh, mksh, oksh | `~/.profile` | same |
| osh | `~/.config/oils/oshrc` | same |
| fish | `~/.config/fish/conf.d/bs.fish` | `contains -- … $PATH; or set -gx PATH …` |
| nu | `~/.config/nushell/env.nu` | `$env.PATH = ($env.PATH \| prepend …)` |

nushell: if `env.nu` does not exist the installer does not invent it; it
prints the exact line to add.

## Strict mode — `bs --strict-shell`

By default the trampoline lets any shell use any module (the code always runs
in bash). `--strict-shell` (or `BS_SHELL_STRICT=1`, needed for the shebang
mode) makes the `@shell` tier binding: a `lib/` module loads only if its tier
fits the shell BS was **started from** (`BS_ORIGIN_SHELL`, exported by the
trampoline; a bash that reached the trampoline counts as `sh`).

| tier of the module | allowed from |
|---|---|
| `posix` | any shell |
| `bash4` (default) | bash 4.2+ |
| another word (`zsh`, `fish`, `nu`, …) | the shell of that name |
| a list `zsh,bash4` | any of them |

Synonyms (tier words and shell names): `sh`, `shell`, `posix` = `posix`; `bash`, `bash4` = `bash4`; `fs`, `fish` = `fish`; `nu`, `nushell` = `nu`. An unknown word is kept as is.

`core/` (the kernel) is always allowed; otherwise nothing could start. A
refusal names the module, its tier and the origin shell, and exits 1:

```bash
dash ./bs --strict-shell run script.sh   # module lib/io/streams (@shell bash4) cannot run from 'dash'
```

## Where shell-specific checks may live

Only in the abstraction layer: `bootstrap/bs.sh`, `bootstrap/shell.sh`, `bootstrap/trampoline.sh`. Anywhere else a direct use of `BASH_SOURCE`, `BASH_VERSION`, `FUNCNAME`, `ZSH_*`, `$SHELL`, `$0`-as-path must either call the layer (`bs::is_main`, `bs::script_dir`, `bs::func_name`, `bs::stack_*`, `bs_shell_host_ok`) or carry a `shell-gate` tag with the reason. `.agents/skills/bs-shell-abstraction/scripts/find_leaks.sh` checks this; the entry points share one prologue and read the bootstrap directory from `BS_ENTRY_DIR` / `BS_BOOTSTRAP_DIR`.

Beyond detection, the layer also gives: `bs::shell::host` (the running bash — start child shells with `"$(bs::shell::host)" -c`, never a bare `bash`), registry questions instead of family comparisons (`bs_shell_can_source`, `bs_shell_rc_create_ok`, `bs_shell_default_login_path`), and `args::completion PROG [bash|zsh|fish|nu]` (zsh is tested in a real zsh; fish and nushell only as text).

## Shell priorities

Priority comes from two things: **where the shell is found** (an estimate from
distributions and platforms, not a measurement) and **what was really verified
on this machine** (Fedora 43; `./bs version`, a script with `#!/usr/bin/env bs`,
`install.sh --help`, `bs init-shell`, `probe_shells.sh`). Fill the table only
with results of real runs.

| # | Shell | Where it is found | Version here | Runs `bs` and a script | Native kernel (`bash4`) | What to do |
|---|---|---|---|---|---|---|
| 1 | bash | nearly every Linux, Termux, WSL; macOS has the old 3.2 | 5.3.0 | yes | yes | the kernel host; the reference |
| 1 | zsh | macOS default, many Linux developers | 5.9 | yes | parses, behaves differently (arrays from 1, no `FUNCNAME`, `BASH_REMATCH`) | compatibility layer, completions |
| 2 | dash | `/bin/sh` on Debian/Ubuntu, install scripts | 0.5.12 | yes (trampoline) | no | POSIX kernel (`core/`) |
| 2 | busybox ash | Alpine, containers, routers, Termux | 1.37.0 | yes (trampoline) | no; friendlier than dash (`[[ ]]`, `pipefail`, `::`) | POSIX kernel, check in Termux |
| 3 | fish | popular interactive shell | 4.2.0 | yes, only as the `bs` command and a script with the shebang | not applicable (other syntax) | bridge (`bs call`), completion text |
| 3 | ksh93 | Unix, BSD, enterprise systems | 93u+m 1.0.10 | yes | parses; no `local`, `local -r`, `::` | POSIX kernel; no bash4 kernel promised |
| 3 | mksh | **the Android system shell**, OpenBSD (a fork) | R59 | yes | does not parse fully | POSIX kernel |
| 4 | nushell | growing, developers | not installed | not verified | not applicable | bridge, check after installing |
| 4 | oksh, osh | rare | not installed | not verified | — | do not develop |

"Yes" in the run column means: `./bs version` through this shell and a script
with `#!/usr/bin/env bs` worked; `install.sh --help` printed the help. "No" for
the bash4 kernel is not an error: the kernel runs in the bash the trampoline
found, and the other shells get POSIX modules and the bridge.

Development order: **1 → 2 → 3 → 4**. At levels 2–3 the main contribution is
growing the POSIX kernel (see "POSIX modules of the kernel") and the bridge for
shells with another syntax.

## What is verified

Run for real on this machine: bash 5.3.0, zsh 5.9, dash 0.5.12, busybox ash
1.37.0, ksh93u+m 1.0.10, mksh R59, fish 4.2.0 — `bs version`, a script with the
`bs` shebang, `install.sh --help`, the feature probe. **Not run:** nushell (not
installed), oksh, osh. For fish only the `bs` command and a script with the
shebang were run; the kernel does not read its syntax.

## Access diagrams: re-run, bridge, POSIX tier

Three ways to reach the kernel from other shells. The whole picture is in [Getting Started](../01-getting-started/README.md).

### Start from dash: re-run in bash

![Scenario 2: start from dash — re-run in bash](../../assets/uml/scenario-2-en.svg)

### Call from fish and nushell: `bs call`

![Scenario 3: bs call from fish or nushell](../../assets/uml/scenario-3-en.svg)

### The POSIX tier without bash

![Scenario 4: the POSIX tier without bash](../../assets/uml/scenario-4-en.svg)

## Tests and tools

- `tests/unit/testshellunit.sh` — registry; `testtrampolineunit.sh` — entry
  points under dash/zsh/bash-as-sh; `testshelltierunit.sh` — annotations;
  `tests/integration/testinstallshells.sh` — installer per shell.
- `bash .agents/skills/bs-shell-portability/scripts/tier_scan.sh --check <paths>`
  — annotation vs. real constructs.
- `bash .agents/skills/bs-shell-portability/scripts/probe_shells.sh` — probes
  installed shells for language features.

## POSIX modules of the kernel

`@shell posix` files in `core/` are converted one at a time (order: `prereq`,
`guard`, `const`, `version`, `logger`, ...). A posix module follows the same
contract as the registry: the real functions have valid identifiers
(`bs_guard`, `bs_source_relative`), the `bs::guard`-style names are aliases made
by `bs_shell_alias` in bash and zsh only, so every existing caller keeps
working. Helpers of the layer used by these modules: `bs_shell_alias`,
`bs_shell_readonly` (a global `readonly`: in zsh `readonly` inside a function is
local, so zsh gets `readonly -g`). The directory of a sourced file comes from
`BS_CURRENT_FILE`, which the loader sets while it sources a module; bash
additionally reads it from the call stack.
`core/const.sh` shows the per-shell branches: ESC bytes come from `printf` (no `$'\033'`),
`SUPPORTED_DISTROS` is an array in bash and zsh and a space-separated string in
shells without arrays; `const::*` names are aliases of `const_*`.

`core/quiet.sh` (`@shell posix`) — the "quiet" idioms: `utils_has`, `utils_quiet`,
`utils_quiet_err`, `utils_ignore`, `utils_attempt` (the old `utils::*` in bash
and zsh). It loads before `core/utils.sh`; verified in bash, zsh, dash, busybox
ash, ksh93 and mksh (`unit/testquietportableunit.sh`).

## Not done yet

fish and nushell completions are generated by `args::completion` but not yet
run in a real fish/nu; `@shell` annotations cover `core/` and almost all of
`lib/` (an unannotated file counts as `bash4`).
