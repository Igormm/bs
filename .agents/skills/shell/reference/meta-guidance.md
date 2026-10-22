# Meta-guidance: when (not) to use shell

The most important shell skill is knowing the language's edges. Shell is
unbeatable as *glue* — launching processes, wiring pipes, reacting to exit codes.
It is a poor general-purpose language. Reach for it deliberately, not by default.

## Prefer a real language (Python, Go, …) when you hit any of these

- **The script is growing past ~100 lines**, or has grown a second level of
  functions calling functions.
- **You need real data structures** — nested maps, records, anything beyond flat
  strings and arrays.
- **You need arithmetic beyond integers**, or any floating point.
- **You parse or emit structured formats** — JSON, YAML, CSV, XML. Shell string
  munging of these is a bug farm.
- **You need robust error handling** with context, retries, or cleanup that
  `trap` cannot express cleanly.
- **You need tests.** Unit-testing shell is possible (bats) but painful compared
  to a language with a real test framework.
- **It must run on Windows** without WSL.

A 300-line Bash script with associative arrays and manual JSON parsing is a
rewrite waiting to happen. Write it in Python or Go the first time.

## When you do stay in shell, use structured tools

Do not hand-roll parsing with `sed`/`awk`/`cut` when a structured tool exists:

| Instead of | Use |
|-----------|-----|
| `grep`/`sed`/`awk` over JSON | [`jq`](https://jqlang.github.io/jq/) |
| the same over YAML | [`yq`](https://github.com/mikefarah/yq) |
| column-counting with `awk` | [Nushell](https://www.nushell.sh/) pipelines |
| `curl \| grep` scraping HTML | a language with an HTML parser |

These tools understand the data's structure, so they do not break when
whitespace, quoting, or field order changes.

## A 30-second decision checklist

1. Is this mostly *launching commands and moving files*? → shell is fine.
2. Does it manipulate structured data or need real types? → not shell.
3. Will it outlive this week or be maintained by others? → lean away from shell.
4. Would you be embarrassed to skip tests for it? → not shell.

When you do write shell, write it to the standards in
[`shell-standards.md`](shell-standards.md) — so that the scripts you *do* keep
are the safe kind.

## Further reading

- Google Shell Style Guide, *"When to use Shell"* —
  <https://google.github.io/styleguide/shellguide.html>
