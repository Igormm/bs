# Migrating from BOSA to BS

The project was renamed from **BOSA** to **BS** (Bash Open Source Architecture).
This note lists the renames for anyone who knew the old version.

## Project and variable names

| Old | New |
|-----|-----|
| BOSA / BashOSA | BS |
| `bosa::` | `bs::` |
| `BOSA_HOME` | `BS_HOME` |
| `#!/usr/bin/env bash` (as framework entry) | `#!/usr/bin/env bs` |

Notes on current state:

- The primary root variable is now `BS_ROOT`, set by `bootstrap/init.sh`;
  `BS_HOME` is kept as an alias of `BS_ROOT` for lib modules
  (see `bootstrap/init.sh` and the `bs` entrypoint).
- There is **no** `bs::init`. Initialization is either the shebang
  `#!/usr/bin/env bs` plus `load "core/args"`, or manually:
  `source bootstrap/init.sh`, then `load`.

## Logger renamed to log

| Old | New |
|-----|-----|
| `logger::` | `log::` |

```bash
# Was:
logger::info "Message"
logger::debug "Debug info"

# Now:
log::info "Message"
log::debug "Debug info"
```

All `log::` functions live in `core/logger.sh` (`log::info`, `log::debug`,
`log::warn`, `log::error`, `log::success`, etc.).

## Loading modules

Modules are no longer loaded with `source lib/...`. Use `load`:

```bash
#!/usr/bin/env bs

load "core/args"
load "lib/io/streams"
```

Or, in a plain bash script:

```bash
source /path/to/bs/bootstrap/init.sh
load "core/args"
```

## Renamed files

Special characters (`_`, `-`) were removed from file names. The table shows the
current path of each renamed file (verified against the repository):

| Old name | Current path |
|----------|--------------|
| `error_handler.sh` | `core/errorhandler.sh` |
| `system_audit.sh` | `lib/audit/systemaudit.sh` |
| `data_processor.sh` | `lib/data/dataprocessor.sh` |
| `frameworks_integration.sh` | `lib/frameworks/frameworksintegration.sh` |
| `vk_api.sh` | `lib/integration/vkapi.sh` |
| `vk_music.sh` | `lib/integration/vkmusic.sh` |
| `ssh_network.sh` | `lib/network/sshnetwork.sh` |
| `ps1_status.sh` | `lib/status/ps1status.sh` |
| `distro_logic.sh` | `lib/system/distrologic.sh` |
| `platform_check.sh` | `lib/system/platformcheck.sh` |
| `ps1_config.sh` | `lib/ui/ps1config.sh` |
| `test_framework.sh` | `tests/testframework.sh` |
| `run_all_tests.sh` | `tests/runalltests.sh` |
| `validate_syntax.sh` | `tests/validatesyntax.sh` |

Modules removed after the rename (no longer in the repository):
`displaysettings.sh`, `interactiveui.sh`, `desktopintegration.sh`,
`telegramintegration.sh`, `bashitintegration.sh`, `datapresentation.sh`.

## See also

- [README](../../README.md)
- [Best practices](./best-practices.md) — naming conventions
  (`log::`, `bs::`, `BS_*`)
