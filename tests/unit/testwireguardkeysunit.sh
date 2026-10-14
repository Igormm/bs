#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testwireguardkeysunit.sh — wireguard key handling without root
# tests/unit/testwireguardkeysunit.sh — работа wireguard с ключами без root
#
# `wg` is a fake and all directories are temporary (BS_WIREGUARD_*_DIR):
# nothing under /etc/wireguard is touched.
# `wg` — заглушка, все каталоги временные (BS_WIREGUARD_*_DIR):
# /etc/wireguard не затрагивается.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

TEST_TMP="$(mktemp -d)"
export BS_WIREGUARD_CONFIG_DIR="${TEST_TMP}/etc"
export BS_WIREGUARD_BACKUP_DIR="${TEST_TMP}/backup"
mkdir -p "${TEST_TMP}/etc/keys" "${TEST_TMP}/bin"
cat > "${TEST_TMP}/bin/wg" <<'FAKE'
#!/bin/sh
case "$1" in
  genkey) echo "FAKEPRIVATEKEY=" ;;
  pubkey) cat >/dev/null; echo "FAKEPUBLICKEY=" ;;
esac
FAKE
chmod +x "${TEST_TMP}/bin/wg"
export PATH="${TEST_TMP}/bin:${PATH}"
load "lib/integration/wireguard"

main() {
    print_header "WireGuard Keys Unit Tests / Тесты ключей WireGuard"
    testframework::init

    local rc pub
    testframework::section "generate_keypair"
    pub="$(wireguard::generate_keypair wgt 2>/dev/null | tail -n 1)"
    testframework::assert_equal "FAKEPUBLICKEY=" "${pub}" "the public key is returned"
    testframework::assert_equal "600" "$(stat -c %a "${TEST_TMP}/etc/keys/wgt_private.key")" "the private key is 0600"

    rc=0; ( wireguard::generate_keypair wgt ) >/dev/null 2>&1 || rc=$?
    testframework::assert_true "${rc} -ne 0" "an existing key is not overwritten"
    testframework::assert_equal "FAKEPRIVATEKEY=" "$(cat "${TEST_TMP}/etc/keys/wgt_private.key")" "the existing private key is intact"

    rm -rf "${TEST_TMP}"
    testframework::summary
}

main "$@"
