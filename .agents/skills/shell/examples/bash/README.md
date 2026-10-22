# Bash examples

Runnable good/bad pairs for [`reference/bash.md`](../../reference/bash.md). The
contract is the same as [`examples/standards/`](../standards/README.md):
`*.good.sh` runs to exit 0 with no arguments and is linter-clean; `*.bad.sh` is
safe to run and declares the ShellCheck code it triggers.

| Pair | Good shows | Bad shows | Code |
|------|-----------|-----------|------|
| `01-mapfile-not-subshell` | `mapfile -t` reads lines safely | `arr=($(...))` word-splits | `SC2207` |
| `02-array-not-scalar` | `"${arr[@]}"` expands all elements | bare `$arr` = first only | `SC2128` |
| `03-quote-args` | `"$@"` forwards args intact | unquoted `$@` re-splits | `SC2068` |
| `04-nullglob-empty-match` | `nullglob` makes an empty match produce zero words | an unmatched glob stays literal | none |
