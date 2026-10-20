#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, подстановки параметров, mktemp, массивы — из core/data.sh / valid POSIX sh: case, parameter expansion, mktemp; arrays come from core/data.sh
# @tier core — builtins and mktemp; works everywhere
#
# core/utils.sh — прочие помощники среды (идиомы тишины — в core/quiet.sh, размеры и время — в core/fmt.sh)
# core/utils.sh — the other environment helpers (the silence idioms are in core/quiet.sh, sizes and time in core/fmt.sh)
#
# ИМЕНА / NAMES
#   Real functions: bs_utils_strict, bs_utils_guard, bs_utils_tempfile, bs_utils_split,
#   bs_utils_ensure_source, bs_utils_ensure_shell_version, bs_utils_detect_root, bs_utils_boot_dir,
#   bs_utils_tmp_cleanup, bs_utils_tmp_registry_trusted; in bash and zsh also utils::* (the old names).
#   Настоящие функции — bs_utils_*; в bash и zsh — ещё и прежние utils::*.

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

bs_guard UTILS || return 0

# Dependencies / Зависимости
bs_source_relative "msg.sh"

# Устанавливает строгий режим (pipefail — там, где он есть; IFS — перевод строки и табуляция).
# @description Enable strict mode (pipefail where it exists; IFS is newline and tab).
# @description Включить строгий режим (pipefail — где есть; IFS — перевод строки и табуляция).
# @function utils::strict
bs_utils_strict() {
  bs_shell_strict
}

# Проверяет, был ли уже загружен модуль.
# @function utils::guard
# @deprecated Используйте bs_guard из core/prereq.sh — она и проверяет, и ставит метку
# @description Check if a module is already loaded / guard against double sourcing.
# @description Проверить, загружен ли уже модуль, идиома защиты от повторного включения.
# @param $1 {string} Уникальное имя модуля (без __ и _SOURCED)
# @returns 0  модуль уже загружался
# @returns 1  модуль ещё не загружался
bs_utils_guard() {
  bs_guard_loaded "${1:?Module name required}"
}

# @global UTILS_TMP_REGISTRY — Utils: temp file registry ($$-scoped) (category: constant)
# @global UTILS_TMP_REGISTRY — Utils: реестр временных файлов (в скоупе $$) (категория: constant)
UTILS_TMP_REGISTRY="${TMPDIR:-/tmp}/bs-tmp-registry.$$"

# Создаёт временный файл (или каталог с --dir) и записывает его в реестр очистки.
# @function utils::tempfile
# @description Create a temp file (or directory with --dir) and record it in the cleanup registry.
# @description Создать временный файл (или каталог с --dir) и записать его в реестр очистки.
# @param $1 prefix, or --dir / префикс или --dir
# @param $2 prefix after --dir / префикс после --dir
# @stdout path / путь
bs_utils_tempfile() {
  __bs_ut_dir_mode=0
  __bs_ut_prefix="bs.$$"
  case "${1:-}" in
    --dir) __bs_ut_dir_mode=1; __bs_ut_prefix="${2:-bs.$$}" ;;
    *) __bs_ut_prefix="${1:-bs.$$}" ;;
  esac
  if [ "$__bs_ut_dir_mode" -eq 1 ]; then
    __bs_ut_path=$(mktemp -d "${TMPDIR:-/tmp}/${__bs_ut_prefix}.XXXXXX") || return 1
  else
    __bs_ut_path=$(mktemp "${TMPDIR:-/tmp}/${__bs_ut_prefix}.XXXXXX") || return 1
  fi
  # Реестр лежит в общем TMPDIR под предсказуемым именем: чужой или подложенный симлинком файл
  # не принимаем (иначе cleanup удалил бы чужие пути, а запись пошла бы по симлинку).
  # The registry lives in the shared TMPDIR under a predictable name: a foreign or symlink-planted
  # file is refused (else cleanup would delete someone else's paths and the append would follow the symlink).
  if [ ! -e "$UTILS_TMP_REGISTRY" ] && [ ! -L "$UTILS_TMP_REGISTRY" ]; then
    ( umask 077; set -C; : > "$UTILS_TMP_REGISTRY" ) 2>/dev/null || true
  fi
  if ! bs_utils_tmp_registry_trusted; then
    rm -rf -- "$__bs_ut_path"
    bs_msg_error "utils::tempfile: temp registry is not ours, refusing: ${UTILS_TMP_REGISTRY}"
    return 1
  fi
  printf '%s\n' "$__bs_ut_path" >> "$UTILS_TMP_REGISTRY"
  printf '%s\n' "$__bs_ut_path"
  return 0
}

# @private
# @description Реестр — обычный файл нашего пользователя, не ссылка / The registry is a regular file of our user, not a link
bs_utils_tmp_registry_trusted() {
  # shellcheck disable=SC3067  # -O (владелец) проверен в dash, ash, ksh, mksh, zsh и bash / -O (owner) was checked in dash, ash, ksh, mksh, zsh and bash
  [ ! -L "$UTILS_TMP_REGISTRY" ] && [ -f "$UTILS_TMP_REGISTRY" ] && [ -O "$UTILS_TMP_REGISTRY" ]
}

# @private
# @description Удалить всё, что записано в реестре, и сам реестр (вызывается при выходе) / Remove everything the registry lists, and the registry (called on exit)
bs_utils_tmp_cleanup() {
  # в подоболочке реестр трогать нельзя: он принадлежит основному процессу / a subshell must not touch the registry: it belongs to the main process
  if bs_shell_in_subshell; then return 0; fi
  [ -e "$UTILS_TMP_REGISTRY" ] || [ -L "$UTILS_TMP_REGISTRY" ] || return 0
  bs_utils_tmp_registry_trusted || return 0
  __bs_ut_base=${UTILS_TMP_REGISTRY%/*}
  while IFS= read -r __bs_ut_p; do
    case "$__bs_ut_p" in
      "$__bs_ut_base"/*/../*|"$__bs_ut_base"/../*|*/..|*"/../"*) continue ;;
      "$__bs_ut_base"/?*) rm -rf -- "$__bs_ut_p" ;;
    esac
  done < "$UTILS_TMP_REGISTRY"
  rm -f -- "$UTILS_TMP_REGISTRY"
  return 0
}

# @private
# @description Разделить символы-разделители на пробельные (→ __bs_ut_ws) и прочие (→ __bs_ut_nw) / Split the delimiter characters into whitespace (→ __bs_ut_ws) and others (→ __bs_ut_nw)
# @param $1 delimiter characters / символы-разделители
bs_utils_split_classify() {
  __bs_ut_ws=''
  __bs_ut_nw=''
  __bs_ut_d=$1
  while [ -n "$__bs_ut_d" ]; do
    __bs_ut_rest=${__bs_ut_d#?}
    __bs_ut_c=${__bs_ut_d%"$__bs_ut_rest"}
    __bs_ut_d=$__bs_ut_rest
    case "$__bs_ut_c" in
      ' '|'	'|'
') __bs_ut_ws="${__bs_ut_ws}${__bs_ut_c}" ;;
      *) __bs_ut_nw="${__bs_ut_nw}${__bs_ut_c}" ;;
    esac
  done
}

# @private
# @description Пропустить в начале __bs_ut_s все пробельные разделители (__bs_ut_ws) / Skip the whitespace delimiters (__bs_ut_ws) at the start of __bs_ut_s
bs_utils_split_skip_ws() {
  while [ -n "$__bs_ut_s" ]; do
    __bs_ut_c=${__bs_ut_s%"${__bs_ut_s#?}"}
    case "$__bs_ut_ws" in *"$__bs_ut_c"*) __bs_ut_s=${__bs_ut_s#?} ;; *) break ;; esac
  done
}

# Разбивает строку на массив по символам-разделителям, как read -ra с IFS=разделители:
# пробельные разделители склеиваются, остальные дают пустые поля, конечный разделитель
# пустого поля не добавляет. Результат — массив слоя данных (bs_arr_*), а не массив bash.
# @function utils::split
# @description Split a string into an array by delimiter characters, like read -ra with IFS=delimiters:
#   whitespace delimiters collapse, others give empty fields, a trailing delimiter adds no empty field.
#   The result is a data-layer array (bs_arr_*), not a bash array.
# @description Разбить строку на массив по символам-разделителям (как read -ra с IFS). Результат — массив
#   слоя данных (bs_arr_*), а не массив bash.
# @param $1 {string} Имя выходного массива (слоя данных) / name of the output (data-layer) array
# @param $2 {string} Исходная строка / the string
# @param $3 {string} Символы-разделители (по умолчанию пробел) / delimiter characters (a space by default)
bs_utils_split() {
  __bs_ut_arr=${1:?Array variable name required}
  __bs_ut_str=${2:-}
  __bs_ut_delim=${3:- }
  bs_arr_clear "$__bs_ut_arr" || return 2
  [ -n "$__bs_ut_str" ] || return 0
  bs_utils_split_classify "$__bs_ut_delim"
  __bs_ut_s=$__bs_ut_str
  # ведущие пробельные разделители пропускаем / skip the leading whitespace delimiters
  bs_utils_split_skip_ws
  while [ -n "$__bs_ut_s" ]; do
    # поле: символы до разделителя / a field: the characters up to a delimiter
    __bs_ut_cur=''
    while [ -n "$__bs_ut_s" ]; do
      __bs_ut_c=${__bs_ut_s%"${__bs_ut_s#?}"}
      case "$__bs_ut_ws" in *"$__bs_ut_c"*) break ;; esac
      case "$__bs_ut_nw" in *"$__bs_ut_c"*) break ;; esac
      __bs_ut_cur="${__bs_ut_cur}${__bs_ut_c}"
      __bs_ut_s=${__bs_ut_s#?}
    done
    bs_arr_push "$__bs_ut_arr" "$__bs_ut_cur"
    [ -n "$__bs_ut_s" ] || break
    # разделитель: пробелы, затем необязательный непробельный символ, затем снова пробелы / the delimiter: spaces, an optional other character, spaces again
    bs_utils_split_skip_ws
    if [ -n "$__bs_ut_s" ]; then
      __bs_ut_c=${__bs_ut_s%"${__bs_ut_s#?}"}
      case "$__bs_ut_nw" in
        *"$__bs_ut_c"*)
          __bs_ut_s=${__bs_ut_s#?}
          bs_utils_split_skip_ws ;;
      esac
    fi
  done
  return 0
}

# Подключает файл и проверяет, что в нём определена нужная функция.
# @function utils::ensure_source
# @description Source a file and check that it defines the required function.
# @description Подключить файл и проверить, что он определяет нужную функцию.
# @param $1 {string} Путь к файлу / file path
# @param $2 {string} Имя функции / function name
bs_utils_ensure_source() {
  __bs_ut_file=${1:?File path is required}
  __bs_ut_func=${2:?Function name is required}
  [ -n "$__bs_ut_file" ] || { bs_msg_error "file argument is empty"; return "${E_INVALID:-2}"; }
  [ -n "$__bs_ut_func" ] || { bs_msg_error "function argument is empty"; return "${E_INVALID:-2}"; }
  if [ ! -f "$__bs_ut_file" ]; then
    bs_msg_error "file not found: ${__bs_ut_file}"
    return "${E_ERROR:-1}"
  fi
  # shellcheck disable=SC1090  # путь известен только во время выполнения / the path is known only at run time
  if ! . "$__bs_ut_file"; then
    bs_msg_error "failed to source file: ${__bs_ut_file}"
    return "${E_ERROR:-1}"
  fi
  if ! command -v "$__bs_ut_func" >/dev/null 2>&1; then
    bs_msg_error "required function ${__bs_ut_func} not defined"
    return "${E_ERROR:-1}"
  fi
  return 0
}

# @function utils::ensure_shell_version
# @deprecated Версию проверяет POSIX-пролог (bs_shell_host_ok) / The POSIX prologue checks the version (bs_shell_host_ok)
# @description Check the major version of the running shell.
# @description Проверить старшую версию запущенной оболочки.
# @param $1 required major version, default 4 / требуемая старшая версия, по умолчанию 4
bs_utils_ensure_shell_version() {
  __bs_ut_req=${1:-4}
  __bs_ut_maj=$(bs_shell_version_major)
  __bs_ut_min=$(bs_shell_version_minor)
  if [ "$__bs_ut_maj" -lt "$__bs_ut_req" ]; then
    printf 'ERROR: %s %s.0+ required, found %s.%s\n' "$(bs_shell_family)" "$__bs_ut_req" "$__bs_ut_maj" "$__bs_ut_min" >&2
    return "${E_ERROR:-1}"
  fi
  printf 'Shell %s meets version requirement (>= %s)\n' "$(bs_shell_family)" "$__bs_ut_req"
  return 0
}

# Определяет корень фреймворка (FRAMEWORK_ROOT): заданный явно или BS_ROOT.
# @function utils::detect_root
# @description Detect the framework root (FRAMEWORK_ROOT): the one set explicitly, or BS_ROOT.
# @description Определить корень фреймворка (FRAMEWORK_ROOT): заданный явно или BS_ROOT.
bs_utils_detect_root() {
  if [ -n "${FRAMEWORK_ROOT:-}" ] && [ -d "$FRAMEWORK_ROOT" ]; then
    if command -v bs_log_debug >/dev/null 2>&1; then
      bs_log_debug "FRAMEWORK_ROOT задан явно: ${FRAMEWORK_ROOT}"
    fi
    return 0
  fi
  FRAMEWORK_ROOT=$(cd -- "${BS_ROOT:?BS_ROOT is not set}" && pwd -P) || return 1
  export FRAMEWORK_ROOT
  if command -v bs_log_info >/dev/null 2>&1; then
    bs_log_info "Корень фреймворка: ${FRAMEWORK_ROOT}"
  fi
  return 0
}

# Каталог bootstrap/ (BOOT_DIR): его определяет init.sh (BS_BOOTSTRAP_DIR).
# @function utils::boot_dir
# @description The bootstrap/ directory (BOOT_DIR): init.sh sets it (BS_BOOTSTRAP_DIR).
# @description Каталог bootstrap/ (BOOT_DIR): его задаёт init.sh (BS_BOOTSTRAP_DIR).
bs_utils_boot_dir() {
  BOOT_DIR=${BS_BOOTSTRAP_DIR:-${BS_ROOT:?BS_ROOT is not set}/bootstrap}
  export BOOT_DIR
}

bs_shell_alias bs_utils_strict utils::strict
bs_shell_alias bs_utils_guard utils::guard
bs_shell_alias bs_utils_tempfile utils::tempfile
bs_shell_alias bs_utils_tmp_registry_trusted utils::__tmp_registry_trusted
bs_shell_alias bs_utils_tmp_cleanup utils::__tmp_cleanup
bs_shell_alias bs_utils_split utils::split
bs_shell_alias bs_utils_ensure_source utils::ensure_source
bs_shell_alias bs_utils_ensure_shell_version utils::ensure_shell_version
bs_shell_alias bs_utils_detect_root utils::detect_root
bs_shell_alias bs_utils_boot_dir utils::boot_dir

# Очистка временных файлов при выходе: через стек очистки, когда он есть / Cleanup of temp files on exit: through the cleanup stack when there is one
if command -v bs_cleanup_add >/dev/null 2>&1; then
  bs_cleanup_add bs_utils_tmp_cleanup
elif command -v cleanup::add >/dev/null 2>&1; then
  cleanup::add bs_utils_tmp_cleanup
fi
