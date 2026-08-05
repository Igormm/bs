# Using BS with AI assistants

This guide helps human developers work with the BS Bash framework through LLMs and coding agents.

## Quick start

1. Read the agent instructions in the repository root: `AGENTS.md`.
2. Read the code style guide:
   - English: `documentation/en/code-style-guide.md`
   - Russian: `documentation/ru/code-style-guide.md`
3. Use the dedicated prompt files when asking an AI to write code:
   - `ai/lib-prompt.md` — for new or updated `lib/` modules.
   - `ai/core-prompt.md` — for changes to the `core/` kernel.
4. After the AI produces code, always run the validators:
   ```bash
   bash tests/validatesyntax.sh
   bash tests/validateshellcheck.sh
   bash tests/runalltests.sh
   ```

## Detailed guides

- `documentation/en/08-development/ai-development.md` — full English guide.
- `documentation/ru/08-development/ai-development.md` — full Russian guide.
- `ai/mcp-integration.md` — ideas for MCP servers, API providers, CI and security.

## Tips for good results

- Be specific: give the target module path, expected function signature, and example input/output.
- Provide context: attach `AGENTS.md`, the code-style guide, the target module, and its tests.
- Keep requests small: one public function or one bug fix per prompt works best.
- Always review generated code before committing; do not let an AI mutate git history unless you explicitly ask.
