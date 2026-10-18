#!/usr/bin/env bash
# @shell bash4 — нужны конструкции bash: double-bracket [[ ]], arithmetic command (( )), array, nameref / needs bash constructs: double-bracket [[ ]], arithmetic command (( )), array, nameref
#
#
#

# core/utils.sh
# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

bs::guard "UTILS" || return 0


# Устанавливает строгий режим.
# @description Enable strict bash mode (set -euo pipefail).
# @description Включить строгий режим bash (set -euo pipefail).
# @function utils::strict
utils::strict() {
  set -euo pipefail
  IFS=$'\n\t'
}

# Проверяет, был ли уже загружен модуль.
# Возвращает 0 – если уже загружён (нужно прервать выполнение модуля),
#            1 – если ещё не загружен (можно продолжать).
# Использование:
#   if utils::guard "foo"; then return 0; fi
#   readonly __FOO_SOURCED=1
# @function utils::guard
# @deprecated Используйте bs::guard из core/prereq.sh — она и проверяет, и ставит метку
# @description Check if module already loaded / guard against double sourcing.
# @description Проверить, загружен ли уже модуль, идиома защиты от повторного включения.
# @param $1 {string} Уникальное имя модуля (без __ и _SOURCED)
# @returns 0  модуль уже загружался
# @returns 1  модуль ещё не загружался
utils::guard() {
  local -r module="${1:?Module name required}"
  bs::guard_loaded "${module}"
}

# utils::has, utils::quiet, utils::quiet_err, utils::ignore, utils::attempt —
# в core/quiet.sh (@shell posix); init.sh загружает его перед этим модулем.
# utils::has, utils::quiet, utils::quiet_err, utils::ignore, utils::attempt live
# in core/quiet.sh (@shell posix); init.sh loads it before this module.

# @global UTILS_TMP_REGISTRY — Utils: temp file registry ($$-scoped) (category: constant)
# @global UTILS_TMP_REGISTRY — Utils: реестр временных файлов (в скоупе $$) (категория: constant)
declare -g UTILS_TMP_REGISTRY="${TMPDIR:-/tmp}/bs-tmp-registry.$$"

utils::tempfile() {
  local dir_mode=0
  local prefix="bs.$$"
  case "${1:-}" in
    --dir) dir_mode=1; prefix="${2:-bs.$$}" ;;
    *) prefix="${1:-bs.$$}" ;;
  esac
  local path
  if (( dir_mode == 1 )); then
    path="$(mktemp -d "${TMPDIR:-/tmp}/${prefix}.XXXXXX")" || return 1
  else
    path="$(mktemp "${TMPDIR:-/tmp}/${prefix}.XXXXXX")" || return 1
  fi
  # Реестр лежит в общем TMPDIR под предсказуемым именем: чужой или
  # подложенный симлинком файл не принимаем (иначе cleanup удалил бы
  # чужие пути, а запись пошла бы по симлинку).
  # The registry lives in the shared TMPDIR under a predictable name: a
  # foreign or symlink-planted file is refused (else cleanup would delete
  # someone else's paths and the append would follow the symlink).
  if [[ ! -e "${UTILS_TMP_REGISTRY}" && ! -L "${UTILS_TMP_REGISTRY}" ]]; then
    ( umask 077; set -C; : > "${UTILS_TMP_REGISTRY}" ) 2>/dev/null || true
  fi
  if ! utils::__tmp_registry_trusted; then
    rm -rf -- "${path}"
    log::error "utils::tempfile: temp registry is not ours, refusing: ${UTILS_TMP_REGISTRY}"
    return 1
  fi
  printf '%s\n' "${path}" >> "${UTILS_TMP_REGISTRY}"
  printf '%s\n' "${path}"
  return 0
}

# @private
# @description The temp registry is a regular file owned by us (not a symlink).
# @description Реестр временных файлов — обычный файл нашего владельца (не симлинк).
utils::__tmp_registry_trusted() {
  [[ ! -L "${UTILS_TMP_REGISTRY}" && -f "${UTILS_TMP_REGISTRY}" && -O "${UTILS_TMP_REGISTRY}" ]]
}

# @private
# @description Remove all recorded temp paths (main process only).
# @description Удалить все записанные временные пути (только главный процесс).
#   A registry that is not ours is ignored; only paths inside the registry's own
#   directory are removed.
#   Чужой реестр игнорируется; удаляются только пути внутри каталога реестра.
utils::__tmp_cleanup() {
  ! bs::shell::in_subshell || return 0
  [[ -e "${UTILS_TMP_REGISTRY}" || -L "${UTILS_TMP_REGISTRY}" ]] || return 0
  utils::__tmp_registry_trusted || return 0
  local p base="${UTILS_TMP_REGISTRY%/*}"
  while IFS= read -r p; do
    case "${p}" in
      "${base}"/*/../*|"${base}"/../*|*/..|*"/../"*) continue ;;
      "${base}"/?*) rm -rf -- "${p}" ;;
    esac
  done < "${UTILS_TMP_REGISTRY}"
  rm -f -- "${UTILS_TMP_REGISTRY}"
  return 0
}

# utils::human_size, utils::head_bytes, utils::now_s, utils::now_ms, utils::now_float,
# utils::stamp, utils::log_stamp — в core/fmt.sh (@shell posix); init.sh загружает его перед этим модулем.
# utils::human_size, utils::head_bytes, utils::now_s, utils::now_ms, utils::now_float,
# utils::stamp, utils::log_stamp live in core/fmt.sh (@shell posix); init.sh loads it before this module.

# Разбивает строку на массив по заданному разделителю.
# Безопасна при любом IFS вызывающего: устанавливает локальный IFS внутри функции.
# @function utils::split
# @description Split string into array by delimiter.
# @description Разбить строку на массив по разделителю.
# @param $1 {string} Имя выходного массива
# @param $2 {string} Исходная строка
# @param $3 {string} Разделитель (по умолчанию пробел)
# @example
#   utils::split my_array "a b c"
#   utils::split my_array "one,two,three" ","
utils::split() {
  local -n __utils_split_ref="${1:?Array variable name required}"
  local str="${2:-}"
  local delim="${3:- }"

  local IFS="${delim}"
  # Пустая строка даёт пустой массив, а не массив из одной пустой строки
  if is::empty "${str}"; then
    __utils_split_ref=()
    return 0
  fi

  read -ra __utils_split_ref <<< "${str}"
}

# Проверяет существование файла-источника, загружает его и убеждается,
# что требуемая функция появилась в окружении.
# Возвращает 0 при успехе, 1 при любой ошибке.
# Глобальные переменные не изменяются.
#
# Аргументы:
#   $1  путь до файла (обязательный)
#   $2  имя проверяемой функции (обязательный)
# Вывод:
#   Всё диагностическое пишет в STDERR
# Load target file and confirm required function exists.
#
# @function utils::ensure_source
# @description Load file and verify required function exists.
# @description Загрузить файл и проверить, что требуемая функция существует.
# @param $1 {string} Absolute or relative path to file (must exist)
# @param $2 {string} Function name to check after sourcing
# @returns 0  If file loaded and function present
# @returns 1  Missing file, failed source, or function absent
# @stderr   Diagnostic messages
# @example
#   utils::ensure_source "${ROOT_DIR}/lib/math.sh" add_integers
utils::ensure_source() {
  local -r file="${1:?File path is required}"
  local -r func="${2:?Function name is required}"

  #  валидация аргументов
  is::not_empty "${file}" || { log::error "file argument is empty"; return "${E_INVALID:-2}"; }
  is::not_empty "${func}" || { log::error "function argument is empty"; return "${E_INVALID:-2}"; }

  if ! is::file "${file}"; then
    log::error "file not found: ${file}"
    return "${E_ERROR:-1}"
  fi

  if ! source -- "${file}"; then
    log::error "failed to source file: ${file}"
    return "${E_ERROR:-1}"
  fi

  if ! declare -F -- "${func}" >/dev/null 2>&1; then
    log::error "required function ${func} not defined"
    return "${E_ERROR:-1}"
  fi

  return 0
}

# Function to check if current shell is at least the required version
# @description Verify shell meets version requirement.
# @description Проверить, что версия оболочки соответствует требованиям.
utils::ensure_shell_version() {
    local -r required_version="${1:-4}"  # Default to version 4 if not specified

    # Оболочку и версию определяет bs::shell::* (рантайм, не $SHELL)
    # The shell and its version come from bs::shell::* (runtime, not $SHELL)
    bs::shell::ensure_version "${required_version}" 0 || return "${E_ERROR:-1}"

    printf 'Shell %s meets version requirement (>= %s)\n' "$(bs::shell::name)" "${required_version}"
    return 0
}

## @brief Получение корневой директории фреймворка
# @description Detect framework root directory regardless of invocation.
# @description Определить корневую директорию фреймворка независимо от способа вызова.
## @description Определяет путь независимо от способа вызова
## @global Устанавливает FRAMEWORK_ROOT
utils::detect_root() {
    # 1. Пробуем получить из переменной окружения
    if is::not_empty "${FRAMEWORK_ROOT:-}" && is::dir "${FRAMEWORK_ROOT}"; then
        # log:: опционален для utils (нижний уровень) / log:: is optional for utils
        if declare -F log::debug >/dev/null 2>&1; then
            log::debug "FRAMEWORK_ROOT задан явно: ${FRAMEWORK_ROOT}"
        fi
        return 0
    fi

    # 2. Каталог этого файла (core/utils.sh), симлинки раскрыты
    local script_dir
    script_dir="$(bs::script_dir)"

    # 5. Переход на уровень выше (если каталог — bin/ или core/; это каталог
    #    самого core/utils.sh, а не вызывающего скрипта)
    #    One level up (if the directory is bin/ or core/; it is the directory of
    #    core/utils.sh itself, not of the calling script)
    if [[ "$(basename -- "${script_dir}")" == "bin" || "$(basename -- "${script_dir}")" == "core" ]]; then
        script_dir="$(dirname -- "${script_dir}")"
    fi

    # 6. Абсолютный путь
    FRAMEWORK_ROOT="$(cd -- "${script_dir}" && pwd -P)"
    export FRAMEWORK_ROOT

    # log:: опционален для utils (нижний уровень) / log:: is optional for utils
    if declare -F log::info >/dev/null 2>&1; then
        log::info "Корень фреймворка: ${FRAMEWORK_ROOT}"
    fi
    return 0
}

#bootdir
# @description Определить каталог bootstrap/ фреймворка / Detect framework bootstrap/ dir
utils::boot_dir() {
  BOOT_DIR="$(cd -- "$(bs::script_dir)/../bootstrap" &>/dev/null && pwd)"
  export BOOT_DIR
}

# Регистрация очистки temp-файлов при загрузке: подстановки $(...) не переживут
# регистрацию, поэтому она происходит здесь, в главном процессе.
# Register temp cleanup at load time: command substitutions would lose the
# registration, so it happens here, in the main process.
if declare -F cleanup::add >/dev/null 2>&1; then
  cleanup::add utils::__tmp_cleanup
fi
