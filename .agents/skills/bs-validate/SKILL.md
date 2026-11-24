---
name: bs-validate
description: Run the full BS framework validation cycle (syntax, ShellCheck, all tests) and the version check, and interpret the results after any code change
type: prompt
whenToUse: After any change to project code, before committing, or when the user asks to check/verify/validate the project — including checking that the version was bumped with the change
tier: meta
---

Run the three mandatory validators from the project root, in this order (AGENTS.md requires all three after ANY change):

```bash
bash tests/validatesyntax.sh
bash tests/validateshellcheck.sh
bash tests/runalltests.sh
```

## Version (do not skip it)

A user-visible `feat`/`refactor`/`fix`/`perf` change must bump the version in the
same change, never as a separate "later" step — that is exactly how the release
heading gets forgotten. The single source is `core/version.sh`; everything else
just repeats the number.

```bash
bash .agents/skills/bs-version-bump/scripts/version.sh check   # 0 drift = consistent
```

- `feat`/`refactor`/`perf` → **minor**; a breaking change → **major**; only
  `fix`/`docs`/`test`/`chore` → **patch**.
- If a bump is needed, follow the `bs-version-bump` skill: bump `core/version.sh`,
  rename the CHANGELOG `## [Unreleased]` heading, update the repeated numbers
  (en/ru architecture, en/ru core-api, `tests/unit/testbsnobashunit.sh`), run
  `version.sh check`, then commit as `chore(release): X.Y.Z "Codename"; …`.

## What each one does

- `tests/validatesyntax.sh` — `bash -n` syntax check on required entry points (`bs`, `boot.sh`, `install.sh`, `bootstrap/*`) and all `*.sh` in `core/ lib/ install/ tests/`. Note: `examples/` is NOT covered — check changed example scripts manually with `bash -n`. Exit 1 on errors.
- `tests/validateshellcheck.sh` — ShellCheck `-s bash --severity=error` over all `*.sh` plus `./bs`. Config in `.shellcheckrc` (`external-sources=false`, SC1090/SC1091 disabled): every file is checked directly, so following sources only re-parsed the kernel. Files are checked in balanced batches on `-P` cores; `SHELLCHECK_JOBS=1` forces serial. `--warnings` gives an informational run that does not fail the build.
- `tests/runalltests.sh` — runs every test suite under `tests/` via `bash <script>`. Serial by default; `--jobs N` or `BS_TEST_JOBS=N` enables isolated parallel workers with parent-side aggregation. Root-only destructive tests (testwireguard, testsystemaudit) are skipped unless `--with-root` is passed and EUID=0. Do NOT run `--with-root` without an explicit user request.

## Interpreting results

- All three must pass before reporting a task as done. Never claim success on a red run.
- On failure: read the actual error, fix the root cause, re-run ALL THREE (not just the failed one).
- **Long runs:** the serial `runalltests.sh` pass over 168 unit files plus integrations takes ~20 minutes. Use `bash tests/runalltests.sh --jobs 8` (or `BS_TEST_JOBS=8`) for a parallel pass; keep serial as the reproducibility fallback. `validateshellcheck.sh` is already batched and parallel. Run long checks in the background with a log, do targeted tests in the foreground meanwhile, and read the logs before claiming success. A foreground timeout is not a pass.
- `examples/` and `example_core/` are NOT covered by `validatesyntax.sh` — check changed example scripts manually (`bash -n`, `shellcheck -s bash`, and a real run via `./bs`).
- CI mirrors this in `.github/workflows/ci.yml`: a lint job (syntax + shellcheck) and a tests job across containers (ubuntu, debian, almalinux 9, almalinux 8 = minimum Bash 4.4). If a change could behave differently on Bash 4.4 (associative arrays, `${var@Q}`, etc.), flag it — the local run may use a newer bash.
- `bs doctor` is a useful extra sanity check after touching `core/` or `bootstrap/`.
