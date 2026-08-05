#!/usr/bin/env bs
# shellcheck shell=bash
# examples/iostreams_dev_example.sh — /dev special files demo for io::streams
# examples/iostreams_dev_example.sh — Демонстрация специальных файлов /dev
#
# Этот скрипт демонстрирует работу со специальными файлами /dev:
#   null_sink (/dev/null), random_bytes (/dev/urandom),
#   fd_path (/dev/fd/N), list_fds (/proc/self/fd)
# This script demonstrates working with /dev special files:
#   null_sink (/dev/null), random_bytes (/dev/urandom),
#   fd_path (/dev/fd/N), list_fds (/proc/self/fd)

# Запуск / Run:
#   bs run examples/iostreams_dev_example.sh [args]
#   ./examples/iostreams_dev_example.sh            # bs должен быть в PATH / bs must be in PATH

# Подключаем модуль потоков / Load the streams module
load "lib/io/streams"

main() {
    # ==========================================
    # 1. null_sink — весь вывод команды в /dev/null
    #    null_sink — send all command output to /dev/null
    # ==========================================
    log::header "io::streams::null_sink — >/dev/null 2>&1"

    # Код возврата сохраняется — можно проверять результат
    # The exit code is preserved — the result can be checked
    if io::streams::null_sink ls /etc/hostname; then
        io::streams::print "/etc/hostname exists (output was discarded)"
    fi
    if io::streams::null_sink ls /nonexistent_path_12345; then
        io::streams::print "unexpected: nonexistent path listed"
    else
        io::streams::print "expected: ls failed, exit code preserved"
    fi

    # ==========================================
    # 2. random_bytes — псевдослучайные байты из /dev/urandom
    #    random_bytes — pseudo-random bytes from /dev/urandom
    # ==========================================
    log::header "io::streams::random_bytes — /dev/urandom"

    # /dev/urandom не блокируется; подходит для токенов и UUID
    # /dev/urandom never blocks; suitable for tokens and UUIDs
    local token
    token="$(io::streams::random_bytes 16 | base64)"
    io::streams::print "Random token: ${token}"

    # Для криптографически важных значений используйте /dev/random
    # или getrandom(2) напрямую
    # For cryptographically critical values use /dev/random
    # or getrandom(2) directly

    # ==========================================
    # 3. fd_path — путь к FD процесса через /dev/fd
    #    fd_path — process FD path via /dev/fd
    # ==========================================
    log::header "io::streams::fd_path — /dev/fd/N"

    # /dev/fd/N — Linux-аналог /proc/self/fd/N
    # /dev/fd/N is the Linux equivalent of /proc/self/fd/N
    io::streams::print "stdin path:  $(io::streams::fd_path 0)"
    io::streams::print "stdout path: $(io::streams::fd_path 1)"

    # Классический трюк: cat /dev/fd/0 читает stdin
    # The classic trick: cat /dev/fd/0 reads stdin
    local via_fd
    via_fd="$(printf 'through fd' | cat "$(io::streams::fd_path 0)")"
    io::streams::print "cat /dev/fd/0 → ${via_fd}"

    # ==========================================
    # 4. list_fds — открытые дескрипторы процесса
    #    list_fds — open process descriptors
    # ==========================================
    log::header "io::streams::list_fds — /proc/self/fd"

    # Полезно для поиска утечек FD (EMFILE)
    # Useful for hunting FD leaks (EMFILE)
    io::streams::list_fds

    # Из справки: /dev/full всегда возвращает ENOSPC при записи —
    # удобен для тестирования обработки ошибок записи:
    # From the reference: /dev/full always returns ENOSPC on write —
    # handy for testing write error handling:
    if printf 'x' > /dev/full 2>/dev/null; then
        io::streams::print "unexpected: write to /dev/full succeeded"
    else
        io::streams::print "/dev/full returned ENOSPC, as expected"
    fi

    log::success "/dev demo finished / Демонстрация /dev завершена"
}

main "$@"
