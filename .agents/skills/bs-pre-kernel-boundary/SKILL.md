---
name: bs-pre-kernel-boundary
description: Check the pre-kernel boundary — code running before the loader (bootstrap/bs.sh, entry-point headers, init.sh pre-loader section) must NOT use core/lib abstractions; after load they are required
type: prompt
whenToUse: After any change to bootstrap/bs.sh, boot.sh, bs, bootstrap/init.sh, bootstrap/loader.sh, or when reviewing whether pre-load code depends on the kernel
---

## The rule

The kernel (`core/`) loads through `bootstrap/loader.sh` — nothing from it exists
before that. So:

- **Pre-kernel scope** (before the loader sources): ONLY bash builtins, POSIX
  tools, and the file's own helpers. No core/lib abstractions, ever.
- **Post-load scope** (after `bootstrap/init.sh` / `load`): the abstractions
  are REQUIRED by project convention (`bs::guard`, `utils::quiet*`,
  `log::*`, `streams::*`) — raw redirects, `echo >&2` and hand-rolled guards
  are violations there.

## Pre-kernel scope definition

| File | Boundary |
|---|---|
| `bootstrap/bs.sh` | the whole file |
| `boot.sh` | everything before `exec "${BS_ROOT}/bs"` |
| `bs` | everything before `source "${BS_ROOT}/bootstrap/init.sh"` |
| `bootstrap/init.sh` | everything before `source .../loader.sh` |
| `bootstrap/loader.sh` | everything before `source .../bs.sh` (the loader itself is load-time machinery and may probe `declare -f`) |

## Forbidden in pre-kernel scope

- Core/lib namespaces: `is::`, `log::`, `utils::`, `streams::`, `error::`,
  `cleanup::`, `config::`, `deps::`, `args::`, `const::`, `str::`, `arr::`,
  `map::`, `lang::`, `platform::`, `langdoc::`, `lsp::`
- Framework functions: `bs::guard`, `bs::guard_loaded`, `bs::source_relative`,
  `load "..."` (and the `load` builtin-style command)
- Core constants: `E_*` (error codes from `core/const.sh`), color/flag constants
- Reading framework vars (`BS_ROOT`, `BS_HOME`, `BS_SILENT`, `BS_VERSION`,
  `HOME`, `PATH`) is ALLOWED — they are environment, not abstractions

## Allowed in pre-kernel scope

- Bash builtins: `[[ ]]`, `case`, `(( ))`, `local -r`, `printf`, `cd`,
  `readonly`, `source` (only of `bootstrap/bs.sh`)
- POSIX tools: `dirname`, `basename`, `pwd -P` (tier core)
- Self-references defined in the same scope: `bs::shell::*`,
  `bs::script_dir`, `bs::append_local_bin_to_path`

## Check procedure

```bash
# 1. bootstrap/bs.sh — must be completely clean
rg -n "is::|log::|utils::|streams::|error::|cleanup::|config::|deps::|args::|const::|\bstr::|\barr::|\bmap::|lang::|platform::|bs::guard|bs::source_relative|bs::guard_loaded|\bE_[A-Z][A-Z_]*|load \"|load\b" bootstrap/bs.sh

# 2. boot.sh — whole file (it never sources init.sh, exec only)
rg -n "is::|log::|utils::|streams::|bs::guard|load\b|E_[A-Z][A-Z_]*" boot.sh

# 3. bs — only the pre-init header
sed -n '1,/source .*bootstrap\/init.sh/p' bs | rg -n "is::|log::|utils::|streams::|bs::guard|load\b|E_[A-Z][A-Z_]*"

# 4. init.sh — only the pre-loader section
sed -n '1,/source .*loader\.sh/p' bootstrap/init.sh | rg -n "is::|log::|utils::|streams::|bs::guard|load\b|E_[A-Z][A-Z_]*|bs::source_relative"

# 5. loader.sh — only before its bs.sh source
sed -n '1,/source .*bs\.sh/p' bootstrap/loader.sh | rg -n "is::|log::|utils::|streams::|bs::guard|load\b|E_[A-Z][A-Z_]*"
```

Rules of interpretation:

- `rg` hits comments too — inspect the match; a comment saying "do not use
  `log::` here" is NOT a violation, a call is.
- `bs::shell::*`, `bs::script_dir`, `bs::append_local_bin_to_path` in
  pre-kernel scope are self-references — allowed, not findings.
- `log::available` inside `bootstrap/loader.sh` (load-time machinery) is
  allowed — it is the loader's own probe, runs after the boundary.

## Positive (post-load) spot check

After the boundary, code MUST use the abstractions. Quick sweep on changed
files: no raw `2>/dev/null` where `utils::quiet_err` fits, no `echo` to stderr
where `log::error` fits, every module starts with `bs::guard "NAME" || return 0`
(exception: `core/prereq.sh` — self-guard by design). Full-depth review of the
post-load side is the `bs-review-module` skill.

## Output format

```
## bs-pre-kernel-boundary check
- bootstrap/bs.sh — CLEAN / <file:line — violation>
- boot.sh — ...
- bs (pre-init) — ...
- bootstrap/init.sh (pre-loader) — ...
- bootstrap/loader.sh (pre-bs.sh) — ...
## Post-load spot check
- <file:line> — <finding or CLEAN>
```

Report only; do not fix anything unless asked.