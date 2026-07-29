#!/usr/bin/env bs
# shellcheck disable=SC2155

# test_wireguard.sh — Unit tests for WireGuard integration module
# Модульные тесты для модуля интеграции WireGuard
#
# Description:
#   Comprehensive test suite for WireGuard module functionality.
#   Комплексный набор тестов для функциональности модуля WireGuard.
#
# Usage:
#   Run as root user (required for WireGuard operations):
#   sudo bash tests/integration/test_wireguard.sh
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

# Initialize BS framework (bootstrap; BS_HOME нужен lib-модулям — pre-existing расхождение BS_ROOT/BS_HOME)
# Initialize BS framework (bootstrap; BS_HOME is needed by lib modules — pre-existing BS_ROOT/BS_HOME mismatch)
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Test configuration
readonly TEST_INTERFACE="wg_test"
readonly TEST_ADDRESS="10.255.255.1/24"
readonly TEST_PORT="51821"

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

# Check if running as root
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log::error "These tests require root privileges. Please run with sudo."
        exit 1
    fi
}

# Test 1: Module initialization
test_module_initialization() {
    log::info "Testing module initialization..."
    
    # Source the module
    source "${BS_PROJECT_ROOT}/lib/integration/wireguard.sh"
    
    # Test initialization
    if wireguard::init; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 2: Directory creation
test_directory_creation() {
    log::info "Testing directory creation..."
    
    local config_dir="/etc/wireguard"
    local key_dir="/etc/wireguard/keys"
    local backup_dir="/var/backups/wireguard"
    
    if [[ -d "${config_dir}" ]] && [[ -d "${key_dir}" ]] && [[ -d "${backup_dir}" ]]; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 3: Key pair generation
test_keypair_generation() {
    log::info "Testing key pair generation..."
    
    local test_interface="test_keys"
    local pubkey
    
    # Generate key pair
    pubkey=$(wireguard::generate_keypair "${test_interface}")
    
    if [[ -n "${pubkey}" ]] && [[ -f "/etc/wireguard/keys/${test_interface}_private.key" ]] && \
       [[ -f "/etc/wireguard/keys/${test_interface}_public.key" ]]; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 4: Interface creation
test_interface_creation() {
    log::info "Testing interface creation..."
    
    # Create test interface
    if wireguard::create_interface "${TEST_INTERFACE}" "${TEST_ADDRESS}" "${TEST_PORT}"; then
        # Check if config file exists
        if [[ -f "/etc/wireguard/${TEST_INTERFACE}.conf" ]]; then
            test_pass
        else
            test_fail
            return 1
        fi
    else
        test_fail
        return 1
    fi
}

# Test 5: Configuration file validation
test_configuration_validation() {
    log::info "Testing configuration file validation..."
    
    local config_file="/etc/wireguard/${TEST_INTERFACE}.conf"
    
    if [[ -f "${config_file}" ]]; then
        # Check for required sections
        if grep -q "\[Interface\]" "${config_file}" && \
           grep -q "Address" "${config_file}" && \
           grep -q "PrivateKey" "${config_file}"; then
            test_pass
        else
            test_fail
            return 1
        fi
    else
        test_fail
        return 1
    fi
}

# Test 6: Peer management
test_peer_management() {
    log::info "Testing peer management..."
    
    local test_peer_key="dGhpcyBpcyBhIHRlc3QgcHVibGljIGtleSBmb3Igd2lyZWd1YXJk"
    local test_allowed_ips="10.255.255.2/32"
    
    # Add peer
    if wireguard::add_peer "${TEST_INTERFACE}" "${test_peer_key}" "${test_allowed_ips}"; then
        # Check if peer was added
        if grep -q "${test_peer_key}" "/etc/wireguard/${TEST_INTERFACE}.conf"; then
            test_pass
        else
            test_fail
            return 1
        fi
    else
        test_fail
        return 1
    fi
}

# Test 7: Interface listing
test_interface_listing() {
    log::info "Testing interface listing..."
    
    local interfaces
    interfaces=$(wireguard::list_interfaces)
    
    if [[ -n "${interfaces}" ]]; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 8: Backup functionality
test_backup_functionality() {
    log::info "Testing backup functionality..."
    
    local backup_file
    backup_file=$(wireguard::backup_config "${TEST_INTERFACE}" "test_backup")
    
    if [[ -n "${backup_file}" ]] && [[ -f "${backup_file}" ]]; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 9: Public IP detection
test_public_ip_detection() {
    log::info "Testing public IP detection..."
    
    local public_ip
    public_ip=$(wireguard::get_public_ip)
    
    # Check if IP is valid format
    if [[ -n "${public_ip}" ]] && [[ "${public_ip}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 10: Client configuration
test_client_configuration() {
    log::info "Testing client configuration..."
    
    local test_client="test_client"
    local test_server_key="dGhpcyBpcyBhIHRlc3Qgc2VydmVyIHB1YmxpYyBrZXk="
    local test_endpoint="192.168.1.1:51820"
    local client_pubkey
    
    # Create client config
    client_pubkey=$(wireguard::create_client_config "${test_client}" "${test_server_key}" "${test_endpoint}")
    
    if [[ -n "${client_pubkey}" ]] && \
       [[ -f "/etc/wireguard/${test_client}_client.conf" ]] && \
       [[ -f "/etc/wireguard/keys/${test_client}_client_private.key" ]]; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 11: Module info
test_module_info() {
    log::info "Testing module info..."
    
    local info_output
    info_output=$(wireguard::info)
    
    if [[ -n "${info_output}" ]] && echo "${info_output}" | grep -q "WireGuard Integration Module"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 12: Error handling
test_error_handling() {
    log::info "Testing error handling..."
    
    local error_caught=0
    
    # Test invalid interface name
    if ! utils::quiet_err wireguard::create_interface "" "10.0.0.1/24"; then
        ((++error_caught))
    fi
    
    # Test invalid peer addition
    if ! utils::quiet_err wireguard::add_peer "nonexistent" "key" ""; then
        ((++error_caught))
    fi
    
    if [[ "${error_caught}" -ge 2 ]]; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 13: Key permissions
test_key_permissions() {
    log::info "Testing key file permissions..."
    
    local private_key_file="/etc/wireguard/keys/${TEST_INTERFACE}_private.key"
    local public_key_file="/etc/wireguard/keys/${TEST_INTERFACE}_public.key"
    
    if [[ -f "${private_key_file}" ]] && [[ -f "${public_key_file}" ]]; then
        local private_perms
        private_perms=$(utils::quiet_err stat -c %a "${private_key_file}" || utils::quiet_err stat -f %A "${private_key_file}")
        
        local public_perms
        public_perms=$(utils::quiet_err stat -c %a "${public_key_file}" || utils::quiet_err stat -f %A "${public_key_file}")
        
        # Private key should be 600, public key should be 644
        if [[ "${private_perms}" == "600" ]] && [[ "${public_perms}" == "644" ]]; then
            test_pass
        else
            test_fail
            return 1
        fi
    else
        test_fail
        return 1
    fi
}

# Test 14: Configuration permissions
test_configuration_permissions() {
    log::info "Testing configuration file permissions..."
    
    local config_file="/etc/wireguard/${TEST_INTERFACE}.conf"
    
    if [[ -f "${config_file}" ]]; then
        local perms
        perms=$(utils::quiet_err stat -c %a "${config_file}" || utils::quiet_err stat -f %A "${config_file}")
        
        # Configuration should be 600
        if [[ "${perms}" == "600" ]]; then
            test_pass
        else
            test_fail
            return 1
        fi
    else
        test_fail
        return 1
    fi
}

# Cleanup function
cleanup() {
    log::info "Cleaning up test artifacts..."
    
    # Stop test interface if running
    if utils::quiet wg show "${TEST_INTERFACE}"; then
        utils::ignore wg-quick down "${TEST_INTERFACE}"
    fi
    
    # Remove test configuration files
    rm -f "/etc/wireguard/${TEST_INTERFACE}.conf"
    rm -f "/etc/wireguard/keys/${TEST_INTERFACE}_"*.key
    rm -f "/etc/wireguard/test_keys_"*.key
    rm -f "/etc/wireguard/test_client_"*.conf
    rm -f "/etc/wireguard/keys/test_client_"*.key
    
    # Remove test backups
    rm -f "/var/backups/wireguard/${TEST_INTERFACE}_"*.conf
    rm -f "/var/backups/wireguard/${TEST_INTERFACE}_"*.key
    
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
    log::info "Starting WireGuard module tests..."
    log::info "Note: These tests require root privileges and may create network interfaces"
    
    # Check root privileges
    check_root
    
    # Register cleanup on exit
    trap cleanup EXIT
    
    # Run tests (|| true: падение одного теста не прерывает прогон / a failing test does not abort the run)
    test_module_initialization || true
    test_directory_creation || true
    test_keypair_generation || true
    test_interface_creation || true
    test_configuration_validation || true
    test_peer_management || true
    test_interface_listing || true
    test_backup_functionality || true
    test_public_ip_detection || true
    test_client_configuration || true
    test_module_info || true
    test_error_handling || true
    test_key_permissions || true
    test_configuration_permissions || true
    
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
