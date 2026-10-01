#!/usr/bin/env bs
# shellcheck shell=bash
# examples/output_contract/log_levels.sh — output contract demo: log levels
# examples/output_contract/log_levels.sh — демо контракта вывода: уровни лога
#
# Все 7 уровней core/logger: [timestamp] LEVEL message (BS_LOG_FORMAT:
# text | structured | json).
# All 7 core/logger levels: [timestamp] LEVEL message (BS_LOG_FORMAT:
# text | structured | json).
#
# Run / Запуск:
#   bs run examples/output_contract/log_levels.sh

export BS_LOG_LEVEL=trace

load "core/logger"

main() {
    printf 'Формат / Format: [timestamp] LEVEL message (BS_LOG_FORMAT=text)\n\n'
    log::trace "trace — диагностика / diagnostics"
    log::debug "debug — отладка / debugging"
    log::info "info — обычное сообщение / regular message"
    log::success "success — успех / done"
    log::warn "warn — предупреждение / warning"
    log::error "error — ошибка / error"
    log::fatal "fatal — фатальная ошибка / fatal"
    printf '\nФормат / Format: BS_LOG_FORMAT=structured\n\n'
    BS_LOG_FORMAT=structured log::info "структурированный / structured"
    BS_LOG_FORMAT=structured log::warn "структурированный / structured"
    printf '\nФормат / Format: BS_LOG_FORMAT=json\n\n'
    BS_LOG_FORMAT=json log::info "json"
}

main "$@"