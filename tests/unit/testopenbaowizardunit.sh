#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testopenbaowizardunit.sh — unit tests for examples/openbao_wizard.sh
# tests/unit/testopenbaowizardunit.sh — модульные тесты examples/openbao_wizard.sh

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

SANDBOX=""
ORIG_PATH="${PATH}"

sandbox_new() {
    SANDBOX="$(mktemp -d)"
    mkdir -p "${SANDBOX}/bin" "${SANDBOX}/tools" "${SANDBOX}/tmp"
    : > "${SANDBOX}/curl.calls"
    cat > "${SANDBOX}/tools/curl" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >> "${FAKE_CALLS}"
data=0
for a in "$@"; do [[ "${a}" == "--data-binary" ]] && data=1; done
if (( data == 1 )); then cat >/dev/null; fi
printf '%s' "${FAKE_BODY:-{\"initialized\":true,\"sealed\":false}}"
printf '\n%s' "${FAKE_STATUS:-200}"
exit "${FAKE_RC:-0}"
EOF
    chmod +x "${SANDBOX}/tools/curl"
    cat > "${SANDBOX}/bin/bao" <<'EOF'
#!/bin/bash
if [[ "${1-}" == "version" ]]; then
    printf '%s\n' 'OpenBao v9.9.9'
    exit 0
fi
exit 1
EOF
    chmod +x "${SANDBOX}/bin/bao"

    export PATH="${ORIG_PATH}"
    export TMPDIR="${SANDBOX}/tmp"
    export FAKE_CALLS="${SANDBOX}/curl.calls"
    export FAKE_BODY='{"initialized":true,"sealed":false}'
    export FAKE_STATUS=200
    export FAKE_RC=0
    export BS_OPENBAO_ADDR="https://bao.test:8200"
    export BS_OPENBAO_CACERT=""
    export BS_OPENBAO_TOKEN=""
    export BS_OPENBAO_TOKEN_FILE="${SANDBOX}/config/bs/openbao-token"
    export BS_OPENBAO_CURL="${SANDBOX}/tools/curl"
    export BS_OPENBAO_JQ="$(command -v jq)"
    export BS_OPENBAO_BIN="${SANDBOX}/bin/bao"
    export BS_OPENBAO_INIT_FILE="${SANDBOX}/root/openbao-init.json"
    export BS_OPENBAO_CONFIG="${SANDBOX}/etc/openbao.hcl"
    export BS_OPENBAO_DATA_DIR="${SANDBOX}/data"
    export BS_OPENBAO_TLS_DIR="${SANDBOX}/tls"
    export BS_OPENBAO_TLS_MODE="off"
    export BS_OPENBAO_DRY_RUN=0
    export BS_OPENBAO_LATEST_VERSION="9.9.9"
    export BS_OPENBAO_VERSION="9.9.9"
    export FRAMEWORK_DRY_RUN=false
}

sandbox_drop() {
    export PATH="${ORIG_PATH}"
    rm -rf "${SANDBOX:?}"
}

load_wizard() {
    unset BASH_EXECUTION_STRING
    # shellcheck source=/dev/null
    source "${BS_PROJECT_ROOT}/examples/openbao_wizard.sh"
}

main() {
    print_header "OpenBao wizard unit tests / Модульные тесты визарда OpenBao"
    testframework::init
    sandbox_new

    testframework::section "parse and help / разбор аргументов и справка"
    load_wizard
    testframework::assert_equal "" "${OBW_ROLE}" "source does not run main"
    testframework::assert_equal "3" "$(obw::parse_args --help; printf '%s' "$?")" "help returns 3"
    testframework::assert_equal "2" "$(obw::parse_args --role bad; printf '%s' "$?")" "bad role returns 2"
    testframework::assert_equal "2" "$(obw::parse_args --role; printf '%s' "$?")" "missing role value"
    OBW_ROLE="" OBW_PROFILE="" OBW_ADDR="" OBW_VERBOSE=0
    obw::parse_args --role client --profile dev --addr https://bao.test:8200 --dry-run --verbose
    testframework::assert_equal "client" "${OBW_ROLE}" "role parsed"
    testframework::assert_equal "dev" "${OBW_PROFILE}" "profile parsed"
    testframework::assert_equal "https://bao.test:8200" "${OBW_ADDR}" "address parsed"
    testframework::assert_equal "1" "${BS_OPENBAO_DRY_RUN}" "dry-run flag"
    testframework::assert_equal "true" "${FRAMEWORK_DRY_RUN}" "framework dry-run"
    testframework::assert_equal "1" "${OBW_VERBOSE}" "verbose flag"
    export BS_OPENBAO_DRY_RUN=0 FRAMEWORK_DRY_RUN=false
    testframework::assert_command "obw::help | grep -qF -- '--role server|client|both'" "help mentions role"
    testframework::assert_command "obw::help | grep -qF '${BS_OPENBAO_TOKEN_FILE}'" "help mentions token file"

    testframework::section "main help does not start a log / help не создаёт журнал"
    local log="${TMPDIR}/openbao_wizard.log"
    rm -f "${log}"
    local rc=0
    ( obw::main --help ) >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "0" "${rc}" "main --help exits 0"
    testframework::assert_true "! -e '${log}'" "help creates no log"
    rc=0
    ( obw::main --role bad ) >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "2" "${rc}" "main bad role exits 2"
    testframework::assert_true "! -e '${log}'" "bad args create no log"

    testframework::section "summaries / сводки"
    OBW_PROFILE="prod"
    OBW_TOKEN="super-secret-token"
    local summary
    summary="$(obw::server_summary)$(obw::client_summary)"
    testframework::assert_command "printf '%s' '${summary}' | grep -qF '${BS_OPENBAO_INIT_FILE}'" "server summary shows init path"
    testframework::assert_command "printf '%s' '${summary}' | grep -qF '${BS_OPENBAO_TOKEN_FILE}'" "client summary shows token path"
    testframework::assert_command "! printf '%s' '${summary}' | grep -qF 'super-secret-token'" "summary never prints the token"

    testframework::section "client apply / применение клиента"
    OBW_ADDR="https://bao.test:8200"
    OBW_CA=""
    OBW_TOKEN=""
    testframework::assert_command "obw::apply_client" "client without token"
    testframework::assert_true "! -e '${BS_OPENBAO_TOKEN_FILE}'" "no token file without token"
    testframework::assert_command "grep -qF 'sys/health' '${SANDBOX}/curl.calls'" "health requested"
    OBW_TOKEN="client-secret"
    testframework::assert_command "obw::apply_client" "client with token"
    testframework::assert_file_exists "${BS_OPENBAO_TOKEN_FILE}" "token file written"
    testframework::assert_equal "600" "$(stat -c %a "${BS_OPENBAO_TOKEN_FILE}")" "token file mode 0600"
    testframework::assert_equal "client-secret" "$(cat "${BS_OPENBAO_TOKEN_FILE}")" "token persisted"
    testframework::assert_command "grep -qF 'auth/token/lookup-self' '${SANDBOX}/curl.calls'" "token checked"
    testframework::assert_command "! grep -qF 'client-secret' '${SANDBOX}/curl.calls'" "token not in curl argv"
    export FAKE_STATUS=500
    testframework::assert_false "( obw::apply_client ) >/dev/null 2>&1" "client fails on HTTP error"
    export FAKE_STATUS=200

    testframework::section "dev apply dry-run / dev dry-run"
    OBW_PROFILE="dev"
    OBW_SERVER_READY=1
    export BS_OPENBAO_DRY_RUN=1
    local dev_out=""
    dev_out="$( ( obw::apply_server ) 2>&1 )" || true
    testframework::assert_command "printf '%s' '${dev_out}' | grep -qF 'OpenBao dev готов / ready'" "dev dry-run reached dev start"
    testframework::assert_command "printf '%s' '${dev_out}' | grep -qF 'Root token'" "dev root token shown"
    export BS_OPENBAO_DRY_RUN=0

    sandbox_drop
    testframework::summary
}

main "$@"
