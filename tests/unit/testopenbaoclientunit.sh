#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testopenbaoclientunit.sh — unit tests for lib/integration/openbao
# tests/unit/testopenbaoclientunit.sh — модульные тесты lib/integration/openbao

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

load "lib/integration/openbao"

SANDBOX=""
ORIG_PATH="${PATH}"

sandbox_new() {
    SANDBOX="$(mktemp -d)"
    mkdir -p "${SANDBOX}/bin"
    : > "${SANDBOX}/calls"
    : > "${SANDBOX}/stdin"
    cat > "${SANDBOX}/bin/curl" <<'EOF'
#!/bin/bash
: > "${FAKE_CALLS}"
printf '%s\n' "$@" >> "${FAKE_CALLS}"
data=0
for a in "$@"; do [[ "${a}" == "--data-binary" ]] && data=1; done
if (( data == 1 )); then cat > "${FAKE_STDIN}"; fi
printf '%s' "${FAKE_BODY:-}"
printf '\n%s' "${FAKE_STATUS:-200}"
exit "${FAKE_RC:-0}"
EOF
    chmod +x "${SANDBOX}/bin/curl"
    export FAKE_CALLS="${SANDBOX}/calls" FAKE_STDIN="${SANDBOX}/stdin"
    export FAKE_BODY="" FAKE_STATUS=200 FAKE_RC=0
    export BS_OPENBAO_CURL="${SANDBOX}/bin/curl"
    export BS_OPENBAO_JQ="$(command -v jq)"
    export BS_OPENBAO_ADDR="https://bao.test:8200"
    export BS_OPENBAO_TOKEN_FILE="${SANDBOX}/token"
    export BS_OPENBAO_CACERT=""
    export BS_OPENBAO_NAMESPACE=""
    export BS_OPENBAO_TIMEOUT=5
    unset BS_OPENBAO_TOKEN BAO_TOKEN BAO_ADDR BAO_CACERT BAO_NAMESPACE
}

sandbox_drop() {
    export PATH="${ORIG_PATH}"
    rm -rf "${SANDBOX:?}"
}

main() {
    print_header "OpenBao client unit tests / Модульные тесты клиента OpenBao"
    testframework::init
    sandbox_new

    testframework::section "token resolution / выбор токена"
    printf '  file-token  \n' > "${BS_OPENBAO_TOKEN_FILE}"
    openbao::init
    testframework::assert_equal "file-token" "${OPENBAO_TOKEN}" "token file is trimmed"
    export BS_OPENBAO_TOKEN="bs-token"
    export BAO_TOKEN="bao-token"
    openbao::init
    testframework::assert_equal "bs-token" "${OPENBAO_TOKEN}" "BS_ token wins"
    unset BS_OPENBAO_TOKEN
    openbao::init
    testframework::assert_equal "bao-token" "${OPENBAO_TOKEN}" "BAO_ token fallback"
    unset BAO_TOKEN
    openbao::init
    testframework::assert_equal "file-token" "${OPENBAO_TOKEN}" "token file fallback"

    testframework::section "generic request / универсальный запрос"
    export BS_OPENBAO_TOKEN="sekret-token"
    export FAKE_BODY='{"ok":true}'
    export FAKE_STATUS=200
    local out rc=0
    openbao::request GET sys/health > "${SANDBOX}/body" || rc=$?
    out="$(cat "${SANDBOX}/body")"
    testframework::assert_equal "0" "${rc}" "200 is success"
    testframework::assert_equal '{"ok":true}' "${out}" "body returned"
    testframework::assert_equal "200" "${OPENBAO_LAST_STATUS}" "status recorded"
    testframework::assert_command "grep -qF 'https://bao.test:8200/v1/sys/health' '${SANDBOX}/calls'" "URL built"
    testframework::assert_command "grep -qF -- '--config' '${SANDBOX}/calls'" "headers from a 0600 config file"
    testframework::assert_command "! grep -qF 'sekret-token' '${SANDBOX}/calls'" "token not in curl argv"

    testframework::section "errors / ошибки"
    rc=0; openbao::request FETCH sys/health >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${rc}" "bad method rejected"
    export FAKE_STATUS=403
    rc=0; out="$(openbao::request GET sys/health)" || rc=$?
    testframework::assert_equal "${OPENBAO_ERROR_AUTH}" "${rc}" "403 -> auth error"
    testframework::assert_equal '{"ok":true}' "${out}" "error body preserved"
    export FAKE_STATUS=500
    rc=0; openbao::request GET sys/health >/dev/null || rc=$?
    testframework::assert_equal "${OPENBAO_ERROR_HTTP}" "${rc}" "500 -> HTTP error"
    export FAKE_STATUS=200 FAKE_RC=7
    rc=0; openbao::request GET sys/health >/dev/null || rc=$?
    testframework::assert_equal "${OPENBAO_ERROR_HTTP}" "${rc}" "curl failure -> HTTP error"
    export FAKE_RC=0

    testframework::section "health states / состояния health"
    export FAKE_BODY='{"sealed":true}'
    export FAKE_STATUS=503
    rc=0; openbao::health > "${SANDBOX}/body" || rc=$?
    out="$(cat "${SANDBOX}/body")"
    testframework::assert_equal "0" "${rc}" "503 is a valid health answer"
    testframework::assert_equal "503" "${OPENBAO_LAST_STATUS}" "503 recorded"
    testframework::assert_equal '{"sealed":true}' "${out}" "health body"

    testframework::section "dry-run / сухой запуск"
    : > "${SANDBOX}/calls"
    export BS_OPENBAO_DRY_RUN=1
    openbao::request GET sys/health >/dev/null
    testframework::assert_equal "" "$(cat "${SANDBOX}/calls")" "dry-run makes no curl call"
    export BS_OPENBAO_DRY_RUN=0

    testframework::section "KV v2 / KV v2"
    export FAKE_STATUS=200 FAKE_BODY='{"data":{}}'
    rc=0; out="$(openbao::kv::get secret app/db)" || rc=$?
    testframework::assert_equal "0" "${rc}" "kv get ok"
    testframework::assert_command "grep -qF 'secret/data/app/db' '${SANDBOX}/calls'" "kv get path"
    export FAKE_STDIN="${SANDBOX}/stdin"
    openbao::kv::put secret app/db '{"password":"x"}' >/dev/null
    testframework::assert_command "grep -qF 'secret/data/app/db' '${SANDBOX}/calls'" "kv put path"
    testframework::assert_equal '{"data":{"password":"x"}}' "$(cat "${SANDBOX}/stdin")" "kv put body wrapped for KV v2"
    rc=0; openbao::kv::get secret ../etc >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${LIB_ERROR_INVALID_INPUT}" "${rc}" "traversal rejected"
    rc=0; openbao::kv::put secret app 'not-json' >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${OPENBAO_ERROR_JSON}" "${rc}" "invalid JSON rejected"

    testframework::section "mounts / mount"
    : > "${SANDBOX}/stdin"
    openbao::mount::enable secret kv >/dev/null
    testframework::assert_command "grep -qF 'sys/mounts/secret' '${SANDBOX}/calls'" "mount path"
    testframework::assert_equal '{"type":"kv","options":{"version":"2"}}' "$(cat "${SANDBOX}/stdin")" "kv mount defaults to v2"
    : > "${SANDBOX}/stdin"
    openbao::mount::enable pki pki '{"max_lease_ttl":"87600h"}' >/dev/null
    testframework::assert_equal '{"type":"pki","options":{"max_lease_ttl":"87600h"}}' "$(cat "${SANDBOX}/stdin")" "mount options passed"

    testframework::section "policy / политика"
    printf 'path "secret/*" {\n  capabilities = ["read"]\n}\n' > "${SANDBOX}/policy.hcl"
    openbao::policy::write app "${SANDBOX}/policy.hcl" >/dev/null
    testframework::assert_command "grep -qF 'sys/policies/acl/app' '${SANDBOX}/calls'" "policy path"
    testframework::assert_command "grep -qF 'capabilities' '${SANDBOX}/stdin'" "policy body via stdin"
    testframework::assert_command "! grep -qF 'capabilities' '${SANDBOX}/calls'" "policy not in argv"

    testframework::section "login/logout / вход и выход"
    export FAKE_STATUS=200 FAKE_BODY='{"data":{}}'
    rm -f "${BS_OPENBAO_TOKEN_FILE}"
    openbao::login "new-token"
    testframework::assert_file_exists "${BS_OPENBAO_TOKEN_FILE}" "token file written"
    testframework::assert_equal "600" "$(stat -c %a "${BS_OPENBAO_TOKEN_FILE}")" "token file 0600"
    testframework::assert_equal "new-token" "$(cat "${BS_OPENBAO_TOKEN_FILE}")" "token content"
    openbao::logout
    testframework::assert_true "! -e '${BS_OPENBAO_TOKEN_FILE}'" "logout removes token"
    export FAKE_STATUS=403
    rc=0; openbao::login "bad-token" >/dev/null 2>&1 || rc=$?
    testframework::assert_equal "${OPENBAO_ERROR_AUTH}" "${rc}" "bad token rejected"
    testframework::assert_true "! -e '${BS_OPENBAO_TOKEN_FILE}'" "rejected token is not saved"

    sandbox_drop
    testframework::summary
}

main "$@"
