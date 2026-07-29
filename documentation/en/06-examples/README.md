[↑ Documentation index](../README.md)

# Examples overview

The [examples/](../../../examples/) directory contains runnable scripts that
demonstrate the framework modules on real tasks. All examples are standalone
BS scripts: they start with the `#!/usr/bin/env bs` shebang and load modules
via `load "core/args"`, `load "lib/io/streams"`, etc.

## Running examples

From the repository root:

```bash
./bs run examples/<file> [args]
```

If `bs` is in your `PATH`, the scripts are also directly executable:

```bash
./examples/<file> [args]
```

## Examples

| File | Demonstrates | Run |
| --- | --- | --- |
| [bs_test.sh](../../../examples/bs_test.sh) | Smoke test: loading of core modules (`core/version`, `core/logger`, `core/const`, `core/errorhandler`) and basic `log::info` / `log::warn` / `log::error` output | `./bs run examples/bs_test.sh` |
| [argsparseexample.sh](../../../examples/argsparseexample.sh) | `args` module: parameter tree (`args::level`, `args::describe`), flags, automatic validation and help, bash completion | `./bs run examples/argsparseexample.sh deploy now`<br>`./bs run examples/argsparseexample.sh --help` |
| [deploytoolexample.sh](../../../examples/deploytoolexample.sh) | Mini deploy tool: `args` + `io::streams` combo — parameter tree, `--env` / `--dry-run` flags, auto-help, logging the deploy section to a file via FD `save` / `restore` | `./bs run examples/deploytoolexample.sh deploy --env production --dry-run` |
| [passwordgenexample.sh](../../../examples/passwordgenexample.sh) | Password generator from `/dev/urandom` with `--length`, `--count`, `--hex` flags and a strength estimate | `./bs run examples/passwordgenexample.sh --length 24 --count 5` |
| [logmonitorexample.sh](../../../examples/logmonitorexample.sh) | Live log monitor: a background service writes to a pipe, the monitor reads it non-blockingly via `io::streams::can_read` and counts ERROR statistics | `./bs run examples/logmonitorexample.sh` |
| [quizgameexample.sh](../../../examples/quizgameexample.sh) | Timed quiz: the answer is awaited via `io::streams::wait_readable` (poll/select equivalent) instead of a blocking `read`; auto mode without a terminal | `./bs run examples/quizgameexample.sh` |
| [iostreams_output_example.sh](../../../examples/iostreams_output_example.sh) | Safe output: `io::streams::print`, `printn`, `printf`, `eprint`, `tty_print` | `./bs run examples/iostreams_output_example.sh` |
| [iostreams_input_example.sh](../../../examples/iostreams_input_example.sh) | Input: `io::streams::read_line`, `read_all`, `feed` | `./bs run examples/iostreams_input_example.sh` |
| [iostreams_redirection_example.sh](../../../examples/iostreams_redirection_example.sh) | Redirections: `io::streams::redirect_stdout`, `redirect_stderr`, `redirect_all`, `silence` | `./bs run examples/iostreams_redirection_example.sh` |
| [iostreams_fd_example.sh](../../../examples/iostreams_fd_example.sh) | FD management: `io::streams::save`, `restore`, `close` (dup/dup2 equivalents) | `./bs run examples/iostreams_fd_example.sh` |
| [iostreams_pipe_buffering_example.sh](../../../examples/iostreams_pipe_buffering_example.sh) | Pipes and stdio buffering: `io::streams::pipe`, `run_line_buffered`, `run_unbuffered` | `./bs run examples/iostreams_pipe_buffering_example.sh` |
| [iostreams_state_example.sh](../../../examples/iostreams_state_example.sh) | Stream state checks: `io::streams::is_tty`, `can_read`, `wait_readable` | `./bs run examples/iostreams_state_example.sh` |
| [iostreams_dev_example.sh](../../../examples/iostreams_dev_example.sh) | `/dev` special files: `io::streams::null_sink` (`/dev/null`), `random_bytes` (`/dev/urandom`), `fd_path` (`/dev/fd/N`), `list_fds` (`/proc/self/fd`) | `./bs run examples/iostreams_dev_example.sh` |
| [ps1configurationexample.sh](../../../examples/ps1configurationexample.sh) | Interactive PS1 prompt configuration via the `lib/ui/ps1config` module: themes, git info, SSH and virtualenv detection, time format | `echo 7 \| ./bs run examples/ps1configurationexample.sh` |

## Additional documentation in examples/

- [examples/README.md](../../../examples/README.md) — detailed description of
  the example set (partially refers to the old BOSA naming).
- [examples/README bs_test.md](../../../examples/README%20bs_test.md) —
  description of the `bs_test.sh` smoke test.
