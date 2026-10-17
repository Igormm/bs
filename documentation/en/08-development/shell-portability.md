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

## Priorities

1. bash, zsh, ash/dash, nushell — full path: install, uninstall, `bs where`,
   `bs init-shell`.
2. fish, ksh, mksh, oksh, osh — in the registry, same code paths.

## What is verified

Run for real: bash 5.3, zsh 5.9, dash 0.5.12 (syntax, entry points,
trampoline, install/uninstall in an isolated `HOME`). **Not run on a real
interpreter:** ash/busybox, ksh, mksh, oksh, osh, fish, nu — only the generated
text (rc file, line, reload command) is tested. Treat those as unverified.

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

## Not done yet

fish and nushell completions are generated by `args::completion` but not yet
run in a real fish/nu; `@shell` annotations cover `core/` and almost all of
`lib/` (an unannotated file counts as `bash4`).
