# Streams: stdin, stdout, stderr

Every process has three standard streams: **stdin** (fd 0, input), **stdout**
(fd 1, data output), and **stderr** (fd 2, diagnostics). Using them correctly is
what makes a script composable — a program that mixes errors into its data
output cannot be piped or parsed reliably. Rules below cite the Bash manual, the
Google Shell Style Guide, POSIX, and Greg's Wiki (BashFAQ / BashPitfalls).

## Keep the channels separate

### 1. Send diagnostics, warnings, and prompts to stderr; keep stdout for data

stdout is the machine-readable channel that feeds pipes and `$(...)`. Any
human-facing text on stdout corrupts it. The standard idiom:

```bash
err() { printf '%s\n' "$*" >&2; }

err "retrying..."            # to stderr
printf '%s\n' "$result"      # to stdout — the data
```

Google Shell Style Guide: "All error messages should go to `STDERR`."
([STDOUT vs STDERR](https://google.github.io/styleguide/shellguide.html#STDOUT_vs_STDERR))

### 2. Signal failure with the exit status, not only a message

The exit status is the channel callers actually test (`if cmd`, `&&`, `set -e`).
Print the diagnostic to stderr **and** return non-zero.

```bash
# bad  — prints an error but still exits 0
printf 'cannot open %s\n' "$f"
# good
printf 'cannot open %s\n' "$f" >&2
return 1
```

## Reading input

### 3. Read line by line with `while IFS= read -r line`

Bare `read` strips leading/trailing whitespace and eats backslashes; `IFS=`
preserves whitespace and `-r` keeps backslashes literal.
([BashFAQ/001](https://mywiki.wooledge.org/BashFAQ/001))

```bash
while IFS= read -r line; do
  process "$line"
done < "$file"
```

### 4. Never loop over `$(cat file)` to read lines — `SC2013`

Command substitution word-splits and glob-expands, so you iterate *words* (and
expand `*`), not lines. Use the `read` loop above.

```bash
# bad  — SC2013
for line in $(cat file); do ...; done
```

### 5. Use `-` and `/dev/std*` where a stream is expected

`-` is a widely-honored operand convention meaning "read stdin" (`cat -`,
`grep -f -`). Bash also maps `/dev/stdin`, `/dev/stdout`, `/dev/stderr`, and
`/dev/fd/N` to file-descriptor duplication, letting you pass a stream where a
filename is required.
([Redirections](https://www.gnu.org/software/bash/manual/html_node/Redirections.html))

## Redirection mechanics

### 6. Redirection is left-to-right — put `2>&1` after `>file` — `SC2069`

`2>&1` duplicates whatever stdout points to *at that moment*.

```bash
cmd >file 2>&1     # both stdout and stderr -> file   (usually intended)
cmd 2>&1 >file     # SC2069: stderr -> terminal, stdout -> file  (usually a bug)
```

([Redirections](https://www.gnu.org/software/bash/manual/html_node/Redirections.html))

### 7. Know here-docs and here-strings

- `<<EOF` feeds a literal block to stdin; `<<-EOF` strips **leading tabs** (not
  spaces) so the block can be indented; quoting the delimiter (`<<'EOF'`)
  disables expansion inside.
- `<<< "$var"` (here-string) feeds one string to stdin without word-splitting.

```bash
cat <<'EOF'
$HOME is printed literally, not expanded
EOF

read -r first rest <<< "$line"
```

## Two pitfalls that silently corrupt data

### 8. Never read and write the same file in one pipeline

The shell truncates the `>file` target before the reader starts, so this
destroys `file`:

```bash
# bad  — empties the file first
sed 's/a/b/' file > file
# good
sed 's/a/b/' file > tmp && mv tmp file    # or GNU: sed -i
```

([BashPitfalls](https://mywiki.wooledge.org/BashPitfalls))

### 9. Command substitution strips trailing newlines

`x=$(cmd)` removes **all** trailing newlines. When they matter, guard with a
sentinel:

```bash
content=$(cat file; printf x); content=${content%x}
```

## What the linter can and cannot catch

ShellCheck flags `SC2013` (for-loop over `$(cat)`) and `SC2069` (`2>&1`
ordering), but it **cannot** tell that a diagnostic went to stdout instead of
stderr — rule 1 is enforced by review, not by the linter. Say so, so nobody
assumes a green lint means the streams are right.

## Sources

- Bash manual, Redirections —
  <https://www.gnu.org/software/bash/manual/html_node/Redirections.html>
- Google Shell Style Guide (STDOUT vs STDERR) —
  <https://google.github.io/styleguide/shellguide.html>
- Greg's Wiki — BashFAQ/001, BashPitfalls —
  <https://mywiki.wooledge.org/BashFAQ/001>

See [`skills/shell`](../skills/shell/) and [`examples/streams/`](../examples/streams/).
