#!/usr/bin/env bs
# examples/iostreams_state_example.sh — Stream state demo for io::streams
# examples/iostreams_state_example.sh — Демонстрация состояния потоков io::streams
#
# Этот скрипт демонстрирует проверку состояния потоков:
#   is_tty, can_read, wait_readable
# This script demonstrates stream state checks:
#   is_tty, can_read, wait_readable

set -euo pipefail

# Подключаем BS bootstrap (пути от расположения скрипта)
# Source BS bootstrap (paths relative to the script location)
readonly EXAMPLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${EXAMPLE_DIR}/.." && pwd)"

export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Подключаем модуль потоков / Load the streams module
load "lib/io/streams"

main() {
    # ==========================================
    # 1. is_tty — привязан ли FD к терминалу ([[ -t fd ]])
    #    is_tty — is an FD attached to a terminal ([[ -t fd ]])
    # ==========================================
    log::header "io::streams::is_tty — [[ -t fd ]]"

    # Типичное применение: включать цвета/прогресс-бары только на терминале
    # Typical use: enable colors/progress bars only on a terminal
    if io::streams::is_tty 1; then
        io::streams::print "stdout is a terminal — colors ON"
    else
        io::streams::print "stdout is not a terminal (pipe/file) — colors OFF"
    fi

    # /dev/null — точно не терминал / /dev/null is definitely not a terminal
    exec {check_fd}< /dev/null
    if io::streams::is_tty "${check_fd}"; then
        io::streams::print "unexpected: /dev/null reported as tty"
    else
        io::streams::print "/dev/null is not a terminal, as expected"
    fi
    exec {check_fd}<&-

    # ==========================================
    # 2. can_read — неблокирующая проверка готовности (read -t 0)
    #    can_read — non-blocking readiness check (read -t 0)
    # ==========================================
    log::header "io::streams::can_read — non-blocking check / неблокирующая проверка"

    # Аналог O_NONBLOCK + poll из C; данные НЕ извлекаются из потока
    # Equivalent of O_NONBLOCK + poll from C; data is NOT consumed
    # Перевод строки важен: read без '\n' вернёт код ошибки на EOF,
    # хотя данные прочитает (стандартное поведение read)
    # The newline matters: read without '\n' returns an error code at EOF
    # even though it did read the data (standard read behaviour)
    exec {pipe_fd}< <(printf 'ready\n')
    if io::streams::can_read "${pipe_fd}"; then
        io::streams::print "pipe has data available (nothing consumed yet)"
        local payload=""
        io::streams::read_line payload "${pipe_fd}"
        io::streams::print "read it now: ${payload}"
    fi
    exec {pipe_fd}<&-

    # ==========================================
    # 3. wait_readable — ожидание данных с таймаутом (poll/select)
    #    wait_readable — wait for data with a timeout (poll/select)
    # ==========================================
    log::header "io::streams::wait_readable — poll/select with timeout / с таймаутом"

    # Данные приходят до таймаута / Data arrives before the timeout
    exec {fast_fd}< <(printf 'x')
    if io::streams::wait_readable "${fast_fd}" 1; then
        io::streams::print "data arrived within 1s"
    fi
    exec {fast_fd}<&-

    # Таймаут без данных / Timeout without data
    io::streams::print "Waiting 0.2s on a silent pipe..."
    exec {slow_fd}< <(sleep 2)
    if io::streams::wait_readable "${slow_fd}" 0.2; then
        io::streams::print "unexpected: data arrived"
    else
        io::streams::print "timeout: no data within 0.2s, doing other work"
    fi
    exec {slow_fd}<&-

    # Практический паттерн: не блокировать скрипт на stdin,
    # если пользователь ничего не вводит
    # Practical pattern: do not block the script on stdin
    # when the user is not typing anything

    log::success "Stream state demo finished / Демонстрация состояния потоков завершена"
}

main "$@"
