#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testdripfetchunit.sh — startup regression for examples/dripfetch.sh
# tests/unit/testdripfetchunit.sh — регрессия запуска examples/dripfetch.sh

set -euo pipefail

TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_SCRIPT_DIR
BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"
readonly BS_PROJECT_ROOT

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"
readonly DRIPFETCH_SCRIPT="${BS_PROJECT_ROOT}/examples/dripfetch.sh"

T=""

run_dashboard() {
    local log="$1" keys="$2" rc=0
    shift 2
    (sleep 0.2; printf '%s' "$keys") | HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" TERM=xterm-256color COLUMNS=80 LINES=24 \
        timeout -k 2 15 "$@" > "${log}" 2>&1 || rc=$?
    printf '%s' "$rc"
}

test_bs_startup() {
    local rc log="${T}/bs-startup.log"
    rc="$(run_dashboard "$log" "qqq" "${BS_PROJECT_ROOT}/bs" run "${DRIPFETCH_SCRIPT}")"
    testframework::assert_equal "0" "$rc" "dashboard starts and quits under bs"
    testframework::assert_command "grep -q 'sysinfo' '$log'" "dashboard renders its default boxes"
    testframework::assert_command "! grep -Eq 'unbound variable|не заданы границы|not an identifier|not interactive' '$log'" "startup has no shell failure"
}

test_bash_startup() {
    local bash_bin rc log="${T}/bash-startup.log"
    bash_bin="$(bs::shell::host)"
    rc="$(run_dashboard "$log" "qqq" "$bash_bin" "$DRIPFETCH_SCRIPT")"
    testframework::assert_equal "0" "$rc" "dashboard starts and quits under bash"
    testframework::assert_command "grep -q 'sysinfo' '$log'" "bash dashboard renders its default boxes"
}

test_zsh_startup() {
    local zsh_bin rc log="${T}/zsh-startup.log"
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh startup" "zsh is not installed / zsh не установлен"
        return 0
    fi
    rc="$(run_dashboard "$log" "qqq" "$zsh_bin" "$DRIPFETCH_SCRIPT")"
    testframework::assert_equal "0" "$rc" "dashboard starts and quits under zsh"
    testframework::assert_command "grep -q 'sysinfo' '$log'" "zsh dashboard renders its default boxes"
    testframework::assert_command "! grep -q 'not interactive' '$log'" "zsh reads keys from stdin"
}

run_net_probe() {
    local shell_bin="$1" prefix="$2" rc=0
    mkdir -p "$prefix"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" "$shell_bin" -c '
        source <(sed "\$d" "$1")
        dripfetch::net_sample_bytes() { printf "100 200"; }
        NET_INTERVAL=1
        dripfetch::net_lines > "$2/first"
        dripfetch::net_lines > "$2/second"
        printf "%s" "$NET_SAMPLES" > "$2/samples"
    ' _ "$DRIPFETCH_SCRIPT" "$prefix" > "${prefix}/stdout" 2> "${prefix}/stderr" || rc=$?
    printf '%s' "$rc"
}

assert_net_probe() {
    local shell_bin="$1" label="$2" rc
    local prefix="${T}/${label}-net-probe"
    rc="$(run_net_probe "$shell_bin" "$prefix")"
    testframework::assert_equal "0" "$rc" "$label net sampling survives empty arrays"

    local first second samples
    first="$(<"${prefix}/first")"
    second="$(<"${prefix}/second")"
    samples="$(<"${prefix}/samples")"
    testframework::assert_equal $'down -\nup -' "$first" "$label net graph starts empty"
    testframework::assert_equal $'down ▁\nup   ▁' "$second" "$label net graph has one glyph per real sample"
    testframework::assert_equal '0:0' "$samples" "$label net graph stores one deterministic sample"
}

assert_net_dashboard() {
    local label="$1" rc="$2" log="$3"
    testframework::assert_equal "0" "$rc" "$label dashboard starts with net and empty rain lists"
    testframework::assert_command "grep -q 'sysinfo' '$log'" "$label net config renders sysinfo"
    testframework::assert_command "grep -q 'down -' '$log'" "$label net graph starts with no samples"
    testframework::assert_command "! grep -Eq 'unbound variable|не заданы границы|division by zero|деление на 0' '$log'" "$label net startup has no shell failure"
}

test_bs_net_startup() {
    local rc log="${T}/bs-net-startup.log"
    rc="$(run_dashboard "$log" "qqq" "${BS_PROJECT_ROOT}/bs" run "$DRIPFETCH_SCRIPT" -c "${T}/net.yaml")"
    assert_net_dashboard "bs" "$rc" "$log"
}

test_bash_net_startup() {
    local bash_bin rc log="${T}/bash-net-startup.log"
    bash_bin="$(bs::shell::host)"
    rc="$(run_dashboard "$log" "qqq" "$bash_bin" "$DRIPFETCH_SCRIPT" -c "${T}/net.yaml")"
    assert_net_dashboard "bash" "$rc" "$log"
    assert_net_probe "$bash_bin" "bash"
}

test_zsh_net_startup() {
    local zsh_bin rc log="${T}/zsh-net-startup.log"
    zsh_bin="$(command -v zsh || true)"
    if [[ -z "$zsh_bin" ]]; then
        testframework::skip "zsh net startup and sampling" "zsh is not installed / zsh не установлен"
        return 0
    fi
    rc="$(run_dashboard "$log" "qqq" "$zsh_bin" "$DRIPFETCH_SCRIPT" -c "${T}/net.yaml")"
    assert_net_dashboard "zsh" "$rc" "$log"
    assert_net_probe "$zsh_bin" "zsh"
}

main() {
    print_header "Dripfetch Startup / Запуск dripfetch"
    testframework::init
    T="$(mktemp -d)"
    trap 'rm -rf "${T:?}"' EXIT
    mkdir -p "${T}/home" "${T}/config"
    HOME="${T}/home" XDG_CONFIG_HOME="${T}/config" \
        "${BS_PROJECT_ROOT}/bs" run "$DRIPFETCH_SCRIPT" --init-config \
        > "${T}/init.log" 2>&1
    testframework::assert_file_exists "${T}/config/dripfetch/config.yaml" "default config initialized"
    cat > "${T}/net.yaml" <<'EOF'
rain:
  intensity: 20
  character: []
  colors: []
  speeds: []
  lengths: []
boxes:
  items:
    - type: sysinfo
    - type: net
net:
  interval: 1
  width: 40
EOF

    testframework::section "Startup / Запуск"
    test_bs_startup
    test_bash_startup
    test_zsh_startup

    testframework::section "Network / Сеть"
    test_bs_net_startup
    test_bash_net_startup
    test_zsh_net_startup

    testframework::summary
}

main "$@"
