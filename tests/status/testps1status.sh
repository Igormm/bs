#!/usr/bin/env bs
# shellcheck disable=SC2155

# test_ps1_status.sh — Unit tests for PS1 Status module
# Модульные тесты для модуля PS1 статуса
#
# @author BS Framework Test Suite
# @since 2026-01-06
# @version 1.0.0

set -euo pipefail

# Test framework setup
readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

# Source test framework
source "${TEST_SCRIPT_DIR}/../testframework.sh"
source "${BS_PROJECT_ROOT}/boot.sh"

# Initialize BS framework
BS::init

# Test results tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Test counter functions
test_increment() {
    ((TESTS_RUN++))
}

test_pass() {
    test_increment
    ((TESTS_PASSED++))
    log::success "✓ ${FUNCNAME[1]}"
}

test_fail() {
    test_increment
    ((TESTS_FAILED++))
    FAILED_TESTS+=("${FUNCNAME[1]}")
    log::error "✗ ${FUNCNAME[1]}"
}

# Test 1: Module initialization
test_module_initialization() {
    log::info "Testing module initialization..."
    
    # Source the module
    source "${BS_PROJECT_ROOT}/lib/status/ps1status.sh"
    
    # Test initialization
    if ps1status::init; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 2: Directory creation
test_directory_creation() {
    log::info "Testing directory creation..."
    
    if [[ -d "${PS1_STATUS_CONFIG_DIR}" ]] && \
       [[ -d "${PS1_STATUS_CACHE_DIR}" ]]; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 3: Component initialization
test_component_initialization() {
    log::info "Testing component initialization..."
    
    # Test individual component initialization
    if ps1status::wireguard::init && \
       ps1status::network::init && \
       ps1status::speed::init && \
       ps1status::audio::init && \
       ps1status::system::init; then
        test_pass
    else
        test_fail
    fi
}

# Test 4: Component enabling/disabling
test_component_management() {
    log::info "Testing component management..."
    
    # Enable component
    ps1status::enable_component "wireguard"
    
    # Check if enabled
    local enabled_components
    enabled_components=$(ps1status::get_enabled_components)
    
    if [[ " ${enabled_components} " =~ " wireguard " ]]; then
        test_pass
    else
        test_fail
    fi
    
    # Disable component
    ps1status::disable_component "wireguard"
    
    # Check if disabled
    enabled_components=$(ps1status::get_enabled_components)
    
    if [[ ! " ${enabled_components} " =~ " wireguard " ]]; then
        test_pass
    else
        test_fail
    fi
}

# Test 5: WireGuard status (mock)
test_wireguard_status() {
    log::info "Testing WireGuard status..."
    
    # Mock WireGuard status
    echo "up" > "${PS1_STATUS_CACHE_DIR}/wireguard.status"
    
    local status
    status=$(ps1status::wireguard::get_status)
    
    if [[ -n "${status}" ]]; then
        test_pass
    else
        test_fail
    fi
}

# Test 6: Network status (mock)
test_network_status() {
    log::info "Testing network status..."
    
    # Mock network status
    echo "up" > "${PS1_STATUS_CACHE_DIR}/network.status"
    echo "25" > "${PS1_STATUS_CACHE_DIR}/network.latency"
    
    local status
    status=$(ps1status::network::get_status)
    
    if [[ -n "${status}" ]]; then
        test_pass
    else
        test_fail
    fi
}

# Test 7: Speed status (mock)
test_speed_status() {
    log::info "Testing speed status..."
    
    # Mock speed status
    echo "45.5" > "${PS1_STATUS_CACHE_DIR}/speed.download"
    
    local status
    status=$(ps1status::speed::get_status)
    
    if [[ -n "${status}" ]]; then
        test_pass
    else
        test_fail
    fi
}

# Test 8: Audio status (mock)
test_audio_status() {
    log::info "Testing audio status..."
    
    # Mock audio status
    echo "75" > "${PS1_STATUS_CACHE_DIR}/audio.volume"
    echo "false" > "${PS1_STATUS_CACHE_DIR}/audio.muted"
    
    local status
    status=$(ps1status::audio::get_status)
    
    if [[ -n "${status}" ]]; then
        test_pass
    else
        test_fail
    fi
}

# Test 9: System status (mock)
test_system_status() {
    log::info "Testing system status..."
    
    # Mock system status
    echo "45" > "${PS1_STATUS_CACHE_DIR}/system.cpu"
    echo "60" > "${PS1_STATUS_CACHE_DIR}/system.mem"
    echo "0.5" > "${PS1_STATUS_CACHE_DIR}/system.load"
    
    local status
    status=$(ps1status::system::get_status)
    
    if [[ -n "${status}" ]]; then
        test_pass
    else
        test_fail
    fi
}

# Test 10: PS1 construction
test_ps1_construction() {
    log::info "Testing PS1 construction..."
    
    # Enable PS1 status
    ps1status::enable
    
    # Build PS1
    ps1status::build_ps1
    
    if [[ -n "${PS1:-}" ]]; then
        test_pass
    else
        test_fail
    fi
}

# Test 11: Equalizer status
test_equalizer_status() {
    log::info "Testing equalizer status..."
    
    local status
    status=$(ps1status::equalizer::get_status)
    
    if [[ -n "${status}" ]]; then
        test_pass
    else
        test_fail
    fi
}

# Test 12: Equalizer availability
test_equalizer_availability() {
    log::info "Testing equalizer availability check..."
    
    # Test availability function (should return 0 or 1)
    ps1status::equalizer::is_available
    local result=$?
    
    if [[ "${result}" =~ ^[01]$ ]]; then
        test_pass
    else
        test_fail
    fi
}

# Test 13: Module info
test_module_info() {
    log::info "Testing module info..."
    
    local info
    info=$(ps1status::info)
    
    if [[ -n "${info}" ]] && echo "${info}" | grep -q "PS1 Status Module"; then
        test_pass
    else
        test_fail
    fi
}

# Cleanup function
cleanup() {
    log::info "Cleaning up test artifacts..."
    
    # Clean up test files
    rm -rf "${PS1_STATUS_CONFIG_DIR}" 2>/dev/null || true
    rm -rf "${PS1_STATUS_CACHE_DIR}" 2>/dev/null || true
    
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
    log::info "Starting PS1 Status module tests..."
    
    # Register cleanup on exit
    trap cleanup EXIT
    
    # Run tests
    test_module_initialization
    test_directory_creation
    test_component_initialization
    test_component_management
    test_wireguard_status
    test_network_status
    test_speed_status
    test_audio_status
    test_system_status
    test_ps1_construction
    test_equalizer_status
    test_equalizer_availability
    test_module_info
    
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
