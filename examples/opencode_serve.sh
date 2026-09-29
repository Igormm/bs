#!/usr/bin/env bs
# shellcheck shell=bash
# examples/opencode_serve.sh — helper for the opencode server task
# examples/opencode_serve.sh — помощник для задачи «opencode-сервер»
#
# Проверяет, что opencode установлен (is::command), предупреждает про sudo
# (нужен только для файрвола и systemd — не для самого сервера), и запускает
# сервер с basic auth.
# Checks that opencode is installed (is::command), warns about sudo (needed
# only for the firewall and systemd — not for the server itself), then starts
# the server with basic auth.
#
# Запуск / Run:
#   OPENCODE_SERVER_PASSWORD='пароль' bs run examples/opencode_serve.sh
#   OPENCODE_SERVER_PASSWORD='пароль' ./examples/opencode_serve.sh

load "core/logger"
load "core/lang"

readonly PORT="${PORT:-4096}"

# 1. Проверка существования пакета / Check the package exists
if ! is::command opencode; then
    log::error "opencode is not installed / opencode не установлен"
    log::error "install it first / сначала установите: https://opencode.ai"
    exit 1
fi
log::info "opencode found: $(command -v opencode)"

# 2. Пароль обязателен / Password is mandatory
if is::empty "${OPENCODE_SERVER_PASSWORD:-}"; then
    log::error "OPENCODE_SERVER_PASSWORD is not set / пароль не задан"
    log::error "run: OPENCODE_SERVER_PASSWORD='ваш-пароль' bs run examples/opencode_serve.sh"
    exit 1
fi

# 3. Предупреждение про sudo / Warn about sudo
#    Сам сервер root НЕ требует (порт 4096 > 1024), но шаги файрвола и
#    systemd — требуют. Проверяем и предупреждаем заранее.
#    The server itself does NOT need root (port 4096 > 1024), but the
#    firewall and systemd steps do. Check and warn up front.
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log::warn "you are not root — this is fine for the server itself"
    log::warn "вы не root — для самого сервера это нормально"
    log::warn "sudo is needed ONLY for: / sudo нужен ТОЛЬКО для:"
    log::warn "  1) firewall: sudo firewall-cmd --add-port=${PORT}/tcp --permanent && sudo firewall-cmd --reload"
    log::warn "  2) optional autostart: sudo systemctl enable --now opencode"
else
    log::warn "running as root — the server will accept connections from 0.0.0.0"
    log::warn "запуск от root — сервер будет принимать подключения с 0.0.0.0"
fi

# 4. Запуск сервера / Start the server
log::info "starting opencode serve on 0.0.0.0:${PORT} ..."
log::info "opencode serve запускается на 0.0.0.0:${PORT} ..."
log::info "find your IP: ip -4 a   (e.g. 192.168.1.50)"
log::info "from another machine: opencode attach http://<ip>:${PORT} -u opencode -p 'пароль'"
exec env OPENCODE_SERVER_PASSWORD="${OPENCODE_SERVER_PASSWORD}" \
    opencode serve --port "${PORT}" --hostname 0.0.0.0