# Design: devices TUI (input & localization configurator skeleton)

Date: 2026-11-08
Status: review

## 1. Goal

A full-screen TUI that lists input devices and localizes them, shown with
their current parameters; selecting a device opens a parameter screen where
every change is applied live; changes can be saved into a reusable BS
profile and re-applied on demand. The skeleton hides the device types behind
a uniform driver contract, so new drivers (keyboard, locale, Keychron layers)
are added without touching the TUI. The first reference driver is "pointers"
(touchpad, trackball, Lenovo TrackPoint) with sensitivity and scrolling.

Scope of this spec: skeleton + driver contract + the pointers driver + the
profile layer. Each following subsystem (keyboard, locale, Keychron) becomes
its own spec on top of the contract.

Decisions already taken with the author (see brainstorm):

- Driver contract variant **A** — a uniform `driver::<name>::` interface, the
  TUI is a generic engine over it. Parameter metadata is a catalog inside
  each driver (as `SSHD_PARAMS` / `F2B_PARAMS`).
- Apply model: **live application + review/save** (not deferred).
- Persistence: **BS profile** (`~/.config/bs/profiles/devices/<name>.conf`),
  not system config files, applied on demand.
- Display server: **X11 and Wayland, both with graceful degradation**
  (`DEVICECTL_BACKEND` = x11 | wayland | none, `E_DEGRADED` + hint).
- Keychron driver later: pure bash via `/dev/hidraw` + JSON mappings, no
  fork at this stage.

## 2. Architecture

```
lib/system/devicectl.sh    engine: driver registry + device list + dispatch
lib/system/devprofile.sh   profiles: save / list / load / apply / active
lib/system/pointers.sh     reference driver: touchpad / trackball / trackpoint
examples/devices_tui.sh    TUI (lib/tui/tui, same engine as locale_wizard)
documentation/{en,ru}/03-modules/system-devices.md
tests/unit/testdevicectlunit.sh / testdevprofileunit.sh /
       testpointersunit.sh / testdevicestuiunit.sh
```

The engine never draws; the TUI never encodes device rules; drivers never
draw. Each driver is a `lib/` module loaded by path from the registry.

## 3. Driver contract

Every driver is a module with the namespace `driver::<name>::` and this
interface:

| Function | Purpose |
|---|---|
| `driver::<name>::detect` | list devices: TSV `handle<TAB>label<TAB>kind` |
| `driver::<name>::params <handle>` | TSV `param<TAB>type<TAB>current<TAB>default<TAB>choices<TAB>tip` |
| `driver::<name>::get <handle> <param>` | current value |
| `driver::<name>::set <handle> <param> <value>` | live apply; 0 or `E_DEGRADED` + hint |
| `driver::<name>::snapshot <handle>` | all `param=value` pairs (profile/review) |

`get`/`set`/`params`/`snapshot` may return the sentinel `DRIVER_NO_HANDLE` /
`DRIVER_NO_PARAM` when the handle or param is unknown.

Parameter types: `bool`, `enum:a,b,c`, `int`, `range:min:max:step` (a slider
for sensitivity), `string`, `keys` (free-form mapping token). Types mirror the
fail2ban catalog, plus `range`.

## 4. Engine `lib/system/devicectl.sh`

- `bs::guard "LIB_SYSTEM_DEVICECTL"`.
- Meta keys: `DEVICECTL_DRIVERS` (indexed array of driver names),
  `DEVICECTL_DRIVER_PATH` (prefix dir, default relative to itself),
  `DEVICECTL_BACKEND` (x11|wayland|none, detected once via
  `$XDG_SESSION_TYPE` / `$WAYLAND_DISPLAY` / `loginctl`).
- API: `device::registry [name...]` (register extra drivers),
  `device::load <name>` (source the module), `device::list [name...]`
  (aggregated TSV `driver<TAB>handle<TAB>label<TAB>kind`),
  `device::params <driver> <handle>`, `device::get <driver> <handle> <param>`,
  `device::set <driver> <handle> <param> <value>` (dispatch; returns the
  driver's status), `device::backend` (detect/cached).

## 5. Profile layer `lib/system/devprofile.sh`

INI with managed markers (as `fail2ban::render`):

```
# Managed by BS / Сгенерировано BS
# BEGIN bs-devices
[pointers:tp-lenovo-trackpoint]
sens=160
speed=0.40
natural_scroll=0
# END bs-devices
```

- Location hook `BS_PROFILE_DIR`
  (default `${XDG_CONFIG_HOME:-$HOME/.config}/bs/profiles/devices`).
- API: `devprofile::save <name> <TSV>` (stdin or arg:
  `driver<TAB>handle<TAB>param<TAB>value`), `devprofile::list` (names),
  `devprofile::load <name>` (→ the same TSV), `devprofile::active` (last
  accessed name via `.active`), `devprofile::apply <name>` (replay through
  `device::set`, per-driver sort, degradation report to stderr),
  `devprofile::remove <name>`.
- Atomic write (tmp + mv); unknown sections dropped; empty values skipped.

## 6. Pointers driver `lib/system/pointers.sh`

- `driver::pointers::detect`: enumerate via `xinput`/libinput or
  `/proc/bus/input/devices`; classify by name into kind `touchpad` |
  `trackball` | `trackpoint` (`TPPS/2`, `TrackPoint`, `stick`, `eraser`).
- Catalog `POINTERS_PARAMS[kind]`:
  - `speed` — `range:-1.0:1.0:0.05` (libinput Accel Speed), live setter;
  - `sens` — `int` (TrackPoint sensitivity via sysfs when available);
  - `natural_scroll` — `bool`;
  - `profile` — `enum:adaptive,flat` (libinput Accel Profile);
  - `tap_to_click` — `bool` (touchpad only).
- `driver::pointers::set`: X11 → `xinput set-prop` (libinput props) and
  `xset m`; Wayland → `gsettings` where meaningful, otherwise `E_DEGRADED`
  with a bilingual hint (libinput config / compositor). Root-only setters
  (sysfs sensitivity) degrade with a `sudo` hint.
- `driver::pointers::get` reads the current value from the same backend.

## 7. TUI `examples/devices_tui.sh`

Same engine/UX as `locale_wizard.sh`: `tui::init`, `tui::key_read`, modal
layer, status bar, `--help` before init. Three screens:

1. **Device list** — grouped by driver; row = `label — kind — key params`;
   `↑↓` select, `Enter` open, `r` re-detect, `q` quit; sidebar of drivers.
2. **Device parameters** — header = device + driver + live `get`; per-param
   row `param = value (type, default)`; `↑↓` select, `Enter` edit: `bool`
   toggle, `enum`/`keys` picker, `int`/`range` input or `←→` step, `string`
   input. Every edit calls `driver::set` immediately; `E_DEGRADED` shows the
   reason in the status bar.
3. **Review & profile** — changed params vs saved profile; `s` save to profile
   (input name), `a` apply profile, `u` revert, `Enter` back.

Optional `tui::mouse_on` (not in the first version).

## 8. Degradation

`device::backend` detects once and caches `DEVICECTL_BACKEND`. Setters that
lack a backend return `E_DEGRADED` (never silent success) with a bilingual
next-step hint. Reads degrade to "unknown" + the same hint, not to a fake
value.

## 9. Documentation / testing

- `documentation/{en,ru}/03-modules/system-devices.md` + overview line.
- `tests/unit/testdevicectlunit.sh`: registry/dispatch, unknown
  handle/param sentinels, backend detection.
- `tests/unit/testdevprofileunit.sh`: save/load/apply/remove, markers,
  atomic write, empty-value skip, unknown-section drop.
- `tests/unit/testpointersunit.sh`: detect classification, catalog shape,
  `set`/`get` with a `xinput` shim on a temp `PATH`, `E_DEGRADED` when no
  backend.
- `tests/unit/testdevicestuiunit.sh`: source-without-main; draw fills
  `TUI_BUF`; list/param navigation state; set -u isolation.
- Full validation cycle (`validatesyntax`, `validateshellcheck`,
  `runalltests`).

## 10. Out of scope (YAGNI)

- Installing packages (uses `apply::check_tools` only to report).
- udev/hwdb or `/etc/X11/xorg.conf.d` authoring and system persistence.
- `bs devices apply <name>` CLI command (functions only; CLI is a follow-up).
- TUI mouse support in the first version.
- Keychron layer/mapping driver, full keyboard and locale catalogs (own specs).
- Wayland system-config persistence beyond `gsettings` where available.
