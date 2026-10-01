#!/usr/bin/env bs
# shellcheck shell=bash
# examples/output_contract/progress.sh — output contract demo: progress
# examples/output_contract/progress.sh — демо контракта вывода: прогресс
#
# log::progress (слева) и presentation::progress (справа) — инлайн-бары
# с \r; обе перерисовывают текущую строку.
# log::progress (left) and presentation::progress (right) — inline bars
# with \r; both redraw the current line.
#
# Run / Запуск:
#   bs run examples/output_contract/progress.sh

load "core/logger"
load "lib/ui/presentation"

main() {
    local -i i
    printf 'log::progress:\n'
    for ((i = 1; i <= 10; i++)); do
        log::progress $((i * 10)) 100
        sleep 0.1
    done
    printf '\n\npresentation::progress:\n'
    for ((i = 1; i <= 10; i++)); do
        presentation::progress $((i * 10)) 100
        sleep 0.1
    done
    printf '\n'
}

main "$@"