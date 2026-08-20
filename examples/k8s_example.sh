#!/usr/bin/env bs
# shellcheck shell=bash
# examples/k8s_example.sh — Kubernetes client demo
# Пример использования Kubernetes-клиента BS.

set -euo pipefail

load "core/utils"
load "lib/integration/k8s"

main() {
    local tmp_dir
    tmp_dir="$(mktemp -d)"

    echo "--- kubectl available ---"
    if k8s::is_available; then
        echo "kubectl is installed"
    else
        echo "kubectl is not installed"
    fi

    echo ""
    echo "--- Current context (dry-run) ---"
    export FRAMEWORK_DRY_RUN=true
    k8s::context::current
    unset FRAMEWORK_DRY_RUN

    echo ""
    echo "--- List pods (dry-run) ---"
    export FRAMEWORK_DRY_RUN=true
    k8s::pod::list
    unset FRAMEWORK_DRY_RUN

    echo ""
    echo "--- Restart deployment (dry-run) ---"
    export FRAMEWORK_DRY_RUN=true
    k8s::deployment::restart my-app
    unset FRAMEWORK_DRY_RUN

    echo ""
    echo "--- Scale deployment (dry-run) ---"
    export FRAMEWORK_DRY_RUN=true
    k8s::deployment::scale my-app 3
    unset FRAMEWORK_DRY_RUN

    echo ""
    echo "--- Apply manifest (dry-run) ---"
    local manifest="${tmp_dir}/deployment.yaml"
    printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: demo\n' > "${manifest}"
    export FRAMEWORK_DRY_RUN=true
    k8s::apply "${manifest}"
    unset FRAMEWORK_DRY_RUN

    echo ""
    echo "--- Structured result (kubectl missing, expect error) ---"
    local result_json
    result_json="$(utils::attempt k8s::result get pods)"
    echo "${result_json}"

    rm -rf "${tmp_dir}"
}

main "$@"
