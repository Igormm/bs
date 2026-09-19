[↑ Documentation index](../README.md)

# Module `sensor`

Touch/sensor input devices on Linux: discovery via `/sys/class/input`,
event decoding from evdev (`/dev/input/eventN`) with pure Bash (`dd` + `od`,
no external parsers), capability decoding, live diagnostics.

Tier: **Linux-only** (`/proc`/`/sys`/evdev). Degrades with defined `E_*` /
`LIB_ERROR_*` codes where access is missing.

Source: [lib/system/sensor.sh](../../../lib/system/sensor.sh)

## Loading

```bash
#!/usr/bin/env bs

load "lib/system/sensor"
```

## Test hooks

| Variable | Default | Purpose |
|---|---|---|
| `SENSOR_INPUT_DIR` | `/sys/class/input` | sysfs root override |
| `SENSOR_DEV_DIR` | `/dev/input` | device-node dir override |
| `SENSOR_EVENT_SIZE` | auto (`getconf LONG_BIT`: 24/16) | `input_event` record size |

## Discovery

```bash
sensor::devices          # "eventN<TAB>name" for every event device
sensor::devices touch    # substring filter, case-insensitive
sensor::info event5      # name/phys/readable/capabilities as k=v lines
sensor::check event5     # 0 | LIB_ERROR_FILE_NOT_FOUND | LIB_ERROR_PERMISSION_DENIED
```

## Events

```bash
sensor::events event5            # stream "sec usec type code value", forever
sensor::events event5 10         # ... or exactly 10 records
sensor::detect event5 2          # first event line within 2 s, or LIB_ERROR_TIMEOUT
sensor::record_size              # 24 on 64-bit, 16 on 32-bit
sensor::type_name 3              # EV_ABS
sensor::abs_name 53              # ABS_MT_POSITION_X
sensor::code_name 1 330          # BTN_TOUCH
```

## Capabilities

```bash
sensor::capabilities event5 ev   # EV_SYN EV_KEY EV_ABS ... (one per line)
sensor::capabilities event5 key  # BTN_TOUCH ...
sensor::abs_range event5 0       # "min max fuzz flat" (when sysfs exposes it)
```

## Diagnostics

```bash
sensor::diagnose event5 3
```

Reports `[PASS]/[WARN]/[FAIL]/[INFO]` lines: sysfs presence, read permission
(hint: `input` group), `EV_ABS` + `BTN_TOUCH` capabilities, axis ranges, and a
3-second live window: event rate, observed axis spans, stuck-axis detection
(same value in ≥3 samples), touch-press count. Exit `E_SUCCESS` when there
are no `[FAIL]`.

## Related

- `examples/sensor_diag.sh` — CLI diagnostic entry point.
- `examples/sensor_tui.sh` — real-time TUI monitor (`bs run examples/sensor_tui.sh`).
- `lib/tui/tui.sh` — the TUI widgets used by the monitor.
