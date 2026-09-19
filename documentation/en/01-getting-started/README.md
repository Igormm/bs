[↑ Documentation index](../README.md)

# Getting Started

## What is BS

**BS** is a modular framework and standard library for Bash 4+. It provides
a module loader, logging, error handling, declarative script arguments, an
I/O streams abstraction, and a set of system modules — all in one consistent
code style and with zero external dependencies.

## Requirements

- Bash 4.4+ (CI minimum)
- Linux (primary platform; macOS is partially supported)

Nothing else is required: BS relies on bash built-ins and standard system
tools only.

## Installation

BS runs straight from the repository — installation is optional and only
puts the `bs` command into your `PATH`.

### Run from the repository

```bash
git clone <repo-url> bs
cd bs
./bs doctor
```

### Local install (`~/.local`, no sudo)

```bash
./install.sh --local
```

Copies the framework to `~/.local/lib/bs`, creates a wrapper at
`~/.local/bin/bs`, and adds `~/.local/bin` to `PATH` in `~/.bashrc` /
`~/.zshrc` (idempotently). PATH helpers:

```bash
./install.sh --local --path          # print the export snippet
./install.sh --local --update-path   # add to ~/.bashrc / ~/.zshrc
```

### System install (`/usr/local`, requires root)

```bash
sudo ./install.sh
```

Files go to `/usr/local/lib/bs`, the wrapper to `/usr/local/bin/bs`.

Install locations can be overridden with the `PREFIX`, `BIN_DIR`, and
`LIB_DIR` environment variables.

### Uninstall

```bash
sudo ./install.sh uninstall      # system
./install.sh --local uninstall   # local
```

> **Note on the source directory.**  
> The installer **copies** BS files to the target directory
> (`~/.local/lib/bs` for `--local`, `/usr/local/lib/bs` for system
> install; paths can be overridden via `PREFIX`/`LIB_DIR`/`BIN_DIR`)
> and creates a `bs` wrapper in the matching `bin/`. After a successful
> install, the source repository can be removed — the framework will
> run from the target directory.

## Verify the installation

```bash
./bs doctor    # framework integrity check
./bs list      # list modules
./bs version   # framework version
```

- `bs doctor` checks that `bootstrap/init.sh`, the core modules, and the
  `core/` and `lib/` directories are present under `BS_ROOT`, and exits
  non-zero if anything is missing.
- `bs list` prints the modules located directly in `core/` and `lib/`
  (for example `core/args.sh`, `lib/automation.sh`). Nested modules such as
  `lib/io/streams.sh` live in subdirectories and are loaded by path.

## Your first script

Runnable copy: [examples/hello.sh](../../../examples/hello.sh).

```bash
#!/usr/bin/env bs
# shellcheck shell=bash
set -euo pipefail

load "lib/io/streams"

io::streams::print "hello from BS ${BS_VERSION}"
```

- `#!/usr/bin/env bs` — runs the script through the `bs` interpreter; the
  framework core is loaded before your code, so no bootstrap boilerplate is
  needed.
- `# shellcheck shell=bash` — required on line 2 when the shebang is `bs`.
- `set -euo pipefail` — strict mode belongs in entry points (scripts, tests),
  never inside `lib/` or `core/` modules.
- `load "lib/io/streams"` — path relative to `BS_ROOT`, no `.sh`. Never
  `source` framework modules directly in a new script.
- `io::streams::print` — safe output: a `printf '%s\n'` wrapper that does
  not break on values like `-n` or `-e`. `BS_VERSION` is set by core.

## Running scripts

```bash
./bs run examples/hello.sh
./examples/hello.sh          # when bs is in PATH
```

Landing examples:

```bash
./bs run examples/hello.sh     # short script
./bs run examples/todo.sh      # TUI todo list (lib/tui)
./bs run examples/pulse.sh     # host capability pulse
```

CLI with `core/args` (auto-help, validation) is in the
[first-script tutorial](../05-tutorials/first-script.md).

## Where to go next

- [Architecture](../02-core-concepts/architecture.md) — boot stages,
  `BS_ROOT`, the module loader
- [core/args module](../03-modules/args.md) — parameter trees, flags,
  bash completion
- [lib/io/streams module](../03-modules/io-streams.md) — safe printing,
  redirection, pipes
- [Tutorial: your first script](../05-tutorials/first-script.md) — a
  step-by-step walkthrough

See also the [repository README](../../../README.md) and the runnable
examples in [examples/](../../../examples/).
