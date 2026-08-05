[↑ Documentation index](README.md)

# Best Practices

High-level conventions for writing and maintaining the BS framework.
For the detailed style rules see the [Code Style Guide](code-style-guide.md);
for day-to-day module development see the [Developer Guide](08-development/README.md).

## Project structure

```text
bootstrap/       # init.sh and loader.sh — module loading and dependency resolution
core/            # Kernel: const, logger, errorhandler, args, utils, version, config, deps, prereq
lib/             # Standard library: io/, system/, ui/, integration/, data/, network/, status/, audit/
install/         # Modular installer: main.sh, actions.sh, checks.sh, path_manager.sh
tests/           # Custom test framework, unit / integration / demos
bs               # CLI entry point and shebang interpreter
boot.sh          # Library-mode launcher
documentation/   # Guides, API references, examples
```

Key entry points:

- Shebang mode: scripts start with `#!/usr/bin/env bs` (sets `BS_SHEBANG=1`).
- CLI: `bs help|version|env|list|doctor|run|init-shell`.
- Initialization: source `bootstrap/init.sh` from `BS_ROOT` to load core and set flags.

## Test strategy

- Use the custom framework in `tests/testframework.sh`:
  `testframework::assert_true`, `assert_equal`, `assert_file_exists`, `assert_command`.
- Organize tests by scope:
  - `tests/unit/*` — single module behavior and edge cases.
  - `tests/integration/*` — cross-module flows and loader behavior.
  - `tests/demos/*` — user-facing usage scenarios.
- Run the suite with `bash tests/runalltests.sh`; validate syntax with
  `bash tests/validatesyntax.sh` and ShellCheck with `bash tests/validateshellcheck.sh`.
- Mock external commands (curl, jq, openssl) by wrapping them in small functions
  that can be stubbed via function indirection or environment variables.

See [Testing](07-testing/README.md) for the full guide.

## Code style summary

- Shebang: `#!/usr/bin/env bs` for scripts and library examples;
  `#!/usr/bin/env bash` for `core/` and entry points.
- Strict mode (`set -euo pipefail` and safe `IFS`) is set **only in entry points**,
  never inside sourced modules.
- Quote every variable expansion: `"${var}"`.
- Use namespaced functions: `module::submodule::function()`.
- Constants are `SCREAMING_SNAKE_CASE` and `readonly`.
- Environment variables use the `BS_*` prefix (`BS_ROOT`, `BS_LOG_LEVEL`, …).
- Always use a Source Guard at the top of a module:
  `bs::guard "MODULE_NAME" || return 0`.
- Load framework modules with `load "path/to/module"` so the loader resolves
  dependencies and prevents double loading.
- Self-source dependencies with `bs::source_relative` for direct-sourcing support.

See the [Code Style Guide](code-style-guide.md) for details.

## Common patterns

- **Module loader**: declare dependencies in a `# @depends core/const, core/logger`
  comment; the loader detects cycles via `BS_LOAD_STACK` and deduplicates loads
  via `BS_LOADED_MODULES`.
- **Centralized shell checks**: validate Bash 4+ through a single helper
  (`core/utils.sh::utils::ensure_shell_version` / `install/utils.sh::ensure_bash4`).
  Do not scatter ad-hoc `BASH_VERSINFO` checks across files.
- **Logging**: use `log::info|warn|error|debug|trace|success|fatal` and configure
  output via `BS_LOG_LEVEL`, `BS_LOG_COLOR`, `BS_LOG_FORMAT`, `BS_LOG_TIMESTAMP`.
- **Error handling**: throw through the errorhandler; register cleanup actions
  with `cleanup::add`; exit cleanly — never `kill -9 $$`.
- **Paths**: resolve everything from `BS_ROOT`; verify that
  `${BS_ROOT}/bootstrap/init.sh` exists before sourcing.
- **Caching / rate limiting**: use configurable cache dirs
  (`${BS_ROOT:-/tmp}/...`) and TTL-based expiry; guard helper usage with
  `function_exists` when the logger may not be loaded yet.
- **Cross-platform**: branch package managers and installers conservatively using
  `lib/system/platformcheck.sh`.

## Do's and Don'ts

- ✅ Do keep modules idempotent; use `*_INITIALIZED` flags.
- ✅ Do use `utils::has`, `utils::quiet`, `utils::quiet_err`, `utils::ignore`
  instead of raw `/dev/null` redirects.
- ✅ Do document public functions with `@description`, `@param`, `@returns`,
  `@example`.
- ✅ Do gate external tool usage and provide install guidance or auto-install.
- ❌ Don't hardcode `/tmp`; prefer `${BS_ROOT:-/tmp}` or configurable paths.
- ❌ Don't source framework modules by hand with `source lib/...`; use `load`.
- ❌ Don't source files without the `.sh` extension when using direct `source`.
- ❌ Don't assume logger/errorhandler availability; guard with `function_exists`
  where optional.

## Tools & dependencies

- **Shell**: Bash 4+ is required for associative arrays and the loader.
  zsh may invoke the CLI, but execution always happens in Bash.
- **Core tools** (module-dependent): `jq`, `curl`, `openssl`, `coreutils`
  (`base64`).
- **Install wrappers**:
  - Local: `~/.local/bin/bs` exports `BS_ROOT="$HOME/.local/lib/bs"`.
  - System: `/usr/local/bin/bs` exports `BS_ROOT="/usr/local/lib/bs"`.
- **Configuration env vars**: `BS_ROOT`, `BS_LOG_LEVEL`, `BS_LOG_COLOR`,
  `BS_LOG_FORMAT`, `BS_LOG_TIMESTAMP`.

## Other notes

- Prefer `load` over raw `source` to benefit from dependency parsing and
  deduplication.
- In shebang mode `bs` sets `BS_SHEBANG=1` and runs the script after init;
  do not re-initialize inside the script.
- Keep naming consistent: `log::` (not `logger::`), `bs::` (not `bosa::`),
  `BS_*` (not `BOSA_*`).
- When adding a module:
  1. Place it under `core/` or the appropriate `lib/<group>/`.
  2. Use a clear namespace and a Source Guard.
  3. Declare `# @depends` where applicable.
  4. Add unit tests in `tests/unit/` and integration tests in
     `tests/integration/` for cross-module behavior.
