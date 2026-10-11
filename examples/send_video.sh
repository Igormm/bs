#!/usr/bin/env bs
# shellcheck shell=bash
#
# send_video.sh - отправка видео на локальный vLLM-сервер и получение ответа модели.
#
# Видео кодируется в base64 и уходит в /v1/chat/completions как content-блок
# "video_url" (data URI). Нужна мультимодальная (VLM) модель с поддержкой видео.
#
# Параметры (все описаны в --help):
#   Файл:    --file
#   Сервер:  --host, --port, --model, --timeout
#   Промпт:  --prompt, --prompt-file, --system, --temperature, --max-tokens
#
# Значения по умолчанию можно менять переменными окружения:
#   VIDEO_SERVER_HOST (по умолчанию 192.168.1.83), VIDEO_SERVER_PORT (8000)
#
# Примеры:
#   ./bs run send_video.sh --file ~/clip.mp4
#   ./bs run send_video.sh --file ~/clip.mp4 --host 192.168.1.90 --port 8001
#   ./bs run send_video.sh --file ~/clip.mp4 --prompt "Опиши видео по таймкодам"
#   ./bs run send_video.sh --file ~/clip.mp4 --prompt-file ~/prompt.txt --temperature 0.2
#
# Зависимости: curl, jq, base64 (GNU coreutils).

load "core/args"
load "lib/io/streams"

# Вывод ошибки в stderr и выход
send_video::die() {
    io::streams::print "ERROR: $*" >&2
    exit 1
}

# Проверка наличия обязательных утилит
send_video::check_deps() {
    local cmd
    for cmd in curl jq base64; do
        command -v "${cmd}" >/dev/null 2>&1 \
            || send_video::die "не найдена утилита: ${cmd}"
    done
}

# MIME-тип по расширению файла
send_video::mime() {
    case "${1,,}" in
        *.mp4|*.m4v) printf 'video/mp4' ;;
        *.webm)      printf 'video/webm' ;;
        *.mkv)       printf 'video/x-matroska' ;;
        *.mov)       printf 'video/quicktime' ;;
        *.avi)       printf 'video/x-msvideo' ;;
        *)           printf 'video/mp4' ;;
    esac
}

main() {
    local -r default_host="${VIDEO_SERVER_HOST:-192.168.1.83}"
    local -r default_port="${VIDEO_SERVER_PORT:-8000}"
    local -r default_prompt="Опиши, что происходит в этом видео."

    # --- Файл ---
    args::flag file value
    args::flag_describe file "Путь к видеофайлу (обязательный параметр)"

    # --- Сервер ---
    args::flag host value "${default_host}"
    args::flag port value "${default_port}"
    args::flag model value
    args::flag timeout value 600
    args::flag_describe host "IP или имя сервера (по умолчанию ${default_host}, env: VIDEO_SERVER_HOST)"
    args::flag_describe port "Порт vLLM (по умолчанию ${default_port}, env: VIDEO_SERVER_PORT)"
    args::flag_describe model "ID модели (по умолчанию первая из /v1/models)"
    args::flag_describe timeout "Таймаут запроса в секундах (по умолчанию 600)"

    # --- Промпт ---
    args::flag prompt value "${default_prompt}"
    args::flag prompt-file value
    args::flag system value
    args::flag temperature value 0.3
    args::flag max-tokens value 2048
    args::flag_describe prompt "Текст запроса к модели"
    args::flag_describe prompt-file "Файл с текстом запроса (имеет приоритет над --prompt)"
    args::flag_describe system "Системный промпт (роль модели), необязательно"
    args::flag_describe temperature "Температура генерации, 0-2 (по умолчанию 0.3)"
    args::flag_describe max-tokens "Лимит токенов ответа (по умолчанию 2048)"

    args::require "$@"

    local -r file="${ARGS_FLAGS["file"]:-}"
    local -r host="${ARGS_FLAGS["host"]:-${default_host}}"
    local -r port="${ARGS_FLAGS["port"]:-${default_port}}"
    local -r timeout="${ARGS_FLAGS["timeout"]:-600}"
    local -r system_prompt="${ARGS_FLAGS["system"]:-}"
    local -r temperature="${ARGS_FLAGS["temperature"]:-0.3}"
    local -r max_tokens="${ARGS_FLAGS["max-tokens"]:-2048}"
    local -r prompt_file="${ARGS_FLAGS["prompt-file"]:-}"
    local prompt="${ARGS_FLAGS["prompt"]:-${default_prompt}}"
    local model="${ARGS_FLAGS["model"]:-}"
    local -r base="http://${host}:${port}"

    send_video::check_deps

    [[ -n "${file}" ]] || send_video::die "укажите видео: --file /путь/к/видео.mp4"
    [[ -f "${file}" ]] || send_video::die "файл не найден: ${file}"

    if [[ -n "${prompt_file}" ]]; then
        [[ -f "${prompt_file}" ]] || send_video::die "файл промпта не найден: ${prompt_file}"
        prompt="$(<"${prompt_file}")"
    fi

    # --- 1. Проверка доступности сервера -----------------------------------
    io::streams::print "Проверяю сервер ${base} ..."
    local models_json
    if ! models_json="$(curl -fsS --max-time 10 "${base}/v1/models" 2>&1)"; then
        send_video::die "сервер недоступен: ${base} (${models_json})"
    fi

    if [[ -z "${model}" ]]; then
        model="$(jq -r '.data[0].id // empty' <<<"${models_json}")"
        [[ -n "${model}" ]] || send_video::die "не удалось определить модель из /v1/models"
    fi
    io::streams::print "Модель: ${model}"

    # --- 2. Подготовка данных (во временной папке, чистится при выходе) -----
    local tmp
    tmp="$(mktemp -d)" || send_video::die "не удалось создать временную папку"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" EXIT

    local mime size_mb
    mime="$(send_video::mime "${file}")"
    size_mb=$(( $(stat -c %s "${file}") / 1024 / 1024 ))
    io::streams::print "Кодирую видео (${size_mb} МБ, ${mime}) ..."

    # Видео и тело запроса идут через файлы, а не через аргументы командной
    # строки: base64 большого видео не помещается в лимит длины аргумента.
    printf 'data:%s;base64,' "${mime}" > "${tmp}/video.uri"
    base64 -w0 "${file}" >> "${tmp}/video.uri"

    jq -n \
        --arg model "${model}" \
        --arg prompt "${prompt}" \
        --arg system "${system_prompt}" \
        --argjson temperature "${temperature}" \
        --argjson max_tokens "${max_tokens}" \
        --rawfile video "${tmp}/video.uri" \
        '{
            model: $model,
            max_tokens: $max_tokens,
            temperature: $temperature,
            messages: (
                (if $system != "" then [{role: "system", content: $system}] else [] end)
                + [{
                    role: "user",
                    content: [
                        {type: "video_url", video_url: {url: $video}},
                        {type: "text", text: $prompt}
                    ]
                }]
            )
        }' > "${tmp}/payload.json" \
        || send_video::die "не удалось собрать JSON-запрос (проверьте --temperature и --max-tokens: нужны числа)"

    # --- 3. Отправка --------------------------------------------------------
    io::streams::print "Отправляю на сервер (таймаут ${timeout} с) ..."
    local http_code
    http_code="$(curl -sS --max-time "${timeout}" \
        -H 'Content-Type: application/json' \
        --data-binary "@${tmp}/payload.json" \
        -o "${tmp}/response.json" \
        -w '%{http_code}' \
        "${base}/v1/chat/completions")" \
        || send_video::die "ошибка соединения при отправке"

    if [[ "${http_code}" != "200" ]]; then
        io::streams::print "HTTP ${http_code}" >&2
        jq -r '.error.message // .' "${tmp}/response.json" >&2
        exit 1
    fi

    # --- 4. Результат -------------------------------------------------------
    io::streams::print ""
    io::streams::print "=== Ответ модели ==="
    jq -r '.choices[0].message.content // "(пустой ответ)"' "${tmp}/response.json"
}

main "$@"
