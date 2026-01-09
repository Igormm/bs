#!/usr/bin/env bash
# shellcheck shell=bash
#
# BS Framework - Enhanced Bash Scripting
# Фреймворк BS - Расширенное bash-скриптование
#
# НАЗНАЧЕНИЕ: Главный entrypoint фреймворка BS
# PURPOSE: Main entrypoint for BS framework
#
# ЗАВИСИМОСТИ: bash 4.0+, стандартные утилиты Linux
# DEPENDENCIES: bash 4.0+, standard Linux utilities
#
# ИСПОЛЬЗУЕТСЯ: Для инициализации фреймворка и загрузки модулей
# USAGE: For framework initialization and module loading
#
#

# boot.sh — bootstrap-файл проекта для подключения BS в bash-скриптах / project bootstrap

# file for connecting BS in bash scripts

#

# Использование / Usage:

#   source "./boot.sh"

#   BS::init

#

# Примечание / Note:

# - По умолчанию фреймворк ожидается в каталоге: ./bs / By default framework is expected

# in directory: ./bs

# - Можно переопределить путь так: / Can override path like this:

#     BS_PROJECT_FRAMEWORK_DIR="/path/to/BS" source "./boot.sh"

#



# Абсолютный путь к каталогу проекта (где лежит boot.sh) / Absolute path to project

# directory (where boot.sh is located)

BS_PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"



# Абсолютный путь к каталогу фреймворка (по умолчанию: <project>/BS) / Absolute path to

# framework directory (default: <project>/BS)

#
# ПЕРЕМЕННАЯ / VARIABLE:
# : "${BS_PROJECT_FRAMEWORK_DIR: - [Описание переменной]
# : "${BS_PROJECT_FRAMEWORK_DIR: - [Variable description]
#
: "${BS_PROJECT_FRAMEWORK_DIR:="${BS_PROJECT_DIR}/bs"}"



# Подключаем entrypoint фреймворка (в каталоге фреймворка это файл "BS") / Connect

# framework entrypoint (in framework directory this is file "BS")

#
# ПОДКЛЮЧЕНИЕ МОДУЛЯ / MODULE IMPORT:
# Импортируется: "${BS_PROJECT_FRAMEWORK_DIR}/bs"
# Imports: "${BS_PROJECT_FRAMEWORK_DIR}/bs"
#
source "${BS_PROJECT_FRAMEWORK_DIR}/bs"



# Опционально: можно сразу инициализировать (если хочешь без явного BS::init) / Optional:

# can initialize immediately (if you want without explicit BS::init)

# BS::init

# load "path/to/module" # для загрузки дополнительных модулей / for loading additional

# modules



unset BS_PROJECT_DIR