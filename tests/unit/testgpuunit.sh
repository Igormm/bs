#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testgpuunit.sh — Unit tests for lib/system/gpu module
# tests/unit/testgpuunit.sh — Модульные тесты модуля lib/system/gpu
#
# Без железа: sysfs drm и lspci подменяются хуками (GPU_SYSFS_DRM_DIR,
# GPU_LSPCI_CMD, GPU_NVIDIA_SMI, GPU_STRESS_TOOL). На реальном хосте —
# только graceful degradation с определёнными кодами.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# ==========================================
# Тестовые фикстуры / test fixtures
# ==========================================

# @private фейковый lspci: печатает строки из FAKE_PCI_LINES
__make_lspci_fake() {
    local -r root="$1"
    cat > "${root}/lspci" <<'EOF'
#!/bin/bash
printf '%s\n' "${FAKE_PCI_LINES:-}"
EOF
    chmod +x "${root}/lspci"
}

# @private фейковый nvidia-smi: отвечает на memory.total/temperature.gpu/utilization.gpu
__make_smi_fake() {
    local -r root="$1"
    cat > "${root}/smi" <<'EOF'
#!/bin/bash
case "${1:-}" in
    --query-gpu=memory.total)      echo '8192' ;;
    --query-gpu=temperature.gpu)   echo '64' ;;
    --query-gpu=utilization.gpu)   echo '33' ;;
esac
EOF
    chmod +x "${root}/smi"
}

# @private фейковый стресс-тул: просто спит
__make_stress_fake() {
    local -r root="$1"
    cat > "${root}/glmark2" <<'EOF'
#!/bin/bash
sleep 30
EOF
    chmod +x "${root}/glmark2"
}

# @private фейковое дерево /sys/class/drm (AMD-карта)
__make_drm_fixture() {
    local -r root="$1"
    mkdir -p "${root}/drm/card0/device/hwmon/hwmon0"
    ln -s amdgpu "${root}/drm/card0/device/driver"
    printf '8589934592\n' > "${root}/drm/card0/device/mem_info_vram_total"
    printf '17\n' > "${root}/drm/card0/device/gpu_busy_percent"
    printf '52000\n' > "${root}/drm/card0/device/hwmon/hwmon0/temp1_input"
}

# ==========================================
# Тесты / tests
# ==========================================

test_loads() {
    load "lib/system/gpu"
    testframework::assert_true "${SYSTEM_GPU_LOADED:-}" "Module loaded"
}

test_vendor() {
    local -r root="$(mktemp -d)"
    __make_lspci_fake "${root}"
    local out rc=0

    out="$(FAKE_PCI_LINES='01:00.0 VGA compatible controller: NVIDIA Corporation GA106 [GeForce RTX 3060]' GPU_LSPCI_CMD="${root}/lspci" gpu::vendor 2>/dev/null)" || rc=$?
    testframework::assert_equal "nvidia" "${out}" "vendor detects NVIDIA"

    out="$(FAKE_PCI_LINES='00:02.0 VGA compatible controller: Intel Corporation AlderLake-S GT1' GPU_LSPCI_CMD="${root}/lspci" gpu::vendor 2>/dev/null)" || rc=$?
    testframework::assert_equal "intel" "${out}" "vendor detects Intel"

    out="$(FAKE_PCI_LINES='02:00.0 3D controller: Advanced Micro Devices, Inc. [AMD/ATI] Vega 20' GPU_LSPCI_CMD="${root}/lspci" gpu::vendor 2>/dev/null)" || rc=$?
    testframework::assert_equal "amd" "${out}" "vendor detects AMD"

    rc=0
    out="$(FAKE_PCI_LINES='00:1f.3 Audio device: Intel Corporation' GPU_LSPCI_CMD="${root}/lspci" gpu::vendor 2>/dev/null)" || rc=$?
    testframework::assert_equal "${LIB_ERROR_FILE_NOT_FOUND}" "${rc}" "no GPU lines → defined code"

    rc=0
    GPU_LSPCI_CMD="${root}/no-such-lspci" gpu::vendor >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_DEPENDENCY_MISSING}" "${rc}" "missing lspci → dependency code"
    rm -rf "${root}"
}

test_name() {
    local -r root="$(mktemp -d)"
    __make_lspci_fake "${root}"
    local out

    out="$(FAKE_PCI_LINES='01:00.0 VGA compatible controller: NVIDIA Corporation GA106 [GeForce RTX 3060]' GPU_LSPCI_CMD="${root}/lspci" gpu::name 2>/dev/null)"
    testframework::assert_equal "NVIDIA Corporation GA106 [GeForce RTX 3060]" "${out}" "name strips bus and controller prefix"

    out="$(FAKE_PCI_LINES='02:00.0 3D controller: Advanced Micro Devices, Inc. [AMD/ATI] Vega 20 [Radeon VII]' GPU_LSPCI_CMD="${root}/lspci" gpu::name 2>/dev/null)"
    testframework::assert_equal "Advanced Micro Devices, Inc. [AMD/ATI] Vega 20 [Radeon VII]" "${out}" "name handles 3D controller"
    rm -rf "${root}"
}

test_detect() {
    local -r root="$(mktemp -d)"
    __make_lspci_fake "${root}"
    local out count=0

    out="$(FAKE_PCI_LINES=$'00:02.0 VGA compatible controller: Intel Corporation UHD Graphics 770\n01:00.0 VGA compatible controller: NVIDIA Corporation GA106' GPU_LSPCI_CMD="${root}/lspci" gpu::detect 2>/dev/null)"
    printf '%s\n' "${out}" | grep -q '^intel	' && count=$(( count + 1 ))
    printf '%s\n' "${out}" | grep -q '^nvidia	' && count=$(( count + 1 ))
    testframework::assert_equal "2" "${count}" "detect lists all GPUs as vendor<TAB>name"
    rm -rf "${root}"
}

test_driver() {
    local -r root="$(mktemp -d)"
    __make_drm_fixture "${root}"
    local out rc=0

    out="$(GPU_SYSFS_DRM_DIR="${root}/drm" GPU_NVIDIA_SMI=/nonexistent gpu::driver 2>/dev/null)" || rc=$?
    testframework::assert_equal "amdgpu" "${out}" "driver from sysfs symlink"

    rc=0
    GPU_SYSFS_DRM_DIR="${root}/empty" GPU_NVIDIA_SMI=/nonexistent gpu::driver >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_FILE_NOT_FOUND}" "${rc}" "no driver → defined code"
    rm -rf "${root}"
}

test_vram() {
    local -r root="$(mktemp -d)"
    __make_drm_fixture "${root}"
    __make_smi_fake "${root}"
    local out rc=0

    out="$(GPU_SYSFS_DRM_DIR="${root}/drm" GPU_NVIDIA_SMI=/nonexistent gpu::vram 2>/dev/null)" || rc=$?
    testframework::assert_equal "8589934592" "${out}" "AMD vram from sysfs bytes"

    out="$(GPU_SYSFS_DRM_DIR="${root}/nope" GPU_NVIDIA_SMI="${root}/smi" gpu::vram 2>/dev/null)" || rc=$?
    testframework::assert_equal "8589934592" "${out}" "NVIDIA vram via smi (8192 MiB → bytes)"

    rc=0
    GPU_SYSFS_DRM_DIR="${root}/nope" GPU_NVIDIA_SMI=/nonexistent gpu::vram >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_FILE_NOT_FOUND}" "${rc}" "no vram → defined code"
    rm -rf "${root}"
}

test_temperature() {
    local -r root="$(mktemp -d)"
    __make_drm_fixture "${root}"
    __make_smi_fake "${root}"
    local out rc=0

    out="$(GPU_SYSFS_DRM_DIR="${root}/drm" GPU_NVIDIA_SMI=/nonexistent gpu::temperature 2>/dev/null)" || rc=$?
    testframework::assert_equal "52" "${out}" "hwmon millidegrees → Celsius"

    out="$(GPU_SYSFS_DRM_DIR="${root}/nope" GPU_NVIDIA_SMI="${root}/smi" gpu::temperature 2>/dev/null)" || rc=$?
    testframework::assert_equal "64" "${out}" "NVIDIA temp via smi"

    rc=0
    GPU_SYSFS_DRM_DIR="${root}/nope" GPU_NVIDIA_SMI=/nonexistent gpu::temperature >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_FILE_NOT_FOUND}" "${rc}" "no temp → defined code"
    rm -rf "${root}"
}

test_utilization() {
    local -r root="$(mktemp -d)"
    __make_drm_fixture "${root}"
    __make_smi_fake "${root}"
    local out rc=0

    out="$(GPU_SYSFS_DRM_DIR="${root}/drm" GPU_NVIDIA_SMI=/nonexistent gpu::utilization 2>/dev/null)" || rc=$?
    testframework::assert_equal "17" "${out}" "AMD utilization from gpu_busy_percent"

    out="$(GPU_SYSFS_DRM_DIR="${root}/nope" GPU_NVIDIA_SMI="${root}/smi" gpu::utilization 2>/dev/null)" || rc=$?
    testframework::assert_equal "33" "${out}" "NVIDIA utilization via smi"

    rc=0
    GPU_SYSFS_DRM_DIR="${root}/nope" GPU_NVIDIA_SMI=/nonexistent gpu::utilization >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_FILE_NOT_FOUND}" "${rc}" "no utilization → defined code"
    rm -rf "${root}"
}

test_stress() {
    local -r root="$(mktemp -d)"
    __make_drm_fixture "${root}"
    __make_stress_fake "${root}"
    local out rc=0

    out="$(GPU_SYSFS_DRM_DIR="${root}/drm" GPU_NVIDIA_SMI=/nonexistent GPU_STRESS_TOOL="${root}/glmark2" gpu::stress 2 2>&1)" || rc=$?
    testframework::assert_equal "0" "${rc}" "stress completes with success"
    testframework::assert_true "'${out}' =~ tool=${root}/glmark2" "report names the tool"
    testframework::assert_true "'${out}' =~ temp_min=52" "report min temperature"
    testframework::assert_true "'${out}' =~ temp_max=52" "report max temperature"
    testframework::assert_true "'${out}' =~ temp_avg=52" "report avg temperature"
    rm -rf "${root}"
}

test_stress_bad_args() {
    local rc=0
    gpu::stress abc >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_ARGS}" "${rc}" "non-numeric duration rejected"
}

test_stress_tool_selection() {
    local out rc=0
    out="$(GPU_STRESS_TOOL=/my/tool gpu::__stress_tool 2>/dev/null)" || rc=$?
    testframework::assert_equal "/my/tool" "${out}" "GPU_STRESS_TOOL override wins"

    rc=0
    PATH="/nonexistent-bin" GPU_STRESS_TOOL='' gpu::__stress_tool >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_DEPENDENCY_MISSING}" "${rc}" "no tools in PATH → dependency code"
}

test_info_and_check() {
    local -r root="$(mktemp -d)"
    __make_lspci_fake "${root}"
    __make_drm_fixture "${root}"
    local out rc=0

    out="$(FAKE_PCI_LINES='01:00.0 VGA compatible controller: NVIDIA Corporation GA106' GPU_LSPCI_CMD="${root}/lspci" GPU_SYSFS_DRM_DIR="${root}/drm" GPU_NVIDIA_SMI=/nonexistent gpu::info 2>/dev/null)" || rc=$?
    testframework::assert_equal "0" "${rc}" "info succeeds with fake GPU"
    testframework::assert_true '${out} == *"vendor=nvidia"*' "info has vendor"
    testframework::assert_true '${out} == *"driver=amdgpu"*' "info has driver"
    testframework::assert_true '${out} == *"temperature=52"*' "info has temperature"

    out="$(FAKE_PCI_LINES='01:00.0 VGA compatible controller: NVIDIA Corporation GA106' GPU_LSPCI_CMD="${root}/lspci" GPU_SYSFS_DRM_DIR="${root}/drm" GPU_NVIDIA_SMI=/nonexistent gpu::check 2>&1)" || rc=$?
    testframework::assert_true "'${out}' =~ \[PASS\]\ vendor" "check reports PASS vendor"
    testframework::assert_true "'${out}' =~ \[PASS\]\ name" "check reports PASS name"
    testframework::assert_false "'${out}' =~ \[FAIL\]" "check has no FAILs"
    rm -rf "${root}"
}

test_real_host_graceful() {
    # На хосте без GPU/прав — чистая деградация с определённым кодом
    local rc=0
    GPU_SYSFS_DRM_DIR="/nonexistent-drm-xyz" GPU_NVIDIA_SMI=/nonexistent gpu::temperature >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_FILE_NOT_FOUND}" "${rc}" "temperature degrades with defined code"

    rc=0
    GPU_LSPCI_CMD=/nonexistent-lspci-xyz gpu::vendor >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_DEPENDENCY_MISSING}" "${rc}" "vendor degrades with dependency code"
}

main() {
    print_header "GPU Module Unit Tests / Модульные тесты lib/system/gpu"

    testframework::init

    testframework::section "Discovery / Обнаружение"
    test_loads
    test_vendor
    test_name
    test_detect

    testframework::section "Driver and VRAM / Драйвер и память"
    test_driver
    test_vram

    testframework::section "Temperature and utilization / Температура и утилизация"
    test_temperature
    test_utilization

    testframework::section "Stress test / Нагрузочный тест"
    test_stress
    test_stress_bad_args
    test_stress_tool_selection

    testframework::section "Reports / Отчёты"
    test_info_and_check

    testframework::section "Real host graceful degradation / Деградация на реальном хосте"
    test_real_host_graceful

    testframework::summary
}

main "$@"