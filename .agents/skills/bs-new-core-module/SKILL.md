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

- Shebang is `#!/usr/bin/env bash` (NOT `#!/usr/bin/env bs`, no `shellcheck shell=bash` line needed).
- NO `bs::source_relative` — core modules do not carry their own dependencies. The whole core is loaded by `bootstrap/init.sh` in a fixed order: `prereq → const → logger → errorhandler → version → utils → config → deps`.
- Guard is still `bs::guard "NAME" || return 0` (defined in `core/prereq.sh`, which is autoloaded first).
- `core/prereq.sh` is the ONLY module allowed a manual self-guard, because `bs::guard` is defined there. Never copy that pattern elsewhere.
- Strict mode is never set in core modules.

## Skeleton

```bash
#!/usr/bin/env bash
# core/mymodule.sh — one-line description

# Source Guard
bs::guard "MYMODULE" || return 0

# Metadata
# shellcheck disable=SC2034
declare -g MYMODULE_VERSION="1.0.0"
```

## Registration checklist (all required for a NEW core module)

1. Add the module to the load list in `bootstrap/init.sh` (~lines 87-94), in the correct dependency position.
2. Add it to the required-files check (`req` list) in the `doctor_cmd` of the `bs` script (~line 122).
3. Add a unit test `tests/unit/test<module>unit.sh` (see `bs-write-test` skill).
4. Run the full validation cycle (see `bs-validate` skill):
   ```bash
   bash tests/validatesyntax.sh
   bash tests/validateshellcheck.sh
   bash tests/runalltests.sh
   ```
5. If conventions or module inventory changed, update `AGENTS.md` and both documentation languages (`documentation/en/` + `documentation/ru/`).

## Extra caution

Core changes affect every script using the framework. Keep changes minimal, do not alter existing public function signatures, and verify `bs doctor` still passes after the change.
