#!/usr/bin/env bs
# examples/iostreams_input_example.sh — Input demo for io::streams
# examples/iostreams_input_example.sh — Демонстрация ввода io::streams
#
# Этот скрипт демонстрирует функции ввода модуля io::streams:
#   read_line, read_all, feed
# This script demonstrates the input functions of the io::streams module:
#   read_line, read_all, feed
#
# Пример неинтерактивный: вместо реального stdin используются
# here-strings и pipe, но функции работают и с клавиатурным вводом.
# The example is non-interactive: here-strings and pipes are used
# instead of a real stdin, but the functions work with keyboard input too.

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
    # 1. read_line — чтение одной строки / read a single line
    # ==========================================
    log::header "io::streams::read_line — one line / одна строка"

    # Интерактивный вариант (закомментирован):
    # Interactive variant (commented out):
    #   io::streams::printn "Enter your name: "
    #   io::streams::read_line user_name

    # Неинтерактивный вариант: строка приходит через here-string
    # Non-interactive variant: the line arrives via a here-string
    local user_name=""
    io::streams::read_line user_name <<< "Igor"
    io::streams::print "Read line: ${user_name}"

    # ==========================================
    # 2. read_all — чтение всего потока до EOF
    #    read_all — read the whole stream until EOF
    # ==========================================
    log::header "io::streams::read_all — until EOF / до EOF"

    # Читаем весь stdout другой команды / Read another command's whole stdout
    local report
    report="$(printf 'line 1\nline 2\nline 3\n' | io::streams::read_all)"
    io::streams::print "Captured report:"
    io::streams::print "${report}"

    # Можно читать и файл: io::streams::read_all < /etc/hostname
    # A file works too: io::streams::read_all < /etc/hostname

    # ==========================================
    # 3. feed — подать строку на stdin команды (аналог <<<)
    #    feed — give a string to a command's stdin (<<< equivalent)
    # ==========================================
    log::header "io::streams::feed — here-string to command / here-string команде"

    # Ищем слово во входной строке / Search a word in the input string
    local found
    found="$(io::streams::feed "error: disk full" grep -o "disk")"
    io::streams::print "grep found: ${found}"

    # Считаем символы во входной строке / Count characters in the input string
    local length
    length="$(io::streams::feed "hello bs" wc -m | tr -d ' ')"
    io::streams::print "Input length (with newline): ${length}"

    log::success "Input demo finished / Демонстрация ввода завершена"
}

main "$@"
