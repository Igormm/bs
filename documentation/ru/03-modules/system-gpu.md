[↑ Указатель документации](../README.md)

# Модуль `gpu`

Диагностика и нагрузочное тестирование видеокарты в Linux, вендор-агностик:
обнаружение через `lspci`, драйвер/память/температура/утилизация через sysfs
drm (`/sys/class/drm`) и `nvidia-smi` (если установлен), стресс-тест с
мониторингом температуры.

Ярус: **только Linux** (`/sys`/`lspci`). Без GPU, доступа или инструментов —
чистая деградация с определёнными кодами `E_*` / `LIB_ERROR_*`, никогда не
молчаливый успех.

Источник: [lib/system/gpu.sh](../../../lib/system/gpu.sh)

## Подключение

```bash
#!/usr/bin/env bs

load "lib/system/gpu"
```

## Тестовые хуки

| Переменная | По умолчанию | Назначение |
|---|---|---|
| `GPU_SYSFS_DRM_DIR` | `/sys/class/drm` | переопределение корня drm в sysfs |
| `GPU_LSPCI_CMD` | `lspci` | команда lspci (можно путь) — подмена для тестов |
| `GPU_NVIDIA_SMI` | `nvidia-smi` | команда nvidia-smi; пусто — отключено |
| `GPU_STRESS_TOOL` | авто-выбор | принудительный стресс-тул |

## Обнаружение

```bash
gpu::detect          # "vendor<TAB>name" для каждой GPU
gpu::vendor          # nvidia | amd | intel | unknown (первая GPU)
gpu::name            # имя первой GPU без префикса "VGA compatible controller: "
gpu::vendor_of <line> # вендор по строке lspci
```

## Драйвер и память

```bash
gpu::driver          # nvidia (по nvidia-smi) | amdgpu/i915/xe (по sysfs)
gpu::vram            # объём VRAM в байтах (NVIDIA: MiB→байты; AMD: mem_info_vram_total)
```

Intel (разделяемая память) честно возвращает `LIB_ERROR_FILE_NOT_FOUND`.

## Температура и утилизация

```bash
gpu::temperature     # °C: nvidia-smi или hwmon temp1_input (миллиградусы)
gpu::utilization     # %: nvidia-smi или sysfs gpu_busy_percent (AMD)
```

## Нагрузочный тест

```bash
gpu::stress 30
```

Запускает стресс-тул (первый из `glmark2`/`vkcube`/`glxgears`/`gpu-burn`,
или `GPU_STRESS_TOOL`) в фоне, семплирует температуру раз в секунду,
убивает тул и печатает отчёт:

```
stress: tool=glmark2 duration=30s temp_min=52 temp_max=71 temp_avg=58
```

Тулов нет — `LIB_ERROR_DEPENDENCY_MISSING`; длительность не число —
`LIB_ERROR_INVALID_ARGS`.

## Диагностика

```bash
gpu::check            # [PASS]/[WARN]/[FAIL] по каждой проверке
gpu::info             # сводка k=v: vendor/name/driver/vram/temperature/utilization
```

`gpu::check` возвращает `E_SUCCESS`, если нет `[FAIL]`, иначе
`LIB_ERROR_FILE_NOT_FOUND` (GPU не найдена). `gpu::info` — код
`LIB_ERROR_FILE_NOT_FOUND` при отсутствии GPU.

## Каталог инструментов

Каталог специализированных программ диагностики и тестирования GPU с тирами
(`GPU_TOOLS[tool]="tier|package|description"`):

| Tier | Назначение | Инструменты |
|---|---|---|
| 1 | базовые | `lspci`, `nvidia-smi`, `glxinfo`, `vulkaninfo` |
| 2 | мониторинг | `nvtop`, `radeontop`, `amdgpu_top`, `intel_gpu_top`, `rocm-smi` |
| 3 | стресс/бенчмарк | `glmark2`, `vkcube`, `glxgears`, `gpu-burn`, `vkmark` |
| 4 | тест памяти | `vulkan-memtest` |

```bash
gpu::tools 1                       # каталог, фильтр по тиру: "tier<TAB>tool<TAB>pkg<TAB>desc"
gpu::tools_available               # только установленные
gpu::check_dependencies [tier]     # отчёт [OK]/[MISS] по каждому; E_SUCCESS / LIB_ERROR_DEPENDENCY_MISSING
gpu::install_dependencies [tier]   # доустановка недостающих через system::packages::install (дедупликация пакетов)
gpu::run glxinfo -B                # запуск тула; нет тула → LIB_ERROR_DEPENDENCY_MISSING
gpu::glxinfo                       # обёртка: glxinfo -B (краткая инфа OpenGL)
gpu::vulkaninfo                    # обёртка: vulkaninfo --summary
gpu::radeontop                     # обёртка: radeontop -d - (одноразовый снимок AMD)
gpu::rocm_smi                      # обёртка: rocm-smi --showtemp --showuse
gpu::nvtop / gpu::amdgpu_top / gpu::intel_gpu_top
gpu::glmark2 / gpu::vkcube / gpu::glxgears / gpu::gpu_burn / gpu::vkmark
gpu::vulkan_memtest                # тест VRAM на битые ячейки
```

## Связанное

- `examples/gpu_diag.sh` — CLI-точка: `--list`, `--check`, `--stress N`,
  `--tools`, `--run <tool>`, `--deps [tier]`.