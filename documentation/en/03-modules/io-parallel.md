[↑ Table of Contents](../README.md)

# Module `io::parallel`

`lib/io/parallel` runs a callback once per input element or executes one shell
command per task-file line, with a bounded number of concurrent workers.

Source: [lib/io/parallel.sh](../../../lib/io/parallel.sh) · Tier: `@shell bash4,zsh`

## Loading

```bash
#!/usr/bin/env bs

load "lib/io/parallel"
```

The module works in bash 4.2+ and zsh. It enables zsh's `KSH_ARRAYS` and
`SH_WORD_SPLIT` options so zero-based arrays and quoted expansions behave like
bash.

## API

```bash
io::parallel::map --jobs N --out-dir DIR [--scheduler pid|fifo|xargs] -- callback item...
io::parallel::run --jobs N --out-dir DIR [--scheduler pid|fifo|xargs] -- tasks.txt
io::parallel::cancel
```

- `--jobs N` and `--out-dir DIR` are required; `N` must be a positive integer
  no greater than `2147483647`.
- `--help` prints usage to stderr and returns `E_SUCCESS` without starting work.
- There is exactly one `--` separator. The callback and all items follow it, so
  an item such as `--jobs` remains positional data.
- `map` invokes `callback` with one item as `$1`. Arguments are never evaluated
  or word-split; spaces and newlines stay inside the item.
- `run` reads one command per non-empty, non-comment line and executes it with
  `bash -c`. Blank lines and comments whose first non-space character is `#`
  are ignored. Task files are trusted shell input, not data to be quoted.
- An empty item list or a task file containing only comments/blank lines returns
  success without writing result files.
- Public functions keep stdout clean. Diagnostics go to stderr.

## Results

Results are files in `--out-dir`, indexed from zero in input order:

| File | Content |
|---|---|
| `NNNN.out` | worker stdout |
| `NNNN.err` | worker stderr |
| `NNNN.rc` | worker exit status as a decimal number |

The index is padded to at least four digits. Workers write into a private
staging directory inside `--out-dir`; completed files are then published under
their final names with `mv -T` (no target-directory interpretation). Existing
regular files and other non-directory entries are replaced, existing symlinks
are replaced rather than followed, and directories cause `E_ERROR`. Unrelated
files and stale higher indexes are not removed.

A worker failure does not stop the remaining work. The function returns
`E_ERROR` after every task has been attempted, and each `.rc` preserves the
individual status.

## Schedulers

| Scheduler | Behavior |
|---|---|
| `pid` | Default. Background workers plus `wait PID`; no scheduler-specific dependency. |
| `fifo` | Workers report completion through a FIFO; additionally requires `mkfifo`. |
| `xargs` | Reserved stub. Returns `E_ERROR` before creating the result directory or temporary state. |

Both implemented schedulers use standard `mkdir`, `mktemp`, `mv` and `rm`
utilities in addition to shell builtins. Safe publication requires `mv` with
`-T` support (GNU coreutils and BusyBox provide it).

## Exit codes

- `E_SUCCESS` (`0`) — all workers succeeded, or there was no work.
- `E_INVALID` (`2`) — invalid options, missing callback/task file, or unreadable task file.
- `E_ERROR` (`1`) — at least one worker failed, a result could not be persisted,
  cancellation was requested, `mkfifo` is unavailable, or the `xargs` stub was
  selected.

## Cancellation

SIGINT/SIGTERM stop active worker PIDs, preserve the result directory and files
already written, remove internal FIFO/temporary state, restore the caller's
previous INT/TERM traps, and make the pool return `E_ERROR`.
`io::parallel::cancel` requests the same cleanup programmatically and returns
`E_SUCCESS` itself.

Pool state is process-global: do not call `io::parallel::map` or
`io::parallel::run` recursively from a worker. Each callback runs in a supervised
child, so callback `exit` and `exec` still produce a result and FIFO completion.
If a callback starts further descendants, it should arrange for their
termination as well; cancellation targets the callback child and registered
worker PID.

## Examples

```bash
load "lib/io/parallel"

my_worker() {
    printf 'item=%s\n' "$1"
    printf 'diagnostic=%s\n' "$1" >&2
}

io::parallel::map --jobs 4 --out-dir results -- \
    my_worker alpha "two words" $'line1\nline2'

io::parallel::run --jobs 4 --scheduler fifo --out-dir results -- tasks.txt
```

A task file for `run`:

```bash
# comments and blank lines are ignored
printf 'first\n'
printf 'second\n' >&2
false
printf 'still runs\n'
```

Runnable demo: [examples/parallel_demo.sh](../../../examples/parallel_demo.sh).

## See also

- [io-process.md](io-process.md) — supervise one long-running process.
- [io-streams.md](io-streams.md) — low-level stream and FD operations.
