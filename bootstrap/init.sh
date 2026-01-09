#!/usr/bin/env bs
# shellcheck shell=bash
#
# bootstrap/init.sh — единая инициализация фреймворка 
# BS unified BS framework initialization
#
# Этот файл обеспечивает идемпотентную инициализацию всех компонентов фреймворка.
# This file provides idempotent initialization of all framework components.
#

set -euo pipefail

# Проверка идемпотентности 
# Idempotency check
if [[ -n "${BOSA_INITIALIZED:-}" ]]; then
    log::debug "BS already initialized, skipping" 2>/dev/null || true
    return 0
fi

# Определение BOSA_ROOT если не установлен 
# Define BOSA_ROOT if not set
if [[ -z "${BOSA_ROOT:-}" ]]; then
    BOSA_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
    export BOSA_ROOT
fi

# Загрузка loader 
# Loading loader
if [[ -f "${BOSA_ROOT}/bootstrap/loader.sh" ]]; then
    source "${BOSA_ROOT}/bootstrap/loader.sh"
elif [[ -f "${BOSA_ROOT}/loader.sh" ]]; then
    source "${BOSA_ROOT}/loader.sh"
else
    echo "BS: error: loader.sh not found in ${BOSA_ROOT}/bootstrap/ or ${BOSA_ROOT}/" >&2
    exit 1
fi

# Загрузка ядра
# Loading core
load "core/const"
load "core/logger"
load "core/errorhandler"
load "core/version"

# Установка флага инициализации 
# Setting initialization flag
export BOSA_INITIALIZED="1"

log::debug "BS framework initialized successfully" 2>/dev/null || true
