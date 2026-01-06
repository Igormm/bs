#!/usr/bin/env bs
# shellcheck disable=SC2155

# test_vk_api.sh — Unit tests for VK API integration module
# Модульные тесты для модуля интеграции VK API
#
# Description:
#   Comprehensive test suite for VK API module functionality.
#   Комплексный набор тестов для функциональности модуля VK API.
#
# Note:
#   These tests require a valid VK API access token.
#   Эти тесты требуют действительный токен доступа VK API.
#
# Usage:
#   VK_TOKEN="your_token_here" bash tests/integration/test_vk_api.sh
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

# Test configuration
readonly TEST_APP_ID="1234567"
readonly TEST_APP_SECRET="test_secret_key"
readonly TEST_ACCESS_TOKEN="${VK_TOKEN:-test_token}"

# Test results tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Mock curl for testing without real API calls
setup_mock_curl() {
    curl() {
        local args=("$@")
        local url=""
        local data=""
        
        # Extract URL and data from arguments
        for i in "${!args[@]}"; do
            if [[ "${args[$i]}" == "https://api.vk.com/method"* ]]; then
                url="${args[$i]}"
            elif [[ "${args[$i]}" == "-d" ]]; then
                data="${args[$((i+1))]}"
            fi
        done
        
        # Mock responses based on method
        if [[ "${url}" == *"users.get"* ]]; then
            echo '{"response":[{"id":1,"first_name":"Павел","last_name":"Дуров","online":1}]}'
        elif [[ "${url}" == *"account.getInfo"* ]]; then
            echo '{"response":{"user_id":1,"name":"Test User"}}'
        elif [[ "${url}" == *"friends.get"* ]]; then
            echo '{"response":{"count":5,"items":[1,2,3,4,5]}}'
        elif [[ "${url}" == *"groups.get"* ]]; then
            echo '{"response":{"count":2,"items":[1,2]}}'
        elif [[ "${url}" == *"wall.get"* ]]; then
            echo '{"response":{"count":1,"items":[{"id":1,"text":"Test post"}]}}'
        elif [[ "${url}" == *"messages.getConversations"* ]]; then
            echo '{"response":{"count":1,"items":[{"conversation":{"peer":{"id":1,"type":"user"}}}]}}'
        elif [[ "${url}" == *"status.get"* ]]; then
            echo '{"response":{"text":"Test status"}}'
        elif [[ "${url}" == *"database.getCountries"* ]]; then
            echo '{"response":[{"id":1,"title":"Russia"}]}'
        else
            echo '{"response":[]}'
        fi
    }
    
    export -f curl
}

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
    source "${BS_PROJECT_ROOT}/lib/integration/vkapi.sh"
    
    # Test initialization
    if vkapi::init "${TEST_APP_ID}" "${TEST_APP_SECRET}"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 2: Directory creation
test_directory_creation() {
    log::info "Testing cache directory creation..."
    
    if [[ -d "/tmp/vk_api_cache" ]]; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 3: Authentication
test_authentication() {
    log::info "Testing authentication..."
    
    # Test auth function
    if vkapi::auth "${TEST_ACCESS_TOKEN}"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 4: Cache key generation
test_cache_key_generation() {
    log::info "Testing cache key generation..."
    
    local cache_key
    cache_key=$(vkapi::get_cache_key "users.get" "user_ids=1")
    
    if [[ -n "${cache_key}" ]] && [[ "${#cache_key}" -eq 64 ]]; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 5: Cache operations
test_cache_operations() {
    log::info "Testing cache operations..."
    
    local test_key="test_key_$(date +%s)"
    local test_data='{"test":"data"}'
    
    # Save to cache
    vkapi::cache_response "${test_key}" "${test_data}"
    
    # Retrieve from cache
    local cached_data
    cached_data=$(vkapi::get_cached_response "${test_key}")
    
    if [[ "${cached_data}" == "${test_data}" ]]; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 6: Rate limiting
test_rate_limiting() {
    log::info "Testing rate limiting..."
    
    local start_time
    start_time=$(date +%s.%N)
    
    # Call rate limit function
    vkapi::rate_limit_delay
    
    local end_time
    end_time=$(date +%s.%N)
    
    local duration
    duration=$(echo "${end_time} - ${start_time}" | bc -l 2>/dev/null || echo "1")
    
    # Should be very fast on first call (no delay)
    if (( $(echo "${duration} < 0.1" | bc -l 2>/dev/null || echo "1") )); then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 7: Response parsing
test_response_parsing() {
    log::info "Testing response parsing..."
    
    local test_response='{"response":{"test":"data"}}'
    local parsed
    parsed=$(vkapi::parse_response "${test_response}")
    
    if [[ "${parsed}" == '{"test":"data"}' ]]; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 8: Error handling
test_error_handling() {
    log::info "Testing error handling..."
    
    local error_response='{"error":{"error_code":5,"error_msg":"User authorization failed"}}'
    
    # Should throw error
    if ! vkapi::parse_response "${error_response}" 2>/dev/null; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 9: Users method
test_users_method() {
    log::info "Testing users.get method..."
    
    # Setup mock curl
    setup_mock_curl
    
    # Set auth token
    vkapi::auth "${TEST_ACCESS_TOKEN}"
    
    local result
    result=$(vkapi::users.get "user_ids=1")
    
    if [[ -n "${result}" ]] && echo "${result}" | grep -q "Павел"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 10: Account method
test_account_method() {
    log::info "Testing account.getInfo method..."
    
    # Setup mock curl
    setup_mock_curl
    
    local result
    result=$(vkapi::account.getInfo)
    
    if [[ -n "${result}" ]] && echo "${result}" | grep -q "user_id"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 11: Friends method
test_friends_method() {
    log::info "Testing friends.get method..."
    
    # Setup mock curl
    setup_mock_curl
    
    local result
    result=$(vkapi::friends.get)
    
    if [[ -n "${result}" ]] && echo "${result}" | grep -q "count"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 12: Groups method
test_groups_method() {
    log::info "Testing groups.get method..."
    
    # Setup mock curl
    setup_mock_curl
    
    local result
    result=$(vkapi::groups.get)
    
    if [[ -n "${result}" ]] && echo "${result}" | grep -q "count"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 13: Wall method
test_wall_method() {
    log::info "Testing wall.get method..."
    
    # Setup mock curl
    setup_mock_curl
    
    local result
    result=$(vkapi::wall.get)
    
    if [[ -n "${result}" ]] && echo "${result}" | grep -q "items"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 14: Messages method
test_messages_method() {
    log::info "Testing messages.getConversations method..."
    
    # Setup mock curl
    setup_mock_curl
    
    local result
    result=$(vkapi::messages.getConversations)
    
    if [[ -n "${result}" ]] && echo "${result}" | grep -q "conversation"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 15: Status method
test_status_method() {
    log::info "Testing status.get method..."
    
    # Setup mock curl
    setup_mock_curl
    
    local result
    result=$(vkapi::status.get)
    
    if [[ -n "${result}" ]] && echo "${result}" | grep -q "text"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 16: Database method
test_database_method() {
    log::info "Testing database.getCountries method..."
    
    # Setup mock curl
    setup_mock_curl
    
    local result
    result=$(vkapi::database.getCountries)
    
    if [[ -n "${result}" ]] && echo "${result}" | grep -q "title"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 17: Utility functions
test_utility_functions() {
    log::info "Testing utility functions..."
    
    # Setup mock curl
    setup_mock_curl
    
    local result1
    result1=$(vkapi::get_my_profile)
    
    local result2
    result2=$(vkapi::get_user_profile "1")
    
    if [[ -n "${result1}" ]] && [[ -n "${result2}" ]]; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 18: Clear cache
test_clear_cache() {
    log::info "Testing cache clearing..."
    
    # Create test cache file
    local test_cache_file="/tmp/vk_api_cache/test_cache.json"
    echo '{"test":"data"}' > "${test_cache_file}"
    
    # Clear cache
    vkapi::clear_cache
    
    if [[ ! -f "${test_cache_file}" ]]; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 19: Statistics
test_statistics() {
    log::info "Testing statistics..."
    
    local stats
    stats=$(vkapi::get_stats)
    
    if [[ -n "${stats}" ]] && echo "${stats}" | grep -q "VK API Statistics"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 20: Module info
test_module_info() {
    log::info "Testing module info..."
    
    local info_output
    info_output=$(vkapi::info)
    
    if [[ -n "${info_output}" ]] && echo "${info_output}" | grep -q "VK API Integration Module"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Cleanup function
cleanup() {
    log::info "Cleaning up test artifacts..."
    
    # Clean up test files
    rm -f "/etc/wireguard/test_keys_"*.key 2>/dev/null || true
    rm -f "/etc/wireguard/test_client_"*.conf 2>/dev/null || true
    rm -f "/etc/wireguard/keys/test_"*.key 2>/dev/null || true
    
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
    log::info "Starting VK API module tests..."
    
    # Register cleanup on exit
    trap cleanup EXIT
    
    # Run tests
    test_module_initialization
    test_directory_creation
    test_authentication
    test_cache_key_generation
    test_cache_operations
    test_rate_limiting
    test_response_parsing
    test_error_handling
    test_users_method
    test_account_method
    test_friends_method
    test_groups_method
    test_wall_method
    test_messages_method
    test_status_method
    test_database_method
    test_utility_functions
    test_clear_cache
    test_statistics
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
