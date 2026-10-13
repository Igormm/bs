#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testauditcoreconfigunit.sh — audit regressions for core/config
# tests/unit/testauditcoreconfigunit.sh — регрессии аудита для core/config
#   Project-local ./.bsrc may come from a foreign repository: it must not be
#   able to export arbitrary environment variables (LD_PRELOAD, BS_UPDATE_REPO).
#   Локальный ./.bsrc может прийти из чужого репозитория: он не должен
#   экспортировать произвольные переменные окружения.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Загрузить ядро в чистом процессе с cwd, где лежит .bsrc; напечатать значения.
# Load the core in a clean process whose cwd holds a .bsrc; print the values.
probe() {
    local -r dir="$1"
    (cd "${dir}" && env -i HOME="${dir}/home" PATH="/usr/bin:/bin" BS_SILENT=1 BS_ROOT="${BS_PROJECT_ROOT}" \
        bash -c 'source "$1/bootstrap/init.sh" >/dev/null 2>&1
                 printf "LD=[%s] REPO=[%s] PROV=[%s] MODEL=[%s]" \
                   "${LD_PRELOAD:-}" "${BS_UPDATE_REPO:-}" "${BS_LLM_PROVIDER:-}" "${BS_LLM_MODEL:-}"' _ "${BS_PROJECT_ROOT}")
}

test_local_file_cannot_export_arbitrary_env() {
    local t out
    t="$(mktemp -d)"
    mkdir -p "${t}/home"
    printf 'LD_PRELOAD=/tmp/evil.so\nBS_UPDATE_REPO=https://evil.example/x\nBS_LLM_PROVIDER=ollama\nBS_LLM_MODEL=m1\n' > "${t}/.bsrc"
    out="$(probe "${t}")"
    testframework::assert_equal "LD=[] REPO=[] PROV=[ollama] MODEL=[m1]" "${out}" \
        "./.bsrc: LD_PRELOAD and BS_UPDATE_REPO ignored, allowed keys still applied"
    rm -rf "${t:?}"
}

test_user_file_is_still_honoured() {
    local t out
    t="$(mktemp -d)"
    mkdir -p "${t}/home/.config/bs"
    printf 'BS_UPDATE_REPO=https://mine.example/x\n' > "${t}/home/.config/bs/config.sh"
    out="$(probe "${t}")"
    testframework::assert_equal "LD=[] REPO=[https://mine.example/x] PROV=[] MODEL=[]" "${out}" \
        "user config (~/.config/bs/config.sh) keeps working"
    rm -rf "${t:?}"
}

main() {
    print_header "Audit: core/config / Аудит: core/config"
    testframework::init
    testframework::section "Project-local .bsrc / Локальный .bsrc"
    test_local_file_cannot_export_arbitrary_env
    test_user_file_is_still_honoured
    testframework::summary
}

main "$@"
