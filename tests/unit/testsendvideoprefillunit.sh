#!/usr/bin/env bs
# shellcheck shell=bash
# tests/unit/testsendvideoprefillunit.sh — send_video.sh: --prefill and the prompt path
# tests/unit/testsendvideoprefillunit.sh — send_video.sh: --prefill и путь промпта
#
# Runs examples/send_video.sh against a fake `curl` that records the request
# body (no network, no server) in a temporary HOME. Needs ffmpeg and jq;
# otherwise the cases are skipped with a printed reason.
# Запускает examples/send_video.sh с подставным `curl`, который сохраняет тело
# запроса (без сети и сервера), во временном HOME. Нужны ffmpeg и jq.

set -euo pipefail

readonly TEST_SCRIPT_DIR="$(bs::script_dir)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

T=""

make_fake_curl() {
    mkdir -p "${T}/fakebin"
    cat > "${T}/fakebin/curl" <<'FAKE'
#!/usr/bin/env bash
out=""; data=""; args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
    [[ "${args[i]}" == "-o" ]] && out="${args[i+1]}"
    [[ "${args[i]}" == "--data-binary" ]] && data="${args[i+1]#@}"
done
url="${args[-1]}"
if [[ "${url}" == */v1/models ]]; then
    echo '{"data":[{"id":"m","max_model_len":24576}]}'
    exit 0
fi
if [[ "${url}" == */v1/chat/completions ]]; then
    cp "${data}" "${CAPTURE_DIR}/payload.json"
    echo '{"choices":[{"message":{"content":"продолжение ответа"},"finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":1}}' > "${out}"
    printf '200 0.1 100'
    exit 0
fi
exit 1
FAKE
    chmod +x "${T}/fakebin/curl"
}

# run_sv <suffix> [send_video args...]  — результат в ${T}/out<suffix>
run_sv() {
    local -r sfx="${1:?suffix}"
    shift
    (
        cd "${T}/work"
        HOME="${T}/home" PATH="${T}/fakebin:${PATH}" TMPDIR="${T}" CAPTURE_DIR="${T}" \
            timeout 120 "${BS_PROJECT_ROOT}/bs" run \
            "${BS_PROJECT_ROOT}/examples/send_video.sh" \
            --file clip.mp4 --segment 0 --output "${T}/out${sfx}" --log-level ERROR "$@"
    ) > "${T}/run${sfx}.log" 2>&1
}

user_text() { jq -r '.messages[] | select(.role=="user") | .content[] | select(.type=="text") | .text' "${T}/payload.json"; }

test_prompt_paths() {
    T="$(mktemp -d)"
    mkdir -p "${T}/work" "${T}/home"
    make_fake_curl
    ffmpeg -loglevel error -f lavfi -i testsrc=d=2:s=64x64:r=5 -pix_fmt yuv420p "${T}/work/clip.mp4"
    printf 'Опиши фрагмент.\nОтвет — целиком на русском языке.\n' > "${T}/prompt.txt"

    run_sv A --prompt-file "${T}/prompt.txt"
    testframework::assert_equal "$(<"${T}/prompt.txt")" "$(user_text)" "--prompt-file: the text reaches the server unchanged"
    testframework::assert_equal '["user"]' "$(jq -c '[.messages[].role]' "${T}/payload.json")" "without --system/--prefill only the user message is sent"
    testframework::assert_equal "false" "$(jq 'has("continue_final_message")' "${T}/payload.json")" "without --prefill no continue flags are sent"

    run_sv B --prompt "короткий" --prompt-file "${T}/prompt.txt"
    testframework::assert_equal "$(<"${T}/prompt.txt")" "$(user_text)" "--prompt-file wins over --prompt"

    run_sv C --prompt-file "${T}/prompt.txt" --system "Отвечай по-русски"
    testframework::assert_equal '["system","user"]' "$(jq -c '[.messages[].role]' "${T}/payload.json")" "--system adds a system message"
    testframework::assert_equal "Отвечай по-русски" "$(jq -r '.messages[0].content' "${T}/payload.json")" "the system text arrives unchanged"
    rm -rf "${T}"
}

test_prefill() {
    T="$(mktemp -d)"
    mkdir -p "${T}/work" "${T}/home"
    make_fake_curl
    ffmpeg -loglevel error -f lavfi -i testsrc=d=2:s=64x64:r=5 -pix_fmt yuv420p "${T}/work/clip.mp4"
    printf 'Опиши фрагмент.\n' > "${T}/prompt.txt"

    run_sv P --prompt-file "${T}/prompt.txt" --prefill 'Описание на русском: '
    testframework::assert_equal '["user","assistant"]' "$(jq -c '[.messages[].role]' "${T}/payload.json")" "--prefill: the last message is the assistant's"
    testframework::assert_equal 'Описание на русском: ' "$(jq -r '.messages[-1].content' "${T}/payload.json")" "--prefill: the prefix arrives unchanged (with the trailing space)"
    testframework::assert_equal "true" "$(jq '.continue_final_message' "${T}/payload.json")" "--prefill: continue_final_message is true"
    testframework::assert_equal "false" "$(jq '.add_generation_prompt' "${T}/payload.json")" "--prefill: add_generation_prompt is false"
    testframework::assert_equal "$(<"${T}/prompt.txt")" "$(user_text)" "--prefill: the user prompt is untouched"
    testframework::assert_command "grep -q 'Описание на русском: продолжение ответа' '${T}/outP/clip/video.txt'" "the report holds the prefix plus the continuation"

    # Тот же прогон без/с другим prefill — разные «паспорта»
    run_sv P --prompt-file "${T}/prompt.txt" --prefill 'Другое: ' || true
    testframework::assert_command "grep -qi 'another run\|другой прогон\|differs' '${T}/runP.log'" "a different prefill is a different run (needs --restart)"
    rm -rf "${T}"
}

main() {
    print_header "Send Video Prefill Unit Tests / Тесты --prefill и пути промпта send_video"

    testframework::init

    testframework::section "Prompt paths / Пути промпта"
    if utils::has ffmpeg && utils::has jq && utils::has flock; then
        test_prompt_paths
        test_prefill
    else
        printf 'SKIP: ffmpeg, jq or flock is missing / нет ffmpeg, jq или flock\n'
    fi

    testframework::summary
}

main "$@"
