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

## Связанное

- `examples/gpu_diag.sh` — CLI-точка: `--list`, `--check`, `--stress N`.