---
name: bs-new-lib-module
description: Scaffold a new BS framework library module under lib/ with guard, dependencies, metadata, and a matching unit test
type: prompt
whenToUse: When the user asks to create a new lib/ module, add a new feature module to the standard library, or extend an existing lib module with new public functions
arguments:
  - module_path
---

Create a new library module `$module_path` (e.g. `lib/network/http.sh`) following BS framework conventions. If `$module_path` is not given, ask the user for the module path and purpose.

## Module skeleton

Every lib module MUST follow this exact structure (see `lib/io/files.sh` as the reference implementation):

```bash
#!/usr/bin/env bs
# shellcheck shell=bash
# lib/group/module.sh — one-line description (bilingual ru/en header preferred)
# @depends core/const, core/logger, core/utils

# Source Guard
bs::guard "GROUP_MODULE" || return 0

# Dependencies (so the module also works when sourced directly, without the loader)
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# Metadata
# shellcheck disable=SC2034
declare -g GROUP_MODULE_VERSION="1.0.0"
# shellcheck disable=SC2034
declare -g GROUP_MODULE_LOADED="1"

# Public API
group::module::function() {
    local -r arg="${1:?argument required}"
    ...
}
```

## Hard rules

- Shebang `#!/usr/bin/env bs` + `# shellcheck shell=bash` on line 2.
- `# @depends` comment is parsed by `bootstrap/loader.sh` — keep it accurate.
- NEVER `set -euo pipefail` inside a module (strict mode only in entry points).
- Do NOT source `core/prereq.sh` manually — it is autoloaded first by `bootstrap/init.sh`.
- Guard name: `SCREAMING_SNAKE_CASE` of the module path (e.g. `lib/io/files.sh` → `IO_FILES`).
- Public functions: `group::module::name` namespace, with DocBlock (`@description`, `@param`, `@stdout`, `@return`). Private helpers: `group::module::__name` with `@private`.
- Use framework abstractions instead of raw commands: `io::streams::print` over `echo`, `utils::has` over `command -v ... >/dev/null 2>&1`, `utils::quiet`/`utils::quiet_err` over output redirects, `utils::ignore` over `>/dev/null 2>&1 || true`, `utils::attempt` over `2>/dev/null || true`, return codes from `core/const.sh` (`E_SUCCESS`, `E_INVALID`, ...). Never use bare `return 1`/`return 2` for error statuses — only in boolean predicates where 0/1 is a true/false protocol.
- Use the `is::*` predicates instead of test flags: `is::empty`/`is::not_empty` for `[[ -z/-n ]]`, `is::file`/`is::dir`/`is::exists` for `[[ -f/-d/-e ]]`, `is::number`, `is::command`, `is::function`.
- Report errors with `error::throw "msg" "${CODE}"` (caller name auto-detected) — never the `local func_name="..."` + `errorhandler::throw` pair.
- Signals via `signal::on`/`signal::ignore`/`signal::reset`, not raw `trap`.
- Strings/collections via `str::*`, `arr::*` (incl. `arr::from_lines`), `map::has`; appends via `io::files::append`; time via `utils::now_*`/`stamp`/`log_stamp`.
- Constants are `readonly` `SCREAMING_SNAKE_CASE`; locals are `local -r lower_snake_case`. No CamelCase/mixedCase anywhere — single unix-like style (code-style-guide §2.1).
- 2-space indent, 80-char lines, `[[ ... ]]`, always quote `"${var}"`.
- Bilingual (ru/en) comments, matching existing modules.

## After creating the module

1. Add a unit test at `tests/unit/test<module>unit.sh` (invoke the `bs-write-test` skill for the skeleton).
2. Optionally add an example in `examples/` (`#!/usr/bin/env bs` with strict mode and `load "group/module"`).
3. If the module introduces new documented behavior, update both `documentation/en/` and `documentation/ru/` (see `bs-docs-sync` skill).
4. Run the full validation cycle (see `bs-validate` skill):
   ```bash
   bash tests/validatesyntax.sh
   bash tests/validateshellcheck.sh
   bash tests/runalltests.sh
   ```
