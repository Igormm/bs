# .agents — AI workspace / Рабочее пространство ИИ

Central place for everything AI-facing in the repo (replaces the old `ai/` directory).
Центральное место для всего ИИ-направленного в репозитории (заменяет старый каталог `ai/`).

## Structure / Структура

```
.agents/
├── skills/     workflow skills (Kimi Code / agents-compatible SKILL.md format)
├── prompts/    role prompts for AI coding agents (core / lib)
└── guides/     human-facing guides: MCP, using BS with AI, toolchain, TS dev
```

## skills/ — reusable workflows (22)

| Skill | Purpose |
|---|---|
| `bs-new-lib-module` | scaffold a new `lib/` module |
| `bs-new-core-module` | add a `core/` module + registration |
| `bs-write-test` | unit/integration test skeleton + assert API |
| `bs-validate` | mandatory validation cycle |
| `bs-docs-sync` | keep en/ru documentation in sync |
| `bs-commit-style` | commit message conventions + history safety |
| `bs-commit-pro` | professional commit engineering (atomic intent, staging) |
| `bs-review-module` | skeptical critic pass (bash pitfalls, §11 lens) |
| `bs-audit` | full project audit chain: validation, docs snippets, artifacts, en/ru sync, module review |
| `bs-check-docs-code` | code snippets in docs vs framework reality |
| `bs-check-ansi` | ANSI escape usage across the project |
| `bs-cli-flags-style` | flags/values structure of CLI scripts on top of `core/args` (RU) |
| `bs-cli-noop-output` | framed bilingual «nothing to do» output for CLI commands |
| `bs-debug-logging` | debugging interactive scripts, never-without-a-log guarantee (RU) |
| `bs-pre-kernel-namespace` | functions in `bootstrap/bs.sh` usable before the loader |
| `bs-pre-kernel-boundary` | pre-loader code must not use core/lib abstractions |
| `bs-variable-docs` | bilingual `# @global` snippets for module-level variables |
| `bs-scenario-audit` | scenario-driven logic audit: six-part scenario card, actual vs expected, function inventory by risk |
| `doc-coauthoring` | co-authoring docs in three stages: context, section-by-section refinement, reader testing (imported from anthropics/skills) |
| `bash-defensive-patterns` | defensive Bash patterns (imported from wshobson/agents, MIT): strict mode, quoting, traps, temp files, idempotency |
| `bs-code-review-security` | security-first review: injection, quoting, paths, temp files, privilege, `@shell` tier, tests, P0–P3 report (adapted from DataDog/rshell, Apache-2.0) |
| `bs-shell-portability` | shell-independence of BS: host/user/script shell, `@shell` tiers, trampoline, `tier_scan.sh`, `probe_shells.sh` |
| `bs-shell-abstraction` | the shell dependency is set by the `@shell` tier; `find_leaks.sh`, `check_posix_tier.sh` (bash does not take part in `posix`) |
| `bs-docs-shell-claims` | fix documentation that says the whole kernel needs bash 4 when only the `bash4` tier does |
| `bs-check-artifacts` | AI-generation traces + request-text leakage scan |
| `bs-cli-markdown-style` | markdown-simplicity principle for CLI/output/docs (RU) |
| `bs-device-module` | Linux device/hardware modules (evdev/sysfs) |
| `bs-ai-toolchain` | operate BS as an AI toolbox |

## prompts/ — role prompts

- `core-prompt.md` — implement/modify `core/` kernel modules (Russian + English).
- `lib-prompt.md` — implement/modify `lib/` feature modules.

## guides/ — human-facing guides

- `using-with-ai.md` — how humans work with BS through LLMs/agents.
- `mcp-integration.md` — MCP server / API provider / CI ideas.
- `toolchain.md` — BS as an AI toolchain: what exists, what to build.
- `ts-development.md` — BS as the operating layer for a local TS stack.
- (analysis drafts live in `.art/`, e.g. `webserver-analysis.md`)

## Conventions / Конвенции

- Skills: `SKILL.md` with frontmatter `name/description/type/whenToUse/arguments`.
- Prompts and guides are bilingual where the repo convention requires it.
- Register new skills in `AGENTS.md` (skills list).
