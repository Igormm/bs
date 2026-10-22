# Streams examples

Runnable good/bad pairs for [`reference/streams.md`](../../reference/streams.md).
`*.good.sh` runs to exit 0; `*.bad.sh` is safe and declares the ShellCheck code
it triggers (or `none` for a rule the linter cannot enforce).

| Pair | Good shows | Bad shows | Code |
|------|-----------|-----------|------|
| `01-errors-to-stderr` | diagnostics to stderr, data to stdout | a warning polluting stdout | none |
| `02-read-lines` | `while IFS= read -r line` | `for line in $(cat file)` | `SC2013` |
| `03-redirection-order` | `>file 2>&1` (both to file) | `2>&1 >file` (stderr escapes) | `SC2069` |

The `01` pair carries `none` deliberately: ShellCheck cannot tell that a message
went to stdout instead of stderr, so it is a review rule, not a lint rule.
