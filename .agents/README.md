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

## skills/ — reusable workflows (12)

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