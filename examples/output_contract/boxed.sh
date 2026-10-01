#!/usr/bin/env bs
# shellcheck shell=bash
# examples/output_contract/boxed.sh — output contract demo: boxed text
# examples/output_contract/boxed.sh — демо контракта вывода: рамка-текст
#
# presentation::boxed — рамка вокруг многострочного текста; "round" —
# скруглённые углы ╭╮, по умолчанию ┌┐. Ширина считается в экранных
# клетках (не байтах — кириллица не ломает рамку).
# presentation::boxed — box around multi-line text; "round" gives
# rounded corners ╭╮, default ┌┐. Width is measured in display cells
# (not bytes — Cyrillic does not break the frame).
#
# Run / Запуск:
#   bs run examples/output_contract/boxed.sh

load "lib/ui/presentation"

main() {
    printf 'Квадратные углы / Square corners (по умолчанию / default):\n\n'
    presentation::boxed "Строка 1 / Line 1
Строка 2 / Line 2"
    printf '\nСкруглённые углы / Rounded corners ("round"):\n\n'
    presentation::boxed "Строка 1 / Line 1
Строка 2 / Line 2" round
}

main "$@"