---
name: bs-ai-toolchain
description: Operate BS as an AI toolbox - discovery, introspection, generation contracts, self-verification loops using bs CLI (list, doctor, lang-doc, lsp, run, build, repl)
type: prompt
whenToUse: When an AI agent needs to explore the BS repo efficiently, answer questions about modules without reading them fully, or set up a generate-verify loop; also when asked to integrate BS with agents/MCP/LLM tooling
arguments: []
---

Use the BS CLI as the agent's tool surface. Everything below is read-only or
sandbox-safe; never guess module APIs — introspect them.

## Discovery ladder (cheapest context first)

1. `bs list` — module inventory (core/, lib/).
2. `bs lang-doc` — full JSON index of function docs (`@description/@param/
   @return/@example` docblocks). This is the contract source of truth;
   prefer it over reading module files.
3. Targeted read: only the module + its `tests/unit/test<module>unit.sh` +
   relevant code-style-guide section.
4. `bs repl` — `:list`, `:doc`, `:info` for interactive probing of live
   behavior (`load "lib/..."` then call functions).
5. `bs lsp` — JSON-RPC over stdin/stdout for LSP-capable clients (hover,
   symbols, docs).

## Health and verification loop

After ANY generated change, in this order:

```bash
bash tests/validatesyntax.sh        # cheap parse gate
bash tests/validateshellcheck.sh    # severity=error gate
bash tests/unit/test<module>unit.sh # targeted test first
bash tests/runalltests.sh           # full suite before finishing
```

Iterate until green. A generated module that only "looks right" but skips
validators is a failed task by project rules (AGENTS.md).

## Generation contracts

- Module metadata is machine-readable: `# @depends` drives the loader's
  dependency resolution; keep it truthful or `bs doctor` fails.
- Guard names are deterministic: path → `SCREAMING_SNAKE` (`lib/io/files.sh`
  → `IO_FILES`), loaded flags `<GUARD>_LOADED`, versions `<GUARD>_VERSION` —
  agents can assert module presence in tests.
- For programmatic results use `lib/integration/result.sh` JSON contract
  instead of scraping stdout prose.

## Distribution of agent output

- `bs run ./script.sh` — execute inside the framework environment.
- `bs build ./script.sh` — produce a standalone self-extracting artifact;
  hand this to users/agents on machines without BS installed.

## Anti-patterns

- Reading whole documentation trees to answer one API question — query
  `bs lang-doc` instead.
- Reimplementing framework idioms (raw `command -v`, manual source guards,
  hand-rolled redirects) — use `utils::has`, `bs::guard`, `utils::quiet*`.
- Trusting model memory about bash: bash 4.4 vs 5.x traps differ; the CI
  matrix (ubuntu/debian/almalinux 8-9) is the arbiter — run validators.
