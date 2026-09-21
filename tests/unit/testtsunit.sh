#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testtsunit.sh — Unit tests for lib/ts/toolchain module
# tests/unit/testtsunit.sh — Модульные тесты модуля lib/ts/toolchain

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# ==========================================
# Фикстуры / fixtures
# ==========================================

# @private каталог с фейковым node/tsc и пустым PATH-каталогом
__fixture() {
    local -r root="$(mktemp -d)"
    mkdir -p "${root}/bin" "${root}/emptybin" "${root}/proj"
    printf '#!/bin/sh\nprintf "v22.1.2\\n"\n' > "${root}/bin/node"
    printf '#!/bin/sh\nprintf "10.9.7\\n"\n' > "${root}/bin/npm"
    chmod +x "${root}/bin/node" "${root}/bin/npm"
    mkdir -p "${root}/proj/node_modules/.bin"
    printf '{"name":"demo","version":"1.2.3","scripts":{"dev":"vite","build":"tsc"}}\n' \
        > "${root}/proj/package.json"
    printf '{"compilerOptions":{"strict":true}}\n' > "${root}/proj/tsconfig.json"
    printf '%s\n' "${root}"
}

# ==========================================
# Тесты / tests
# ==========================================

test_loads() {
    load "lib/ts/toolchain"
    testframework::assert_true "${TS_TOOLCHAIN_LOADED:-}" "Module loaded"
}

test_runtime_detection() {
    local -r root="$(__fixture)"
    local out rc
    out="$(PATH="${root}/bin:/usr/bin:/bin" ts::toolchain::runtime_version node)"
    testframework::assert_equal "22.1.2" "${out}" "runtime_version strips v"
    rc=0
    PATH="${root}/emptybin" ts::toolchain::runtime_version node >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_DEPENDENCY_MISSING}" "${rc}" "missing runtime code"
    out="$(PATH="${root}/bin:/usr/bin:/bin" TS_RUNTIMES="node bun" ts::toolchain::detect_runtime)"
    testframework::assert_equal "node" "${out}" "detect_runtime priority"
    out="$(PATH="${root}/bin:/usr/bin:/bin" TS_RUNTIMES="nosuchxyz" ts::toolchain::detect_runtime 2>/dev/null)" || true
    testframework::assert_equal "" "${out}" "detect_runtime empty when absent"
    rm -rf "${root}"
}

test_runtimes_listing() {
    local -r root="$(__fixture)"
    local out
    out="$(PATH="${root}/bin:/usr/bin:/bin" TS_RUNTIMES="node" ts::toolchain::runtimes)"
    testframework::assert_true '${out} == node*22.1.2*' "runtimes lists bin+version"
    out="$(PATH="${root}/bin:/usr/bin:/bin" TS_PACKAGE_MANAGERS="npm" ts::toolchain::package_managers)"
    testframework::assert_true '${out} == npm*10.9.7*' "package_managers lists npm"
    rm -rf "${root}"
}

test_lockfile_pm() {
    local -r root="$(__fixture)"
    local pm
    touch "${root}/proj/pnpm-lock.yaml"
    pm="$(ts::toolchain::lockfile_pm "${root}/proj")"
    testframework::assert_equal "pnpm" "${pm}" "pnpm lock wins over npm lock"
    rm -f "${root}/proj/pnpm-lock.yaml"
    touch "${root}/proj/package-lock.json"
    pm="$(ts::toolchain::lockfile_pm "${root}/proj")"
    testframework::assert_equal "npm" "${pm}" "package-lock -> npm"
    local rc=0
    ts::toolchain::lockfile_pm "${root}/emptybin" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_FILE_NOT_FOUND}" "${rc}" "no lockfile code"
    rm -rf "${root}"
}

test_project_layout() {
    local -r root="$(__fixture)"
    testframework::assert_command "ts::toolchain::has_tsconfig ${root}/proj" "tsconfig detected"
    testframework::assert_false "ts::toolchain::has_tsconfig ${root}/emptybin" "no tsconfig elsewhere"
    testframework::assert_command "ts::toolchain::has_node_modules ${root}/proj" "node_modules detected"
    local out
    out="$(ts::toolchain::pkg_field "${root}/proj" version)"
    testframework::assert_equal "1.2.3" "${out}" "pkg_field version"
    rm -rf "${root}"
}

test_pkg_field_scripts() {
    if ! utils::has jq; then
        testframework::assert_true "true" "jq absent - scalar path still tested above"
        return
    fi
    local -r root="$(__fixture)"
    local out
    out="$(ts::toolchain::pkg_field "${root}/proj" scripts)"
    testframework::assert_equal "build dev" "${out}" "scripts keys via jq (sorted)"
    rm -rf "${root}"
}

test_tsc_bin_resolution() {
    local -r root="$(__fixture)"
    printf '#!/bin/sh\nexit 0\n' > "${root}/proj/node_modules/.bin/tsc"
    chmod +x "${root}/proj/node_modules/.bin/tsc"
    local out
    out="$(ts::toolchain::tsc_bin "${root}/proj")"
    testframework::assert_equal "${root}/proj/node_modules/.bin/tsc" "${out}" "local tsc wins"
    local rc=0
    PATH="${root}/emptybin" ts::toolchain::tsc_bin "${root}/emptybin" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_DEPENDENCY_MISSING}" "${rc}" "no tsc anywhere"
    rm -rf "${root}"
}

test_validate_gates() {
    local -r root="$(__fixture)"
    # PASS: tsc-stub exits 0; eslint/prettier отсутствуют -> SKIP
    printf '#!/bin/sh\nexit 0\n' > "${root}/proj/node_modules/.bin/tsc"
    chmod +x "${root}/proj/node_modules/.bin/tsc"
    local out rc=0
    out="$(ts::toolchain::validate "${root}/proj")" || rc=$?
    testframework::assert_equal "${E_SUCCESS}" "${rc}" "validate green with passing tsc"
    testframework::assert_true '${out} == *"tsc"*PASS*' "tsc PASS line"
    testframework::assert_true '${out} == *"eslint"*SKIP*' "eslint SKIP without config"
    testframework::assert_true '${out} == *"prettier"*SKIP*' "prettier SKIP without config"

    # FAIL: tsc-stub errors
    printf '#!/bin/sh\nprintf "src/a.ts(1,1): error TS2304: nope\\n" >&2\nexit 1\n' \
        > "${root}/proj/node_modules/.bin/tsc"
    chmod +x "${root}/proj/node_modules/.bin/tsc"
    rc=0
    out="$(ts::toolchain::validate "${root}/proj" 2>/dev/null)" || rc=$?
    testframework::assert_equal "${E_ERROR}" "${rc}" "validate fails on tsc error"
    testframework::assert_true '${out} == *"tsc"*FAIL*TS2304*' "FAIL carries first error line"
    rm -rf "${root}"
}

test_port_free() {
    local rc=0
    ts::toolchain::port_free abc >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "non-numeric port rejected"
    rc=0
    ts::toolchain::port_free 70000 >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "out-of-range port rejected"
    rc=0
    ts::toolchain::port_free 49999 >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${E_SUCCESS}" "${rc}" "unused high port is free"
}

test_doctor_summary() {
    local -r root="$(__fixture)"
    local out
    out="$(PATH="${root}/bin:/usr/bin:/bin" TS_RUNTIMES="node" ts::toolchain::doctor "${root}/proj")"
    testframework::assert_true '${out} == *"runtime=node 22.1.2"*' "doctor shows runtime"
    testframework::assert_true '${out} == *"tsconfig=yes"*' "doctor shows tsconfig"
    testframework::assert_true '${out} == *"project-version=1.2.3"*' "doctor shows version"
    rm -rf "${root}"
}

# ==========================================
# Main
# ==========================================

main() {
    print_header "TS Toolchain Unit Tests"
    testframework::init
    load "lib/ts/toolchain"

    testframework::section "Loading"
    test_loads

    testframework::section "Runtime detection"
    test_runtime_detection

    testframework::section "Listings"
    test_runtimes_listing

    testframework::section "Lockfile -> package manager"
    test_lockfile_pm

    testframework::section "Project layout"
    test_project_layout
    test_pkg_field_scripts

    testframework::section "tsc resolution"
    test_tsc_bin_resolution

    testframework::section "Validation gates"
    test_validate_gates

    testframework::section "Ports"
    test_port_free

    testframework::section "Doctor"
    test_doctor_summary

    testframework::summary
}

main "$@"
