# Design: fail2ban config wizard (TUI)

Date: 2026-10-07
Status: review

## 1. Goal

A full-screen TUI wizard and a supporting module that build a fail2ban jail
configuration: pick a profile, select jails (auto-detected filters), tune
`[DEFAULT]` and per-jail parameters (each with a short Russian tip), preview,
validate (`fail2ban-client -t`), install as a drop-in
(`/etc/fail2ban/jail.d/99-bs.conf`) with backup and rollback, and reload — or
just print the config. Mirrors `lib/system/sshd.sh` + `examples/sshd_wizard.sh`.

## 2. Architecture

```
lib/system/fail2ban.sh        catalog, validate, profiles, INI render, install
examples/fail2ban_wizard.sh   TUI (lib/tui/tui), same engine as sshd wizard
documentation/{en,ru}/03-modules/system-fail2ban.md
tests/unit/testfail2banunit.sh / testfail2banwizardunit.sh
```

The module never draws; the wizard never encodes fail2ban rules.

## 3. Module `lib/system/fail2ban.sh`

### 3.1 Meta / deps

- `#!/usr/bin/env bs`, line 2 `# shellcheck shell=bash`, `bs::guard`,
  `bs::source_relative` (`core/lang`, `core/const`, `core/logger`,
  `core/utils`, `../io/files`, `../data/format`).
- `bs::guard "LIB_SYSTEM_FAIL2BAN"`.

### 3.2 Hooks

| Variable | Default | Purpose |
|---|---|---|
| `BS_FAIL2BAN_DIR` | `/etc/fail2ban` | config root |
| `BS_FAIL2BAN_DROPIN` | `jail.d/99-bs.conf` | drop-in path (relative to dir) |
| `BS_FAIL2BAN_CLIENT` | `fail2ban-client` | client binary / test mock |
| `BS_FAIL2BAN_SERVICE` | `fail2ban` | systemd unit for reload |
| `BS_FAIL2BAN_DRY_RUN` | `0` | `1` = no write/reload |

Paired bilingual `# @global ... (category: hook)`.

### 3.3 Catalog

Associative arrays (as `SSHD_PARAMS`):

```
F2B_DEFAULT[param]='type|default|recommended'
F2B_JAIL_PARAM[param]='type|default|recommended'
F2B_TIPS[param]=$'line1\nline2'          # bilingual RU tip, shared by name
F2B_JAILS[jail]='filter|logpath|port|recommended_enabled'
```

**[DEFAULT] params:** `bantime` (time, `10m`), `findtime` (time, `10m`),
`maxretry` (int, `5`), `ignoreip` (iplist, empty),
`backend` (enum auto,pyinotify,gamin,systemd,rsyslog,polling | auto),
`banaction` (string, `iptables-multiport`), `action` (string, empty),
`chain` (enum INPUT,FORWARD,DOCKER-USER | INPUT),
`bantime.increment` (bool, false), `bantime.factor` (int, 1),
`bantime.maxtime` (time, `1d`), `bantime.rndtime` (time, empty),
`bantime.overalljails` (bool, false), `destemail` (string, empty),
`sender` (string, empty), `mta` (enum sendmail,mail,mailx,null | sendmail).

**Jail params:** `enabled` (bool), `port` (csv), `filter` (string),
`logpath` (pathlist), `mode` (enum normal,aggressive,ddos | normal),
and overrides `maxretry`/`bantime`/`findtime`/`ignoreip`/`backend`/`action`/
`banaction` (same types; empty = inherit DEFAULT).

**Jail catalog** (`F2B_JAILS`, recommended filter/logpath/port):
`sshd`, `sshd-ddos`, `recidive`, `nginx-http-auth`, `nginx-botsearch`,
`nginx-limit-req`, `apache-auth`, `apache-badbots`, `apache-noscript`,
`apache-overflows`, `postfix`, `postfix-sasl`, `dovecot`, `exim`, `vsftpd`,
`proftpd`, `pure-ftpd`, `roundcube-auth`, `phpmyadmin`.

### 3.4 Types and validation

`time` (`-1` permanent, or `\d+d?\d*h?\d*m?\d*s?` / bare seconds),
`int` (`^[0-9]+$`), `bool` (`true|false`), `enum:a,b,c`, `iplist` (space/comma
of IPv4/IPv6/CIDR), `csv`, `path`, `pathlist` (colon/comma/space paths),
`string`, `action` (string; may contain `%(...)s`). Values with `\n\r\t` are
rejected globally (as sshd). Unknown type → `LIB_ERROR_INVALID_ARGS`.

### 3.5 Profiles

`fail2ban::profile <basic|strict|paranoid>` emits `section.param=value` lines:
- `basic`: `DEFAULT.bantime=10m`, `DEFAULT.findtime=10m`, `DEFAULT.maxretry=5`,
  `sshd.enabled=true`.
- `strict`: `basic` + `DEFAULT.bantime=1h`, `DEFAULT.maxretry=3`,
  `DEFAULT.bantime.increment=true`, `DEFAULT.bantime.factor=2`,
  `DEFAULT.bantime.maxtime=1d`, enable `sshd-ddos`, `recidive`.
- `paranoid`: `strict` + `DEFAULT.bantime=-1` (permanent),
  `DEFAULT.maxretry=2`, `DEFAULT.backend=systemd`.

### 3.6 Public API

| Function | Purpose |
|---|---|
| `fail2ban::init` | defaults, detect client/dir (warn-only) |
| `fail2ban::param_list <default\|jail>` | TSV `name<TAB>type<TAB>default<TAB>recommended` |
| `fail2ban::param_desc <name>` | 2-line Russian tip |
| `fail2ban::param_type <name>` | type |
| `fail2ban::validate <name> <value>` | 0 / `LIB_ERROR_INVALID_INPUT` |
| `fail2ban::jails` | TSV `jail<TAB>filter<TAB>logpath<TAB>port<TAB>rec` |
| `fail2ban::detect` | available jails (filters present in `filter.d/*.conf`) |
| `fail2ban::enabled_jails` | jails currently enabled (parse drop-in + `fail2ban-client status`) |
| `fail2ban::profile <name>` | `section.param=value` preset lines |
| `fail2ban::render` | stdin `[SECTION]`/`key=value`/blank → INI text + managed markers |
| `fail2ban::test [file]` | `"$BS_FAIL2BAN_CLIENT" -t` (config test); missing → `LIB_ERROR_DEPENDENCY_MISSING` |
| `fail2ban::install <file> [target]` | backup → validate → atomic write → reload; rollback on failure |
| `fail2ban::revert <target>` | restore newest `.bak.*` |

Errors `LIB_ERROR_*`, never silent success; `BS_FAIL2BAN_DRY_RUN` prints the plan.

### 3.7 Render grammar and output

`fail2ban::render` input (stdin):
```
@section DEFAULT
bantime=1h
maxretry=5

@section sshd
enabled=true
```
Output:
```
# Managed by BS fail2ban wizard / Сгенерировано визардом BS
# BEGIN bs-fail2ban
[DEFAULT]
bantime = 1h
maxretry = 5

[sshd]
enabled = true
# END bs-fail2ban
```
`[DEFAULT]` first, jails sorted; `key = value` (fail2ban INI style); empty
values skipped; unknown sections dropped.

### 3.8 Format contract (state getters)

`fail2ban::jailed [jail]` (banned IP list) and `fail2ban::status` emit canonical
records via `lib/data/format` so they honour `BS_OUTPUT_FORMAT` — consistent
with the framework-wide output contract.

## 4. TUI wizard `examples/fail2ban_wizard.sh`

Same engine and UX as the sshd wizard: `lib/tui/tui`, single-line border,
two-pane focus (`←` menu / `→` params / `↑↓` in the focused pane), damage
redraw, `lib/ui/steplog` with `--verbose`, `--help` before init, `--dry-run`.

Flow:
1. intro.
2. **Jails screen**: multi-select (`Space`) of `fail2ban::detect` results,
   preseeded from a profile; `[DEFAULT]` always present.
3. **Params screen**: sections = `[DEFAULT]` + chosen jails; per-param edit
   (`yn` for bool, chooser for enum, input for others, validated).
4. **Preview** (`fail2ban::render`).
5. **Apply**: target `dropin` (jail.d/99-bs.conf) / `print`; `tui::confirm`
   with default **No**; then `fail2ban::install` (backup → `-t` → write →
   reload) or print-only; result frame with `fail2ban-client status`.

Keys: `←` menu · `→` params · `↑↓` move · `Space` toggle jail · `Enter` edit ·
`P` profile · `V` preview · `A` apply · `?` help · `q` quit (Cyrillic mapped).

## 5. Documentation / testing

- `documentation/{en,ru}/03-modules/system-fail2ban.md` + overview line.
- `tests/unit/testfail2banunit.sh`: catalog shape + RU tips; per-type
  validate; profiles; render output (DEFAULT/jails/markers/skip-empty);
  `test`/`install`/`revert` on a fake client + temp dir; detect.
- `tests/unit/testfail2banwizardunit.sh`: source-without-main; draw fills
  `TUI_BUF`; focus/jail-toggle state; render_config; set -u isolation.
- Full validation cycle (`validatesyntax`, `validateshellcheck`,
  `runalltests`).

## 6. Out of scope (YAGNI)

- `action.d`/`filter.d` authoring, custom filters.
- Email/notification testing, MTA setup.
- `fail2ban-client set <jail> ban/unban` (runtime ops) beyond status display.
- Installing/removing the fail2ban package (that is `system::security::fail2ban`).
