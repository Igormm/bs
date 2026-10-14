#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testsendaudioprogressunit.sh — send_audio.sh: waiting and progress
# tests/unit/testsendaudioprogressunit.sh — send_audio.sh: ожидание и прогресс
#
# Runs examples/send_audio.sh against a fake `curl` that answers slowly (no
# network, no server) in a temporary HOME. Needs ffmpeg and jq; otherwise the
# cases are skipped with a printed reason.
# Запускает examples/send_audio.sh с подставным медленным `curl` (без сети и
# сервера) во временном HOME. Нужны ffmpeg и jq, иначе случаи пропускаются.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

# Fake curl: /v1/models answers at once, a transcription takes $SLOW_S seconds.
# It records its pid so that a test can tell whether it was stopped.
make_fake_curl() {
    local -r dir="${1:?dir required}"
    mkdir -p "${dir}"
    cat > "${dir}/curl" <<'FAKE'
#!/usr/bin/env bash
out=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
    [[ "${args[i]}" == "-o" ]] && out="${args[i+1]}"
done
url="${args[-1]}"
if [[ "${url}" == */v1/models ]]; then
    echo '{"detail":"Not Found"}'
    exit 0
fi
if [[ "${url}" == */v1/audio/transcriptions ]]; then
    echo $$ > "${FAKE_CURL_PID_FILE:-/dev/null}"
    sleep "${SLOW_S:-0}"
    echo '{"text":"hello","segments":[{"start_ms":100,"end_ms":900,"text":"hello"}]}' > "${out}"
    printf '200 0.1 100'
    exit 0
fi
exit 1
FAKE
    chmod +x "${dir}/curl"
}

run_send_audio() {
    local -r tmp="${1:?tmp required}"
    shift
    (
        cd "${tmp}/work"
        HOME="${tmp}/home" PATH="${tmp}/fakebin:${PATH}" TMPDIR="${tmp}" \
            SEND_AUDIO_HEARTBEAT_S=1 SLOW_S="${SLOW_S:-0}" \
            FAKE_CURL_PID_FILE="${tmp}/curl.pid" \
            timeout 120 "${BS_PROJECT_ROOT}/bs" run \
            "${BS_PROJECT_ROOT}/examples/send_audio.sh" \
            --output "${tmp}/out" --log-level INFO "$@"
    ) > "${tmp}/run.log" 2>&1
}

test_waiting_and_progress() {
    local tmp rc=0
    tmp="$(mktemp -d)"
    mkdir -p "${tmp}/work" "${tmp}/home"
    make_fake_curl "${tmp}/fakebin"
    ffmpeg -loglevel error -f lavfi -i sine=d=6 "${tmp}/work/clip.wav"

    SLOW_S=3 run_send_audio "${tmp}" --file clip.wav --segment 3 || rc=$?
    testframework::assert_equal "0" "${rc}" "a slow server does not break the run"
    testframework::assert_command "grep -q 'waiting for the server' '${tmp}/run.log'" "a long wait prints a heartbeat message"
    testframework::assert_command "grep -q 'фрагмент 1/2' '${tmp}/run.log'" "the heartbeat names the chunk"
    testframework::assert_command "grep -q 'progress: 50%' '${tmp}/run.log'" "progress after the first chunk is 50%"
    testframework::assert_command "grep -q 'осталось ≈ 00:00:0' '${tmp}/run.log'" "the remaining time is estimated"
    testframework::assert_command "grep -q 'x от реального времени' '${tmp}/run.log'" "the speed is printed"
    testframework::assert_command "grep -q 'progress: 100%' '${tmp}/run.log'" "progress reaches 100%"

    rm -rf "${tmp}"
}

test_interrupt_stops_curl() {
    local tmp rc=0 pid="" bs_pid curl_pid=""
    tmp="$(mktemp -d)"
    mkdir -p "${tmp}/work" "${tmp}/home"
    make_fake_curl "${tmp}/fakebin"
    ffmpeg -loglevel error -f lavfi -i sine=d=4 "${tmp}/work/clip.wav"

    ( SLOW_S=30 run_send_audio "${tmp}" --file clip.wav --segment 4 ) &
    bs_pid=$!
    # Wait until the fake curl is running, then interrupt the script itself
    local -i n
    for ((n = 0; n < 60; n++)); do
        [[ -s "${tmp}/curl.pid" ]] && break
        sleep 0.5
    done
    curl_pid="$(cat "${tmp}/curl.pid" 2>/dev/null || true)"
    pid="$(pgrep -f "send_audio.sh --output ${tmp}/out" | head -n 1 || true)"
    testframework::assert_true "-n '${curl_pid}' && -n '${pid}'" "the run and its curl are up"
    kill -INT "${pid}" 2>/dev/null || true
    wait "${bs_pid}" 2>/dev/null || rc=$?
    sleep 1
    testframework::assert_false "kill -0 '${curl_pid}'" "Ctrl-C stops the background curl"
    testframework::assert_command "grep -q 'status=stopped' '${tmp}/out/clip/audio.state' || ! test -f '${tmp}/out/clip/audio.state'" "the checkpoint is not left as running"

    rm -rf "${tmp}"
}

main() {
    print_header "Send Audio Progress Unit Tests / Тесты ожидания и прогресса send_audio"

    testframework::init

    testframework::section "Waiting and progress / Ожидание и прогресс"
    if utils::has ffmpeg && utils::has jq && utils::has flock; then
        test_waiting_and_progress
        test_interrupt_stops_curl
    else
        printf 'SKIP: ffmpeg, jq or flock is missing / нет ffmpeg, jq или flock\n'
    fi

    testframework::summary
}

main "$@"
