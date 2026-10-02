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

## Tools catalog

A catalog of GPU diagnostic/test programs with tiers
(`GPU_TOOLS[tool]="tier|package|description"`):

| Tier | Purpose | Tools |
|---|---|---|
| 1 | basic | `lspci`, `nvidia-smi`, `glxinfo`, `vulkaninfo` |
| 2 | monitoring | `nvtop`, `radeontop`, `amdgpu_top`, `intel_gpu_top`, `rocm-smi` |
| 3 | stress/benchmark | `glmark2`, `vkcube`, `glxgears`, `gpu-burn`, `vkmark` |
| 4 | memory test | `vulkan-memtest` |

```bash
gpu::tools 1                       # catalog, tier filter: "tier<TAB>tool<TAB>pkg<TAB>desc"
gpu::tools_available               # only installed ones
gpu::check_dependencies [tier]     # [OK]/[MISS] per tool; E_SUCCESS / LIB_ERROR_DEPENDENCY_MISSING
gpu::install_dependencies [tier]   # install missing via system::packages::install (dedup)
gpu::run glxinfo -B                # run a tool; missing → LIB_ERROR_DEPENDENCY_MISSING
gpu::glxinfo                       # wrapper: glxinfo -B (brief OpenGL info)
gpu::vulkaninfo                    # wrapper: vulkaninfo --summary
gpu::radeontop                     # wrapper: radeontop -d - (one-shot AMD snapshot)
gpu::rocm_smi                      # wrapper: rocm-smi --showtemp --showuse
gpu::nvtop / gpu::amdgpu_top / gpu::intel_gpu_top
gpu::glmark2 / gpu::vkcube / gpu::glxgears / gpu::gpu_burn / gpu::vkmark
gpu::vulkan_memtest                # VRAM test for bad cells
```

## Related

- `examples/gpu_diag.sh` — CLI entry point: `--list`, `--check`, `--stress N`,
  `--tools`, `--run <tool>`, `--deps [tier]`.