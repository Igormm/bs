#!/usr/bin/env bs
# shellcheck shell=bash
# examples/send_video.sh — describe a video with a vLLM vision model
# examples/send_video.sh — описание видео моделью vLLM по фрагментам
#
# Cuts the video with ffmpeg, sends every chunk to /v1/chat/completions as a
# base64 "video_url" item and writes the answers with per-chunk timings.
# Режет видео ffmpeg, шлёт каждый фрагмент в /v1/chat/completions как base64
# "video_url" и пишет ответы вместе со временем обработки каждого фрагмента.
#
# Everything about one video lives in the run directory <output>/<video name>/:
# video.params (settings the run was started with), video.state (checkpoint),
# video.txt (report), video.jsonl (answers with start_ms/end_ms) and the logs.
# A rerun of the same command continues from the checkpoint.
# Всё об одном видео лежит в каталоге прогона <output>/<имя видео>/:
# video.params (параметры запуска), video.state (точка остановки), video.txt
# (отчёт), video.jsonl (ответы со start_ms/end_ms) и журналы. Повторный запуск
# той же команды продолжает с точки остановки.
#
# Usage / Использование:
#   bs run examples/send_video.sh --file clip.mp4 --host llm.local
#   bs run examples/send_video.sh --file clip.mp4 --suggest
#   bs run examples/send_video.sh --file clip.mp4 --output ~/results
#   bs run examples/send_video.sh --file clip.mp4 --restart
#   bs run examples/send_video.sh --help

load "core/args"
load "core/deps"
load "core/errorhandler"
load "core/logger"
load "lib/io/streams"

bs::source_relative "send_common.sh"

# @global SEND_VIDEO_DEFAULT_HOST — constant (category: constant); server host
# @global SEND_VIDEO_DEFAULT_HOST — константа (категория: constant); хост
readonly SEND_VIDEO_DEFAULT_HOST="${SEND_VIDEO_HOST:-127.0.0.1}"

# @global SEND_VIDEO_DEFAULT_PORT — constant (category: constant); server port
# @global SEND_VIDEO_DEFAULT_PORT — константа (категория: constant); порт
readonly SEND_VIDEO_DEFAULT_PORT="${SEND_VIDEO_PORT:-8000}"

# @global SEND_VIDEO_DEFAULT_PROMPT — constant (category: constant); prompt
# @global SEND_VIDEO_DEFAULT_PROMPT — константа (категория: constant); запрос
readonly SEND_VIDEO_DEFAULT_PROMPT="Опиши, что происходит в этом видео."

# @global SEND_VIDEO_SAFETY_PCT — constant (category: constant); limit share
# @global SEND_VIDEO_SAFETY_PCT — константа (категория: constant); доля лимита
readonly SEND_VIDEO_SAFETY_PCT=85

# @global SEND_VIDEO_PROBE_LIMIT — constant (category: constant); max probes
# @global SEND_VIDEO_PROBE_LIMIT — константа (категория: constant); число проб
readonly SEND_VIDEO_PROBE_LIMIT=10

# @global SEND_VIDEO_SPLIT_DEPTH — constant (category: constant); max re-splits
# @global SEND_VIDEO_SPLIT_DEPTH — константа (категория: constant); деления
readonly SEND_VIDEO_SPLIT_DEPTH=4

# @global SEND_VIDEO_STAT_KEYS — constant (category: constant); saved counters
# @global SEND_VIDEO_STAT_KEYS — константа (категория: constant); счётчики
readonly -a SEND_VIDEO_STAT_KEYS=(done failed splits tokens model_ms)

# @global SEND_VIDEO_PARAM_KEYS — constant (category: constant); params file
# @global SEND_VIDEO_PARAM_KEYS — константа (категория: constant); параметры
readonly -a SEND_VIDEO_PARAM_KEYS=(file file_size duration_ms base model
  segment temperature max_tokens prompt_sha saved_at)

# @global SEND_VIDEO_STATE_KEYS — constant (category: constant); checkpoint
# @global SEND_VIDEO_STATE_KEYS — константа (категория: constant); остановка
readonly -a SEND_VIDEO_STATE_KEYS=(status next_chunk chunks_total offset_ms
  report_bytes results_bytes done failed splits tokens model_ms wall_ms
  updated_at)

# @global __SEND_VIDEO_CFG — internal state (category: state); run settings
# @global __SEND_VIDEO_CFG — внутреннее состояние (категория: state); настройки
declare -gA __SEND_VIDEO_CFG=()

# @global __SEND_VIDEO_STAT — internal state (category: state); counters
# @global __SEND_VIDEO_STAT — внутреннее состояние (категория: state); счётчики
declare -gA __SEND_VIDEO_STAT=()

# @global __SEND_VIDEO_SAVED — internal state (category: state); loaded params
# @global __SEND_VIDEO_SAVED — внутреннее состояние (категория: state); параметры
declare -gA __SEND_VIDEO_SAVED=()

# @global __SEND_VIDEO_STATE — internal state (category: state); checkpoint
# @global __SEND_VIDEO_STATE — внутреннее состояние (категория: state); остановка
declare -gA __SEND_VIDEO_STATE=()

# ---------------------------------------------------------------------------
# Logging and report / Логирование и отчёт
# ---------------------------------------------------------------------------

# @description Log a message on screen and append it to the log file.
# @description Записать сообщение на экран и дописать его в файл журнала.
# @param $1 Level: trace|debug|info|success|warn|error / Уровень
# @param $@ Message / Сообщение
# @return 0
send_video::__log() {
  local -r level="${1:?level required}"
  shift
  # "$*" joins with the first IFS char; bs run sets IFS to newline/tab
  local IFS=' '
  local -n __map_cfg=__SEND_VIDEO_CFG
  local -r log_file="${__map_cfg[log_file]:-}"
  local -r msg="$*"
  if is::not_empty "${log_file}"; then
    io::streams::print \
      "$(utils::log_stamp) ${level^^} ${msg}" >> "${log_file}"
  fi
  "log::${level}" "${msg}"
  return 0
}

# @description Print a report line and append it to the current report file
#   (video.txt, or the buffer of the chunk being processed).
# @description Вывести строку отчёта и дописать её в текущий файл отчёта
#   (video.txt либо буфер обрабатываемого фрагмента).
# @param $@ Text / Текст
# @return 0
send_video::__report() {
  local IFS=' '
  local -n __map_cfg=__SEND_VIDEO_CFG
  local -r output="${__map_cfg[output]:-}"
  local -r text="$*"
  io::streams::print "${text}"
  if is::not_empty "${output}"; then
    io::streams::print "${text}" >> "${output}"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Integer arithmetic: no awk, no locale / Целочисленная арифметика
# ---------------------------------------------------------------------------

# @description Convert "12.345" seconds to integer milliseconds.
# @description Перевести секунды вида "12.345" в целые миллисекунды.
# @param $1 Seconds, dot or comma decimal / Секунды, точка или запятая
# @stdout Milliseconds / Миллисекунды
# @return 0 on success, 1 if the value is not a number
send_video::__to_ms() {
  local -r raw="${1:-}"
  local -r re='^([0-9]+)([.,]([0-9]*))?$'
  local frac
  if [[ ! "${raw}" =~ ${re} ]]; then
    return 1
  fi
  frac="${BASH_REMATCH[3]:-}000"
  io::streams::printf '%d' \
    "$(( 10#${BASH_REMATCH[1]} * 1000 + 10#${frac:0:3} ))"
}

# @description Format milliseconds as HH:MM:SS.
# @description Отформатировать миллисекунды как ЧЧ:ММ:СС.
# @param $1 Milliseconds / Миллисекунды
# @stdout Time code / Таймкод
send_video::__timecode() {
  local -r ms="${1:-0}"
  local -i sec=0
  if is::number "${ms}"; then
    sec=$(( ms / 1000 ))
  fi
  io::streams::printf '%02d:%02d:%02d' \
    "$(( sec / 3600 ))" "$(( (sec % 3600) / 60 ))" "$(( sec % 60 ))"
}

# @description Format milliseconds as seconds with one decimal digit.
# @description Отформатировать миллисекунды как секунды с одним знаком.
# @param $1 Milliseconds / Миллисекунды
# @stdout Seconds, e.g. 12.3 / Секунды
send_video::__seconds() {
  local -r ms="${1:-0}"
  io::streams::printf '%d.%d' "$(( ms / 1000 ))" "$(( (ms % 1000) / 100 ))"
}

# @description Duration of a video file in milliseconds via ffprobe.
# @description Длительность видеофайла в миллисекундах через ffprobe.
# @param $1 File / Файл
# @stdout Milliseconds / Миллисекунды
# @return 0 on success, 1 if ffprobe failed
send_video::__duration_ms() {
  local -r file="${1:?file required}"
  local raw
  if ! raw="$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "${file}" 2>&1)"; then
    return 1
  fi
  send_video::__to_ms "${raw}"
}

# @description MIME type of a video file by its extension.
# @description MIME-тип видеофайла по расширению.
# @param $1 File / Файл
# @stdout MIME type / MIME-тип
send_video::__mime() {
  case "${1,,}" in
    *.webm) io::streams::printf 'video/webm' ;;
    *.mkv)  io::streams::printf 'video/x-matroska' ;;
    *.mov)  io::streams::printf 'video/quicktime' ;;
    *.avi)  io::streams::printf 'video/x-msvideo' ;;
    *)      io::streams::printf 'video/mp4' ;;
  esac
}

# ---------------------------------------------------------------------------
# Server errors / Ошибки сервера
# ---------------------------------------------------------------------------

# @description Parse a server "too large" error into "<size> <limit>".
# @description Разобрать ошибку сервера «слишком большой» в "<размер> <лимит>".
# @param $1 File with the error text / Файл с текстом ошибки
# @stdout Two integers: requested size and the limit, in tokens
# @return 0 if the message is a size error, 1 otherwise
send_video::__overflow_parse() {
  local -r file="${1:?error file required}"
  local -r re_item='item[[:space:]]+with[^0-9]*([0-9]+)'
  local -r re_cache='cache[[:space:]]+size[^0-9]*([0-9]+)'
  local -r re_ctx='maximum[[:space:]]+context[[:space:]]+length[^0-9]*([0-9]+)'
  local -r re_req='requested[[:space:]]+([0-9]+)[[:space:]]+tokens'
  local -r re_input='[Ii]nput[[:space:]]+length[^0-9]*([0-9]+)'
  local -r re_len='prompt[[:space:]]+\(length[[:space:]]+([0-9]+)\)'
  local -r re_max='model[[:space:]]+length[[:space:]]+of[[:space:]]+([0-9]+)'
  local msg over="" limit=""
  msg="$(<"${file}")"
  if [[ "${msg}" =~ ${re_item} ]]; then
    over="${BASH_REMATCH[1]}"
    if [[ "${msg}" =~ ${re_cache} ]]; then
      limit="${BASH_REMATCH[1]}"
    fi
  elif [[ "${msg}" =~ ${re_ctx} ]]; then
    limit="${BASH_REMATCH[1]}"
    # vLLM: "Input length (26569) exceeds model's maximum context length
    # (24576)"; старый формат — "... you requested N tokens". Если размер
    # не распознан, это всё равно ошибка размера: 0 = «неизвестно», поиск
    # длины фрагмента пойдёт делением пополам.
    # vLLM: "Input length (26569) exceeds model's maximum context length
    # (24576)"; the older format is "... you requested N tokens". An
    # unrecognised size is still a size error: 0 = "unknown", the chunk
    # search then falls back to bisection.
    if [[ "${msg}" =~ ${re_req} || "${msg}" =~ ${re_input} ]]; then
      over="${BASH_REMATCH[1]}"
    else
      over=0
    fi
  elif [[ "${msg}" =~ ${re_len} ]]; then
    over="${BASH_REMATCH[1]}"
    if [[ "${msg}" =~ ${re_max} ]]; then
      limit="${BASH_REMATCH[1]}"
    fi
  fi
  if is::number "${over}" && is::number "${limit}"; then
    io::streams::printf '%s %s' "${over}" "${limit}"
    return 0
  fi
  return 1
}

# @description Send one video file to the server and store the outcome.
# @description Отправить один видеофайл на сервер и сохранить результат.
# @param $1 Video file / Видеофайл
# @param $2 max_tokens, empty = let the server choose / Пусто = решает сервер
# @return 0 ok, 2 size error (over/limit in state), 1 any other error
send_video::__request() {
  local -r chunk="${1:?chunk required}"
  local -r max_tokens="${2:-}"
  local -n __map_cfg=__SEND_VIDEO_CFG
  local -n __map_stat=__SEND_VIDEO_STAT
  local -r tmp="${__map_cfg[tmp]}"
  local -r jq_usage='"\(.usage.prompt_tokens // 0)
    \(.usage.completion_tokens // 0) \(.choices[0].finish_reason // "?")"'
  local mime line code ttotal sent info over limit
  local -i size t_start t_sent
  local ptok=0 ctok=0 finish="?"

  mime="$(send_video::__mime "${chunk}")"
  size=$(( $(wc -c < "${chunk}") ))
  send_video::__log debug \
    "request: ${chunk} ${size} B, ${mime}, max_tokens=${max_tokens:-auto}"

  t_start="$(utils::now_ms)"
  io::streams::printf 'data:%s;base64,' "${mime}" > "${tmp}/video.uri"
  if ! base64 < "${chunk}" | tr -d '\n' >> "${tmp}/video.uri"; then
    send_video::__log error "base64 failed for ${chunk}"
    return 1
  fi
  if ! jq -n \
    --arg model "${__map_cfg[model]}" \
    --arg prompt "${__map_cfg[prompt]}" \
    --arg system "${__map_cfg[system]}" \
    --arg max_tokens "${max_tokens}" \
    --argjson temperature "${__map_cfg[temperature]}" \
    --rawfile video "${tmp}/video.uri" \
    '{model: $model, temperature: $temperature,
      messages: (
        (if $system != "" then [{role: "system", content: $system}] else [] end)
        + [{role: "user", content: [
            {type: "video_url", video_url: {url: $video}},
            {type: "text", text: $prompt}]}])}
     + (if $max_tokens != ""
        then {max_tokens: ($max_tokens | tonumber)} else {} end)' \
    > "${tmp}/payload.json"; then
    send_video::__log error "jq could not build the request body"
    return 1
  fi
  t_sent="$(utils::now_ms)"
  send_video::__log trace "payload built in $(( t_sent - t_start )) ms," \
    "$(( $(wc -c < "${tmp}/payload.json") )) B"

  if ! line="$(curl -sS --max-time "${__map_cfg[timeout]}" \
    -H 'Content-Type: application/json' \
    --data-binary "@${tmp}/payload.json" \
    --stderr "${tmp}/curl.err" \
    -o "${tmp}/response.json" \
    -w '%{http_code} %{time_total} %{size_upload}' \
    "${__map_cfg[base]}/v1/chat/completions")"; then
    send_video::__log error "curl failed: $(<"${tmp}/curl.err")"
    return 1
  fi
  IFS=' ' read -r code ttotal sent <<< "${line}"
  send_video::__log debug \
    "response: HTTP ${code}, curl ${ttotal} s, uploaded ${sent} B"
  __map_stat[http]="${code}"

  if [[ "${code}" != "200" ]]; then
    if ! utils::quiet_err jq -r '.error.message // .message // tostring' \
      "${tmp}/response.json" > "${tmp}/error.txt"; then
      cp "${tmp}/response.json" "${tmp}/error.txt"
    fi
    send_video::__log warn "server error HTTP ${code}: $(<"${tmp}/error.txt")"
    if info="$(send_video::__overflow_parse "${tmp}/error.txt")"; then
      IFS=' ' read -r over limit <<< "${info}"
      __map_stat[over]="${over}"
      __map_stat[limit]="${limit}"
      return 2
    fi
    return 1
  fi

  if ! jq -r '.choices[0].message.content // empty' \
    "${tmp}/response.json" > "${tmp}/reply.txt"; then
    send_video::__log error "response is not valid JSON"
    return 1
  fi
  info="$(jq -r "${jq_usage//$'\n'/}" "${tmp}/response.json")"
  IFS=' ' read -r ptok ctok finish <<< "${info}"
  __map_stat[ptok]="${ptok}"
  __map_stat[ctok]="${ctok}"
  send_video::__log debug \
    "usage: prompt=${ptok} completion=${ctok} finish=${finish}"
  if [[ "${finish}" == "length" ]]; then
    send_video::__log warn "answer was cut by the token limit (finish=length)"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# ffmpeg
# ---------------------------------------------------------------------------

# @description Run ffmpeg with logging of the command and its diagnostics.
# @description Запустить ffmpeg с журналом команды и диагностики.
# @param $@ ffmpeg arguments / Аргументы ffmpeg
# @return ffmpeg exit code / Код возврата ffmpeg
send_video::__ffmpeg() {
  local -n __map_cfg=__SEND_VIDEO_CFG
  local -r err="${__map_cfg[tmp]}/ffmpeg.err"
  local -a argv=(ffmpeg -hide_banner -loglevel warning -y "$@")
  local -i rc=0
  send_video::__log debug "run: $(arr::join argv ' ')"
  "${argv[@]}" 2> "${err}" || rc=$?
  if is::file_not_empty "${err}"; then
    send_video::__log debug "ffmpeg: $(<"${err}")"
  fi
  return "${rc}"
}

# @description Cut the first N seconds of a video without re-encoding.
# @description Вырезать первые N секунд видео без перекодирования.
# @param $1 Input / Вход
# @param $2 Seconds / Секунды
# @param $3 Output / Выход
# @return ffmpeg exit code
send_video::__cut_head() {
  send_video::__ffmpeg -i "${1:?input required}" -map 0:v:0 -c copy \
    -t "${2:?seconds required}" "${3:?output required}"
}

# @description Cut a chunk into equal parts with re-encoding.
# @description Нарезать фрагмент на равные части с перекодированием.
# @param $1 Input / Вход
# @param $2 Part length, seconds / Длина части, секунды
# @param $3 Output dir / Папка для part_NNN.mp4
# @param $@ Encoder arguments (from $4) / Аргументы кодера
# @return ffmpeg exit code
send_video::__split_try() {
  local -r input="${1:?input required}"
  local -r len="${2:?length required}"
  local -r out="${3:?output dir required}"
  shift 3
  utils::ignore rm -f "${out}"/part_*.mp4
  send_video::__ffmpeg -i "${input}" -map 0:v:0 -an -sn "$@" \
    -force_key_frames "expr:gte(t,n_forced*${len})" \
    -f segment -segment_time "${len}" -reset_timestamps 1 \
    "${out}/part_%03d.mp4"
}

# @description Exact cut: libx264 first, the built-in mpeg4 as fallback.
# @description Точная нарезка: сначала libx264, при отсутствии — mpeg4.
# @param $1 Input / Вход
# @param $2 Part length, seconds / Длина части, секунды
# @param $3 Output dir / Папка
# @return 0 on success, 1 if both encoders failed
send_video::__split_exact() {
  if send_video::__split_try "$1" "$2" "$3" \
    -c:v libx264 -preset ultrafast -crf 23 -pix_fmt yuv420p; then
    return 0
  fi
  send_video::__log warn "libx264 failed, trying the mpeg4 encoder"
  send_video::__split_try "$1" "$2" "$3" -c:v mpeg4 -q:v 4
}

# ---------------------------------------------------------------------------
# Chunk processing / Обработка фрагментов
# ---------------------------------------------------------------------------

# @description Count a failed chunk and write the reason to the report.
# @description Учесть неудачный фрагмент и записать причину в отчёт.
# @param $1 Report header / Заголовок
# @param $2 Reason / Причина
# @return 0
send_video::__fail() {
  local -n __map_stat=__SEND_VIDEO_STAT
  __map_stat[failed]=$(( ${__map_stat[failed]:-0} + 1 ))
  send_video::__log error "$1: $2"
  send_video::__report ""
  send_video::__report "$1"
  send_video::__report "ОШИБКА: $2"
  return 0
}

# @description Split a rejected chunk by the server's numbers and resend.
# @description Поделить отклонённый фрагмент по данным сервера и отправить.
# @param $1 Chunk file / Файл фрагмента
# @param $2 Chunk start in the video, ms / Начало в видео, мс
# @param $3 Label / Метка
# @param $4 Split depth / Глубина деления
# @param $5 Report header / Заголовок отчёта
# @return 0 always; the outcome is counted in the state map
send_video::__resplit() {
  local -r chunk="${1:?chunk required}"
  local -r label="${3:-}"
  local -r depth="${4:-0}"
  local -r header="${5:-}"
  local -n __map_cfg=__SEND_VIDEO_CFG
  local -n __map_stat=__SEND_VIDEO_STAT
  local -i over="${__map_stat[over]}" limit="${__map_stat[limit]}"
  local -i poff_ms="${2:-0}" dur_ms=0 parts part_len k=0 part_ms
  local sub part sub_label

  if (( depth >= SEND_VIDEO_SPLIT_DEPTH )); then
    send_video::__fail "${header}" \
      "слишком велик (${over} токенов, лимит ${limit}), глубина исчерпана"
    return 0
  fi
  dur_ms="$(send_video::__duration_ms "${chunk}")" || dur_ms=0
  if (( dur_ms < 2000 )); then
    send_video::__fail "${header}" \
      "слишком велик (${over} > ${limit} токенов), делить нельзя"
    return 0
  fi

  parts=$(( (over * 100 + limit * SEND_VIDEO_SAFETY_PCT - 1)
    / (limit * SEND_VIDEO_SAFETY_PCT) ))
  parts=$(( parts < 2 ? 2 : (parts > 16 ? 16 : parts) ))
  part_len=$(( (dur_ms + parts * 1000 - 1) / (parts * 1000) ))
  __map_stat[splits]=$(( ${__map_stat[splits]:-0} + 1 ))
  send_video::__report ""
  send_video::__report "${header}"
  send_video::__report "Не поместился в лимит (${over} токенов, лимит" \
    "${limit}): делю на ${parts} части по ~${part_len} с"

  sub="$(mktemp -d "${__map_cfg[tmp]}/split.XXXXXX")"
  if ! send_video::__split_exact "${chunk}" "${part_len}" "${sub}"; then
    send_video::__fail "${header}" "ffmpeg не смог разделить фрагмент"
    utils::ignore rm -rf "${sub}"
    return 0
  fi
  for part in "${sub}"/part_*.mp4; do
    is::file "${part}" || continue
    k=$(( k + 1 ))
    if [[ "${label}" == */* ]]; then
      sub_label="${label%%/*}.${k}/${label#*/}"
    else
      sub_label="${label:-1}.${k}"
    fi
    send_video::__process_chunk "${part}" "${poff_ms}" "${sub_label}" \
      "$(( depth + 1 ))"
    if part_ms="$(send_video::__duration_ms "${part}")"; then
      poff_ms=$(( poff_ms + part_ms ))
    fi
    utils::ignore rm -f "${part}"
  done
  utils::ignore rm -rf "${sub}"
  return 0
}

# @description Process one chunk; split it again if the server rejects it.
# @description Обработать фрагмент; при отказе сервера поделить ещё раз.
# @param $1 Chunk file / Файл фрагмента
# @param $2 Chunk start in the video, ms / Начало в видео, мс
# @param $3 Label like "3/75" or empty / Метка
# @param $4 Split depth / Глубина деления
# @return 0 always; the outcome is counted in the state map
send_video::__process_chunk() {
  local -r chunk="${1:?chunk required}"
  local -r start_ms="${2:-0}"
  local -r label="${3:-}"
  local -r depth="${4:-0}"
  local -n __map_cfg=__SEND_VIDEO_CFG
  local -n __map_stat=__SEND_VIDEO_STAT
  local header reply
  local -i rc=0 t_start elapsed chunk_ms=0 end_ms

  if ! chunk_ms="$(send_video::__duration_ms "${chunk}")"; then
    chunk_ms=0
  fi
  end_ms=$(( start_ms + chunk_ms ))
  if is::not_empty "${label}"; then
    header="=== Фрагмент ${label}"
    header+=" ($(sendrun::timecode_ms "${start_ms}")"
    header+=" – $(sendrun::timecode_ms "${end_ms}")) ==="
  else
    header="=== Ответ модели ==="
  fi
  send_video::__log info "send ${header} file=${chunk} depth=${depth}"

  t_start="$(utils::now_ms)"
  send_video::__request "${chunk}" "${__map_cfg[max_tokens]}" || rc=$?
  elapsed=$(( $(utils::now_ms) - t_start ))

  if (( rc == 2 )); then
    send_video::__resplit "${chunk}" "${start_ms}" "${label}" "${depth}" \
      "${header}"
    return 0
  fi
  if (( rc != 0 )); then
    send_video::__fail "${header}" \
      "фрагмент не обработан (код ${rc}, прошло $(( elapsed / 1000 )) с)"
    return 0
  fi

  __map_stat[done]=$(( ${__map_stat[done]:-0} + 1 ))
  __map_stat[model_ms]=$(( ${__map_stat[model_ms]:-0} + elapsed ))
  __map_stat[tokens]=$(( ${__map_stat[tokens]:-0} + __map_stat[ptok] ))
  reply="$(<"${__map_cfg[tmp]}/reply.txt")"
  if is::empty "${reply}"; then
    reply="(пустой ответ)"
  fi
  send_video::__report ""
  send_video::__report "${header}"
  local secs
  secs="$(send_video::__seconds "${elapsed}")"
  send_video::__report "Время обработки: ${secs} с |" \
    "токены: ${__map_stat[ptok]} → ${__map_stat[ctok]}"
  send_video::__report ""
  send_video::__report "${reply}"
  # Machine-readable twin of the report: one object per answered piece
  if is::not_empty "${__map_cfg[jsonl]:-}"; then
    jq -cn --argjson start "${start_ms}" --argjson end "${end_ms}" \
      --arg label "${label}" --arg text "${reply}" \
      '{start_ms: $start, end_ms: $end, label: $label, text: $text}' \
      >> "${__map_cfg[jsonl]}"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Segment length search / Подбор длины фрагмента
# ---------------------------------------------------------------------------

# @description Send the first N seconds as a probe and report the outcome.
# @description Отправить первые N секунд как пробу и вернуть результат.
# @param $1 Probe length, seconds / Длина пробы, секунды
# @return 0 accepted, 2 rejected as too large, 1 other error
send_video::__probe() {
  local -r secs="${1:?seconds required}"
  local -n __map_cfg=__SEND_VIDEO_CFG
  local -n __map_stat=__SEND_VIDEO_STAT
  local -r probe="${__map_cfg[tmp]}/probe.${__map_cfg[ext]}"
  local -i rc=0 dur_ms=0 ptok=0

  if ! send_video::__cut_head "${__map_cfg[file]}" "${secs}" "${probe}"; then
    send_video::__log error "could not cut a ${secs} s probe"
    return 1
  fi
  if ! dur_ms="$(send_video::__duration_ms "${probe}")"; then
    dur_ms=$(( secs * 1000 ))
    send_video::__log warn "probe length unknown, assuming ${secs} s"
  fi
  send_video::__log info "probe ${secs} s (real length ${dur_ms} ms)"
  send_video::__request "${probe}" 16 || rc=$?
  utils::ignore rm -f "${probe}"

  case "${rc}" in
    0)
      ptok="${__map_stat[ptok]}"
      send_video::__log success "probe ${secs} s accepted: ${ptok} tokens," \
        "$(( ptok * 1000 / (dur_ms > 0 ? dur_ms : 1) )) tok/s"
      ;;
    2)
      send_video::__log warn "probe ${secs} s rejected:" \
        "${__map_stat[over]} tokens, limit ${__map_stat[limit]}"
      ;;
  esac
  return "${rc}"
}

# @description Find the longest chunk length the server accepts.
# @description Найти максимальную длину фрагмента, которую принимает сервер.
# @param $1 Video length, seconds / Длина видео, секунды
# @return 0 on success (state "found"; 0 = the whole video fits), 1 on failure
send_video::__find_segment() {
  local -r total="${1:?duration required}"
  local -n __map_cfg=__SEND_VIDEO_CFG
  local -n __map_stat=__SEND_VIDEO_STAT
  local -i cap="${__map_cfg[segment_max]}"
  local -i cur="${__map_cfg[segment_start]}"
  local -i lo=0 hi=0 next=0 iter rc over limit

  cap=$(( cap < total ? cap : total ))
  cur=$(( cur < cap ? cur : cap ))
  cur=$(( cur < 1 ? 1 : cur ))
  send_video::__log info "segment search: start=${cur} s, cap=${cap} s"

  for (( iter = 1; iter <= SEND_VIDEO_PROBE_LIMIT; iter++ )); do
    rc=0
    send_video::__probe "${cur}" || rc=$?
    if (( rc == 0 )); then
      lo="${cur}"
      if (( lo >= total )); then
        __map_stat[found]=0
        return 0
      fi
      if (( hi == 0 )); then
        next=$(( cur * 2 < cap ? cur * 2 : cap ))
        (( next > lo )) || break
      else
        (( hi - lo > 1 && (hi - lo) * 10 > lo )) || break
        next=$(( (lo + hi) / 2 ))
      fi
    elif (( rc == 2 )); then
      hi="${cur}"
      over="${__map_stat[over]}"
      limit="${__map_stat[limit]}"
      if (( hi == 1 )); then
        send_video::__log error "even a 1 s probe is rejected by the server"
        return 1
      fi
      next=$(( cur * limit * 90 / ((over > 0 ? over : 1) * 100) ))
      if (( next <= lo || next >= hi )); then
        next=$(( lo > 0 ? (lo + hi) / 2 : hi / 2 ))
      fi
      next=$(( next < 1 ? 1 : next ))
      if (( lo > 0 && hi - lo <= 1 )); then
        break
      fi
    else
      return 1
    fi
    cur="${next}"
  done

  if (( lo == 0 )); then
    send_video::__log error "no accepted probe length was found"
    return 1
  fi
  __map_stat[found]="${lo}"
  return 0
}

# ---------------------------------------------------------------------------
# Environment / Окружение
# ---------------------------------------------------------------------------

# @description Check required programs; stop with a package list if missing.
# @description Проверить нужные программы; при нехватке остановиться.
# @param $1 "yes" if ffmpeg and ffprobe are needed / «yes», если нужен ffmpeg
# @return 0 on success; exits with LIB_ERROR_DEPENDENCY_MISSING otherwise
send_video::__check_deps() {
  local -a missing=()
  local -a specs=(curl jq base64:coreutils tr:coreutils mktemp:coreutils
    wc:coreutils sha256sum:coreutils)
  if [[ "${1:-no}" == "yes" ]]; then
    specs+=(ffmpeg ffprobe:ffmpeg)
  fi
  deps::missing_tools missing "${specs[@]}"
  if (( ${#missing[@]} > 0 )); then
    error::exit "Missing packages: $(arr::join missing ', ')." \
      "${LIB_ERROR_DEPENDENCY_MISSING}"
  fi
  # jq --rawfile appeared in jq 1.6 / --rawfile появился в jq 1.6
  if ! utils::quiet jq -n --rawfile x /dev/null '$x'; then
    error::exit "jq 1.6+ is required: $(jq --version)" \
      "${LIB_ERROR_DEPENDENCY_MISSING}"
  fi
}

# @description Log versions and settings for post-mortem analysis.
# @description Записать версии и настройки для разбора проблем.
# @return 0
send_video::__log_environment() {
  local -n __map_cfg=__SEND_VIDEO_CFG
  local key line
  send_video::__log debug \
    "bash ${BASH_VERSION}, IFS=$(io::streams::printf '%q' "${IFS}")"
  send_video::__log debug \
    "locale: LC_ALL=${LC_ALL:-} LC_NUMERIC=${LC_NUMERIC:-} LANG=${LANG:-}"
  send_video::__log debug "system: $(uname -sr)"
  for key in curl jq ffmpeg; do
    if utils::has "${key}" \
      && IFS= read -r line < <("${key}" --version 2>&1); then
      send_video::__log debug "${key}: ${line}"
    fi
  done
  for key in "${!__map_cfg[@]}"; do
    if [[ "${key}" != "prompt" ]]; then
      send_video::__log trace "cfg[${key}]=${__map_cfg[${key}]}"
    fi
  done
  return 0
}

# @description Remove the temporary directory; registered as a cleanup.
# @description Удалить временную папку; регистрируется как cleanup.
# @return 0
send_video::__cleanup() {
  local -n __map_cfg=__SEND_VIDEO_CFG
  local -r tmp="${__map_cfg[tmp]:-}"
  if is::not_empty "${tmp}" && is::dir "${tmp}"; then
    # Temporary chunks are removed directly, without backups
    utils::ignore rm -rf -- "${tmp}"
  fi
  return 0
}

# @description Read a flag value, falling back to a default.
# @description Прочитать значение флага, при отсутствии — значение по умолчанию.
# @param $1 Flag name / Имя флага
# @param $2 Default / Значение по умолчанию
# @stdout Value / Значение
send_video::__flag() {
  local -n __map_flags=ARGS_FLAGS
  io::streams::printf '%s' "${__map_flags[$1]:-${2-}}"
}

# @description True if a boolean flag was passed.
# @description Истина, если булев флаг указан.
# @param $1 Flag name / Имя флага
# @return 0 if set, 1 otherwise
send_video::__flag_on() {
  utils::quiet args::flag_get "${1:?flag name required}"
}

# @description Declare all command-line flags.
# @description Объявить все флаги командной строки.
# @return 0
send_video::__declare_flags() {
  args::flag file value
  args::flag segment value auto
  args::flag segment-start value 15 number
  args::flag segment-max value 300 number
  args::flag suggest
  args::flag output value .
  args::flag restart
  args::flag keep-going
  args::flag host value "${SEND_VIDEO_DEFAULT_HOST}"
  args::flag port value "${SEND_VIDEO_DEFAULT_PORT}" number
  args::flag model value
  args::flag timeout value 600 number
  args::flag prompt value "${SEND_VIDEO_DEFAULT_PROMPT}"
  args::flag prompt-file value
  args::flag system value
  args::flag temperature value 0.7
  args::flag max-tokens value auto
  args::flag log-level value TRACE "enum:TRACE,DEBUG,INFO,SUCCESS,WARN,ERROR"
  args::flag log-file value
  args::flag xtrace

  args::flag_describe file "Видеофайл / video file (required)"
  args::flag_describe segment \
    "Секунд в фрагменте: число, auto = подобрать по ответам сервера,"\
" 0 = не резать / chunk length"
  args::flag_describe segment-start \
    "С какой длины начинать подбор при auto, сек / search start"
  args::flag_describe segment-max \
    "Верхний предел подбора при auto, сек / search cap"
  args::flag_describe suggest \
    "Только подобрать --segment и выйти / only find --segment"
  args::flag_describe output \
    "КАТАЛОГ, в котором создаётся <имя видео>/ с video.txt, video.jsonl,"\
" video.params, video.state (точка остановки) и журналами; по умолчанию"\
" текущий. Повторный запуск продолжает с точки остановки / parent dir"
  args::flag_describe restart \
    "Начать заново: забыть параметры, точку остановки и отчёт / start over"
  args::flag_describe keep-going \
    "Не останавливаться на неудачном фрагменте, а идти дальше / keep going"
  args::flag_describe host "Хост сервера / server host"
  args::flag_describe port "Порт сервера / server port"
  args::flag_describe model "ID модели, по умолчанию первая с сервера"
  args::flag_describe timeout "Таймаут запроса, сек / request timeout"
  args::flag_describe prompt "Текст запроса к модели / prompt text"
  args::flag_describe prompt-file "Файл с запросом (приоритетнее --prompt)"
  args::flag_describe system "Системный промпт / system prompt"
  args::flag_describe temperature "Температура генерации / temperature"
  args::flag_describe max-tokens \
    "Лимит токенов ответа; auto = сколько позволит контекст"
  args::flag_describe log-level "Уровень журнала, по умолчанию TRACE"
  args::flag_describe log-file \
    "Файл журнала (по умолчанию send_video_<время>.log в каталоге прогона)"
  args::flag_describe xtrace "Трассировка bash (set -x) в журнал / xtrace"
  return 0
}

# ---------------------------------------------------------------------------
# Entry point / Точка входа
# ---------------------------------------------------------------------------

# @description Validate arguments and set up logging.
# @description Проверить аргументы и настроить журнал.
# @return 0 on success; exits with a framework code on invalid input
send_video::__configure() {
  local -n __map_cfg=__SEND_VIDEO_CFG
  local prompt_file fd
  local -i dir_rc=0

  __map_cfg[file]="$(send_video::__flag file)"
  __map_cfg[out_parent]="$(send_video::__flag output .)"
  __map_cfg[host]="$(send_video::__flag host "${SEND_VIDEO_DEFAULT_HOST}")"
  __map_cfg[port]="$(send_video::__flag port "${SEND_VIDEO_DEFAULT_PORT}")"
  __map_cfg[base]="http://${__map_cfg[host]}:${__map_cfg[port]}"
  __map_cfg[model]="$(send_video::__flag model)"
  __map_cfg[timeout]="$(send_video::__flag timeout 600)"
  __map_cfg[system]="$(send_video::__flag system)"
  __map_cfg[temperature]="$(send_video::__flag temperature 0.7)"
  __map_cfg[max_tokens]="$(send_video::__flag max-tokens auto)"
  __map_cfg[segment]="$(send_video::__flag segment auto)"
  __map_cfg[segment_start]="$(send_video::__flag segment-start 15)"
  __map_cfg[segment_max]="$(send_video::__flag segment-max 300)"
  __map_cfg[log_level]="$(send_video::__flag log-level TRACE)"
  __map_cfg[log_file]="$(send_video::__flag log-file)"
  __map_cfg[prompt]="$(send_video::__flag prompt \
    "${SEND_VIDEO_DEFAULT_PROMPT}")"
  prompt_file="$(send_video::__flag prompt-file)"

  if is::empty "${__map_cfg[file]}"; then
    error::exit "--file is required (see --help)" "${E_INVALID}"
  fi
  if ! is::file "${__map_cfg[file]}"; then
    error::exit "File not found: ${__map_cfg[file]}" \
      "${LIB_ERROR_FILE_NOT_FOUND}"
  fi
  if ! is::readable "${__map_cfg[file]}"; then
    error::exit "File is not readable: ${__map_cfg[file]}" \
      "${LIB_ERROR_PERMISSION_DENIED}"
  fi
  if send_video::__flag_on suggest; then
    __map_cfg[segment]=auto
  fi
  if [[ "${__map_cfg[segment]}" != "auto" ]] \
    && ! is::number "${__map_cfg[segment]}"; then
    error::exit "--segment: a number of seconds or auto" "${E_INVALID}"
  fi
  # Decimal numbers have no is:: predicate; plain regex / десятичные числа
  if [[ ! "${__map_cfg[temperature]}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    error::exit "--temperature: a number such as 0.7" "${E_INVALID}"
  fi
  if [[ "${__map_cfg[max_tokens]}" == "auto" ]]; then
    __map_cfg[max_tokens]=""
  elif ! is::number "${__map_cfg[max_tokens]}"; then
    error::exit "--max-tokens: a number or auto" "${E_INVALID}"
  fi
  if is::not_empty "${prompt_file}"; then
    if ! is::file "${prompt_file}"; then
      error::exit "Prompt file not found: ${prompt_file}" \
        "${LIB_ERROR_FILE_NOT_FOUND}"
    fi
    __map_cfg[prompt]="$(<"${prompt_file}")"
  fi
  # Extension of the file NAME (a dot in a directory name or no dot at all
  # must not leak into the chunk path); mp4 when the name has none
  # Расширение ИМЕНИ файла (точка в имени каталога или её отсутствие не
  # должны попадать в путь фрагмента); без расширения — mp4
  __map_cfg[ext]="mp4"
  if [[ "${__map_cfg[file]##*/}" == ?*.* ]]; then
    __map_cfg[ext]="${__map_cfg[file]##*.}"
  fi

  # Run directory: looked up on every start, created only when missing
  __map_cfg[run_dir]="$(sendrun::dir_for "${__map_cfg[out_parent]}" \
    "${__map_cfg[file]}")"
  sendrun::ensure_dir "${__map_cfg[run_dir]}" || dir_rc=$?
  if (( dir_rc == 2 )); then
    error::exit "Cannot use the run directory ${__map_cfg[run_dir]}: \
$(sendrun::explain_dir_error "${__map_cfg[run_dir]}")" \
      "${LIB_ERROR_PERMISSION_DENIED}"
  fi
  # One copy per directory: two runs would write the same checkpoint
  if ! sendrun::lock "${__map_cfg[run_dir]}" video; then
    error::exit "Another send_video is already running in \
${__map_cfg[run_dir]} (lock .video.lock)" "${E_ERROR}"
  fi
  __map_cfg[report]="${__map_cfg[run_dir]}/video.txt"
  __map_cfg[results]="${__map_cfg[run_dir]}/video.jsonl"
  __map_cfg[params]="${__map_cfg[run_dir]}/video.params"
  __map_cfg[state]="${__map_cfg[run_dir]}/video.state"
  __map_cfg[prompt_copy]="${__map_cfg[run_dir]}/video.prompt.txt"
  # Nothing goes to the report until the run decides fresh start or resume
  __map_cfg[output]=""
  __map_cfg[jsonl]=""

  # Maximum log detail: TRACE on screen and in the file by default
  BS_LOG_LEVEL="${__map_cfg[log_level]}"
  if is::empty "${__map_cfg[log_file]}"; then
    __map_cfg[log_file]="${__map_cfg[run_dir]}/send_video_$(utils::stamp).log"
  fi
  : > "${__map_cfg[log_file]}"
  if send_video::__flag_on xtrace; then
    exec {fd}>> "${__map_cfg[log_file]}"
    BASH_XTRACEFD="${fd}"
    PS4='+ ${BASH_SOURCE##*/}:${LINENO}: '
    set -x
  fi
  if (( dir_rc == 0 )); then
    send_video::__log info "run directory exists: ${__map_cfg[run_dir]}"
  else
    send_video::__log info "run directory created: ${__map_cfg[run_dir]}"
  fi
  send_video::__log info "log file: ${__map_cfg[log_file]}"
  return 0
}

# ---------------------------------------------------------------------------
# Run directory: parameters and checkpoint / Параметры и точка остановки
# ---------------------------------------------------------------------------

# @description Save the settings this run works with to video.params.
# @description Сохранить параметры, с которыми идёт прогон, в video.params.
# @return 0 on success; exits if the file cannot be written
send_video::__save_params() {
  local -n __map_cfg=__SEND_VIDEO_CFG
  local -A params=(
    [file]="${__map_cfg[file_abs]}"
    [file_size]="${__map_cfg[file_size]}"
    [duration_ms]="${__map_cfg[duration_ms]:-0}"
    [base]="${__map_cfg[base]}"
    [model]="${__map_cfg[model]}"
    [segment]="${__map_cfg[segment]}"
    [temperature]="${__map_cfg[temperature]}"
    [max_tokens]="${__map_cfg[max_tokens]:-auto}"
    [prompt_sha]="${__map_cfg[prompt_sha]}"
    [saved_at]="$(utils::log_stamp)"
  )
  if ! sendrun::kv_write "${__map_cfg[params]}" params \
    "${SEND_VIDEO_PARAM_KEYS[@]}"; then
    error::exit "Cannot write ${__map_cfg[params]}" "${E_ERROR}"
  fi
  io::streams::print "${__map_cfg[prompt]}" > "${__map_cfg[prompt_copy]}"
  send_video::__log debug "parameters saved: ${__map_cfg[params]}"
  return 0
}

# @description Save the checkpoint (position and counters) to video.state.
# @description Сохранить точку остановки (позицию и счётчики) в video.state.
# @param $1 Status: running|stopped|done / Статус
# @return 0 on success; exits if the file cannot be written
send_video::__save_state() {
  local -n __map_cfg=__SEND_VIDEO_CFG
  local -n __map_stat=__SEND_VIDEO_STAT
  local -n __map_state=__SEND_VIDEO_STATE
  local key
  __map_state[status]="${1:?status required}"
  for key in "${SEND_VIDEO_STAT_KEYS[@]}"; do
    __map_state["${key}"]="${__map_stat[${key}]:-0}"
  done
  # Exact sizes of the files at this moment: on resume everything written
  # after the checkpoint is cut off (a crash between append and state write)
  __map_state[report_bytes]="$(sendrun::size "${__map_cfg[report]}")"
  __map_state[results_bytes]="$(sendrun::size "${__map_cfg[results]}")"
  __map_state[updated_at]="$(utils::log_stamp)"
  if ! sendrun::kv_write "${__map_cfg[state]}" __SEND_VIDEO_STATE \
    "${SEND_VIDEO_STATE_KEYS[@]}"; then
    error::exit "Cannot write ${__map_cfg[state]}" "${E_ERROR}"
  fi
  return 0
}

# @description Ctrl-C, SIGTERM or a closed terminal: mark the checkpoint as
#   stopped and leave. Counters and position are those of the last finished
#   chunk, so nothing half-done is recorded.
# @description Ctrl-C, SIGTERM или закрытый терминал: пометить точку
#   остановки как stopped и выйти. Счётчики и позиция — по последнему
#   готовому фрагменту, недоделанное не записывается.
# @return Does not return
send_video::__interrupted() {
  local -n __map_cfg=__SEND_VIDEO_CFG
  local -n __map_state=__SEND_VIDEO_STATE
  trap - INT TERM HUP
  if is::number "${__map_state[next_chunk]:-}"; then
    __map_state[status]=stopped
    __map_state[updated_at]="$(utils::log_stamp)"
    utils::ignore sendrun::kv_write "${__map_cfg[state]}" \
      __SEND_VIDEO_STATE "${SEND_VIDEO_STATE_KEYS[@]}"
    send_video::__log warn "interrupted; checkpoint saved:" \
      "${__map_cfg[state]}"
    send_video::__log info "rerun the same command to continue from chunk" \
      "$(( __map_state[next_chunk] + 1 ))"
  fi
  exit 130
}

# @description Forget a previous run: parameters, checkpoint, report, results.
#   Logs are kept.
# @description Забыть прошлый прогон: параметры, точку остановки, отчёт и
#   результаты. Журналы остаются.
# @return 0
send_video::__forget_run() {
  local -n __map_cfg=__SEND_VIDEO_CFG
  local -n __map_saved=__SEND_VIDEO_SAVED
  local -n __map_state=__SEND_VIDEO_STATE
  local key
  for key in params state report results prompt_copy; do
    utils::ignore rm -f -- "${__map_cfg[${key}]}"
  done
  __map_saved=()
  __map_state=()
  return 0
}

# @description Look at the run directory and decide: fresh start or resume.
#   Sets cfg[resume] (yes|no) and, when the saved run is the same job, takes
#   the chunk length found earlier instead of probing the server again.
# @description Посмотреть в каталог прогона и решить: с нуля или продолжать.
#   Ставит cfg[resume] (yes|no) и, если сохранённый прогон — та же задача,
#   берёт найденную раньше длину фрагмента, не опрашивая сервер заново.
# @return 0 on success; exits when the saved run conflicts with this one
send_video::__load_run() {
  local -n __map_cfg=__SEND_VIDEO_CFG
  local -n __map_stat=__SEND_VIDEO_STAT
  local -n __map_saved=__SEND_VIDEO_SAVED
  local -n __map_state=__SEND_VIDEO_STATE
  local key diff=""
  local -i progress=0

  __map_cfg[resume]=no
  if send_video::__flag_on restart; then
    send_video::__log warn "--restart: the previous run in" \
      "${__map_cfg[run_dir]} is forgotten (logs are kept)"
    send_video::__forget_run
    return 0
  fi
  if ! sendrun::kv_read "${__map_cfg[params]}" __SEND_VIDEO_SAVED; then
    send_video::__log info "no saved parameters: a fresh run"
    send_video::__forget_run
    return 0
  fi
  utils::ignore sendrun::kv_read "${__map_cfg[state]}" __SEND_VIDEO_STATE
  if is::number "${__map_state[next_chunk]:-}"; then
    progress="${__map_state[next_chunk]}"
  fi

  # The same job = the same file, model and prompt
  for key in file file_size model prompt_sha; do
    case "${key}" in
      file) [[ "${__map_saved[file]:-}" == "${__map_cfg[file_abs]}" ]] ;;
      *)    [[ "${__map_saved[${key}]:-}" == "${__map_cfg[${key}]}" ]] ;;
    esac || diff+=" ${key}"
  done
  if is::number "${__map_cfg[segment]}" \
    && is::number "${__map_saved[segment]:-}" \
    && [[ "${__map_cfg[segment]}" != "${__map_saved[segment]}" ]]; then
    diff+=" segment"
  fi
  if is::not_empty "${diff}"; then
    if (( progress > 0 )) || [[ "${__map_state[status]:-}" == "done" ]]; then
      error::exit "The run directory ${__map_cfg[run_dir]} holds another run\
 (differs in:${diff}). Pass --restart to start over, or another --output." \
        "${E_INVALID}"
    fi
    send_video::__log warn "saved parameters differ in:${diff};" \
      "nothing was processed yet, starting fresh"
    send_video::__forget_run
    return 0
  fi

  if [[ "${__map_cfg[segment]}" == "auto" ]] \
    && is::number "${__map_saved[segment]:-}"; then
    __map_cfg[segment]="${__map_saved[segment]}"
    send_video::__log success "chunk length ${__map_cfg[segment]} s taken" \
      "from ${__map_cfg[params]} (no new probing)"
  fi
  if [[ "${__map_state[status]:-}" == "done" ]]; then
    __map_cfg[resume]=done
    return 0
  fi
  if (( progress > 0 )); then
    __map_cfg[resume]=yes
    send_video::__log info "found an unfinished run (status" \
      "${__map_state[status]:-?}): ${progress} of" \
      "${__map_state[chunks_total]:-?} chunks done," \
      "last update ${__map_state[updated_at]:-?}"
    for key in "${SEND_VIDEO_STAT_KEYS[@]}"; do
      if is::number "${__map_state[${key}]:-}"; then
        __map_stat["${key}"]="${__map_state[${key}]}"
      fi
    done
  fi
  return 0
}

# @description Contact the server and pick the model.
# @description Связаться с сервером и выбрать модель.
# @return 0 on success; exits when the server cannot be used
send_video::__connect() {
  local -n __map_cfg=__SEND_VIDEO_CFG
  local models_json ctx
  send_video::__log info "server: ${__map_cfg[base]}"
  if ! models_json="$(curl -fsS --max-time 10 \
    "${__map_cfg[base]}/v1/models" 2>&1)"; then
    error::exit "Server is unavailable: ${__map_cfg[base]} (${models_json})" \
      "${E_ERROR}"
  fi
  send_video::__log trace "models: ${models_json:0:2000}"
  if is::empty "${__map_cfg[model]}"; then
    __map_cfg[model]="$(jq -r '.data[0].id // empty' <<< "${models_json}")"
  fi
  if is::empty "${__map_cfg[model]}"; then
    error::exit "No model in /v1/models; pass --model" "${E_ERROR}"
  fi
  ctx="$(jq -r '.data[0].max_model_len // "?"' <<< "${models_json}")"
  send_video::__log info "model: ${__map_cfg[model]} (context ${ctx})"
  return 0
}

# @description Cut the video into chunks and list them in the array "$1".
# @description Нарезать видео на фрагменты и перечислить их в массиве "$1".
# @param $1 Name of the output array / Имя выходного массива
# @param $2 Chunk length, seconds; 0 = the whole file / Длина фрагмента
# @return 0 on success; exits if ffmpeg fails
send_video::__make_chunks() {
  local -n __arr_out="${1:?array name required}"
  local -r segment="${2:?segment required}"
  local -n __map_cfg=__SEND_VIDEO_CFG
  local part free_kb
  local -i need_kb

  if (( segment == 0 )); then
    arr::push __arr_out "${__map_cfg[file]}"
    return 0
  fi
  need_kb=$(( $(wc -c < "${__map_cfg[file]}") / 1024 ))
  IFS=' ' read -r _ _ _ free_kb _ \
    <<< "$(df -Pk "${__map_cfg[tmp]}" | tail -n 1)"
  if is::number "${free_kb}" && (( free_kb < need_kb )); then
    send_video::__log warn "temp dir has ~$(( free_kb / 1024 )) MB free," \
      "up to $(( need_kb / 1024 )) MB needed; set TMPDIR to a bigger disk"
  fi
  if ! send_video::__ffmpeg -i "${__map_cfg[file]}" -map 0:v:0 -c copy \
    -f segment -segment_time "${segment}" -reset_timestamps 1 \
    "${__map_cfg[tmp]}/part_%05d.${__map_cfg[ext]}"; then
    error::exit "ffmpeg could not cut the video" "${E_ERROR}"
  fi
  for part in "${__map_cfg[tmp]}"/part_*."${__map_cfg[ext]}"; do
    if is::file "${part}"; then
      arr::push __arr_out "${part}"
    fi
  done
  if (( ${#__arr_out[@]} == 0 )); then
    error::exit "ffmpeg produced no chunks" "${E_ERROR}"
  fi
  send_video::__log info "chunks: ${#__arr_out[@]}"
  return 0
}

# @description Write the final statistics to the report.
# @description Записать итоговую статистику в отчёт.
# @param $1 Video length, ms / Длина видео, мс
# @param $2 Wall time, ms / Общее время, мс
# @return 0
send_video::__summary() {
  local -r dur_ms="${1:-0}"
  local -r wall_ms="${2:-0}"
  local -n __map_stat=__SEND_VIDEO_STAT
  local -i done_n="${__map_stat[done]:-0}" model_ms="${__map_stat[model_ms]:-0}"
  local -i speed

  send_video::__report ""
  send_video::__report "=== Итого ==="
  send_video::__report "Фрагментов обработано: ${done_n}," \
    "ошибок: ${__map_stat[failed]:-0}," \
    "автоделений: ${__map_stat[splits]:-0}"
  send_video::__report "Токенов видео: ${__map_stat[tokens]:-0}"
  send_video::__report "Общее время: $(send_video::__timecode "${wall_ms}")" \
    "($(( wall_ms / 1000 )) с)"
  send_video::__report "Время ответов модели:" \
    "$(send_video::__timecode "${model_ms}")"
  if (( done_n > 0 )); then
    send_video::__report "Среднее на фрагмент:" \
      "$(send_video::__seconds "$(( model_ms / done_n ))") с"
  fi
  if (( dur_ms > 0 && wall_ms > 0 )); then
    speed=$(( dur_ms * 10 / wall_ms ))
    send_video::__report \
      "Скорость: $(( speed / 10 )).$(( speed % 10 ))x от реального времени"
  fi
  return 0
}

# @description Run the whole pipeline: checks, search, chunks, report.
# @description Выполнить весь процесс: проверки, подбор, фрагменты, отчёт.
# @param $@ Command-line arguments / Аргументы командной строки
# @return Does not return: leaves through bs::exit
send_video::main() {
  local -n __map_cfg=__SEND_VIDEO_CFG
  local -n __map_stat=__SEND_VIDEO_STAT
  local -n __map_state=__SEND_VIDEO_STATE
  local -a chunks=()
  local -A before=()
  local key
  local -i t_run i dur_ms=0 total=0 offset_ms=0 chunk_ms segment
  local -i first=0 wall_before=0 cut_bytes=0

  # Decimal separators must not depend on the user's locale
  export LC_NUMERIC=C

  send_video::__declare_flags
  args::require "$@"
  t_run="$(utils::now_ms)"
  send_video::__configure
  signal::on INT send_video::__interrupted
  signal::on TERM send_video::__interrupted
  signal::on HUP send_video::__interrupted

  if [[ "${__map_cfg[segment]}" != "0" ]]; then
    send_video::__check_deps yes
  else
    send_video::__check_deps no
  fi
  __map_cfg[tmp]="$(mktemp -d "${TMPDIR:-/tmp}/send_video.XXXXXX")"
  cleanup::add send_video::__cleanup
  send_video::__connect

  __map_cfg[file_abs]="$(sendrun::abs_path "${__map_cfg[file]}")"
  __map_cfg[file_size]=$(( $(wc -c < "${__map_cfg[file]}") ))
  __map_cfg[prompt_sha]="$(sendrun::hash \
    "${__map_cfg[system]}"$'\n'"${__map_cfg[prompt]}")"
  send_video::__load_run
  send_video::__log_environment

  if [[ "${__map_cfg[resume]}" == "done" ]] \
    && ! send_video::__flag_on suggest; then
    send_video::__log success "this video is already processed:" \
      "${__map_cfg[report]}"
    send_video::__log info "pass --restart to process it again"
    bs::exit success
  fi

  if [[ "${__map_cfg[segment]}" != "0" ]]; then
    if ! dur_ms="$(send_video::__duration_ms "${__map_cfg[file]}")"; then
      error::exit "ffprobe could not read the video length" "${E_ERROR}"
    fi
    total=$(( (dur_ms + 999) / 1000 ))
    send_video::__log info "video length: ${dur_ms} ms"
  fi
  __map_cfg[duration_ms]="${dur_ms}"

  if [[ "${__map_cfg[segment]}" == "auto" ]]; then
    if ! send_video::__find_segment "${total}"; then
      error::exit "Could not find a chunk length the server accepts" \
        "${E_ERROR}"
    fi
    __map_cfg[segment]="${__map_stat[found]}"
    send_video::__log success \
      "chunk length found: ${__map_cfg[segment]} s (0 = the whole file)"
  fi
  segment="${__map_cfg[segment]}"
  # The chunk length is known now: keep it so that a rerun does not probe
  if [[ "${__map_cfg[resume]}" == "no" ]]; then
    send_video::__save_params
  fi
  if send_video::__flag_on suggest; then
    send_video::__log info \
      "probe found: ${segment} s; --suggest only reports it," \
      "the video transcription is not started"
    io::streams::print "Используйте: --segment ${segment}"
    io::streams::print "Сохранено в ${__map_cfg[params]}:" \
      "следующий запуск возьмёт это значение сам"
    bs::exit success
  fi
  send_video::__log info \
    "probe found: ${segment} s — starting the video transcription now"

  # Cut first: a resume is only valid if the video is cut the same way
  send_video::__make_chunks chunks "${segment}"
  __map_cfg[output]="${__map_cfg[report]}"
  if [[ "${__map_cfg[resume]}" == "yes" ]]; then
    if [[ "${#chunks[@]}" != "${__map_state[chunks_total]:-}" ]]; then
      error::exit "The video is cut into ${#chunks[@]} chunks now, the \
checkpoint was made for ${__map_state[chunks_total]:-?}. Pass --restart to \
start over." "${E_INVALID}"
    fi
    # Bring the report and the results back to the checkpoint
    for key in report results; do
      if ! is::number "${__map_state[${key}_bytes]:-}"; then
        continue
      fi
      if ! cut_bytes="$(sendrun::truncate_to "${__map_cfg[${key}]}" \
        "${__map_state[${key}_bytes]}")"; then
        error::exit "${__map_cfg[${key}]} is shorter than the checkpoint \
says: data was lost. Pass --restart to start over." "${E_ERROR}"
      fi
      if (( cut_bytes > 0 )); then
        send_video::__log warn "${__map_cfg[${key}]##*/}: cut ${cut_bytes} B" \
          "written after the checkpoint (an interrupted run)"
      fi
    done
    first="${__map_state[next_chunk]}"
    offset_ms="${__map_state[offset_ms]:-0}"
    wall_before="${__map_state[wall_ms]:-0}"
    send_video::__log success "resuming from chunk $(( first + 1 ))" \
      "($(sendrun::timecode_ms "${offset_ms}")), checkpoint" \
      "${__map_cfg[state]}"
    send_video::__report ""
    send_video::__report "# Продолжение $(utils::log_stamp): с фрагмента" \
      "$(( first + 1 )) ($(sendrun::timecode_ms "${offset_ms}"))"
  else
    : > "${__map_cfg[report]}"
    : > "${__map_cfg[results]}"
    send_video::__report "# send_video: ${__map_cfg[file_abs]}"
    send_video::__report "# $(utils::log_stamp) | ${__map_cfg[base]} |" \
      "${__map_cfg[model]}"
    send_video::__report "# segment=${segment}" \
      "temperature=${__map_cfg[temperature]}" \
      "max-tokens=${__map_cfg[max_tokens]:-auto}"
    if (( dur_ms > 0 )); then
      send_video::__report "# Длина видео: $(sendrun::timecode_ms "${dur_ms}")"
    fi
  fi

  __map_state[chunks_total]="${#chunks[@]}"
  __map_state[next_chunk]="${first}"
  __map_state[offset_ms]="${offset_ms}"
  __map_state[wall_ms]="${wall_before}"
  send_video::__save_state running

  for (( i = 0; i < ${#chunks[@]}; i++ )); do
    if (( i < first )); then
      # segment 0: the "chunk" is the user's own file, never delete it
      # segment 0: «фрагмент» — это файл пользователя, его не удаляем
      if (( segment != 0 )); then
        utils::ignore rm -f "${chunks[i]}"
      fi
      continue
    fi
    # A chunk is written to buffers first: the report and the results get it
    # only as a whole, so an interrupted chunk leaves no half-written entry
    __map_cfg[output]="${__map_cfg[tmp]}/chunk.txt"
    __map_cfg[jsonl]="${__map_cfg[tmp]}/chunk.jsonl"
    : > "${__map_cfg[output]}"
    : > "${__map_cfg[jsonl]}"
    for key in "${SEND_VIDEO_STAT_KEYS[@]}"; do
      before["${key}"]="${__map_stat[${key}]:-0}"
    done

    if (( segment == 0 )); then
      send_video::__process_chunk "${chunks[i]}" 0 "" 0
    else
      send_video::__process_chunk "${chunks[i]}" "${offset_ms}" \
        "$(( i + 1 ))/${#chunks[@]}" 0
    fi

    if (( ${__map_stat[failed]:-0} > before[failed] )) \
      && ! send_video::__flag_on keep-going; then
      # Stop here: the checkpoint still points at this chunk
      for key in "${SEND_VIDEO_STAT_KEYS[@]}"; do
        __map_stat["${key}"]="${before[${key}]}"
      done
      __map_cfg[output]=""
      __map_cfg[jsonl]=""
      __map_state[wall_ms]=$(( wall_before + $(utils::now_ms) - t_run ))
      send_video::__save_state stopped
      send_video::__log error "chunk $(( i + 1 ))/${#chunks[@]} failed —" \
        "stopped; $(( i )) of ${#chunks[@]} chunks are done"
      send_video::__log info "rerun the same command to continue from chunk" \
        "$(( i + 1 )); --keep-going skips failed chunks instead"
      send_video::__log info "log file: ${__map_cfg[log_file]}"
      bs::exit "${E_ERROR}"
    fi

    cat -- "${__map_cfg[tmp]}/chunk.txt" >> "${__map_cfg[report]}"
    cat -- "${__map_cfg[tmp]}/chunk.jsonl" >> "${__map_cfg[results]}"
    if (( segment != 0 )); then
      if chunk_ms="$(send_video::__duration_ms "${chunks[i]}")"; then
        offset_ms=$(( offset_ms + chunk_ms ))
      else
        offset_ms=$(( offset_ms + segment * 1000 ))
      fi
      utils::ignore rm -f "${chunks[i]}"
    fi
    __map_state[next_chunk]=$(( i + 1 ))
    __map_state[offset_ms]="${offset_ms}"
    __map_state[wall_ms]=$(( wall_before + $(utils::now_ms) - t_run ))
    send_video::__save_state running
  done

  __map_cfg[output]="${__map_cfg[report]}"
  __map_cfg[jsonl]=""
  send_video::__summary "${dur_ms}" \
    "$(( wall_before + $(utils::now_ms) - t_run ))"
  send_video::__save_state done
  send_video::__log info "report: ${__map_cfg[report]}"
  send_video::__log info "results: ${__map_cfg[results]}"
  send_video::__log info "log file: ${__map_cfg[log_file]}"
  if (( ${__map_stat[failed]:-0} > 0 )); then
    bs::exit "${E_ERROR}"
  fi
  bs::exit success
}

send_video::main "$@"
