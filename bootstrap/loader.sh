#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, test, параметры-расширения, `.`; без массивов и [[ ]] / valid POSIX sh: case, test, parameter expansion, `.`; no arrays, no [[ ]]
# @tier core — builtins only; works everywhere
# @tier core — только builtin'ы; работает везде
#
# bootstrap/loader.sh — модуль загрузки с предотвращением повторного подключения
# bootstrap/loader.sh — loading module with duplicate loading prevention
#
# ИМЕНА / NAMES
#   Real functions: bs_load, bs_load_is_loaded, bs_load_stack_size (and the private
#   bs_load_check_cycle, bs_load_deps, bs_load_dep_list, bs_load_strict_check); `load` is
#   a plain POSIX function name and works in every shell; bs::load is the bash/zsh alias.
#   Настоящие функции — bs_load, bs_load_is_loaded, bs_load_stack_size; `load` — обычное
#   имя функции POSIX и работает в любой оболочке; bs::load — псевдоним для bash и zsh.
#
# ДАННЫЕ / DATA
#   The registry of loaded modules and the load stack are plain strings, one module per line
#   (the loader runs BEFORE core/data.sh, so it cannot use the data layer).
#   They replace the bash arrays BS_LOADED_MODULES and BS_LOAD_STACK.
#   Реестр загруженных модулей и стек загрузки — обычные строки, по модулю на строку
#   (загрузчик работает ДО core/data.sh и слоем данных пользоваться не может).
#   Они заменили массивы bash BS_LOADED_MODULES и BS_LOAD_STACK.
#
# Состояние рекурсии (путь модуля, прежний BS_CURRENT_FILE, остаток списка зависимостей)
# хранится в позиционных параметрах: в POSIX у функции нет local, а вложенный load
# затёр бы глобальные переменные.
# The recursion state (module path, the previous BS_CURRENT_FILE, the rest of the dependency
# list) lives in positional parameters: POSIX has no local, and a nested load would clobber
# globals.
#
# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# ============================================================================
# ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ / GLOBAL VARIABLES
# ============================================================================

# @global __bs_ld_loaded — Loader: registry of loaded modules, newline-separated "\na\nb\n" (category: private)
# @global __bs_ld_loaded — Loader: реестр загруженных модулей через перевод строки "\na\nb\n" (категория: private)
__bs_ld_nl="
"
__bs_ld_loaded="${__bs_ld_loaded:-$__bs_ld_nl}"

# @global __bs_ld_stack — Loader: load stack for cycle detection, "\na\nb" (category: private)
# @global __bs_ld_stack — Loader: стек загрузки для обнаружения циклов, "\na\nb" (категория: private)
__bs_ld_stack="${__bs_ld_stack:-}"

# @global BS_CURRENT_FILE — Loader: file being sourced right now; POSIX modules take their directory from it (category: env)
# @global BS_CURRENT_FILE — Loader: файл, подключаемый прямо сейчас; POSIX-модули берут каталог из него (категория: env)
BS_CURRENT_FILE="${BS_CURRENT_FILE:-}"

# ============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ / HELPER FUNCTIONS
# ============================================================================

# @description Загружен ли модуль / Is the module loaded
# @param $1 module path / путь модуля
# @return 0 loaded, 1 not / 0 загружен, 1 нет
bs_load_is_loaded() {
  case "$__bs_ld_loaded" in
    *"${__bs_ld_nl}${1-}${__bs_ld_nl}"*) return 0 ;;
  esac
  return 1
}

# @description Глубина стека загрузки (0, когда ничего не грузится) / Depth of the load stack (0 when nothing is loading)
# @stdout number / число
bs_load_stack_size() {
  __bs_ld_n=0
  __bs_ld_rest="$__bs_ld_stack"
  while [ -n "$__bs_ld_rest" ]; do
    __bs_ld_rest="${__bs_ld_rest%"$__bs_ld_nl"*}"
    __bs_ld_n=$((__bs_ld_n + 1))
  done
  printf '%s\n' "$__bs_ld_n"
}

# @private
# @description Проверить циклические зависимости
# @description Check for circular dependencies
# @param $1 Путь к модулю
# @param $1 Module path
bs_load_check_cycle() {
  case "${__bs_ld_stack}${__bs_ld_nl}" in
    *"${__bs_ld_nl}${1:?Missing module path}${__bs_ld_nl}"*)
      printf 'BS: error: circular dependency detected:%s -> %s\n' "$(printf '%s' "$__bs_ld_stack" | tr '\n' ' ')" "$1" >&2
      return 1
      ;;
  esac
  return 0
}

# @private
# @description Загрузить зависимости из списка через запятую (рекурсивно через bs_load)
# @description Load dependencies from a comma-separated list (recursively through bs_load)
# @param $1 module path  $2 the rest of the list  $3 the current dependency (state)
bs_load_dep_list() {
  while [ -n "$2" ]; do
    case "$2" in
      *,*) set -- "$1" "${2#*,}" "${2%%,*}" ;;
      *)   set -- "$1" "" "$2" ;;
    esac
    # обрезаем пробелы по краям / trim the blanks on both sides
    set -- "$1" "$2" "${3#"${3%%[![:space:]]*}"}"
    set -- "$1" "$2" "${3%"${3##*[![:space:]]}"}"
    [ -n "$3" ] || continue
    if ! bs_load_is_loaded "$3"; then
      if ! bs_load "$3"; then
        printf "BS: error: failed to load dependency '%s' for module '%s'\n" "$3" "$1" >&2
        return 1
      fi
    fi
  done
  return 0
}

# @private
# @description Загрузить зависимости модуля
# @description Load module dependencies
# @param $1 Путь к модулю
# @param $1 Module path
bs_load_deps() {
  : "${1:?Missing module path}"
  if [ ! -f "${BS_ROOT}/${1}.sh" ]; then
    printf 'BS: error: module file not found: %s\n' "${BS_ROOT}/${1}.sh" >&2
    return 1
  fi

  # Парсим комментарии вида: # @depends core/logger, lib/system/utils
  # Parse comments like: # @depends core/logger, lib/system/utils
  __bs_ld_depends=""
  while IFS= read -r __bs_ld_line || [ -n "$__bs_ld_line" ]; do
    # строка комментария, в которой после @depends идёт пробел и список
    # a comment line with @depends followed by a blank and a list
    __bs_ld_t="${__bs_ld_line#"${__bs_ld_line%%[![:space:]]*}"}"
    case "$__bs_ld_t" in
      '#'*@depends[[:space:]]*)
        __bs_ld_depends="${__bs_ld_t#*@depends}"
        # Отрезаем trailing-комментарий (всё после очередного #)
        # Strip any trailing comment after another #
        __bs_ld_depends="${__bs_ld_depends%%#*}"
        __bs_ld_depends="${__bs_ld_depends#"${__bs_ld_depends%%[![:space:]]*}"}"
        __bs_ld_depends="${__bs_ld_depends%"${__bs_ld_depends##*[![:space:]]}"}"
        break
        ;;
    esac
  done < "${BS_ROOT}/${1}.sh"

  if [ -z "$__bs_ld_depends" ]; then
    return 0  # Нет зависимостей / No dependencies
  fi

  # Загружаем каждую зависимость / Load each dependency
  bs_load_dep_list "$1" "$__bs_ld_depends" ""
}

# ============================================================================
# ОСНОВНАЯ ФУНКЦИЯ ЗАГРУЗКИ / MAIN LOADING FUNCTION
# ============================================================================

# @private
# @description --strict-shell: refuse a lib/ module whose @shell tier does not
#   fit the shell BS was started from. core/ is the kernel and always allowed.
# @description --strict-shell: отказать модулю lib/, чей tier @shell не подходит
#   оболочке, из которой запущен BS. core/ — ядро, ему можно всегда.
# @param $1 module path / путь модуля
bs_load_strict_check() {
  [ "${BS_SHELL_STRICT:-0}" = "1" ] || return 0
  case "$1" in
    lib/*) ;;
    *) return 0 ;;
  esac
  command -v bs_shell_file_tier >/dev/null 2>&1 || return 0
  __bs_ld_tier="$(bs_shell_file_tier "${BS_ROOT}/${1}.sh")"
  __bs_ld_origin="${BS_ORIGIN_SHELL:-bash}"
  if bs_shell_tier_allows "$__bs_ld_tier" "$__bs_ld_origin"; then
    return 0
  fi
  printf '%s\n' \
    "BS: модуль '${1}' (@shell ${__bs_ld_tier}) нельзя исполнять из оболочки '${__bs_ld_origin}' (--strict-shell)" \
    "BS: module '${1}' (@shell ${__bs_ld_tier}) cannot run from shell '${__bs_ld_origin}' (--strict-shell)" \
    "    Запустите из подходящей оболочки или уберите --strict-shell / Run from a fitting shell or drop --strict-shell" >&2
  return 1
}

# @description Загрузить модуль по пути относительно BS_ROOT
# @description Load module by path relative to BS_ROOT
# @param $1 Путь к модулю без расширения .sh (например: "core/logger")
# @param $1 Module path without .sh extension (e.g.: "core/logger")
# @example
#   load "core/logger"
bs_load() {
  : "${1:?Missing module path}"

  # Валидация BS_ROOT / Validate BS_ROOT
  if [ -z "${BS_ROOT:-}" ]; then
    printf 'BS: error: BS_ROOT is not set\n' >&2
    return 1
  fi
  if [ ! -d "${BS_ROOT}" ]; then
    printf 'BS: error: BS_ROOT directory not found: %s\n' "${BS_ROOT}" >&2
    return 1
  fi

  # Проверка на повторную загрузку / Check for duplicate loading
  if bs_load_is_loaded "$1"; then
    return 0
  fi

  # --strict-shell: tier модуля против исходной оболочки / module tier vs the origin shell
  bs_load_strict_check "$1" || return 1

  # Проверка циклических зависимостей / Check for circular dependencies
  bs_load_check_cycle "$1" || return 1

  # Добавляем модуль в стек загрузки / Add module to loading stack
  __bs_ld_stack="${__bs_ld_stack}${__bs_ld_nl}${1}"

  # Загружаем зависимости модуля / Load module dependencies
  if ! bs_load_deps "$1"; then
    # Убираем модуль из стека загрузки при ошибке / Pop module from loading stack on error
    __bs_ld_stack="${__bs_ld_stack%"$__bs_ld_nl"*}"
    return 1
  fi

  # Загружаем файл модуля; прежний BS_CURRENT_FILE хранится во втором позиционном параметре
  # Load the module file; the previous BS_CURRENT_FILE is kept in the second positional parameter
  set -- "$1" "${BS_CURRENT_FILE:-}"
  BS_CURRENT_FILE="${BS_ROOT}/${1}.sh"
  # shellcheck disable=SC1090
  if ! . "${BS_ROOT}/${1}.sh"; then
    BS_CURRENT_FILE="$2"
    printf "BS: error: failed to load module '%s'\n" "$1" >&2
    # Убираем модуль из стека загрузки при ошибке / Pop module from loading stack on error
    __bs_ld_stack="${__bs_ld_stack%"$__bs_ld_nl"*}"
    return 1
  fi
  BS_CURRENT_FILE="$2"

  # Удаляем модуль из стека загрузки / Remove module from loading stack
  __bs_ld_stack="${__bs_ld_stack%"$__bs_ld_nl"*}"

  # Помечаем модуль как загруженный / Mark module as loaded
  __bs_ld_loaded="${__bs_ld_loaded}${1}${__bs_ld_nl}"

  return 0
}

# @description Загрузить модуль (короткое имя) / Load a module (the short name)
# @param $1 module path / путь модуля
load() {
  bs_load "$@"
}

# @description Полное имя функции для обратной совместимости
# @description Full function name for backward compatibility
if command -v bs_shell_alias >/dev/null 2>&1; then
  bs_shell_alias bs_load bs::load
fi
