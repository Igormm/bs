#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testauditsystemtimelocaleunit.sh — scenario-audit regression tests for
# lib/system/{time,locale,keyboard,system}
# tests/unit/testauditsystemtimelocaleunit.sh — регрессионные тесты сценарного аудита
# lib/system/{time,locale,keyboard,system}
#
# Всё в песочнице: подставные команды, пути конфигов через переменные окружения.
# Everything runs in a sandbox: fake commands, config paths via environment variables.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

SANDBOX=""
ORIG_PATH="${PATH}"
REAL_CHMOD="$(command -v chmod)"

eq() { testframework::assert_equal "$@"; }

# check NAME CMD... — зелёный, если команда успешна / green when the command succeeds
check() {
    local -r name="${1}"
    shift
    if "$@"; then
        testframework::assert_true "true" "${name}"
    else
        testframework::assert_true "false" "${name}"
    fi
}

# fake NAME [EXIT] [STDOUT] — подставная команда, пишет вызов в $SANDBOX/calls
# fake NAME [EXIT] [STDOUT] — fake command, records the call in $SANDBOX/calls
fake() {
    local -r name="${1}" rc="${2:-0}" out="${3:-}"
    rm -f "${SANDBOX}/bin/${name}"    # never write through a symlink to a real tool / не писать через симлинк в настоящую утилиту
    printf '#!/bin/bash\necho "%s $*" >> "%s/calls"\n[ -z %q ] || printf "%%s\\n" %q\nexit %s\n' \
        "${name}" "${SANDBOX}" "${out}" "${out}" "${rc}" > "${SANDBOX}/bin/${name}"
    "${REAL_CHMOD}" +x "${SANDBOX}/bin/${name}"
}

# PATH: только подставные команды и белый список базовых утилит (симлинки). Настоящих
# systemctl/ufw/useradd/localectl в PATH нет — тест не может тронуть систему.
# PATH: fakes plus a whitelist of base tools (symlinks) only. No real
# systemctl/ufw/useradd/localectl in PATH — the test cannot touch the system.
sandbox_new() {
    SANDBOX="$(mktemp -d)"
    mkdir -p "${SANDBOX}/bin"
    : > "${SANDBOX}/calls"
    local tool real
    for tool in bash sh cat cp mv rm mkdir chmod grep sed head tail cut tr wc dirname basename mktemp date uname id ls readlink stat awk touch sort env tput ln sleep find; do
        real="$(PATH="${ORIG_PATH}" command -v "${tool}" 2>/dev/null)" || continue
        ln -sf "${real}" "${SANDBOX}/bin/${tool}"
    done
    export PATH="${SANDBOX}/bin"
}

sandbox_drop() {
    export PATH="${ORIG_PATH}"
    rm -rf "${SANDBOX:?}"
}

load "lib/system/time"
load "lib/system/locale"
load "lib/system/keyboard"
load "lib/system/system"

main() {
    print_header "Time/locale/keyboard audit tests / Тесты аудита времени, локали, клавиатуры"
    testframework::init
    local rc out

    testframework::section "timezone: ../ и абсолютные пути отвергаются / traversal rejected"
    sandbox_new
    mkdir -p "${SANDBOX}/zi/Europe"
    : > "${SANDBOX}/zi/Europe/Moscow"
    : > "${SANDBOX}/zi/zone.tab"
    export BS_ZONEINFO_DIR="${SANDBOX}/zi" BS_LOCALTIME="${SANDBOX}/localtime"
    rc=0; system::time::timezone "../../../etc/passwd" >/dev/null 2>&1 || rc=$?
    check "traversal rejected" test "${rc}" -ne 0
    rc=0; system::time::timezone "zone tab" >/dev/null 2>&1 || rc=$?
    check "name with a space rejected" test "${rc}" -ne 0

    testframework::section "timezone: сбой timedatectl не выдаётся за успех / timedatectl failure"
    fake timedatectl 1
    rc=0; system::time::timezone "Europe/Moscow" >/dev/null 2>&1 || rc=$?
    check "timedatectl failure -> non-zero" test "${rc}" -ne 0
    sandbox_drop

    testframework::section "timezone: без timedatectl — симлинк / fallback symlink"
    sandbox_new
    mkdir -p "${SANDBOX}/zi/Europe"
    : > "${SANDBOX}/zi/Europe/Moscow"
    export BS_ZONEINFO_DIR="${SANDBOX}/zi" BS_LOCALTIME="${SANDBOX}/localtime" BS_TIMEZONE_FILE="${SANDBOX}/timezone"
    system::time::timezone "Europe/Moscow" >/dev/null 2>&1
    eq "${SANDBOX}/zi/Europe/Moscow" "$(readlink "${SANDBOX}/localtime")" "localtime points to the zone file"
    sandbox_drop
    unset BS_ZONEINFO_DIR BS_LOCALTIME BS_TIMEZONE_FILE

    testframework::section "time::set: NTP включён -> ошибка видна / NTP on -> error is visible"
    sandbox_new
    fake timedatectl 1
    rc=0; system::time::set "2030-01-01 00:00:00" >/dev/null 2>&1 || rc=$?
    check "set-time failure -> non-zero" test "${rc}" -ne 0
    sandbox_drop

    testframework::section "time::ntp: неверное значение не выключает NTP / invalid value keeps NTP"
    sandbox_new
    fake timedatectl 0
    rc=0; system::time::ntp "yes" >/dev/null 2>&1 || rc=$?
    check "'yes' rejected" test "${rc}" -ne 0
    eq "" "$(cat "${SANDBOX}/calls")" "timedatectl not called for an invalid value"
    sandbox_drop

    testframework::section "ntp без служб -> ошибка / no NTP service -> error"
    sandbox_new
    rc=0; system::time::ntp "true" >/dev/null 2>&1 || rc=$?
    check "no ntpd/chronyd -> non-zero" test "${rc}" -ne 0
    sandbox_drop

    testframework::section "locale::set: сбой localectl / localectl failure"
    sandbox_new
    fake localectl 1
    rc=0; system::locale::set "xx_XX.UTF-8" >/dev/null 2>&1 || rc=$?
    check "localectl failure -> non-zero" test "${rc}" -ne 0
    rc=0; system::locale::set "en_US.UTF-8; reboot" >/dev/null 2>&1 || rc=$?
    check "locale with shell chars rejected" test "${rc}" -ne 0
    sandbox_drop

    testframework::section "locale::set: без localectl, сохраняются остальные строки / other lines kept"
    sandbox_new
    printf '# ru_RU.UTF-8 UTF-8\n# en_US.UTF-8 UTF-8\n# en_USxUTF-8 UTF-8\n' > "${SANDBOX}/locale.gen"
    printf 'LANG=C\nLC_TIME=ru_RU.UTF-8\n' > "${SANDBOX}/default_locale"
    fake locale-gen 0
    BS_LOCALE_GEN="${SANDBOX}/locale.gen" BS_DEFAULT_LOCALE="${SANDBOX}/default_locale" \
        system::locale::set "en_US.UTF-8" >/dev/null 2>&1
    eq "1" "$(grep -c '^en_US.UTF-8 UTF-8' "${SANDBOX}/locale.gen")" "requested locale uncommented"
    eq "0" "$(grep -c '^en_USxUTF-8' "${SANDBOX}/locale.gen")" "dot is literal, lookalike untouched"
    eq "LANG=en_US.UTF-8" "$(head -1 "${SANDBOX}/default_locale")" "LANG replaced"
    eq "LC_TIME=ru_RU.UTF-8" "$(sed -n 2p "${SANDBOX}/default_locale")" "LC_TIME kept"
    sandbox_drop

    testframework::section "locale-gen падает -> ошибка / locale-gen fails -> error"
    sandbox_new
    printf '# en_US.UTF-8 UTF-8\n' > "${SANDBOX}/locale.gen"
    fake locale-gen 1
    rc=0
    BS_LOCALE_GEN="${SANDBOX}/locale.gen" BS_DEFAULT_LOCALE="${SANDBOX}/none" system::locale::set "en_US.UTF-8" >/dev/null 2>&1 || rc=$?
    check "locale-gen failure -> non-zero" test "${rc}" -ne 0
    sandbox_drop

    testframework::section "keyboard::model: set-x11-keymap с текущей раскладкой / keeps current layout"
    sandbox_new
    printf '#!/bin/bash\necho "localectl $*" >> "%s/calls"\nif [ "$1" = status ]; then\n  echo "   X11 Layout: us,ru"\n  echo "    X11 Model: pc105"\n  echo "  X11 Variant: n/a"\n  echo "  X11 Options: grp:alt_shift_toggle"\nfi\nexit 0\n' "${SANDBOX}" > "${SANDBOX}/bin/localectl"
    chmod +x "${SANDBOX}/bin/localectl"
    system::keyboard::model "pc104" >/dev/null 2>&1
    check "set-x11-keymap with new model, old layout/options" grep -qF 'localectl set-x11-keymap us,ru pc104  grp:alt_shift_toggle' "${SANDBOX}/calls"
    check "bogus --keymap-model flag is gone" test "$(grep -c -- '--keymap-model' "${SANDBOX}/calls")" -eq 0
    sandbox_drop

    testframework::section "keyboard::layout: сбой localectl / failure"
    sandbox_new
    fake localectl 1
    rc=0; system::keyboard::layout "ru" >/dev/null 2>&1 || rc=$?
    check "set-keymap failure -> non-zero" test "${rc}" -ne 0
    sandbox_drop
    sandbox_new
    rc=0; system::keyboard::layout "ru" >/dev/null 2>&1 || rc=$?
    check "no tool at all -> non-zero" test "${rc}" -ne 0
    sandbox_drop

    testframework::section "ntp_servers: валидация / validation"
    sandbox_new
    rc=0; system::time::ntp_servers >/dev/null 2>&1 || rc=$?
    check "no args rejected" test "${rc}" -ne 0
    rc=0; system::time::ntp_servers "a;rm -rf" >/dev/null 2>&1 || rc=$?
    check "server with shell chars rejected" test "${rc}" -ne 0
    rc=0; system::time::ntp_servers "has space" >/dev/null 2>&1 || rc=$?
    check "server with a space rejected" test "${rc}" -ne 0
    sandbox_drop

    testframework::section "ntp_servers: timesyncd NTP= заменяется, остальное остаётся / replaced"
    sandbox_new
    printf '[Time]\nNTP=old.pool.ntp.org\nFallbackNTP=fallback.ntp.org\n' > "${SANDBOX}/ts.conf"
    BS_NTP_CONF="${SANDBOX}/ts.conf" system::time::ntp_servers "pool.ntp.org" "ru.pool.ntp.org" >/dev/null 2>&1
    eq "NTP=pool.ntp.org ru.pool.ntp.org" "$(grep '^NTP=' "${SANDBOX}/ts.conf")" "NTP= replaced"
    eq "FallbackNTP=fallback.ntp.org" "$(grep '^FallbackNTP=' "${SANDBOX}/ts.conf")" "unrelated line kept"
    sandbox_drop

    testframework::section "ntp_servers: timesyncd без NTP= — вставка после [Time] / inserted"
    sandbox_new
    printf '[Time]\n# comment\n' > "${SANDBOX}/ts2.conf"
    BS_NTP_CONF="${SANDBOX}/ts2.conf" system::time::ntp_servers "pool.ntp.org" >/dev/null 2>&1
    eq "NTP=pool.ntp.org" "$(grep '^NTP=' "${SANDBOX}/ts2.conf")" "NTP= inserted"
    eq "1" "$(grep -c '^\[Time\]' "${SANDBOX}/ts2.conf")" "single [Time]"
    sandbox_drop

    testframework::section "ntp_servers: chrony — server/pool заменяются, остальное остаётся / kept"
    sandbox_new
    printf 'server old1.example\npool old2.example\ndriftfile /var/lib/chrony/drift\n' > "${SANDBOX}/chrony.conf"
    BS_NTP_CONF="${SANDBOX}/chrony.conf" system::time::ntp_servers "pool.ntp.org" "time.cloudflare.com" >/dev/null 2>&1
    eq "0" "$(grep -c 'old1.example\|old2.example' "${SANDBOX}/chrony.conf")" "old servers gone"
    eq "1" "$(grep -c '^server pool.ntp.org$' "${SANDBOX}/chrony.conf")" "new server"
    eq "driftfile /var/lib/chrony/drift" "$(grep '^driftfile' "${SANDBOX}/chrony.conf")" "unrelated line kept"
    sandbox_drop

    testframework::summary
}

main "$@"
