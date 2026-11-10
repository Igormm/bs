#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testkeyboarddriverunit.sh — unit tests for driver::keyboard:: (lib/system/keyboard)
# tests/unit/testkeyboarddriverunit.sh — юнит-тесты driver::keyboard:: (lib/system/keyboard)

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

# fake localectl: статус с X11-полями и журнал вызовов / status with X11 fields + call log
fake_localectl() {
    cat > "${SANDBOX}/bin/localectl" <<'EOF'
#!/usr/bin/env bash
printf 'localectl %s\n' "$*" >> "${BS_TEST_CALLS}"
if [[ "$1" == "status" ]]; then
    printf '   System Locale: LANG=en_US.UTF-8\n'
    printf '      X11 Layout: us,ru\n'
    printf '       X11 Model: pc105\n'
    printf '     X11 Variant: n/a\n'
    printf '     X11 Options: grp:alt_shift_toggle\n'
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

load "lib/system/keyboard"

main() {
    print_header "keyboard driver Unit Tests / Юнит-тесты драйвера клавиатуры"
    testframework::init

    sandbox_new

    testframework::section "detect / детект"
    testframework::assert_equal $'default\tKeyboard layout\tkeyboard' "$(driver::keyboard::detect)" "detect lists one keyboard device"

    testframework::section "params / параметры"
    local params
    params="$(driver::keyboard::params default)"
    local -i n=0
    local line
    while IFS= read -r line; do
        [[ -n "${line}" ]] && n=$(( n + 1 ))
    done <<< "${params}"
    testframework::assert_equal "4" "${n}" "4 keymap fields"
    testframework::assert_command "grep -q $'^layout\tstring\tus,ru' <<< '${params}'" "layout carries current value"

    testframework::section "get / чтение"
    testframework::assert_equal "us,ru" "$(driver::keyboard::get default layout)" "get layout"
    testframework::assert_equal "pc105" "$(driver::keyboard::get default model)" "get model"
    testframework::assert_equal "" "$(driver::keyboard::get default variant)" "get variant (n/a -> empty)"
    testframework::assert_equal "grp:alt_shift_toggle" "$(driver::keyboard::get default options)" "get options"
    local rc=0
    driver::keyboard::get default bogus 2>/dev/null || rc=$?
    testframework::assert_equal "2" "${rc}" "unknown param -> E_INVALID"

    testframework::section "set / применение"
    rc=0; driver::keyboard::set default layout ru || rc=$?
    testframework::assert_equal "0" "${rc}" "set layout ok"
    testframework::assert_command "grep -qF 'localectl set-keymap ru' '${SANDBOX}/calls'" "layout sets console keymap"
    rc=0; driver::keyboard::set default model pc104 || rc=$?
    testframework::assert_equal "0" "${rc}" "set model ok"
    testframework::assert_command "grep -qF 'localectl set-x11-keymap us,ru pc104  grp:alt_shift_toggle' '${SANDBOX}/calls'" "model keeps other X11 fields"
    rc=0; driver::keyboard::set default bogus 1 2>/dev/null || rc=$?
    testframework::assert_equal "2" "${rc}" "unknown param -> E_INVALID"

    testframework::section "snapshot / снимок"
    testframework::assert_command "grep -q $'^layout\tus,ru' <<< \"\$(driver::keyboard::snapshot default)\"" "snapshot has layout with value"

    sandbox_drop
    testframework::summary
}

main "$@"
