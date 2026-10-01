#!/usr/bin/env bs
# shellcheck shell=bash
# examples/output_contract/bullets.sh — output contract demo: bullet list
# examples/output_contract/bullets.sh — демо контракта вывода: список с маркерами
#
# log::list — маркерованный список (• в цветном терминале, * без цвета).
# log::list — bulleted list (• in a color terminal, * without color).
#
# Run / Запуск:
#   bs run examples/output_contract/bullets.sh

load "core/logger"

main() {
    log::list \
        "первый пункт / first item" \
        "второй пункт / second item" \
        "третий пункт / third item"
}

main "$@"