---
name: bs-version-bump
description: Bump and verify the BS framework version — the single source core/version.sh, the CHANGELOG release heading, en/ru documentation examples and the hardcoded no-bash test output. Use when cutting a release, when the user asks to update/bump/check the version, or when a version string may be stale.
type: prompt
whenToUse: Before a release, when the user asks to bump or verify the framework version, or after changing BS_VERSION
arguments:
  - version
---

# BS version — bump and check

`BS_VERSION` and `BS_CODENAME` have **one source**: `core/version.sh`.
Everything else (CHANGELOG, docs, tests) only repeats that number and must be
checked after every bump.

## Quick check

```bash
bash .agents/skills/bs-version-bump/scripts/version.sh check
```

Exit 0 means the single source, runtime `bs version`, CHANGELOG heading,
en/ru docs, `tests/unit/testbsnobashunit.sh` and the `mtest/` code-name
fixtures all agree. Any drift is printed
as `DRIFT` with the expected and the actual value.

## Bump

1. Choose SemVer from the commits since the last release
   (`git log --oneline vX.Y.Z..HEAD`): breaking → major, `feat`/`refactor` →
   minor, only `fix`/`docs`/`test`/`chore` → patch.
2. Run the bump (it edits only `core/version.sh`):

   ```bash
   bash .agents/skills/bs-version-bump/scripts/version.sh bump 0.10.0 --codename Vela
   ```

   Without `--codename` the current code name is kept.
3. Edit `CHANGELOG.md`: rename the top release section to
   `## [X.Y.Z] - YYYY-MM-DD "Codename"` (turn `## [Unreleased]` into it when
   that section exists).
4. Update the repeated numbers found by the checker:
   - `documentation/en/02-core-concepts/architecture.md` — `(currently \`X.Y.Z\`)`
   - `documentation/ru/02-core-concepts/architecture.md` — `(сейчас \`X.Y.Z\`)`
   - `documentation/en/04-api-reference/core-api.md` — `(e.g. \`X.Y.Z\`)`
   - `documentation/ru/04-api-reference/core-api.md` — `(например, \`X.Y.Z\`)`
   - `tests/unit/testbsnobashunit.sh` — the expected
     `version=BS Framework version: X.Y.Z` and `help=BS Framework X.Y.Z`
   - `mtest/t_const_version.sh` and `mtest/t_nu.nu` — the code name hardcoded
     as the expected `bs_version_codename` output (only when the code name changes)
5. Run `version.sh check`, then the full `bs-validate` cycle.
6. Commit as `chore(release): X.Y.Z "Codename"; <clarifiers>`.

## Do not touch

Old `0.8.0` values in `tests/unit/testupdatesafetyunit.sh`,
`testuninstallsafetyunit.sh` and `testversion*unit.sh` are **fixtures**
(fake installed repositories and version-comparison cases), not the current
version. Leave them alone.

## Script

`scripts/version.sh` is POSIX-friendly Bash, ShellCheck-clean and has no
dependencies beyond `sed`, `grep` and `bash`. It works from any current
directory and resolves the repository root from its own location.
