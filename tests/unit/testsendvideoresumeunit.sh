#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testsendvideoresumeunit.sh — send_video.sh: resume safety
# tests/unit/testsendvideoresumeunit.sh — send_video.sh: безопасность возобновления
#
# Runs examples/send_video.sh against a fake `curl` (no network, no server)
# in a temporary HOME. Needs ffmpeg and jq; otherwise the cases are skipped
# with a printed reason.
# Запускает examples/send_video.sh с подставным `curl` (без сети и сервера)
# во временном HOME. Нужны ffmpeg и jq, иначе случаи пропускаются с причиной.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

# Fake curl: /v1/models and /v1/chat/completions answer, nothing else
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
    echo '{"data":[{"id":"m","max_model_len":1000}]}'
    exit 0
fi
if [[ "${url}" == */v1/chat/completions ]]; then
    echo '{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":2}}' > "${out}"
    printf '200 0.1 100'
    exit 0
fi
exit 1
FAKE
    chmod +x "${dir}/curl"
}

run_send_video() {
    local -r tmp="${1:?tmp required}"
    shift
    (
        cd "${tmp}/work"
        HOME="${tmp}/home" PATH="${tmp}/fakebin:${PATH}" TMPDIR="${tmp}" \
            timeout 120 "${BS_PROJECT_ROOT}/bs" run \
            "${BS_PROJECT_ROOT}/examples/send_video.sh" \
            --output "${tmp}/out" --log-level ERROR "$@"
    ) > "${tmp}/run.log" 2>&1
}

test_resume_keeps_input_file() {
    local tmp rc=0
    tmp="$(mktemp -d)"
    mkdir -p "${tmp}/work" "${tmp}/home"
    make_fake_curl "${tmp}/fakebin"
    ffmpeg -loglevel error -f lavfi -i testsrc=d=2:s=64x64:r=5 \
        -pix_fmt yuv420p "${tmp}/work/clip.mp4"

    run_send_video "${tmp}" --file clip.mp4 --segment 0 || rc=$?
    testframework::assert_equal "0" "${rc}" "first run (segment 0) succeeds"
    testframework::assert_command "test -f '${tmp}/out/clip/video.state'" "checkpoint is written"

    # Ctrl-C during the summary leaves status=stopped with every chunk done
    sed -i 's/^status=.*/status=stopped/' "${tmp}/out/clip/video.state"
    rc=0; run_send_video "${tmp}" --file clip.mp4 --segment 0 || rc=$?
    testframework::assert_equal "0" "${rc}" "resume of a fully processed run succeeds"
    testframework::assert_command "test -f '${tmp}/work/clip.mp4'" "resume with segment 0 does not delete the user's video"

    rm -rf "${tmp}"
}

test_file_without_extension() {
    local tmp rc=0
    tmp="$(mktemp -d)"
    mkdir -p "${tmp}/work" "${tmp}/home"
    make_fake_curl "${tmp}/fakebin"
    ffmpeg -loglevel error -f lavfi -i testsrc=d=2:s=64x64:r=5 \
        -pix_fmt yuv420p -f mp4 "${tmp}/work/noext"

    run_send_video "${tmp}" --file "${tmp}/work/noext" --segment 1 || rc=$?
    testframework::assert_equal "0" "${rc}" "a file name without extension is processed"
    testframework::assert_command "grep -q 'Фрагмент 1/' '${tmp}/out/noext/video.txt'" "the report has the chunk entry"

    rm -rf "${tmp}"
}

main() {
    print_header "Send Video Resume Unit Tests / Тесты возобновления send_video"

    testframework::init

    testframework::section "Resume safety / Безопасность возобновления"
    if utils::has ffmpeg && utils::has jq && utils::has flock; then
        test_resume_keeps_input_file
        test_file_without_extension
    else
        printf 'SKIP: ffmpeg, jq or flock is missing / нет ffmpeg, jq или flock\n'
    fi

    testframework::summary
}

main "$@"
