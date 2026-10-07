# AI Agent Guide — BS Framework

> Instructions for AI assistants, coding agents, and LLM-based tools working with the BS Bash framework.

## What is BS?

BS is a modular Bash 4.2+ framework and standard library. It provides:

- `bs` — shebang interpreter and CLI (`#!/usr/bin/env bs`)
- `bootstrap/loader.sh` — module loader with dependency resolution (`load "lib/io/streams"`)
- `bootstrap/bs.sh` — pre-kernel root namespace: dependency-free helpers available
  before the loader (shell detection `bs::shell::*`, `bs::script_dir`, PATH tweak);
  sourced by entry points, `bootstrap/init.sh` and the loader itself
- `core/` — framework kernel: `args`, `logger`, `errorhandler`, `const`, `utils`, `version`, `config`, `deps`, `prereq`, `lang`
- `lib/` — standard library: `io/streams`, `io/files`, `io/process`, `system/*`, `integration/*`, `ui/*`, etc.
- `tests/` — custom test framework, ShellCheck validation, syntax validation

All modules are Bash 4.2+ scripts. No external dependencies are required at runtime.

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
- Single unix-like style everywhere: `lower_snake_case` + `module::` namespaces; CamelCase/mixedCase are never used (see code-style-guide §2.1).
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

- `.agents/prompts/lib-prompt.md` — implement or modify `lib/` modules.
- `.agents/prompts/core-prompt.md` — implement or modify `core/` modules.

## Agent skills

Reusable workflow skills live in `.agents/skills/` (Kimi Code / agents-compatible format):

- `bs-new-lib-module` — scaffold a new `lib/` module (skeleton, guard, `@depends`, metadata).
- `bs-new-core-module` — add a `core/` module and register it in `bootstrap/init.sh` + `bs doctor`.
- `bs-pre-kernel-namespace` — write/edit functions in `bootstrap/bs.sh` (dependency-free helpers usable before the loader).
- `bs-pre-kernel-boundary` — check that pre-load code uses no core/lib abstractions; after load they are required.
- `bs-variable-docs` — check that module-level variables carry a bilingual `# @global` snippet naming their category (code-style-guide §4.2).
- `bs-write-test` — unit/integration test skeleton and `testframework.sh` assert API.
- `bs-validate` — the mandatory validation cycle after any change.
- `bs-docs-sync` — keep `documentation/en/` and `documentation/ru/` in sync.
- `bs-commit-style` — commit message conventions and history-safety rules.
- `bs-commit-pro` — professional commit engineering (atomic intent, staging discipline, bisect/revert safety, series ordering).
- `bs-review-module` — skeptical critic pass over a module (bash-pitfalls checklist, §11 lens, prioritized doubt report).
- `bs-check-artifacts` — scan for traces of unfinished AI generation and leakage of request/prompt text into code and docs.
- `bs-cli-markdown-style` — apply the «markdown simplicity» principle to CLI/interface/output/docs design (7-criteria test, Russian).
- `bs-cli-noop-output` — «nothing to do» output for BS CLI commands: framed bilingual «…НЕТ / NO …» box with per-item reasons and next-step hints instead of raw WARN/ERROR; up-to-date detection before redoing work; character-based frame padding (printf %-*s pads by bytes and breaks Cyrillic borders); exit 0 for no-ops, exit 1 for real failures.
- `bs-device-module` — write Linux device/hardware modules (evdev/sysfs, binary decoding, test hooks, graceful degradation).
- `bs-ai-toolchain` — operate BS as an AI toolbox (discovery ladder, verification loops, generation contracts).

### Imported methodology skills (external, verbatim)

General agent-workflow skills imported from [obra/superpowers](https://github.com/obra/superpowers)
(MIT) and [anthropics/skills](https://github.com/anthropics/skills) (Apache-2.0);
kept as-is, cross-references between them are intact:

- `brainstorming` — refine intent/design before writing code
- `writing-plans` — bite-sized implementation plans (file paths, verification steps)
- `executing-plans` — inline plan execution with review
- `test-driven-development` — RED-GREEN-REFACTOR cycle
- `requesting-code-review` / `receiving-code-review` — review workflow by severity
- `systematic-debugging` — 4-phase root-cause process
- `verification-before-completion` — prove the fix, then finish
- `writing-skills` — authoring skills as TDD over process documentation
- `using-superpowers` — meta intro (required background for the others)
- `dispatching-parallel-agents` — concurrent subagent workflows
- `subagent-driven-development` — per-task subagents with two-stage review
- `using-git-worktrees` / `finishing-a-development-branch` — branch hygiene

### Imported engineering skills (external; helper scripts rewritten to BS)

Imported from [alirezarezvani/claude-skills](https://github.com/alirezarezvani/claude-skills).
The repo is **Python-free**: helper scripts of these skills were ported from
Python to BS-native Bash (`scripts/*.sh`, same CLI/exit-code contract, invoked
as `bash scripts/<name>.sh`); skills whose tooling is inherently Python-bound
were removed (2026-10-07):

- `zero-hallucination-coder` — Discuss→Map→Decompose→Execute→Verify discipline
- `named-persona-adversarial-review` — code review through named, sourced engineering philosophies
- `pr-review-expert` — blast radius, security scan, coverage delta PR review
- `changelog-generator` — Conventional Commits → CHANGELOG.md (used for `CHANGELOG.md`; bash scripts)
- `write-a-skill` / `grill-me` / `handoff` — skill authoring, plan review, work handoff (bash scripts)
- `git-worktree-manager` — worktree lifecycle with automation scripts (bash scripts)
- removed: `skill-creator` (eval machinery), `skill-doctor` (Claude/Codex log
  parsing), `ci-cd-pipeline-builder`, `codebase-onboarding`,
  `tech-debt-tracker`, `mcp-server-builder`, `skill-security-auditor`

## MCP / API provider suggestions

- **MCP**: expose `bs` CLI commands (`bs doctor`, `bs list`, `bs run`) plus the validator/test scripts as tools.
- **API providers**: any LLM with function-calling / tool-use support can invoke the validation tools to verify generated code. Examples: OpenAI GPT, Anthropic Claude, Kimi, DeepSeek, Google Gemini, and local models via Ollama/vLLM.
- **Context compression**: when the full repo is too large, provide only `AGENTS.md`, the target module, its tests, and `code-style-guide.md`.
