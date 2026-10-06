[↑ Documentation index](../README.md)

# Module `sshd`

Server-side OpenSSH configuration: a data-driven parameter catalog with a
short Russian tip for every parameter, hardening profiles, per-type
validation, rendering to a config file with managed-block markers, and safe
installation (backup → `sshd -t` → atomic replace → reload, with rollback).

Tier: **Linux-only** (writes under `/etc/ssh`, reloads via `systemctl`).
Without the `sshd` binary or write access it degrades with defined
`LIB_ERROR_*` codes — never a silent success.

Source: [lib/system/sshd.sh](../../../lib/system/sshd.sh)

## Loading

```bash
#!/usr/bin/env bs

load "lib/system/sshd"
```

## Test hooks

| Variable | Default | Purpose |
|---|---|---|
| `BS_SSHD_DIR` | `/etc/ssh/sshd_config.d` | drop-in config dir |
| `BS_SSHD_MAIN` | `/etc/ssh/sshd_config` | main config path (managed block) |
| `BS_SSHD_BIN` | `sshd` | sshd binary or test mock |
| `BS_SSHD_SERVICE` | `sshd` | systemd service name for reload |
| `BS_SSHD_DRY_RUN` | `0` | `1` = no writes and no reload |
| `BS_SSHD_DROPIN` | `99-bs.conf` | drop-in file name |

## Catalog

Each parameter carries `section|type|default|recommended` and a two-line
Russian tip:

```bash
sshd::param_list            # name<TAB>section<TAB>type<TAB>default<TAB>recommended
sshd::param_list Network    # filter by section
sshd::param_type Port       # "port"
sshd::param_desc Port       # two-line Russian tip
sshd::param_default Port    # 22
sshd::param_recommended Port # 22
```

Types: `bool`, `int`, `port`, `enum:...`, `string`, `userlist`,
`grouplist`, `csv`, `path`, `addr`, `time`.

Sections: `Network`, `Authentication`, `Access Control`, `Forwarding`,
`Logging`, `Cryptography`, `SFTP`, `Match`.

## Validation

```bash
sshd::validate PasswordAuthentication no   # E_SUCCESS
sshd::validate Port 70000                   # LIB_ERROR_INVALID_INPUT
```

Values containing newlines, carriage returns, tabs or spaces are rejected,
so a value can never inject a new directive into the rendered config.

## Profiles

```bash
sshd::profile basic      # keys-only login, root by key, no X11
sshd::profile strict     # + no root, no forwarding, publickey only
sshd::profile paranoid   # + inet only, tightened ciphers/MACs/Kex
```

`strict` extends `basic`, `paranoid` extends `strict` (later lines win when
consumed into a map).

## Rendering

`sshd::render` reads `name=value` lines from stdin and emits a config with
the managed-block markers. Main parameters are ordered by the catalog;
`@match <criteria>` opens a Match block, a blank line closes it.

```bash
printf 'Port=2222\nPasswordAuthentication=no\n' | sshd::render
printf '@match Group sftponly\nChrootDirectory=%%h\nForceCommand=internal-sftp\n\n' | sshd::render
```

Empty values are skipped. Match directives are indented.

## Install / revert

```bash
sshd::test /tmp/sshd.conf          # sshd -t -f; 101 if sshd is missing
sshd::install /tmp/sshd.conf       # drop-in: backup → validate → replace → reload
sshd::install_main /tmp/block.conf # managed block inside BS_SSHD_MAIN
sshd::revert /etc/ssh/sshd_config.d/99-bs.conf  # restore newest .bak.*
```

`sshd::install` writes atomically and validates before and after the
replace; on failure it restores the backup (or removes the new file).
`BS_SSHD_DRY_RUN=1` prints the planned actions and writes nothing.

## Error codes

| Code | Meaning |
|---|---|
| `E_SUCCESS` | ok |
| `LIB_ERROR_INVALID_INPUT` | value/directive rejected (including `sshd -t`) |
| `LIB_ERROR_INVALID_ARGS` | unknown parameter/type/profile |
| `LIB_ERROR_FILE_NOT_FOUND` | source/target/backup missing |
| `LIB_ERROR_PERMISSION_DENIED` | target dir/file not writable |
| `LIB_ERROR_DEPENDENCY_MISSING` | `sshd`/`systemctl` absent |
| `LIB_ERROR_FILE_OPERATION` | copy/move failed |

## Wizard

`examples/sshd_wizard.sh` is a full-screen TUI on `lib/tui/tui`: pick a
profile, tune parameters by section (each with its Russian tip), add
Match/chroot blocks, preview, and apply to a drop-in or the main config (or
just print). Run:

```bash
bs run examples/sshd_wizard.sh --dry-run
```
