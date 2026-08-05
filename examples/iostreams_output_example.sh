#!/usr/bin/env bs
# shellcheck shell=bash
# examples/iostreams_output_example.sh — Safe output demo for io::streams
# examples/iostreams_output_example.sh — Демонстрация безопасного вывода io::streams
#
# Этот скрипт демонстрирует функции вывода модуля io::streams:
#   print, printn, printf, eprint, tty_print
# This script demonstrates the output functions of the io::streams module:
#   print, printn, printf, eprint, tty_print

# Запуск / Run:
#   bs run examples/iostreams_output_example.sh [args]
#   ./examples/iostreams_output_example.sh            # bs должен быть в PATH / bs must be in PATH

# Подключаем модуль потоков / Load the streams module
load "lib/io/streams"

main() {
    # ==========================================
    # 1. print — безопасный вывод строки / safe line output
    # ==========================================
    log::header "io::streams::print — safe output / безопасный вывод"

    # Обычный вывод с переводом строки / Plain output with trailing newline
    io::streams::print "Hello, BS!"

    # echo "$var" ломается, если var='-n' или '-e' — print выводит как есть
    # echo "$var" breaks when var='-n' or '-e' — print outputs it literally
    io::streams::print "-n"
    io::streams::print "-e"

    # ==========================================
    # 2. printn — вывод без перевода строки / output without newline
    # ==========================================
    log::header "io::streams::printn — no trailing newline / без перевода строки"

    # Собираем строку из частей / Build a line from parts
    io::streams::printn "Loading"
    io::streams::printn "..."
    io::streams::print " done"

    # ==========================================
    # 3. printf — форматированный вывод / formatted output
    # ==========================================
    log::header "io::streams::printf — formatted output / форматированный вывод"

    # Формат — отдельный аргумент, данные не попадают в format string
    # Format is a separate argument, data never lands in the format string
    io::streams::printf 'PID: %04d\n' 7
    io::streams::printf '%-10s | %s\n' "load" "0.50" "users" "12"

    # ==========================================
    # 4. eprint — вывод в stderr / output to stderr
    # ==========================================
    log::header "io::streams::eprint — stderr"

    # Диагностика идёт в stderr и не загрязняет stdout пайплайна
    # Diagnostics go to stderr and do not pollute the pipeline stdout
    io::streams::eprint "warning: this line goes to stderr"

    # ==========================================
    # 5. tty_print — вывод в терминал мимо перенаправлений
    #    tty_print — output to terminal bypassing redirections
    # ==========================================
    log::header "io::streams::tty_print — /dev/tty"

    # Полезно для диагностики, когда stdout уходит в файл или pipe
    # Useful for diagnostics when stdout is redirected to a file or pipe
    if io::streams::is_tty 1; then
        io::streams::tty_print "This line always reaches the terminal"
    else
        log::info "No controlling terminal in this environment, skipping tty_print"
        log::info "В этом окружении нет управляющего терминала, tty_print пропущен"
    fi

    log::success "Output demo finished / Демонстрация вывода завершена"
}

main "$@"
