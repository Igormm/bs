[↑ Documentation index](../README.md)

# Module `gpu`

Vendor-agnostic GPU diagnostics and stress testing on Linux: discovery via
`lspci`, driver/VRAM/temperature/utilization via sysfs drm
(`/sys/class/drm`) and `nvidia-smi` (when installed), a stress test with
temperature monitoring.

Tier: **Linux-only** (`/sys`/`lspci`). Without a GPU, access or tools it
degrades with defined `E_*` / `LIB_ERROR_*` codes — never a silent success.

Source: [lib/system/gpu.sh](../../../lib/system/gpu.sh)

## Loading

```bash
#!/usr/bin/env bs

load "lib/system/gpu"
```

## Test hooks

| Variable | Default | Purpose |
|---|---|---|
| `GPU_SYSFS_DRM_DIR` | `/sys/class/drm` | sysfs drm root override |
| `GPU_LSPCI_CMD` | `lspci` | lspci command (path allowed) — mock for tests |
| `GPU_NVIDIA_SMI` | `nvidia-smi` | nvidia-smi command; empty disables it |
| `GPU_STRESS_TOOL` | auto-detect | forced stress tool |

## Discovery

```bash
gpu::detect          # "vendor<TAB>name" for every GPU
gpu::vendor          # nvidia | amd | intel | unknown (first GPU)
gpu::name            # first GPU name without the "VGA compatible controller: " prefix
gpu::vendor_of <line> # vendor of an lspci line
```

## Driver and VRAM

```bash
gpu::driver          # nvidia (via nvidia-smi) | amdgpu/i915/xe (via sysfs)
gpu::vram            # VRAM size in bytes (NVIDIA: MiB→bytes; AMD: mem_info_vram_total)
```

Intel (shared memory) honestly returns `LIB_ERROR_FILE_NOT_FOUND`.

## Temperature and utilization

```bash
gpu::temperature     # °C: nvidia-smi or hwmon temp1_input (millidegrees)
gpu::utilization     # %: nvidia-smi or sysfs gpu_busy_percent (AMD)
```

## Stress test

```bash
gpu::stress 30
```

Runs a stress tool (first of `glmark2`/`vkcube`/`glxgears`/`gpu-burn`, or
`GPU_STRESS_TOOL`) in the background, samples temperature once per second,
kills the tool and prints the report:

```
stress: tool=glmark2 duration=30s temp_min=52 temp_max=71 temp_avg=58
```

No tools — `LIB_ERROR_DEPENDENCY_MISSING`; non-numeric duration —
`LIB_ERROR_INVALID_ARGS`.

## Diagnostics

```bash
gpu::check            # [PASS]/[WARN]/[FAIL] per check
gpu::info             # k=v summary: vendor/name/driver/vram/temperature/utilization
```

`gpu::check` returns `E_SUCCESS` when there are no `[FAIL]`, otherwise
`LIB_ERROR_FILE_NOT_FOUND` (no GPU found). `gpu::info` returns
`LIB_ERROR_FILE_NOT_FOUND` when there is no GPU.

## Related

- `examples/gpu_diag.sh` — CLI entry point: `--list`, `--check`, `--stress N`.