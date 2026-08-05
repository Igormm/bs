#!/usr/bin/env bs
# shellcheck shell=bash
# examples/iostreams_pipe_buffering_example.sh — Pipe and buffering demo
# examples/iostreams_pipe_buffering_example.sh — Демонстрация pipe и буферизации
#
# Этот скрипт демонстрирует pipe и управление буферизацией stdio:
#   pipe, run_line_buffered, run_unbuffered
# This script demonstrates pipes and stdio buffering control:
#   pipe, run_line_buffered, run_unbuffered
#
# Напоминание из справки по потокам: stdout построчно буферизуется
# на терминале и полностью — в pipe/файле; stderr не буферизуется вовсе.
# Reminder from the streams reference: stdout is line-buffered on a
# terminal and fully buffered on pipes/files; stderr is not buffered at all.

# Запуск / Run:
#   bs run examples/iostreams_pipe_buffering_example.sh [args]
#   ./examples/iostreams_pipe_buffering_example.sh            # bs должен быть в PATH / bs must be in PATH

# Подключаем модуль потоков / Load the streams module
load "lib/io/streams"

main() {
    # ==========================================
    # 1. pipe — соединение двух команд (аналог cmd1 | cmd2)
    #    pipe — connecting two commands (cmd1 | cmd2 equivalent)
    # ==========================================
    log::header "io::streams::pipe — cmd1 | cmd2"

    # Под капотом: pipe() + dup2() + fork() в C
    # Under the hood: pipe() + dup2() + fork() in C
    local filtered
    filtered="$(io::streams::pipe printf 'apple\nbanana\ncherry\n' -- grep an)"
    io::streams::print "grep an → ${filtered}"

    local count
    count="$(io::streams::pipe seq 1 100 -- wc -l)"
    io::streams::print "seq 1 100 | wc -l → ${count}"

    # ==========================================
    # 2. run_line_buffered — построчная буферизация (stdbuf -oL)
    #    run_line_buffered — line buffering (stdbuf -oL)
    # ==========================================
    log::header "io::streams::run_line_buffered — stdbuf -oL -eL"

    if command -v stdbuf >/dev/null 2>&1; then
        # Полезно для длинных задач в pipe: строки видны сразу,
        # а не после заполнения 4-8 КБ буфера
        # Useful for long tasks in a pipe: lines appear immediately
        # instead of waiting for the 4-8 KB buffer to fill
        io::streams::run_line_buffered printf 'visible line by line\n'

        # ==========================================
        # 3. run_unbuffered — без буферизации (stdbuf -o0)
        #    run_unbuffered — no buffering (stdbuf -o0)
        # ==========================================
        log::header "io::streams::run_unbuffered — stdbuf -o0 -e0"

        # Максимально «живой» вывод, как у stderr по стандарту
        # The most "live" output, like stderr by the standard
        io::streams::run_unbuffered printf 'unbuffered output\n'
    else
        log::warn "stdbuf not available, skipping buffering demos"
        log::warn "stdbuf недоступен, демонстрация буферизации пропущена"
    fi

    # Замечание: полный аналог unbuffer (expect) эмулирует pty,
    # stdbuf работает только с программами на stdio.
    # Note: the full unbuffer (expect) emulates a pty,
    # stdbuf only works with stdio-based programs.

    log::success "Pipe and buffering demo finished / Демонстрация pipe и буферизации завершена"
}

main "$@"
