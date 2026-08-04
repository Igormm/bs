# Installation

BS is installed by the modular installer in the repository root: [install.sh](../../install.sh) is the entry point, and the logic lives in [install/](../../install).

## Installer layout

- [install.sh](../../install.sh) — entry point. Validates the repository layout (`core/`, `bootstrap/`, `install/`), loads `core/utils.sh`, enables strict mode via `utils::strict`, checks the shell version via `utils::ensure_shell_version`, then runs `install/main.sh`.
- [install/main.sh](../../install/main.sh) — argument parsing, mode/path resolution, dispatch to install/uninstall actions.
- [install/checks.sh](../../install/checks.sh) — environment checks: `is_already_installed`, `check_shell_environment`.
- [install/actions.sh](../../install/actions.sh) — `do_install` and `do_uninstall`.
- [install/path_manager.sh](../../install/path_manager.sh) — PATH helpers: `print_path_hint`, `auto_update_path`, `update_path_bashrc`.

## Modes

| Mode | Flag | Prefix | Requires root |
| --- | --- | --- | --- |
| system | (default) | `/usr/local` | yes (`sudo`) |
| local | `--local` | `~/.local` | no |

Defaults can be overridden with environment variables: `PREFIX`, `BIN_DIR` (default `$PREFIX/bin`), `LIB_DIR` (default `$PREFIX/lib`).

## What gets installed

- `TARGET_LIB=$LIB_DIR/bs` — the framework files: `bootstrap/`, `core/`, `lib/`, and the `bs` launcher, copied from the repository.
- `TARGET_BIN=$BIN_DIR/bs` — a small wrapper script:

```bash
#!/usr/bin/env bash
export BS_ROOT="${TARGET_LIB}"
exec "${BS_ROOT}/bs" "$@"
```

The wrapper exports `BS_ROOT` and delegates to the real `bs` entry point, so `#!/usr/bin/env bs` works in user scripts once `BIN_DIR` is on `PATH`.

## Usage

System install (default action is `install`):

```bash
sudo ./install.sh
sudo ./install.sh install
```

Local install, no sudo:

```bash
./install.sh --local
./install.sh --local install
```

Custom prefix:

```bash
PREFIX=/opt/bs sudo ./install.sh
```

## Uninstall

```bash
sudo ./install.sh uninstall        # system
./install.sh --local uninstall     # local
```

`uninstall` (alias: `remove`) deletes `TARGET_BIN` and `TARGET_LIB`. In local mode it additionally removes `BIN_DIR`/`LIB_DIR` only if they are empty (`rmdir`), so other files in `~/.local` are never touched.

## PATH management (local mode)

After a local install, `auto_update_path` runs automatically. Both PATH flags are valid only together with `--local`:

```bash
./install.sh --local --path         # print a snippet for manual setup
./install.sh --local --update-path  # add the line to ~/.bashrc and/or ~/.zshrc
```

`--update-path` appends the following line (idempotently — existing identical lines are detected with `grep -Fqx` and not duplicated):

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Rules: `~/.bashrc` is updated if it exists, or if there is no `~/.zshrc`; `~/.zshrc` is updated only if it already exists. Reload the shell afterwards (`source ~/.bashrc`) or open a new session.

## Notes

- **The source repository can be removed.**  
  The installer copies framework files to `TARGET_LIB` and creates a
  wrapper at `TARGET_BIN`. After installation BS runs from the target
  directory, not from the repository where `install.sh` was launched.
  The target directory depends on the mode:
  - `system` (default): `/usr/local/lib/bs`;
  - `local` (`--local`): `~/.local/lib/bs`;
  - custom: values of `PREFIX`, `BIN_DIR`, `LIB_DIR`.
- bash 4.0+ is required; the installer aborts on older shells via `utils::ensure_shell_version`.
- If BS is already installed at the target (`is_already_installed`), the installer stops and suggests uninstalling first or overriding `PREFIX`/`BIN_DIR`/`LIB_DIR`.
- The installer runs under strict mode (`utils::strict`: `set -euo pipefail`) and validates every file it sources via `utils::ensure_source`.
