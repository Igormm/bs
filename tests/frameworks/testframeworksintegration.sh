#!/usr/bin/env bs
# shellcheck shell=bash
# shellcheck disable=SC2155

# test_frameworks_integration.sh — Unit tests for Frameworks Integration module
# Модульные тесты для модуля интеграции фреймворков
#
# Description:
#   Comprehensive test suite for Frameworks Integration module functionality.
#   Комплексный набор тестов для функциональности модуля интеграции фреймворков.
#
# @author BS Framework Test Suite
# @since 2026-01-06
# @version 1.0.0

set -euo pipefail

# command -v видит alias'ы только с expand_aliases (плагины bash-it задают alias'ы)
# command -v only sees aliases with expand_aliases (bash-it plugins define aliases)
shopt -s expand_aliases

# Test framework setup
readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

# Source test framework
source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Initialize BS framework (bootstrap; BS_HOME нужен lib-модулям — pre-existing расхождение BS_ROOT/BS_HOME)
# Initialize BS framework (bootstrap; BS_HOME is needed by lib modules — pre-existing BS_ROOT/BS_HOME mismatch)
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Изолированный HOME: модуль создаёт ~/.config/bs_frameworks (readonly-путь вычисляется из HOME при source)
# Isolated HOME: the module creates ~/.config/bs_frameworks (readonly path computed from HOME at source time)
TEST_HOME="$(mktemp -d)"
export HOME="${TEST_HOME}"

# Test results tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Test counter functions
test_increment() {
    ((++TESTS_RUN))
}

test_pass() {
    test_increment
    ((++TESTS_PASSED))
    log::success "✓ ${FUNCNAME[1]}"
}

test_fail() {
    test_increment
    ((++TESTS_FAILED))
    FAILED_TESTS+=("${FUNCNAME[1]}")
    log::error "✗ ${FUNCNAME[1]}"
}

# Test 1: Module initialization
test_module_initialization() {
    log::info "Testing module initialization..."
    
    # Source the module
    source "${BS_PROJECT_ROOT}/lib/frameworks/frameworksintegration.sh"
    
    # Test initialization
    if frameworks::init; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 2: Directory creation
test_directory_creation() {
    log::info "Testing directory creation..."
    
    if [[ -d "${FRAMEWORKS_CONFIG_DIR}" ]] && \
       [[ -d "${FRAMEWORKS_PLUGIN_DIR}" ]] && \
       [[ -d "${FRAMEWORKS_CACHE_DIR}" ]]; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 3: Bash-it integration initialization
test_bashit_init() {
    log::info "Testing Bash-it integration initialization..."
    
    if frameworks::bashit::init; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 4: Bash-it plugin loading
test_bashit_plugin_loading() {
    log::info "Testing Bash-it plugin loading..."
    
    # Test loading base plugin
    if frameworks::bashit::load_plugin "base"; then
        # Check if plugin was added to loaded plugins
        if [[ " ${FRAMEWORKS_BASHIT_PLUGINS[*]} " =~ " base " ]]; then
            test_pass
        else
            test_fail
        fi
    else
        test_fail
    fi
}

# Test 5: Bash-it base plugin
test_bashit_base_plugin() {
    log::info "Testing Bash-it base plugin..."
    
    # Load base plugin
    frameworks::bashit::load_plugin "base"
    
    # Test aliases
    if utils::has .. && \
       utils::has ll && \
       utils::has psg; then
        test_pass
    else
        test_fail
    fi
}

# Test 6: Bash-it git plugin
test_bashit_git_plugin() {
    log::info "Testing Bash-it git plugin..."
    
    # Load git plugin
    frameworks::bashit::load_plugin "git"
    
    # Test git aliases
    if utils::has g && \
       utils::has gs && \
       utils::has ga; then
        test_pass
    else
        test_fail
    fi
}

# Test 7: Bash-it history plugin
test_bashit_history_plugin() {
    log::info "Testing Bash-it history plugin..."
    
    # Load history plugin
    frameworks::bashit::load_plugin "history"
    
    # Test history settings
    if [[ "${HISTCONTROL}" == "ignoredups" ]] && \
       [[ "${HISTSIZE}" == "10000" ]]; then
        test_pass
    else
        test_fail
    fi
}

# Test 8: Bash-it extract function
test_bashit_extract_function() {
    log::info "Testing Bash-it extract function..."
    
    # Load alias plugin which includes extract
    frameworks::bashit::load_plugin "alias"
    
    # Test extract function
    if utils::has extract; then
        test_pass
    else
        test_fail
    fi
}

# Test 9: Bashinator integration initialization
test_bashinator_init() {
    log::info "Testing Bashinator integration initialization..."
    
    if frameworks::bashinator::init; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 10: Bashinator log message
test_bashinator_log_message() {
    log::info "Testing Bashinator log message..."
    
    # Test different log levels
    if frameworks::bashinator::log_message "DEBUG" "Test debug message" && \
       frameworks::bashinator::log_message "INFO" "Test info message" && \
       frameworks::bashinator::log_message "WARNING" "Test warning message" && \
       frameworks::bashinator::log_message "ERROR" "Test error message"; then
        test_pass
    else
        test_fail
    fi
}

# Test 11: Bashly integration initialization
test_bashly_init() {
    log::info "Testing Bashly integration initialization..."
    
    if frameworks::bashly::init; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 12: Bashly argument parsing
test_bashly_argument_parsing() {
    log::info "Testing Bashly argument parsing..."
    
    # Test parsing
    local result
    result=$(frameworks::bashly::parse_args --debug --verbose arg1 arg2)
    
    if [[ -n "${result}" ]] && echo "${result}" | grep -q "args: arg1 arg2"; then
        test_pass
    else
        test_fail
    fi
}

# Test 13: Bashly help generation
test_bashly_help_generation() {
    log::info "Testing Bashly help generation..."
    
    local help_text
    help_text=$(frameworks::bashly::generate_help "test-command" "Test description")
    
    if [[ -n "${help_text}" ]] && echo "${help_text}" | grep -q "Usage: test-command"; then
        test_pass
    else
        test_fail
    fi
}

# Test 14: ShellSpec integration initialization
test_shellspec_init() {
    log::info "Testing ShellSpec integration initialization..."
    
    if frameworks::shellspec::init; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 15: ShellSpec describe
test_shellspec_describe() {
    log::info "Testing ShellSpec describe..."
    
    if frameworks::shellspec::describe "Test Suite" "echo 'test'"; then
        test_pass
    else
        test_fail
    fi
}

# Test 16: ShellSpec it
test_shellspec_it() {
    log::info "Testing ShellSpec it..."
    
    if frameworks::shellspec::it "Test case" "true"; then
        test_pass
    else
        test_fail
    fi
}

# Test 17: ShellSpec matchers
test_shellspec_matchers() {
    log::info "Testing ShellSpec matchers..."
    
    # Test equal matcher
    if frameworks::shellspec::matchers::equal "test" "test" && \
       ! frameworks::shellspec::matchers::equal "test" "different"; then
        test_pass
    else
        test_fail
    fi
}

# Test 18: ShellSpec contain matcher
test_shellspec_contain_matcher() {
    log::info "Testing ShellSpec contain matcher..."
    
    if frameworks::shellspec::matchers::contain "test string" "string" && \
       ! frameworks::shellspec::matchers::contain "test string" "missing"; then
        test_pass
    else
        test_fail
    fi
}

# Test 19: ShellSpec be_empty matcher
test_shellspec_be_empty_matcher() {
    log::info "Testing ShellSpec be_empty matcher..."
    
    if frameworks::shellspec::matchers::be_empty "" && \
       ! frameworks::shellspec::matchers::be_empty "not empty"; then
        test_pass
    else
        test_fail
    fi
}

# Test 20: ShellSpec exist matcher
test_shellspec_exist_matcher() {
    log::info "Testing ShellSpec exist matcher..."
    
    if frameworks::shellspec::matchers::exist "/tmp" && \
       ! frameworks::shellspec::matchers::exist "/nonexistent/path"; then
        test_pass
    else
        test_fail
    fi
}

# Test 21: mbfl integration initialization
test_mbfl_init() {
    log::info "Testing mbfl integration initialization..."
    
    if frameworks::mbfl::init; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 22: mbfl function definition
test_mbfl_function_definition() {
    log::info "Testing mbfl function definition..."
    
    frameworks::mbfl::define_function "test_func" "echo 'test output'"
    
    if utils::has mbfl_test_func && \
       [[ "$(mbfl_test_func)" == "test output" ]]; then
        test_pass
    else
        test_fail
    fi
}

# Test 23: mbfl variable setting
test_mbfl_variable_setting() {
    log::info "Testing mbfl variable setting..."
    
    frameworks::mbfl::set_var "test_var" "test_value"
    
    if [[ "${mbfl_test_var}" == "test_value" ]]; then
        test_pass
    else
        test_fail
    fi
}

# Test 24: mbfl string functions
test_mbfl_string_functions() {
    log::info "Testing mbfl string functions..."
    
    if frameworks::mbfl::string::is_empty "" && \
       ! frameworks::mbfl::string::is_empty "test" && \
       [[ "$(frameworks::mbfl::string::length "test")" == "4" ]] && \
       [[ "$(frameworks::mbfl::string::substring "test" 1 2)" == "es" ]]; then
        test_pass
    else
        test_fail
    fi
}

# Test 25: mbfl array functions
test_mbfl_array_functions() {
    log::info "Testing mbfl array functions..."
    
    local test_array=("item1" "item2" "item3")
    
    if [[ "$(frameworks::mbfl::array::length "${test_array[@]}")" == "3" ]] && \
       frameworks::mbfl::array::contains "item2" "${test_array[@]}" && \
       ! frameworks::mbfl::array::contains "item4" "${test_array[@]}"; then
        test_pass
    else
        test_fail
    fi
}

# Test 26: mbfl file functions
test_mbfl_file_functions() {
    log::info "Testing mbfl file functions..."
    
    # Create test file
    local test_file
    test_file=$(mktemp)
    echo "test" > "${test_file}"
    
    if frameworks::mbfl::file::exists "${test_file}" && \
       frameworks::mbfl::file::is_readable "${test_file}" && \
       frameworks::mbfl::file::is_writable "${test_file}"; then
        test_pass
    else
        test_fail
    fi
    
    rm -f "${test_file}"
}

# Test 27: mbfl directory functions
test_mbfl_directory_functions() {
    log::info "Testing mbfl directory functions..."
    
    local test_dir
    test_dir=$(mktemp -d)
    
    if frameworks::mbfl::dir::exists "${test_dir}"; then
        test_pass
    else
        test_fail
    fi
    
    rm -rf "${test_dir}"
}

# Test 28: frameworks status
test_frameworks_status() {
    log::info "Testing frameworks status..."
    
    local status
    status=$(frameworks::status)
    
    if [[ -n "${status}" ]] && echo "${status}" | grep -q "Frameworks Integration Status"; then
        test_pass
    else
        test_fail
    fi
}

# Test 29: frameworks clear
test_frameworks_clear() {
    log::info "Testing frameworks clear..."
    
    # Add some test data
    FRAMEWORKS_BASHIT_PLUGINS=("test")
    frameworks::clear
    
    if [[ ${#FRAMEWORKS_BASHIT_PLUGINS[@]} -eq 0 ]]; then
        test_pass
    else
        test_fail
    fi
}

# Test 30: frameworks info
test_frameworks_info() {
    log::info "Testing frameworks info..."
    
    local info
    info=$(frameworks::info)
    
    if [[ -n "${info}" ]] && echo "${info}" | grep -q "Frameworks Integration Module"; then
        test_pass
    else
        test_fail
    fi
}

# Cleanup function
cleanup() {
    log::info "Cleaning up test artifacts..."
    
    # Clean up test files (изолированный HOME / isolated HOME)
    utils::quiet_err rm -rf "${TEST_HOME:-}" || true
    utils::quiet_err rm -rf "${FRAMEWORKS_CACHE_DIR:-}" || true
    
    log::debug "Cleanup completed"
}

# Print test summary
print_summary() {
    log::info "=== Test Summary ==="
    log::info "Tests run: ${TESTS_RUN}"
    log::info "Tests passed: ${TESTS_PASSED}"
    log::info "Tests failed: ${TESTS_FAILED}"
    
    if [[ "${TESTS_FAILED}" -gt 0 ]]; then
        log::error "Failed tests:"
        for test in "${FAILED_TESTS[@]}"; do
            log::error "  - ${test}"
        done
        return 1
    else
        log::success "All tests passed!"
        return 0
    fi
}

# Main test runner
main() {
    log::info "Starting Frameworks Integration module tests..."
    
    # Register cleanup on exit
    trap cleanup EXIT
    
    # Run tests (|| true: падение одного теста не прерывает прогон / a failing test does not abort the run)
    test_module_initialization || true
    test_directory_creation || true
    test_bashit_init || true
    test_bashit_plugin_loading || true
    test_bashit_base_plugin || true
    test_bashit_git_plugin || true
    test_bashit_history_plugin || true
    test_bashit_extract_function || true
    test_bashinator_init || true
    test_bashinator_log_message || true
    test_bashly_init || true
    test_bashly_argument_parsing || true
    test_bashly_help_generation || true
    test_shellspec_init || true
    test_shellspec_describe || true
    test_shellspec_it || true
    test_shellspec_matchers || true
    test_shellspec_contain_matcher || true
    test_shellspec_be_empty_matcher || true
    test_shellspec_exist_matcher || true
    test_mbfl_init || true
    test_mbfl_function_definition || true
    test_mbfl_variable_setting || true
    test_mbfl_string_functions || true
    test_mbfl_array_functions || true
    test_mbfl_file_functions || true
    test_mbfl_directory_functions || true
    test_frameworks_status || true
    test_frameworks_clear || true
    test_frameworks_info || true
    
    # Print summary
    print_summary
    
    # Exit with appropriate code
    if [[ "${TESTS_FAILED}" -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
