---
name: bs-device-module
description: Write or extend a Linux device/hardware module (evdev, /sys, /dev nodes) with sysfs test hooks, pure-bash binary decoding and graceful degradation
type: prompt
whenToUse: When asked to add support for a hardware device (sensor, touchscreen, buttons, serial, hwmon, block) to lib/system/* or a similar lib group
arguments:
  - module_path
---

Create/extend the device module `$module_path` (reference implementation:
`lib/system/sensor.sh`). Device code is the highest-risk area for bash traps —
follow this recipe exactly.

## Environment access rules

1. sysfs/procfs paths MUST go through test hooks, never hardcoded inline:
   `: "${SENSOR_INPUT_DIR:=/sys/class/input}"` — this is what makes the module
   unit-testable without hardware (see `HW_DMI_PATH` precedent, `lib/system/hw`).
2. Guard every `/proc`/`/sys`/`/dev` access: `[[ -d ... ]]`, `is::readable`,
   and return a DEFINED code (`LIB_ERROR_FILE_NOT_FOUND`,
   `LIB_ERROR_PERMISSION_DENIED`) — never a silent empty success.
3. Declare the tier in the header comment (`Linux-only (evdev, /sys/...)`)
   and keep degradation honest: a host without the device must pass tests.
4. Enumerate via stable kernel interfaces: `/sys/class/*`,
   `/proc/bus/input/devices`; treat names as data (quote everything).

## Binary reading (evdev et al.) in pure bash

- Read fixed-size records through `dd bs=$size`, decode bytes with
  `od -An -tu1 -v`; assemble little-endian fields in `$(( ))`, sign-extend
  manually (`v >= 2147483648 → v -= 2^32`).
- Probe struct size, never assume: `struct input_event` = 2*sizeof(long)+8 →
  24 B on 64-bit, 16 B on 32-bit (`getconf LONG_BIT`, hook override).
- NEVER `read -n1` directly on evdev: a short read on the device is an error
  and breaks record alignment. Stream via `dd` in a pipeline.
- Capability bitmasks in sysfs are printed most-significant word first —
  decode index as `(words-1-word)*64 + bit`.

## Timeouts and non-blocking I/O

- `timeout` cannot run a shell function. Use `read -t` on a pipe fd instead.
- `io::streams::wait_readable` consumes a byte — do not use it on structured
  streams; use `read -t` loop lines instead.
- For a fixed observation window use a deadline in `utils::now_ms` and
  recompute the per-`read -t` remainder; `read -t` restarts its timer per line.

## set -e traps specific to device code

- A function whose last statement is `[[ ... ]] && ...` or `(( cond )) && ...`
  returns 1 and KILLS the caller's strict-mode loop. End statement-functions
  with an explicit `return 0`/`return "${E_SUCCESS}"`.
- `exec N<&-` on a never-opened fd is fatal in non-interactive bash. Track an
  "attached" flag and close only what was opened.
- Nameref argument named identical to the caller's array → circular-reference
  warning. Use a distinct ref name (`local -n src_bytes="$1"`).

## Required deliverables per device module

1. `lib/<group>/<module>.sh` with the standard skeleton (`bs-new-lib-module`).
2. `tests/unit/test<module>unit.sh` — ALL hardware-free paths exercised via the
   test hooks (synthesize binary fixtures: `printf '%b'` records), plus a
   graceful-degradation test against the real host (`|| rc=$?` and accept a
   defined error code).
3. A CLI entry point in `examples/<module>_diag.sh` (args tree, `--list`).
4. Docs in BOTH `documentation/{en,ru}/03-modules/`.
5. Full validation cycle (`bs-validate` skill).
