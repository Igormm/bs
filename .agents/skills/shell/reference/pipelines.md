# Pipelines and text processing

The most common shell mistake is not a quoting bug. It is reaching for
`awk`/`sed`/`cut` when a dedicated tool or a ten-line script would be shorter,
portable, and readable.

## Replacement table

| Task | Reach for | Instead of |
| --- | --- | --- |
| Read a field from JSON | `jq -r .field` | `grep`/`sed`/`cut` on JSON |
| Reshape JSON | `jq` | `awk` |
| Read or edit YAML / TOML / XML | `yq` | any regex |
| Substitute in a file | `sd 'from' 'to' file` | `sed -i 's/from/to/'` |
| Find files | `fd pattern` | `find . -name '*pattern*'` |
| Search contents | `rg pattern` | `grep -r pattern .` |
| Files → sizes → sorted | `nu` | `du` + `sort` + `awk` |
| Case / encoding / hashing of a string | `sttr` | `tr` / `openssl` one-liners |
| Column from a *fixed* delimiter | `cut -d, -f2` | `awk -F, '{print $2}'` |
| Anything with logic, state, or arithmetic | Python / `bun` .ts | a pipeline |

## Why `sed -i` specifically

`sed -i` is the single least portable common invocation:

```bash
sed -i    's/a/b/' f   # GNU: edits in place
sed -i    's/a/b/' f   # BSD/macOS: error — -i needs an argument
sed -i '' 's/a/b/' f   # BSD/macOS: correct
sed -i '' 's/a/b/' f   # GNU: creates a file literally named ''
```

There is no invocation that works on both. Scripts that "work on my machine" and
corrupt files in CI usually contain exactly this line. `sd` takes real regex, needs no
delimiter escaping, and behaves identically everywhere:

```bash
sd 'from' 'to' file.txt
sd -p 'from' 'to' file.txt   # preview
```

## When awk is still right

`awk` is fine for exactly one thing: selecting or summing a column of
whitespace-delimited output.

```bash
awk '{print $2}'            # fine
awk '{s+=$1} END {print s}' # fine
```

The moment it grows a `BEGIN` block, a second pattern, an array, or a regex with
capture groups, it has become a program written in a language nobody on the team
reads. Move it to Python or a `bun` script.

## Structured data deserves a structured tool

Parsing `du`, `ps`, or `ls` output with `awk` re-derives fields the OS already
returned as data. Nushell keeps them typed:

```nu
ls **/*.log | where size > 10mb | sort-by size --reverse | first 10
ps | where cpu > 10 | select pid name cpu
```

The Python equivalent, when logic is involved:

```python
from pathlib import Path
big = sorted(
    (p for p in Path(".").rglob("*.log") if p.stat().st_size > 10 * 1024**2),
    key=lambda p: p.stat().st_size, reverse=True,
)
```

Both beat `du -sk * | sort -rn | head | awk '{print $2}'`, which breaks on the first
filename containing a space.

## Worked rewrite

Fragile — nested substitutions, unquoted expansion, `echo` as a header, breaks on
spaces in paths:

```bash
echo "=== big dirs ==="
du -sh $(find . -type d -name node_modules -prune -print) | sort -rh | head
echo "total: $(du -sh $(find . -type d -name node_modules -prune -print) | tail -1)"
```

Two scans, two nested `$( )`, word-split file list, and `sort -rh` is GNU-only.

Nushell — one pass, typed, no parsing:

```nu
glob **/node_modules --no-file
| each {|p| {size: (du $p | get 0.apparent), path: $p} }
| sort-by size --reverse
| first 10
```

Python when the result feeds further logic:

```python
import os
from pathlib import Path

def tree_size(root: Path) -> int:
    return sum(f.stat().st_size for f in root.rglob("*") if f.is_file())

trees = [Path(r) / d for r, dirs, _ in os.walk(".")
         for d in dirs if d == "node_modules"]
for t in sorted(trees, key=tree_size, reverse=True)[:10]:
    print(f"{tree_size(t) / 1024**2:8.1f} MB  {t}")
```

## If it must be a pipeline

- One stage is fine. Two is usually fine. Three is a script.
- `set -o pipefail`, or a failure mid-pipe is invisible.
- Quote every expansion; a filename with a space is not an edge case.
- `find -print0 | xargs -0`, never bare `find | xargs`.
- Prefer `while IFS= read -r line` over `for line in $(cmd)`.
- Check `${PIPESTATUS[@]}` when you need to know *which* stage failed.
