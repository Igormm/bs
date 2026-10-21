#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, подстановки параметров, eval с проверкой имён; словарь — из core/data.sh / valid POSIX sh: case, parameter expansion, eval with name checks; the map comes from core/data.sh
# @tier core — builtins and sort; works everywhere
#
# core/config.sh — Unified configuration loader for BS
# core/config.sh — единый загрузчик конфигурации BS
#
# Loads configuration from defaults, user config, project-local config and
# environment variables. Provides getter/setter API.
#
# Usage / Использование:
#   load "core/config"
#   config::load
#   config::get "BS_LOG_LEVEL" "info"
#   config::set "BS_LOG_LEVEL" "debug"
#
# ИМЕНА / NAMES
#   Real functions: bs_config_load, bs_config_get, bs_config_set, bs_config_list,
#   bs_config_user_file, bs_config_local_file and the private bs_config_set_defaults,
#   bs_config_load_file, bs_config_export_to_env, bs_config_key_usable; in bash and zsh also
#   config::* (the old names).
#   The loaded configuration is the data-layer map bs_config (it was the associative array BS_CONFIG).
#   Настоящие функции — bs_config_*; в bash и zsh — ещё и config::*. Загруженная конфигурация —
#   словарь слоя данных bs_config (был ассоциативным массивом BS_CONFIG).
#
# КЛЮЧИ / KEYS
#   A key is also the name of an environment variable, so it is checked before any eval: a variable
#   name (bs_var_is_name), not the kernel's own (__bs_*) and not read-only (assigning to a read-only
#   variable ends a non-interactive shell). A key that fails the check is skipped in a file (a warning
#   for a reserved or read-only name) and refused by bs_config_set (status 2).
#   Ключ — ещё и имя переменной окружения, поэтому он проверяется до любого eval: имя переменной
#   (bs_var_is_name), не служебное (__bs_*) и не только для чтения (присваивание такой переменной
#   завершает неинтерактивную оболочку). Негодный ключ в файле пропускается (для служебного и
#   read-only имени — с предупреждением), bs_config_set его отклоняет (статус 2).
#
# @depends core/const, core/logger, core/utils, core/data, core/var

# shellcheck disable=SC2154  # значения присваиваются через eval / values are assigned through eval
bs_guard "CORE_CONFIG" || return 0

# Зависимости / Dependencies
bs_source_relative "const.sh" "logger.sh" "utils.sh" "data.sh" "var.sh"

# @global CORE_CONFIG_VERSION — Module version (category: module-flag)
# @global CORE_CONFIG_VERSION — Версия модуля (категория: module-flag)
# shellcheck disable=SC2034  # читают другие модули и тесты / read by other modules and tests
CORE_CONFIG_VERSION="1.0.0"

# @global BS_CONFIG_USER_DIR — Env: user config dir ~/.config/bs (category: env)
# @global BS_CONFIG_USER_DIR — Env: каталог конфигурации пользователя ~/.config/bs (категория: env)
# Без HOME (cron, systemd, env -i) пользовательского конфига нет: путь пуст / Without HOME (cron, systemd, env -i) there is no user config: the path is empty
bs_shell_readonly BS_CONFIG_USER_DIR="${HOME:+${HOME}/.config/bs}"
# @global BS_CONFIG_USER_FILE — Env: user config file (category: env)
# @global BS_CONFIG_USER_FILE — Env: файл конфигурации пользователя (категория: env)
bs_shell_readonly BS_CONFIG_USER_FILE="${BS_CONFIG_USER_DIR:+${BS_CONFIG_USER_DIR}/config.sh}"
# @global BS_CONFIG_LOCAL_FILE — Env: local (cwd) config file name (category: env)
# @global BS_CONFIG_LOCAL_FILE — Env: имя локального (cwd) конфиг-файла (категория: env)
bs_shell_readonly BS_CONFIG_LOCAL_FILE=".bsrc"
# @global BS_CONFIG_LOCAL_KEYS — Config: keys a project-local ./.bsrc may set (category: constant)
# @global BS_CONFIG_LOCAL_KEYS — Config: ключи, которые может задать локальный ./.bsrc (категория: constant)
bs_shell_readonly BS_CONFIG_LOCAL_KEYS=" BS_LOG_LEVEL BS_SILENT BS_FRAMEWORK_DRY_RUN BS_FRAMEWORK_DEBUG BS_FILES_ATOMIC BS_FILES_BACKUP_SUFFIX BS_FILES_ATOMIC_FALLBACK BS_LLM_PROVIDER BS_LLM_MODEL "

# ==========================================
# Private helpers / Приватные вспомогательные функции
# ==========================================

# @private
# @description Set default values for built-in configuration keys.
# @description Установить значения по умолчанию для встроенных ключей конфигурации.
bs_config_set_defaults() {
  bs_map_set bs_config BS_LOG_LEVEL "info"
  bs_map_set bs_config BS_SILENT "0"
  bs_map_set bs_config BS_FRAMEWORK_DRY_RUN "false"
  bs_map_set bs_config BS_FRAMEWORK_DEBUG "false"
  bs_map_set bs_config BS_RESULT_FILE ""
  bs_map_set bs_config BS_FILES_ATOMIC "false"
  bs_map_set bs_config BS_FILES_BACKUP_SUFFIX ""
  bs_map_set bs_config BS_FILES_ATOMIC_FALLBACK "true"
  bs_map_set bs_config BS_LLM_PROVIDER ""
  bs_map_set bs_config BS_LLM_MODEL ""
  bs_map_set bs_config BS_LLM_BASE_URL ""
  bs_map_set bs_config BS_LLM_API_KEY ""
}

# @private
# @description Can the key become an environment variable: a valid name, not the kernel's own (__bs_*), not read-only. / Может ли ключ стать переменной окружения: допустимое имя, не служебное (__bs_*), не только для чтения.
# @param $1 key / ключ
# @returns 0 usable / 1 not
bs_config_key_usable() {
  bs_var_is_name "${1-}" || return 1
  case "$1" in
    __bs_*) return 1 ;;
  esac
  # bs_var_is_readonly пробует присваивание в подоболочке и не завершает вызывающего / bs_var_is_readonly tries the assignment in a subshell and cannot end the caller
  if bs_var_is_readonly "$1"; then
    return 1
  fi
  return 0
}

# @private
# @description Parse a config file line by line (KEY=value) into the map.
# @description Разобрать файл конфигурации построчно (KEY=значение) в словарь.
# @param $1 File path / Путь к файлу
# @param $2 [optional] "local": accept only BS_CONFIG_LOCAL_KEYS (untrusted file)
#   / "local": принимать только BS_CONFIG_LOCAL_KEYS (недоверенный файл)
bs_config_load_file() {
  __bs_cf_file=${1:-}
  __bs_cf_trust=${2:-user}
  [ -n "$__bs_cf_file" ] && [ -f "$__bs_cf_file" ] || return 0
  bs_log_debug "Loading config file: ${__bs_cf_file}"
  while IFS= read -r __bs_cf_line || [ -n "$__bs_cf_line" ]; do
    [ -n "$__bs_cf_line" ] || continue
    # комментарий: пробелы, затем # / a comment: spaces, then #
    __bs_cf_trim=${__bs_cf_line#"${__bs_cf_line%%[![:space:]]*}"}
    case "$__bs_cf_trim" in '#'*) continue ;; esac
    case "$__bs_cf_line" in *=*) ;; *) continue ;; esac
    # ключ — идентификатор в начале строки, за ним необязательные пробелы и «=» / the key is an identifier at the start of the line, then optional spaces and "="
    __bs_cf_key=${__bs_cf_line%%=*}
    __bs_cf_key=${__bs_cf_key%"${__bs_cf_key##*[![:space:]]}"}
    bs_var_is_name "$__bs_cf_key" || continue
    __bs_cf_val=${__bs_cf_line#*=}
    __bs_cf_val=${__bs_cf_val#"${__bs_cf_val%%[![:space:]]*}"}
    if [ "$__bs_cf_trust" = "local" ]; then
      case "$BS_CONFIG_LOCAL_KEYS" in
        *" ${__bs_cf_key} "*) ;;
        *)
          bs_log_warn "config: ${__bs_cf_file}: key ${__bs_cf_key} is not allowed in a project-local file, ignored"
          continue ;;
      esac
    fi
    if ! bs_config_key_usable "$__bs_cf_key"; then
      bs_log_warn "config: ${__bs_cf_file}: key ${__bs_cf_key} is reserved or read-only, ignored"
      continue
    fi
    # значение в двойных или одинарных кавычках — снять их / a value in double or single quotes loses them
    case "$__bs_cf_val" in
      \"*\")
        if [ "${#__bs_cf_val}" -ge 2 ]; then __bs_cf_val=${__bs_cf_val#\"}; __bs_cf_val=${__bs_cf_val%\"}; fi ;;
      \'*\')
        if [ "${#__bs_cf_val}" -ge 2 ]; then __bs_cf_val=${__bs_cf_val#\'}; __bs_cf_val=${__bs_cf_val%\'}; fi ;;
    esac
    bs_map_set bs_config "$__bs_cf_key" "$__bs_cf_val"
  done < "$__bs_cf_file"
  return 0
}

# @private
# @description Export non-empty values for the keys in the positional parameters / Экспортировать непустые значения для ключей из позиционных параметров
bs_config_export_keys() {
  for __bs_cf_key in "$@"; do
    bs_map_get_to bs_config "$__bs_cf_key" __bs_cf_val || continue
    # bs_var_set отказывает негодному имени (статус 2): export такого имени завершил бы dash / bs_var_set refuses a bad name (status 2): export of such a name would end dash
    if [ -n "$__bs_cf_val" ] && bs_var_set "$__bs_cf_key" "$__bs_cf_val"; then
      export "${__bs_cf_key?}"
    fi
  done
}

# @private
# shellcheck disable=SC2120  # заменяет позиционные параметры списком ключей / replaces the positional parameters with the key list
# @description Export non-empty configuration values to the environment.
# @description Экспортировать непустые значения конфигурации в окружение.
bs_config_export_to_env() {
  bs_map_keys_to bs_config bscfgkeys
  bs_arr_to_args_to bscfgkeys __bs_cf_args
  eval "$__bs_cf_args"
  bs_config_export_keys "$@"
}

# ==========================================
# Public API / Публичный API
# ==========================================

# @description Load configuration: defaults, user file, project-local file, environment.
#   Priority (low → high): defaults, user config, local config, environment variables.
# @description Загрузить конфигурацию: умолчания, файл пользователя, локальный файл проекта, окружение.
#   Приоритет (низкий → высокий): дефолты, пользовательский config, локальный config, env.
# @return 0
# @example
#   config::load
bs_config_load() {
  bs_config_set_defaults

  # Ensure user config directory exists / Создаём директорию пользовательского конфига
  if [ -n "$BS_CONFIG_USER_DIR" ] && [ ! -d "$BS_CONFIG_USER_DIR" ]; then
    bs_utils_ignore mkdir -p "$BS_CONFIG_USER_DIR"
  fi

  # Load user config / Пользовательский конфиг
  if [ -n "$BS_CONFIG_USER_FILE" ]; then
    bs_config_load_file "$BS_CONFIG_USER_FILE"
  fi

  # Load project-local config / Локальный конфиг проекта
  if [ -f "$BS_CONFIG_LOCAL_FILE" ]; then
    bs_config_load_file "$BS_CONFIG_LOCAL_FILE" local
  fi

  # Environment variables override / Переменные окружения имеют приоритет
  bs_map_keys_to bs_config bscfgkeys
  bs_arr_to_args_to bscfgkeys __bs_cf_args
  eval "$__bs_cf_args"
  for __bs_cf_key in "$@"; do
    __bs_cf_env=''
    bs_var_get "$__bs_cf_key" __bs_cf_env || :
    if [ -n "$__bs_cf_env" ]; then
      bs_map_set bs_config "$__bs_cf_key" "$__bs_cf_env"
    fi
  done

  # ключи уже в "$@" — не копируем их из словаря второй раз
  # the keys are already in "$@" — do not copy them from the map again
  bs_config_export_keys "$@"
  return "${E_SUCCESS}"
}

# @description Get a configuration value (or a default).
# @description Получить значение конфигурации (или значение по умолчанию).
# @param $1 Key / Ключ
# @param $2 Default value (optional) / Значение по умолчанию (необязательно)
# @stdout Value / Значение
# @return 0 if found or defaulted, E_INVALID otherwise / 0 если найдено или есть умолчание, иначе E_INVALID
bs_config_get() {
  if [ -z "${1:-}" ]; then
    bs_log_warn "config::get: key required"
    return "${E_INVALID}"
  fi
  if bs_map_get_to bs_config "$1" __bs_cf_val; then
    printf '%s' "$__bs_cf_val"
  elif [ -n "${2:-}" ]; then
    printf '%s' "$2"
  else
    return "${E_INVALID}"
  fi
  return "${E_SUCCESS}"
}

# @description Set a configuration value, in the map and in the environment.
# @description Установить значение конфигурации — в словаре и в окружении.
# @param $1 Key / Ключ
# @param $2 Value / Значение
# @return 0 on success, E_INVALID if the key is empty, not a variable name, reserved (__bs_*) or read-only / 0 при успехе, E_INVALID если ключ пуст, не имя переменной, служебный (__bs_*) или только для чтения
bs_config_set() {
  if [ -z "${1:-}" ]; then
    bs_log_warn "config::set: key required"
    return "${E_INVALID}"
  fi
  if ! bs_config_key_usable "$1"; then
    bs_log_warn "config::set: not a usable variable name (invalid, reserved or read-only): $1"
    return "${E_INVALID}"
  fi
  __bs_cf_key=$1
  __bs_cf_val=${2:-}
  bs_map_set bs_config "$__bs_cf_key" "$__bs_cf_val"
  bs_var_set "$__bs_cf_key" "$__bs_cf_val"
  export "${__bs_cf_key?}"
  return "${E_SUCCESS}"
}

# @description Print all configuration as KEY=VALUE, sorted.
# @description Вывести всю конфигурацию как KEY=VALUE, по алфавиту.
bs_config_list() {
  bs_map_keys bs_config | sort | while IFS= read -r __bs_cf_key; do
    bs_map_get_to bs_config "$__bs_cf_key" __bs_cf_val
    printf '%s=%s\n' "$__bs_cf_key" "$__bs_cf_val"
  done
}

# @description Return path to user config file.
# @description Вернуть путь к пользовательскому файлу конфигурации.
# @stdout Path / Путь
bs_config_user_file() {
  printf '%s' "$BS_CONFIG_USER_FILE"
}

# @description Return the name of the project-local config file.
# @description Вернуть имя локального файла конфигурации проекта.
# @stdout Name / Имя
bs_config_local_file() {
  printf '%s' "$BS_CONFIG_LOCAL_FILE"
}

bs_shell_alias bs_config_set_defaults __config::set_defaults
bs_shell_alias bs_config_load_file __config::load_file
bs_shell_alias bs_config_export_to_env __config::export_to_env
bs_shell_alias bs_config_load config::load
bs_shell_alias bs_config_get config::get
bs_shell_alias bs_config_set config::set
bs_shell_alias bs_config_list config::list
bs_shell_alias bs_config_user_file config::user_file
bs_shell_alias bs_config_local_file config::local_file
