#!/usr/bin/env bs
# shellcheck shell=bash
# lib/system/apply.sh — apply-step runner: run commands with a clear failure
# report (step, command, log hint); tool pre-checks
# lib/system/apply.sh — выполнение шагов применения: запуск команд с
# понятным отчётом об ошибке (шаг, команда, подсказка про журнал);
# предпроверка утилит
#
# The runner only REPORTS failures (log::error) and returns the exit code —
# the caller decides how to present them (e.g. wizard::fail). Used by
# examples/ai_user_wizard.sh.
# Раннер только СООБЩАЕТ об ошибке (log::error) и возвращает код выхода —
# представление выбирает вызывающий (например wizard::fail). Используется
# examples/ai_user_wizard.sh.
#
# Usage / Использование:
#   load "lib/system/apply"
#   apply::run "useradd demo" useradd -m demo
#   apply::check_tools id useradd passwd || exit 1
#
# @depends core/logger, core/utils

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_SYSTEM_APPLY" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/logger.sh" "../../core/utils.sh"

# @description Run a command; on failure log the step, the command and a
# log hint, then return the command's exit code.
# @description Выполнить команду; при неудаче записать в лог шаг, команду
# и подсказку про журнал, затем вернуть код выхода команды.
# @param $1 Step description / Описание шага
# @param $@ Command / Команда
# @return command exit code / код выхода команды
apply::run() {
    local -r desc="${1:?step description required}"
    shift
    "$@"
    local -r rc=$?
    if (( rc != 0 )); then
        log::error "Шаг не выполнен / Step failed: ${desc}"
        log::error "Команда / Command: $*"
        log::error "Журнал / Log: journalctl -xe"
    fi
    return "${rc}"
}

# @description Check required tools; report the missing ones.
# @description Проверить обязательные утилиты; сообщить об отсутствующих.
# @param $@ Tool names / Имена утилит
# @return 0 all present, 1 some missing / 0 всё на месте, 1 чего-то нет
apply::check_tools() {
    local -a missing=()
    local tool
    for tool in "$@"; do
        is::command "${tool}" || missing+=("${tool}")
    done
    if (( ${#missing[@]} > 0 )); then
        log::error "Отсутствуют зависимости / Missing dependencies:"
        local t
        for t in "${missing[@]}"; do
            log::error "  • ${t}"
        done
        log::error "Установите пакеты и повторите / Install the packages and retry."
        return 1
    fi
    return 0
}