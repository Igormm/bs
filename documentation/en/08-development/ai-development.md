# AI-assisted development

BS is a Bash framework with strict conventions. LLMs and agents can write modules effectively when given the right context and prompts.

## Quick start for AI developers

1. Read `AGENTS.md` in the repository root.
2. Read `documentation/en/code-style-guide.md`.
3. For `lib/` tasks use the prompt in `ai/lib-prompt.md`.
4. For `core/` tasks use the prompt in `ai/core-prompt.md`.
5. For MCP, provider and CI ideas read `ai/mcp-integration.md`.
5. After changes run:
   ```bash
   bash tests/validatesyntax.sh
   bash tests/validateshellcheck.sh
   bash tests/runalltests.sh
   ```

## How to shrink the context

If the repository is too large for the model's context window, provide only:

- `AGENTS.md`
- `documentation/en/code-style-guide.md`
- the target module and its tests
- related modules (via `# @depends`)

## Prompts

### For lib/ development

```text
You are an expert Bash developer working with the BS framework. Implement a function in lib/<group>/<module>.sh.

Requirements:
- Use shebang #!/usr/bin/env bs and # shellcheck shell=bash
- Idempotency via bs::guard
- Dependencies via bs::source_relative
- Public functions use namespace group::module::function
- No external dependencies; Bash 4+ and standard Unix tools only
- Add a unit test in tests/unit/test<module>unit.sh
- Validate with validatesyntax.sh, validateshellcheck.sh, runalltests.sh

Describe what the function should do: ...
```

### For core/ development

```text
You are an expert Bash developer maintaining the BS framework core. Modify core/<module>.sh.

Requirements:
- Do not source core/prereq.sh — bs::guard and bs::source_relative are available a priori
- Use shebang #!/usr/bin/env bash
- Minimize dependencies on other core modules
- Maintain backward compatibility of public API
- Add/update unit tests and core-api.md documentation
- Validate with validatesyntax.sh, validateshellcheck.sh, runalltests.sh

Describe the task: ...
```

## MCP and API provider integration

### MCP (Model Context Protocol)

Recommended tools to expose:

- `bs doctor` — framework integrity check
- `bs list` — list modules
- `bs run <script> [args...]` — run scripts
- `bash tests/validatesyntax.sh` — syntax validation
- `bash tests/validateshellcheck.sh` — ShellCheck validation
- `bash tests/runalltests.sh` — run test suite

### API providers

Any LLM with function calling (or tool use) can invoke the validators to verify generated code. The major providers all fit the same loop:

1. Model generates code from a request.
2. Agent calls `validatesyntax.sh`.
3. Agent calls `validateshellcheck.sh`.
4. Agent calls `runalltests.sh`.
5. If errors exist, the model receives the output and fixes the code.

Examples of supported provider families:

- **OpenAI GPT** — function calling (GPT-4o, GPT-4.1, o3, etc.)
- **Anthropic Claude** — tool use (Claude 3.5/4 Sonnet, Opus)
- **Kimi** — function calling (Moonshot AI, e.g. Kimi k1.5)
- **DeepSeek** — function calling / reasoning (V3, R1)
- **Google Gemini** — function calling (1.5/2.0 Pro/Flash)
- **Local models** — tool use via Ollama, vLLM, llama.cpp

### Context tips

- For small tasks, `AGENTS.md` + the target file is enough.
- For new modules, add `code-style-guide.md` and examples from `examples/`.
- For integration modules, add `lib/integration/result.sh` as a reference.

## What to avoid

- Do not introduce external dependencies (Python, Node, jq) without agreement.
- Do not mutate git history (`git rebase`, `git reset`, force-push) without explicit permission.
- Do not add `set -euo pipefail` to library modules.
