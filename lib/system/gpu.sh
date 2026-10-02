#!/usr/bin/env bs
# shellcheck shell=bash
# lib/system/gpu.sh — GPU diagnostics and stress testing (vendor-agnostic)
# lib/system/gpu.sh — диагностика и нагрузочное тестирование видеокарты (вендор-агностик)
#
# Tier / Ярус: Linux-only (/sys/class/drm, lspci, опционально nvidia-smi).
# Деградация: определённые E_*/LIB_ERROR_* коды при отсутствии GPU, доступа
# или инструментов; никогда не молчаливый успех.
#
# @depends core/const, core/logger, core/utils, core/deps, lib/system/packages

# Source Guard / Защита от повторной загрузки
bs::guard "SYSTEM_GPU" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "../../core/deps.sh" "../system/packages.sh"

# @global SYSTEM_GPU_VERSION — Module version (category: module-flag)
# @global SYSTEM_GPU_VERSION — Версия модуля (категория: module-flag)
declare -g SYSTEM_GPU_VERSION="1.0.0"
# @global SYSTEM_GPU_LOADED — Module loaded flag (category: module-flag)
# @global SYSTEM_GPU_LOADED — Флаг загрузки модуля (категория: module-flag)
declare -g SYSTEM_GPU_LOADED="1"

# @global GPU_SYSFS_DRM_DIR — Hook: sysfs drm root /sys/class/drm (category: hook)
# @global GPU_SYSFS_DRM_DIR — Хук: корень drm в sysfs /sys/class/drm (категория: hook)
: "${GPU_SYSFS_DRM_DIR:=/sys/class/drm}"
# @global GPU_LSPCI_CMD — Hook: lspci command (path allowed) (category: hook)
# @global GPU_LSPCI_CMD — Хук: команда lspci (можно путь) (категория: hook)
: "${GPU_LSPCI_CMD:=lspci}"
# @global GPU_NVIDIA_SMI — Hook: nvidia-smi command; empty disables (category: hook)
# @global GPU_NVIDIA_SMI — Хук: команда nvidia-smi; пусто — отключено (категория: hook)
: "${GPU_NVIDIA_SMI:=nvidia-smi}"
# @global GPU_STRESS_TOOL — Hook: stress tool override (empty = auto-detect) (category: hook)
# @global GPU_STRESS_TOOL — Хук: принудительный стресс-тул (пусто = авто-выбор) (категория: hook)
: "${GPU_STRESS_TOOL:=}"

# ==========================================
# Обнаружение / Discovery (lspci)
# ==========================================

# @private
# @description Проверить доступность lspci / Check lspci availability
# @return E_SUCCESS ok; LIB_ERROR_DEPENDENCY_MISSING нет lspci
gpu::__require_lspci() {
    if ! is::command "${GPU_LSPCI_CMD}"; then
        log::error "gpu: lspci not found (install pciutils)"
        return "${LIB_ERROR_DEPENDENCY_MISSING}"
    fi
    return "${E_SUCCESS}"
}

# @private
# @description Строки VGA/3D/Display из lspci / VGA/3D/Display lines from lspci
# @stdout строки lspci / lspci lines
# @return E_SUCCESS найдено; LIB_ERROR_FILE_NOT_FOUND GPU нет
gpu::__pci_gpus() {
    gpu::__require_lspci || return $?
    local out=""
    out="$("${GPU_LSPCI_CMD}" 2>/dev/null | grep -Ei '(vga compatible controller|3d controller|display controller)' || true)"
    if is::empty "${out}"; then
        return "${LIB_ERROR_FILE_NOT_FOUND}"
    fi
    printf '%s\n' "${out}"
    return "${E_SUCCESS}"
}

# @description Вендор по строке lspci / Vendor of an lspci line
# @param $1 Строка lspci / lspci line
# @stdout nvidia | amd | intel | unknown
gpu::vendor_of() {
    local -r line="${1}"
    case "${line}" in
        *[Nn][Vv][Ii][Dd][Ii][Aa]*) printf 'nvidia\n' ;;
        *[Aa][Mm][Dd]*|*[Rr][Aa][Dd][Ee][Oo][Nn]*|*[Aa][Mm][Dd]/[Aa][Tt][Ii]*) printf 'amd\n' ;;
        *[Ii][Nn][Tt][Ee][Ll]*) printf 'intel\n' ;;
        *) printf 'unknown\n' ;;
    esac
}

# @private
# @description Очистить имя GPU из строки lspci / Clean GPU name from an lspci line
# @param $1 Строка lspci / lspci line
# @stdout имя / name
gpu::__clean_name() {
    local -r raw="${1}"
    local rest="${raw#* }"
    if [[ "${rest}" == *controller:* ]]; then
        rest="${rest#*controller: }"
    fi
    rest="$(printf '%s\n' "${rest}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    printf '%s\n' "${rest}"
}

# @description Вендор первой GPU / Vendor of the first GPU
# @stdout nvidia | amd | intel | unknown
# @return E_SUCCESS найдено; LIB_ERROR_FILE_NOT_FOUND GPU нет
gpu::vendor() {
    local out="" line=""
    out="$(gpu::__pci_gpus)" || return $?
    while IFS= read -r line; do
        gpu::vendor_of "${line}"
        return "${E_SUCCESS}"
    done <<< "${out}"
    return "${LIB_ERROR_FILE_NOT_FOUND}"
}

# @description Имя первой GPU / Name of the first GPU
# @stdout имя / name
# @return E_SUCCESS найдено; LIB_ERROR_FILE_NOT_FOUND GPU нет
gpu::name() {
    local out="" line=""
    out="$(gpu::__pci_gpus)" || return $?
    while IFS= read -r line; do
        gpu::__clean_name "${line}"
        return "${E_SUCCESS}"
    done <<< "${out}"
    return "${LIB_ERROR_FILE_NOT_FOUND}"
}

# @description Список GPU как "vendor<TAB>name" / List GPUs as "vendor<TAB>name"
# @stdout по строке на GPU / one line per GPU
# @return E_SUCCESS найдено; LIB_ERROR_FILE_NOT_FOUND GPU нет
gpu::detect() {
    local out="" line="" v="" n=""
    out="$(gpu::__pci_gpus)" || return $?
    while IFS= read -r line; do
        v="$(gpu::vendor_of "${line}")"
        n="$(gpu::__clean_name "${line}")"
        printf '%s\t%s\n' "${v}" "${n}"
    done <<< "${out}"
    return "${E_SUCCESS}"
}

# ==========================================
# Драйвер и память / Driver and VRAM
# ==========================================

# @description Имя драйвера GPU / GPU driver name
#   nvidia-smi → nvidia; иначе symlink device/driver в sysfs (amdgpu, i915, xe...)
# @stdout имя драйвера / driver name
# @return E_SUCCESS найден; LIB_ERROR_FILE_NOT_FOUND не определён
gpu::driver() {
    if is::command "${GPU_NVIDIA_SMI}"; then
        printf 'nvidia\n'
        return "${E_SUCCESS}"
    fi
    local d
    for d in "${GPU_SYSFS_DRM_DIR}"/card[0-9]*/device/driver; do
        if [[ -L "${d}" ]]; then
            printf '%s\n' "$(basename "$(readlink -f "${d}")")"
            return "${E_SUCCESS}"
        fi
    done
    return "${LIB_ERROR_FILE_NOT_FOUND}"
}

# @description Объём видеопамяти в байтах / VRAM size in bytes
#   NVIDIA: nvidia-smi (MiB → байты); AMD: sysfs mem_info_vram_total.
#   Intel (разделяемая память) — честно "не доступно".
# @stdout число байт / byte count
# @return E_SUCCESS найден; LIB_ERROR_FILE_NOT_FOUND не доступен
gpu::vram() {
    if is::command "${GPU_NVIDIA_SMI}"; then
        local mi="" rc=0
        mi="$("${GPU_NVIDIA_SMI}" --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null)" || rc=$?
        if (( rc == 0 )) && is::number "${mi}"; then
            printf '%s\n' "$(( mi * 1048576 ))"
            return "${E_SUCCESS}"
        fi
    fi
    local f bytes
    for f in "${GPU_SYSFS_DRM_DIR}"/card[0-9]*/device/mem_info_vram_total; do
        if is::readable "${f}"; then
            bytes="$(cat "${f}")"
            if is::number "${bytes}"; then
                printf '%s\n' "${bytes}"
                return "${E_SUCCESS}"
            fi
        fi
    done
    return "${LIB_ERROR_FILE_NOT_FOUND}"
}

# ==========================================
# Температура и утилизация / Temperature and utilization
# ==========================================

# @description Температура GPU в °C / GPU temperature in Celsius
#   NVIDIA: nvidia-smi; AMD/Intel: hwmon temp1_input (миллиградусы).
# @stdout целое °C / integer Celsius
# @return E_SUCCESS найдена; LIB_ERROR_FILE_NOT_FOUND не доступна
gpu::temperature() {
    if is::command "${GPU_NVIDIA_SMI}"; then
        local t="" rc=0
        t="$("${GPU_NVIDIA_SMI}" --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null)" || rc=$?
        if (( rc == 0 )) && is::number "${t}"; then
            printf '%s\n' "${t}"
            return "${E_SUCCESS}"
        fi
    fi
    local f millis
    for f in "${GPU_SYSFS_DRM_DIR}"/card[0-9]*/device/hwmon/hwmon*/temp1_input; do
        if is::readable "${f}"; then
            millis="$(cat "${f}")"
            if is::number "${millis}"; then
                printf '%s\n' "$(( millis / 1000 ))"
                return "${E_SUCCESS}"
            fi
        fi
    done
    return "${LIB_ERROR_FILE_NOT_FOUND}"
}

# @description Загрузка GPU в % / GPU utilization percent
#   NVIDIA: nvidia-smi; AMD: sysfs gpu_busy_percent.
# @stdout целое % / integer percent
# @return E_SUCCESS найдена; LIB_ERROR_FILE_NOT_FOUND не доступна
gpu::utilization() {
    if is::command "${GPU_NVIDIA_SMI}"; then
        local u="" rc=0
        u="$("${GPU_NVIDIA_SMI}" --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null)" || rc=$?
        if (( rc == 0 )) && is::number "${u}"; then
            printf '%s\n' "${u}"
            return "${E_SUCCESS}"
        fi
    fi
    local f p
    for f in "${GPU_SYSFS_DRM_DIR}"/card[0-9]*/device/gpu_busy_percent; do
        if is::readable "${f}"; then
            p="$(cat "${f}")"
            if is::number "${p}"; then
                printf '%s\n' "${p}"
                return "${E_SUCCESS}"
            fi
        fi
    done
    return "${LIB_ERROR_FILE_NOT_FOUND}"
}

# ==========================================
# Нагрузочный тест / Stress test
# ==========================================

# @private
# @description Выбрать стресс-тул / Pick a stress tool
#   GPU_STRESS_TOOL принудительно; иначе первый из glmark2/vkcube/glxgears/gpu-burn.
# @stdout имя/путь тула / tool name or path
# @return E_SUCCESS найден; LIB_ERROR_DEPENDENCY_MISSING тулов нет
gpu::__stress_tool() {
    if is::not_empty "${GPU_STRESS_TOOL}"; then
        printf '%s\n' "${GPU_STRESS_TOOL}"
        return "${E_SUCCESS}"
    fi
    local t
    for t in glmark2 vkcube glxgears gpu-burn; do
        if is::command "${t}"; then
            printf '%s\n' "${t}"
            return "${E_SUCCESS}"
        fi
    done
    return "${LIB_ERROR_DEPENDENCY_MISSING}"
}

# @description Нагрузочный тест GPU с мониторингом температуры / GPU stress test
#   Запускает стресс-тул в фоне и семплирует температуру раз в секунду,
#   затем убивает тул и печатает отчёт min/max/avg.
# @param $1 Продолжительность в секундах / Duration in seconds
# @stdout строка отчёта / report line
# @return E_SUCCESS тест выполнен; LIB_ERROR_* нет тула/неверный аргумент
gpu::stress() {
    local -r seconds="${1:?duration in seconds required}"
    if ! is::number "${seconds}"; then
        log::error "gpu::stress: duration must be a number: ${seconds}"
        return "${LIB_ERROR_INVALID_ARGS}"
    fi

    local tool="" rc=0
    tool="$(gpu::__stress_tool)" || rc=$?
    if (( rc != 0 )); then
        log::error "gpu::stress: no stress tool found (glmark2/vkcube/glxgears/gpu-burn); set GPU_STRESS_TOOL"
        return "${LIB_ERROR_DEPENDENCY_MISSING}"
    fi

    "${tool}" >/dev/null 2>&1 &
    local -r pid=$!

    local -r deadline=$(( $(utils::now_ms) + seconds * 1000 ))
    local now temp t_min="" t_max="" t_sum=0 t_count=0

    while true; do
        now="$(utils::now_ms)"
        if (( now >= deadline )); then
            break
        fi
        if temp="$(gpu::temperature 2>/dev/null)" && is::number "${temp}"; then
            if is::empty "${t_min}" || (( temp < t_min )); then
                t_min="${temp}"
            fi
            if is::empty "${t_max}" || (( temp > t_max )); then
                t_max="${temp}"
            fi
            t_sum=$(( t_sum + temp ))
            t_count=$(( t_count + 1 ))
        fi
        sleep 1
    done

    if ! kill -0 "${pid}" 2>/dev/null; then
        log::warn "gpu::stress: ${tool} exited before ${seconds}s"
    fi
    kill "${pid}" 2>/dev/null || true
    utils::ignore wait "${pid}"

    local avg="n/a"
    if (( t_count > 0 )); then
        avg="$(( t_sum / t_count ))"
    fi
    printf 'stress: tool=%s duration=%ss temp_min=%s temp_max=%s temp_avg=%s\n' \
        "${tool}" "${seconds}" "${t_min:-n/a}" "${t_max:-n/a}" "${avg}"
    return "${E_SUCCESS}"
}

# ==========================================
# Каталог инструментов / Tools catalog
# ==========================================

# @global GPU_TOOLS — Tools catalog: tier|package|description (category: constant)
# @global GPU_TOOLS — Каталог инструментов: тир|пакет|описание (категория: constant)
#   Тиры / tiers: 1 — базовые (diagnostics), 2 — мониторинг (monitoring),
#   3 — стресс/бенчмарки (stress/benchmark), 4 — тест памяти (VRAM test).
declare -gA GPU_TOOLS=(
    [lspci]="1|pciutils|PCI bus enumeration / шина PCI"
    [nvidia-smi]="1|nvidia-utils|NVIDIA diagnostics (temp/VRAM/utilization)"
    [glxinfo]="1|mesa-utils|OpenGL renderer and version info"
    [vulkaninfo]="1|vulkan-tools|Vulkan devices and extensions"
    [nvtop]="2|nvtop|Unified GPU monitor (NVIDIA/AMD/Intel)"
    [radeontop]="2|radeontop|AMD Radeon utilization monitor"
    [amdgpu_top]="2|amdgpu_top|AMD GPU top (modern radeontop replacement)"
    [intel_gpu_top]="2|intel-gpu-tools|Intel GPU utilization monitor"
    [rocm-smi]="2|rocm-smi-lib|AMD ROCm system management"
    [glmark2]="3|glmark2|OpenGL 2.0 benchmark"
    [vkcube]="3|vulkan-tools|Vulkan smoke/load demo"
    [glxgears]="3|mesa-utils|OpenGL load demo (FPS)"
    [gpu-burn]="3|gpu-burn|CUDA compute stress test"
    [vkmark]="3|vkmark|Vulkan benchmark"
    [vulkan-memtest]="4|vulkan-memtest|VRAM memory test (bad cells)"
)

# @description Каталог инструментов / Tools catalog
# @param $1 [optional] Фильтр по тиру 1|2|3|4 / Tier filter
# @stdout "tier<TAB>tool<TAB>package<TAB>description" по строке на инструмент
# @return E_SUCCESS
# @example
#   gpu::tools 1          # только базовые / only tier 1
gpu::tools() {
    local -r tier_filter="${1:-}"
    local tool spec tier pkg desc
    for tool in "${!GPU_TOOLS[@]}"; do
        spec="${GPU_TOOLS[${tool}]}"
        tier="${spec%%|*}"
        if is::not_empty "${tier_filter}" && [[ "${tier}" != "${tier_filter}" ]]; then
            continue
        fi
        pkg="${spec#*|}"
        desc="${pkg#*|}"
        pkg="${pkg%%|*}"
        printf '%s\t%s\t%s\t%s\n' "${tier}" "${tool}" "${pkg}" "${desc}"
    done | sort
    return "${E_SUCCESS}"
}

# @description Установленные инструменты каталога / Installed catalog tools
# @param $1 [optional] Фильтр по тиру 1|2|3|4 / Tier filter
# @stdout "tier<TAB>tool" по строке на инструмент
# @return E_SUCCESS
gpu::tools_available() {
    local -r tier_filter="${1:-}"
    local tool spec tier
    for tool in "${!GPU_TOOLS[@]}"; do
        spec="${GPU_TOOLS[${tool}]}"
        tier="${spec%%|*}"
        if is::not_empty "${tier_filter}" && [[ "${tier}" != "${tier_filter}" ]]; then
            continue
        fi
        if is::command "${tool}"; then
            printf '%s\t%s\n' "${tier}" "${tool}"
        fi
    done | sort
    return "${E_SUCCESS}"
}

# @description Проверить наличие инструментов каталога / Check catalog tools presence
# @param $1 [optional] Фильтр по тиру 1|2|3|4 / Tier filter
# @stdout строки "[OK]"/"[MISS]" с тиром и пакетом
# @return E_SUCCESS все на месте; LIB_ERROR_DEPENDENCY_MISSING чего-то нет
gpu::check_dependencies() {
    local -r tier_filter="${1:-}"
    local tool spec tier pkg missing=0
    for tool in "${!GPU_TOOLS[@]}"; do
        spec="${GPU_TOOLS[${tool}]}"
        tier="${spec%%|*}"
        if is::not_empty "${tier_filter}" && [[ "${tier}" != "${tier_filter}" ]]; then
            continue
        fi
        pkg="${spec#*|}"
        pkg="${pkg%%|*}"
        if is::command "${tool}"; then
            printf '[OK]   tier=%s %-16s package=%s\n' "${tier}" "${tool}" "${pkg}"
        else
            printf '[MISS] tier=%s %-16s package=%s\n' "${tier}" "${tool}" "${pkg}"
            missing=1
        fi
    done
    if (( missing == 0 )); then
        return "${E_SUCCESS}"
    fi
    return "${LIB_ERROR_DEPENDENCY_MISSING}"
}

# @description Доустановить недостающие инструменты каталога / Install missing tools
# @param $1 [optional] Фильтр по тиру 1|2|3|4 / Tier filter
# @return E_SUCCESS установлены/нечего ставить; код ошибки установки
gpu::install_dependencies() {
    local -r tier_filter="${1:-}"
    local -a missing=()
    local tool spec tier pkg
    for tool in "${!GPU_TOOLS[@]}"; do
        spec="${GPU_TOOLS[${tool}]}"
        tier="${spec%%|*}"
        if is::not_empty "${tier_filter}" && [[ "${tier}" != "${tier_filter}" ]]; then
            continue
        fi
        if ! is::command "${tool}"; then
            pkg="${spec#*|}"
            pkg="${pkg%%|*}"
            missing+=("${pkg}")
        fi
    done
    if (( ${#missing[@]} == 0 )); then
        log::info "gpu: all catalog tools already installed"
        return "${E_SUCCESS}"
    fi
    local -a uniq=()
    for pkg in "${missing[@]}"; do
        [[ " ${uniq[*]} " == *" ${pkg} "* ]] || uniq+=("${pkg}")
    done
    log::info "gpu: installing missing tools: ${uniq[*]}"
    system::packages::install "${uniq[@]}"
}

# @description Запустить инструмент каталога / Run a catalog tool
# @param $1 Имя инструмента / Tool name
# @param $@ [optional] Аргументы / Arguments
# @stdout вывод инструмента / tool output
# @return код инструмента; LIB_ERROR_DEPENDENCY_MISSING не установлен
# @example
#   gpu::run vulkaninfo --summary
gpu::run() {
    local -r tool="${1:?tool name required}"
    shift
    if ! is::command "${tool}"; then
        local hint=""
        if [[ -v GPU_TOOLS["${tool}"] ]]; then
            hint="${GPU_TOOLS[${tool}]}"
            hint="${hint#*|}"
            hint="${hint%%|*}"
        fi
        log::error "gpu::run: ${tool} not installed${hint:+ (package: ${hint})}"
        return "${LIB_ERROR_DEPENDENCY_MISSING}"
    fi
    "${tool}" "$@"
}

# @description OpenGL info (glxinfo -B) / Информация OpenGL
gpu::glxinfo() {
    gpu::run glxinfo -B
}

# @description Vulkan info (vulkaninfo --summary) / Информация Vulkan
gpu::vulkaninfo() {
    gpu::run vulkaninfo --summary
}

# @description AMD utilization snapshot (radeontop -d -) / Утилизация AMD
gpu::radeontop() {
    gpu::run radeontop -d -
}

# @description Unified GPU monitor (nvtop) / Монитор GPU
gpu::nvtop() {
    gpu::run nvtop
}

# @description AMD GPU top (amdgpu_top) / Монитор AMD
gpu::amdgpu_top() {
    gpu::run amdgpu_top
}

# @description Intel GPU monitor (intel_gpu_top) / Монитор Intel
gpu::intel_gpu_top() {
    gpu::run intel_gpu_top
}

# @description AMD ROCm info (rocm-smi) / Информация ROCm
gpu::rocm_smi() {
    gpu::run rocm-smi --showtemp --showuse
}

# @description OpenGL benchmark (glmark2) / Бенчмарк OpenGL
gpu::glmark2() {
    gpu::run glmark2
}

# @description Vulkan smoke test (vkcube) / Смоук-тест Vulkan
gpu::vkcube() {
    gpu::run vkcube
}

# @description OpenGL FPS demo (glxgears) / Демо FPS
gpu::glxgears() {
    gpu::run glxgears
}

# @description CUDA compute stress (gpu-burn) / Стресс CUDA
gpu::gpu_burn() {
    gpu::run gpu-burn
}

# @description Vulkan benchmark (vkmark) / Бенчмарк Vulkan
gpu::vkmark() {
    gpu::run vkmark
}

# @description VRAM memory test (vulkan-memtest) / Тест памяти VRAM
gpu::vulkan_memtest() {
    gpu::run vulkan-memtest
}

# ==========================================
# Отчёты / Reports
# ==========================================

# @description Полная диагностика / Full diagnostics
#   Строки [PASS]/[WARN]/[FAIL] по каждой проверке.
# @stdout отчёт / report
# @return E_SUCCESS нет [FAIL]; LIB_ERROR_FILE_NOT_FOUND GPU не найдена
gpu::check() {
    local fails=0 out=""
    if out="$(gpu::vendor 2>/dev/null)"; then
        printf '[PASS] vendor: %s\n' "${out}"
    else
        printf '[FAIL] vendor: GPU not found (lspci: no VGA/3D/Display lines)\n'
        fails=1
    fi
    if out="$(gpu::name 2>/dev/null)"; then
        printf '[PASS] name: %s\n' "${out}"
    else
        printf '[FAIL] name: unknown\n'
        fails=1
    fi
    if out="$(gpu::driver 2>/dev/null)"; then
        printf '[PASS] driver: %s\n' "${out}"
    else
        printf '[WARN] driver: not exposed (basic framebuffer?)\n'
    fi
    if out="$(gpu::vram 2>/dev/null)"; then
        printf '[PASS] vram: %s bytes\n' "${out}"
    else
        printf '[WARN] vram: n/a (Intel shared memory or missing sysfs)\n'
    fi
    if out="$(gpu::temperature 2>/dev/null)"; then
        printf '[PASS] temperature: %s C\n' "${out}"
    else
        printf '[WARN] temperature: n/a (no hwmon / nvidia-smi)\n'
    fi
    if out="$(gpu::utilization 2>/dev/null)"; then
        printf '[PASS] utilization: %s %%\n' "${out}"
    else
        printf '[WARN] utilization: n/a\n'
    fi
    if out="$(gpu::__stress_tool 2>/dev/null)"; then
        printf '[PASS] stress tool: %s\n' "${out}"
    else
        printf '[WARN] stress tool: none of glmark2/vkcube/glxgears/gpu-burn\n'
    fi
    if (( fails == 0 )); then
        return "${E_SUCCESS}"
    fi
    return "${LIB_ERROR_FILE_NOT_FOUND}"
}

# @description Сводка GPU в формате k=v / GPU summary as k=v lines
# @stdout сводка / summary
# @return E_SUCCESS найдена; LIB_ERROR_FILE_NOT_FOUND GPU нет
gpu::info() {
    local out=""
    out="$(gpu::vendor 2>/dev/null)" || return $?
    printf 'vendor=%s\n' "${out}"
    if out="$(gpu::name 2>/dev/null)"; then
        printf 'name=%s\n' "${out}"
    fi
    if out="$(gpu::driver 2>/dev/null)"; then
        printf 'driver=%s\n' "${out}"
    fi
    if out="$(gpu::vram 2>/dev/null)"; then
        printf 'vram=%s\n' "${out}"
    fi
    if out="$(gpu::temperature 2>/dev/null)"; then
        printf 'temperature=%s\n' "${out}"
    fi
    if out="$(gpu::utilization 2>/dev/null)"; then
        printf 'utilization=%s\n' "${out}"
    fi
    return "${E_SUCCESS}"
}