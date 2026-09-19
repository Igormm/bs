#!/usr/bin/env bash
#
# core/repl.sh — Interactive BS REPL
# Интерактивная консоль BS: загруженное ядро + оценка выражений на лету.
#
# Usage / Использование:
#   bs repl
#   bs repl --help
#
# Команды REPL: :help, :load, :list, :doc, :info, :version, :hist, :!N,
#               :exit
# Всё остальное выполняется как bash-выражение внутри загруженного ядра
# (load "core/args" … работает прямо в сессии).
#
# Переменные окружения / Environment:
#   BS_REPL_PROMPT1  основной промпт (по умолчанию "bs> ") / main prompt
#   BS_REPL_PROMPT2  промпт продолжения (по умолчанию "...> ") / continuation
#   BS_REPL_HISTORY_FILE  файл истории (по умолчанию $XDG_CONFIG_HOME/bs/repl_history)

# Source Guard / Защита от повторной загрузки
bs::guard "CORE_REPL" || return 0

# История сессии / Session history (последние 200 строк)
declare -g REPL_HISTORY=()
readonly REPL_HISTORY_MAX=200

# @description Показать справку REPL / Show REPL help
repl::help() {
  cat <<HELP
BS REPL ${BS_VERSION:-} — interactive shell for the BS framework

Usage / Использование:
  bs repl [--help|-h]

REPL commands / Команды:
  :help, :h       Show this help / Справка
  :load <module>  Load a module (e.g. :load lib/io/streams) / Загрузить модуль
  :list           List available modules (core/ lib/) / Список модулей
  :doc <func>     Print function source (declare -f) / Исходник функции
  :info <module>  Print module header / Заголовок модуля
  :version        Show framework version / Версия фреймворка
  :hist           Show command history / История команд
  :!N             Re-run history entry N / Повторить команду N из истории
  :exit, :q       Exit REPL / Выход

Everything else is evaluated as bash in the loaded BS environment.
Любое другое выражение выполняется как bash в загруженном окружении BS.

Examples / Примеры:
  bs> load "core/args"
  bs> is::file /etc
  bs> system::hw::cpu_model
HELP
}

# @description Путь к файлу истории / History file path
repl::__history_file() {
  printf '%s\n' "${BS_REPL_HISTORY_FILE:-${XDG_CONFIG_HOME:-${HOME}/.config}/bs/repl_history}"
}

# @private
# @description Загрузить историю из файла / Load history from a file
repl::__history_load() {
  local file="${1:-}"
  if ! is::file "${file}"; then
    return 0
  fi
  mapfile -t REPL_HISTORY < "${file}"
}

# @private
# @description Добавить строку в историю / Append a line to history
repl::__history_add() {
  local line="${1:-}"
  if is::empty "${line}"; then
    return 0
  fi
  REPL_HISTORY+=("${line}")
  if (( ${#REPL_HISTORY[@]} > REPL_HISTORY_MAX )); then
    local -a kept
    kept=("${REPL_HISTORY[@]: -${REPL_HISTORY_MAX}}")
    REPL_HISTORY=("${kept[@]}")
  fi
}

# @private
# @description Сохранить историю в файл / Save history to a file
repl::__history_save() {
  local file
  file="$(repl::__history_file)"
  local dir
  dir="$(dirname -- "${file}")"
  if ! mkdir -p -- "${dir}"; then
    log::warn "repl: cannot create history dir: ${dir}"
    return 0
  fi
  if (( ${#REPL_HISTORY[@]} == 0 )); then
    return 0
  fi
  printf '%s\n' "${REPL_HISTORY[@]}" > "${file}" 2>/dev/null || {
    log::warn "repl: cannot write history: ${file}"
    return 0
  }
}

# @private
# @description Прочитать строку с readline (read -e), без pipefail-суицида
repl::__read() {
  local prompt="${1:-}"
  local out_var="${2:-}"
  local buf=""
  if ! read -r -e -p "${prompt}" buf; then
    return 1
  fi
  printf -v "${out_var}" '%s' "${buf}"
  return 0
}

# @private
# @description Выполнить выражение в текущем процессе / Eval in this process
#   Состояние сохраняется между строками (eval в текущем процессе).
#   Во время выполнения строки отключаем errexit/nounset: фатальные ошибки
#   расширения (unbound var) не должны убивать REPL. Код возврата строки
#   захватывается до восстановления опций.
repl::__eval() {
  local line="${1:-}"
  local rc=0

  set +e +u
  eval "${line}"
  rc=$?
  set -e -u

  if (( rc != 0 )); then
    log::error "expression failed (rc=${rc}): ${line}"
  fi
  return 0
}

# @private
# @description Выполнить строку как REPL-команду / Handle a REPL command
# @return 0 — продолжить цикл; 1 — запрошен выход / continue; 1 — exit request
repl::__command() {
  local line="${1:-}"
  local word="${line%% *}"
  local rest="${line#* }"

  case "${word}" in
    :h|:help)
      repl::help ;;
    :q|:quit|:exit)
      return 1 ;;
    :version)
      bs::version::print ;;
    :list)
      local file
      while IFS= read -r file; do
        printf '  %s\n' "${file#"${BS_ROOT}"/}"
      done < <(find "${BS_ROOT}/core" "${BS_ROOT}/lib" -type f -name "*.sh" 2>/dev/null | sort) ;;
    :load)
      local mod="${rest%% .sh}"
      mod="${mod%.sh}"
      if is::empty "${mod}"; then
        log::warn "usage: :load <module> (e.g. :load lib/io/streams)"
      elif load "${mod}"; then
        log::success "loaded: ${mod}"
      else
        log::error "failed to load: ${mod}"
      fi
      ;;
    :doc)
      if is::empty "${rest}"; then
        log::warn "usage: :doc <function>"
      elif declare -F -- "${rest%% *}" >/dev/null 2>&1; then
        declare -f -- "${rest%% *}"
      else
        log::error "function not found: ${rest%% *}"
      fi
      ;;
    :info)
      local mod="${rest%.sh}"
      if is::empty "${mod}"; then
        log::warn "usage: :info <module> (e.g. :info lib/system/hw)"
      elif is::file "${BS_ROOT}/${mod}.sh"; then
        sed -n '1,8p' -- "${BS_ROOT}/${mod}.sh"
        if [[ -n "${BS_LOADED_MODULES["${mod}"]:-}" ]]; then
          printf '[loaded]\n'
        else
          printf '[not loaded — use :load %s]\n' "${mod}"
        fi
      else
        log::error "module not found: ${mod}"
      fi
      ;;
    :hist)
      local -i idx=0
      local entry
      for entry in "${REPL_HISTORY[@]}"; do
        printf '%3d  %s\n' "$((++idx))" "${entry}"
      done
      ;;
    :!*)
      local num="${word#:!}"
      if [[ "${num}" =~ ^[0-9]+$ ]] && (( num >= 1 )) && (( num <= ${#REPL_HISTORY[@]} )); then
        local entry="${REPL_HISTORY[$((num - 1))]}"
        printf '%s\n' "${entry}"
        repl::__eval "${entry}"
      else
        log::warn "no history entry: ${word}"
      fi
      ;;
    *)
      log::warn "unknown REPL command: ${word} (see :help)"
      ;;
  esac
  return 0
}

# @description Точка входа REPL / REPL entry point
repl::main() {
  case "${1:-}" in
    -h|--help)
      repl::help
      return 0 ;;
  esac

  local history_file prompt ps1 ps2 line buffer
  history_file="$(repl::__history_file)"
  ps1="${BS_REPL_PROMPT1:-bs> }"
  ps2="${BS_REPL_PROMPT2:-...> }"

  repl::__history_load "${history_file}"

  printf 'BS REPL %s — BS Bash framework interactive shell\n' "${BS_VERSION:-}"
  printf 'Тех, кто не знает команд, отправляем в :help; выход — :exit\n'

  while true; do
    buffer=""
    while true; do
      if is::not_empty "${buffer}"; then
        prompt="${ps2}"
      else
        prompt="${ps1}"
      fi

      if ! repl::__read "${prompt}" line; then
        # EOF: сохраняем историю и выходим / EOF: save history and exit
        repl::__history_save
        printf '\n'
        return 0
      fi

      if [[ "${line}" == *'\' ]]; then
        buffer+="${line%\\}"
        buffer+=$'\n'
        continue
      fi

      if is::not_empty "${buffer}"; then
        buffer+="${line}"
      else
        buffer="${line}"
      fi
      break
    done

    if is::empty "${buffer}"; then
      continue
    fi

    repl::__history_add "${buffer}"

    if [[ "${buffer:0:1}" == ":" ]]; then
      if ! repl::__command "${buffer}"; then
        break
      fi
    else
      repl::__eval "${buffer}"
    fi
  done

  repl::__history_save
  return 0
}