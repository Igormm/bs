# 📘 Project Best Practices

## 1. Project Purpose
BS (Bash Open Source Architecture or BOSA) is a modular Bash framework for building maintainable CLI tools and shell-based systems. It provides a unified entrypoint (bs), bootstrap orchestration, a robust module loader, structured logging, error handling, and a library of reusable modules (system, UI, data integrations). It targets Bash 4+ while keeping zsh compatibility for user shells invoking the tools.

## 2. Project Structure
- bootstrap/
  - init.sh: Initializes BS_ROOT, idempotently loads core modules via loader, sets flags (BS_INITIALIZED).
  - loader.sh: Module loader with cycle detection, dependency parsing (@depends), eager/lazy load support, BS_* global tracking.
- core/
  - const.sh: Common constants and version helpers.
  - logger.sh: Logging system (log::info, log::warn, log::error, log::debug, log::trace) configurable via BS_LOG_* env vars.
  - errorhandler.sh: Cleanup stack, backtraces, exit/panic helpers, retry/try patterns.
  - version.sh: Framework version and name.
- lib/
  - system/: platform detection, packages, services, processes, users, network, etc.
  - ui/: interactive UI helpers and themes.
  - data/: algorithms, monads, etc.
  - integration/: integrations such as vkapi with caching, retries, and dependency checks.
- install/
  - main.sh, actions.sh, checks.sh, path_manager.sh, utils.sh: Modular installer; generates wrapper that exports BS_ROOT then execs bs.
- tests/
  - unit/, integration/, demos/, runalltests.sh, testframework.sh: Organized test suites covering modules and flows.
- bs: Unified entrypoint for CLI and shebang-interpreter mode; resolves BS_ROOT, ensures bootstrap/init.sh, dispatches commands.
- boot.sh: Project launcher (library mode).
- documentation/: Guides, refactoring notes, API references, examples.

Key entrypoints and setup:
- Shebang mode: Scripts can start with `#!/usr/bin/env bs`, which sets BS_SHEBANG=1 and executes via the framework.
- CLI: `bs help|version|env|list|doctor|run|init-shell`.
- Initialization: Source `bootstrap/init.sh` from BS_ROOT to load core and set flags.

## 3. Test Strategy
- Frameworks/tools:
  - Custom test framework (tests/testframework.sh) with assertions (assert_true, assert_equal, assert_file_exists, assert_command).
- Organization:
  - Unit tests: tests/unit/* focus on single modules (e.g., logger).
  - Integration tests: tests/integration/* validate cross-module flows (init, loading, shebang mode, installation).
  - Demos: tests/demos/* show example usage scenarios.
  - Runner: tests/runalltests.sh orchestrates suites; validates syntax via tests/validatesyntax.sh.
- Naming and invocation:
  - Scripts named test_*.sh; run with Bash.
  - Initialize BS in tests: `source "../testframework.sh"; source "../../boot.sh"; bs::init`.
- Mocking guidelines:
  - Prefer dependency injection via env vars and function indirection.
  - For external commands (curl/jq/openssl), gate calls via small wrapper functions to enable stubbing.
- Coverage philosophy:
  - Unit tests for core behavior and edge cases.
  - Integration tests for module interactions and loader behavior (including @depends resolution).
  - Demo tests for user-facing flows (install, run, UI).

## 4. Code Style
- Shell options:
  - Always set `set -euo pipefail` at the top of executable scripts and modules.
- Shell version/compat:
  - Require Bash 4+ for loader and associative arrays, but allow invocation from zsh user shells.
  - Centralize shell checks using a shared utility (see “Common Patterns”).
- Naming conventions:
  - Namespaced functions with double-colon: `module::submodule::function` or `namespace::function`.
  - Constants in ALL_CAPS with BS_ or domain-specific prefixes.
  - Environment variables use the BS_* prefix (e.g., BS_ROOT, BS_LOG_LEVEL).
- Sourcing and module loading:
  - Use `load "path/to/module"` for framework modules (relative to BS_ROOT), or `source "${BS_ROOT}/path/to/file.sh"` when load isn’t appropriate.
  - Always include explicit `.sh` extension when sourcing files directly.
- Quoting and safety:
  - Quote all variable expansions (`"${var}"`) especially in file ops (rm, cp, mv) and command arguments.
  - Use arrays for command execution when possible to avoid injection risks.
- Error handling:
  - Prefer errorhandler functions for uniform behavior (e.g., backtraces, cleanup stack).
  - Use cleanup::add to register reversible operations and cleanup::__run_all in exit paths.
- Logging and docs:
  - Use `log::` functions. Configure verbosity via BS_LOG_* vars.
  - Keep bilingual comments (RU/EN) concise. Document module purpose, parameters, and examples with `@description`, `@param`, `@example`.
- Idempotency:
  - Use flags like BS_INITIALIZED to ensure multiple sourcing is safe.

## 5. Common Patterns
- Module loader:
  - `load` with dependency detection from `# @depends` comments.
  - Circular dependency detection via BS_LOAD_STACK.
  - BS_LOADED_MODULES for deduplication.
- Centralized shell environment checks:
  - Prefer a single reusable function (e.g., install/utils.sh: ensure_bash4 or install scripts’ check_shell_environment) to validate shell/version early.
  - Replace ad-hoc `BASH_VERSINFO` checks with the shared helper to support zsh invocation with bash execution.
- Logging:
  - `log::info|warn|error|debug|trace|success|fatal`, configured via:
    - BS_LOG_LEVEL, BS_LOG_COLOR, BS_LOG_FORMAT, BS_LOG_TIMESTAMP.
- Error handling:
  - Backtrace printing with controlled depth.
  - `error::panic` exits cleanly (no kill -9).
  - Retry patterns and safe exit codes; prefer throwing through a single handler.
- Path resolution:
  - Always resolve paths from BS_ROOT; avoid relative paths.
  - Ensure `${BS_ROOT}/bootstrap/init.sh` exists before sourcing.
- Caching and rate-limiting (vkapi):
  - Configurable cache dir (`${BS_ROOT:-/tmp}/vk_api_cache`).
  - TTL-based cache and request rate limiting with exponential-ish backoff.
  - Local helper `function_exists` when logger may be absent.
- Cross-platform support:
  - Use platformcheck module to branch installers and package managers conservatively.

## 6. Do's and Don'ts
- ✅ Do
  - Use `set -euo pipefail` and quote all variables.
  - Use the loader (load) or BS_ROOT-based absolute paths for sourcing.
  - Keep modules idempotent; set and check initialization flags.
  - Use BS_* environment variable names consistently.
  - Centralize shell checks (ensure_bash4/check_shell_environment) and call early in entrypoints.
  - Add cleanup handlers via cleanup::add and rely on errorhandler for structured exits.
  - Provide clear `@description`, `@param`, `@example` headers for public functions.
  - Gate external tool usage behind checks and provide fallback messages or installation helpers.
- ❌ Don’t
  - Don’t hardcode /tmp paths; prefer `${BS_ROOT:-/tmp}` or configurable cache dirs.
  - Don’t use `kill -9 $$`; exit cleanly via errorhandler.
  - Don’t leave ad-hoc Bash version checks scattered across files; use a single helper for Bash 4+ enforcement.
  - Don’t source modules without `.sh` extension when using direct `source`.
  - Don’t assume logger/errorhandler availability; guard with `function_exists` where needed.

## 7. Tools & Dependencies
- Shell: Bash 4+ required for loader and associative arrays; zsh supported for invoking CLI but execution should happen in Bash.
- Core tools:
  - jq, curl, openssl, coreutils (base64) — required by certain integrations (e.g., vkapi).
- Setup:
  - Local install (no sudo): wrapper in `~/.local/bin/bs` exporting `BS_ROOT="$HOME/.local/lib/bs"` then `exec "$BS_ROOT/bs" "$@"`.
  - System install (sudo): wrapper in `/usr/local/bin/bs` exporting `BS_ROOT="/usr/local/lib/bs"` then `exec "$BS_ROOT/bs" "$@"`.
  - Ensure PATH includes `~/.local/bin` for local installs.
- Configuration env vars:
  - BS_ROOT: framework root; must exist before loading modules.
  - Logging: BS_LOG_LEVEL, BS_LOG_COLOR, BS_LOG_FORMAT, BS_LOG_TIMESTAMP.

## 8. Other Notes
- Prefer `load` for framework modules to leverage dependency parsing and duplication protection.
- In shebang mode, `bs` sets BS_SHEBANG=1 and runs the user script after init; do not re-init inside the script.
- Keep naming consistent: `log::` (not `logger::`), `bs::` (not `bosa::`), `BS_*` (not `BOSA_*`).
- When adding new modules:
  - Place in core/ or lib/ with clear namespacing.
  - Provide `@depends` header where applicable; ensure idempotent initialization.
  - Provide unit tests in tests/unit/ and, if cross-module, integration tests in tests/integration/.
- When adding shell checks or portability logic:
  - Use a shared helper (e.g., `ensure_bash4`) very early in entrypoints (bs, bootstrap/loader.sh) and avoid copy-pasted checks.
``````markdown
# 📘 Project Best Practices

## 1. Project Purpose
BS (Bash Open Source Architecture) is a modular shell framework for building maintainable CLI tools and shell-based systems. It provides a unified entrypoint (bs), bootstrap orchestration, a robust module loader, structured logging, error handling, and a library of reusable modules (system, UI, data integrations). It targets Bash 4+ for execution while maintaining compatibility with zsh user shells for invocation.

## 2. Project Structure
- bootstrap/
  - init.sh: Initializes BS_ROOT, is idempotent via BS_INITIALIZED, loads core modules through the loader, prints optional info.
  - loader.sh: Module loader with cycle detection; parses `@depends`, supports eager/lazy loading registration and tracks loaded modules via BS_* globals.
- core/
  - const.sh: Framework constants and helpers (e.g., const::version).
  - logger.sh: Logging (log::info/warn/error/debug/trace/success/fatal) configurable via BS_LOG_* env vars.
  - errorhandler.sh: Cleanup stack, backtraces, exit/panic helpers, retry/try patterns.
  - version.sh: Framework version and name.
- lib/
  - system/: platform detection (platformcheck), packages, services, users, network, etc.
  - ui/: interactive UI helpers and themes (interactiveui, bosatheme).
  - data/: algorithms, monads, etc.
  - integration/: vkapi integration with caching, retries, dependency checks.
- install/
  - main.sh, actions.sh, checks.sh, path_manager.sh, utils.sh: Modular installer; generates wrappers that export BS_ROOT then exec bs.
- tests/
  - unit/, integration/, demos/, runalltests.sh, testframework.sh: Organized test suites.
- bs: Unified entrypoint for CLI and shebang mode; resolves BS_ROOT; ensures bootstrap/init.sh; dispatches commands.
- boot.sh: Project launcher (library mode).
- documentation/: Guides, refactoring notes, API references, examples.

Key entrypoints and setup:
- Shebang mode: Scripts can start with `#!/usr/bin/env bs` (BS_SHEBANG=1).
- CLI: `bs help|version|env|list|doctor|run|init-shell`.
- Initialization: Source `bootstrap/init.sh` from BS_ROOT to load core and set flags.

## 3. Test Strategy
- Test framework: Custom (tests/testframework.sh) with assertions: assert_true, assert_equal, assert_file_exists, assert_command.
- Organization:
  - Unit: tests/unit/* — isolate modules (e.g., logger).
  - Integration: tests/integration/* — cross-module flows (init, loader, install).
  - Demos: tests/demos/* — example scenarios, user-facing flows.
  - Runners: tests/runalltests.sh, tests/validatesyntax.sh.
- Conventions:
  - Test scripts named test_*.sh, executed with Bash.
  - Initialize BS: `source "../testframework.sh"; source "../../boot.sh"; bs::init`.
- Mocking:
  - Prefer DI via env vars and function indirection.
  - Wrap external tools (curl/jq/openssl) with small functions for stubbing.
- Coverage:
  - Unit for core logic/edge cases.
  - Integration for loader semantics and module interactions.
  - Demo for end-to-end usage and installation flows.

## 4. Code Style
- Shell options: Always `set -euo pipefail` at top of scripts/modules.
- Shell version/compat:
  - Require Bash 4+ (associative arrays) for runtime; allow zsh for invocation.
  - Centralize version checks via a shared helper (see Common Patterns).
- Naming:
  - Functions namespaced with double-colon: `module::submodule::function` or `namespace::function`.
  - Constants ALL_CAPS with BS_ or domain prefixes.
  - Env vars standardized to BS_* (BS_ROOT, BS_LOG_LEVEL, etc.).
- Sourcing & loading:
  - Prefer `load "path/module"` for framework modules relative to BS_ROOT.
  - When sourcing directly, always use explicit `.sh` extension and `${BS_ROOT}` absolute paths.
- Quoting & safety:
  - Quote all variable expansions, especially in file ops (rm/cp/mv) and command args.
  - Use arrays for command execution to avoid injection.
- Error handling:
  - Use errorhandler (try/retry/exit_with_backtrace) for uniform behavior.
  - Register cleanup via cleanup::add; rely on cleanup stack on exit.
- Documentation:
  - Bilingual concise comments (RU/EN).
  - Public functions: `@description`, `@param`, `@example`.
- Idempotency:
  - Use `*_INITIALIZED` flags to ensure safe multiple sourcing.

## 5. Common Patterns
- Module loader:
  - `load` reads `# @depends` to resolve dependencies.
  - Detects circular deps via BS_LOAD_STACK.
  - Deduplicates via BS_LOADED_MODULES.
- Centralized shell environment checks (refactoring guidance):
  - Use a single helper to enforce Bash 4+ and proper shell execution early.
  - Source it from early entrypoints (bs, bootstrap/loader.sh) instead of duplicating inline checks.
  - Recommended approach:
    - Create core/shell.sh:
      - ensure_bash4(): Validate Bash availability and major version >=4; print bilingual errors; return-safe for sourced contexts; exit for executed contexts.
      - maybe_ensure_bash_runtime(): Detect if invoked from non-bash shells (zsh) and exec bash if needed.
    - Source core/shell.sh first in bs and bootstrap/loader.sh, replacing ad-hoc `BASH_VERSINFO` guards.
    - Optionally export ensure_bash4 in install/utils.sh for installer scripts (already present there), but prefer core/shell.sh for framework runtime.
- Logging:
  - `log::info|warn|error|debug|trace|success|fatal`.
  - Env vars: BS_LOG_LEVEL, BS_LOG_COLOR, BS_LOG_FORMAT, BS_LOG_TIMESTAMP.
- Error handling:
  - Backtrace excluding internal frames.
  - error::panic exits cleanly (no `kill -9 $$`).
  - Consistent error codes (const.sh) and throwing via centralized handler.
- Paths:
  - Resolve from BS_ROOT; verify `${BS_ROOT}/bootstrap/init.sh` before sourcing.
- Caching & rate-limiting:
  - VK API uses `${BS_ROOT:-/tmp}/vk_api_cache`, TTL-based cache, rate limiting with retries and backoff.
  - Local `function_exists` shim where logger may be unavailable.
- Cross-platform:
  - platformcheck module for distro detection and package management branching.

## 6. Do's and Don'ts
- ✅ Do
  - Use `set -euo pipefail` and quote all variables.
  - Use `load` or `${BS_ROOT}`-absolute `source` paths; include `.sh` suffix when sourcing directly.
  - Keep modules idempotent with `*_INITIALIZED` flags.
  - Standardize on BS_* env vars; avoid BOSA_* in new code.
  - Centralize Bash 4+ checks: source core/shell.sh and call ensure_bash4 early in bs and loader.
  - Register cleanups and use errorhandler for structured exits and backtraces.
  - Gate external tool use via checks; provide install guidance or auto-install (platform-aware).
- ❌ Don’t
  - Don’t hardcode `/tmp`; prefer `${BS_ROOT:-/tmp}` or configurable locations.
  - Don’t use `kill -9 $$`; always exit cleanly through handlers.
  - Don’t duplicate Bash version checks across files; avoid inline `BASH_VERSINFO` guards.
  - Don’t source modules without `.sh` extension when not using the loader.
  - Don’t assume logger/errorhandler availability; guard with `function_exists` when optional.

## 7. Tools & Dependencies
- Shell: Bash 4+ required for runtime; zsh supported as user shell for invocation.
- Core tools (module-dependent): jq, curl, openssl, coreutils (base64).
- Installation:
  - Local: Wrapper in `~/.local/bin/bs` exports `BS_ROOT="$HOME/.local/lib/bs"` then `exec "$BS_ROOT/bs" "$@"`.
  - System: Wrapper in `/usr/local/bin/bs` exports `BS_ROOT="/usr/local/lib/bs"` then `exec "$BS_ROOT/bs" "$@"`.
  - Ensure PATH includes `~/.local/bin` for local installs.
- Configuration:
  - BS_ROOT must be valid before loading.
  - Logging configured via BS_LOG_* environment variables.

## 8. Other Notes
- Prefer `load` for framework modules to benefit from dependency resolution and deduplication.
- In shebang mode, `bs` sets `BS_SHEBANG=1` and runs the user script after init; avoid re-initialization inside scripts.
- Naming consistency: `log::` (not `logger::`), `bs::` (not `bosa::`), `BS_*` (not `BOSA_*`).
- Adding new modules:
  - Place under core/ or appropriate lib/ subdirectory with clear namespace.
  - Declare dependencies via `# @depends`.
  - Protect against double sourcing via the shared wrapper: `source "$(dirname -- "${BASH_SOURCE[0]}")/guard.sh"` (adjust the relative path to core/), then `bs::guard "NAME" || return 0`. Do not hand-roll `[[ -n "${__X_SOURCED:-}" ]] && return 0` idioms — `bs::guard` checks and sets the mark atomically.
  - Provide unit tests (tests/unit) and integration tests (tests/integration) as needed.
- Version check refactor plan for current codebase:
  - Implement core/shell.sh with ensure_bash4 and optional zsh-to-bash shimming.
  - Source core/shell.sh in bs (before doing anything else).
  - Source core/shell.sh at the top of bootstrap/loader.sh (return-safe when sourced).
  - Replace inline guards like:
    ```
    if [[ -z "${BASH_VERSION:-}" || ${BASH_VERSINFO[0]} -lt 4 ]]; then ... fi
    ```
    with:
    ```
    ensure_bash4 || exit 1
    ```
  - Keep install/utils.sh::ensure_bash4 for installer scripts, or re-export from core/shell.sh to avoid duplication.
``````markdown
# 📘 Project Best Practices

## 1. Project Purpose
BS (Bash Open Source Architecture) is a modular shell framework to build maintainable CLI tools and shell-based systems. It provides a unified entrypoint (bs), bootstrap orchestration, a robust module loader, structured logging, error handling, and a library of reusable modules (system, UI, data integrations). Runtime requires Bash 4+ (associative arrays), while zsh users can still invoke the tools (the framework should execute under Bash).

## 2. Project Structure
- bootstrap/
  - init.sh: Determines BS_ROOT, enforces idempotency with BS_INITIALIZED, loads core modules via loader, emits optional info (respects BS_SILENT).
  - loader.sh: Module loader with cycle detection. Parses `# @depends`, supports eager/lazy registration, tracks state in BS_LOADED_MODULES, BS_LAZY_MODULES, BS_LOAD_STACK.
- core/
  - const.sh: Common constants and helpers (e.g., const::version).
  - logger.sh: Logging API (log::info/warn/error/debug/trace/success/fatal) configurable by BS_LOG_* variables.
  - errorhandler.sh: Cleanup stack, backtrace logging, uniform exit/panic, retry/try helpers.
  - version.sh: Framework version and name strings.
- lib/
  - system/: platform detection (platformcheck), packages, services, users, network, processes, etc.
  - ui/: interactive UI helpers and themes (interactiveui, bosatheme).
  - data/: algorithms, monads.
  - integration/: integrations (e.g., vkapi) with caching, retries, dependency checks.
- install/
  - main.sh, actions.sh, checks.sh, path_manager.sh, utils.sh: Modular installer; generates wrapper exporting BS_ROOT and execs bs.
- tests/
  - unit/, integration/, demos/, runalltests.sh, testframework.sh, validatesyntax.sh: Organized suites and custom test helpers.
- bs: Unified entrypoint (CLI and shebang mode); resolves BS_ROOT, ensures bootstrap/init.sh, dispatches commands.
- boot.sh: Project launcher for library mode.
- documentation/: Guides, refactoring notes, API references, examples.

Entry points and setup:
- Shebang mode: Scripts can use `#!/usr/bin/env bs` (BS_SHEBANG=1 path).
- CLI: `bs help|version|env|list|doctor|run|init-shell`.
- Initialization: Source `bootstrap/init.sh` from BS_ROOT to load core and set flags.

## 3. Test Strategy
- Framework: Custom (tests/testframework.sh) with assertions (assert_true, assert_equal, assert_file_exists, assert_command).
- Structure:
  - Unit tests: tests/unit/* — focus on module internals (e.g., logger).
  - Integration tests: tests/integration/* — loader interactions, framework init, installation flows.
  - Demos: tests/demos/* — real-world examples and user-facing flows.
  - Suite runner: tests/runalltests.sh orchestrates; tests/validatesyntax.sh validates syntax.
- Naming/Invocation:
  - Test scripts named test_*.sh (Bash).
  - Initialize BS: `source "../testframework.sh"; source "../../boot.sh"; bs::init`.
- Mocking:
  - Prefer DI via env vars and function indirection.
  - Wrap external tools (curl/jq/openssl) behind small functions for stubbing.
- Coverage philosophy:
  - Unit for core logic and edge cases.
  - Integration for module interactions and loader semantics (@depends, circular checks).
  - Demo for broader user-facing operations and installation.

## 4. Code Style
- Shell options:
  - Always `set -euo pipefail` at top of executable scripts and modules.
- Shell version/compat:
  - Require Bash 4+ for runtime (associative arrays used in loader).
  - Allow zsh user shells for invocation; ensure execution under Bash via centralized checks.
- Naming:
  - Functions: namespaced with double-colons, e.g., `module::submodule::fn` or `namespace::fn`.
  - Constants: ALL_CAPS with `BS_` or domain-specific prefixes.
  - Env vars: standardize on `BS_*` (e.g., BS_ROOT, BS_LOG_LEVEL, BS_LOG_FORMAT).
- Sourcing and module loading:
  - Use `load "path/module"` for framework modules (relative to BS_ROOT).
  - When sourcing directly, always include `.sh` extension and use `${BS_ROOT}/...` absolute paths.
- Quoting and safety:
  - Quote all variable expansions (`"${var}"`), especially in file ops (rm, cp) and when passing arguments to commands.
  - Prefer arrays for command construction to avoid injection.
- Error handling:
  - Use errorhandler helpers (try/retry/backtraces/exit_with_backtrace).
  - Register cleanup actions via cleanup::add; rely on cleanup stack at exit.
- Documentation:
  - Concise bilingual comments (RU/EN).
  - Public APIs include `@description`, `@param`, `@example`.
- Idempotency:
  - Guard init with flags (e.g., BS_INITIALIZED, MONADS_INITIALIZED).

## 5. Common Patterns
- Module loader:
  - Parses `# @depends` for dependencies; detects circular deps via BS_LOAD_STACK.
  - Deduplicates loads with BS_LOADED_MODULES; supports registering lazy wrappers.
- Centralized shell checks (recommended refactor):
  - Create `core/shell.sh` with:
    - ensure_bash4(): verify Bash and major version >= 4; bilingual error messages; return-safe for sourced contexts (return 1), exit for executed contexts if needed.
    - maybe_exec_bash(): if invoked from non-bash (e.g., zsh) and executing a script, re-exec under bash with preserved args/env.
  - Source `core/shell.sh` as early as possible in `bs` and `bootstrap/loader.sh`, replacing scattered `BASH_VERSINFO` checks (e.g., `ensure_bash4 || exit 1`).
  - Reuse install/utils.sh::ensure_bash4 for installer context or delegate installer to source `core/shell.sh` to avoid duplication.
- Logging:
  - `log::info|warn|error|debug|trace|success|fatal`.
  - Env configuration: BS_LOG_LEVEL, BS_LOG_COLOR, BS_LOG_FORMAT, BS_LOG_TIMESTAMP.
- Error handling:
  - Clean `error::panic` (no `kill -9 $$`).
  - Structured thrown errors and consistent error codes in `const.sh`.
- Paths:
  - Resolve strictly from BS_ROOT; verify `${BS_ROOT}/bootstrap/init.sh` before sourcing.
- Caching and rate-limiting (vkapi):
  - Cache dir `${BS_ROOT:-/tmp}/vk_api_cache`, TTL-based caching, 3 RPS rate limiting with backoff retries.
  - Provide local `function_exists` shim if logger may be missing.
- Cross-platform:
  - platformcheck module for distro detection (apt/dnf/brew) and conditional installs.

## 6. Do's and Don'ts
- ✅ Do
  - Use `set -euo pipefail` and quote all variables.
  - Use the loader (`load`) or `${BS_ROOT}`-absolute sourcing; include `.sh` extension for direct `source`.
  - Keep modules idempotent with `*_INITIALIZED` flags.
  - Standardize on BS_* env var names (avoid legacy BOSA_*).
  - Centralize Bash 4+ checks via `core/shell.sh` and call early in `bs` and `bootstrap/loader.sh`.
  - Register cleanups with `cleanup::add` and use errorhandler for consistent backtraces/exits.
  - Gate external tool usage and provide auto-install or guidance using `platformcheck`.
- ❌ Don’t
  - Don’t hardcode `/tmp`; use `${BS_ROOT:-/tmp}` or make paths configurable.
  - Don’t use `kill -9 $$`; fail fast with clean exits.
  - Don’t duplicate inline `BASH_VERSINFO` checks across the codebase; use a shared helper.
  - Don’t source modules without `.sh` extension when using direct `source`.
  - Don’t assume logger/errorhandler presence; guard with `function_exists` if optional.

## 7. Tools & Dependencies
- Shell: Bash 4+ required for runtime (assoc arrays). zsh supported as user shell for invocation.
- External tools (module-specific): jq, curl, openssl, coreutils (base64).
- Installation:
  - Local install wrapper: `~/.local/bin/bs` exporting `BS_ROOT="$HOME/.local/lib/bs"` then `exec "$BS_ROOT/bs" "$@"`; ensure PATH includes `~/.local/bin`.
  - System install wrapper: `/usr/local/bin/bs` exporting `BS_ROOT="/usr/local/lib/bs"` then `exec "$BS_ROOT/bs" "$@"`.
- Configuration:
  - BS_ROOT must be valid before module loading.
  - Logging configured exclusively through BS_LOG_* variables.

## 8. Other Notes
- Prefer `load` over raw `source` for framework modules to leverage dependency parsing and duplication protection.
- Shebang mode: `bs` sets `BS_SHEBANG=1` and runs the target script post-init; avoid re-init in scripts.
- Naming consistency: `log::` (not `logger::`), `bs::` (not `bosa::`), `BS_*` (not `BOSA_*`).
- Adding new modules:
  - Place in core/ or an appropriate lib/ subdirectory.
  - Declare `# @depends` where applicable and ensure idempotent init.
  - Provide unit tests (tests/unit) and, for cross-module flows, integration tests (tests/integration).
- Version-check refactor plan (actionable):
  - Add `core/shell.sh` with `ensure_bash4` and optional `maybe_exec_bash`.
  - In `bs` and `bootstrap/loader.sh`, source `core/shell.sh` first and replace ad-hoc checks with `ensure_bash4`.
  - Optionally adjust `install/utils.sh` to source `core/shell.sh` to keep a single source of truth for version checks across runtime and installer.