---
name: posix-shell
version: 0.4
author: f-steff
email: fsteff@gmail.com
description: >
  Expert POSIX sh / Bash shell scripting: write, lint, test, and harden scripts
  for cross-platform portability. Tests across dash, bash --posix, ash, zsh, ksh,
  mksh, yash, posh via Docker Alpine. Also supports Windows Git Bash. Use when
  writing, debugging, or reviewing shell scripts that must work across systems.
---

# POSIX_Shell_Skill

You are an expert in portable POSIX shell scripting with deep knowledge of the
POSIX specification, common shell pitfalls, and cross-platform compatibility.

## Detection & Setup

When invoked, detect environment:

```sh
case "$(uname -s)" in
  Linux)   PLATFORM=linux ;;
  Darwin)  PLATFORM=macos ;;
  CYGWIN*|MINGW*|MSYS*) PLATFORM=windows ;;
  *)       PLATFORM=unknown ;;
esac

DOCKER_AVAILABLE=false
command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 && DOCKER_AVAILABLE=true
```

### Tool Installation

Instruct user or install tools. Per-platform commands:

- **Alpine:** `apk add shellcheck shfmt bash dash zsh ksh mksh yash posh`
- **Debian/Ubuntu:** `apt-get install -y shellcheck shfmt bash dash zsh ksh mksh`
- **Fedora/RHEL:** `dnf install -y shellcheck bash dash zsh ksh mksh`
- **macOS:** `brew install shellcheck shfmt bash dash zsh ksh mksh`
- **Windows (Git SDK):** derive Git path from `where git`, then `pacman -S shellcheck bash dash zsh`

Fallback URLs: shellcheck (github.com/koalaman/shellcheck), shfmt (github.com/mvdan/sh)

### Windows Git Bash

```sh
git_path=$(command -v git 2>/dev/null || where git 2>/dev/null)
if [ -n "$git_path" ]; then
  git_install_dir=$(dirname "$(dirname "$git_path")")
  GIT_BASH_PATH="$git_install_dir/bin/bash.exe"
  [ -f "$git_install_dir/usr/bin/pacman.exe" ] && GIT_SDK_AVAILABLE=true
fi
```

**Lesson: MSYS2 path-conversion exclusions break native binaries in Git Bash.**
Setting `MSYS2_ARG_CONV_EXCL=*` or `MSYS_NO_PATHCONV=1` disables MSYS2's
POSIX-to-Windows argument conversion for every native Windows binary in the
process tree. A native `git.exe` then receives raw `/tmp/...` paths and fails
with `fatal: cannot change to '/tmp/...'` even though the directory exists.

- These env vars leak from scripts wrapping `docker run -v` (to stop MSYS2 from
  mangling volume mount arguments) into every child process, silently breaking
  all git and other native binary invocations.
- Fix: `unset MSYS2_ARG_CONV_EXCL MSYS_NO_PATHCONV MSYS2_ENV_CONV_EXCL` at
  startup. Never leak caller-specific env into child processes.

**Lesson: temp-dir leaks.** Test helpers that create `mktemp -d` mock
directories must remove them in teardown. Missing cleanup accumulates
directories in `/tmp`, making debugging noisy and masking real signal.

### Helper Scripts

This skill ships with helper scripts in its `scripts/` directory:

| Script | Purpose |
|--------|---------|
| `scripts/docker_test.sh` | Docker multi-shell test runner (file/dir/entrypoint) |
| `scripts/docker_test_cross.sh` | Cross-distro test runner (Alpine + Debian + Fedora) |
| `scripts/test_runner.sh` | Local multi-shell test runner (file/dir/entrypoint) |
| `scripts/install_tools.sh` | Cross-platform tool installer |
| `scripts/find_git_bash.sh` | Windows Git Bash locator |

Use these as building blocks when testing user scripts.

## Writing Scripts

### POSIX Mode (default)

Shebang `#!/bin/sh`. Rules:

| Do | Don't |
|----|-------|
| `printf '%s\n' "$var"` | `echo "$var"` |
| `$(cmd)` | backticks |
| `case` for branching | `[[ ]]` |
| `[ ]` tests | `[[ ]]` |
| `$(( ))` arithmetic | `let` or `(( ))` |
| `myfunc() { }` | `function myfunc` |
| `set -eu` + quoting | bare `read`, unquoted vars |
| `IFS= read -r` | `read` without flags |
| `${var:-default}` / `${var:?err}` | no defaults |
| `. script` | `source` |
| `printf '%s\n' "$var"` | arrays, `<<<`, `$[]`, `select`, `&>`, `type` |

Note: `local` inside a function is not detected by any tool. It must be
caught during code review or by running the script under dash.
checkbashisms detects most other bashisms (`[[ ]]`, arrays, `<<<`, etc.),
but coverage varies by version.

### Code Documentation

**ASCII-only:** All scripts must contain only ASCII characters (bytes
0x00-0x7F). Non-ASCII characters like em dashes, arrows, or smart quotes
cause encoding issues across different terminals and editors.
Use ASCII alternatives: `--` for dashes, `=>` for arrows, straight quotes.

**Comments:** Every function and significant code block must have at least
one comment line explaining why it exists. A comment like:

```sh
# Use temp file instead of pipe to avoid pipefail loss in POSIX
```

tells future readers why this approach was chosen. This is especially
important for workarounds, portability fixes, and non-obvious patterns.

The iteration loop below includes a documentation review step.

**Script Structure:** Place functions at the top, call `main "$@"` at the
bottom. Never put executable code in the middle of a script. Use a source
guard to allow both sourcing and direct execution:

```sh
if [ "${0##*/}" = "${SCRIPT_NAME}" ]; then
    main "$@"
fi
```

**Config files:** Load configuration with `.`, keeping environment overrides:
```sh
[ -f "/etc/myapp.conf" ] && . "/etc/myapp.conf"
[ -f "$HOME/.myapp.conf" ] && . "$HOME/.myapp.conf"
DATABASE="${MYAPP_DATABASE:-$DEFAULT_DATABASE}"
```

### Security Hardening

**Temp files:** Never use `$$` for temp file names (predictable, race
condition). Always use `mktemp`:

```sh
tmpfile=$(mktemp /tmp/myapp-XXXXXX) || exit 1
trap 'rm -f "$tmpfile"' EXIT INT TERM
```

**Input validation:** Always validate and quote inputs:

```sh
case "$input" in
  *[!0-9]*) echo "error: not a number" >&2; exit 1 ;;
esac
```

**Secrets:** Never embed secrets in scripts. Read from files with
restricted permissions or environment variables. Be aware that `/proc`
and error messages may leak environment contents.

**Filenames:** Use `--` to mark end of options. Prefix glob results with
`./` to prevent filenames starting with `-` from being interpreted as
flags:

```sh
for f in ./*.sh; do
  [ -f "$f" ] || continue
  cmd -- "$f"
done
```

**Injection:** Use `printf '%s' "$var"` instead of `echo "$var"` when
writing data that may contain special characters. Never pass unvalidated
input to `eval`.

### Bash Mode

When user requests bash features: `#!/usr/bin/env bash`, support arrays,
`[[ ]]`, `local`, `<<<`, process substitution, `globstar`, etc. But follow
POSIX rules wherever bash features aren't required.

### Safety Boilerplate

```sh
#!/bin/sh
set -eu
IFS="$(printf '\n\t')"
unset CDPATH
```

**CRITICAL: pipefail is not POSIX.** In dash and ash, `cmd1 | cmd2` exits 0
even if `cmd1` fails. This is the single most common silent-failure pattern
in shell scripts -- a pipeline like `tar cf - . | gzip > backup.tgz` will
produce a truncated archive if `tar` fails, and the script will not notice.

For bash/zsh, enable pipefail:

```sh
if command -v bash >/dev/null 2>&1; then
  set -o pipefail 2>/dev/null || true
fi
```

For POSIX shells (dash, ash, etc.), **check each pipeline stage explicitly**:

```sh
# Instead of:  tar cf - . | gzip > backup.tgz
# Do:
tar cf - . > /tmp/backup.tar
gzip -c /tmp/backup.tar > backup.tgz
rm -f /tmp/backup.tar
```

Or use a helper to check the pipe exit:

```sh
run_pipeline() {
  pipe_exit=0
  eval "$@" || pipe_exit=$?
  return "$pipe_exit"
}
run_pipeline 'tar cf - . | gzip > backup.tgz'
```

## Portability

### sed (BSD vs GNU)

BSD `sed -i` requires a mandatory backup extension argument. Write
`sed -i.bak 's/.../.../' "$file" && rm -f "$file.bak"` -- never bare
`sed -i`. BSD sed also rejects multi-command `{ }` blocks joined by
semicolons; prefer `awk` for multi-step text extraction or pipe stages.

### tar (BSD vs GNU)

BSD tar lacks `--sort=name`, `--mtime`, `--owner`, `--group`,
`--numeric-owner`, and `GZIP=-n`. For deterministic archives, detect
GNU tar and fall back to Python's `tarfile`:

```sh
if tar --version 2>/dev/null | grep -q "GNU tar"; then
    GZIP=-n tar --sort=name --mtime='UTC 1980-01-01' \
        --owner=0 --group=0 --numeric-owner -czf out.tar.gz .
else
    python3 - "$output" <<'PY'
import gzip, io, os, tarfile
# Build deterministic tar.gz in memory
PY
fi
```

When using Python's `gzip.GzipFile`, pass `filename=""` to suppress the
non-deterministic FNAME header the `fileobj.name` property would embed.

### Path Resolution

On macOS, `/var`, `/tmp`, and `/etc` are symlinks to `/private/*`.
`pwd` returns the logical path; `pwd -P` returns the physical path.
Always use `cd -P` and `pwd -P` for canonical paths used in comparisons:

```sh
canonical=$(CDPATH= cd -P -- "$dir" && pwd)
```

### Command Resolution

macOS (since 12.3) has no `python`, only `python3`. Resolve dynamically:

```sh
python_cmd=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)
[ -n "$python_cmd" ] || die "python3 or python required"
```

### date (GNU vs BSD)

`date` is notoriously non-portable. Detect the variant and adapt:

```sh
if date --version >/dev/null 2>&1; then
    date -d "yesterday" +%Y-%m-%d           # GNU
else
    date -v -1d +%Y-%m-%d 2>/dev/null ||    # BSD
    perl -e 'use POSIX; print strftime(...)' # fallback
fi
```

### stat (GNU vs BSD)

Use `wc -c < "$file"` as universal fallback for file size. For mtime:

```sh
if stat --version >/dev/null 2>&1; then
    stat -c%Y "$file"    # GNU
elif stat -f%m "$file" >/dev/null 2>&1; then
    stat -f%m "$file"    # BSD
else
    wc -c < "$file"      # size fallback for any system
fi
```

### POSIX Command Options

Prefer short POSIX options: `ls -la` (not `--all`), `ps -e` (not `aux`),
`df -k` (not `-h`), `grep -E` (not `-P`).

## Testing

### Static Analysis

```sh
shellcheck --shell=sh script.sh
shfmt -d script.sh
checkbashisms script.sh
```

### Docker Multi-Shell Testing (preferred)

Mount project dir, test across shells:

```sh
docker run --rm -v "$(pwd):/mnt" alpine:latest sh -c '
  apk add -q dash bash zsh ksh mksh yash posh busybox >/dev/null 2>&1
  for sh in dash bash ash zsh ksh mksh yash posh; do
    printf "Testing %s... " "$sh"
    if command -v "$sh" >/dev/null 2>&1; then
      if "$sh" /mnt/script.sh; then echo PASS; else echo "FAIL ($?)"; fi
    else echo SKIP; fi
  done
'
```

For directory + entrypoint:

```sh
docker run --rm -v "$(pwd):/mnt" -w /mnt alpine:latest sh -c '
  apk add -q dash bash zsh ksh mksh yash posh >/dev/null 2>&1
  for sh in dash bash ash zsh ksh mksh yash posh; do
    printf "Testing %s with %s... " "$sh" "$1"
    if command -v "$sh" >/dev/null 2>&1; then
      if "$sh" "$1"; then echo PASS; else echo "FAIL ($?)"; fi
    fi
  done
' -- "$entrypoint"
```

### Cross-Distro Testing

The helper script `scripts/docker_test_cross.sh` runs the same tests across
Alpine (busybox ash), Debian (dash), and Fedora (bash) to catch userland
differences:

```sh
scripts/docker_test_cross.sh script.sh
scripts/docker_test_cross.sh src/
scripts/docker_test_cross.sh src/ main.sh
```

You can also run against a specific image:

```sh
DOCKER_TEST_IMAGE=debian:stable-slim scripts/docker_test.sh script.sh
DOCKER_TEST_IMAGE=fedora:latest scripts/docker_test.sh script.sh
```

### Local Testing (fallback)

```sh
for sh in dash bash zsh ksh; do
  command -v "$sh" >/dev/null 2>&1 || continue
  "$sh" script.sh && echo "$sh: PASS" || echo "$sh: FAIL ($?)"
done
```

### Windows

```sh
[ -n "$GIT_BASH_PATH" ] && "$GIT_BASH_PATH" --posix script.sh && echo "Git Bash: PASS"
```

## Iteration Loop

1. Write script following rules above
2. Run static analysis (shellcheck, shfmt, checkbashisms)
   Note: checkbashisms coverage varies by distribution. The Debian
   devscripts package catches more patterns than the standalone script.
   Always run the script under dash/ash as final verification.
3. Fix all findings
4. Performance check: Review loops for patterns that are slow in dash/ash.
   See the Performance Guidance section below.
5. Run multi-shell tests (Docker preferred, local fallback)
6. Fix failures per shell
7. Re-test until all target shells pass
8. Final static analysis pass

## Performance Guidance

Shell performance varies dramatically across implementations. A loop that
runs in 1s under bash can take 20s+ under dash or ash.

**When shell loops are fine:**
- Iterating over a small set of files (`for f in *.txt`)
- Orchestrating external commands (running rsync/gcc/docker per item)
- Simple conditionals and argument parsing
- Reading config files with known small size

**When to avoid shell loops:**
- Processing large text files line by line (`while read -r line`)
  => Use `awk`, `sed`, `grep` instead
- Repeatedly calling tools per item in a large set
  => Batch the work: collect all input, run the tool once, post-process
  the output in the shell

**The middle ground:**
If the processing requires calling a tool many times (e.g., `ffprobe` on
each file), it can be cleaner to batch all files through the tool and do
final post-processing in the shell rather than forcing everything into a
single `awk` script. The key is: one tool invocation per file is fine;
one tool invocation per line is not.

**Use `cut` and `tr` for simple field/character operations:**
They are much faster than shell parameter expansion in loops.

## Debugging

When a script fails, diagnose it with these tools:

**Syntax check (no execution):**
```sh
sh -n script.sh          # report syntax errors without running
sh -n -e script.sh       # stop on first error
```

**Trace execution:**
```sh
sh -x script.sh          # print each command before executing
sh -v script.sh          # print each line verbatim
sh -xv script.sh         # combine trace + verbose
```

**Customize trace output:**
```sh
# In the script itself:
PS4='+[$LINENO] '         # prefix each trace line with line number
set -x                    # enable trace
# ... code to debug ...
set +x                    # disable trace
```

**Explain shellcheck warnings:**
```sh
shellcheck --shell=sh script.sh   # SH rules
shellcheck --shell=bash script.sh # Bash rules
shellcheck --help                 # List all rules
```

These patterns are covered in the debug output format used by
`scripts/docker_test.sh --verbose`.

## POSIX Reference

### printf vs echo
`printf '%s\n' "$var"` is always safe. `echo "$var"` is unspecified with `\` or `-n`.

### Reading Input
`IFS= read -r line` -- always use both `IFS=` and `-r`.

### Parameter Expansion
- `${var:-word}` -- default if unset/null
- `${var:=word}` -- assign default
- `${var:?msg}` -- error if unset/null
- `${var:+word}` -- alternate if set
- `${var#pat}` / `${var##pat}` -- remove prefix
- `${var%pat}` / `${var%%pat}` -- remove suffix
- `${#var}` -- string length

### Test / [ ]
`[ "$a" = "$b" ]` (single `=`), `[ "$a" != "$b" ]`, `[ -z "$var" ]`,
`[ -n "$var" ]`, `[ -f "$file" ]`, `[ -d "$dir" ]`, `[ -e "$path" ]`,
`[ -L "$file" ]` (symlink), `[ -r "$file" ]`, `[ -w "$file" ]`,
`[ -x "$file" ]`, `[ -s "$file" ]` (non-empty),
`[ "$a" -eq "$b" ]`, `[ "$a" -lt "$b" ]`, `[ "$a" -gt "$b" ]`,
`[ "$f1" -nt "$f2" ]` (newer), `[ "$f1" -ot "$f2" ]` (older).

### Case
```sh
case "$var" in
  pattern1) action ;;
  pattern2|p3) action ;;
  *) default ;;
esac
```

### Traps
Always use signal names, not numbers: `trap 'cleanup' EXIT INT TERM`.

### Locale Safety

Prefer scoped locale overrides over global `LC_ALL=C` -- the latter can
break user scripts and locale-dependent output. When only floating-point
formatting matters (e.g., `awk` output consumed by other tools like
`sleep`), scope `LC_NUMERIC=C` to just that invocation:

```sh
seconds=$(LC_NUMERIC=C awk -v ms="$ms" 'BEGIN { printf "%.3f", ms / 1000 }')
```

Use `LC_ALL=C` only when truly needed for predictable sorting/parsing.

### Naming Conventions
- `readonly CONSTANT_VAR` -- uppercase with underscores
- `local_var` or `MY_ENV_VAR` -- lowercase for locals, uppercase for exports
- Avoid single-letter names, camelCase, and hyphens (`-` is not allowed)

### Regex POSIX Character Classes
`[[:alnum:]]`, `[[:alpha:]]`, `[[:digit:]]`, `[[:space:]]`, `[[:upper:]]`,
`[[:lower:]]`, `[[:punct:]]`. Use in `grep`, `sed`, `tr` for locale-safe
character matching: `tr '[:upper:]' '[:lower:]'`.

### Glob Patterns for Dotfiles
- `. [!. ]*` -- hidden files except `.` and `..`
- `.. ?*` -- double-dot files
- `*` -- non-hidden files

### File Reading Loop
```sh
while IFS= read -r line; do
  printf '%s\n' "$line"
done < file
```

### Advanced Patterns

**Shell-quoting for safe eval:**
```sh
quote() { printf '%s\n' "$1" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/'/"; }
```

**Function return without subshell (avoids trailing newline stripping):**
```sh
myfunc() { ...; eval "$1=\$result"; }
# Call: myfunc outvar; printf '%s\n' "$outvar"
```

**Array simulation with `$@`:**
```sh
save() { for i do printf '%s\n' "$i" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/' \\\\/"; done; echo " "; }
# Save: myarray=$(save "$@")
# Restore: eval "set -- $myarray"
```

**Glob matching with `case`:**
```sh
fnmatch() { case "$2" in $1) return 0;; *) return 1;; esac; }
```

**Test if directory is empty:**
```sh
is_empty() (
  cd "$1" || return 1
  set -- .[!.]*; [ -f "$1" ] && return 1
  set -- ..?*;  [ -f "$1" ] && return 1
  set -- *;     [ -f "$1" ] && return 1
  return 0
)
```

**Write bytes by numeric value:**
```sh
writebytes() { printf %b "$(printf '\\%03o' "$@")"; }
```

**Read binary byte-by-byte:**
```sh
read dummy oct <<EOF
$(dd bs=1 count=1 | od -b)
EOF
```

**Count character occurrences:**
```sh
tr 'a\n' '\na' | wc -l  # safer than tr -dc 'a' | wc -c for non-ASCII
```

**Remove all exported variables (sanitize environment):**
```sh
unexport_all() {
  eval set -- "$(export -p)"
  for i; do
    case "$i" in
      *=*) unset "${i%%=*}"; eval "${i%%=*}=\${i#*=}" ;;
    esac
  done
}
```

**Query a user's home directory:**
```sh
eval "home=~$user"  # only when $user is trusted
```

**Portable find with xargs (prefer `-exec ... '{}' +`):**
```sh
find ... -exec command '{}' +
```

**Portable find -print0:**
```sh
find ... -exec printf '%s\0' '{}' +
```

**Password input without echo:**
```sh
stty -echo; read password; stty echo; echo
```

**Pipeline debugging with tee:**
```sh
command1 | tee stage1.log | command2 | tee stage2.log | command3
```

**Save and restore IFS:**
```sh
oldIFS="$IFS"; IFS=':'; ...; IFS="$oldIFS"
```

**Subshell for variable isolation (POSIX alternative to `local`):**
```sh
myfunc() (  # subshell via parentheses -- variables don't leak
  temp_var="isolated"
)
```
