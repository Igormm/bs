#!/usr/bin/env bs
# examples/iostreams_fd_example.sh — FD management demo for io::streams
# examples/iostreams_fd_example.sh — Демонстрация управления FD io::streams
#
# Этот скрипт демонстрирует работу с файловыми дескрипторами:
#   save, restore, close
# This script demonstrates file descriptor management:
#   save, restore, close
#
# Аналоги из C: save = dup(STDOUT_FILENO), restore = dup2(saved, 1),
# close = close(fd). Временные FD всегда закрываются, иначе — утечка (EMFILE).
# C equivalents: save = dup(STDOUT_FILENO), restore = dup2(saved, 1),
# close = close(fd). Temporary FDs are always closed, otherwise — a leak (EMFILE).

# Запуск / Run:
#   bs run examples/iostreams_fd_example.sh [args]
#   ./examples/iostreams_fd_example.sh            # bs должен быть в PATH / bs must be in PATH

# Подключаем модуль потоков / Load the streams module
load "lib/io/streams"

main() {
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    # Путь разворачивается сразу: tmp_dir локальна, при EXIT она уже вне области
    # The path is expanded now: tmp_dir is local and out of scope at EXIT
    trap "rm -rf -- '${tmp_dir}'" EXIT

    # ==========================================
    # 1. save + restore — классический паттерн логирования
    #    save + restore — the classic logging pattern
    # ==========================================
    log::header "io::streams::save + io::streams::restore"

    # ВАЖНО: номер FD нельзя получить через $(io::streams::save 1) —
    # $( ) создаёт подоболочку, и дескриптор закроется вместе с ней.
    # Поэтому save пишет номер в переменную вызывающего shell.
    # IMPORTANT: the FD number cannot be obtained via $(io::streams::save 1) —
    # $( ) spawns a subshell and the descriptor dies with it.
    # That is why save stores the number in a caller's variable.
    (
        local saved_fd=""
        io::streams::save 1 saved_fd                     # аналог exec 3>&1 / dup(1)
        io::streams::print "stdout is still the terminal (fd ${saved_fd} saved)"

        io::streams::redirect_stdout "${tmp_dir}/capture.log"
        io::streams::print "this goes to capture.log"

        io::streams::restore "${saved_fd}" 1             # аналог exec 1>&3- / dup2 + close
        io::streams::print "stdout is back to the terminal"
    )
    io::streams::print "capture.log contains: $(cat "${tmp_dir}/capture.log")"

    # ==========================================
    # 2. close — закрытие FD / closing an FD
    # ==========================================
    log::header "io::streams::close — exec n>&-"

    # Открываем копию stdout на свободном FD, затем закрываем её
    # Open a copy of stdout on a free FD, then close it
    (
        exec {my_fd}>&1
        io::streams::print "writing through fd ${my_fd}" >&"${my_fd}"

        io::streams::close "${my_fd}"
        # Запись в закрытый FD завершится ошибкой
        # 2>/dev/null ставим ПЕРЕД >&fd: при ошибке дублирования дескриптора
        # сообщение об ошибке тоже должно уйти в /dev/null
        # Writing to a closed FD fails
        # 2>/dev/null comes BEFORE >&fd: if descriptor duplication fails,
        # the shell's own error message must go to /dev/null too
        # shellcheck disable=SC2261  # конкурирующие редиректы — предмет демонстрации
        if io::streams::print "unreachable" 2>/dev/null >&"${my_fd}"; then
            io::streams::print "unexpected: write to closed fd succeeded"
        else
            io::streams::print "expected: write to closed fd ${my_fd} failed"
        fi
    )

    # ==========================================
    # 3. Паттерн: логирование части скрипта / pattern: logging a script section
    # ==========================================
    log::header "Pattern: log one section to a file / Паттерн: логирование секции"

    (
        local log_fd=""
        io::streams::save 1 log_fd
        io::streams::redirect_all "${tmp_dir}/section.log"

        io::streams::print "=== deploy section started ==="
        io::streams::eprint "deploy warning: low disk space"
        io::streams::print "=== deploy section finished ==="

        io::streams::restore "${log_fd}" 1
        io::streams::print "deploy done (details in section.log)"
    )
    io::streams::print "section.log contents:"
    io::streams::read_all < "${tmp_dir}/section.log"

    log::success "FD demo finished / Демонстрация FD завершена"
}

main "$@"
