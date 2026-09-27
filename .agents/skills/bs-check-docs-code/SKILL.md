---
name: bs-check-docs-code
description: Verify that bash code snippets in README.md, documentation/ and examples/*.md are consistent with framework reality — conventions (no redundant set -euo pipefail in bs scripts), existing load paths, real module APIs, and the actual example files they reference
type: prompt
whenToUse: After editing README/docs code snippets, after adding or renaming example scripts or module functions, before committing doc changes, or when the user asks to check docs-code drift
arguments:
  - scope
---

Check `${scope}` (default: whole repo docs) for **docs-code drift**: snippets that contradict framework conventions, call nonexistent APIs, load nonexistent modules, or diverge from the real `examples/` files they claim to show. ShellCheck and syntax validation do NOT catch this class — they only check syntax, not conventions or existence.

# Step 1 — Run the checker script

```bash
bash tests/validatedocscode.sh
```

This is the primary tool. It scans all `bash` code blocks in `README.md`, `documentation/**/*.md` and `examples/*.md` and reports:

- **A** `ERROR` — `load "X"` does not resolve to `X.sh` (core/ or lib/)
- **B** `WARN` — `module::func` call not found in the loaded modules, the snippet's own definitions, or the full framework index
- **C** `WARN` — `set -euo pipefail` / `IFS=` in a `#!/usr/bin/env bs` snippet (the interpreter enables strict mode before sourcing — see code-style-guide §1.1)
- **D** `ERROR` — direct `source` of a core/lib/bootstrap module instead of `load` (in `bs`-shebang blocks)
- **E** `ERROR` — snippet referencing `examples/X.sh` does not match the real file (comments, blank lines, guard block, `main()` wrapper, indentation and omitted lines are ignored; block lines must appear in the file in the same order)

# Step 2 — Triage the findings

The script intentionally reports honest findings; not every finding needs a fix. Classify each one:

## 2.1 Real drift — fix it

- A snippet contradicts a documented convention (e.g. `set -euo pipefail` in a `bs` script, `source` instead of `load`).
- A snippet calls a function that does not exist in any module → the doc invents an API, or the module was renamed — fix the doc or the module.
- A snippet diverges from the `examples/` file it references (removed line, changed argument, renamed function). Fix the snippet to match the file — the file is the source of truth.
- `load` paths that point to deleted/renamed modules.

## 2.2 Intentional content — accept, no fix

| Finding | Why it's fine |
| --- | --- |
| `some::failing_command` in test templates | Illustrative fake command in `assert_false` examples |
| `load "lib/system/foo"` in 08-development | Teaching example of the module-loading convention with a placeholder name |
| `logger::info` / `logger::debug` in 09-migration-bosa-to-bs.md | Old BOSA API shown intentionally to teach the migration |
| Excerpt divergences in 03-modules docs (e.g. `action=...` without `local` in args.md) | Simplified excerpt with a link to the full example file; judge if worth fixing |
| `set -euo pipefail` / `source testframework.sh` in test-file templates (07-testing, code-style-guide) | Test files are entry points that set strict mode themselves — the checker exempts blocks that source testframework/bootstrap |

## 2.3 Known-stale legacy docs — cleanup candidate

`examples/README.md` still uses the old BOSA naming (`bosa::init`, `telegramintegration`). These findings are correct; the file is known-stale (the 06-examples docs note it). Fix or mark as a cleanup task — do not silently ignore.

# Step 3 — Verify a fix

Re-run the script and confirm the finding is gone and no new ones appeared:

```bash
bash tests/validatedocscode.sh
```

# Manual spot-checks the script cannot do

- **Semantics**: the script checks function existence, not argument semantics. E.g. `args::required 2` with a free-form positional value is invalid — `core/args` validates positionals by exact name match; free-form values must be value flags (`args::flag name value`). Run self-contained snippets via `./bs run` to verify behavior when in doubt.
- **Bilingual sync**: en/ru snippets should show the same code (see `bs-docs-sync`).
- **Fragments**: tutorial step fragments (no shebang) are checked for `load`/API only; judge convention rules by context.

# Output format

```
## bs-check-docs-code: <scope>
- <file>:<line> [ERROR|WARN] <finding>
...
## Triage
- <file>:<line> — real drift, fixed / intentional, accepted / stale, cleanup candidate
## Verified clean
- <area> — checked, no findings
```

Do not fix anything unless asked — report first, then fix on request.