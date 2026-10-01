#!/usr/bin/env bs
# shellcheck shell=bash
# examples/output_contract/header_box.sh — output contract demo: header box
# examples/output_contract/header_box.sh — демо контракта вывода: рамка-заголовок
#
# log::header — юникод-рамка ╭─╮ по умолчанию или классическое
# подчёркивание вторым аргументом.
# log::header — unicode box ╭─╮ by default, or a classic underline
# passed as the second argument.
#
# Run / Запуск:
#   bs run examples/output_contract/header_box.sh

load "core/logger"

main() {
    printf 'Рамка / Box (по умолчанию / default):\n\n'
    log::header "Заголовок / Header — box"
    printf '\nПодчёркивание / Underline (второй аргумент / 2nd arg):\n\n'
    log::header "Заголовок / Header — underline" "="
}

main "$@"