# CLI cheatsheets

Cached essentials for the tools this kit sends you to. **Verified against installed
versions, not recalled** — the versions are recorded so a future reader knows when to
re-check.

The point of this file is not to replace `--help`. It is to record the handful of
**defaults that silently do the wrong thing**, which `--help` states plainly but
nobody reads until after they have been bitten.

Verified 2026-07-19: `sd 1.0.0` · `rg 15.2.0` · `fd 10.4.2` · `nu 0.114.1` ·
`jq 1.7.1` · `yq 4.53.3`.

## How to check anything here

```sh
<cmd> --help          # first, always — matches the installed version
man -w <cmd>          # is there a man page at all?
<cmd> --version       # before trusting any remembered flag
```

`nu` and `sttr` ship **no** man page. `sd`, `rg`, `fd`, `jq`, `yq` do.

---

## fd — find files

```sh
fd pattern              # regex by default
fd -g '*.log'           # glob mode
fd -e db                # by extension
fd -t f / -t d / -t l   # files / dirs / symlinks
fd -x cmd {}            # execute per result (parallel)
fd -X cmd               # execute once with all results
```

**The gotcha that costs you an hour:** `fd` skips hidden files **and** honours
`.gitignore`, `.ignore`, `.fdignore` and the global ignore file. `-H` only fixes the
first half.

```sh
fd -H -e db      # 0 results — files were gitignored
fd -H -I -e db   # 3 results  ← -I / --no-ignore is the other half
```

A `.db` or `.env` you are hunting is *usually* gitignored, which is precisely why you
are hunting it. Reach for `-HI` when searching for state and data files.

## rg — search contents

```sh
rg pattern              # recursive, respects .gitignore, skips hidden
rg -HI pattern          # ...unless you say otherwise (same trap as fd)
rg -l pattern           # filenames only
rg -o pattern           # only the matched part
rg -U 'a\n.*b'          # -U/--multiline: patterns may cross lines
rg -t py pattern        # restrict by file type
rg --json pattern       # structured output, parseable
rg -A3 -B1 pattern      # context after / before
rg -c pattern           # count per file
```

Same ignore semantics as `fd`. `rg --json` beats parsing `rg` text output.

## sd — substitute (use instead of sed)

```sh
sd 'find' 'replace' file.txt      # in place, by default
sd -p 'find' 'replace' file.txt   # -p/--preview: show, do not write
sd -F 'literal' 'replace' file    # -F: no regex, treat as fixed string
sd -n 2 'find' 'replace' file     # limit replacements per file
cat f | sd 'a' 'b'                # reads STDIN when no file given
```

Captures are `$1`, `$2` — not `\1`. **`sd` writes in place by default**, so use `-p`
first on anything you cannot regenerate.

Why `sd` and not `sed`: there is no `sed -i` invocation portable across BSD and GNU.
`sed -i 's/a/b/' f` works on GNU and errors on macOS; `sed -i '' 's/a/b/' f` works on
macOS and creates a file named `''` on GNU. `sd` behaves identically everywhere.

## nu — structured shell

```sh
nu -n -c '...'          # agent/CI: -n = --no-config-file, deterministic
nu --stdin -c 'print $in'
nu --no-newline -c '...'   # for command substitution
nu --ide-check 0 script.nu # parse + type check, no execution
```

Without `-n`, `nu -c` loads the user's `config.nu`/`env.nu` and inherits their
aliases, `$env`, and any parse-time `source`. See
[`nushell.md`](nushell.md) for the language itself.

Useful shapes:

```nu
ls **/*.log | where size > 10mb | sort-by size --reverse | first 10
glob **/node_modules --no-file | each {|p| {path: $p, size: (du $p | get 0.apparent)} }
open data.json | get items | where active | select name id
ps | where cpu > 10 | select pid name cpu
^git status --short | complete | get stdout    # ^ = external, complete = exit code
```

`$nu` has `home-path`? **No** — that was a wrong guess that cost two failed attempts.
Check `$nu | columns` before using any `$nu.*` field.

## jq — JSON

```sh
jq -r .field            # -r: raw, no surrounding quotes
jq -c .                 # compact, one line — good for piping
jq -e '.x'              # exit non-zero if null/false — usable in `if`
jq -s '.'               # slurp multiple inputs into one array
jq --arg k "$v" '.[$k]' # pass a shell value in SAFELY, never interpolate
jq 'to_entries[] | "\(.key)=\(.value)"'
```

Never build a `jq` program by string-interpolating shell variables; use `--arg` /
`--argjson`.

## yq — YAML / TOML / XML

Mike Farah's Go `yq` (v4), not the Python wrapper — the syntaxes differ.

```sh
yq '.field' file.yaml
yq -i '.version = "0.3.0"' file.yaml    # -i: in place
yq -o json '.' file.yaml                 # convert
yq -p toml '.tool' file.toml             # -p: input format
yq ea '. as $i ireduce ({}; . * $i)' *.yaml   # merge multiple docs
```

## sttr — string transforms

No `--help` and no man page in this install; run `sttr` with no arguments for its
interactive picker, or `sttr <transform> <input>`. Covers base64, url, hash, case
conversion, json/yaml formatting.

## Cross-cutting

- `--dry-run` / `-p` / `--preview` first, on anything that writes.
- `--json` output where offered — parse data, not formatting.
- `-0` / `--null` pairs with `xargs -0` for paths containing spaces.
- Long flags in scripts (`--no-ignore`), short flags interactively (`-I`). A script
  is read more often than it is written.
