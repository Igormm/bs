---
name: bs-pre-kernel-namespace
description: Write or modify functions in bootstrap/bs.sh — the dependency-free pre-kernel root namespace (bs::shell::*, bs::script_dir, PATH tweak) that must be usable BEFORE the loader
type: prompt
whenToUse: When adding/editing functions that run before bootstrap/loader.sh loads (entry-point gates, shell detection, early helpers), or when moving a helper out of core/ into the pre-kernel namespace
---

`bootstrap/bs.sh` is the pre-kernel root namespace: it is sourced by the entry
points (`boot.sh`, `bs`), by `bootstrap/init.sh` (before the loader) and by
`bootstrap/loader.sh` (for direct loader users), so its functions are available
before ANY kernel code exists. A function belongs here if it must work before
`load` runs — everything else goes to `core/` or `lib/`.

## Hard constraints

1. **Zero dependencies.** No `source`, no `load`, no `bs::guard`
   (it lives in `core/prereq.sh`, loaded via the loader), no `is::*`, no `log::*`,
   no constants. Only builtins and shell variables.
2. **Bash 3.2 compatibility.** The file is sourced BEFORE the version gate, so
   it must parse and run on the oldest interpreter the framework rejects.
   Forbidden in this file: associative arrays (`declare -A`), `mapfile`,
   `${var,,}`/`${var^^}`, `${var@Q}`, `&>`, `[[ =~ ]]` with ERE portability
   traps — stick to `[[ ]]`, `case`, `(( ))`, `local -r`, `printf`.
   Reference for a bash-3.2-safe subset: `core/prereq.sh::bs::guard`.
3. **Raw self-guard** at the top — `bs::guard` cannot be used here:
   ```bash
   [[ -n "${__BS_SH_SOURCED:-}" ]] && return 0
   readonly __BS_SH_SOURCED=1
   ```
   Comment why (guard lives in prereq, loaded via loader). Never use `exit`
   inside a function — return a status code; the caller decides.
4. **Runtime shell detection, never `$SHELL`.** `$SHELL` is the login shell and
   lies when sourcing from another shell. Detect via `BASH_VERSION` /
   `ZSH_VERSION` (see `bs::shell::name`). This is the whole point of the file —
   do not reintroduce `$SHELL`.
5. **Silent on success, error to stderr.** Entry points run under
   `set -euo pipefail` and print their own messages; a gate function must not
   spam stdout on every `bs run`. On failure: `printf 'ERROR: ...' >&2` +
   `return 1`.

## Documentation conventions

- Bilingual `@description` pairs (en/ru) per function, `@param`/`@stdout`/
  `@exitcode`/`@return` when relevant — `bs lang-doc` parses these.
- Add `# @tier core` to the file header: the pre-kernel namespace is pure
  Bash 4+, no GNU tools — works everywhere. This replaces ad-hoc runtime
  checks: the tier declares the requirement, the single canonical gate
  (`bs::shell::ensure_version`) enforces it at the entry points.

## Wiring checklist for a NEW function

1. Add it to `bootstrap/bs.sh` under the right section (PATH / script dir /
   shell detection / gate).
2. If it replaces an inline check in an entry point (`boot.sh`, `bs`) or in
   `bootstrap/init.sh` — remove the inline copy; do not keep duplicates.
3. If it supersedes a `core/utils.sh` function — mark the old one
   `@deprecated` in code and docs; do not delete it (backward compatibility).
4. Add tests to `tests/unit/testbsunit.sh` (auto-discovered): pass/fail exit
   codes, stderr content, default arguments, guard idempotency. Directly
   `source "${BS_PROJECT_ROOT}/bootstrap/bs.sh"` in the test, like
   `testprerequnit.sh` does for prereq.
5. Update `documentation/en|ru/02-core-concepts/architecture.md` (stage 1/2
   and init.sh step lists) and `best-practices.md` (centralized shell checks
   pattern) — both languages, mirrored.
6. Run the validation cycle (see `bs-validate` skill):
   ```bash
   bash tests/validatesyntax.sh
   bash tests/validateshellcheck.sh
   bash tests/runalltests.sh
   ```

## Who sources this file (keep this list in sync)

- `boot.sh` — stage 1, after resolving `BOOT_DIR`, before `exec bs`;
- `bs` — stage 2, after resolving `BS_DIR`, before anything else;
- `bootstrap/init.sh` — after `BS_ROOT` resolution, before the loader
  (`bs::append_local_bin_to_path` depends on it);
- `bootstrap/loader.sh` — so direct loader users get `bs::shell::*` too.

## Never put in this file

- Load-time machinery (`bs::guard`, `bs::guard_loaded`, `bs::source_relative`)
  — they belong to `core/prereq.sh`, the loader's first module;
- functions needing `log::*`, `is::*`, arrays of results, or any external tool;
- `$SHELL`-based detection of any kind.