#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testk8sunit.sh — Unit tests for lib/integration/k8s
# tests/unit/testk8sunit.sh — Модульные тесты Kubernetes-клиента BS

set -euo pipefail

# Подключаем тестовый фреймворк / Source test framework
readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Инициализируем BS / Initialize BS
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Подключаем тестируемый модуль / Load module under test
load "lib/integration/k8s"

main() {
    print_header "Kubernetes Client Unit Tests"
    print_header "Модульные тесты Kubernetes-клиента"

    testframework::init

    local tmp_dir
    tmp_dir="$(mktemp -d)"

    # ==========================================
    # availability
    # ==========================================
    testframework::section "availability"

    if utils::has kubectl; then
        testframework::assert_command "source ${BS_PROJECT_ROOT}/lib/integration/k8s.sh; k8s::is_available" "k8s::is_available returns true when kubectl exists"
    else
        testframework::assert_false "source ${BS_PROJECT_ROOT}/lib/integration/k8s.sh; k8s::is_available" "k8s::is_available returns false without kubectl"
    fi

    # ==========================================
    # kubectl args builder
    # ==========================================
    testframework::section "kubectl args builder"

    local args
    args="$(source ${BS_PROJECT_ROOT}/lib/integration/k8s.sh; K8S_NAMESPACE=prod; __k8s::kubectl_args get pods)"
    testframework::assert_command "printf '%s' '${args}' | grep -qx 'get'" "kubectl args contains get"
    testframework::assert_command "printf '%s' '${args}' | grep -qx 'pods'" "kubectl args contains pods"
    testframework::assert_command "printf '%s' '${args}' | grep -qx -- '--namespace'" "kubectl args adds namespace flag"
    testframework::assert_command "printf '%s' '${args}' | grep -qx 'prod'" "kubectl args uses K8S_NAMESPACE"

    # Already has namespace
    args="$(source ${BS_PROJECT_ROOT}/lib/integration/k8s.sh; __k8s::kubectl_args get pods -n kube-system)"
    testframework::assert_false "printf '%s' '${args}' | grep -q '^default$'" "kubectl args does not override explicit namespace"

    # ==========================================
    # arg_present
    # ==========================================
    testframework::section "arg_present"

    testframework::assert_command "source ${BS_PROJECT_ROOT}/lib/integration/k8s.sh; __k8s::arg_present '-n' get pods -n kube-system" "arg_present finds short flag"
    testframework::assert_false "source ${BS_PROJECT_ROOT}/lib/integration/k8s.sh; __k8s::arg_present '-n' get pods" "arg_present does not find missing flag"

    # ==========================================
    # context validation
    # ==========================================
    testframework::section "context validation"

    local rc=0
    k8s::context::use "" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "context::use requires name"

    # ==========================================
    # pod validation
    # ==========================================
    testframework::section "pod validation"

    rc=0
    k8s::pod::logs "" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "pod::logs requires pod name"

    rc=0
    k8s::pod::exec "" "ls" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "pod::exec requires pod and command"

    # ==========================================
    # deployment validation
    # ==========================================
    testframework::section "deployment validation"

    rc=0
    k8s::deployment::restart "" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "deployment::restart requires name"

    rc=0
    k8s::deployment::scale "" 3 >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "deployment::scale requires name and replicas"

    # ==========================================
    # apply validation
    # ==========================================
    testframework::section "apply validation"

    rc=0
    k8s::apply "" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "apply requires target"

    rc=0
    k8s::apply "${tmp_dir}/missing.yaml" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_FILE_NOT_FOUND}" "${rc}" "apply fails on missing manifest"

    # ==========================================
    # get validation
    # ==========================================
    testframework::section "get validation"

    rc=0
    k8s::get "" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" "get requires resource"

    # ==========================================
    # dry-run commands
    # ==========================================
    testframework::section "dry-run commands"

    export FRAMEWORK_DRY_RUN=true

    rc=0
    k8s::pod::list >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "0" "${rc}" "pod::list dry-run returns 0"

    rc=0
    k8s::deployment::restart my-app >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "0" "${rc}" "deployment::restart dry-run returns 0"

    rc=0
    k8s::deployment::scale my-app 3 >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "0" "${rc}" "deployment::scale dry-run returns 0"

    local manifest="${tmp_dir}/deployment.yaml"
    printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: test\n' > "${manifest}"
    rc=0
    k8s::apply "${manifest}" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "0" "${rc}" "apply dry-run returns 0"

    unset FRAMEWORK_DRY_RUN

    # ==========================================
    # missing kubectl
    # ==========================================
    testframework::section "missing kubectl"

    if ! utils::has kubectl; then
        rc=0
        k8s::pod::list >/dev/null 2>&1 || rc=$?
        testframework::assert_equal "${INTEGRATION_ERROR_MISSING_DEPS}" "${rc}" "kubectl returns missing deps error"
    else
        testframework::assert_true "true" "kubectl is installed; skip missing-kubectl test"
    fi

    # ==========================================
    # Cleanup and summary
    # ==========================================
    rm -rf "${tmp_dir}"

    testframework::summary
}

main "$@"
