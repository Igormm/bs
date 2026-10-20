---
name: bs-new-core-module
description: Create or modify a core/ kernel module of the BS framework, including registration in bootstrap/init.sh and the bs doctor checks
type: prompt
whenToUse: When the user asks to add a new core/ module, change kernel behavior, or modify the framework boot sequence
arguments:
  - module_name
---

Create or modify core module `$module_name`. Core modules differ from lib modules in important ways — read `core/logger.sh` and `bootstrap/init.sh` before writing anything.

## Differences from lib modules

- **Two tiers.** A core file is `# @shell posix` (default for NEW core code; valid POSIX sh, runs in dash, ash, ksh, mksh, zsh, bash) or `# @shell bash4` (only if it really needs associative arrays, namerefs, `=~`: today no `core/` file; what needs real bash arrays goes to a bridge in `lib/compat/`, like `args`, `deps`, `lang`). The tier is the single source of truth about the shell dependency.
- **`posix` files** live in the one `bs_` namespace (`bs_module_name`; the `module::name` alias is made by `bs_shell_alias` at the end of the file), have `#!/bin/sh`, no `local`/`[[ ]]`/arrays, and a portable test. Write them with the skill **`bs-kernel-code`** (skeleton, rules in chapter 12 of the code style guide) — this skill only covers registration.
- `bash4` files keep `#!/usr/bin/env bash`, `bs::guard`, `module::function` names.
- No manual dependency sourcing between modules unless the file is loaded alone: the whole core is loaded by `bootstrap/kernel.sh` (sourced by `bootstrap/init.sh`) in a fixed order: `prereq → lang → const → var → str → num → msg → logger → quiet → fmt → data → errorhandler → version → utils → config → deps → args` (then, in the full mode, the bridges `lib/compat/deps`, `lib/compat/lang` and `lib/compat/args`). Add a new module to the list in `kernel.sh`. A module may call only what is loaded before it; `bs_source_relative` for explicit dependencies, `command -v` for optional ones.
- `core/prereq.sh` is the ONLY module allowed a manual self-guard, because `bs_guard` is defined there. Never copy that pattern elsewhere.
- Strict mode is never set in core modules.

## Skeleton

`posix`: instantiate `.agents/skills/bs-kernel-code/references/module.sh.tmpl` (see `bs-kernel-code`, step 4). `bash4`:

```bash
#!/usr/bin/env bash
# shellcheck shell=bash
# @shell bash4 — <what holds the file> / <что держит файл>
# core/mymodule.sh — one-line description

# Source Guard
bs::guard "MYMODULE" || return 0

# Metadata
# shellcheck disable=SC2034
declare -g MYMODULE_VERSION="1.0.0"
```

## Registration checklist (all required for a NEW core module)

1. Add the module to the load list in `bootstrap/init.sh` (`load "core/…"` lines), in the correct dependency position (after everything it calls).
2. Add it to the required-files list (`req=(…)`) in `bs::cli::doctor_cmd` in `bootstrap/bs.sh`.
3. Add a unit test `tests/unit/test<module>unit.sh` (see `bs-write-test`) and, for a `posix` file, `tests/unit/test<module>portableunit.sh` (`bs-kernel-code`, step 6); `testposixtierunit.sh` requires it.
4. Run the full validation cycle (see `bs-validate`):
   ```bash
   bash tests/validatesyntax.sh
   bash tests/validateshellcheck.sh
   bash tests/validatedocscode.sh
   bash .agents/skills/bs-shell-abstraction/scripts/check_posix_tier.sh
   bash tests/runalltests.sh
   ```
5. If the module inventory or a tier changed, update `AGENTS.md`, both documentation languages (`documentation/en/` + `documentation/ru/`), the tier lists of the skills `bs-shell-abstraction` / `bs-shell-portability` and `CHANGELOG.md`; `tests/unit/testdoctierscountunit.sh` fails when the counts in the docs disagree with the `@shell` labels.

## Extra caution

Core changes affect every script using the framework. Keep changes minimal, do not alter existing public function signatures, and verify `bs doctor` still passes after the change.

## Portability / Вектор возможностей

Core kernel must stay portable (per `documentation/ru/code-style-guide.md`
§11, EN synced):

1. No GNU-only tools in core without a pure-bash fallback
   (`grep -P`, `sed -z`, `stat -c`, `date +%N`, `readlink -f`).
2. Probe chains for optional tools (reference: `bs_build::sha256`:
   `sha256sum → shasum -a 256 → cksum`).
3. Feature-detect, then gate: primitives portable by default;
   platform-specific behavior behind probes (`[[ -d /proc ]]` and the like).
4. Never select behavior by `uname` — probe the capability.
