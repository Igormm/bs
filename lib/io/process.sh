#!/usr/bin/env bs
# shellcheck shell=bash
#
# lib/io/process.sh — Process Guard for BS
# lib/io/process.sh — обёртка-сторож процесса с таймаутом, hang-детекцией
# и диагностическим снимком /proc/<pid> + strace.
#
# This module runs a command under supervision: it monitors stdout/stderr
# activity and total runtime, collects diagnostics on timeout/hang, and
# terminates the process gracefully (TERM → grace → KILL).
#
# Usage / Использование:
#   load "lib/io/process"
#   io::process::guard --timeout 60 --hang-after 30 -- wget https://example.com/file.iso
#
# @depends core/const, core/logger, core/utils, core/errorhandler

# Source Guard / Защита от повторной загрузки
# Load core prerequisites if not already available
if ! declare -f bs::guard >/dev/null 2>&1; then
    source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/prereq.sh"
fi
bs::guard "IO_PROCESS" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "../../core/errorhandler.sh"

# Module version / Версия модуля
# shellcheck disable=SC2034
declare -g IO_PROCESS_VERSION="1.0.0"
# shellcheck disable=SC2034
declare -g IO_PROCESS_LOADED="1"

# Exit codes specific to this module / Специфичные коды возврата модуля
readonly IO_PROCESS_EXIT_TIMEOUT=124
readonly IO_PROCESS_EXIT_HANG=125
readonly IO_PROCESS_EXIT_KILLED=126

# Global runtime state / Глобальное состояние выполнения
declare -gA IO_PROCESS_CONFIG
declare -g IO_PROCESS_CURRENT_PID=""
declare -ga IO_PROCESS_CMD=()

# ==========================================
# Private helpers / Приватные вспомогательные функции
# ==========================================

# @private
# @description Reset configuration to defaults (env → hardcoded).
# @description Сбросить конфигурацию к значениям по умолчанию.
io::process::__reset_config() {
  IO_PROCESS_CONFIG=(
    [timeout]="${BS_PROCESS_GUARD_TIMEOUT:-0}"
    [hang_after]="${BS_PROCESS_GUARD_HANG_AFTER:-0}"
    [strace_duration]="${BS_PROCESS_GUARD_STRACE_DURATION:-5}"
    [strace_file]="${BS_PROCESS_GUARD_STRACE_FILE:-true}"
    [strace_net]="${BS_PROCESS_GUARD_STRACE_NET:-false}"
    [diagnostic_dir]="${BS_PROCESS_GUARD_DIAGNOSTIC_DIR:-}"
    [kill_signal]="${BS_PROCESS_GUARD_KILL_SIGNAL:-TERM}"
    [grace_period]="${BS_PROCESS_GUARD_GRACE_PERIOD:-5}"
    [sudo]="${BS_PROCESS_GUARD_SUDO:-auto}"
    [auto_diag_dir]="false"
    [cmd_str]=""
  )
}

# @private
# @description Parse guard options until command starts.
# @description Разобрать опции до начала команды.
# @param $@ All arguments / Все аргументы
# @return E_INVALID on bad option / E_INVALID при плохой опции
# @sideeffect Populates IO_PROCESS_CONFIG and IO_PROCESS_CMD.
io::process::__parse_opts() {
  while [[ $# -gt 0 ]]; do
    local opt="${1}"
    case "${opt}" in
      --timeout|--hang-after|--strace-duration)
        if [[ $# -lt 2 ]]; then
          log::warn "Option ${opt} requires a value"
          return "${E_INVALID}"
        fi
        if ! [[ "${2}" =~ ^[0-9]+$ ]]; then
          log::warn "Option ${opt} requires a non-negative integer, got: ${2}"
          return "${E_INVALID}"
        fi
        case "${opt}" in
          --timeout)        IO_PROCESS_CONFIG[timeout]="${2}" ;;
          --hang-after)     IO_PROCESS_CONFIG[hang_after]="${2}" ;;
          --strace-duration) IO_PROCESS_CONFIG[strace_duration]="${2}" ;;
        esac
        shift 2
        ;;
      --diagnostic-dir)
        if [[ $# -lt 2 ]]; then
          log::warn "Option ${opt} requires a value"
          return "${E_INVALID}"
        fi
        IO_PROCESS_CONFIG[diagnostic_dir]="${2}"
        IO_PROCESS_CONFIG[auto_diag_dir]="false"
        shift 2
        ;;
      --kill-signal)
        if [[ $# -lt 2 ]]; then
          log::warn "Option ${opt} requires a value"
          return "${E_INVALID}"
        fi
        IO_PROCESS_CONFIG[kill_signal]="${2}"
        shift 2
        ;;
      --grace-period)
        if [[ $# -lt 2 ]]; then
          log::warn "Option ${opt} requires a value"
          return "${E_INVALID}"
        fi
        if ! [[ "${2}" =~ ^[0-9]+$ ]]; then
          log::warn "Option ${opt} requires a non-negative integer, got: ${2}"
          return "${E_INVALID}"
        fi
        IO_PROCESS_CONFIG[grace_period]="${2}"
        shift 2
        ;;
      --strace-file)        IO_PROCESS_CONFIG[strace_file]="true"; shift ;;
      --no-strace-file)     IO_PROCESS_CONFIG[strace_file]="false"; shift ;;
      --strace-net)         IO_PROCESS_CONFIG[strace_net]="true"; shift ;;
      --no-strace-net)      IO_PROCESS_CONFIG[strace_net]="false"; shift ;;
      --sudo)               IO_PROCESS_CONFIG[sudo]="yes"; shift ;;
      --no-sudo)            IO_PROCESS_CONFIG[sudo]="no"; shift ;;
      --)
        shift
        break
        ;;
      --*)
        log::warn "Unknown option: ${opt}"
        return "${E_INVALID}"
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ $# -eq 0 ]]; then
    log::warn "No command specified"
    return "${E_INVALID}"
  fi

  # Store command string for reports / Сохранить командную строку для отчётов
  IO_PROCESS_CONFIG[cmd_str]="$*"
  IO_PROCESS_CMD=("$@")
  return "${E_SUCCESS}"
}

# @private
# @description Determine whether to use sudo for strace.
# @description Определить, нужно ли использовать sudo для strace.
# @return 0 to use sudo, 1 otherwise / 0 — использовать sudo
io::process::__use_sudo() {
  local sudo_mode="${IO_PROCESS_CONFIG[sudo]}"

  if [[ "${sudo_mode}" == "no" ]]; then
    return 1
  fi

  if [[ "${sudo_mode}" == "yes" ]]; then
    if utils::has sudo; then
      return 0
    fi
    log::warn "sudo requested but not available"
    return 1
  fi

  # auto
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    return 1
  fi

  if ! utils::has sudo; then
    return 1
  fi

  # Check non-interactive sudo / Проверить non-interactive sudo
  if utils::quiet_err sudo -n true; then
    return 0
  fi

  return 1
}

# @private
# @description Ensure diagnostic directory exists.
# @description Создать каталог для диагностики.
# @return 0 on success, LIB_ERROR_FILE_OPERATION on failure
io::process::__ensure_diagnostic_dir() {
  local dir="${IO_PROCESS_CONFIG[diagnostic_dir]}"

  if [[ -z "${dir}" ]]; then
    dir="$(mktemp -d)"
    if [[ -z "${dir}" || ! -d "${dir}" ]]; then
      log::error "Failed to create diagnostic directory"
      return "${LIB_ERROR_FILE_OPERATION}"
    fi
    IO_PROCESS_CONFIG[diagnostic_dir]="${dir}"
    IO_PROCESS_CONFIG[auto_diag_dir]="true"
  elif [[ ! -d "${dir}" ]]; then
    if ! mkdir -p -- "${dir}"; then
      log::error "Failed to create diagnostic directory: ${dir}"
      return "${LIB_ERROR_FILE_OPERATION}"
    fi
    IO_PROCESS_CONFIG[auto_diag_dir]="false"
  fi

  return "${E_SUCCESS}"
}

# @private
# @description Run strace for a given trace category.
# @description Запустить strace для заданной категории.
# @param $1 PID
# @param $2 Output directory
# @param $3 strace trace expression
# @param $4 Output filename
io::process::__run_strace() {
  local pid="${1}"
  local dir="${2}"
  local trace_expr="${3}"
  local outfile="${4}"
  local outpath="${dir}/${outfile}"
  local duration="${IO_PROCESS_CONFIG[strace_duration]}"

  if ! utils::has strace; then
    log::debug "strace not available, skipping ${trace_expr} trace"
    return 1
  fi

  if ! kill -0 "${pid}" 2>/dev/null; then
    log::debug "Process ${pid} not alive, skipping strace"
    return 1
  fi

  local -a sudo_cmd=()
  if io::process::__use_sudo; then
    sudo_cmd=(sudo -n)
  fi

  log::debug "Running strace -e trace=${trace_expr} on PID ${pid} for ${duration}s"

  if utils::has timeout; then
    utils::ignore timeout "${duration}" "${sudo_cmd[@]}" strace -p "${pid}" \
      -e "trace=${trace_expr}" -T -tt -o "${outpath}"
  else
    # Fallback without external timeout / Резерв без внешнего timeout
    local strace_pid
    "${sudo_cmd[@]}" strace -p "${pid}" -e "trace=${trace_expr}" -T -tt -o "${outpath}" \
      >/dev/null 2>&1 &
    strace_pid=$!
    ( sleep "${duration}"; utils::ignore kill -TERM "${strace_pid}" ) &
    utils::ignore wait "${strace_pid}"
  fi
}

# @private
# @description Collect diagnostic snapshot for a running process.
# @description Собрать диагностический снимок работающего процесса.
# @param $1 PID
# @param $2 Reason (timeout|hang)
# @param $3 Diagnostic directory
io::process::__diagnose() {
  local pid="${1}"
  local reason="${2}"
  local dir="${3}"
  local report="${dir}/report.log"

  log::info "Collecting diagnostics for PID ${pid} (reason: ${reason}) into ${dir}"

  {
    echo "=== Process Guard Diagnostic Report ==="
    echo "Timestamp: $(date -Iseconds)"
    echo "Reason: ${reason}"
    echo "PID: ${pid}"
    echo "Command: ${IO_PROCESS_CONFIG[cmd_str]}"
    echo ""

    echo "=== Process status (ps) ==="
    ps -p "${pid}" -o pid,ppid,user,comm,cmd,etime,%cpu,%mem,stat 2>/dev/null || echo "unavailable"
    echo ""

    if [[ -d "/proc/${pid}" ]]; then
      echo "=== /proc/${pid}/status ==="
      cat "/proc/${pid}/status" 2>/dev/null || echo "unavailable"
      echo ""

      echo "=== /proc/${pid}/cmdline ==="
      tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null || echo "unavailable"
      echo ""
      echo ""

      echo "=== /proc/${pid}/stack ==="
      cat "/proc/${pid}/stack" 2>/dev/null || echo "unavailable"
      echo ""

      echo "=== /proc/${pid}/fd ==="
      ls -l "/proc/${pid}/fd" 2>/dev/null || echo "unavailable"
      echo ""

      echo "=== /proc/${pid}/wchan ==="
      cat "/proc/${pid}/wchan" 2>/dev/null || echo "unavailable"
      echo ""
    else
      echo "=== /proc/${pid} unavailable ==="
    fi
  } > "${report}"

  if [[ "${IO_PROCESS_CONFIG[strace_file]}" == "true" ]]; then
    io::process::__run_strace "${pid}" "${dir}" "read,write,%file" "strace_file.log"
  fi

  if [[ "${IO_PROCESS_CONFIG[strace_net]}" == "true" ]]; then
    io::process::__run_strace "${pid}" "${dir}" "%net" "strace_net.log"
  fi
}

# @private
# @description Terminate a process with signal → grace → KILL.
# @description Завершить процесс: сигнал → пауза → KILL.
# @param $1 PID
io::process::__terminate() {
  local pid="${1}"
  local signal="${IO_PROCESS_CONFIG[kill_signal]}"
  local grace="${IO_PROCESS_CONFIG[grace_period]}"

  if ! kill -0 "${pid}" 2>/dev/null; then
    return
  fi

  log::warn "Terminating process ${pid} with signal ${signal}"
  utils::ignore kill -s "${signal}" "${pid}"

  local deadline_ms
  deadline_ms=$(( $(date +%s%3N) + grace * 1000 ))

  while kill -0 "${pid}" 2>/dev/null; do
    local now_ms
    now_ms=$(date +%s%3N)
    if [[ "${now_ms}" -ge "${deadline_ms}" ]]; then
      break
    fi
    sleep 0.2
  done

  if kill -0 "${pid}" 2>/dev/null; then
    log::warn "Process ${pid} did not exit in ${grace}s, sending KILL"
    utils::ignore kill -KILL "${pid}"
  fi
}

# @private
# @description Cleanup handler registered with cleanup::add.
# @description Обработчик очистки, зарегистрированный через cleanup::add.
io::process::__cleanup_handler() {
  local pid="${IO_PROCESS_CURRENT_PID:-}"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    utils::ignore kill -KILL "${pid}"
    utils::ignore wait "${pid}"
  fi
  IO_PROCESS_CURRENT_PID=""

  if [[ "${IO_PROCESS_CONFIG[auto_diag_dir]:-false}" == "true" ]]; then
    local dir="${IO_PROCESS_CONFIG[diagnostic_dir]:-}"
    if [[ -n "${dir}" && -d "${dir}" ]]; then
      utils::ignore rm -rf "${dir}"
    fi
  fi
}

# ==========================================
# Public API / Публичный API
# ==========================================

# @description Run a command under process guard.
# @description Запустить команду под надзором сторожа.
# @param $@ Options followed by command and its arguments.
# @return Command exit code on success,
#         IO_PROCESS_EXIT_TIMEOUT (124) on timeout,
#         IO_PROCESS_EXIT_HANG (125) on hang,
#         IO_PROCESS_EXIT_KILLED (126) if forced KILL was required,
#         E_INVALID (2) on argument errors.
# @example
#   io::process::guard --timeout 60 --hang-after 30 -- wget https://example.com/file.iso
io::process::guard() {
  io::process::__reset_config

  if ! io::process::__parse_opts "$@"; then
    return "${E_INVALID}"
  fi

  local -a cmd=("${IO_PROCESS_CMD[@]}")

  if [[ ${#cmd[@]} -eq 0 ]]; then
    log::warn "No command to guard"
    return "${E_INVALID}"
  fi

  if [[ "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]; then
    log::warn "[DRY-RUN] io::process::guard would run: ${cmd[*]}"
    return "${E_SUCCESS}"
  fi

  if ! io::process::__ensure_diagnostic_dir; then
    return "${LIB_ERROR_FILE_OPERATION}"
  fi

  local diag_dir="${IO_PROCESS_CONFIG[diagnostic_dir]}"
  local stdout_log="${diag_dir}/stdout.log"
  local stderr_log="${diag_dir}/stderr.log"

  cleanup::add io::process::__cleanup_handler

  log::info "Guarding command (timeout=${IO_PROCESS_CONFIG[timeout]} hang_after=${IO_PROCESS_CONFIG[hang_after]}): ${cmd[*]}"

  # Start command with stdout/stderr captured to files.
  # Запускаем команду, перехватывая stdout/stderr в файлы.
  local pid
  "${cmd[@]}" > "${stdout_log}" 2> "${stderr_log}" &
  pid=$!
  IO_PROCESS_CURRENT_PID="${pid}"

  local timeout_ms=$(( IO_PROCESS_CONFIG[timeout] * 1000 ))
  local hang_after_ms=$(( IO_PROCESS_CONFIG[hang_after] * 1000 ))
  local start_ms
  start_ms=$(date +%s%3N)
  local last_output_ms=${start_ms}
  local prev_stdout_size=0
  local prev_stderr_size=0
  local reason=""
  local cmd_rc=0

  while true; do
    if ! kill -0 "${pid}" 2>/dev/null; then
      # Process finished naturally / Процесс завершился сам
      break
    fi

    local now_ms
    now_ms=$(date +%s%3N)

    if [[ "${IO_PROCESS_CONFIG[timeout]}" -gt 0 ]]; then
      if [[ $((now_ms - start_ms)) -ge "${timeout_ms}" ]]; then
        reason="timeout"
        break
      fi
    fi

    if [[ "${IO_PROCESS_CONFIG[hang_after]}" -gt 0 ]]; then
      local stdout_size stderr_size
      stdout_size=$(stat -c %s "${stdout_log}" 2>/dev/null || echo 0)
      stderr_size=$(stat -c %s "${stderr_log}" 2>/dev/null || echo 0)

      if [[ "${stdout_size}" -gt "${prev_stdout_size}" || "${stderr_size}" -gt "${prev_stderr_size}" ]]; then
        last_output_ms=${now_ms}
        prev_stdout_size=${stdout_size}
        prev_stderr_size=${stderr_size}
      elif [[ $((now_ms - last_output_ms)) -ge "${hang_after_ms}" ]]; then
        reason="hang"
        break
      fi
    fi

    sleep 0.5
  done

  if [[ -n "${reason}" ]]; then
    io::process::__diagnose "${pid}" "${reason}" "${diag_dir}"
    io::process::__terminate "${pid}"
    wait "${pid}"
    cmd_rc=$?

    log::warn "Process ${pid} stopped due to ${reason}; diagnostics: ${diag_dir}"

    case "${reason}" in
      timeout)
        IO_PROCESS_CURRENT_PID=""
        return "${IO_PROCESS_EXIT_TIMEOUT}"
        ;;
      hang)
        IO_PROCESS_CURRENT_PID=""
        return "${IO_PROCESS_EXIT_HANG}"
        ;;
      *)
        IO_PROCESS_CURRENT_PID=""
        return "${IO_PROCESS_EXIT_KILLED}"
        ;;
    esac
  fi

  # Collect exit code of naturally finished process / Собираем код завершения
  wait "${pid}"
  cmd_rc=$?

  # Replay captured output / Проигрываем захваченный вывод
  if [[ -s "${stdout_log}" ]]; then
    cat "${stdout_log}"
  fi
  if [[ -s "${stderr_log}" ]]; then
    cat "${stderr_log}" >&2
  fi

  # Remove auto-created diagnostic directory on clean exit / Удаляем авто-каталог при чистом выходе
  if [[ "${IO_PROCESS_CONFIG[auto_diag_dir]}" == "true" ]]; then
    utils::ignore rm -rf "${diag_dir}"
  fi

  IO_PROCESS_CURRENT_PID=""
  return "${cmd_rc}"
}
