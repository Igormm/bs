# BS Documentation

**BS** is a modular framework. Its `core/` runs in any shell of the registry: bash, zsh, dash, busybox ash, ksh, mksh; from fish and nushell through `bs call`. The shell registry is `bootstrap/shell.sh` (a table is in [shell-portability](08-development/shell-portability.md)).

- **Install for your shell:** `./install.sh --local --update-path --shell fish` (PATH and hints are set for that shell).
- **Run for a specific shell:** `bs --strict-shell=dash COMMAND` checks whether the command fits that shell; from fish and nushell, kernel functions are called with `bs call FUNCTION`.

**The main library `lib/` is bash 4.2+ only for now.** So BS as a whole requires bash 4.2+, while the kernel is becoming shell-independent step by step: 13 of 15 `core/` files are already POSIX.

Русская версия: [documentation/ru/](../ru/README.md)

## Start here

1. [Getting Started](01-getting-started/README.md) — installation, `bs doctor`, `examples/hello.sh`.
2. [Architecture](02-core-concepts/architecture.md) — how loading works: `boot.sh` → `bs` → `bootstrap/init.sh` → `loader.sh` → `core/` → `lib/`.
3. [Tutorial: Your First Script](05-tutorials/first-script.md) — step by step: from an empty file to a CLI utility.

## Module references

- [core/args](03-modules/args.md) — declarative argument trees: validation, auto-help, completion.
- [core/utils](03-modules/core-utils.md) — silence idioms (`utils::has`, `utils::quiet`, `utils::quiet_err`, `utils::ignore`) and helper utilities.
- [lib/io/streams](03-modules/io-streams.md) — output, input, redirections, FDs, pipes, buffering.
- [Lib modules overview](03-modules/lib-modules-overview.md) — system, ui, network, data, integration, status, audit and more.
- [Core API](04-api-reference/core-api.md) — `log::*`, `error::*`, `cleanup::*`, exit codes, version.

## Practice

- [Examples](06-examples/README.md) — every script in `examples/` with run commands.
- [Testing](07-testing/README.md) — test framework, validators, CI matrix.
- [Installation](install.md) — installation types (system/local/custom), install manifest, `bs update` (local repo or GitHub), `bs where` (traces of BS on a machine), PATH manager, uninstall.

## For developers

- [Developer guide](08-development/README.md) — writing modules, `# @depends`, pre-commit checks.
- [Code style guide](code-style-guide.md) — project conventions.
- [Best practices](best-practices.md) — high-level guidelines for contributors.
- [Migration BOSA → BS](09-migration-bosa-to-bs.md) — renaming tables for those who knew the old version.
