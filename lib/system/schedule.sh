#!/usr/bin/env bs
# shellcheck shell=bash
# lib/system/schedule.sh — Task scheduling helpers / Помощники планирования задач
#
# Linguistic wrappers over `at` and `crontab`.
# / «Лингвистические» обёртки над `at` и `crontab`.
#
# Usage / Использование:
#   load "lib/system/schedule"
#   system::schedule::at "now + 1 hour" /usr/local/bin/backup.sh
#   system::schedule::cron_add "0 3 * * *" /usr/local/bin/backup.sh
#
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
bs::guard "SYSTEM_SCHEDULE" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# Метаданные модуля / Module metadata
# shellcheck disable=SC2034
declare -g SYSTEM_SCHEDULE_VERSION="1.0.0"

# @description Schedule a one-shot command with `at`.
# @description Запланировать одноразовую команду через `at`.
# @param $1 Time spec ("now + 1 hour", "10:15", "midnight") / Время запуска
# @param $@ Command and arguments / Команда и аргументы
# @return E_INVALID on bad arguments, E_ERROR if `at` is missing
# @example
#   system::schedule::at "now + 30 minutes" systemctl restart nginx
system::schedule::at() {
    local -r when="${1:-}"

    if is::empty "${when}" || [[ $# -lt 2 ]]; then
        log::warn "Time spec and command required"
        return "${E_INVALID}"
    fi
    shift

    if [[ "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]; then
        log::warn "[DRY-RUN] at ${when}: $*"
        return "${E_SUCCESS}"
    fi

    if ! utils::has at; then
        log::error "at not found (install package: at)"
        return "${E_ERROR}"
    fi

    printf '%s\n' "$*" | at "${when}"
}

# @description Add a cron job (idempotent: an identical line is never duplicated).
# @description Добавить cron-задачу (идемпотентно: одинаковая строка не дублируется).
# @param $1 Cron spec (e.g. "0 3 * * *") / Cron-спецификация
# @param $@ Command and arguments / Команда и аргументы
# @return E_INVALID on bad arguments, E_ERROR if crontab is missing
# @example
#   system::schedule::cron_add "0 3 * * *" /usr/local/bin/backup.sh --full
system::schedule::cron_add() {
    local -r spec="${1:-}"

    if is::empty "${spec}" || [[ $# -lt 2 ]]; then
        log::warn "Cron spec and command required"
        return "${E_INVALID}"
    fi
    shift

    local -r entry="${spec} $*"

    if [[ "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]; then
        log::warn "[DRY-RUN] crontab += ${entry}"
        return "${E_SUCCESS}"
    fi

    if ! utils::has crontab; then
        log::error "crontab not found (install package: cronie / cron)"
        return "${E_ERROR}"
    fi

    if crontab -l 2>/dev/null | grep -Fxq "${entry}"; then
        log::info "Cron job already present: ${entry}"
        return "${E_SUCCESS}"
    fi

    # Append to the existing table / Дописать в существующую таблицу
    (crontab -l 2>/dev/null; printf '%s\n' "${entry}") | crontab -
    log::info "Cron job added: ${entry}"
}

# @description List the current user's cron jobs / Показать cron-задачи пользователя.
# @example
#   system::schedule::cron_list
system::schedule::cron_list() {
    if ! utils::has crontab; then
        log::error "crontab not found (install package: cronie / cron)"
        return "${E_ERROR}"
    fi

    crontab -l 2>/dev/null || log::info "No cron jobs for ${USER:-current user}"
}

# Метка загрузки / Load marker
# shellcheck disable=SC2034
declare -g SYSTEM_SCHEDULE_LOADED="1"
