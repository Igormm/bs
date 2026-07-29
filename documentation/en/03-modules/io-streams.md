[↑ Documentation index](../README.md)

# Module `io::streams`

Abstraction over I/O streams, file descriptors and redirections: safe output,
`exec` redirections, FD save/restore, pipes, stdio buffering and `/dev`
special files.

Source: [lib/io/streams.sh](../../../lib/io/streams.sh)

## Loading

```bash
#!/usr/bin/env bs

load "lib/io/streams"
```

Or manually:

```bash
source bootstrap/init.sh
load "lib/io/streams"
```

## Output

`print` uses `printf '%s\n'` instead of `echo`, so values like `-n`, `-e`
or strings with backslashes are printed literally. `printf` takes the format
as a separate argument, so data never lands in the format string.

```bash
io::streams::print "hello"        # line with trailing newline
io::streams::printn "no newline"  # no trailing newline
io::streams::printf '%04d' 7      # formatted output (format-string safe)
io::streams::eprint "to stderr"   # line to stderr
io::streams::tty_print "bypass"   # to /dev/tty, ignoring redirections
```

`tty_print` writes to the controlling terminal even when stdout/stderr are
redirected to a file or pipe; it returns 1 if there is no controlling terminal.

## Input

```bash
io::streams::read_line var            # one line from stdin into a variable
io::streams::read_line var 3          # one line from FD 3
io::streams::read_all < file.txt      # the whole stream until EOF
io::streams::feed "input" grep data   # feed a string to a command's stdin (<<<)
```

`read_line` returns 1 on EOF, which makes it usable in `while` loops.
`feed` is a here-string (`<<<`) wrapper; it returns the command's exit code.

## Redirections and FD save/restore

Redirections affect the **current** shell (`exec`). Run them in a subshell
`( ... )` if you need to keep your own streams intact.

```bash
io::streams::redirect_stdout "out.log"    # exec 1>file
io::streams::redirect_stderr "err.log"    # exec 2>file
io::streams::redirect_all "all.log"       # exec >file 2>&1 — order matters:
                                          # >file first, then 2>&1
io::streams::silence                      # exec >/dev/null 2>&1
```

To redirect temporarily, save the FD first and restore it afterwards:

```bash
io::streams::save 1 saved_fd        # dup(1) equivalent; the new FD number
                                    # goes into a variable, NOT via $(...)
                                    # (a subshell would close the FD)
io::streams::redirect_stdout "capture.log"
# ... output goes to capture.log ...
io::streams::restore "${saved_fd}" 1   # dup2 + close of the temp FD (no leaks)
io::streams::close 3                   # exec 3>&-
```

Only the standard FDs 0, 1, 2 can be saved/restored. `restore` closes the
temporary descriptor to avoid FD leaks (`EMFILE`).

## Pipes and stdio buffering

```bash
io::streams::pipe printf 'a\nb\n' -- grep b   # cmd1 | cmd2, '--' is the separator
io::streams::run_line_buffered tail -f app.log  # stdbuf -oL -eL
io::streams::run_unbuffered long_task           # stdbuf -o0 -e0
```

Reminder: stdout is line-buffered on a terminal and fully buffered on
pipes/files; stderr is not buffered at all. The `run_*` helpers require
`stdbuf` and check it with `utils::has`; they return 1 if it is missing.

## `/dev` special files

```bash
io::streams::null_sink noisy_cmd      # cmd >/dev/null 2>&1, exit code preserved
io::streams::random_bytes 32 | base64 # N bytes from /dev/urandom (non-blocking)
io::streams::fd_path 0                # prints /dev/fd/0
io::streams::list_fds                 # open FDs via /proc/self/fd (or /dev/fd)
```

For one-off output suppression outside of this module, prefer the idioms from
[core/utils.sh](../../../core/utils.sh): `utils::quiet cmd`
(`cmd >/dev/null 2>&1`), `utils::quiet_err cmd` (`cmd 2>/dev/null`) or
`utils::ignore cmd` (`cmd >/dev/null 2>&1 || true`) — `null_sink` is the
module-level equivalent of `utils::quiet`.

## Stream state checks

```bash
io::streams::is_tty 1              # is FD 1 a terminal ([[ -t 1 ]])
io::streams::can_read 0            # non-blocking readability check
                                   # (no data is consumed)
io::streams::wait_readable 0 5     # wait up to 5 s for data (poll/select
                                   # equivalent); on success consumes 1 byte
```

Typical use of `is_tty`: enable colors and progress bars only on a terminal.
Note the trade-off: `can_read` peeks without consuming, while `wait_readable`
consumes one byte on success.

## Examples

Runnable demos (from the repository root):

```bash
bs run examples/iostreams_output_example.sh           # print/printn/printf/eprint/tty_print
bs run examples/iostreams_input_example.sh            # read_line/read_all/feed
bs run examples/iostreams_redirection_example.sh      # redirect_*/silence
bs run examples/iostreams_fd_example.sh               # save/restore/close
bs run examples/iostreams_pipe_buffering_example.sh   # pipe/run_line_buffered/run_unbuffered
bs run examples/iostreams_dev_example.sh              # null_sink/random_bytes/fd_path/list_fds
bs run examples/iostreams_state_example.sh            # is_tty/can_read/wait_readable
bs run examples/logmonitorexample.sh                  # live monitor: can_read + pipes + /dev/fd
```

Sources: [examples/iostreams_output_example.sh](../../../examples/iostreams_output_example.sh),
[examples/iostreams_input_example.sh](../../../examples/iostreams_input_example.sh),
[examples/iostreams_redirection_example.sh](../../../examples/iostreams_redirection_example.sh),
[examples/iostreams_fd_example.sh](../../../examples/iostreams_fd_example.sh),
[examples/iostreams_pipe_buffering_example.sh](../../../examples/iostreams_pipe_buffering_example.sh),
[examples/iostreams_dev_example.sh](../../../examples/iostreams_dev_example.sh),
[examples/iostreams_state_example.sh](../../../examples/iostreams_state_example.sh),
[examples/logmonitorexample.sh](../../../examples/logmonitorexample.sh).
