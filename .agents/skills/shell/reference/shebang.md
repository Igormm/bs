# Shebangs

The shebang (`#!`) on line 1 tells the kernel which interpreter runs a script.
It looks trivial and is quietly full of edges — wrong ones cause
`bad interpreter` errors, silent truncation, or the wrong language version. These
rules teach good, *non-exotic* shebangs. Snippets cite `execve(2)`, the GNU
`env` manual, and ShellCheck.

## How it actually works (mechanism)

When you execute a file, the kernel reads its first bytes. If they are `#!`, it
runs the named interpreter with the script as an argument. Three facts drive
every rule below
([execve(2)](https://man7.org/linux/man-pages/man2/execve.2.html)):

1. **The interpreter path is not searched on `PATH`** — it is used as written, so
   it must be absolute (`/usr/bin/env` counts).
2. **Everything after the interpreter is passed as a *single* argument.** You
   cannot pass multiple flags without help (see `env -S`).
3. **The line is length-limited** by the kernel's `BINPRM_BUF_SIZE` — 127 bytes
   before Linux 5.1, 255 since — and anything beyond is **silently truncated**.

> Trivia, verified in mainline: the kernel allows a shebang to point at another
> shebanged script up to 5 rewrites deep. A 2026 doc fix to the comment in
> `fs/exec.c` corrected an off-by-one ("4 levels" → "5 levels") — Linux commit
> [`f718c9fa87be`](https://github.com/torvalds/linux/commit/f718c9fa87be) by
> Alan Urmancheev ([@alurm](https://github.com/alurm)).

## Rules

### 1. Default to `#!/usr/bin/env bash`, not `#!/bin/bash`

`env` resolves the interpreter via `PATH`, finding the user's or Homebrew's modern
Bash. `/bin/bash` is Bash **3.2** on macOS and does not exist at all on NixOS and
some BSDs. `/usr/bin/env` is near-universal.

```sh
#!/usr/bin/env bash     # good
#!/bin/bash             # 3.2 on macOS; absent on NixOS
```

### 2. Pass interpreter flags with `env -S`, never bare

Because the kernel passes the rest of the line as one argument,
`#!/usr/bin/env bash -euo pipefail` makes `env` look for a program literally named
`"bash -euo pipefail"` and fail. `env -S` (split-string; GNU coreutils 8.30+, also
on BSD/macOS) splits it. This is the clean way to bake strict mode into a script.

```sh
#!/usr/bin/env -S bash -euo pipefail     # good
#!/usr/bin/env bash -euo pipefail        # env: 'bash -euo pipefail': No such file
```

([GNU env manual](https://www.gnu.org/software/coreutils/manual/html_node/env-invocation.html))

### 3. Keep the interpreter path absolute — `SC2239`

A relative interpreter fails when the script runs from another directory. ShellCheck
flags it.

```sh
#!/usr/bin/env python3     # good (env is absolute)
#!bin/python3              # SC2239: shebang must use an absolute path
```

### 4. Put `#!` at byte 0, use LF endings, no BOM

The kernel only recognizes `#!` as the very first two bytes. A CRLF ending appends
`\r` to the interpreter name (`/bin/bash\r` → `bad interpreter`). A blank first
line or a UTF-8 BOM breaks detection entirely.

```sh
#!/usr/bin/env bash        # good: first line, LF
#/usr/bin/env bash         # SC1113: missing '!'
```

(CRLF → [SC1017](https://www.shellcheck.net/wiki/SC1017); shebang not first →
[SC1128](https://www.shellcheck.net/wiki/SC1128).)

### 5. Always give an executable script a shebang — `SC2148`

Without one, `execve` returns `ENOEXEC` and the caller decides what runs — many
shells silently fall back to `/bin/sh`, changing the language out from under you.

### 6. Keep the whole line short (well under 127 bytes)

The kernel truncates at `BINPRM_BUF_SIZE` silently. Long `env -S` flag chains are
the usual offender; if you need many flags, set them in the body with `set`
instead.

### 7. In privileged, cron, or security-sensitive scripts, pin an absolute interpreter

`env` resolves through `PATH`, which a hostile environment can hijack. A fixed
path (`#!/bin/sh`, `#!/bin/bash`) removes that vector. (Note: Linux ignores the
set-user-ID bit on `#!` scripts, so never rely on a shebang for a setuid script.)

### 8. Make the shebang match the dialect you actually write

`#!/bin/sh` promises POSIX; using arrays, `[[ ]]`, or `local` under it breaks on
`dash`. Declare `bash` if you use bashisms.

```sh
#!/usr/bin/env bash        # good, and the body may use [[ ]], arrays, local
#!/bin/sh                  # then declare -A / [[ ]] in the body breaks on dash
```

## Anti-patterns (do not teach or write these)

- **Polyglot / self-re-exec shebang tricks** (a `#!/bin/sh` header that re-`exec`s
  another interpreter; `//usr/bin/env` C-shell polyglots) — clever, unreadable,
  fragile.
- **`${ORIGIN}/`-relative shebangs** — an interesting
  [kernel proposal](https://github.com/alurm/relocatable-shebangs) but non-standard
  and unmerged; requires a patched kernel.
- **Arbitrary programs as interpreters** — `#!/usr/bin/awk -f` is legitimate, but
  chaining surprising tools is not.
- **Multiple flags without `env -S`**, **relative interpreter paths**, and
  **relying on setuid** — all covered above.

## What ShellCheck catches

`SC2148` (missing shebang), `SC2239` (non-absolute interpreter), `SC2096`
(more than one parameter — the missing-`env -S` case), `SC1113` (`#` without
`!`), `SC1017` (CRLF), `SC1128` (shebang not first line). It does **not** enforce
`env bash` over `/bin/bash`, or the length limit — those are the judgment calls
this guide exists for.

## Sources

- `execve(2)` — <https://man7.org/linux/man-pages/man2/execve.2.html>
- GNU `env` (`-S`) —
  <https://www.gnu.org/software/coreutils/manual/html_node/env-invocation.html>
- ShellCheck wiki — <https://www.shellcheck.net/wiki/>
- LWN, "The case of the supersized shebang" — <https://lwn.net/Articles/779997/>
- Linux shebang doc fix, commit `f718c9fa87be` (Alan Urmancheev, [@alurm](https://github.com/alurm))
  — <https://github.com/torvalds/linux/commit/f718c9fa87be>

See [`skills/shell`](../skills/shell/) and [`examples/shebang/`](../examples/shebang/).
