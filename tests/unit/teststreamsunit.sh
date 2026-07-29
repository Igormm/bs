#!/usr/bin/env bs
# tests/unit/teststreamsunit.sh — Unit tests for IO streams module
# tests/unit/teststreamsunit.sh — Модульные тесты для модуля потоков ввода/вывода
#
# Этот файл содержит unit тесты для модуля io::streams (lib/io/streams.sh).
# This file contains unit tests for the io::streams module (lib/io/streams.sh).

set -euo pipefail

# Подключаем тестовый фреймворк (пути от расположения скрипта)
# Source test framework (paths relative to the script location)
readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Подключаем bootstrap BS (ядро загружается через loader)
# Source BS bootstrap (core is loaded via the loader)
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"

# lib-модули подключают core через BS_HOME (pre-existing расхождение BS_ROOT/BS_HOME)
# lib modules source core via BS_HOME (pre-existing BS_ROOT/BS_HOME mismatch)
export BS_HOME="${BS_PROJECT_ROOT}"

# Главная функция тестов
main() {
    print_header "IO Streams Unit Tests"
    print_header "Модульные тесты потоков ввода/вывода"

    testframework::init

    # Тест 1: Инициализация модуля
    testframework::section "Module Initialization / Инициализация модуля"
    load "lib/io/streams"
    testframework::assert_true "${IO_STREAMS_LOADED:-}" "Module initialized"
    testframework::assert_equal "1.0.0" "${IO_STREAMS_VERSION}" "Version correct"

    # Тест 2: Безопасный вывод
    testframework::section "Safe Output / Безопасный вывод"

    testframework::assert_equal "hello" "$(io::streams::print "hello")" "print adds newline"

    # echo сломался бы на '-n' — print выводит как есть
    testframework::assert_equal "-n" "$(io::streams::print "-n")" "print safe against -n"

    testframework::assert_equal "hello" "$(io::streams::printn "hello")" "printn without newline"

    testframework::assert_equal "0007" "$(io::streams::printf '%04d' 7)" "printf formatted output"

    # Данные не попадают в format string
    testframework::assert_equal "%s%s" "$(io::streams::print '%s%s')" "print safe against format injection"

    # Тест 3: Вывод в stderr
    testframework::section "Stderr Output / Вывод в stderr"

    local err_out
    err_out="$(io::streams::eprint "oops" 2>&1 1>/dev/null)"
    testframework::assert_equal "oops" "${err_out}" "eprint writes to stderr"

    local stdout_out
    stdout_out="$(io::streams::eprint "oops" 2>/dev/null)"
    testframework::assert_equal "" "${stdout_out}" "eprint keeps stdout clean"

    # Тест 4: Ввод
    testframework::section "Input / Ввод"

    local line_var=""
    io::streams::read_line line_var <<< "input line"
    testframework::assert_equal "input line" "${line_var}" "read_line reads one line"

    local all_out
    all_out="$(printf 'a\nb\n' | io::streams::read_all)"
    testframework::assert_equal "$(printf 'a\nb')" "${all_out}" "read_all reads until EOF"

    local feed_out
    feed_out="$(io::streams::feed "input data" grep -o data)"
    testframework::assert_equal "data" "${feed_out}" "feed runs command with here-string"

    # Тест 5: Перенаправления (в подоболочках, чтобы не трогать потоки теста)
    testframework::section "Redirections / Перенаправления"

    local tmp_dir
    tmp_dir="$(mktemp -d)"

    ( io::streams::redirect_stdout "${tmp_dir}/out.log"; io::streams::print "to file" )
    testframework::assert_equal "to file" "$(cat "${tmp_dir}/out.log")" "redirect_stdout writes to file"

    ( io::streams::redirect_stderr "${tmp_dir}/err.log"; io::streams::eprint "err line" )
    testframework::assert_equal "err line" "$(cat "${tmp_dir}/err.log")" "redirect_stderr writes to file"

    ( io::streams::redirect_all "${tmp_dir}/all.log"; io::streams::print "out line"; io::streams::eprint "err line" )
    testframework::assert_equal "$(printf 'out line\nerr line')" "$(cat "${tmp_dir}/all.log")" "redirect_all merges stdout+stderr"

    local silenced
    silenced="$( io::streams::silence; io::streams::print "x"; io::streams::eprint "y" )"
    testframework::assert_equal "" "${silenced}" "silence sends everything to /dev/null"

    # Тест 6: Сохранение и восстановление FD
    testframework::section "FD Save and Restore / Сохранение и восстановление FD"

    local restore_out
    restore_out="$(
        saved_fd=""
        io::streams::save 1 saved_fd
        io::streams::redirect_stdout "${tmp_dir}/saved.log"
        io::streams::print "hidden"
        io::streams::restore "${saved_fd}" 1
        io::streams::print "visible"
    )"
    testframework::assert_equal "visible" "${restore_out}" "restore brings stdout back"
    testframework::assert_equal "hidden" "$(cat "${tmp_dir}/saved.log")" "redirect worked while stdout saved"

    # Закрытие FD: запись в закрытый дескриптор должна падать
    local close_result="true"
    ( exec {test_fd}>&1; io::streams::close "${test_fd}"; io::streams::print "x" >&"${test_fd}" ) 2>/dev/null || close_result="false"
    testframework::assert_equal "false" "${close_result}" "close makes FD unusable"

    # Тест 7: Pipe и буферизация
    testframework::section "Pipe and Buffering / Pipe и буферизация"

    local pipe_out
    pipe_out="$(io::streams::pipe printf 'a\nb\n' -- grep b)"
    testframework::assert_equal "b" "${pipe_out}" "pipe connects two commands"

    if command -v stdbuf >/dev/null 2>&1; then
        testframework::assert_equal "line" "$(io::streams::run_line_buffered printf 'line\n')" "run_line_buffered works"
        testframework::assert_equal "raw" "$(io::streams::run_unbuffered printf 'raw\n')" "run_unbuffered works"
    else
        log::warn "stdbuf not available, skipping buffering tests" 2>/dev/null || true
    fi

    # Тест 8: Состояние потоков
    testframework::section "Stream State / Состояние потоков"

    # /dev/null — не терминал
    local tty_result="true"
    exec {null_fd}< /dev/null
    io::streams::is_tty "${null_fd}" || tty_result="false"
    exec {null_fd}<&-
    testframework::assert_equal "false" "${tty_result}" "is_tty detects non-terminal"

    # can_read: в pipe есть данные
    local read_result="false"
    exec {pipe_fd}< <(printf 'data')
    io::streams::can_read "${pipe_fd}" && read_result="true"
    exec {pipe_fd}<&-
    testframework::assert_equal "true" "${read_result}" "can_read detects available data"

    # wait_readable: данные приходят до таймаута
    local wait_result="false"
    exec {wait_fd}< <(printf 'x')
    io::streams::wait_readable "${wait_fd}" 1 && wait_result="true"
    exec {wait_fd}<&-
    testframework::assert_equal "true" "${wait_result}" "wait_readable returns on data"

    # wait_readable: таймаут без данных
    local timeout_result="true"
    exec {slow_fd}< <(sleep 2)
    io::streams::wait_readable "${slow_fd}" 0.2 || timeout_result="false"
    exec {slow_fd}<&-
    testframework::assert_equal "false" "${timeout_result}" "wait_readable times out without data"

    # Тест 9: Специальные файлы /dev
    testframework::section "/dev Special Files / Специальные файлы /dev"

    local sink_out
    sink_out="$(io::streams::null_sink printf 'lost')"
    testframework::assert_equal "" "${sink_out}" "null_sink discards output"

    local sink_code="true"
    io::streams::null_sink false || sink_code="false"
    testframework::assert_equal "false" "${sink_code}" "null_sink preserves exit code"

    testframework::assert_equal "16" "$(io::streams::random_bytes 16 | wc -c)" "random_bytes returns N bytes"

    testframework::assert_equal "/dev/fd/1" "$(io::streams::fd_path 1)" "fd_path builds /dev/fd path"

    testframework::assert_command "io::streams::list_fds" "list_fds lists open descriptors"

    # Тест 10: Обработка ошибок
    testframework::section "Error Handling / Обработка ошибок"

    testframework::assert_false "io::streams::printf ''" "printf rejects empty format"
    testframework::assert_false "io::streams::read_line ''" "read_line rejects empty variable name"
    testframework::assert_false "io::streams::close 'abc'" "close rejects non-numeric FD"
    testframework::assert_false "io::streams::save 5" "save rejects non-standard FD"
    testframework::assert_false "io::streams::pipe printf x" "pipe rejects missing separator"
    testframework::assert_false "io::streams::random_bytes 0" "random_bytes rejects zero count"

    # Очистка
    rm -rf "${tmp_dir}"

    # Вывод сводки
    testframework::summary
}

# Запуск тестов
main "$@"
