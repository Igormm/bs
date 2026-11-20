#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testvkmusictuiunit.sh — vkmusic_tui state helpers (selection, viewport, modes) without a terminal
# tests/unit/testvkmusictuiunit.sh — служебное состояние vkmusic_tui (выбор, viewport, режимы) без терминала

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Изолированный HOME: объектный кеш пишет в $HOME/.cache/bs/cache / Isolated HOME
T="$(mktemp -d)"
export HOME="${T}/home"
mkdir -p "${HOME}"

load "lib/integration/vkmusic_tui"

# Мок vkapi::api_call: две рекомендации / Mock: two recommended tracks
vkapi::api_call() {
    case "${1:-}" in
        audio.getRecommendations)
            printf '%s\n' '{"count":2,"items":[{"id":2,"owner_id":2,"artist":"Reco Artist","title":"Reco Song","duration":200,"url":"http://example.com/rec.mp3"},{"id":3,"owner_id":3,"artist":"Pop Artist","title":"Pop Song","duration":210,"url":"http://example.com/pop.mp3"}]}'
            ;;
        *)
            printf '%s\n' '{"count":0,"items":[]}'
            ;;
    esac
}

# tui::size без терминала не трогаем: задаём дефолтные размеры вручную / tui::size is
# not run without a terminal: set the default sizes by hand
: "${TUI_LINES:=24}" "${TUI_COLS:=80}"

main() {
    testframework::section "Load and collect / Загрузка и коллекция"
    VKM_MODE=reco
    vkm_tui::__load
    testframework::assert_equal "2" "$(vkmusic::track_count)" "reco collects two tracks into objects"
    testframework::assert_equal "Reco Artist" "$(vkmusic::track_field 0 artist)" "track 0 artist is typed"
    testframework::assert_equal "200" "$(vkmusic::track_field 0 duration)" "track 0 duration is typed"
    testframework::assert_equal "Reco Artist - Reco Song [03:20] (ID: 2)" "$(vkmusic::track_line 0)" "track_line renders the summary"

    testframework::section "Selection and viewport / Выбор и viewport"
    vkm_tui::__move 1
    testframework::assert_equal "1" "${VKM_SEL}" "move down selects 1"
    vkm_tui::__move 5
    testframework::assert_equal "1" "${VKM_SEL}" "selection is clamped to the last track"
    vkm_tui::__move -10
    testframework::assert_equal "0" "${VKM_SEL}" "selection is clamped to the first track"
    vkm_tui::__page down
    testframework::assert_equal "1" "${VKM_SEL}" "a page down is clamped to the list"

    testframework::section "Empty list / Пустой список"
    vkm_tui::__mode user
    testframework::assert_equal "0" "$(vkmusic::track_count)" "user mode with an empty mock yields zero tracks"
    testframework::assert_equal "0" "${VKM_SEL}" "selection resets on an empty list"
    testframework::assert_equal "0" "${VKM_BASE}" "viewport resets on an empty list"

    testframework::section "Modes / Режимы"
    vkm_tui::__mode popular
    testframework::assert_equal "popular" "${VKM_MODE}" "__mode switches the list mode"
    testframework::assert_equal "0" "${VKM_SEL}" "__mode resets the selection"

    rm -rf "${T}"
    testframework::summary
}

main "$@"
