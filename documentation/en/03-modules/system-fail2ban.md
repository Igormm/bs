[↑ Documentation index](../README.md)

# Module `fail2ban`

Server-side fail2ban jail configuration: a data-driven catalog of `[DEFAULT]`
and per-jail parameters with a short Russian tip each, per-type validation,
hardening profiles, INI rendering with managed-block markers, and safe
installation (backup → `fail2ban-client -t` → atomic write → reload, with
rollback). A jail catalog with recommended `filter`/`logpath`/`port` and filter
auto-detection round it out.

Tier: **Linux-only** (writes under `/etc/fail2ban`, reloads via
`fail2ban-client`). Without the client or write access it degrades with
defined `LIB_ERROR_*` codes — never a silent success.

Source: [lib/system/fail2ban.sh](../../../lib/system/fail2ban.sh)

## Loading

```bash
#!/usr/bin/env bs

load "lib/system/fail2ban"
```

## Test hooks

| Variable | Default | Purpose |
|---|---|---|
| `BS_FAIL2BAN_DIR` | `/etc/fail2ban` | config root |
| `BS_FAIL2BAN_DROPIN` | `jail.d/99-bs.conf` | drop-in path (relative to dir) |
| `BS_FAIL2BAN_CLIENT` | `fail2ban-client` | client binary or test mock |
| `BS_FAIL2BAN_SERVICE` | `fail2ban` | systemd unit name |
| `BS_FAIL2BAN_DRY_RUN` | `0` | `1` = no write/reload |

## Catalog

```bash
fail2ban::param_list default   # name<TAB>type<TAB>default<TAB>recommended
fail2ban::param_list jail
fail2ban::param_type bantime   # "time"
fail2ban::param_desc bantime   # two-line Russian tip
fail2ban::jails                # jail<TAB>filter<TAB>logpath<TAB>port<TAB>rec
```

`[DEFAULT]`: `bantime`, `findtime`, `maxretry`, `ignoreip`, `backend`,
`banaction`, `action`, `chain`, `bantime.increment`, `bantime.factor`,
`bantime.maxtime`, `bantime.rndtime`, `bantime.overalljails`, `destemail`,
`sender`, `mta`.
Jail: `enabled`, `port`, `filter`, `logpath`, `mode`, and overrides
`maxretry`/`bantime`/`findtime`/`ignoreip`/`backend`/`action`/`banaction`.
Types: `time` (e.g. `10m`, `1h`, `-1` permanent), `int`, `bool`, `enum`,
`iplist`, `pathlist`, `string`.

## Validation

```bash
fail2ban::validate bantime 1h              # E_SUCCESS
fail2ban::validate maxretry "5;rm"         # LIB_ERROR_INVALID_INPUT
```

Values with newlines/tabs are rejected globally; `ignored`/ip lists and paths
are checked per type.

## Profiles

```bash
fail2ban::profile basic      # 10m/5 retries, enable sshd
fail2ban::profile strict     # 1h, increment×2, enable sshd-ddos + recidive
fail2ban::profile paranoid   # permanent ban (-1), systemd backend
```

## Rendering

`fail2ban::render` reads `@section NAME` / `key=value` lines and emits INI with
managed markers; `[DEFAULT]` first, other sections sorted, empty values skipped:

```bash
printf '@section DEFAULT\nbantime=1h\nmaxretry=5\n\n@section sshd\nenabled=true\n' | fail2ban::render
```

## Install / revert

```bash
fail2ban::test /path/jail.local     # fail2ban-client -c <dir> -t (mock hook)
fail2ban::install /path/jail.local  # backup → test → atomic write → reload
fail2ban::revert /etc/fail2ban/jail.d/99-bs.conf
fail2ban::detect                    # available jails (filter.d/*.conf)
fail2ban::status                    # client status (BS_OUTPUT_FORMAT aware)
```

`BS_FAIL2BAN_DRY_RUN=1` prints the planned actions and writes nothing.

## Error codes

| Code | Meaning |
|---|---|
| `E_SUCCESS` | ok |
| `LIB_ERROR_INVALID_INPUT` | value rejected (including `-t`) |
| `LIB_ERROR_INVALID_ARGS` | unknown parameter/type/profile |
| `LIB_ERROR_FILE_NOT_FOUND` | source/target/backup missing |
| `LIB_ERROR_PERMISSION_DENIED` | target dir not writable |
| `LIB_ERROR_DEPENDENCY_MISSING` | `fail2ban-client` absent |
| `LIB_ERROR_FILE_OPERATION` | copy/move failed |

## Wizard

`examples/fail2ban_wizard.sh` is a full-screen TUI on `lib/tui/tui` (same
engine as the sshd wizard): pick jails from detected filters, tune `[DEFAULT]`
and per-jail parameters (each with its Russian tip), preview, and apply to the
drop-in (or print). Run:

```bash
bs run examples/fail2ban_wizard.sh --dry-run
```
