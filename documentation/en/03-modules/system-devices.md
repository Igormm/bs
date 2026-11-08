[↑ Documentation index](../README.md)

# Module `devicectl` + `devprofile` + `pointers`

A device-configuration engine and its first driver. `devicectl` registers
drivers behind a uniform contract and dispatches device lists, parameters and
live get/set. `devprofile` saves a set of devices as a reusable BS profile
(INI with managed markers) and re-applies it. `pointers` is the reference
driver: touchpads, trackballs and the Lenovo TrackPoint (the red stick) with
sensitivity, speed, scrolling and tap-to-click.

Tier: **Linux, X11 and Wayland with graceful degradation**
(`DEVICECTL_BACKEND` = `x11`/`wayland`/`none`). Lookups and setters that lack
a backend return defined codes (`LIB_ERROR_DEPENDENCY_MISSING`,
`LIB_ERROR_PLATFORM_UNSUPPORTED`) — never a silent success. A full-screen
[`devices_tui.sh`](../../../examples/devices_tui.sh) lists every device with
its current parameters, applies changes live and saves/loads profiles.

Sources: [lib/system/devicectl.sh](../../../lib/system/devicectl.sh),
[lib/system/devprofile.sh](../../../lib/system/devprofile.sh),
[lib/system/pointers.sh](../../../lib/system/pointers.sh)

## Driver contract

Every driver is a `lib/system/<name>.sh` module in the `driver::<name>::`
namespace and implements:

| Function | Returns |
|---|---|
| `driver::<name>::detect` | devices: `handle<TAB>label<TAB>kind` |
| `driver::<name>::params <handle>` | `param<TAB>type<TAB>current<TAB>default<TAB>choices<TAB>tip` |
| `driver::<name>::get <handle> <param>` | current value |
| `driver::<name>::set <handle> <param> <value>` | live apply; `0` or a defined error code |
| `driver::<name>::snapshot <handle>` | all `param<TAB>value` |

Parameter types: `bool`, `enum:a,b,c`, `int`, `range:min:max:step`, `string`,
`keys`. Adding a driver means registering it — the TUI needs no change.

## Loading

```bash
#!/usr/bin/env bs

load "lib/system/devicectl"
load "lib/system/devprofile"
```

## Test hooks

| Variable | Default | Purpose |
|---|---|---|
| `DEVICECTL_BACKEND` | *(detected)* | force `x11` / `wayland` / `none` (skip lookup) |
| `DEVICECTL_DRIVER_EXT` | `sh` | driver file extension |
| `BS_PROFILE_DIR` | `~/.config/bs/profiles/devices` | profile storage root |
| `DRIVER_POINTERS_XINPUT` | `xinput` | xinput binary or test shim |
| `DRIVER_POINTERS_SENS_PATH` | *(globs i8042)* | TrackPoint sensitivity sysfs file |

## Engine API

```bash
device::backend                      # x11 | wayland | none (cached)
device::registry foopad              # register a driver
device::list                         # driver<TAB>handle<TAB>label<TAB>kind
device::params pointers "my device"  # parameter catalogue with current values
device::get pointers "my device" speed
device::set pointers "my device" speed 0.4
device::snapshot pointers "my device"
```

## Profiles

```bash
printf 'pointers\tTPPS/2 IBM TrackPoint\tsens\t160\n' | devprofile::save default
devprofile::list                     # profile names
devprofile::load default             # driver<TAB>handle<TAB>param<TAB>value
devprofile::apply default            # replay through device::set
devprofile::active                   # last used profile
devprofile::remove default
```

Profiles live as `[driver:handle]` INI sections with `# BEGIN bs-devices` /
`# END bs-devices` markers, written atomically; empty values are skipped and
unmanaged content is ignored on load.
