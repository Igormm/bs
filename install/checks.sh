#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: test и реестр оболочек bootstrap/shell.sh / valid POSIX sh: test and the shell registry bootstrap/shell.sh
# @tier core — builtins only; works everywhere
#
# Environment checking functions for the installer
# Проверки окружения для установщика
#
# ИМЕНА / NAMES
#   Real functions: bs_is_already_installed, bs_get_current_shell_name, bs_check_shell_environment;
#   in bash and zsh also is_already_installed, get_current_shell_name, check_shell_environment
#   (the old names).
#   Настоящие функции — bs_*; в bash и zsh — ещё и прежние is_already_installed,
#   get_current_shell_name, check_shell_environment.

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# Check if already installed
bs_is_already_installed() {
  [ -d "${TARGET_LIB}" ] && [ -f "${TARGET_BIN}" ]
}

# Имя интерпретатора, который исполняет установщик (по реестру оболочек).
# Это НЕ оболочка пользователя: пользовательская — bs_shell_user.
# The interpreter that runs the installer (from the shell registry). This is
# NOT the user's shell: that one is bs_shell_user.
bs_get_current_shell_name() {
  bs_shell_family
}

# check_shell_environment
#
# Установщик исполняется в оболочке, которую выбрал POSIX-пролог install.sh
# (bs_shell_host_ok), а при необходимости точка входа перезапускается в
# подходящем bash (bootstrap/trampoline.sh). Здесь повторной проверки нет:
# запоминается оболочка, исполняющая установщик.
# The installer runs in the shell the POSIX prologue of install.sh chose
# (bs_shell_host_ok) and, when needed, the entry point re-runs itself in a
# capable bash (bootstrap/trampoline.sh). There is no second check here: the
# shell that runs the installer is recorded.
bs_check_shell_environment() {
  __bs_ck_name=$(bs_get_current_shell_name)

  # Сохраняем для других функций
  bs_shell_readonly CURRENT_SHELL="${__bs_ck_name}"
}

bs_shell_alias bs_is_already_installed is_already_installed
bs_shell_alias bs_get_current_shell_name get_current_shell_name
bs_shell_alias bs_check_shell_environment check_shell_environment
