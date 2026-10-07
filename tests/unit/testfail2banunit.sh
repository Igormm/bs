#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testfail2banunit.sh — unit tests for lib/system/fail2ban
# tests/unit/testfail2banunit.sh — юнит-тесты lib/system/fail2ban

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/system/fail2ban"

main() {
    print_header "fail2ban Unit Tests / Юнит-тесты fail2ban"
    testframework::init

    testframework::section "catalog / каталог"
    local name
    for name in "${!F2B_DEFAULT[@]}"; do
        testframework::assert_true "-n '${F2B_TIPS[$name]:-}'" "default tip: ${name}"
    done
    testframework::assert_true "-n '${F2B_JAILS[sshd]:-}'" "sshd jail present"
    testframework::assert_equal "5" "$(printf '%s' "${F2B_DEFAULT[maxretry]}" | cut -d'|' -f2)" "maxretry default 5"
    testframework::assert_true "$(fail2ban::param_list default | wc -l) -ge 10" "default param_list non-empty"
    testframework::assert_true "$(fail2ban::jails | wc -l) -ge 10" "jail catalog non-empty"

    testframework::section "types / типы"
    testframework::assert_equal "time" "$(fail2ban::param_type bantime)" "bantime time"
    testframework::assert_equal "int" "$(fail2ban::param_type maxretry)" "maxretry int"
    testframework::assert_equal "bool" "$(fail2ban::param_type bantime.increment)" "increment bool"

    testframework::section "validate / валидация"
    local rc=0
    fail2ban::validate bantime 1h || rc=$?; testframework::assert_equal 0 "${rc}" "time 1h ok"
    rc=0; fail2ban::validate bantime -1 || rc=$?; testframework::assert_equal 0 "${rc}" "time -1 ok"
    rc=0; fail2ban::validate bantime "1x" || rc=$?; testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${rc}" "time 1x rejected"
    rc=0; fail2ban::validate maxretry 5 || rc=$?; testframework::assert_equal 0 "${rc}" "int ok"
    rc=0; fail2ban::validate maxretry "5;rm" || rc=$?; testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${rc}" "int injection rejected"
    rc=0; fail2ban::validate bantime.increment true || rc=$?; testframework::assert_equal 0 "${rc}" "bool ok"
    rc=0; fail2ban::validate backend bogus || rc=$?; testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${rc}" "enum bad rejected"
    rc=0; fail2ban::validate ignoreip "10.0.0.0/8 192.168.1.5" || rc=$?; testframework::assert_equal 0 "${rc}" "iplist ok"
    rc=0; fail2ban::validate ignoreip "10.0.0.1;x" || rc=$?; testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${rc}" "iplist bad rejected"

    testframework::section "render / INI"
    local out
    out="$(printf '@section DEFAULT\nbantime=1h\nmaxretry=5\n\n@section sshd\nenabled=true\nport=ssh\n' | fail2ban::render)"
    testframework::assert_command "printf '%s' '${out}' | grep -qF '# BEGIN bs-fail2ban'" "begin marker"
    testframework::assert_command "printf '%s' '${out}' | grep -q '^\[DEFAULT\]$'" "DEFAULT section"
    testframework::assert_command "printf '%s' '${out}' | grep -q '^bantime = 1h$'" "bantime line"
    testframework::assert_command "printf '%s' '${out}' | grep -q '^\[sshd\]$'" "sshd section"
    testframework::assert_command "printf '%s' '${out}' | grep -q '^enabled = true$'" "enabled line"
    local d_line s_line
    d_line="$(printf '%s\n' "${out}" | grep -n '^\[DEFAULT\]$' | cut -d: -f1)"
    s_line="$(printf '%s\n' "${out}" | grep -n '^\[sshd\]$' | cut -d: -f1)"
    testframework::assert_true "d_line -lt s_line" "DEFAULT before jails"
    out="$(printf '@section DEFAULT\nmaxretry=\n' | fail2ban::render)"
    testframework::assert_command "! printf '%s' '${out}' | grep -q '^maxretry '" "empty value skipped"

    testframework::section "profiles / профили"
    testframework::assert_command "fail2ban::profile basic | grep -q '^sshd.enabled=true$'" "basic enables sshd"
    testframework::assert_command "fail2ban::profile strict | grep -q '^DEFAULT.bantime.increment=true$'" "strict increment"
    testframework::assert_command "fail2ban::profile paranoid | grep -q '^DEFAULT.bantime=-1$'" "paranoid permanent"

    testframework::section "test/install/revert / установка"
    local tmp; tmp="$(mktemp -d)"
    export BS_FAIL2BAN_DIR="${tmp}" BS_FAIL2BAN_DROPIN="jail.d/99-bs.conf"
    export BS_FAIL2BAN_CLIENT="${tmp}/f2b" BS_FAIL2BAN_SERVICE="fail2ban"
    cat > "${BS_FAIL2BAN_CLIENT}" <<'EOF'
#!/bin/bash
dir=""
while (( $# )); do
  case "$1" in
    -c) dir="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
if [[ -n "${dir}" ]] && grep -rq 'BAD' "${dir}" 2>/dev/null; then exit 1; fi
exit 0
EOF
    chmod +x "${BS_FAIL2BAN_CLIENT}"

    mkdir -p "${tmp}/good" "${tmp}/bad"
    printf '[DEFAULT]\nbantime = 1h\n' > "${tmp}/good/jail.local"
    printf '[DEFAULT]\nBAD x\n' > "${tmp}/bad/jail.local"
    local trc=0; fail2ban::test "${tmp}/good/jail.local" || trc=$?
    testframework::assert_equal 0 "${trc}" "fake client accepts good"
    trc=0; fail2ban::test "${tmp}/bad/jail.local" || trc=$?
    testframework::assert_equal 1 "${trc}" "fake client rejects bad"

    local old="${BS_FAIL2BAN_CLIENT}"; BS_FAIL2BAN_CLIENT="no-such-f2b-xyz"
    trc=0; fail2ban::test "${tmp}/good/jail.local" 2>/dev/null || trc=$?
    testframework::assert_equal "${LIB_ERROR_DEPENDENCY_MISSING}" "${trc}" "missing client → dependency missing"
    BS_FAIL2BAN_CLIENT="${old}"

    local irc=0
    fail2ban::install "${tmp}/good/jail.local" || irc=$?
    testframework::assert_equal 0 "${irc}" "install ok"
    testframework::assert_file_exists "${tmp}/jail.d/99-bs.conf" "drop-in written"
    irc=0; fail2ban::install "${tmp}/bad/jail.local" 2>/dev/null || irc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${irc}" "bad rejected"
    testframework::assert_file_exists "${tmp}/jail.d/99-bs.conf" "target unchanged after reject"

    rm -f "${tmp}/jail.d/99-bs.conf"
    export BS_FAIL2BAN_DRY_RUN=1
    fail2ban::install "${tmp}/good/jail.local" || irc=$?
    testframework::assert_true "! -f '${tmp}/jail.d/99-bs.conf'" "dry-run writes nothing"
    export BS_FAIL2BAN_DRY_RUN=0

    testframework::section "detect / автообнаружение"
    mkdir -p "${tmp}/filter.d"
    touch "${tmp}/filter.d/sshd.conf" "${tmp}/filter.d/nginx-http-auth.conf"
    local det; det="$(fail2ban::detect)"
    testframework::assert_command "printf '%s' '${det}' | grep -q '^sshd$'" "detect finds sshd"
    testframework::assert_command "printf '%s' '${det}' | grep -q '^nginx-http-auth$'" "detect finds nginx-http-auth"
    rm -rf "${tmp}"

    testframework::summary
}

main "$@"
