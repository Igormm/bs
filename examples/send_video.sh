#!/usr/bin/env bs
# shellcheck shell=bash
#
# send_video.sh - отправка видео на локальный vLLM-сервер и получение ответа модели.
# Длинные видео режутся на фрагменты (ffmpeg) и отправляются по одному.
# Время обработки каждого фрагмента и итоговая статистика пишутся в текст.
#
# Видео кодируется в base64 и уходит в /v1/chat/completions как content-блок
# "video_url" (data URI). Нужна мультимодальная (VLM) модель с поддержкой видео.
#
# Параметры (все описаны в --help):
#   Файл:      --file, --segment (число или auto), --suggest, --output
#   Сервер:    --host, --port, --model, --context, --timeout
#   Промпт:    --prompt, --prompt-file, --system, --temperature, --max-tokens
#
# Значения по умолчанию можно менять переменными окружения:
#   VIDEO_SERVER_HOST (по умолчанию 192.168.1.83), VIDEO_SERVER_PORT (8000)
#
# Автоподбор длины фрагмента (--segment auto): скрипт отправляет короткую пробу
# (~10 с видео), читает из ответа сервера реальное число токенов (usage) и
# считает, сколько секунд видео помещается в контекст модели с запасом.
#
# Нарезка выполняется там, где запущен скрипт. Если видео лежит на сервере,
# запускайте скрипт на нём с --host 127.0.0.1: тогда по сети ничего не идёт.
#
# Примеры:
#   ./bs run send_video.sh --file ~/clip.mp4
#   ./bs run send_video.sh --file ~/long.mp4 --suggest
#   ./bs run send_video.sh --file ~/long.mp4 --segment auto --output ~/result.txt
#   ./bs run send_video.sh --file ~/long.mp4 --segment 15 --output ~/result.txt
#
# Зависимости (проверяются при запуске, недостающие выводятся списком с командой
# установки): bash 4.4+, curl, jq 1.6+, awk, base64, tr, mktemp, date;
# ffmpeg и ffprobe - только для --segment/--suggest. Работает на Linux и macOS
# (на macOS нужен bash из Homebrew: brew install bash).

load "core/args"
load "lib/io/streams"

# Вывод ошибки в stderr и выход
send_video::die() {
    io::streams::print "ERROR: $*" >&2
    exit 1
}

# Пакет, в котором лежит команда (имя может зависеть от системы)
send_video::pkg_for() {
    case "$1" in
        ffprobe)                          printf 'ffmpeg' ;;
        base64|tr|mktemp|date|wc|df)      printf 'coreutils' ;;
        awk)                              printf 'gawk' ;;
        *)                                printf '%s' "$1" ;;
    esac
}

# Команда установки пакетов для текущей системы (пусто, если менеджер не найден)
send_video::install_cmd() {
    local -a pkgs=("$@")
    if [[ "$(uname -s)" == "Darwin" ]]; then
        printf 'brew install %s' "${pkgs[*]}"
    elif command -v apt-get >/dev/null 2>&1; then
        printf 'sudo apt-get install -y %s' "${pkgs[*]}"
    elif command -v dnf >/dev/null 2>&1; then
        # В репозиториях Fedora полноценный ffmpeg есть только в RPM Fusion;
        # свободная сборка ffmpeg-free содержит и ffmpeg, и ffprobe.
        printf 'sudo dnf install -y %s' "${pkgs[*]//ffmpeg/ffmpeg-free}"
    elif command -v pacman >/dev/null 2>&1; then
        printf 'sudo pacman -S --needed %s' "${pkgs[*]}"
    elif command -v zypper >/dev/null 2>&1; then
        printf 'sudo zypper install %s' "${pkgs[*]}"
    elif command -v apk >/dev/null 2>&1; then
        printf 'sudo apk add %s' "${pkgs[*]}"
    fi
}

# Проверка окружения: версия bash и все нужные утилиты. Все недостающие
# программы выводятся одним списком, вместе с командой установки.
# $1 - "yes", если нужны ffmpeg/ffprobe (нарезка или автоподбор --segment).
send_video::preflight() {
    local -r need_ffmpeg="${1:-no}"

    if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
        io::streams::print "ERROR: нужен bash 4.4 или новее, сейчас ${BASH_VERSION}" >&2
        if [[ "$(uname -s)" == "Darwin" ]]; then
            io::streams::print "  macOS: brew install bash  (и проверьте: env bash --version)" >&2
        fi
        exit 1
    fi

    local -a required=(curl jq base64 awk tr mktemp date wc df)
    if [[ "${need_ffmpeg}" == "yes" ]]; then
        required+=(ffmpeg ffprobe)
    fi

    local -a missing=() pkgs=()
    local cmd pkg known p
    for cmd in "${required[@]}"; do
        command -v "${cmd}" >/dev/null 2>&1 && continue
        missing+=("${cmd}")
        pkg="$(send_video::pkg_for "${cmd}")"
        known=no
        for p in "${pkgs[@]}"; do
            [[ "${p}" == "${pkg}" ]] && known=yes
        done
        if [[ "${known}" == "no" ]]; then
            pkgs+=("${pkg}")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        io::streams::print "ERROR: не хватает программ: ${missing[*]}" >&2
        local hint
        hint="$(send_video::install_cmd "${pkgs[@]}")"
        if [[ -n "${hint}" ]]; then
            io::streams::print "  Установите: ${hint}" >&2
        else
            io::streams::print "  Установите пакеты: ${pkgs[*]}" >&2
        fi
        exit 1
    fi

    # --rawfile появился в jq 1.6: на старых версиях запрос не соберётся
    if ! jq -n --rawfile x /dev/null '$x' >/dev/null 2>&1; then
        io::streams::print "ERROR: jq слишком старый (нужен 1.6+): $(jq --version 2>&1)" >&2
        exit 1
    fi
}

# Вывод на экран и (если задан --output) дописывание в текстовый файл.
# Использует переменную output из main (динамическая область видимости).
send_video::emit() {
    io::streams::print "$*"
    if [[ -n "${output:-}" ]]; then
        printf '%s\n' "$*" >> "${output}"
    fi
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

# Секунды -> ЧЧ:ММ:СС
send_video::timecode() {
    local -i s="$1"
    printf '%02d:%02d:%02d' $(( s / 3600 )) $(( (s % 3600) / 60 )) $(( s % 60 ))
}

# Длительность видео в целых секундах (пусто, если ffprobe недоступен/ошибка)
send_video::duration() {
    command -v ffprobe >/dev/null 2>&1 || return 0
    ffprobe -v error -show_entries format=duration \
        -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null \
        | awk 'NR==1 && $1 ~ /^[0-9.]+$/ { printf "%d", $1 }'
}

# Отправка одного файла. Использует переменные из main (динамическая область):
# base, model, prompt, system_prompt, temperature, max_tokens, timeout, tmp.
# Необязательный 2-й аргумент - свой лимит токенов ответа (для пробы).
# Печатает ответ модели в stdout; токены (prompt completion) пишет в ${tmp}/usage.txt.
send_video::send_one() {
    local -r chunk="$1"
    local -r mt="${2:-${max_tokens}}"
    local mime
    mime="$(send_video::mime "${chunk}")"

    # Видео и тело запроса идут через файлы, а не через аргументы командной
    # строки: base64 большого видео не помещается в лимит длины аргумента.
    printf 'data:%s;base64,' "${mime}" > "${tmp}/video.uri"
    # base64 без переносов строк; "< файл | tr" работает и в GNU, и в BSD (macOS)
    base64 < "${chunk}" | tr -d '\n' >> "${tmp}/video.uri"

    jq -n \
        --arg model "${model}" \
        --arg prompt "${prompt}" \
        --arg system "${system_prompt}" \
        --argjson temperature "${temperature}" \
        --argjson max_tokens "${mt}" \
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

    local http_code
    http_code="$(curl -sS --max-time "${timeout}" \
        -H 'Content-Type: application/json' \
        --data-binary "@${tmp}/payload.json" \
        -o "${tmp}/response.json" \
        -w '%{http_code}' \
        "${base}/v1/chat/completions")" \
        || { io::streams::print "ошибка соединения при отправке" >&2; return 1; }

    if [[ "${http_code}" != "200" ]]; then
        io::streams::print "HTTP ${http_code}" >&2
        jq -r '.error.message // .' "${tmp}/response.json" >&2
        return 1
    fi

    jq -r '"\(.usage.prompt_tokens // 0) \(.usage.completion_tokens // 0)"' \
        "${tmp}/response.json" > "${tmp}/usage.txt"
    jq -r '.choices[0].message.content // "(пустой ответ)"' "${tmp}/response.json"
}

# Подбор длины фрагмента по пробе. Печатает число секунд в stdout,
# диагностику - в stderr. Использует переменные main: file, ext, duration,
# context, models_json, max_tokens, tmp.
send_video::auto_segment() {
    local -i probe_len=10
    local ctx="${context}"
    if [[ -z "${ctx}" ]]; then
        ctx="$(jq -r '.data[0].max_model_len // empty' <<<"${models_json}")"
    fi
    [[ "${ctx}" =~ ^[0-9]+$ ]] \
        || send_video::die "не удалось узнать размер контекста модели: укажите --context"

    io::streams::print "Проба: режу первые ${probe_len} с для замера токенов ..." >&2
    ffmpeg -loglevel error -i "${file}" -map 0:v:0 -c copy -t "${probe_len}" \
        "${tmp}/probe.${ext}" \
        || send_video::die "ffmpeg не смог сделать пробный фрагмент"

    local probe_dur
    probe_dur="$(send_video::duration "${tmp}/probe.${ext}")"
    [[ "${probe_dur}" =~ ^[0-9]+$ ]] && (( probe_dur > 0 )) || probe_dur="${probe_len}"

    io::streams::print "Проба: отправляю на сервер ..." >&2
    send_video::send_one "${tmp}/probe.${ext}" 16 >/dev/null \
        || send_video::die "проба не прошла: сервер отклонил запрос"

    local ptok
    read -r ptok _ < "${tmp}/usage.txt"
    [[ "${ptok}" =~ ^[0-9]+$ ]] && (( ptok > 0 )) \
        || send_video::die "сервер не вернул usage.prompt_tokens, подобрать значение нельзя"

    # Бюджет = контекст - ответ - 512 (запас под текст промпта), с коэффициентом 0.85.
    # Токены пробы включают и текст промпта, поэтому оценка слегка завышена (в запас).
    awk -v ctx="${ctx}" -v mt="${max_tokens}" -v pt="${ptok}" -v d="${probe_dur}" 'BEGIN {
        budget = (ctx - mt - 512) * 0.85
        tps = pt / d
        s = int(budget / tps)
        if (s < 5) s = 5
        if (s > 300) s = 300
        printf "%d %.1f", s, tps
    }'
}

main() {
    local -r default_host="${VIDEO_SERVER_HOST:-192.168.1.83}"
    local -r default_port="${VIDEO_SERVER_PORT:-8000}"
    local -r default_prompt="Опиши, что происходит в этом видео."

    # --- Файл ---
    args::flag file value
    args::flag segment value 0
    args::flag suggest
    args::flag output value
    args::flag_describe file "Путь к видеофайлу (обязательный параметр)"
    args::flag_describe segment "Длина фрагмента в секундах; auto - подобрать автоматически; 0 - не резать (по умолчанию 0)"
    args::flag_describe suggest "Только подобрать и показать значение --segment (делает пробный запрос), без обработки видео"
    args::flag_describe output "Дописывать результаты, время и статистику в этот текстовый файл"

    # --- Сервер ---
    args::flag host value "${default_host}"
    args::flag port value "${default_port}"
    args::flag model value
    args::flag context value
    args::flag timeout value 600
    args::flag_describe host "IP или имя сервера (по умолчанию ${default_host}, env: VIDEO_SERVER_HOST)"
    args::flag_describe port "Порт vLLM (по умолчанию ${default_port}, env: VIDEO_SERVER_PORT)"
    args::flag_describe model "ID модели (по умолчанию первая из /v1/models)"
    args::flag_describe context "Размер контекста модели в токенах для автоподбора (по умолчанию берётся с сервера)"
    args::flag_describe timeout "Таймаут одного запроса в секундах (по умолчанию 600)"

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

    local -r t_start="$(date +%s)"
    local -r file="${ARGS_FLAGS["file"]:-}"
    local segment="${ARGS_FLAGS["segment"]:-0}"
    local -r output="${ARGS_FLAGS["output"]:-}"
    local -r host="${ARGS_FLAGS["host"]:-${default_host}}"
    local -r port="${ARGS_FLAGS["port"]:-${default_port}}"
    local -r timeout="${ARGS_FLAGS["timeout"]:-600}"
    local -r system_prompt="${ARGS_FLAGS["system"]:-}"
    local -r temperature="${ARGS_FLAGS["temperature"]:-0.3}"
    local -r max_tokens="${ARGS_FLAGS["max-tokens"]:-2048}"
    local -r prompt_file="${ARGS_FLAGS["prompt-file"]:-}"
    local -r context="${ARGS_FLAGS["context"]:-}"
    local prompt="${ARGS_FLAGS["prompt"]:-${default_prompt}}"
    local model="${ARGS_FLAGS["model"]:-}"
    local -r base="http://${host}:${port}"

    if args::flag_is_set suggest; then
        segment="auto"
    fi
    [[ "${segment}" == "auto" || "${segment}" =~ ^[0-9]+$ ]] \
        || send_video::die "--segment: целое число секунд или auto"

    # Проверка окружения до любой работы: ffmpeg нужен для нарезки и автоподбора
    if [[ "${segment}" == "auto" || "${segment}" != "0" ]]; then
        send_video::preflight yes
    else
        send_video::preflight no
    fi

    [[ -n "${file}" ]] || send_video::die "укажите видео: --file /путь/к/видео.mp4"
    [[ -f "${file}" ]] || send_video::die "файл не найден: ${file}"
    [[ -r "${file}" ]] || send_video::die "нет прав на чтение файла: ${file}"

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

    # --- 2. Временная папка (чистится при выходе) --------------------------
    local tmp
    tmp="$(mktemp -d)" || send_video::die "не удалось создать временную папку"
    # shellcheck disable=SC2064
    trap "rm -rf '${tmp}'" EXIT

    local -r ext="${file##*.}"
    local duration=""
    duration="$(send_video::duration "${file}")"

    # --- 3. Автоподбор длины фрагмента --------------------------------------
    if [[ "${segment}" == "auto" ]]; then
        [[ "${duration}" =~ ^[0-9]+$ ]] \
            || send_video::die "ffprobe не определил длительность видео"
        if (( duration <= 15 )); then
            io::streams::print "Видео короткое (${duration} с): нарезка не нужна."
            segment=0
        else
            local auto_result tps
            auto_result="$(send_video::auto_segment)" || exit 1
            segment="${auto_result% *}"
            tps="${auto_result#* }"
            io::streams::print "Подобрано: --segment ${segment} (≈ ${tps} токенов на секунду видео)"
        fi
        if args::flag_is_set suggest; then
            io::streams::print "Используйте: --segment ${segment}"
            return 0
        fi
    fi

    # --- 4. Заголовок текстового отчёта -------------------------------------
    send_video::emit "# send_video: ${file} | $(date '+%F %T')"
    send_video::emit "# Сервер: ${base} | модель: ${model}"
    send_video::emit "# segment=${segment} | temperature=${temperature} | max-tokens=${max_tokens}"
    if [[ "${duration}" =~ ^[0-9]+$ ]]; then
        send_video::emit "# Длина видео: $(send_video::timecode "${duration}")"
    fi
    send_video::emit ""

    # --- 5. Список фрагментов -----------------------------------------------
    local -a chunks=()
    if (( segment > 0 )); then
        # Предупреждение, если во временной папке может не хватить места
        local -i need_kb free_kb
        need_kb=$(( $(wc -c < "${file}") / 1024 ))
        free_kb="$(df -Pk "${tmp}" | awk 'NR==2 { print $4 }')"
        if (( free_kb > 0 && free_kb < need_kb )); then
            io::streams::print "ВНИМАНИЕ: во временной папке ~$(( free_kb / 1024 )) МБ свободно, нужно до $(( need_kb / 1024 )) МБ." >&2
            io::streams::print "  Укажите другую папку: TMPDIR=/путь/на/диске bs run ..." >&2
        fi
        io::streams::print "Режу на фрагменты по ${segment} с (ffmpeg, без перекодирования) ..."
        # -map 0:v:0 - только видеодорожка (звук vLLM не использует).
        # -c copy режет по ключевым кадрам, поэтому длины фрагментов приблизительные.
        ffmpeg -loglevel error -i "${file}" -map 0:v:0 -c copy \
            -f segment -segment_time "${segment}" -reset_timestamps 1 \
            "${tmp}/part_%04d.${ext}" \
            || send_video::die "ffmpeg не смог разрезать видео"
        local part
        for part in "${tmp}"/part_*."${ext}"; do
            [[ -f "${part}" ]] && chunks+=("${part}")
        done
        (( ${#chunks[@]} > 0 )) || send_video::die "ffmpeg не создал ни одного фрагмента"
        io::streams::print "Фрагментов: ${#chunks[@]}"
    else
        chunks=("${file}")
    fi

    # --- 6. Отправка по одному, с замером времени ----------------------------
    local -i i failed=0 model_time=0 done_count=0 t0 t1 elapsed ptok ctok
    local reply header
    for (( i = 0; i < ${#chunks[@]}; i++ )); do
        if (( segment > 0 )); then
            header="=== Фрагмент $(( i + 1 ))/${#chunks[@]} (≈ $(send_video::timecode $(( i * segment )))) ==="
        else
            header="=== Ответ модели ==="
        fi
        io::streams::print "Отправляю: ${header}"

        t0="$(date +%s)"
        if reply="$(send_video::send_one "${chunks[i]}")"; then
            t1="$(date +%s)"
            elapsed=$(( t1 - t0 ))
            model_time=$(( model_time + elapsed ))
            done_count=$(( done_count + 1 ))
            read -r ptok ctok < "${tmp}/usage.txt"
            send_video::emit ""
            send_video::emit "${header}"
            send_video::emit "Время обработки: ${elapsed} с | токены: ${ptok} → ${ctok}"
            send_video::emit ""
            send_video::emit "${reply}"
        else
            t1="$(date +%s)"
            elapsed=$(( t1 - t0 ))
            failed=$(( failed + 1 ))
            send_video::emit ""
            send_video::emit "${header}"
            send_video::emit "ОШИБКА: фрагмент не обработан (прошло ${elapsed} с)"
        fi
        # Фрагмент больше не нужен - освобождаем место (оригинал не трогаем)
        if (( segment > 0 )); then
            rm -f "${chunks[i]}"
        fi
    done

    # --- 7. Итоги -----------------------------------------------------------
    local -i wall=$(( $(date +%s) - t_start ))
    send_video::emit ""
    send_video::emit "=== Итого ==="
    send_video::emit "Фрагментов: ${#chunks[@]} (успешно: ${done_count}, ошибок: ${failed})"
    if [[ "${duration}" =~ ^[0-9]+$ ]]; then
        send_video::emit "Длина видео: $(send_video::timecode "${duration}")"
    fi
    send_video::emit "Общее время работы: $(send_video::timecode "${wall}") (${wall} с)"
    send_video::emit "Время ответов модели: $(send_video::timecode "${model_time}") (${model_time} с)"
    if (( done_count > 0 )); then
        send_video::emit "Среднее на фрагмент: $(( model_time / done_count )) с"
    fi
    if [[ "${duration}" =~ ^[0-9]+$ ]] && (( wall > 0 )); then
        send_video::emit "Скорость: $(awk -v d="${duration}" -v w="${wall}" 'BEGIN { printf "%.1f", d / w }')x от реального времени"
    fi
    if [[ -n "${output}" ]]; then
        io::streams::print "Результаты сохранены: ${output}"
    fi

    (( failed == 0 )) || send_video::die "не обработано фрагментов: ${failed}"
}

main "$@"
