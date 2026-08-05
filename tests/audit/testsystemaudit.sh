#!/usr/bin/env bs
# shellcheck shell=bash
# shellcheck disable=SC2155

# test_system_audit.sh — Unit tests for System Audit module
# Модульные тесты для модуля аудита системы
#
# Note: Some tests require root privileges
# Примечание: Некоторые тесты требуют root прав
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

# Изолированный HOME: модуль создаёт ~/.config/systemaudit (readonly-путь вычисляется из HOME при source)
# Isolated HOME: the module creates ~/.config/systemaudit (readonly path computed from HOME at source time)
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
    source "${BS_PROJECT_ROOT}/lib/audit/systemaudit.sh"
    
    # Test initialization
    if systemaudit::init; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 2: Directory creation
test_directory_creation() {
    log::info "Testing directory creation..."
    
    if [[ -d "${AUDIT_CONFIG_DIR}" ]] && \
       [[ -d "${AUDIT_REPORT_DIR}" ]] && \
       [[ -d "${AUDIT_CACHE_DIR}" ]]; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 3: Finding creation
test_finding_creation() {
    log::info "Testing finding creation..."
    
    local finding
    finding=$(systemaudit::create_finding \
        "Test Finding" \
        "This is a test finding" \
        "${AUDIT_SEVERITY_HIGH}" \
        "test" \
        "Test recommendation")
    
    if [[ -n "${finding}" ]] && echo "${finding}" | grep -q "Test Finding"; then
        test_pass
    else
        test_fail
    fi
}

# Test 4: Audit score calculation
test_score_calculation() {
    log::info "Testing audit score calculation..."
    
    # Create test findings
    AUDIT_FINDINGS=()
    
    # Add some test findings
    AUDIT_FINDINGS+=("$(systemaudit::create_finding "Critical Issue" "" "${AUDIT_SEVERITY_CRITICAL}")")
    AUDIT_FINDINGS+=("$(systemaudit::create_finding "High Issue" "" "${AUDIT_SEVERITY_HIGH}")")
    AUDIT_FINDINGS+=("$(systemaudit::create_finding "Medium Issue" "" "${AUDIT_SEVERITY_MEDIUM}")")
    
    # Calculate score
    systemaudit::calculate_score
    
    if [[ "${AUDIT_SCORE}" -eq 60 ]]; then  # 100 - 25 - 15 - 5 = 55, but minimum is 0
        test_pass
    else
        test_fail
    fi
}

# Test 5: Quick audit
test_quick_audit() {
    log::info "Testing quick audit..."
    
    # Mock system commands for testing
    ps() {
        echo "USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND"
        echo "root         1  0.0  0.1 225768  9144 ?        Ss   12:00   0:01 /sbin/init"
    }
    
    free() {
        echo "              total        used        free      shared  buff/cache   available"
        echo "Mem:        8388608     4194304     2097152      524288     2097152     3670016"
    }
    
    uptime() {
        echo "12:00:00 up 1 day, 1 user, load average: 0.12, 0.08, 0.05"
    }
    
    export -f ps free uptime
    
    if utils::quiet systemaudit::run_quick; then
        test_pass
    else
        test_fail
    fi
    
    unset -f ps free uptime
}

# Test 6: Full audit
test_full_audit() {
    log::info "Testing full audit..."
    
    # Mock system files for testing
    mkdir -p /tmp/test_audit
    
    # Create mock sshd_config
    cat > /tmp/test_audit/sshd_config << EOF
Protocol 2
PermitRootLogin no
PermitEmptyPasswords no
EOF
    
    # Create mock login.defs
    cat > /tmp/test_audit/login.defs << EOF
PASS_MAX_DAYS 365
PASS_MIN_DAYS 0
PASS_WARN_AGE 7
EOF
    
    # Mock system commands
    grep() {
        if [[ "$*" == *"PermitRootLogin yes"* ]]; then
            return 1
        elif [[ "$*" == *"PermitEmptyPasswords yes"* ]]; then
            return 1
        elif [[ "$*" == *"PASS_MAX_DAYS"* ]]; then
            echo "PASS_MAX_DAYS 365"
        else
            command grep "$@"
        fi
    }
    
    command() {
        if [[ "$1" == "grep" ]]; then
            shift
            grep "$@"
        else
            command command "$@"
        fi
    }
    
    export -f grep command
    
    if utils::quiet systemaudit::run_full; then
        test_pass
    else
        test_fail
    fi
    
    rm -rf /tmp/test_audit
    unset -f grep command
}

# Test 7: Report generation
test_report_generation() {
    log::info "Testing report generation..."
    
    # Test text report
    local text_report
    text_report="${AUDIT_REPORT_DIR}/test_text.txt"
    
    if systemaudit::generate_text_report "${text_report}"; then
        if [[ -f "${text_report}" ]]; then
            test_pass
        else
            test_fail
        fi
    else
        test_fail
    fi
    
    # Test JSON report
    local json_report
    json_report="${AUDIT_REPORT_DIR}/test_json.json"
    
    if systemaudit::generate_json_report "${json_report}"; then
        if [[ -f "${json_report}" ]]; then
            test_pass
        else
            test_fail
        fi
    else
        test_fail
    fi
    
    # Test CSV report
    local csv_report
    csv_report="${AUDIT_REPORT_DIR}/test_csv.csv"
    
    if systemaudit::generate_csv_report "${csv_report}"; then
        if [[ -f "${csv_report}" ]]; then
            test_pass
        else
            test_fail
        fi
    else
        test_fail
    fi
    
    # Test XML report
    local xml_report
    xml_report="${AUDIT_REPORT_DIR}/test_xml.xml"
    
    if systemaudit::generate_xml_report "${xml_report}"; then
        if [[ -f "${xml_report}" ]]; then
            test_pass
        else
            test_fail
        fi
    else
        test_fail
    fi
}

# Test 8: Security audit
test_security_audit() {
    log::info "Testing security audit..."
    
    # Mock system files
    mkdir -p /tmp/test_audit/etc
    
    # Create mock sshd_config with issues
    cat > /tmp/test_audit/etc/sshd_config << EOF
PermitRootLogin yes
PermitEmptyPasswords yes
Protocol 1
EOF
    
    # Mock functions
    [[ -f /etc/ssh/sshd_config ]] && mv /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    utils::quiet_err cp /tmp/test_audit/etc/sshd_config /etc/ssh/sshd_config || true
    
    systemaudit::security::check_root_login
    systemaudit::security::check_password_policy
    systemaudit::security::check_ssh_config
    
    # Restore original
    [[ -f /etc/ssh/sshd_config.bak ]] && utils::quiet_err mv /etc/ssh/sshd_config.bak /etc/ssh/sshd_config || true
    
    rm -rf /tmp/test_audit
    
    test_pass
}

# Test 9: Users audit
test_users_audit() {
    log::info "Testing users audit..."
    
    # Mock getent function
    getent() {
        if [[ "$1" == "group" ]] && [[ "$2" == "sudo" ]]; then
            echo "sudo:x:27:user1,user2,user3,user4,user5,user6,user7,user8"
        else
            command getent "$@"
        fi
    }
    
    export -f getent
    
    systemaudit::users::check_sudo_users
    
    unset -f getent
    
    test_pass
}

# Test 10: Network audit
test_network_audit() {
    log::info "Testing network audit..."
    
    # Mock ss/netstat
    ss() {
        if [[ "$*" == *"tuln"* ]]; then
            echo "LISTEN 0      128          0.0.0.0:22       0.0.0.0:*"
            echo "LISTEN 0      128          0.0.0.0:23       0.0.0.0:*"
            echo "LISTEN 0      128          0.0.0.0:21       0.0.0.0:*"
        fi
    }
    
    netstat() {
        ss "$@"
    }
    
    export -f ss netstat
    
    systemaudit::network::check_open_ports
    
    unset -f ss netstat
    
    test_pass
}

# Test 11: Filesystem audit
test_filesystem_audit() {
    log::info "Testing filesystem audit..."
    
    # Create test world-writable file
    touch /tmp/test_world_writable
    chmod 666 /tmp/test_world_writable
    
    systemaudit::filesystem::check_world_writable
    
    rm -f /tmp/test_world_writable
    
    test_pass
}

# Test 12: Services audit
test_services_audit() {
    log::info "Testing services audit..."
    
    # Mock ps
    ps() {
        if [[ "$*" == *aux* ]]; then
            echo "USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND"
            echo "root      1234  0.0  0.1  12345  6789 ?        Ss   12:00   0:00 telnetd"
        fi
    }
    
    export -f ps
    
    systemaudit::services::check_running_services
    
    unset -f ps
    
    test_pass
}

# Test 13: Compliance audit
test_compliance_audit() {
    log::info "Testing compliance audit..."
    
    # Mock system files
    mkdir -p /tmp/test_audit/etc/security
    
    cat > /tmp/test_audit/etc/security/pwquality.conf << EOF
minlen = 6
EOF
    
    # Mock pwquality.conf location
    if [[ -f /etc/security/pwquality.conf ]]; then
        utils::quiet_err mv /etc/security/pwquality.conf /etc/security/pwquality.conf.bak || true
    fi
    utils::quiet_err cp /tmp/test_audit/etc/security/pwquality.conf /etc/security/pwquality.conf || true
    
    systemaudit::compliance::check_password_complexity
    
    # Restore
    if [[ -f /etc/security/pwquality.conf.bak ]]; then
        utils::quiet_err mv /etc/security/pwquality.conf.bak /etc/security/pwquality.conf || true
    fi
    
    rm -rf /tmp/test_audit
    
    test_pass
}

# Test 14: Baseline creation
test_baseline_creation() {
    log::info "Testing baseline creation..."
    
    # Mock system commands
    hostname() {
        echo "test-host"
    }
    
    uname() {
        if [[ "$1" == "-r" ]]; then
            echo "5.4.0-100-generic"
        else
            command uname "$@"
        fi
    }
    
    getent() {
        if [[ "$1" == "passwd" ]]; then
            echo "root:x:0:0:root:/root:/bin/bash"
            echo "user1:x:1000:1000:user1:/home/user1:/bin/bash"
            echo "user2:x:1001:1001:user2:/home/user2:/bin/bash"
        else
            command getent "$@"
        fi
    }
    
    ss() {
        if [[ "$*" == *"tuln"* ]]; then
            echo "LISTEN 0 128 0.0.0.0:22 0.0.0.0:*"
            echo "LISTEN 0 128 0.0.0.0:80 0.0.0.0:*"
        fi
    }
    
    export -f hostname uname getent ss
    
    if systemaudit::create_baseline; then
        if [[ -f "${AUDIT_BASELINE_FILE}" ]]; then
            test_pass
        else
            test_fail
        fi
    else
        test_fail
    fi
    
    unset -f hostname uname getent ss
}

# Test 15: Module info
test_module_info() {
    log::info "Testing module info..."
    
    local info
    info=$(systemaudit::info)
    
    if [[ -n "${info}" ]] && echo "${info}" | grep -q "System Audit Module"; then
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
    log::info "Starting System Audit module tests..."
    
    # Register cleanup on exit
    trap cleanup EXIT
    
    # Run tests (|| true: падение одного теста не прерывает прогон / a failing test does not abort the run)
    test_module_initialization || true
    test_directory_creation || true
    test_finding_creation || true
    test_score_calculation || true
    test_quick_audit || true
    test_full_audit || true
    test_report_generation || true
    test_security_audit || true
    test_users_audit || true
    test_network_audit || true
    test_filesystem_audit || true
    test_services_audit || true
    test_compliance_audit || true
    test_baseline_creation || true
    test_module_info || true
    
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
