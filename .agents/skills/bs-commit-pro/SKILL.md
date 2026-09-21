---
name: bs-commit-pro
description: Professional commit engineering - atomic intent, staging discipline, bisect/revert safety, message anatomy, series ordering; the repo's dense "subject; clarifiers" convention
type: prompt
whenToUse: When preparing, splitting or reviewing git commits for real: multi-file changes, mixed work trees, commit series, or when a commit must survive blame/bisect/revert months later; goes beyond bs-commit-style (format) - this skill is about the engineering of history
arguments: []
---

A commit is a unit of review, a bisect step and a revert target. Optimize for
all three, in the repo's voice.

## 1. Atomicity by intent, not by file

One commit = one logical change ("why"), even if it touches several kinds of
files. Correctly atomic examples:
- module + its unit tests + its docs (en+ru) - one commit: the tests and docs
  belong to the feature; splitting them leaves dead states between commits.
- Wrong: `feat: X` then separate `test: tests for X` - bisect lands on a commit
  where X has no tests and the follow-up is noise.
Split into separate commits when the *why* differs: a refactor that enables the
fix = two commits (refactor first, alone, verifiable). Drive-by formatting of
files you didn't change = separate `style` commit or drop it.

## 2. Staging discipline

```bash
git status --short            # what exists
git diff                      # what you actually changed
git add <explicit paths>      # NEVER git add -A in a dirty tree
git diff --staged             # review the exact snapshot being committed
```
- `git add -A` is how secret files, `.env`, editor cruft and half-baked
  experiments reach `main`. Add paths you have looked at.
- Partial change from a mixed file: `git add -p` (hunks), or stop - the tree
  is telling you the change is not atomic.
- Untracked new files: `git status --short` lists them with `??` - decide each
  one; silence surprises with .gitignore, not by forgetting.
- Never commit: debug copies (`_dbg_*`), tmp fixtures, `/tmp` leftovers copied
  in, generated caches, anything matched by `git check-ignore` exceptions.

## 3. Gates before, not after

The tree must be green AT EVERY COMMIT, not just at HEAD (bisect/revert
depend on it):
```bash
bash tests/validatesyntax.sh && bash tests/validateshellcheck.sh && bash tests/runalltests.sh
```
A failing gate is a bug, not a footnote: fix before commit; do not commit a
known-red state with "will fix next commit" - next commit may be someone
else's. Do not skip slow suites for "docs-only" changes without checking that
the validator scans your file type.

## 4. Message anatomy (repo convention)

Subject: `type(scope): what changed` - imperative, ≤ ~72 chars where possible;
this repo allows dense semicolon clarifiers when one intent has several
observable effects:
```
fix(ssh): strict validation of --port/--key (no rsync -e injection, no option-injection via leading dash)
```
Rules distilled from history:
- Name the SCOPE as the module/area (`fix(hw)`, `test(lsp)`, `docs(sensor)`),
  never `misc`, `various`, `update`.
- Say WHAT IS NOW TRUE, not what you did: "no crash on zero-flag tree", not
  "fixed the crash".
- Put the WHY/constraint in parentheses or the body when the subject would get
  vague: "(ranking shifted by new regex docstrings)".
- One subject per intent: if you need `feat: A; fix: B; docs: C` across
  unrelated intents - that is three commits. Semicolons join facets of ONE
  intent (feature + its tests + its docs), not separate tickets.
- Body: for non-trivial commits add why, alternatives rejected, and links
  (`Refs #123`, `Co-authored-by:`). Subjects carry the headline; bodies carry
  the reasoning.
- No "AI-generated"/"as requested"/prompt text in messages (see
  bs-check-artifacts); no jokes unless asked.

## 5. Series hygiene

When a change needs several commits:
1. Order so that every intermediate commit builds+passes gates (tests can come
   WITH the code, never before it).
2. Dependency direction: core → lib → examples → docs. Revert of a later
   commit must not orphan an earlier one.
3. No empty commits, no `wip`, no "fix typo in previous commit" - if you catch
   it before anyone else's pull, the uncommitted state was yours to fix.
4. History mutation (rebase/`commit --amend`/force-push) is forbidden by
   AGENTS.md unless the user explicitly asks; when they do ask - only on
   unpushed commits.

## 6. The 60-second self-review

Before `git commit`, answer:
- [ ] `git diff --staged` - every line belongs to THIS intent?
- [ ] Could a stranger bisect to this commit and see a complete reason?
- [ ] Would `git revert HEAD` be safe and sufficient?
- [ ] Subject readable alone in `git log --oneline`?
- [ ] Gates green? Files staged by name? No secrets (`git diff --staged | grep -iE 'passw|token|secret|\.pem'` as a reflex)?

## Anti-patterns (seen in the wild, keep out)

- Sweeping commits (several intents joined by `;` where each could be reverted
  alone).
- "Update files", "fixes", "minor changes" - a bisect tombstone.
- Committing the debug scaffolding that made the fix possible.
- Mixing line-ending/format churn with behavior change.
- Commit messages written as a changelog of files ("added foo.sh, edited
  bar.sh") - the diff already says that; the message says why.
