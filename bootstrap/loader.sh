#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, подстановки параметров, read -r; реестр и стек загрузки — на слое core/data.sh / valid POSIX sh: case, parameter expansion, read -r; the registry and the load stack are on the core/data.sh layer
# @tier core — builtins only; works everywhere
#
# bootstrap/loader.sh — модуль загрузки с предотвращением повторного подключения
# bootstrap/loader.sh — loading module with duplicate loading prevention
#
# Что делает / What it does
#   bs_load core/logger  → читает «# @depends …» модуля, загружает зависимости, подключает файл,
#   помечает модуль загруженным; повторный вызов ничего не делает; цикл зависимостей — ошибка.
#   bs_load core/logger  → reads the module's "# @depends …", loads the dependencies, sources the
#   file and marks the module loaded; a second call does nothing; a dependency cycle is an error.
#
# Состояние / State
#   Реестр загруженных — словарь слоя данных bs_loaded_modules (был BS_LOADED_MODULES), стек
#   загрузки — массив bs_load_stack (был BS_LOAD_STACK), стек файлов — bs_load_files. Слой данных
#   и всё, что ему нужно (prereq, var, str, data), загрузчик подключает сам при первом вызове:
#   это нижний слой «априори», до него в ядре ничего нет.
#   The registry of loaded modules is the data-layer map bs_loaded_modules (it was
#   BS_LOADED_MODULES), the load stack is the array bs_load_stack (was BS_LOAD_STACK), the file
#   stack is bs_load_files. The loader sources the data layer and what it needs (prereq, var, str,
#   data) itself on the first call: this is the a-priori bottom layer, nothing is below it.
#
# ИМЕНА / NAMES
#   Real functions: bs_load, bs_load_prepare, bs_load_check_circular_dependency,
#   bs_load_load_dependencies, bs_load_read_depends, bs_load_strict_shell_check,
#   bs_load_restore_file, bs_log_available; in bash and zsh also load, bs::load, load::__*,
#   log::available (the old names, used by the whole framework).
#   Настоящие функции: bs_load и приватные bs_load_*, bs_log_available; в bash и zsh — ещё и
#   load, bs::load, load::__*, log::available (прежние имена, их зовёт весь фреймворк).
#
# Рекурсия / Recursion
#   Временные переменные глобальны, а bs_load рекурсивен (модуль зовёт load): после любого
#   вложенного вызова путь модуля берётся с вершины bs_load_stack, а не из переменной.
#   Temporaries are global and bs_load is recursive (a module calls load): after any nested call
#   the module path is read from the top of bs_load_stack, not from a variable.

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# POSIX-часть pre-kernel (base.sh с реестром оболочек shell.sh) и, в bash, bs.sh. Всё идемпотентно:
# безопасно, если init.sh уже подключил.
# The POSIX part of the pre-kernel (base.sh with the shell registry shell.sh) and, in bash, bs.sh.
# All idempotent: safe when init.sh has sourced them already.
if ! command -v bs_strict >/dev/null 2>&1 && [ -f "${BS_BOOTSTRAP_DIR:-}/base.sh" ]; then
  # shellcheck disable=SC1090,SC1091
  . "${BS_BOOTSTRAP_DIR}/base.sh"
fi
if ! command -v bs_shell_family >/dev/null 2>&1 && [ -f "${BS_BOOTSTRAP_DIR:-}/shell.sh" ]; then
  # shellcheck disable=SC1090,SC1091
  . "${BS_BOOTSTRAP_DIR}/shell.sh"
fi
if command -v bs_shell_family >/dev/null 2>&1; then
  case "$(bs_shell_family)" in
    bash)
      if [ -f "${BS_BOOTSTRAP_DIR:-}/bs.sh" ]; then
        # shellcheck disable=SC1090,SC1091
        . "${BS_BOOTSTRAP_DIR}/bs.sh"
      fi ;;
  esac
fi

# @global BS_CURRENT_FILE — Loader: file being sourced right now; POSIX modules take their directory from it (category: env)
# @global BS_CURRENT_FILE — Loader: файл, подключаемый прямо сейчас; POSIX-модули берут каталог из него (категория: env)
BS_CURRENT_FILE=${BS_CURRENT_FILE:-}

# ============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ / HELPER FUNCTIONS
# ============================================================================

# @private
# @description Проверяет, доступна ли функция логирования
# @description Checks if logging function is available
# @param $1 function name / имя функции
bs_log_available() {
  command -v "$1" >/dev/null 2>&1
}

# @private
# @description Проверить BS_ROOT и подключить нижний слой (prereq, var, str, data), если его ещё нет / Check BS_ROOT and source the bottom layer (prereq, var, str, data) if it is not there yet
# @returns 0 ok / 1 BS_ROOT is not usable or a layer file failed
bs_load_prepare() {
  if [ -z "${BS_ROOT:-}" ]; then
    printf '%s\n' "BS: error: BS_ROOT is not set" >&2
    return 1
  fi
  if [ ! -d "${BS_ROOT}" ]; then
    printf '%s\n' "BS: error: BS_ROOT directory not found: ${BS_ROOT}" >&2
    return 1
  fi
  if command -v bs_map_set >/dev/null 2>&1; then
    return 0
  fi
  __bs_ld_prev=$BS_CURRENT_FILE
  for __bs_ld_layer in prereq var str data; do
    BS_CURRENT_FILE="${BS_ROOT}/core/${__bs_ld_layer}.sh"
    # shellcheck disable=SC1090
    if ! . "$BS_CURRENT_FILE"; then
      printf '%s\n' "BS: error: failed to load the base layer: core/${__bs_ld_layer}.sh" >&2
      BS_CURRENT_FILE=$__bs_ld_prev
      return 1
    fi
  done
  BS_CURRENT_FILE=$__bs_ld_prev
}

# @private
# @description Проверить циклические зависимости / Check for circular dependencies
# @param $1 Путь к модулю / Module path
bs_load_check_circular_dependency() {
  if bs_arr_contains bs_load_stack "${1:?Missing module path}"; then
    __bs_ld_chain=$(bs_arr_join bs_load_stack ' ')
    printf '%s\n' "BS: error: circular dependency detected: ${__bs_ld_chain} -> ${1}" >&2
    return 1
  fi
  return 0
}

# @private
# @description Прочитать из файла первую строку «# @depends a, b» → __bs_ld_deps (пусто — зависимостей нет) / Read the first "# @depends a, b" line of a file → __bs_ld_deps (empty means no dependencies)
# @param $1 module file / файл модуля
bs_load_read_depends() {
  __bs_ld_deps=''
  while IFS= read -r __bs_ld_line || [ -n "$__bs_ld_line" ]; do
    case "$__bs_ld_line" in
      *@depends*) ;;
      *) continue ;;
    esac
    # строка — комментарий: первый непробельный символ «#» / the line is a comment: its first non-blank character is "#"
    __bs_ld_text=$(bs_str_ltrim "$__bs_ld_line")
    case "$__bs_ld_text" in
      '#'*) ;;
      *) continue ;;
    esac
    __bs_ld_text=${__bs_ld_text#*@depends}
    case "$__bs_ld_text" in
      ' '?*|'	'?*) ;;
      *) continue ;;
    esac
    # отрезаем замыкающий комментарий и пробелы по краям / cut a trailing comment and the blanks at the edges
    __bs_ld_text=${__bs_ld_text%%'#'*}
    __bs_ld_deps=$(bs_str_trim "$__bs_ld_text")
    break
  done < "$1"
}

# @private
# @description Загрузить зависимости модуля / Load module dependencies
# @param $1 Путь к модулю / Module path
bs_load_load_dependencies() {
  __bs_ld_file="${BS_ROOT}/${1:?Missing module path}.sh"
  if [ ! -f "$__bs_ld_file" ]; then
    printf '%s\n' "BS: error: module file not found: ${__bs_ld_file}" >&2
    return 1
  fi
  bs_load_read_depends "$__bs_ld_file"
  if [ -z "$__bs_ld_deps" ]; then
    return 0  # Нет зависимостей / No dependencies
  fi

  # Зависимости — в позиционные параметры: цикл «for … in "$@"» раскрывается один раз и не
  # страдает от вложенных вызовов, которые затирают временные переменные.
  # The dependencies go into the positional parameters: a "for … in "$@"" loop is expanded once
  # and survives the nested calls that clobber the temporaries.
  set --
  __bs_ld_rest=$__bs_ld_deps
  while [ -n "$__bs_ld_rest" ]; do
    case "$__bs_ld_rest" in
      *,*)
        __bs_ld_item=${__bs_ld_rest%%,*}
        __bs_ld_rest=${__bs_ld_rest#*,} ;;
      *)
        __bs_ld_item=$__bs_ld_rest
        __bs_ld_rest='' ;;
    esac
    __bs_ld_item=${__bs_ld_item#"${__bs_ld_item%%[! 	]*}"}
    __bs_ld_item=${__bs_ld_item%"${__bs_ld_item##*[! 	]}"}
    if [ -n "$__bs_ld_item" ]; then
      set -- "$@" "$__bs_ld_item"
    fi
  done

  for __bs_ld_dep in "$@"; do
    if ! bs_map_has bs_loaded_modules "$__bs_ld_dep"; then
      if ! bs_load "$__bs_ld_dep"; then
        bs_arr_get bs_load_stack -1 __bs_ld_mod
        printf '%s\n' "BS: error: failed to load dependency '${__bs_ld_dep}' for module '${__bs_ld_mod}'" >&2
        return 1
      fi
    fi
  done
  return 0
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
bs_load_strict_shell_check() {
  [ "${BS_SHELL_STRICT:-0}" = "1" ] || return 0
  case "$1" in
    lib/*) ;;
    *) return 0 ;;
  esac
  command -v bs_shell_file_tier >/dev/null 2>&1 || return 0
  __bs_ld_origin=${BS_ORIGIN_SHELL:-bash}
  __bs_ld_tier=$(bs_shell_file_tier "${BS_ROOT}/${1}.sh")
  if bs_shell_tier_allows "$__bs_ld_tier" "$__bs_ld_origin"; then
    return 0
  fi
  printf '%s\n' \
    "BS: модуль '${1}' (@shell ${__bs_ld_tier}) нельзя исполнять из оболочки '${__bs_ld_origin}' (--strict-shell)" \
    "BS: module '${1}' (@shell ${__bs_ld_tier}) cannot run from shell '${__bs_ld_origin}' (--strict-shell)" \
    "    Запустите из подходящей оболочки или уберите --strict-shell / Run from a fitting shell or drop --strict-shell" >&2
  return 1
}

# @private
# @description Вернуть BS_CURRENT_FILE, который был до подключения модуля / Put back the BS_CURRENT_FILE that was there before the module was sourced
bs_load_restore_file() {
  bs_arr_pop bs_load_files BS_CURRENT_FILE
}

# @description Загрузить модуль по пути относительно BS_ROOT
# @description Load module by path relative to BS_ROOT
# @param $1 Путь к модулю без расширения .sh (например: "core/logger")
# @param $1 Module path without .sh extension (e.g.: "core/logger")
# @example
#   bs_load "core/logger"      # bash and zsh: load "core/logger"
bs_load() {
  __bs_ld_mod=${1:?Missing module path}

  # Валидация BS_ROOT и нижний слой / Validate BS_ROOT and the bottom layer
  bs_load_prepare || return 1

  # Проверка на повторную загрузку / Check for duplicate loading
  if bs_map_has bs_loaded_modules "$__bs_ld_mod"; then
    return 0
  fi

  # --strict-shell: tier модуля против исходной оболочки / module tier vs the origin shell
  bs_load_strict_shell_check "$__bs_ld_mod" || return 1

  # Проверка циклических зависимостей / Check for circular dependencies
  bs_load_check_circular_dependency "$__bs_ld_mod" || return 1

  # Добавляем модуль в стек загрузки / Add module to loading stack
  bs_arr_push bs_load_stack "$__bs_ld_mod"

  # Загружаем зависимости модуля / Load module dependencies
  if ! bs_load_load_dependencies "$__bs_ld_mod"; then
    # Убираем модуль из стека загрузки при ошибке / Pop module from loading stack on error
    bs_arr_pop bs_load_stack __bs_ld_gone
    return 1
  fi

  # Загружаем файл модуля; путь — с вершины стека (вложенные вызовы затёрли переменную)
  # Load the module file; the path comes from the top of the stack (nested calls clobbered the variable)
  bs_arr_get bs_load_stack -1 __bs_ld_mod
  bs_arr_push bs_load_files "$BS_CURRENT_FILE"
  BS_CURRENT_FILE="${BS_ROOT}/${__bs_ld_mod}.sh"
  # shellcheck disable=SC1090
  if ! . "$BS_CURRENT_FILE"; then
    bs_load_restore_file
    bs_arr_get bs_load_stack -1 __bs_ld_mod
    printf '%s\n' "BS: error: failed to load module '${__bs_ld_mod}'" >&2
    bs_arr_pop bs_load_stack __bs_ld_gone
    return 1
  fi
  bs_load_restore_file

  # Удаляем модуль из стека загрузки и помечаем загруженным / Remove from the stack and mark as loaded
  bs_arr_get bs_load_stack -1 __bs_ld_mod
  bs_arr_pop bs_load_stack __bs_ld_gone
  bs_map_set bs_loaded_modules "$__bs_ld_mod" 1
  return 0
}

bs_shell_alias bs_load load
bs_shell_alias bs_load bs::load
bs_shell_alias bs_load_check_circular_dependency load::__check_circular_dependency
bs_shell_alias bs_load_load_dependencies load::__load_dependencies
bs_shell_alias bs_load_strict_shell_check load::__strict_shell_check
bs_shell_alias bs_log_available log::available
