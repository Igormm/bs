# Nushell examples

Parse-clean fragments for [`reference/nushell.md`](../../reference/nushell.md).

Unlike the Bash examples, Nushell examples are **not** split into good/bad files.
Every `*.nu` must pass `nu --ide-check` (verified by `task nushell`), and a file
that failed on purpose would break that gate. So these files show the **correct**
pattern; the anti-pattern is described in a comment and, for the classic startup
bug, demonstrated at runtime in
[`tests/nushell-startup-demo.sh`](../../tests/nushell-startup-demo.sh).

| File | Shows |
|------|-------|
| `01-optional-cell-path.nu` | `get -o` returns `null` for a missing column instead of erroring |
| `02-structured-data.nu` | filter/sort/select on a typed table, no text munging |
| `03-typed-command.nu` | a typed `def` with a `--flag` and an input/output signature |
| `04-error-handling.nu` | `try`/`catch` plus an optional cell path with `default` |

```sh
# Static-check:
task nushell
# Run one:
nu examples/nushell/01-optional-cell-path.nu
```
