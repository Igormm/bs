#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: только redirect'ы и command -v / valid POSIX sh: redirects and command -v only
# @tier core — builtins only; works everywhere
# @tier core — только builtin'ы; работает везде
#
# core/quiet.sh — идиомы «тишины»: проверка команды и подавление вывода
# core/quiet.sh — the "quiet" idioms: command check and output suppression
#
# ИМЕНА / NAMES
#   Real functions: bs_utils_has, bs_utils_quiet, bs_utils_quiet_err, bs_utils_ignore,
#   bs_utils_attempt; in bash and zsh also utils::* (the old names, they live in
#   core/utils.sh as aliases of these).
#   Настоящие функции: bs_utils_has, bs_utils_quiet, bs_utils_quiet_err, bs_utils_ignore,
#   bs_utils_attempt; в bash и zsh — ещё и utils::* (прежние имена).

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

bs_guard QUIET || return 0

# Проверяет наличие команды в PATH.
# Заменяет идиому: command -v foo >/dev/null 2>&1
# @description Check if command exists in PATH.
# @description Проверить наличие команды в PATH.
# @param $1 {string} Имя команды
# @returns 0  команда доступна
# @returns 1  команда не найдена
# @example
#   if bs_utils_has dnf; then ...; fi        # bash/zsh: utils::has dnf
bs_utils_has() {
  # статус нормализуем: dash и ash при «не найдено» отдают 127, а не 1 / normalise the status: dash and ash return 127, not 1, for "not found"
  command -v "${1-}" >/dev/null 2>&1 || return 1
}

# Выполняет команду, полностью подавляя вывод. Код возврата сохраняется.
# Заменяет идиому: cmd >/dev/null 2>&1
# @description Run command suppressing all output (stdout and stderr).
# @description Выполнить команду, подавляя весь вывод (stdout и stderr).
# @param $@ {string} Команда и её аргументы
# @returns код возврата команды
bs_utils_quiet() {
  "$@" >/dev/null 2>&1
}

# Выполняет команду, подавляя только stderr. Код возврата сохраняется.
# Заменяет идиому: cmd 2>/dev/null
# @description Run command suppressing stderr only.
# @description Выполнить команду, подавляя только stderr.
# @param $@ {string} Команда и её аргументы
# @returns код возврата команды
bs_utils_quiet_err() {
  "$@" 2>/dev/null
}

# Выполняет команду, подавляя вывод и игнорируя результат.
# Явная замена идиомы: cmd >/dev/null 2>&1 || true
# Использовать только там, где неудача команды действительно не важна.
# @description Run command ignoring result (always succeeds).
# @description Выполнить команду, игнорируя результат (всегда успех).
# @param $@ {string} Команда и её аргументы
# @returns всегда 0
bs_utils_ignore() {
  "$@" >/dev/null 2>&1 || :
}

# Выполняет команду, игнорируя результат; stderr подавляется, stdout сохраняется.
# Явная замена идиомы: cmd 2>/dev/null || true (и utils::quiet_err cmd || true)
# Использовать для best-effort операций, где неудача допустима.
# @description Best-effort command, ignore failure (always succeeds).
# @description Выполнить команду best-effort, игнорируя сбой (всегда успех).
# @param $@ {string} Команда и её аргументы
# @returns всегда 0
bs_utils_attempt() {
  "$@" 2>/dev/null || :
}

bs_shell_alias bs_utils_has utils::has
bs_shell_alias bs_utils_quiet utils::quiet
bs_shell_alias bs_utils_quiet_err utils::quiet_err
bs_shell_alias bs_utils_ignore utils::ignore
bs_shell_alias bs_utils_attempt utils::attempt
