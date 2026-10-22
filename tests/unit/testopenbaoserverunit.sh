#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testopenbaoserverunit.sh — unit tests for lib/system/openbao
# tests/unit/testopenbaoserverunit.sh — модульные тесты lib/system/openbao

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/system/openbao"

SANDBOX=""
ORIG_PATH="${PATH}"
REAL_ID="$(command -v id)"

sandbox_new() {
    SANDBOX="$(mktemp -d)"
    mkdir -p "${SANDBOX}/bin" "${SANDBOX}/tools" "${SANDBOX}/releases/download/v9.9.9" \
        "${SANDBOX}/systemd" "${SANDBOX}/root"
    : > "${SANDBOX}/useradd.calls"
    : > "${SANDBOX}/passwd.calls"
    : > "${SANDBOX}/systemctl.calls"
    : > "${SANDBOX}/curl.calls"

    cat > "${SANDBOX}/bin/id" <<EOF
#!/bin/bash
if [[ "\${1-}" == "\${FAKE_USER}" && -e "\${FAKE_USER_MARKER}" ]]; then
    exit 0
fi
exec "${REAL_ID}" "\$@"
EOF
    cat > "${SANDBOX}/bin/useradd" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >> "${FAKE_USERADD_CALLS}"
: > "${FAKE_USER_MARKER}"
exit 0
EOF
    cat > "${SANDBOX}/bin/passwd" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >> "${FAKE_PASSWD_CALLS}"
exit 0
EOF
    cat > "${SANDBOX}/bin/systemctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >> "${FAKE_SYSTEMCTL_CALLS}"
exit 0
EOF
    cat > "${SANDBOX}/tools/curl" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >> "${FAKE_CURL_CALLS}"
url="${!#}"
data=0
for a in "$@"; do [[ "${a}" == "--data-binary" ]] && data=1; done
if (( data == 1 )); then cat >/dev/null; fi
case "${url}" in
    *sys/seal-status*) printf '%s' '{"sealed":false}' ;;
    *sys/unseal*)      printf '%s' '{"sealed":false}' ;;
    *sys/health*)      printf '%s' '{"initialized":true,"sealed":false}' ;;
    *)                 printf '%s' '{}' ;;
esac
printf '\n200'
exit 0
EOF
    chmod +x "${SANDBOX}/bin/"* "${SANDBOX}/tools/curl"

    export PATH="${SANDBOX}/bin:${ORIG_PATH}"
    export FAKE_USER="bs-openbao-test-$$"
    export FAKE_USER_MARKER="${SANDBOX}/user.marker"
    export FAKE_USERADD_CALLS="${SANDBOX}/useradd.calls"
    export FAKE_PASSWD_CALLS="${SANDBOX}/passwd.calls"
    export FAKE_SYSTEMCTL_CALLS="${SANDBOX}/systemctl.calls"
    export FAKE_CURL_CALLS="${SANDBOX}/curl.calls"

    export BS_OPENBAO_BIN="${SANDBOX}/bin/bao"
    export BS_OPENBAO_CONFIG="${SANDBOX}/etc/openbao/openbao.hcl"
    export BS_OPENBAO_CONFIG_DIR="${SANDBOX}/etc/openbao"
    export BS_OPENBAO_DATA_DIR="${SANDBOX}/var/lib/openbao"
    export BS_OPENBAO_TLS_DIR="${SANDBOX}/etc/openbao/tls"
    export BS_OPENBAO_TLS_CERT="${BS_OPENBAO_TLS_DIR}/server.crt"
    export BS_OPENBAO_TLS_KEY="${BS_OPENBAO_TLS_DIR}/server.key"
    export BS_OPENBAO_TLS_CA="${BS_OPENBAO_TLS_DIR}/ca.crt"
    export BS_OPENBAO_TLS_MODE=selfsigned
    export BS_OPENBAO_LISTEN="127.0.0.1:8200"
    export BS_OPENBAO_INIT_FILE="${SANDBOX}/root/openbao-init.json"
    export BS_OPENBAO_USER="${FAKE_USER}"
    export BS_OPENBAO_GROUP="${FAKE_USER}"
    export BS_OPENBAO_SERVICE="openbao-test"
    export BS_OPENBAO_RELEASE_BASE="file://${SANDBOX}/releases"
    export BS_OPENBAO_API_BASE="file://${SANDBOX}/api.json"
    export BS_OPENBAO_LATEST_VERSION="9.9.9"
    export BS_OPENBAO_VERSION="9.9.9"
    export BS_OPENBAO_INIT_SHARES=5
    export BS_OPENBAO_INIT_THRESHOLD=3
    export BS_OPENBAO_TIMEOUT=2
    export BS_OPENBAO_DRY_RUN=0
    export BS_OPENBAO_CURL="${SANDBOX}/tools/curl"
    export BS_OPENBAO_JQ="$(command -v jq)"
    export BS_OPENBAO_TOKEN_FILE="${SANDBOX}/client-token"
    export BS_SYSTEMD_UNIT_DIR="${SANDBOX}/systemd"
}

sandbox_drop() {
    export PATH="${ORIG_PATH}"
    rm -rf "${SANDBOX:?}"
}

build_release() {
    local arch name asset src
    arch="$(openbao_server::arch)"
    name="openbao_9.9.9_linux_${arch}.tar.gz"
    asset="${SANDBOX}/releases/download/v9.9.9/${name}"
    src="${SANDBOX}/release-src"
    mkdir -p "${src}"
    cat > "${src}/bao" <<'EOF'
#!/bin/bash
case "${1-}" in
    version) printf '%s\n' 'OpenBao v9.9.9' ;;
    operator)
        if [[ "${2-}" == "init" ]]; then
            printf '%s\n' '{"unseal_keys_b64":["a","b","c","d","e"],"unseal_keys_hex":[],"root_token":"root"}'
        else
            exit 1
        fi
        ;;
    status) printf '%s\n' '{"sealed":false,"initialized":true}' ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "${src}/bao"
    tar -czf "${asset}" -C "${src}" bao
    sha256sum "${asset}" | awk -v n="${name}" '{print $1"  "n}' \
        > "${SANDBOX}/releases/download/v9.9.9/checksums.txt"
}

main() {
    print_header "OpenBao server unit tests / Модульные тесты сервера OpenBao"
    testframework::init
    sandbox_new

    testframework::section "init and validation / init и проверки"
    testframework::assert_command "openbao_server::init" "valid hooks accepted"
    BS_OPENBAO_LISTEN="bad"
    testframework::assert_false "openbao_server::init" "bad listen rejected"
    BS_OPENBAO_LISTEN="127.0.0.1:8200\"x"
    testframework::assert_false "openbao_server::init" "quote in listen rejected"
    BS_OPENBAO_LISTEN="127.0.0.1:70000"
    testframework::assert_false "openbao_server::init" "listen port out of range rejected"
    BS_OPENBAO_LISTEN="127.0.0.1:8200"
    BS_OPENBAO_USER="Bad User"
    testframework::assert_false "openbao_server::init" "bad user rejected"
    BS_OPENBAO_USER="${FAKE_USER}"
    BS_OPENBAO_SERVICE="bad service"
    testframework::assert_false "openbao_server::init" "bad service rejected"
    BS_OPENBAO_SERVICE="openbao-test"
    BS_OPENBAO_TLS_MODE="bad"
    testframework::assert_false "openbao_server::init" "bad TLS mode rejected"
    BS_OPENBAO_TLS_MODE="selfsigned"
    BS_OPENBAO_INIT_SHARES=2 BS_OPENBAO_INIT_THRESHOLD=3
    testframework::assert_false "openbao_server::init" "threshold above shares rejected"
    BS_OPENBAO_INIT_SHARES=5 BS_OPENBAO_INIT_THRESHOLD=3

    testframework::section "platform and version / платформа и версия"
    local arch
    arch="$(openbao_server::arch)"
    testframework::assert_true "'${arch}' == amd64 || '${arch}' == arm64" "arch mapped"
    testframework::assert_false "openbao_server::version" "no binary yet"
    testframework::assert_equal "9.9.9" "$(openbao_server::__resolve_version 9.9.9)" "explicit version"
    testframework::assert_equal "9.9.9" "$(openbao_server::__resolve_version latest)" "pre-resolved latest"
    testframework::assert_false "openbao_server::__resolve_version bad" "bad version rejected"
    testframework::assert_command "openbao_server::asset_url 9.9.9 | grep -qF 'openbao_9.9.9_linux_${arch}.tar.gz'" "asset URL"
    testframework::assert_command "openbao_server::checksums_url 9.9.9 | grep -qF 'download/v9.9.9/checksums.txt'" "checksums URL"

    testframework::section "config and unit / конфиг и юнит"
    local cfg
    cfg="$(openbao_server::render_config prod)"
    testframework::assert_command "printf '%s' '${cfg}' | grep -qF 'storage \"file\"'" "file storage"
    testframework::assert_command "printf '%s' '${cfg}' | grep -qF 'tls_disable = 0'" "TLS enabled in prod"
    testframework::assert_command "printf '%s' '${cfg}' | grep -qF 'api_addr = \"https://127.0.0.1:8200\"'" "prod api_addr"
    testframework::assert_command "printf '%s' '${cfg}' | grep -qF 'cluster_addr = \"https://127.0.0.1:8201\"'" "cluster port"
    cfg="$(openbao_server::render_config dev)"
    testframework::assert_command "printf '%s' '${cfg}' | grep -qF 'tls_disable = 1'" "dev disables TLS"
    testframework::assert_command "printf '%s' '${cfg}' | grep -qF 'api_addr = \"http://127.0.0.1:8200\"'" "dev api_addr"
    testframework::assert_equal "https://127.0.0.1:8200" "$(openbao_server::local_api_addr prod)" "local prod address"
    BS_OPENBAO_LISTEN="0.0.0.0:8200"
    testframework::assert_equal "https://127.0.0.1:8200" "$(openbao_server::local_api_addr prod)" "wildcard normalized"
    BS_OPENBAO_LISTEN="127.0.0.1:8200"
    local unit
    unit="$(openbao_server::unit_render)"
    testframework::assert_command "printf '%s' '${unit}' | grep -qF 'ExecStart=${BS_OPENBAO_BIN} server -config=${BS_OPENBAO_CONFIG}'" "unit ExecStart"
    testframework::assert_command "printf '%s' '${unit}' | grep -qF 'User=${BS_OPENBAO_USER}'" "unit user"
    testframework::assert_command "printf '%s' '${unit}' | grep -qF 'ReadWritePaths=${BS_OPENBAO_DATA_DIR}'" "unit writable data"

    testframework::section "TLS / TLS"
    testframework::assert_false "openbao_server::tls_selfsigned 'bad host'" "bad SAN rejected"
    testframework::assert_command "openbao_server::tls_selfsigned localhost 127.0.0.1" "self-signed TLS generated"
    testframework::assert_file_exists "${BS_OPENBAO_TLS_CA}" "CA certificate"
    testframework::assert_file_exists "${BS_OPENBAO_TLS_CERT}" "server certificate"
    testframework::assert_file_exists "${BS_OPENBAO_TLS_KEY}" "server key"
    testframework::assert_equal "600" "$(stat -c %a "${BS_OPENBAO_TLS_KEY}")" "key mode 0600"
    testframework::assert_command "openssl verify -CAfile '${BS_OPENBAO_TLS_CA}' '${BS_OPENBAO_TLS_CERT}' >/dev/null 2>&1" "certificate chains to CA"

    testframework::section "configure / настройка"
    mkdir -p "${BS_OPENBAO_CONFIG_DIR}"
    printf '%s\n' "old config" > "${BS_OPENBAO_CONFIG}"
    testframework::assert_command "openbao_server::configure prod" "prod configure"
    testframework::assert_file_exists "${BS_OPENBAO_CONFIG}" "config written"
    testframework::assert_equal "640" "$(stat -c %a "${BS_OPENBAO_CONFIG}")" "config mode 0640"
    testframework::assert_command "grep -qF 'storage \"file\"' '${BS_OPENBAO_CONFIG}'" "config content"
    testframework::assert_command "compgen -G '${BS_OPENBAO_CONFIG}.bak.*' >/dev/null" "old config backed up"
    testframework::assert_command "[[ -d '${BS_OPENBAO_DATA_DIR}/data' ]]" "data directory"

    testframework::section "system user / системный пользователь"
    testframework::assert_command "openbao_server::ensure_user" "user created"
    testframework::assert_command "grep -qF -- '--system' '${SANDBOX}/useradd.calls'" "useradd --system"
    testframework::assert_command "grep -qF -- '--user-group' '${SANDBOX}/useradd.calls'" "useradd --user-group"
    testframework::assert_command "grep -qF -- '-l' '${SANDBOX}/passwd.calls'" "password locked"
    local before
    before="$(wc -l < "${SANDBOX}/useradd.calls")"
    testframework::assert_command "openbao_server::ensure_user" "user already exists"
    testframework::assert_equal "${before}" "$(wc -l < "${SANDBOX}/useradd.calls")" "useradd not repeated"

    testframework::section "systemd unit / systemd-юнит"
    testframework::assert_command "openbao_server::install_service" "unit installed"
    local unit_path="${BS_SYSTEMD_UNIT_DIR}/${BS_OPENBAO_SERVICE}.service"
    testframework::assert_file_exists "${unit_path}" "unit file"
    testframework::assert_command "grep -qF 'daemon-reload' '${SANDBOX}/systemctl.calls'" "daemon reload"
    testframework::assert_command "grep -qF 'enable' '${SANDBOX}/systemctl.calls' && grep -qF -- '--now' '${SANDBOX}/systemctl.calls'" "enable --now"

    testframework::section "dev command / команда dev"
    export BS_OPENBAO_DEV_TOKEN="dev-token"
    testframework::assert_command "openbao_server::dev_command | grep -qF 'BAO_DEV_ROOT_TOKEN_ID=dev-token'" "dev token"
    testframework::assert_command "openbao_server::dev_command | grep -qF 'server -dev -dev-listen-address=127.0.0.1:8200'" "dev listen"
    testframework::section "release install / установка релиза"
    build_release
    testframework::assert_command "openbao_server::install" "release installed"
    testframework::assert_file_exists "${BS_OPENBAO_BIN}" "bao installed"
    testframework::assert_equal "9.9.9" "$(openbao_server::version)" "installed version"
    testframework::assert_equal "${BS_OPENBAO_BIN}"$'\t'"9.9.9" "$(openbao_server::detect)" "detect output"
    testframework::assert_command "openbao_server::install" "already installed is a no-op"
    testframework::assert_command "openbao_server::status | grep -qF 'sealed'" "server status"
    export BS_OPENBAO_DRY_RUN=1
    testframework::assert_command "openbao_server::dev_start" "dev dry-run"
    testframework::assert_command "openbao_server::apply dev" "apply dev dry-run"
    export BS_OPENBAO_DRY_RUN=0

    testframework::section "init and unseal / init и unseal"
    testframework::assert_command "openbao_server::init_cluster" "cluster initialized"
    testframework::assert_file_exists "${BS_OPENBAO_INIT_FILE}" "init file"
    testframework::assert_equal "600" "$(stat -c %a "${BS_OPENBAO_INIT_FILE}")" "init file mode 0600"
    testframework::assert_command "grep -qF 'root_token' '${BS_OPENBAO_INIT_FILE}'" "root token saved"
    testframework::assert_false "openbao_server::init_cluster" "second init is a conflict"
    : > "${SANDBOX}/curl.calls"
    testframework::assert_command "openbao_server::unseal" "unseal from init file"
    testframework::assert_equal "3" "$(grep -c 'sys/unseal' "${SANDBOX}/curl.calls")" "threshold keys used"
    testframework::assert_command "grep -qF 'sys/seal-status' '${SANDBOX}/curl.calls'" "seal status checked"
    testframework::assert_command "openbao_server::wait_ready 2" "readiness wait"
    export BS_OPENBAO_DRY_RUN=1
    testframework::assert_command "openbao_server::apply prod" "apply prod dry-run"
    export BS_OPENBAO_DRY_RUN=0

    testframework::section "checksum failure / ошибка контрольной суммы"
    rm -f "${BS_OPENBAO_BIN}"
    printf '%064d  %s\n' 0 "openbao_9.9.9_linux_$(openbao_server::arch).tar.gz" \
        > "${SANDBOX}/releases/download/v9.9.9/checksums.txt"
    testframework::assert_false "openbao_server::install" "bad checksum rejected"
    testframework::assert_true "! -e '${BS_OPENBAO_BIN}'" "bad release not installed"

    sandbox_drop
    testframework::summary
}

main "$@"
