#!/usr/bin/env bs
# examples/logmonitorexample.sh — Live log monitor: pipes + non-blocking reads
# examples/logmonitorexample.sh — Живой монитор лога: pipe + неблокирующее чтение
#
# Фоновый «сервис» пишет лог в pipe, а монитор читает его неблокирующе
# через can_read, мигает «тиками» ожидания и считает статистику по ERROR.
# A background "service" writes a log into a pipe, and the monitor reads it
# non-blockingly via can_read, blinks waiting "ticks" and counts ERROR stats.
#
# Показывает на практике: process substitution, /dev/fd, can_read,
# read_line с произвольного FD, pipe между командами.
# Demonstrates in practice: process substitution, /dev/fd, can_read,
# read_line from an arbitrary FD, command pipes.

# Запуск / Run:
#   bs run examples/logmonitorexample.sh [args]
#   ./examples/logmonitorexample.sh            # bs должен быть в PATH / bs must be in PATH

load "lib/io/streams"

# Фейковый сервис: пишет лог со случайными паузами
# Fake service: writes a log with random pauses
fake_service() {
    local i level
    for i in $(seq 1 12); do
        level="INFO"
        if (( RANDOM % 4 == 0 )); then
            level="ERROR"
        fi
        io::streams::printf '[app] %-5s event #%d processed\n' "${level}" "${i}"
        sleep "0.$(( RANDOM % 4 + 1 ))"
    done
}

main() {
    log::header "Live log monitor / Живой монитор лога"
    io::streams::print "Starting fake service, monitoring its pipe..."
    io::streams::print ""

    # Подключаем stdout сервиса на свободный FD текущего shell
    # Attach the service stdout to a free FD of the current shell
    exec {log_fd}< <(fake_service)
    local service_pid=$!

    local lines=0 errors=0 ticks=0
    local line=""

    # Крутимся, пока сервис жив или в pipe остались данные
    # Spin while the service is alive or the pipe still has data
    while kill -0 "${service_pid}" 2>/dev/null || io::streams::can_read "${log_fd}"; do
        if io::streams::can_read "${log_fd}"; then
            # Неблокирующая проверка сказала «есть данные» — читаем строку
            # The non-blocking check said "data available" — read a line
            io::streams::read_line line "${log_fd}" || break
            ((++lines))
            if [[ "${line}" == *ERROR* ]]; then
                ((++errors))
                # Ошибки дублируем в stderr — как настоящий монитор
                # Errors are mirrored to stderr — like a real monitor
                io::streams::eprint "  !! ${line}"
            else
                io::streams::printf '\r%-60s\n' "  ${line}"
            fi
        else
            # Данных нет: живой «тик», скрипт не заблокирован
            # No data: a live "tick", the script is not blocked
            io::streams::printn $'\rmonitoring /'
            sleep 0.1
            io::streams::printn $'\rmonitoring -'
            sleep 0.1
            ((++ticks))
        fi
    done
    exec {log_fd}<&-

    # Итоговая статистика / Final statistics
    io::streams::print ""
    io::streams::print ""
    io::streams::printf '  %-16s %d\n' "lines read" "${lines}" "errors" "${errors}" "idle ticks" "${ticks}"

    # Та же статистика через pipe-модуль / The same stats via the pipe module
    local summary
    summary="$(io::streams::pipe printf 'service finished cleanly\n' -- tr 'a-z' 'A-Z')"
    io::streams::print "${summary}"
}

main "$@"
