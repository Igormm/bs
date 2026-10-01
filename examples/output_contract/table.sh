#!/usr/bin/env bs
# shellcheck shell=bash
# examples/output_contract/table.sh — output contract demo: tables
# examples/output_contract/table.sh — демо контракта вывода: таблицы
#
# Два вида таблиц: log::table (простые строки "кол|кол") и
# presentation::table (выровненная рамка с колонками "кол:кол").
# Two table kinds: log::table (plain "col|col" rows) and
# presentation::table (aligned framed table, "col:col" cells).
#
# Run / Запуск:
#   bs run examples/output_contract/table.sh

load "core/logger"
load "lib/ui/presentation"

main() {
    printf 'log::table — простые строки / plain rows:\n\n'
    log::table \
        "Компонент / Item:Статус / Status" \
        "пользователь / user:создан / created" \
        "сервис / service:запущен / started"
    printf '\npresentation::table — выровненная / aligned:\n\n'
    presentation::table \
        "Компонент / Item:Статус / Status" \
        "пользователь / user:создан / created" \
        "сервис / service:запущен / started"
}

main "$@"