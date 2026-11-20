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

## skills/ — reusable workflows by tier

Полный каталог с определением tier и группировкой — **[skills/README.md](skills/README.md)**.
Каждый bs-скилл несёт поле `tier:` во frontmatter; плоская раскладка каталогов
сохраняется для обнаружения скиллов. Полный каталог — в skills/README.md.

| Tier | Скиллы |
|---|---|
| `posix` (ядро) | `bs-kernel-code`, `bs-new-core-module`, `bs-posix-output` |
| `bash4` (lib/) | `bs-new-lib-module`, `bs-device-module`, `bs-debug-logging` |
| pre-kernel | `bs-pre-kernel-namespace`, `bs-pre-kernel-boundary` |
| doctrine (о ярусах) | `bs-shell-portability`, `bs-shell-abstraction`, `bs-docs-shell-claims` |
| both | `bs-object-class`, `bs-regex`, `bs-write-test`, `bs-review-module`, `bs-variable-docs`, `bs-variable-metadata`, `bs-check-ansi`, `bs-code-review-security`, `bs-cli-style`, `bs-cli-flags-style`, `bs-cli-noop-output`, `bs-cli-markdown-style`, `bs-scenario-audit` |
| meta (процесс) | `bs-validate`, `bs-version-bump`, `bs-docs-sync`, `bs-commit-style`, `bs-commit-pro`, `bs-audit`, `bs-check-docs-code`, `bs-check-artifacts`, `bs-ai-toolchain`, `bs-code-design` |
| импортированные (verbatim) | `posix-shell` (posix), `bash-defensive-patterns` (bash4), `shell` (both), методические и инженерные скиллы (meta) — классификация в skills/README.md, файлы не редактируются |

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
