#!/usr/bin/env bs
# shellcheck shell=bash
# lib/system/systemd.sh — systemd unit helpers: paths, existence, unit file
# content, write + daemon-reload, enable/start/stop/restart/status
# lib/system/systemd.sh — помощники systemd: пути, наличие юнита, содержимое
# файла, запись + daemon-reload, enable/start/stop/restart/status
#
# The unit dir is overridable for tests and non-standard layouts:
# BS_SYSTEMD_UNIT_DIR (default /etc/systemd/system).
# Каталог юнитов переопределяется для тестов и нестандартных раскладок:
# BS_SYSTEMD_UNIT_DIR (по умолчанию /etc/systemd/system).
#
# Usage / Использование:
#   load "lib/system/systemd"
#   systemd::unit_exists myservice
#   systemd::unit_write myservice "…unit content…"
#   systemd::daemon_reload && systemd::unit_enable_now myservice
#
# @depends core/logger, core/utils

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_SYSTEM_SYSTEMD" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/logger.sh" "../../core/utils.sh"

# @global BS_SYSTEMD_UNIT_DIR — Hook: systemd unit dir override for tests (category: hook)
# @global BS_SYSTEMD_UNIT_DIR — Хук: каталог юнитов systemd для тестов (категория: hook)
declare -g BS_SYSTEMD_UNIT_DIR="/etc/systemd/system"

# @description systemd available / systemd доступен
systemd::available() { is::command systemctl; }

# @description Unit file path (name without .service) / Путь к файлу юнита
# @param $1 Unit name / Имя юнита
# @stdout absolute path / абсолютный путь
systemd::unit_path() {
    local -r name="${1:?unit name required}"
    printf '%s/%s.service\n' "${BS_SYSTEMD_UNIT_DIR}" "${name}"
}

# @description Unit file exists / Файл юнита существует
# @param $1 Unit name / Имя юнита
systemd::unit_exists() {
    local -r name="${1:?unit name required}"
    is::file "$(systemd::unit_path "${name}")"
}

# @description Unit is active (systemctl is-active) / Юнит активен
# @param $1 Unit name / Имя юнита
systemd::unit_running() {
    local -r name="${1:?unit name required}"
    systemctl is-active --quiet "${name}" 2>/dev/null
}

# @description First ExecStart line of an existing unit file / Первая строка
# ExecStart существующего файла юнита.
# @param $1 Unit name / Имя юнита
# @stdout ExecStart value (empty if none) / значение ExecStart (пусто, если нет)
systemd::unit_execstart() {
    local -r name="${1:?unit name required}"
    sed -n 's/^ExecStart=//p' "$(systemd::unit_path "${name}")" 2>/dev/null | head -1
}

# @description Write a unit file (content with \n) / Записать файл юнита
# @param $1 Unit name / Имя юнита
# @param $2 Content / Содержимое
# @return 0 written, 1 not writable / 0 записан, 1 нет доступа
systemd::unit_write() {
    local -r name="${1:?unit name required}" content="$2"
    local -r path="$(systemd::unit_path "${name}")"
    if ! printf '%s' "${content}" > "${path}" 2>/dev/null; then
        log::error "systemd::unit_write: нет доступа / not writable: ${path}"
        return 1
    fi
    return 0
}

# @description Reload systemd (daemon-reload) / Перезагрузить systemd
systemd::daemon_reload() { systemctl daemon-reload; }

# @description enable --now / Включить и запустить
# @param $1 Unit name / Имя юнита
systemd::unit_enable_now() {
    systemctl enable --now "${1:?unit name required}"
}

# @description start / Запустить
systemd::unit_start() { systemctl start "${1:?unit name required}"; }
# @description stop / Остановить
systemd::unit_stop() { systemctl stop "${1:?unit name required}"; }
# @description restart / Перезапустить
systemd::unit_restart() { systemctl restart "${1:?unit name required}"; }
# @description status / Статус
systemd::unit_status() { systemctl status "${1:?unit name required}"; }
# @description enable / Включить автозапуск
systemd::unit_enable() { systemctl enable "${1:?unit name required}"; }
# @description disable / Отключить автозапуск
systemd::unit_disable() { systemctl disable "${1:?unit name required}"; }