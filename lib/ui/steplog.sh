#!/usr/bin/env bs
# shellcheck shell=bash
# lib/ui/steplog.sh — step log component: always-on file log + optional --verbose
# lib/ui/steplog.sh — компонент журнала шагов: файл журнала всегда + опциональный --verbose
#
# Гарантия: журнал пишется при ЛЮБОМ завершении — успех, ошибка, отмена,
# падение по set -e. «Невозможно завершение без лога».
# Guarantee: the log is written on ANY exit — success, failure, cancel,
# a set -e crash. "No completion without a log."
#
# Использование / Usage:
#   load "lib/ui/steplog"
#   steplog::init "/tmp/my-app.log" "${verbose:-0}"
#   steplog::on_exit my::restore_terminal
#   steplog::step "useradd ..."
#   steplog::ok "пользователь создан / user created"

# @depends core/lang

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_UI_STEPLOG" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/lang.sh"

# @global STEPLOG_FILE — Steplog: log file path (category: constant)
# @global STEPLOG_FILE — Steplog: путь к файлу журнала (категория: constant)
declare -g STEPLOG_FILE=""
# @global STEPLOG_VERBOSE — Steplog: verbose flag (category: framework-flag)
# @global STEPLOG_VERBOSE — Steplog: флаг подробного вывода (категория: framework-flag)
declare -g STEPLOG_VERBOSE=0
# @global STEPLOG_BUF — Steplog: buffered log lines (category: constant)
# @global STEPLOG_BUF — Steplog: буфер строк журнала (категория: constant)
declare -ga STEPLOG_BUF=()
# @global STEPLOG_HOOKS — Steplog: EXIT hook functions (category: hook)
# @global STEPLOG_HOOKS — Steplog: функции-хуки на EXIT (категория: hook)
declare -ga STEPLOG_HOOKS=()

# @description Init: set the log file, verbose flag and the EXIT trap.
# @description Инициализация: файл журнала, флаг verbose и EXIT-trap.
# @param $1 Log file path / Путь к файлу журнала
# @param $2 [optional] Verbose 0/1 (default 0)
steplog::init() {
    STEPLOG_FILE="${1:?log file required}"
    STEPLOG_VERBOSE="${2:-0}"
    STEPLOG_BUF=()
    STEPLOG_HOOKS=()
    # Пробуем писать в подшелле: ( : > file ) 2>/dev/null гасит и ошибку
    # редиректа шелла, и проверку. При неудаче — запасной журнал по UID:
    # чужой root-файл в /tmp не должен ронять визард или печатать сырую
    # ошибку bash («Отказано в доступе»).
    # Probe writability in a subshell: ( : > file ) 2>/dev/null silences
    # both the shell's redirect error and the check. On failure — fall back
    # to a per-UID log: a foreign root-owned file in /tmp must not crash the
    # wizard or print a raw bash error.
    if ! ( : > "${STEPLOG_FILE}" ) 2>/dev/null; then
        local fallback="${TMPDIR:-/tmp}/steplog.${UID:-$(id -u)}.log"
        printf 'steplog: %s не доступен для записи / not writable — журнал / log: %s\n' "${STEPLOG_FILE}" "${fallback}" >&2
        STEPLOG_FILE="${fallback}"
        ( : > "${STEPLOG_FILE}" ) 2>/dev/null || true
    fi
    # EXIT-trap принадлежит steplog: хуки (восстановление терминала и т.п.)
    # выполняются до сброса журнала. The EXIT trap is owned by steplog:
    # hooks (terminal restore etc.) run before the log flush.
    trap 'steplog::__on_exit' EXIT
}

# @description Register an EXIT hook (runs before the log flush).
# @description Зарегистрировать EXIT-хук (выполняется до сброса журнала).
# @param $1 Function name / Имя функции
steplog::on_exit() {
    STEPLOG_HOOKS+=("${1:?handler required}")
}

# @description Record a line: buffered always, printed to stderr when verbose.
# @description Записать строку: в буфер всегда, в stderr при verbose.
# @param $1 Level: step|ok|warn|error|info
# @param $2 Text / Текст
steplog::add() {
    local -r level="${1:-info}" text="${2:-}"
    STEPLOG_BUF+=("$(printf '[%s] %-5s %s' "$(date '+%Y-%m-%d %H:%M:%S')" "${level}" "${text}")")
    if (( STEPLOG_VERBOSE == 1 )); then
        printf 'LOG[%s] %s\n' "${level}" "${text}" >&2
    fi
}

# @description Record a step (▶) / Записать шаг (▶)
steplog::step()  { steplog::add step  "${1}"; }
# @description Record success (✓) / Записать успех (✓)
steplog::ok()    { steplog::add ok    "${1}"; }
# @description Record a warning / Записать предупреждение
steplog::warn()  { steplog::add warn  "${1}"; }
# @description Record an error / Записать ошибку
steplog::error() { steplog::add error "${1}"; }
# @description Record info / Записать информацию
steplog::info()  { steplog::add info  "${1}"; }

# @description Flush the buffer to the file (idempotent).
# @description Сбросить буфер в файл (идемпотентно).
steplog::finish() {
    if (( ${#STEPLOG_BUF[@]} > 0 )); then
        printf '%s\n' "${STEPLOG_BUF[@]}" > "${STEPLOG_FILE}" 2>/dev/null || true
    fi
}

# @private EXIT trap: run hooks, then flush the log.
# @private EXIT-trap: выполнить хуки, затем сбросить журнал.
steplog::__on_exit() {
    local h
    for h in "${STEPLOG_HOOKS[@]}"; do
        is::function "${h}" && "${h}"
    done
    steplog::finish
}