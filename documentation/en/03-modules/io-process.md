[↑ Table of Contents](../README.md)

# Module `io::process`

Process Guard is a supervisor wrapper for running arbitrary commands.
It monitors total runtime (`--timeout`) and output activity (`--hang-after`),
collects a diagnostic snapshot on timeout/hang, and terminates the process
gracefully.

Source: [lib/io/process.sh](../../../lib/io/process.sh)

## Loading

```bash
#!/usr/bin/env bs

load "lib/io/process"
```

Or manually:

```bash
source bootstrap/init.sh
load "lib/io/process"
```

## API

```bash
io::process::guard [options] -- command [args...]
```

**Important:** if the command itself has `--` arguments, put `--` before the
command so the guard does not try to parse them as its own options.

## Options

| Option | Env variable | Purpose |
|---|---|---|
| `--timeout <sec>` | `BS_PROCESS_GUARD_TIMEOUT` | Total time limit, `0` disables. |
| `--hang-after <sec>` | `BS_PROCESS_GUARD_HANG_AFTER` | stdout/stderr silence limit, `0` disables. |
| `--strace-duration <sec>` | `BS_PROCESS_GUARD_STRACE_DURATION` | How long to run each strace (default 5). |
| `--strace-file` / `--no-strace-file` | `BS_PROCESS_GUARD_STRACE_FILE` | strace `read,write,%file`. |
| `--strace-net` / `--no-strace-net` | `BS_PROCESS_GUARD_STRACE_NET` | strace `%net`. |
| `--diagnostic-dir <path>` | `BS_PROCESS_GUARD_DIAGNOSTIC_DIR` | Report directory. Defaults to `mktemp -d`. |
| `--kill-signal <SIG>` | `BS_PROCESS_GUARD_KILL_SIGNAL` | Termination signal, default `TERM`. |
| `--grace-period <sec>` | `BS_PROCESS_GUARD_GRACE_PERIOD` | Time between signal and `KILL`, default 5. |
| `--sudo` / `--no-sudo` | `BS_PROCESS_GUARD_SUDO` | Force/ignore `sudo` for strace. |

## Exit codes

- command exit code — on normal completion;
- `124` (`IO_PROCESS_EXIT_TIMEOUT`) — `--timeout` fired;
- `125` (`IO_PROCESS_EXIT_HANG`) — `--hang-after` fired;
- `126` (`IO_PROCESS_EXIT_KILLED`) — process had to be force-killed;
- `2` (`E_INVALID`) — argument error.

## Examples

```bash
# Limit a file download to 60 seconds
io::process::guard --timeout 60 -- wget https://example.com/file.iso

# Consider the process hung if there is no output for 30 seconds
io::process::guard --timeout 120 --hang-after 30 -- ./long-task

# Capture network strace on hang
io::process::guard --timeout 120 --hang-after 30 --strace-net \
  --diagnostic-dir /var/log/bs/guard -- ./server
```

## Diagnostic report

When the guard fires, it creates the following in the specified (or auto-created)
report directory:

- `report.log` — timestamp, reason, PID, command line, `ps`, `/proc/<pid>/status`,
  `cmdline`, `stack`, `fd/` listing, `wchan`;
- `strace_file.log` — strace with filter `read,write,%file` (if strace and root
  / passwordless sudo are available);
- `strace_net.log` — strace with filter `%net` (if `--strace-net` is set).

## Dry-run mode

When `FRAMEWORK_DRY_RUN=true` the guard only logs the command and does not run it.

```bash
export FRAMEWORK_DRY_RUN=true
io::process::guard --timeout 60 -- sleep 10
```

## See also

- [io-streams.md](io-streams.md) — I/O stream management.
- [io-files.md](io-files.md) — file operations.
