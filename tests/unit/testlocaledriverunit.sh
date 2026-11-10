#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testlocaledriverunit.sh — unit tests for driver::locale:: (lib/system/locale)
# tests/unit/testlocaledriverunit.sh — юнит-тесты driver::locale:: (lib/system/locale)

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

SANDBOX=""
ORIG_PATH="${PATH}"
REAL_CHMOD="$(command -v chmod)"

# fake localectl: статус с System Locale и журнал вызовов / status with locale + call log
fake_localectl() {
    cat > "${SANDBOX}/bin/localectl" <<'EOF'
#!/usr/bin/env bash
printf 'localectl %s\n' "$*" >> "${BS_TEST_CALLS}"
if [[ "$1" == "status" ]]; then
    printf '   System Locale: LANG=en_US.UTF-8\n'
    printf '       VC Keymap: us\n'
fi
exit 0
EOF
    "${REAL_CHMOD}" +x "${SANDBOX}/bin/localectl"
    export BS_TEST_CALLS="${SANDBOX}/calls"
}

sandbox_new() {
    SANDBOX="$(mktemp -d)"
    mkdir -p "${SANDBOX}/bin"
    : > "${SANDBOX}/calls"
    local tool real
    for tool in bash sh cat cp mv rm mkdir chmod grep sed head tail cut tr wc dirname basename mktemp date uname id ls readlink stat awk touch sort env tput ln sleep find; do
        real="$(PATH="${ORIG_PATH}" command -v "${tool}" 2>/dev/null)" || continue
        ln -sf "${real}" "${SANDBOX}/bin/${tool}"
    done
    fake_localectl
    export PATH="${SANDBOX}/bin"
}

sandbox_drop() {
    export PATH="${ORIG_PATH}"
    rm -rf "${SANDBOX:?}"
}

load "lib/system/locale"

main() {
    print_header "locale driver Unit Tests / Юнит-тесты драйвера локали"
    testframework::init

    sandbox_new

    testframework::section "detect / детект"
    testframework::assert_equal $'default\tSystem locale\tlocale' "$(driver::locale::detect)" "detect lists one locale device"

    testframework::section "params / параметры"
    local params
    params="$(driver::locale::params default)"
    testframework::assert_command "grep -q $'^lang\tstring\ten_US.UTF-8' <<< '${params}'" "lang carries current value"

    testframework::section "get / чтение"
    testframework::assert_equal "en_US.UTF-8" "$(driver::locale::get default lang)" "get lang"
    local rc=0
    driver::locale::get default bogus 2>/dev/null || rc=$?
    testframework::assert_equal "2" "${rc}" "unknown param -> E_INVALID"

    testframework::section "set / применение"
    rc=0; driver::locale::set default lang ru_RU.UTF-8 || rc=$?
    testframework::assert_equal "0" "${rc}" "set lang ok"
    testframework::assert_command "grep -qF 'localectl set-locale ru_RU.UTF-8' '${SANDBOX}/calls'" "set-locale dispatched"
    rc=0; driver::locale::set default bogus 1 2>/dev/null || rc=$?
    testframework::assert_equal "2" "${rc}" "unknown param -> E_INVALID"

    testframework::section "snapshot / снимок"
    testframework::assert_command "grep -q $'^lang\ten_US.UTF-8' <<< \"\$(driver::locale::snapshot default)\"" "snapshot has lang with value"

    testframework::section "fallback без localectl / fallback without localectl"
    rm -f "${SANDBOX}/bin/localectl"
    testframework::assert_equal "C.UTF-8" "$(LANG=C.UTF-8 driver::locale::get default lang)" "get lang falls back to LANG"

    sandbox_drop
    testframework::summary
}

main "$@"
