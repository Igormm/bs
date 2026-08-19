---
name: bs-validate
description: Run the full BS framework validation cycle (syntax, ShellCheck, all tests) and interpret the results after any code change
type: prompt
whenToUse: After any change to project code, before committing, or when the user asks to check/verify/validate the project
---

Run the three mandatory validators from the project root, in this order (AGENTS.md requires all three after ANY change):

```bash
bash tests/validatesyntax.sh
bash tests/validateshellcheck.sh
bash tests/runalltests.sh
```

## What each one does

- `tests/validatesyntax.sh` — `bash -n` syntax check on required entry points (`bs`, `boot.sh`, `install.sh`, `bootstrap/*`) and all `*.sh` in `core/ lib/ install/ tests/`. Note: `examples/` is NOT covered — check changed example scripts manually with `bash -n`. Exit 1 on errors.
- `tests/validateshellcheck.sh` — ShellCheck `-s bash --severity=error` over all `*.sh` plus `./bs`. Config in `.shellcheckrc` (`external-sources=true`, SC1090/SC1091 disabled). If shellcheck is not installed it skips silently with exit 0 — mention this to the user when it happens. `--warnings` gives an informational run that does not fail the build.
- `tests/runalltests.sh` — runs every test suite under `tests/` via `bash <script>`. Root-only destructive tests (testwireguard, testsystemaudit) are skipped unless `--with-root` is passed and EUID=0. Do NOT run `--with-root` without an explicit user request.

## Interpreting results

- All three must pass before reporting a task as done. Never claim success on a red run.
- On failure: read the actual error, fix the root cause, re-run ALL THREE (not just the failed one).
- CI mirrors this in `.github/workflows/ci.yml`: a lint job (syntax + shellcheck) and a tests job across containers (ubuntu, debian, almalinux 9, almalinux 8 = minimum Bash 4.4). If a change could behave differently on Bash 4.4 (associative arrays, `${var@Q}`, etc.), flag it — the local run may use a newer bash.
- `bs doctor` is a useful extra sanity check after touching `core/` or `bootstrap/`.
