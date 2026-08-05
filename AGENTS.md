# AI Agent Guide — BS Framework

> Instructions for AI assistants, coding agents, and LLM-based tools working with the BS Bash framework.

## What is BS?

BS is a modular Bash 4+ framework and standard library. It provides:

- `bs` — shebang interpreter and CLI (`#!/usr/bin/env bs`)
- `bootstrap/loader.sh` — module loader with dependency resolution (`load "lib/io/streams"`)
- `core/` — framework kernel: `args`, `logger`, `errorhandler`, `const`, `utils`, `version`, `config`, `deps`, `prereq`
- `lib/` — standard library: `io/streams`, `io/files`, `io/process`, `system/*`, `integration/*`, `ui/*`, etc.
- `tests/` — custom test framework, ShellCheck validation, syntax validation

All modules are Bash 4+ scripts. No external dependencies are required at runtime.

## How AI should work with this framework

1. **Always use the `bs` interpreter or `bootstrap/init.sh`**. Do not source modules directly in new scripts.
2. **Follow the code style guide**: `documentation/en/code-style-guide.md` / `documentation/ru/code-style-guide.md`.
3. **Run validators after any change**:
   ```bash
   bash tests/validatesyntax.sh
   bash tests/validateshellcheck.sh
   bash tests/runalltests.sh
   ```
4. **Add tests** for new public functions or behaviors.
5. **Keep changes minimal**. Prefer small, focused commits.
6. **Do not mutate git history** (no `git rebase`, `git reset`, `git push --force`) unless explicitly asked.

## Module skeleton

```bash
#!/usr/bin/env bs
# shellcheck shell=bash
# lib/group/module.sh — one-line description
# @depends core/const, core/logger, core/utils

# Source Guard
bs::guard "MODULE_NAME" || return 0

# Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# Public API
group::module::function() {
    local -r arg="${1:?argument required}"
    ...
}
```

## Key conventions

- Shebang: `#!/usr/bin/env bs` for library/example scripts; `#!/usr/bin/env bash` for `core/` and entry points.
- Add `# shellcheck shell=bash` on line 2 for `#!/usr/bin/env bs` files.
- Public functions use `module::function` or `module::sub::function` namespaces.
- Constants are `SCREAMING_SNAKE_CASE` and `readonly`.
- Use `bs::guard` for idempotency; never hand-roll `[[ -n "${__X_SOURCED:-}" ]] && return 0`.
- Use `bs::source_relative` for relative dependency sourcing.
- Use `utils::has`, `utils::quiet`, `utils::quiet_err`, `utils::ignore` instead of raw redirects.
- Strict mode (`set -euo pipefail`) is set only in entry points, never in library modules.

## Testing

- Unit tests: `tests/unit/test*unit.sh`
- Integration / system tests: `tests/{integration,network,audit,system,status,data,frameworks}/`
- Use `testframework::assert_equal`, `testframework::assert_true`, `testframework::assert_false`, `testframework::assert_command`.
- New unit tests are auto-discovered by `tests/runalltests.sh` if placed in `tests/unit/`.

## AI workflow

When asked to implement a feature:

1. Read the relevant existing modules and tests.
2. Check `code-style-guide.md` and the relevant API reference.
3. Implement the change.
4. Add or update tests.
5. Run `validatesyntax.sh`, `validateshellcheck.sh`, and `runalltests.sh`.
6. Commit with a clear, concise message; add a joke only if the user asks.

## Role-specific prompts

For focused development tasks, use the dedicated prompt files:

- `.qodo/agents/lib-developer.md` — implement or modify `lib/` modules.
- `.qodo/agents/core-developer.md` — implement or modify `core/` modules.

## MCP / API provider suggestions

- **MCP**: expose `bs` CLI commands (`bs doctor`, `bs list`, `bs run`) plus the validator/test scripts as tools.
- **API providers**: any LLM with function-calling support can invoke the validation tools to verify generated code.
- **Context compression**: when the full repo is too large, provide only `AGENTS.md`, the target module, its tests, and `code-style-guide.md`.
