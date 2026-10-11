#!/usr/bin/env bs
# shellcheck shell=bash
# examples/send_audio.sh — transcribe the audio track of a video with Whisper
# examples/send_audio.sh — расшифровка звуковой дорожки видео через Whisper
#
# Extracts the audio track with ffmpeg (mono 16 kHz WAV on the timeline of the
# video), sends it to /v1/audio/transcriptions and writes every phrase with
# its start and end in milliseconds from the start of the video.
# Извлекает звуковую дорожку ffmpeg (моно WAV 16 кГц на шкале времени видео),
# шлёт её в /v1/audio/transcriptions и пишет каждую фразу с началом и концом в
# миллисекундах от начала видео.
#
# Everything lives in the run directory <output>/<video name>/, next to the
# files of send_video.sh: audio.params, audio.state (checkpoint), audio.txt,
# audio.jsonl, audio.wav and the logs. A rerun continues from the checkpoint.
# Всё лежит в каталоге прогона <output>/<имя видео>/, рядом с файлами
# send_video.sh: audio.params, audio.state (точка остановки), audio.txt,
# audio.jsonl, audio.wav и журналы. Повторный запуск продолжает с остановки.
#
# Usage / Использование:
#   bs run examples/send_audio.sh --file clip.mp4 --host llm.local --port 8001
#   bs run examples/send_audio.sh --file clip.mp4 --language ru
#   bs run examples/send_audio.sh --file clip.mp4 --output ~/results
#   bs run examples/send_audio.sh --file clip.mp4 --restart
#   bs run examples/send_audio.sh --help

load "core/args"
load "core/deps"
load "core/errorhandler"
load "core/logger"
load "lib/io/streams"

bs::source_relative "send_common.sh"

# @global SEND_AUDIO_DEFAULT_HOST — constant (category: constant); server host
# @global SEND_AUDIO_DEFAULT_HOST — константа (категория: constant); хост
readonly SEND_AUDIO_DEFAULT_HOST="${SEND_AUDIO_HOST:-127.0.0.1}"

# @global SEND_AUDIO_DEFAULT_PORT — constant (category: constant); server port
# @global SEND_AUDIO_DEFAULT_PORT — константа (категория: constant); порт
readonly SEND_AUDIO_DEFAULT_PORT="${SEND_AUDIO_PORT:-8001}"

# @global SEND_AUDIO_DEFAULT_SEGMENT — constant (category: constant); seconds
# @global SEND_AUDIO_DEFAULT_SEGMENT — константа (категория: constant); секунды
readonly SEND_AUDIO_DEFAULT_SEGMENT=600

# @global SEND_AUDIO_STAT_KEYS — constant (category: constant); saved counters
# @global SEND_AUDIO_STAT_KEYS — константа (категория: constant); счётчики
readonly -a SEND_AUDIO_STAT_KEYS=(done phrases model_ms)

# @global SEND_AUDIO_PARAM_KEYS — constant (category: constant); params file
# @global SEND_AUDIO_PARAM_KEYS — константа (категория: constant); параметры
readonly -a SEND_AUDIO_PARAM_KEYS=(file file_size duration_ms base model
  language segment wav saved_at)

# @global SEND_AUDIO_STATE_KEYS — constant (category: constant); checkpoint
# @global SEND_AUDIO_STATE_KEYS — константа (категория: constant); остановка
readonly -a SEND_AUDIO_STATE_KEYS=(status next_chunk chunks_total offset_ms
  done phrases model_ms wall_ms updated_at)

# @global __SEND_AUDIO_CFG — internal state (category: state); run settings
# @global __SEND_AUDIO_CFG — внутреннее состояние (категория: state); настройки
declare -gA __SEND_AUDIO_CFG=()

# @global __SEND_AUDIO_STAT — internal state (category: state); counters
# @global __SEND_AUDIO_STAT — внутреннее состояние (категория: state); счётчики
declare -gA __SEND_AUDIO_STAT=()

# @global __SEND_AUDIO_SAVED — internal state (category: state); loaded params
# @global __SEND_AUDIO_SAVED — внутреннее состояние (категория: state); параметры
declare -gA __SEND_AUDIO_SAVED=()

# @global __SEND_AUDIO_STATE — internal state (category: state); checkpoint
# @global __SEND_AUDIO_STATE — внутреннее состояние (категория: state); остановка
declare -gA __SEND_AUDIO_STATE=()

# ---------------------------------------------------------------------------
# Logging and report / Логирование и отчёт
# ---------------------------------------------------------------------------

# @description Log a message on screen and append it to the log file.
# @description Записать сообщение на экран и дописать его в файл журнала.
# @param $1 Level: trace|debug|info|success|warn|error / Уровень
# @param $@ Message / Сообщение
# @return 0
send_audio::__log() {
  local -r level="${1:?level required}"
  shift
  # "$*" joins with the first IFS char; bs run sets IFS to newline/tab
  local IFS=' '
  local -n __map_cfg=__SEND_AUDIO_CFG
  local -r log_file="${__map_cfg[log_file]:-}"
  local -r msg="$*"
  if is::not_empty "${log_file}"; then
    io::streams::print \
      "$(utils::log_stamp) ${level^^} ${msg}" >> "${log_file}"
  fi
  "log::${level}" "${msg}"
  return 0
}

# @description Print a report line and append it to audio.txt.
# @description Вывести строку отчёта и дописать её в audio.txt.
# @param $@ Text / Текст
# @return 0
send_audio::__report() {
  local IFS=' '
  local -n __map_cfg=__SEND_AUDIO_CFG
  local -r text="$*"
  io::streams::print "${text}"
  if is::not_empty "${__map_cfg[report]:-}"; then
    io::streams::print "${text}" >> "${__map_cfg[report]}"
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
send_audio::__ffmpeg() {
  local -n __map_cfg=__SEND_AUDIO_CFG
  local -r err="${__map_cfg[tmp]}/ffmpeg.err"
  local -a argv=(ffmpeg -hide_banner -loglevel warning -y "$@")
  local -i rc=0
  send_audio::__log debug "run: $(arr::join argv ' ')"
  "${argv[@]}" 2> "${err}" || rc=$?
  if is::file_not_empty "${err}"; then
    send_audio::__log debug "ffmpeg: $(<"${err}")"
  fi
  return "${rc}"
}

# @description Duration of a media file in milliseconds via ffprobe.
# @description Длительность медиафайла в миллисекундах через ffprobe.
# @param $1 File / Файл
# @stdout Milliseconds / Миллисекунды
# @return 0 on success, 1 if ffprobe failed or printed no number
send_audio::__duration_ms() {
  local -r file="${1:?file required}"
  local -r re='^([0-9]+)([.,]([0-9]*))?$'
  local raw frac
  if ! raw="$(ffprobe -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "${file}" 2>&1)"; then
    return 1
  fi
  if [[ ! "${raw}" =~ ${re} ]]; then
    return 1
  fi
  frac="${BASH_REMATCH[3]:-}000"
  io::streams::printf '%d' \
    "$(( 10#${BASH_REMATCH[1]} * 1000 + 10#${frac:0:3} ))"
}

# @description Extract the first audio track as mono 16 kHz WAV. Gaps and a
#   late start are filled with silence, so a position in the WAV is the same
#   position in the video.
# @description Извлечь первую звуковую дорожку как моно WAV 16 кГц. Пропуски
#   и поздний старт заполняются тишиной, поэтому позиция в WAV — та же позиция
#   в видео.
# @param $1 Input media file / Входной медиафайл
# @param $2 Output WAV / Выходной WAV
# @return ffmpeg exit code
send_audio::__extract() {
  send_audio::__ffmpeg -i "${1:?input required}" -vn -sn -map 0:a:0 \
    -af 'aresample=async=1:first_pts=0' -ac 1 -ar 16000 -c:a pcm_s16le \
    "${2:?output required}"
}

# ---------------------------------------------------------------------------
# Server / Сервер
# ---------------------------------------------------------------------------

# @description Check that the server answers and pick the model if it lists
#   one. A Whisper server may have no /v1/models: then no model is sent.
# @description Проверить, что сервер отвечает, и взять модель, если он её
#   перечисляет. У сервера Whisper может не быть /v1/models: тогда модель в
#   запросе не передаётся.
# @return 0 on success; exits when the server cannot be reached
send_audio::__connect() {
  local -n __map_cfg=__SEND_AUDIO_CFG
  local reply
  send_audio::__log info "server: ${__map_cfg[base]}"
  if ! reply="$(curl -sS --max-time 10 "${__map_cfg[base]}/v1/models" 2>&1)"; then
    error::exit "Server is unavailable: ${__map_cfg[base]} (${reply})" \
      "${E_ERROR}"
  fi
  send_audio::__log trace "models: ${reply:0:2000}"
  if is::empty "${__map_cfg[model]}"; then
    __map_cfg[model]="$(utils::quiet_err jq -r '.data[0].id // empty' \
      <<< "${reply}")" || __map_cfg[model]=""
  fi
  send_audio::__log info "model: ${__map_cfg[model]:-(server default)}"
  return 0
}

# @description Send one WAV file for transcription; the answer is left in
#   <tmp>/response.json.
# @description Отправить один WAV на расшифровку; ответ остаётся в
#   <tmp>/response.json.
# @param $1 WAV file / Файл WAV
# @return 0 on success, 1 on a transport or server error
send_audio::__request() {
  local -r chunk="${1:?chunk required}"
  local -n __map_cfg=__SEND_AUDIO_CFG
  local -r tmp="${__map_cfg[tmp]}"
  local -a form=(-F "file=@${chunk};type=audio/wav"
    -F 'response_format=verbose_json')
  local line code ttotal sent

  if is::not_empty "${__map_cfg[model]}"; then
    form+=(-F "model=${__map_cfg[model]}")
  fi
  if is::not_empty "${__map_cfg[language]}"; then
    form+=(-F "language=${__map_cfg[language]}")
  fi
  send_audio::__log debug \
    "request: ${chunk} $(( $(wc -c < "${chunk}") )) B," \
    "language=${__map_cfg[language]:-auto}"

  if ! line="$(curl -sS --max-time "${__map_cfg[timeout]}" "${form[@]}" \
    --stderr "${tmp}/curl.err" \
    -o "${tmp}/response.json" \
    -w '%{http_code} %{time_total} %{size_upload}' \
    "${__map_cfg[base]}/v1/audio/transcriptions")"; then
    send_audio::__log error "curl failed: $(<"${tmp}/curl.err")"
    return 1
  fi
  IFS=' ' read -r code ttotal sent <<< "${line}"
  send_audio::__log debug \
    "response: HTTP ${code}, curl ${ttotal} s, uploaded ${sent} B"
  if [[ "${code}" != "200" ]]; then
    if ! utils::quiet_err jq -r \
      '.error.message // .detail // .message // tostring' \
      "${tmp}/response.json" > "${tmp}/error.txt"; then
      cp "${tmp}/response.json" "${tmp}/error.txt"
    fi
    send_audio::__log warn "server error HTTP ${code}: $(<"${tmp}/error.txt")"
    return 1
  fi
  return 0
}

# @description Turn the server answer into phrases on the video timeline.
#   Understands segments with start_ms/end_ms and the OpenAI verbose_json
#   form (start/end in seconds); an answer without segments becomes one
#   phrase covering the whole chunk.
# @description Превратить ответ сервера во фразы на шкале времени видео.
#   Понимает сегменты со start_ms/end_ms и формат OpenAI verbose_json
#   (start/end в секундах); ответ без сегментов становится одной фразой на
#   весь фрагмент.
# @param $1 Chunk start in the video, ms / Начало фрагмента в видео, мс
# @param $2 Chunk length, ms / Длина фрагмента, мс
# @param $3 Output: JSON lines / Выход: строки JSON
# @param $4 Output: report lines / Выход: строки отчёта
# @return 0 on success, 1 if the answer is not valid JSON
send_audio::__parse() {
  local -n __map_cfg=__SEND_AUDIO_CFG
  local -r response="${__map_cfg[tmp]}/response.json"
  local -r jq_phrases='
    def ms($direct; $seconds):
      if $direct != null then ($direct | floor)
      else (($seconds // 0) * 1000 | round) end;
    . as $root
    | [ ($root.segments // [])[]
        | { start_ms: (ms(.start_ms; .start) + $off),
            end_ms:   (ms(.end_ms; .end) + $off),
            text:     ((.text // "") | gsub("^\\s+|\\s+$"; "")) }
        | select(.text != "") ]
    | if length == 0 and (($root.text // "") | gsub("^\\s+|\\s+$"; "")) != ""
      then [{ start_ms: $off, end_ms: ($off + $len),
              text: ($root.text | gsub("^\\s+|\\s+$"; "")) }]
      else . end
    | .[]'
  local -r jq_line='
    def pad($n): tostring | ("000" + .) | .[-$n:];
    def tc: . as $ms | ($ms / 1000 | floor) as $s
      | "\($s / 3600 | floor | pad(2)):\(($s % 3600) / 60 | floor | pad(2)):"
        + "\($s % 60 | pad(2)).\($ms % 1000 | pad(3))";
    "[\(.start_ms | tc) → \(.end_ms | tc)] \(.text)"'

  if ! jq -c --argjson off "${1:?offset required}" \
    --argjson len "${2:?length required}" "${jq_phrases}" \
    "${response}" > "${3:?jsonl output required}"; then
    return 1
  fi
  jq -r "${jq_line}" "$3" > "${4:?report output required}"
}

# ---------------------------------------------------------------------------
# Environment / Окружение
# ---------------------------------------------------------------------------

# @description Check required programs; stop with a package list if missing.
# @description Проверить нужные программы; при нехватке остановиться.
# @return 0 on success; exits with LIB_ERROR_DEPENDENCY_MISSING otherwise
send_audio::__check_deps() {
  local -a missing=()
  deps::missing_tools missing curl jq ffmpeg ffprobe:ffmpeg \
    mktemp:coreutils wc:coreutils
  if (( ${#missing[@]} > 0 )); then
    error::exit "Missing packages: $(arr::join missing ', ')." \
      "${LIB_ERROR_DEPENDENCY_MISSING}"
  fi
}

# @description Remove the temporary directory; registered as a cleanup.
# @description Удалить временную папку; регистрируется как cleanup.
# @return 0
send_audio::__cleanup() {
  local -n __map_cfg=__SEND_AUDIO_CFG
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
send_audio::__flag() {
  local -n __map_flags=ARGS_FLAGS
  io::streams::printf '%s' "${__map_flags[$1]:-${2-}}"
}

# @description True if a boolean flag was passed.
# @description Истина, если булев флаг указан.
# @param $1 Flag name / Имя флага
# @return 0 if set, 1 otherwise
send_audio::__flag_on() {
  utils::quiet args::flag_get "${1:?flag name required}"
}

# @description Declare all command-line flags.
# @description Объявить все флаги командной строки.
# @return 0
send_audio::__declare_flags() {
  args::flag file value
  args::flag output value .
  args::flag segment value "${SEND_AUDIO_DEFAULT_SEGMENT}" number
  args::flag language value
  args::flag host value "${SEND_AUDIO_DEFAULT_HOST}"
  args::flag port value "${SEND_AUDIO_DEFAULT_PORT}" number
  args::flag model value
  args::flag timeout value 3600 number
  args::flag restart
  args::flag log-level value TRACE "enum:TRACE,DEBUG,INFO,SUCCESS,WARN,ERROR"
  args::flag log-file value

  args::flag_describe file "Видео- или аудиофайл / media file (required)"
  args::flag_describe output \
    "Где создать каталог прогона <имя файла>/ (отчёт, параметры, точка"\
" остановки, журналы); по умолчанию здесь / run directory parent"
  args::flag_describe segment \
    "Секунд звука в одном запросе; 0 = весь файл одним запросом"\
" / seconds of audio per request"
  args::flag_describe language \
    "Язык речи (ru, en, ...); пусто = определить автоматически / language"
  args::flag_describe host "Хост сервера / server host"
  args::flag_describe port "Порт сервера / server port"
  args::flag_describe model \
    "ID модели; по умолчанию первая с сервера или его умолчание / model"
  args::flag_describe timeout "Таймаут запроса, сек / request timeout"
  args::flag_describe restart \
    "Начать заново: забыть параметры, точку остановки и отчёт / start over"
  args::flag_describe log-level "Уровень журнала, по умолчанию TRACE"
  args::flag_describe log-file \
    "Файл журнала (по умолчанию send_audio_<время>.log в каталоге прогона)"
  return 0
}

# ---------------------------------------------------------------------------
# Run directory: parameters and checkpoint / Параметры и точка остановки
# ---------------------------------------------------------------------------

# @description Validate arguments, open the run directory, set up logging.
# @description Проверить аргументы, открыть каталог прогона, настроить журнал.
# @return 0 on success; exits with a framework code on invalid input
send_audio::__configure() {
  local -n __map_cfg=__SEND_AUDIO_CFG
  local -i dir_rc=0
  local key

  __map_cfg[file]="$(send_audio::__flag file)"
  __map_cfg[out_parent]="$(send_audio::__flag output .)"
  __map_cfg[host]="$(send_audio::__flag host "${SEND_AUDIO_DEFAULT_HOST}")"
  __map_cfg[port]="$(send_audio::__flag port "${SEND_AUDIO_DEFAULT_PORT}")"
  __map_cfg[base]="http://${__map_cfg[host]}:${__map_cfg[port]}"
  __map_cfg[model]="$(send_audio::__flag model)"
  __map_cfg[language]="$(send_audio::__flag language)"
  __map_cfg[timeout]="$(send_audio::__flag timeout 3600)"
  __map_cfg[segment]="$(send_audio::__flag segment \
    "${SEND_AUDIO_DEFAULT_SEGMENT}")"
  __map_cfg[log_level]="$(send_audio::__flag log-level TRACE)"
  __map_cfg[log_file]="$(send_audio::__flag log-file)"

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
  if ! is::number "${__map_cfg[segment]}"; then
    error::exit "--segment: a number of seconds, 0 = the whole file" \
      "${E_INVALID}"
  fi

  # Run directory: looked up on every start, created only when missing
  __map_cfg[run_dir]="$(sendrun::dir_for "${__map_cfg[out_parent]}" \
    "${__map_cfg[file]}")"
  sendrun::ensure_dir "${__map_cfg[run_dir]}" || dir_rc=$?
  if (( dir_rc == 2 )); then
    error::exit "Cannot use the run directory: ${__map_cfg[run_dir]}" \
      "${LIB_ERROR_PERMISSION_DENIED}"
  fi
  for key in txt jsonl params state wav; do
    __map_cfg["path_${key}"]="${__map_cfg[run_dir]}/audio.${key}"
  done
  # Nothing goes to the report until the run decides fresh start or resume
  __map_cfg[report]=""

  BS_LOG_LEVEL="${__map_cfg[log_level]}"
  if is::empty "${__map_cfg[log_file]}"; then
    __map_cfg[log_file]="${__map_cfg[run_dir]}/send_audio_$(utils::stamp).log"
  fi
  : > "${__map_cfg[log_file]}"
  if (( dir_rc == 0 )); then
    send_audio::__log info "run directory exists: ${__map_cfg[run_dir]}"
  else
    send_audio::__log info "run directory created: ${__map_cfg[run_dir]}"
  fi
  send_audio::__log info "log file: ${__map_cfg[log_file]}"
  return 0
}

# @description Save the settings this run works with to audio.params.
# @description Сохранить параметры, с которыми идёт прогон, в audio.params.
# @return 0 on success; exits if the file cannot be written
send_audio::__save_params() {
  local -n __map_cfg=__SEND_AUDIO_CFG
  local -A params=(
    [file]="${__map_cfg[file_abs]}"
    [file_size]="${__map_cfg[file_size]}"
    [duration_ms]="${__map_cfg[duration_ms]:-0}"
    [base]="${__map_cfg[base]}"
    [model]="${__map_cfg[model]}"
    [language]="${__map_cfg[language]}"
    [segment]="${__map_cfg[segment]}"
    [wav]="${__map_cfg[path_wav]}"
    [saved_at]="$(utils::log_stamp)"
  )
  if ! sendrun::kv_write "${__map_cfg[path_params]}" params \
    "${SEND_AUDIO_PARAM_KEYS[@]}"; then
    error::exit "Cannot write ${__map_cfg[path_params]}" "${E_ERROR}"
  fi
  send_audio::__log debug "parameters saved: ${__map_cfg[path_params]}"
  return 0
}

# @description Save the checkpoint (position and counters) to audio.state.
# @description Сохранить точку остановки (позицию и счётчики) в audio.state.
# @param $1 Status: running|stopped|done / Статус
# @return 0 on success; exits if the file cannot be written
send_audio::__save_state() {
  local -n __map_cfg=__SEND_AUDIO_CFG
  local -n __map_stat=__SEND_AUDIO_STAT
  local -n __map_state=__SEND_AUDIO_STATE
  local key
  __map_state[status]="${1:?status required}"
  for key in "${SEND_AUDIO_STAT_KEYS[@]}"; do
    __map_state["${key}"]="${__map_stat[${key}]:-0}"
  done
  __map_state[updated_at]="$(utils::log_stamp)"
  if ! sendrun::kv_write "${__map_cfg[path_state]}" __SEND_AUDIO_STATE \
    "${SEND_AUDIO_STATE_KEYS[@]}"; then
    error::exit "Cannot write ${__map_cfg[path_state]}" "${E_ERROR}"
  fi
  return 0
}

# @description Forget a previous run: parameters, checkpoint, report, results
#   and the extracted WAV. Logs are kept.
# @description Забыть прошлый прогон: параметры, точку остановки, отчёт,
#   результаты и извлечённый WAV. Журналы остаются.
# @return 0
send_audio::__forget_run() {
  local -n __map_cfg=__SEND_AUDIO_CFG
  local -n __map_saved=__SEND_AUDIO_SAVED
  local -n __map_state=__SEND_AUDIO_STATE
  local key
  for key in txt jsonl params state wav; do
    utils::ignore rm -f -- "${__map_cfg[path_${key}]}"
  done
  __map_saved=()
  __map_state=()
  return 0
}

# @description Look at the run directory and decide: fresh start or resume.
#   Sets cfg[resume] to no, yes or done.
# @description Посмотреть в каталог прогона и решить: с нуля или продолжать.
#   Ставит cfg[resume] в no, yes или done.
# @return 0 on success; exits when the saved run conflicts with this one
send_audio::__load_run() {
  local -n __map_cfg=__SEND_AUDIO_CFG
  local -n __map_stat=__SEND_AUDIO_STAT
  local -n __map_saved=__SEND_AUDIO_SAVED
  local -n __map_state=__SEND_AUDIO_STATE
  local key diff=""
  local -i progress=0

  __map_cfg[resume]=no
  if send_audio::__flag_on restart; then
    send_audio::__log warn "--restart: the previous run in" \
      "${__map_cfg[run_dir]} is forgotten (logs are kept)"
    send_audio::__forget_run
    return 0
  fi
  if ! sendrun::kv_read "${__map_cfg[path_params]}" __SEND_AUDIO_SAVED; then
    send_audio::__log info "no saved parameters: a fresh run"
    send_audio::__forget_run
    return 0
  fi
  utils::ignore sendrun::kv_read "${__map_cfg[path_state]}" __SEND_AUDIO_STATE
  if is::number "${__map_state[next_chunk]:-}"; then
    progress="${__map_state[next_chunk]}"
  fi

  # The same job = the same file, model, language and chunk length
  [[ "${__map_saved[file]:-}" == "${__map_cfg[file_abs]}" ]] || diff+=" file"
  for key in file_size model language segment; do
    [[ "${__map_saved[${key}]:-}" == "${__map_cfg[${key}]}" ]] \
      || diff+=" ${key}"
  done
  if is::not_empty "${diff}"; then
    if (( progress > 0 )) || [[ "${__map_state[status]:-}" == "done" ]]; then
      error::exit "The run directory ${__map_cfg[run_dir]} holds another run\
 (differs in:${diff}). Pass --restart to start over, or another --output." \
        "${E_INVALID}"
    fi
    send_audio::__log warn "saved parameters differ in:${diff};" \
      "nothing was processed yet, starting fresh"
    send_audio::__forget_run
    return 0
  fi
  if [[ "${__map_state[status]:-}" == "done" ]]; then
    __map_cfg[resume]=done
    return 0
  fi
  if (( progress > 0 )); then
    __map_cfg[resume]=yes
    for key in "${SEND_AUDIO_STAT_KEYS[@]}"; do
      if is::number "${__map_state[${key}]:-}"; then
        __map_stat["${key}"]="${__map_state[${key}]}"
      fi
    done
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Entry point / Точка входа
# ---------------------------------------------------------------------------

# @description Cut the WAV into chunks and list them in the array "$1".
#   PCM is cut without re-encoding, exactly on the sample.
# @description Нарезать WAV на фрагменты и перечислить их в массиве "$1".
#   PCM режется без перекодирования, точно по отсчёту.
# @param $1 Name of the output array / Имя выходного массива
# @param $2 Chunk length, seconds; 0 = the whole file / Длина фрагмента
# @return 0 on success; exits if ffmpeg fails
send_audio::__make_chunks() {
  local -n __arr_out="${1:?array name required}"
  local -r segment="${2:?segment required}"
  local -n __map_cfg=__SEND_AUDIO_CFG
  local part

  if (( segment == 0 )); then
    arr::push __arr_out "${__map_cfg[path_wav]}"
    return 0
  fi
  if ! send_audio::__ffmpeg -i "${__map_cfg[path_wav]}" -c copy \
    -f segment -segment_time "${segment}" -reset_timestamps 1 \
    "${__map_cfg[tmp]}/part_%05d.wav"; then
    error::exit "ffmpeg could not cut the audio" "${E_ERROR}"
  fi
  for part in "${__map_cfg[tmp]}"/part_*.wav; do
    if is::file "${part}"; then
      arr::push __arr_out "${part}"
    fi
  done
  if (( ${#__arr_out[@]} == 0 )); then
    error::exit "ffmpeg produced no chunks" "${E_ERROR}"
  fi
  send_audio::__log info "chunks: ${#__arr_out[@]}"
  return 0
}

# @description Make sure audio.wav is there: reuse it on resume, extract
#   otherwise.
# @description Убедиться, что audio.wav на месте: при продолжении взять
#   готовый, иначе извлечь.
# @return 0 on success; exits if the file has no usable audio track
send_audio::__prepare_wav() {
  local -n __map_cfg=__SEND_AUDIO_CFG
  local streams
  if [[ "${__map_cfg[resume]}" == "yes" ]] \
    && is::file_not_empty "${__map_cfg[path_wav]}"; then
    send_audio::__log info "audio track reused: ${__map_cfg[path_wav]}"
    return 0
  fi
  streams="$(utils::quiet_err ffprobe -v error -select_streams a \
    -show_entries stream=index -of csv=p=0 "${__map_cfg[file]}")" || streams=""
  if is::empty "${streams}"; then
    error::exit "No audio track in ${__map_cfg[file]}" "${E_INVALID}"
  fi
  send_audio::__log info "extracting the audio track to ${__map_cfg[path_wav]}"
  if ! send_audio::__extract "${__map_cfg[file]}" "${__map_cfg[path_wav]}"; then
    error::exit "ffmpeg could not extract the audio track" "${E_ERROR}"
  fi
  return 0
}

# @description Write the final statistics to the report.
# @description Записать итоговую статистику в отчёт.
# @param $1 Audio length, ms / Длина звука, мс
# @param $2 Wall time, ms / Общее время, мс
# @return 0
send_audio::__summary() {
  local -r dur_ms="${1:-0}"
  local -r wall_ms="${2:-0}"
  local -n __map_stat=__SEND_AUDIO_STAT
  local -i speed
  send_audio::__report ""
  send_audio::__report "=== Итого ==="
  send_audio::__report "Фрагментов обработано: ${__map_stat[done]:-0}," \
    "фраз: ${__map_stat[phrases]:-0}"
  send_audio::__report "Общее время: $(sendrun::timecode_ms "${wall_ms}")," \
    "ответы сервера: $(sendrun::timecode_ms "${__map_stat[model_ms]:-0}")"
  if (( dur_ms > 0 && wall_ms > 0 )); then
    speed=$(( dur_ms * 10 / wall_ms ))
    send_audio::__report \
      "Скорость: $(( speed / 10 )).$(( speed % 10 ))x от реального времени"
  fi
  return 0
}

# @description Run the whole pipeline: checks, extraction, chunks, report.
# @description Выполнить весь процесс: проверки, извлечение, фрагменты, отчёт.
# @param $@ Command-line arguments / Аргументы командной строки
# @return Does not return: leaves through bs::exit
send_audio::main() {
  local -n __map_cfg=__SEND_AUDIO_CFG
  local -n __map_stat=__SEND_AUDIO_STAT
  local -n __map_state=__SEND_AUDIO_STATE
  local -a chunks=()
  local -i t_run t_start i dur_ms=0 offset_ms=0 chunk_ms segment
  local -i first=0 wall_before=0 count

  # Decimal separators must not depend on the user's locale
  export LC_NUMERIC=C

  send_audio::__declare_flags
  args::require "$@"
  t_run="$(utils::now_ms)"
  send_audio::__configure
  send_audio::__check_deps
  __map_cfg[tmp]="$(mktemp -d "${TMPDIR:-/tmp}/send_audio.XXXXXX")"
  cleanup::add send_audio::__cleanup
  send_audio::__connect

  __map_cfg[file_abs]="$(sendrun::abs_path "${__map_cfg[file]}")"
  __map_cfg[file_size]=$(( $(wc -c < "${__map_cfg[file]}") ))
  send_audio::__load_run
  if [[ "${__map_cfg[resume]}" == "done" ]]; then
    send_audio::__log success "this file is already transcribed:" \
      "${__map_cfg[path_txt]}"
    send_audio::__log info "pass --restart to transcribe it again"
    bs::exit success
  fi

  send_audio::__prepare_wav
  if ! dur_ms="$(send_audio::__duration_ms "${__map_cfg[path_wav]}")"; then
    error::exit "ffprobe could not read the audio length" "${E_ERROR}"
  fi
  __map_cfg[duration_ms]="${dur_ms}"
  segment="${__map_cfg[segment]}"
  send_audio::__log info "audio length: ${dur_ms} ms," \
    "chunk length: ${segment} s (0 = the whole file)"

  __map_cfg[report]="${__map_cfg[path_txt]}"
  if [[ "${__map_cfg[resume]}" == "yes" ]]; then
    first="${__map_state[next_chunk]}"
    offset_ms="${__map_state[offset_ms]:-0}"
    wall_before="${__map_state[wall_ms]:-0}"
    send_audio::__log success "resuming from chunk $(( first + 1 ))" \
      "($(sendrun::timecode_ms "${offset_ms}")), checkpoint" \
      "${__map_cfg[path_state]}"
  else
    send_audio::__save_params
    : > "${__map_cfg[path_txt]}"
    : > "${__map_cfg[path_jsonl]}"
    send_audio::__report "# send_audio: ${__map_cfg[file_abs]}"
    send_audio::__report "# $(utils::log_stamp) | ${__map_cfg[base]} |" \
      "${__map_cfg[model]:-(server default)}"
    send_audio::__report "# segment=${segment}" \
      "language=${__map_cfg[language]:-auto}"
    send_audio::__report "# Длина звука: $(sendrun::timecode_ms "${dur_ms}")"
    send_audio::__report ""
  fi

  send_audio::__make_chunks chunks "${segment}"
  __map_state[chunks_total]="${#chunks[@]}"
  __map_state[next_chunk]="${first}"
  __map_state[offset_ms]="${offset_ms}"
  __map_state[wall_ms]="${wall_before}"
  send_audio::__save_state running

  for (( i = 0; i < ${#chunks[@]}; i++ )); do
    if (( i < first )); then
      continue
    fi
    if ! chunk_ms="$(send_audio::__duration_ms "${chunks[i]}")"; then
      chunk_ms=$(( segment * 1000 ))
    fi
    send_audio::__log info "send chunk $(( i + 1 ))/${#chunks[@]}" \
      "($(sendrun::timecode_ms "${offset_ms}") –" \
      "$(sendrun::timecode_ms "$(( offset_ms + chunk_ms ))"))"

    t_start="$(utils::now_ms)"
    if ! send_audio::__request "${chunks[i]}" \
      || ! send_audio::__parse "${offset_ms}" "${chunk_ms}" \
        "${__map_cfg[tmp]}/chunk.jsonl" "${__map_cfg[tmp]}/chunk.txt"; then
      # Stop here: the checkpoint still points at this chunk
      __map_state[wall_ms]=$(( wall_before + $(utils::now_ms) - t_run ))
      send_audio::__save_state stopped
      send_audio::__log error "chunk $(( i + 1 ))/${#chunks[@]} failed —" \
        "stopped; $(( i )) of ${#chunks[@]} chunks are done"
      send_audio::__log info \
        "rerun the same command to continue from chunk $(( i + 1 ))"
      send_audio::__log info "log file: ${__map_cfg[log_file]}"
      bs::exit "${E_ERROR}"
    fi

    # A chunk reaches the report and the results only as a whole
    count=$(( $(wc -l < "${__map_cfg[tmp]}/chunk.jsonl") ))
    cat -- "${__map_cfg[tmp]}/chunk.txt"
    cat -- "${__map_cfg[tmp]}/chunk.txt" >> "${__map_cfg[path_txt]}"
    cat -- "${__map_cfg[tmp]}/chunk.jsonl" >> "${__map_cfg[path_jsonl]}"
    __map_stat[done]=$(( ${__map_stat[done]:-0} + 1 ))
    __map_stat[phrases]=$(( ${__map_stat[phrases]:-0} + count ))
    __map_stat[model_ms]=$(( ${__map_stat[model_ms]:-0}
      + $(utils::now_ms) - t_start ))
    send_audio::__log success "chunk $(( i + 1 ))/${#chunks[@]}:" \
      "${count} phrases"

    offset_ms=$(( offset_ms + chunk_ms ))
    __map_state[next_chunk]=$(( i + 1 ))
    __map_state[offset_ms]="${offset_ms}"
    __map_state[wall_ms]=$(( wall_before + $(utils::now_ms) - t_run ))
    send_audio::__save_state running
  done

  send_audio::__summary "${dur_ms}" \
    "$(( wall_before + $(utils::now_ms) - t_run ))"
  send_audio::__save_state done
  send_audio::__log info "report: ${__map_cfg[path_txt]}"
  send_audio::__log info "results: ${__map_cfg[path_jsonl]}"
  send_audio::__log info "log file: ${__map_cfg[log_file]}"
  bs::exit success
}

send_audio::main "$@"
