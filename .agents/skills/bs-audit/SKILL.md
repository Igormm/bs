---
name: bs-audit
description: Full project audit of the BS framework — run the validation cycle (syntax, ShellCheck, tests), docs-code snippet check, AI-artifact scan, en/ru docs sync, and a skeptical module review, then produce a triaged verdict. Use before releases, after big merges, or when the user asks for a full audit
type: prompt
whenToUse: Before a release, after a large merge, when the user asks for a full audit of the project, or periodically to verify framework health
arguments:
  - modules
---

Run the full BS framework audit as a chain of stages. Each stage either passes, reports findings to triage, or fails hard. Do not fix anything unless asked — audit reports first.

# Stage 0 — Repository state

```bash
git status --short
git log origin/main..main --oneline        # unpushed commits
```

Report: clean/dirty tree, unpushed commits. A dirty tree is a note, not a blocker — audit whatever is in the working tree.

# Stage 1 — Validation cycle (bs-validate)

```bash
bash tests/validatesyntax.sh
bash tests/validateshellcheck.sh
bash tests/runalltests.sh
```

- **Hard gate**: any failure here is a finding that must be fixed before anything else.
- Report: counts (files checked, tests run/passed/failed/skipped).

# Stage 2 — Docs code snippets (bs-check-docs-code)

```bash
bash tests/validatedocscode.sh
```

Triage each finding (see the bs-check-docs-code skill for the full classes):

| Class | Verdict |
| --- | --- |
| `load` path missing, unknown function, snippet/file mismatch | Real drift — fix or list as must-fix |
| `set -euo pipefail` in bs script, `source` instead of `load` | Real convention drift — fix |
| `some::failing_command`, `lib/system/foo`, migration old APIs | Intentional — accept |
| `examples/README.md` BOSA legacy names | Known-stale — cleanup candidate |

# Stage 3 — AI artifacts and leakage (bs-check-artifacts)

Run the artifact scan (prompt-based part; commands below are the automated half):

```bash
rg -l -U $'\r' --glob '*.sh' --glob '*.md'                 # CRLF
rg -n "[\x{200B}\x{200C}\x{200D}\x{FEFF}\x{00AD}]" --glob '*.sh' --glob '*.md'  # zero-width/BOM
rg -n -i "your code here|placeholder|foobar|stub|dummy|lorem ipsum" --glob '!ai/**' --glob '!.agents/**' --glob '!review/**' --glob '!.art/**'  # placeholders
git ls-files | rg -i "\.(bak|tmp|old|orig|swp)$|~$|\.(txt|log)$"               # stray files
```

Then the judgment part: scan changed/new files for LLM conversational filler ("here is", "as an ai", "let's", "i hope"), imperative request-style text in docs ("create a", "the user wants"), and — if the request/prompt texts that produced the code are available — verbatim phrase leakage (exempt `ai/*.md` and `.agents/skills/*/SKILL.md`).

# Stage 4 — Bilingual docs sync (bs-docs-sync)

Compare each `documentation/ru/**` file with its `documentation/en/**` twin.
Section titles differ by language by design (ru vs en headers) — compare
structure by section COUNT, not by title names:

```bash
for f in documentation/en/**/*.md; do
  ru="$(printf '%s' "$f" | sed 's#/en/#/ru/#')"
  [[ -f "$ru" ]] || echo "MISSING RU: $ru"
done
for f in documentation/en/**/*.md; do
  ru="$(printf '%s' "$f" | sed 's#/en/#/ru/#')"
  dr="$(grep -c '^## ' "$ru")"; de="$(grep -c '^## ' "$f")"
  [[ "$dr" != "$de" ]] && echo "SECTION COUNT DIFF: $ru ($dr) vs $f ($de)"
done
```

Findings: missing twin (one language lacks the page) or section-count drift
(a behavior described in one language only). Accept wording differences and
title translations.

# Stage 5 — Skeptical module review (bs-review-module)

Pick modules: `${modules}` argument if given; otherwise the most recently changed modules (`git log --oneline -5 --name-only | rg '\.(sh)$' | sort -u | head -5`), plus the framework kernel (`core/`, `bootstrap/`).

For each module, a skeptical pass over:
- bash pitfalls: unquoted vars, `(( var++ ))` under `set -e`, `IFS` leakage, globbing, subshell surprises
- conventions: guard via `bs::guard`, `bs::source_relative`, `is::*` predicates, `error::throw`, no raw `echo`/redirects in lib code
- `@global` doc snippets for module-level variables (bs-variable-docs)
- pre-kernel boundary: bootstrap/bs.sh and pre-loader code must not use core/lib abstractions (bs-pre-kernel-boundary)

Output a prioritized doubt list per module — no fixes.

# Stage 6 — Verdict

```
## bs-audit: <date>
Stage 0: <state>
Stage 1: <pass/fail, counts>
Stage 2: <findings count, triage summary>
Stage 3: <findings count, classes>
Stage 4: <missing twins, structure drift>
Stage 5: <doubts per module>

## Must fix
- <file>:<line> — <issue>

## Should fix
- ...

## Accepted / intentional
- ...

## Verdict: <PASS | PASS WITH NOTES | FAIL>
```

Verdict rules: any Stage 1 failure or Stage 2 real drift → **FAIL**. Only intentional/known findings → **PASS WITH NOTES**. Nothing → **PASS**.