#!/usr/bin/env bs
# shellcheck shell=bash
# examples/output_contract/tui_elements.sh — output contract demo: TUI elements
# examples/output_contract/tui_elements.sh — демо контракта вывода: TUI-элементы
#
# 12 полноэкранных центрированных элементов в lib/ui/elements/* — по
# модулю на элемент, каждый рисует в буфер TUI (tui::buf::clear +
# tui::render) и самодемонстрируется при прямом запуске:
#   bs run lib/ui/elements/box.sh
# Здесь показан образец — рамка с заголовком.
# 12 full-screen centered elements in lib/ui/elements/* — one module per
# element, each draws into the TUI buffer and self-demos on direct run:
#   bs run lib/ui/elements/box.sh
# A sample is shown here — a framed box with a title.
#
# Run / Запуск:
#   bs run examples/output_contract/tui_elements.sh

load "lib/tui/tui"
load "lib/ui/elements/box"

main() {
    tui::init
    tui::buf::clear
    ui::elements::box::draw \
        "TUI-элементы / TUI elements" \
        "12 элементов в lib/ui/elements/ — по модулю на элемент
12 elements in lib/ui/elements/ — one module per element

  box · table · list · input · menu · confirm
  progress · spinner · statusbar · titlebar
  separator · message

Запуск каждого / run each:
  bs run lib/ui/elements/<имя>.sh / <name>.sh"
    tui::render
    tui::key_read >/dev/null
    tui::quit
}

main "$@"