#!/usr/bin/env bs
# shellcheck shell=bash
# examples/iostreams_redirection_example.sh — Redirection demo for io::streams
# examples/iostreams_redirection_example.sh — Демонстрация перенаправлений io::streams
#
# Этот скрипт демонстрирует функции перенаправления модуля io::streams:
#   redirect_stdout, redirect_stderr, redirect_all, silence
# This script demonstrates the redirection functions of the io::streams module:
#   redirect_stdout, redirect_stderr, redirect_all, silence
#
# Перенаправления действуют на ТЕКУЩИЙ shell (exec), поэтому все демо
# выполняются в подоболочках ( ... ), чтобы не трогать потоки примера.
# Redirections affect the CURRENT shell (exec), so all demos run
# in subshells ( ... ) to keep the example's own streams intact.

# Запуск / Run:
#   bs run examples/iostreams_redirection_example.sh [args]
#   ./examples/iostreams_redirection_example.sh            # bs должен быть в PATH / bs must be in PATH

# Подключаем модуль потоков / Load the streams module
load "lib/io/streams"

main() {
    # Временный каталог для файлов демо / Temporary directory for demo files
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    # Удаляем каталог при выходе (путь разворачивается сразу:
    # tmp_dir — локальная переменная, при EXIT она уже вне области)
    # Remove the directory on exit (the path is expanded now:
    # tmp_dir is local and already out of scope at EXIT)
    trap "rm -rf -- '${tmp_dir}'" EXIT

    # ==========================================
    # 1. redirect_stdout — stdout в файл / stdout to a file
    # ==========================================
    log::header "io::streams::redirect_stdout — exec 1>file"

    (
        io::streams::redirect_stdout "${tmp_dir}/stdout.log"
        io::streams::print "application output"
        io::streams::eprint "this stays on terminal"   # stderr не затронут / stderr untouched
    )
    io::streams::print "stdout.log contains: $(cat "${tmp_dir}/stdout.log")"

    # ==========================================
    # 2. redirect_stderr — stderr в файл / stderr to a file
    # ==========================================
    log::header "io::streams::redirect_stderr — exec 2>file"

    (
        io::streams::redirect_stderr "${tmp_dir}/stderr.log"
        io::streams::print "normal output"
        io::streams::eprint "error details for the log"
    )
    io::streams::print "stderr.log contains: $(cat "${tmp_dir}/stderr.log")"

    # ==========================================
    # 3. redirect_all — stdout+stderr в один файл
    #    redirect_all — stdout+stderr into one file
    # ==========================================
    log::header "io::streams::redirect_all — exec >file 2>&1"

    (
        io::streams::redirect_all "${tmp_dir}/combined.log"
        io::streams::print "output line"
        io::streams::eprint "error line"
    )
    io::streams::print "combined.log contains:"
    io::streams::read_all < "${tmp_dir}/combined.log"

    # Порядок важен: >file 2>&1 ≠ 2>&1 >file
    # Во втором случае stderr останется на терминале!
    # Order matters: >file 2>&1 ≠ 2>&1 >file
    # In the second case stderr stays on the terminal!

    # ==========================================
    # 4. silence — тихий режим (/dev/null)
    #    silence — silent mode (/dev/null)
    # ==========================================
    log::header "io::streams::silence — exec >/dev/null 2>&1"

    io::streams::print "Before silence you can see this"
    (
        io::streams::silence
        io::streams::print "you will NOT see this"
        io::streams::eprint "and will NOT see this either"
    )
    io::streams::print "After the subshell output is back"

    log::success "Redirection demo finished / Демонстрация перенаправлений завершена"
}

main "$@"
