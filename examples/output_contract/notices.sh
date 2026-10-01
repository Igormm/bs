#!/usr/bin/env bs
# shellcheck shell=bash
# examples/output_contract/notices.sh — output contract demo: notices
# examples/output_contract/notices.sh — демо контракта вывода: уведомления
#
# presentation::success/error/warning/info — цветные однострочные
# уведомления для итогов и подсказок.
# presentation::success/error/warning/info — colored one-line notices
# for results and hints.
#
# Run / Запуск:
#   bs run examples/output_contract/notices.sh

load "lib/ui/presentation"

main() {
    presentation::success "Готово! / Done!"
    presentation::error "Ошибка / Error"
    presentation::warning "Предупреждение / Warning"
    presentation::info "Информация / Info"
}

main "$@"