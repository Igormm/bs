#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testsendcommonunit.sh — Unit tests for examples/send_common.sh
# tests/unit/testsendcommonunit.sh — Модульные тесты для examples/send_common.sh
#
# The run directory of send_video.sh / send_audio.sh: naming, creation,
# the key=value files, the lock and the checkpoint consistency helpers.
# Каталог прогона send_video.sh / send_audio.sh: имя, создание, файлы
# key=value, блокировка и функции согласования с точкой остановки.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
load "lib/io/streams"
source "${BS_PROJECT_ROOT}/examples/send_common.sh"

test_dir_for() {
    testframework::assert_equal "/r/mam" "$(sendrun::dir_for /r /x/mam.mp4)" "dir name is the file name without extension"
    testframework::assert_equal "/r/a.b" "$(sendrun::dir_for /r/ a.b.mkv)" "only the last extension is cut, trailing slash ignored"
    testframework::assert_equal "./noext" "$(sendrun::dir_for . noext)" "a name without extension is kept"
}

test_ensure_dir() {
    local tmp rc
    tmp="$(mktemp -d)"

    rc=0; sendrun::ensure_dir "${tmp}/new/deep" || rc=$?
    testframework::assert_equal "1" "${rc}" "ensure_dir reports a created directory"
    testframework::assert_command "test -d '${tmp}/new/deep'" "ensure_dir creates the whole path"

    rc=0; sendrun::ensure_dir "${tmp}/new/deep" || rc=$?
    testframework::assert_equal "0" "${rc}" "ensure_dir reports an existing directory"

    printf 'old report\n' > "${tmp}/file"
    rc=0; sendrun::ensure_dir "${tmp}/file/mam" || rc=$?
    testframework::assert_equal "2" "${rc}" "ensure_dir fails when a file is in the way"
    testframework::assert_true "'$(sendrun::explain_dir_error "${tmp}/file/mam")' =~ это\\ файл" "the reason names the file in the way"
    testframework::assert_equal "old report" "$(cat "${tmp}/file")" "the file in the way is left intact"

    rm -rf "${tmp}"
}

test_kv_files() {
    local tmp
    local -A out=() in=([a]="1" [b]="two words" [c]=$'line1\nline2')
    tmp="$(mktemp -d)"

    sendrun::kv_write "${tmp}/p" in a b c
    testframework::assert_command "test ! -e '${tmp}/p.tmp.$$'" "kv_write leaves no temp file"
    sendrun::kv_read "${tmp}/p" out
    testframework::assert_equal "1" "${out[a]}" "kv round trip: number"
    testframework::assert_equal "two words" "${out[b]}" "kv round trip: value with a space"
    testframework::assert_equal "line1 line2" "${out[c]}" "a value never carries a line break"
    testframework::assert_false "sendrun::kv_read '${tmp}/missing' out" "kv_read of a missing file fails"

    rm -rf "${tmp}"
}

test_checkpoint_files() {
    local tmp cut
    tmp="$(mktemp -d)"
    printf '0123456789' > "${tmp}/f"

    testframework::assert_equal "10" "$(sendrun::size "${tmp}/f")" "size of a file"
    testframework::assert_equal "0" "$(sendrun::size "${tmp}/none")" "size of a missing file is 0"

    cut="$(sendrun::truncate_to "${tmp}/f" 10)"
    testframework::assert_equal "0" "${cut}" "truncate_to keeps a consistent file"

    cut="$(sendrun::truncate_to "${tmp}/f" 6)"
    testframework::assert_equal "4" "${cut}" "truncate_to reports the bytes it cut"
    testframework::assert_equal "012345" "$(cat "${tmp}/f")" "data after the checkpoint is cut off"

    testframework::assert_false "sendrun::truncate_to '${tmp}/f' 99" "a file shorter than the checkpoint is rejected"
    testframework::assert_equal "012345" "$(cat "${tmp}/f")" "a rejected file is not touched"

    rm -rf "${tmp}"
}

test_lock() {
    if ! utils::has flock; then
        testframework::assert_true "true" "lock test skipped (no flock)"
        return 0
    fi
    local tmp
    tmp="$(mktemp -d)"

    # The lock is held by the process that took it: try from another one
    sendrun::lock "${tmp}" video
    testframework::assert_command "test -f '${tmp}/.video.lock'" "lock file is created"
    testframework::assert_false "bash -c 'exec 9>> \"${tmp}/.video.lock\"; flock -n 9'" "a second process cannot take the same lock"
    testframework::assert_command "bash -c 'exec 9>> \"${tmp}/.audio.lock\"; flock -n 9'" "video and audio locks are independent"

    rm -rf "${tmp}"
}

test_timecode() {
    testframework::assert_equal "00:00:00.000" "$(sendrun::timecode_ms 0)" "timecode of zero"
    testframework::assert_equal "01:02:03.045" "$(sendrun::timecode_ms 3723045)" "timecode with milliseconds"
    testframework::assert_equal "00:00:00.000" "$(sendrun::timecode_ms abc)" "a non-number gives zero"
}

main() {
    print_header "Send Common Unit Tests / Модульные тесты send_common"

    testframework::init

    testframework::section "Run directory / Каталог прогона"
    test_dir_for
    test_ensure_dir

    testframework::section "State files / Файлы состояния"
    test_kv_files
    test_checkpoint_files

    testframework::section "Lock and time / Блокировка и время"
    test_lock
    test_timecode

    testframework::summary
}

main "$@"
