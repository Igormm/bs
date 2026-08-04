#!/usr/bin/env bs
# lib/io/streams.sh — Абстракция потоков ввода/вывода, FD и перенаправлений для BS
# lib/io/streams.sh — I/O streams, file descriptors and redirections abstraction for BS
#
# Модуль реализует практические паттерны работы с потоками по материалам
# «Потоки ввода и вывода»: безопасный вывод, перенаправления stdout/stderr,
# сохранение/восстановление FD, тихий режим, pipe, буферизация stdio
# и специальные файлы /dev.
# The module implements practical I/O stream patterns from the
# "Input and Output Streams" reference: safe output, stdout/stderr redirection,
# FD save/restore, silent mode, pipes, stdio buffering and /dev special files.
#
# Использование / Usage:
#   io::streams::print "hello"            # Безопасный вывод / Safe output
#   io::streams::printf '%04d' 7          # Форматированный вывод / Formatted output
#   io::streams::redirect_stdout "log.txt"  # Перенаправить stdout / Redirect stdout
#   io::streams::silence                  # Тихий режим / Silent mode
#   io::streams::save 1 saved             # Сохранить stdout / Save stdout
#   io::streams::restore "${saved}" 1     # Восстановить stdout / Restore stdout
#   io::streams::pipe printf 'a\n' -- cat # Pipe между командами / Pipe commands
#
# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/guard.sh"
bs::guard "IO_STREAMS" || return 0

# Зависимости / Dependencies
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/const.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/logger.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/utils.sh"

# Версия модуля / Module version
declare -g IO_STREAMS_VERSION="1.0.0"

# Номера стандартных потоков / Standard stream numbers
readonly IO_STREAMS_STDIN=0
readonly IO_STREAMS_STDOUT=1
readonly IO_STREAMS_STDERR=2

# ==========================================
# Приватные вспомогательные функции / Private helper functions
# ==========================================

# @private
# @description Проверить, что аргумент — неотрицательное целое число (номер FD)
# @description Check that the argument is a non-negative integer (FD number)
# @param $1 Value to check / Значение для проверки
# @return 0 if valid FD number, 1 otherwise / 0 если валидный номер FD, иначе 1
io::streams::__is_fd() {
    local fd="${1}"
    [[ "${fd}" =~ ^[0-9]+$ ]]
}

# @private
# @description Проверить, что имя файла для перенаправления задано
# @description Check that a redirection target file is specified
# @param $1 File path / Путь к файлу
# @return 0 if valid, 1 otherwise / 0 если валиден, иначе 1
io::streams::__check_file() {
    local file="${1}"

    if [[ -z "${file}" ]]; then
        log::warn "Redirection target file not specified"
        return "${E_ERROR:-1}"
    fi
    return "${E_SUCCESS:-0}"
}

# ==========================================
# Вывод / Output
# ==========================================

# @description Безопасный вывод строки с переводом строки
#   (printf '%s\n' вместо echo — не ломается на '-n', '-e' и '\')
# @description Safe line output with trailing newline
#   (printf '%s\n' instead of echo — safe against '-n', '-e' and '\')
# @param $@ Text to print / Текст для вывода
# @example
#   io::streams::print "hello"
io::streams::print() {
    printf '%s\n' "$*"
}

# @description Вывод без перевода строки / Output without trailing newline
# @param $@ Text to print / Текст для вывода
# @example
#   io::streams::printn "hello"
io::streams::printn() {
    printf '%s' "$*"
}

# @description Форматированный вывод: формат — отдельный аргумент,
#   данные никогда не попадают в format string (защита от format string уязвимости)
# @description Formatted output: format is a separate argument,
#   data never lands in the format string (format string vulnerability safe)
# @param $1 printf format string / Строка формата printf
# @param $@ Format arguments / Аргументы формата
# @example
#   io::streams::printf '%04d' 7
io::streams::printf() {
    local format="${1}"

    if [[ -z "${format}" ]]; then
        log::warn "Format string not specified"
        return "${E_ERROR:-1}"
    fi
    shift
    printf "${format}" "$@"
}

# @description Вывод в stderr / Output to stderr
# @param $@ Text to print / Текст для вывода
# @example
#   io::streams::eprint "error occurred"
io::streams::eprint() {
    printf '%s\n' "$*" >&2
}

# @description Вывод в управляющий терминал (/dev/tty), игнорируя перенаправления
#   Полезно для диагностики, когда stdout/stderr уходят в файл или pipe
# @description Write to the controlling terminal (/dev/tty), bypassing redirections
#   Useful for diagnostics when stdout/stderr are redirected to a file or pipe
# @param $@ Text to print / Текст для вывода
# @return 1 if no controlling terminal / 1 если нет управляющего терминала
# @example
#   io::streams::tty_print "password prompt"
io::streams::tty_print() {
    if [[ -w "/dev/tty" ]]; then
        printf '%s\n' "$*" > /dev/tty
    else
        log::warn "No controlling terminal available (/dev/tty)"
        return "${E_ERROR:-1}"
    fi
}

# ==========================================
# Ввод / Input
# ==========================================

# @description Прочитать одну строку из потока в переменную
# @description Read a single line from a stream into a variable
# @param $1 Variable name for the result / Имя переменной для результата
# @param $2 [optional] FD to read from (default: stdin) / [опционально] FD (по умолчанию: stdin)
# @return 1 on EOF or invalid arguments / 1 при EOF или неверных аргументах
# @example
#   io::streams::read_line answer
io::streams::read_line() {
    local var_name="${1}"
    local fd="${2:-${IO_STREAMS_STDIN}}"

    if [[ -z "${var_name}" ]]; then
        log::warn "Result variable name not specified"
        return "${E_ERROR:-1}"
    fi
    if ! io::streams::__is_fd "${fd}"; then
        log::warn "Invalid file descriptor: ${fd}"
        return "${E_ERROR:-1}"
    fi

    local line
    if ! IFS= read -r -u "${fd}" line; then
        return "${E_ERROR:-1}"
    fi
    printf -v "${var_name}" '%s' "${line}"
}

# @description Прочитать весь поток до EOF / Read the whole stream until EOF
# @param $1 [optional] FD to read from (default: stdin) / [опционально] FD (по умолчанию: stdin)
# @example
#   io::streams::read_all < file.txt
io::streams::read_all() {
    local fd="${1:-${IO_STREAMS_STDIN}}"

    if ! io::streams::__is_fd "${fd}"; then
        log::warn "Invalid file descriptor: ${fd}"
        return "${E_ERROR:-1}"
    fi
    cat <&"${fd}"
}

# @description Запустить команду, подав строку на stdin (аналог here-string <<<)
# @description Run a command feeding a string to its stdin (here-string <<< equivalent)
# @param $1 Input string / Входная строка
# @param $@ Command and its arguments / Команда и её аргументы
# @return Command exit code / Код возврата команды
# @example
#   io::streams::feed "input data" grep "data"
io::streams::feed() {
    local input="${1}"
    shift

    if [[ $# -eq 0 ]]; then
        log::warn "Command not specified"
        return "${E_ERROR:-1}"
    fi
    "$@" <<< "${input}"
}

# ==========================================
# Перенаправления / Redirections
# ==========================================

# @description Перенаправить stdout в файл для текущего shell (exec 1>file)
# @description Redirect stdout to a file for the current shell (exec 1>file)
# @param $1 Target file / Файл назначения
# @example
#   io::streams::redirect_stdout "log.txt"
io::streams::redirect_stdout() {
    local file="${1}"

    io::streams::__check_file "${file}" || return "${E_ERROR:-1}"
    exec 1>"${file}"
}

# @description Перенаправить stderr в файл для текущего shell (exec 2>file)
# @description Redirect stderr to a file for the current shell (exec 2>file)
# @param $1 Target file / Файл назначения
# @example
#   io::streams::redirect_stderr "errors.log"
io::streams::redirect_stderr() {
    local file="${1}"

    io::streams::__check_file "${file}" || return "${E_ERROR:-1}"
    exec 2>"${file}"
}

# @description Объединить stdout+stderr в файл (exec >file 2>&1)
#   Порядок важен: сначала >file, затем 2>&1 — иначе stderr останется в терминале
# @description Merge stdout+stderr into a file (exec >file 2>&1)
#   Order matters: >file first, then 2>&1 — otherwise stderr stays on the terminal
# @param $1 Target file / Файл назначения
# @example
#   io::streams::redirect_all "output.log"
io::streams::redirect_all() {
    local file="${1}"

    io::streams::__check_file "${file}" || return "${E_ERROR:-1}"
    exec >"${file}" 2>&1
}

# @description Тихий режим: отправить stdout и stderr в /dev/null
# @description Silent mode: send stdout and stderr to /dev/null
# @example
#   io::streams::silence
io::streams::silence() {
    exec >/dev/null 2>&1
}

# ==========================================
# Сохранение и восстановление FD / FD save and restore
# ==========================================

# @description Сохранить FD (0, 1 или 2) в новый свободный дескриптор
#   Номер нового FD записывается в переменную вызывающего shell.
#   Вывод через stdout невозможен: $( ) создаёт подоболочку, и дескриптор
#   закрылся бы вместе с ней.
#   Аналог: exec 3>&1 + int saved = dup(STDOUT_FILENO)
# @description Save an FD (0, 1 or 2) into a new free descriptor
#   The new FD number is stored in a caller's shell variable.
#   Printing via stdout is impossible: $( ) spawns a subshell and the
#   descriptor would be closed together with it.
# @param $1 FD to save (0, 1 or 2) / FD для сохранения (0, 1 или 2)
# @param $2 [optional] Result variable name (default: IO_STREAMS_SAVED_FD)
#   [опционально] Имя переменной для результата (по умолчанию: IO_STREAMS_SAVED_FD)
# @return 0 on success, 1 on error / 0 при успехе, 1 при ошибке
# @example
#   io::streams::save 1 saved_fd
io::streams::save() {
    local fd="${1}"
    local result_var="${2:-IO_STREAMS_SAVED_FD}"
    local new_fd

    case "${fd}" in
        "${IO_STREAMS_STDIN}")  exec {new_fd}<&0 ;;
        "${IO_STREAMS_STDOUT}") exec {new_fd}>&1 ;;
        "${IO_STREAMS_STDERR}") exec {new_fd}>&2 ;;
        *)
            log::warn "Only standard FDs 0, 1, 2 can be saved, got: ${fd}"
            return "${E_ERROR:-1}"
            ;;
    esac
    printf -v "${result_var}" '%s' "${new_fd}"
}

# @description Восстановить сохранённый FD и закрыть временный дескриптор (n>&m-)
#   Временный FD закрывается, чтобы избежать утечки FD (EMFILE)
# @description Restore a saved FD and close the temporary descriptor (n>&m-)
#   The temporary FD is closed to avoid descriptor leaks (EMFILE)
# @param $1 Saved FD number from io::streams::save / Сохранённый номер FD
# @param $2 [optional] Target FD (default: 1) / [опционально] Целевой FD (по умолчанию: 1)
# @example
#   io::streams::restore "${saved}" 1
io::streams::restore() {
    local saved="${1}"
    local target="${2:-${IO_STREAMS_STDOUT}}"

    if ! io::streams::__is_fd "${saved}" || ! io::streams::__is_fd "${target}"; then
        log::warn "Invalid file descriptor: saved='${saved}' target='${target}'"
        return "${E_ERROR:-1}"
    fi

    case "${target}" in
        "${IO_STREAMS_STDIN}")  eval "exec 0<&${saved}-" ;;
        "${IO_STREAMS_STDOUT}") eval "exec 1>&${saved}-" ;;
        "${IO_STREAMS_STDERR}") eval "exec 2>&${saved}-" ;;
        *)
            log::warn "Only standard FDs 0, 1, 2 can be restored, got: ${target}"
            return "${E_ERROR:-1}"
            ;;
    esac
}

# @description Закрыть FD текущего shell (exec n>&-)
# @description Close an FD of the current shell (exec n>&-)
# @param $1 FD number to close / Номер FD для закрытия
# @example
#   io::streams::close 3
io::streams::close() {
    local fd="${1}"

    if ! io::streams::__is_fd "${fd}"; then
        log::warn "Invalid file descriptor: ${fd}"
        return "${E_ERROR:-1}"
    fi
    eval "exec ${fd}>&-"
}

# ==========================================
# Pipe и буферизация / Pipes and buffering
# ==========================================

# @description Pipe между двумя командами, разделёнными '--'
#   Аналог: cmd1 | cmd2 (pipe() + dup2() + fork())
# @description Pipe between two commands separated by '--'
#   Equivalent: cmd1 | cmd2 (pipe() + dup2() + fork())
# @param $@ cmd1 args... -- cmd2 args... / аргументы cmd1... -- аргументы cmd2...
# @return Exit code of the second command / Код возврата второй команды
# @example
#   io::streams::pipe printf 'a\nb\n' -- grep b
io::streams::pipe() {
    local -a left=() right=()
    local seen_sep="false"
    local arg

    for arg in "$@"; do
        if [[ "${arg}" == "--" ]] && [[ "${seen_sep}" == "false" ]]; then
            seen_sep="true"
            continue
        fi
        if [[ "${seen_sep}" == "false" ]]; then
            left+=("${arg}")
        else
            right+=("${arg}")
        fi
    done

    if [[ ${#left[@]} -eq 0 ]] || [[ ${#right[@]} -eq 0 ]]; then
        log::warn "Usage: io::streams::pipe cmd1 args... -- cmd2 args..."
        return "${E_ERROR:-1}"
    fi

    "${left[@]}" | "${right[@]}"
}

# @description Запустить команду с построчной буферизацией stdout/stderr (stdbuf -oL -eL)
# @description Run a command with line-buffered stdout/stderr (stdbuf -oL -eL)
# @param $@ Command and its arguments / Команда и её аргументы
# @return Command exit code; 1 if stdbuf missing / Код возврата команды; 1 если нет stdbuf
# @example
#   io::streams::run_line_buffered tail -f app.log
io::streams::run_line_buffered() {
    if [[ $# -eq 0 ]]; then
        log::warn "Command not specified"
        return "${E_ERROR:-1}"
    fi
    if ! utils::has stdbuf; then
        log::warn "stdbuf not available, cannot change buffering"
        return "${E_ERROR:-1}"
    fi
    stdbuf -oL -eL "$@"
}

# @description Запустить команду без буферизации stdout/stderr (stdbuf -o0 -e0)
# @description Run a command with unbuffered stdout/stderr (stdbuf -o0 -e0)
# @param $@ Command and its arguments / Команда и её аргументы
# @return Command exit code; 1 if stdbuf missing / Код возврата команды; 1 если нет stdbuf
# @example
#   io::streams::run_unbuffered long_running_task
io::streams::run_unbuffered() {
    if [[ $# -eq 0 ]]; then
        log::warn "Command not specified"
        return "${E_ERROR:-1}"
    fi
    if ! utils::has stdbuf; then
        log::warn "stdbuf not available, cannot change buffering"
        return "${E_ERROR:-1}"
    fi
    stdbuf -o0 -e0 "$@"
}

# ==========================================
# Состояние потоков / Stream state
# ==========================================

# @description Проверить, привязан ли FD к терминалу ([[ -t fd ]])
# @description Check if an FD is attached to a terminal ([[ -t fd ]])
# @param $1 [optional] FD number (default: stdout) / [опционально] Номер FD (по умолчанию: stdout)
# @return 0 if FD is a terminal, 1 otherwise / 0 если FD — терминал, иначе 1
# @example
#   io::streams::is_tty 1
io::streams::is_tty() {
    local fd="${1:-${IO_STREAMS_STDOUT}}"

    if ! io::streams::__is_fd "${fd}"; then
        log::warn "Invalid file descriptor: ${fd}"
        return "${E_ERROR:-1}"
    fi
    [[ -t "${fd}" ]]
}

# @description Неблокирующая проверка готовности FD к чтению (read -t 0)
#   Данные из потока не извлекаются
# @description Non-blocking check whether an FD is readable (read -t 0)
#   No data is consumed from the stream
# @param $1 [optional] FD number (default: stdin) / [опционально] Номер FD (по умолчанию: stdin)
# @return 0 if data is available, 1 otherwise / 0 если есть данные, иначе 1
# @example
#   io::streams::can_read 0
io::streams::can_read() {
    local fd="${1:-${IO_STREAMS_STDIN}}"

    if ! io::streams::__is_fd "${fd}"; then
        log::warn "Invalid file descriptor: ${fd}"
        return "${E_ERROR:-1}"
    fi
    utils::quiet_err read -t 0 -u "${fd}"
}

# @description Ждать готовности FD к чтению с таймаутом (poll/select аналог)
#   Внимание: при успехе из потока извлекается один байт
# @description Wait for an FD to become readable with a timeout (poll/select equivalent)
#   Note: on success one byte is consumed from the stream
# @param $1 FD number / Номер FD
# @param $2 Timeout in seconds / Таймаут в секундах
# @return 0 if data arrived, 1 on timeout or error / 0 если данные пришли, 1 при таймауте или ошибке
# @example
#   io::streams::wait_readable 0 5
io::streams::wait_readable() {
    local fd="${1}"
    local timeout="${2}"

    if ! io::streams::__is_fd "${fd}"; then
        log::warn "Invalid file descriptor: ${fd}"
        return "${E_ERROR:-1}"
    fi
    if [[ -z "${timeout}" ]]; then
        log::warn "Timeout not specified"
        return "${E_ERROR:-1}"
    fi

    local byte
    local IFS=""
    utils::quiet_err read -r -t "${timeout}" -u "${fd}" -n 1 byte
}

# ==========================================
# Специальные файлы /dev / /dev special files
# ==========================================

# @description Запустить команду, отправив весь вывод в /dev/null
#   Код возврата команды сохраняется
# @description Run a command sending all output to /dev/null
#   The command exit code is preserved
# @param $@ Command and its arguments / Команда и её аргументы
# @return Command exit code / Код возврата команды
# @example
#   io::streams::null_sink noisy_command --flag
io::streams::null_sink() {
    if [[ $# -eq 0 ]]; then
        log::warn "Command not specified"
        return "${E_ERROR:-1}"
    fi
    "$@" >/dev/null 2>&1
}

# @description Прочитать N псевдослучайных байт из /dev/urandom (не блокирует)
# @description Read N pseudo-random bytes from /dev/urandom (non-blocking)
# @param $1 Number of bytes / Количество байт
# @example
#   io::streams::random_bytes 32 | base64
io::streams::random_bytes() {
    local count="${1}"

    if ! io::streams::__is_fd "${count}" || [[ "${count}" -eq 0 ]]; then
        log::warn "Byte count must be a positive integer, got: ${count}"
        return "${E_ERROR:-1}"
    fi
    if [[ ! -r "/dev/urandom" ]]; then
        log::error "/dev/urandom is not readable"
        return "${E_ERROR:-1}"
    fi
    head -c "${count}" /dev/urandom
}

# @description Путь к FD текущего процесса через /dev/fd (аналог /proc/self/fd)
# @description Path to a current process FD via /dev/fd (/proc/self/fd equivalent)
# @param $1 FD number / Номер FD
# @return Prints /dev/fd/N path; 1 on error / Выводит путь /dev/fd/N; 1 при ошибке
# @example
#   cat "$(io::streams::fd_path 0)"
io::streams::fd_path() {
    local fd="${1}"

    if ! io::streams::__is_fd "${fd}"; then
        log::warn "Invalid file descriptor: ${fd}"
        return "${E_ERROR:-1}"
    fi
    printf '%s\n' "/dev/fd/${fd}"
}

# @description Список открытых FD текущего процесса (/proc/self/fd)
# @description List open FDs of the current process (/proc/self/fd)
# @example
#   io::streams::list_fds
io::streams::list_fds() {
    if [[ -d "/proc/self/fd" ]]; then
        utils::quiet_err ls -l /proc/self/fd
    elif [[ -d "/dev/fd" ]]; then
        utils::quiet_err ls -l /dev/fd
    else
        log::warn "No method available to list file descriptors"
        return "${E_ERROR:-1}"
    fi
}

# ==========================================
# Инициализация модуля / Module initialization
# ==========================================

# Отмечаем модуль как загруженный / Mark module as loaded
declare -g IO_STREAMS_LOADED="1"

utils::quiet_err log::debug "IO streams module initialized, version: ${IO_STREAMS_VERSION}" || true
