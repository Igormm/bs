# Zsh

Zsh is an excellent *interactive* shell, but scripting it is not "Bash with a
different prompt." Two things shape everything below:

1. **ShellCheck and shfmt do not support zsh** (ShellCheck rejects a `zsh`
   shebang; shfmt targets POSIX/bash/mksh). The practical syntax check is
   `zsh -n script.zsh` plus runtime testing. These rules are the substitute for
   the static analysis you'd get in Bash — which is itself a reason to prefer
   Bash for portable, lintable scripts and keep zsh for interactive config and
   zsh-only features.
2. **Zsh's superpower is doing work without forking a subprocess.** Roman
   Perepelitsa (romkatv), author of Powerlevel10k, built the fastest zsh setups
   in existence on exactly this discipline; the performance section below is
   distilled from his work.

Sources are cited per rule. The zsh manual is at
<https://zsh.sourceforge.io/Doc/Release/>.

## Writing robust functions and scripts

- **Start every shippable function with `emulate -L zsh`.** `-L` enables
  `LOCAL_OPTIONS`, `LOCAL_PATTERNS`, and `LOCAL_TRAPS`, so any `setopt`/trap you
  change is scoped to the function and restored on return. The manual recommends
  exactly this to "guarantee itself a known shell configuration."
  ([Options](https://zsh.sourceforge.io/Doc/Release/Options.html))
- **Use `emulate -LR zsh` at the top of standalone scripts.** `-R` also resets
  all options to documented defaults, so behaviour doesn't depend on the caller's
  environment.
- **Inside functions prefer `setopt err_return` over `errexit`.** `ERR_RETURN`
  aborts via an implicit `return` instead of killing the shell — critical for
  sourced code, where `errexit` "can cause the whole interactive shell to exit."
  As in Bash, neither fires for a command whose status feeds `&&`/`||` or an
  `if`/`while` test, so still check critical commands explicitly.
- **Turn on `no_unset` and `pipefail` for fail-fast scripts;** guard legitimately
  optional parameters with `${var:-default}` or `${var-}`.
- **Enable `warn_create_global` and declare every variable `local`/`typeset`.**
  It warns when an assignment creates a global inside a function — the classic
  state-leak bug. Intentional globals (`typeset -g`) are exempt.

```zsh
process() {
  emulate -L zsh
  setopt err_return no_unset pipefail warn_create_global
  local url=$1
  curl -fsS $url | jq .
}
```

## Word splitting: the big difference from Bash

**Zsh does not word-split unquoted parameters** (unless `SH_WORD_SPLIT` is set) —
the manual calls this "an important difference from other shells." `$var` with
spaces stays one word. Split *explicitly* when you want it, rather than enabling
`SH_WORD_SPLIT` globally.
([Expansion](https://zsh.sourceforge.io/Doc/Release/Expansion.html))

```zsh
line="a b c"
args=( ${=line} )          # force IFS split -> 3 words
parts=( ${(s:,:)csv} )     # split on a chosen separator
lines=( ${(f)"$(cmd)"} )   # split command output at newlines
joined=${(j:,:)parts}      # join an array with a separator
```

## Arrays, quoting, indirection

- **Arrays are 1-indexed:** `$arr[1]` is the first element, `$#arr` the length,
  `arr+=(x)` appends. Expand element-safe with `"${(@)arr}"`. Porting Bash's
  `${arr[0]}` gives the wrong element.
- **Quote data for re-parsing with `${(q)var}`** (or `${(qq)}` / `${(qqqq)}`)
  before `eval`, a generated script, or an `ssh` remote command — the robust
  alternative to hand-rolled escaping.
- **Indirect by computed name with `${(P)name}`** (zsh's safe answer to Bash's
  `${!name}`), no `eval`.

## Option parsing and existence checks

- **Parse options with `zparseopts -D -E -F`:** `-D` strips matched options from
  `$@`, `-E` allows options mixed with positionals, `-F` (zsh 5.8+) errors on an
  unknown flag instead of ignoring it.
- **Check existence subprocess-free via `zsh/parameter`:** load it idempotently
  with `-i` (a no-op if already loaded), then test the hashes.

  ```zsh
  zmodload -i zsh/parameter
  (( $+commands[git] )) || return 1   # no `command -v` fork
  (( $+functions[my_helper] ))
  ```

- **Resolve and bypass names with builtins:** `whence -w foo` reports the type
  (`alias`/`builtin`/`command`/`function`/`reserved`); `builtin cd …` /
  `command foo` run the builtin/external past a same-named function — the zsh
  analogues of Bash's `type`/`builtin`/`command`.

## Globbing instead of parsing `ls`/`find`

Zsh globbing runs in-process and returns a properly split array. Glob qualifiers
filter and sort natively; `**/` recurses. Enable `setopt extended_glob` for
`#`/`~`/`^` operators.
([Expansion](https://zsh.sourceforge.io/Doc/Release/Expansion.html))

```zsh
for f in ./*.log(.N); do ...; done   # (.) plain files, (N) no error if none
latest=( *(.om[1]) )                 # newest regular file, by mtime
all_src=( **/*.zsh(.N) )             # recursive, plain files, null-safe
```

## Performance: never fork in a hot path

romkatv's [zsh-bench](https://github.com/romkatv/zsh-bench) sets the budget: below
~10 ms command lag is "indistinguishable from zero." Every `$(...)`, pipe, and
external command is a `fork()`+`exec()` costing on that order — so a prompt that
shells out per segment blows the budget (his benchmark shows a fork-happy prompt
"clones 158 times"). Stay inside the interpreter.

### `$TTY`, never `$(tty)`

This is the canonical example. Use the parameter:

```zsh
export GPG_TTY=$TTY          # correct and instant
# export GPG_TTY="$(tty)"    # slow and sometimes wrong
```

Three independent reasons `"${TTY}"` is correct and `$(tty)` is not:

1. **Cost.** `$(tty)` forks a subshell and execs the external `tty(1)` binary;
   `$TTY` is a parameter read inside the interpreter. romkatv measured "the
   former is 1000+ times faster."
2. **Correctness under redirected stdin.** `tty(1)` prints the terminal attached
   to *its own stdin* (fd 0) — that is its defined job. So `$(tty)` answers "what
   terminal is on fd 0," not "what terminal is this shell on." If the shell's
   stdin is a pipe, a file, a heredoc, or **Powerlevel10k's instant prompt (which
   redirects the standard file descriptors)**, `tty` prints `not a tty` and exits
   non-zero, so `$(tty)` is empty/wrong. `$TTY` is maintained by zsh as "the name
   of the tty associated with the shell" — the controlling terminal, independent
   of where fd 0 currently points.
3. **Authority.** Zsh sets and updates `$TTY`; there is nothing to recompute.

([`$TTY` definition](https://zsh.sourceforge.io/Doc/Release/Parameters.html) ·
[p10k instant-prompt "not a tty"](https://github.com/romkatv/powerlevel10k/issues/524))

### Other in-process replacements for forks

| Instead of (forks) | Use (in-process) | Notes |
|--------------------|------------------|-------|
| `dirname $f` / `basename $f` | `${f:h}` / `${f:t}` | also `${f:r}` root, `${f:e}` extension |
| `realpath $f` | `${f:A}` | `:a` absolute without symlink resolution |
| `$(date +%s)` | `$EPOCHSECONDS` / `$EPOCHREALTIME` | `zmodload zsh/datetime`; `strftime -s` to format |
| `dirname $(readlink -f $0)` | `${${(%):-%x}:A:h}` | `%x` = current source file; romkatv's gitstatus idiom |
| current function name | `${(%):-%N}`, `$funcstack` | `zsh/parameter` |
| `[ … ]` / `test` / `expr` | `[[ … ]]` / `(( … ))` | keywords, no fork, no split |
| `sed`/`awk`/`cut`/`tr` | `${v//a/b}`, `${v#p}`, `${v:l}`, `${(s:/:)v}` | parameter expansion |
| `$(cat file)` | `$(<file)` | the manual notes this is "faster" |
| `find` / parsing `ls` | globbing + qualifiers | see above |

### Structure and measurement

- **Amortize expensive per-prompt work into a daemon and update asynchronously**
  — the [gitstatus](https://github.com/romkatv/gitstatus) pattern Powerlevel10k
  uses instead of forking `git` every prompt.
- **Lay out `.zshrc` in zsh-bench's three phases** so instant prompt stays valid:
  TTY-touching commands first, then activate instant prompt, then the bulk of
  init — which must not read the TTY/stdin or write stdout/stderr. (This is *why*
  a stray `$(tty)`/`echo` in late init breaks under instant prompt.)
- **Measure with zsh-bench, not `time zsh -lic exit`** — the latter ignores
  instant prompt, async init, and input lag, the things users feel.
- **Don't buy speed with dangerous shortcuts** — compiling `.zshrc` to wordcode
  (stale-bytecode risk), `compinit -C` (skips the security/freshness check), or
  printing the prompt before plugins load (buffered-keystroke corruption).

## Sources

- Zsh manual — Options, Expansion, Modules, Parameters, Prompt Expansion:
  <https://zsh.sourceforge.io/Doc/Release/>
- romkatv — [zsh-bench](https://github.com/romkatv/zsh-bench),
  [Powerlevel10k](https://github.com/romkatv/powerlevel10k),
  [gitstatus](https://github.com/romkatv/gitstatus)

See [`skills/shell`](../skills/shell/) for the router summary.
