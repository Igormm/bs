#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testconfigunit.sh — Unit tests for core/config module
# tests/unit/testconfigunit.sh — Модульные тесты для модуля core/config

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Isolate HOME before loading the framework so config module picks up the temp dir.
readonly TEST_HOME="$(mktemp -d)"
export HOME="${TEST_HOME}"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

cleanup() {
    rm -rf "${TEST_HOME}"
}
trap cleanup EXIT

# Helper: unset variables that could override built-in defaults.
__test_config_unset_overrides() {
    unset BS_LOG_LEVEL BS_SILENT BS_FRAMEWORK_DRY_RUN BS_FRAMEWORK_DEBUG \
        BS_RESULT_FILE BS_FILES_ATOMIC BS_FILES_BACKUP_SUFFIX \
        BS_FILES_ATOMIC_FALLBACK BS_LLM_PROVIDER BS_LLM_MODEL \
        BS_LLM_BASE_URL BS_LLM_API_KEY 2>/dev/null || true
}

# Test config::load applies built-in defaults when no files or env vars are present.
test_config_load_defaults() {
    local work_dir result
    work_dir="$(mktemp -d)"

    result="$(
        cd "${work_dir}"
        __test_config_unset_overrides
        config::load >/dev/null 2>&1
        config::get BS_LOG_LEVEL
    )"
    testframework::assert_equal "info" "${result}" "BS_LOG_LEVEL default is info"

    result="$(
        cd "${work_dir}"
        __test_config_unset_overrides
        config::load >/dev/null 2>&1
        config::get BS_SILENT
    )"
    testframework::assert_equal "0" "${result}" "BS_SILENT default is 0"

    result="$(
        cd "${work_dir}"
        __test_config_unset_overrides
        config::load >/dev/null 2>&1
        config::get BS_FRAMEWORK_DRY_RUN
    )"
    testframework::assert_equal "false" "${result}" "BS_FRAMEWORK_DRY_RUN default is false"

    rm -rf "${work_dir}"
}

# Test config::get returns a value that was explicitly set.
test_config_get_set_value() {
    config::set "TEST_CONFIG_KEY" "expected_value"
    testframework::assert_equal "expected_value" "$(config::get TEST_CONFIG_KEY)" \
        "config::get returns a set value"
}

# Test config::get returns the provided default for missing keys.
test_config_get_default() {
    testframework::assert_equal "fallback_default" \
        "$(config::get NO_SUCH_CONFIG_KEY "fallback_default")" \
        "config::get returns provided default for missing key"
}

# Test config::get returns E_INVALID when key is missing and no default is given.
test_config_get_missing_no_default() {
    local rc=0
    config::get "ABSENT_CONFIG_KEY" || rc=$?
    testframework::assert_equal "${E_INVALID}" "${rc}" \
        "config::get without default returns E_INVALID for missing key"
}

# Test config::set updates the map and exports the value to the environment.
test_config_set() {
    config::set "RUNTIME_CONFIG_KEY" "runtime_value"
    testframework::assert_equal "runtime_value" "$(config::get RUNTIME_CONFIG_KEY)" \
        "config::set updates configuration map"
    testframework::assert_equal "runtime_value" "${RUNTIME_CONFIG_KEY}" \
        "config::set exports value to environment"
}

# Test config::load reads a local .bsrc file and overrides defaults.
test_config_load_local_bsrc() {
    local work_dir result
    work_dir="$(mktemp -d)"
    printf 'BS_LOG_LEVEL=debug\n' > "${work_dir}/.bsrc"

    result="$(
        cd "${work_dir}"
        __test_config_unset_overrides
        config::load >/dev/null 2>&1
        config::get BS_LOG_LEVEL
    )"
    testframework::assert_equal "debug" "${result}" \
        "config::load reads local .bsrc and overrides defaults"

    rm -rf "${work_dir}"
}

# Test environment variables override both user config and local .bsrc values.
test_config_env_overrides_file() {
    local work_dir result
    work_dir="$(mktemp -d)"

    mkdir -p "${TEST_HOME}/.config/bs"
    printf 'BS_LOG_LEVEL=error\n' > "${TEST_HOME}/.config/bs/config.sh"
    printf 'BS_LOG_LEVEL=warning\n' > "${work_dir}/.bsrc"

    result="$(
        cd "${work_dir}"
        BS_LOG_LEVEL=debug config::load >/dev/null 2>&1
        config::get BS_LOG_LEVEL
    )"
    testframework::assert_equal "debug" "${result}" \
        "config::load uses environment variables over file values"

    rm -rf "${work_dir}"
    rm -f "${TEST_HOME}/.config/bs/config.sh"
}

# Test config::list outputs key=value pairs.
test_config_list() {
    config::load >/dev/null 2>&1
    config::set "Z_LIST_KEY" "z_value"
    config::set "A_LIST_KEY" "a_value"

    local output
    output="$(config::list)"

    testframework::assert_true "'${output}' =~ A_LIST_KEY=a_value" \
        "config::list contains A_LIST_KEY=a_value"
    testframework::assert_true "'${output}' =~ Z_LIST_KEY=z_value" \
        "config::list contains Z_LIST_KEY=z_value"
    testframework::assert_true "'${output}' =~ BS_LOG_LEVEL=" \
        "config::list contains built-in BS_LOG_LEVEL key"
}

# Test config::user_file and config::local_file return expected paths.
test_config_paths() {
    testframework::assert_equal "${TEST_HOME}/.config/bs/config.sh" "$(config::user_file)" \
        "config::user_file returns user config path"
    testframework::assert_equal ".bsrc" "$(config::local_file)" \
        "config::local_file returns local config file name"
}

main() {
    print_header "Core Config Unit Tests / Модульные тесты core/config"

    testframework::init

    testframework::section "config::load defaults / Значения по умолчанию"
    test_config_load_defaults

    testframework::section "config::get / Чтение значений"
    test_config_get_set_value
    test_config_get_default
    test_config_get_missing_no_default

    testframework::section "config::set / Запись значений"
    test_config_set

    testframework::section "config::load files and env / Файлы и переменные окружения"
    test_config_load_local_bsrc
    test_config_env_overrides_file

    testframework::section "config::list and paths / Список и пути"
    test_config_list
    test_config_paths

    testframework::summary
}

main "$@"
