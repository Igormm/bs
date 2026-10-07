#!/usr/bin/env bs
# shellcheck shell=bash
# lib/network/avahi.sh — mDNS/Avahi helpers for BS
# lib/network/avahi.sh — вспомогательные функции mDNS/Avahi для BS
#
# Provides .local hostname discovery and availability checks for Avahi/mDNS.
# Предоставляет определение .local-имени хоста и проверки доступности Avahi/mDNS.
#
# Usage / Использование:
#   load "lib/network/avahi"
#   network::avahi::hostname_local   # myhost.local
#   network::avahi::available        # 0/1
#
# @depends core/const, core/logger, core/utils, core/lang

# Source Guard / Защита от повторной загрузки
bs::guard "LIB_NETWORK_AVAHI" || return 0

# Dependencies / Зависимости
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "../../core/lang.sh" "../data/format.sh"

# @global LIB_NETWORK_AVAHI_VERSION — Module version (category: module-flag)
# @global LIB_NETWORK_AVAHI_VERSION — Версия модуля (категория: module-flag)
declare -g LIB_NETWORK_AVAHI_VERSION="1.0.0"
# @global LIB_NETWORK_AVAHI_LOADED — Module loaded flag (category: module-flag)
# @global LIB_NETWORK_AVAHI_LOADED — Флаг загрузки модуля (категория: module-flag)
declare -g LIB_NETWORK_AVAHI_LOADED="1"

# @description Check if Avahi tools are available.
# @description Проверить, доступны ли утилиты Avahi.
# @return 0 if avahi-daemon or avahi-publish-service found, 1 otherwise
# @return 0 если найден avahi-daemon или avahi-publish-service, 1 иначе
network::avahi::available() {
  utils::has avahi-daemon || utils::has avahi-publish-service
}

# @description Check if the Avahi daemon is running.
# @description Проверить, запущен ли демон Avahi.
# @return 0 if a pid file or active process is found, 1 otherwise
# @return 0 если найден pid-файл или активный процесс, 1 иначе
network::avahi::running() {
  if is::file /run/avahi-daemon/pid || is::file /var/run/avahi-daemon/pid; then
    return "${E_SUCCESS}"
  fi
  if utils::has pgrep && utils::quiet pgrep -x avahi-daemon; then
    return "${E_SUCCESS}"
  fi
  return "${E_ERROR}"
}

# @description Return the mDNS .local hostname for this machine.
# @description Вернуть mDNS .local-имя хоста для этой машины.
#   Uses the short hostname when possible; falls back to plain hostname with
#   the domain part stripped, then to "localhost".
#   По возможности использует короткое имя хоста; в случае неудачи — обычное
#   имя без доменной части, затем "localhost".
# @stdout .local hostname / .local-имя хоста
# @example
#   network::avahi::hostname_local  # myhost.local
network::avahi::hostname_local() {
  local short_host=""

  if is::command hostname; then
    short_host="$(utils::quiet_err hostname -s || true)"
    if is::empty "${short_host}"; then
      short_host="$(utils::quiet_err hostname || true)"
      short_host="${short_host%%.*}"
    fi
  fi

  if is::empty "${short_host}"; then
    short_host="localhost"
  fi

  # Canonical record + selected format; string default is the bare value.
  # Каноническая запись + выбранный формат; string по умолчанию — значение.
  format::record hostname_local "${short_host}.local" \
    | format::emit "${BS_OUTPUT_FORMAT:-string}"
}
