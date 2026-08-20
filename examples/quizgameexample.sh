#!/usr/bin/env bs
# shellcheck shell=bash
# examples/quizgameexample.sh — Timed quiz: wait_readable on stdin
# examples/quizgameexample.sh — Викторина с таймаутом: wait_readable на stdin
#
# Вопрос с ограничением по времени: ответ ждём через wait_readable
# (аналог poll/select), а не блокирующим read. Без терминала пример
# вежливо пропускает интерактив и прогоняет авто-режим.
# A timed question: the answer is awaited via wait_readable
# (poll/select equivalent), not a blocking read. Without a terminal the
# example politely skips the interactive part and runs an auto mode.
#
# Попробуйте интерактивно / Try it interactively:
#   bs run examples/quizgameexample.sh

# Запуск / Run:
#   bs run examples/quizgameexample.sh [args]
#   ./examples/quizgameexample.sh            # bs должен быть в PATH / bs must be in PATH

load "core/args"
load "lib/io/streams"

readonly QUIZ_ANSWER="4"
readonly QUIZ_TIMEOUT=5

main() {
    args::flag auto
    args::flag_describe auto "Non-interactive demo mode"

    args::require "$@"

    log::header "Timed quiz / Викторина с таймаутом"
    io::streams::print "Question: 2 + 2 = ?"
    io::streams::print "You have ${QUIZ_TIMEOUT} seconds. Type the answer and press Enter."

    # Без терминала stdin — не интерактив: честно пропускаем
    # Without a terminal stdin is not interactive: skip honestly
    if ! io::streams::is_tty 0 || args::flag_get auto >/dev/null; then
        log::warn "No interactive stdin (or --auto): answering for you"
        io::streams::feed "${QUIZ_ANSWER}" io::streams::read_line auto_answer
        io::streams::print "Auto answer: ${auto_answer} — correct!"
        bs::exit success
    fi

    io::streams::printn "> "

    # Ждём ввод с таймаутом: скрипт НЕ висит на read вечно
    # Wait for input with a timeout: the script does NOT hang on read forever
    if io::streams::wait_readable 0 "${QUIZ_TIMEOUT}"; then
        # wait_readable съедает первый байт — дочитываем остаток строки
        # wait_readable consumes the first byte — read the rest of the line
        local rest=""
        io::streams::read_line rest || true
        io::streams::print "Got your answer (first byte was spent on the poll)."

        if [[ "${rest}" == *"${QUIZ_ANSWER}"* ]]; then
            log::success "Correct!"
        else
            log::error "Wrong. The answer was ${QUIZ_ANSWER}."
        fi
    else
        io::streams::print ""
        log::warn "Time is up! The answer was ${QUIZ_ANSWER}."
    fi
}

main "$@"
