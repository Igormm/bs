#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testsshdunit.sh — Unit tests for lib/system/sshd
# tests/unit/testsshdunit.sh — Модульные тесты для lib/system/sshd

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/system/sshd"

main() {
    print_header "SSHd Unit Tests / Модульные тесты sshd"
    testframework::init

    testframework::section "catalog shape / форма каталога"
    local name meta fields
    for name in "${SSHD_PARAM_ORDER[@]}"; do
        meta="${SSHD_PARAMS[$name]:-}"
        testframework::assert_true "-n '${meta}'" "meta present: ${name}"
        fields="$(awk -F'|' '{print NF}' <<< "${meta}")"
        testframework::assert_equal "4" "${fields}" "4 fields: ${name}"
        testframework::assert_true "-n '${SSHD_TIPS[$name]:-}'" "tip present: ${name}"
        testframework::assert_command "LC_ALL=C grep -q '[^ -~]' <<< \"\${SSHD_TIPS[${name}]}\"" "tip non-ascii/cyrillic: ${name}"
    done

    testframework::section "param_list / список параметров"
    local count filtered
    count="$(sshd::param_list | wc -l)"
    testframework::assert_equal "${#SSHD_PARAM_ORDER[@]}" "${count}" "all params listed"
    filtered="$(sshd::param_list Network)"
    testframework::assert_true "-n '${filtered}'" "Network filter non-empty"
    testframework::assert_command "! printf '%s' '${filtered}' | grep -q 'Authentication'" "Network filter excludes others"

    testframework::section "param_type / param_desc"
    testframework::assert_equal "bool" "$(sshd::param_type PasswordAuthentication)" "bool type"
    testframework::assert_equal "port" "$(sshd::param_type Port)" "port type"
    local desc
    desc="$(sshd::param_desc PasswordAuthentication)"
    testframework::assert_equal "2" "$(printf '%s\n' "${desc}" | wc -l)" "desc is two lines"
    local rc=0; sshd::param_type no_such_param >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_ARGS}" "${rc}" "unknown param → invalid args"

    testframework::section "param_default / param_recommended"
    testframework::assert_equal "22" "$(sshd::param_default Port)" "Port default 22"
    testframework::assert_equal "no" "$(sshd::param_recommended PasswordAuthentication)" "pw recommended no"

    testframework::section "validate / валидация значений"
    local vrc=0
    sshd::validate PasswordAuthentication yes || vrc=$?
    testframework::assert_equal "0" "${vrc}" "bool yes ok"
    vrc=0; sshd::validate PasswordAuthentication maybe || vrc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${vrc}" "bool maybe rejected"

    vrc=0; sshd::validate Port 65535 || vrc=$?
    testframework::assert_equal "0" "${vrc}" "port 65535 ok"
    vrc=0; sshd::validate Port 70000 || vrc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${vrc}" "port 70000 rejected"
    vrc=0; sshd::validate Port "22;rm -rf /" || vrc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${vrc}" "port injection rejected"

    vrc=0; sshd::validate PermitRootLogin prohibit-password || vrc=$?
    testframework::assert_equal "0" "${vrc}" "enum ok"
    vrc=0; sshd::validate PermitRootLogin root || vrc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${vrc}" "enum bad rejected"

    vrc=0; sshd::validate AllowUsers "alice,bob" || vrc=$?
    testframework::assert_equal "0" "${vrc}" "userlist ok"
    vrc=0; sshd::validate AllowUsers "alice root" || vrc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${vrc}" "userlist space rejected"

    vrc=0; sshd::validate Ciphers "aes256-ctr,chacha20-poly1305@openssh.com" || vrc=$?
    testframework::assert_equal "0" "${vrc}" "ciphers ok"
    vrc=0; sshd::validate Ciphers "aes256-ctr,"$'\n'"PermitRootLogin yes" || vrc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${vrc}" "newline injection rejected"

    vrc=0; sshd::validate Subsystem internal-sftp || vrc=$?
    testframework::assert_equal "0" "${vrc}" "path internal-sftp ok"
    vrc=0; sshd::validate ChrootDirectory "%h" || vrc=$?
    testframework::assert_equal "0" "${vrc}" "string %h ok"
    vrc=0; sshd::validate LoginGraceTime 30 || vrc=$?
    testframework::assert_equal "0" "${vrc}" "time 30 ok"
    vrc=0; sshd::validate LoginGraceTime "1h30" || vrc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${vrc}" "time bad rejected"

    testframework::section "profiles / профили"
    local out
    out="$(sshd::profile basic)"
    testframework::assert_command "printf '%s' '${out}' | grep -q '^PubkeyAuthentication=yes$'" "basic pubkey"
    testframework::assert_command "printf '%s' '${out}' | grep -q '^PasswordAuthentication=no$'" "basic no password"
    out="$(sshd::profile strict)"
    testframework::assert_command "printf '%s' '${out}' | grep -q '^PermitRootLogin=no$'" "strict root no"
    testframework::assert_command "printf '%s' '${out}' | grep -q '^AllowTcpForwarding=no$'" "strict no tcp fwd"
    out="$(sshd::profile paranoid)"
    testframework::assert_command "printf '%s' '${out}' | grep -q '^AddressFamily=inet$'" "paranoid inet"
    testframework::assert_command "printf '%s' '${out}' | grep -q '^Ciphers='" "paranoid ciphers"
    local prc=0; sshd::profile no_such >/dev/null 2>&1 || prc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_ARGS}" "${prc}" "unknown profile rejected"

    testframework::section "render / рендер конфига"
    local rendered
    rendered="$(printf 'PasswordAuthentication=no\nPort=2222\n' | sshd::render)"
    testframework::assert_command "printf '%s' '${rendered}' | grep -qF '${SSHD_MARK_BEGIN}'" "begin marker"
    testframework::assert_command "printf '%s' '${rendered}' | grep -qF '${SSHD_MARK_END}'" "end marker"
    testframework::assert_command "printf '%s' '${rendered}' | grep -q '^Port 2222$'" "port rendered"
    testframework::assert_command "printf '%s' '${rendered}' | grep -q '^PasswordAuthentication no$'" "pw rendered"
    local port_line pw_line
    port_line="$(printf '%s\n' "${rendered}" | grep -n '^Port ' | cut -d: -f1)"
    pw_line="$(printf '%s\n' "${rendered}" | grep -n '^PasswordAuthentication ' | cut -d: -f1)"
    testframework::assert_true "port_line -lt pw_line" "catalog order (Port before Password…)"

    rendered="$(printf 'AllowUsers=\nPort=22\n' | sshd::render)"
    testframework::assert_command "! printf '%s' '${rendered}' | grep -q 'AllowUsers '" "empty value skipped"

    rendered="$(printf '@match Group sftponly\nChrootDirectory=%%h\nForceCommand=internal-sftp\n\n' | sshd::render)"
    testframework::assert_command "printf '%s' '${rendered}' | grep -q '^Match Group sftponly$'" "match header"
    testframework::assert_command "printf '%s' '${rendered}' | grep -q '^    ChrootDirectory %h$'" "match indented directive"

    testframework::summary
}

main "$@"
