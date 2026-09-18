#!/usr/bin/env bs
# shellcheck shell=bash
# lib/network/ssh.sh — remote Linux: run / push / pull / multiplex / check
# lib/network/ssh.sh — удалённый Linux: run / push / pull / multiplex / check

# @depends core/lang, core/const, core/utils, core/logger
# @tier core

# Source Guard
bs::guard "LIB_NETWORK_SSH" || return 0

# Dependencies
bs::source_relative "../../core/lang.sh" "../../core/const.sh" "../../core/utils.sh" "../../core/logger.sh"

# ==========================================
# Remote Linux over SSH / Удалённый Linux по SSH
#
# A clean layer over ssh/scp/rsync with exit-code propagation, a reusable
# ControlMaster connection (multiplex) and a host health battery.
# Test hook: SSH_MOCK=<script> replaces ssh; RSYNC_MOCK replaces rsync.
# Чистый слой поверх ssh/scp/rsync с пробросом кодов возврата,
# переиспользуемым соединением (multiplex) и батареей проверок хоста.
# Тестовый хук: SSH_MOCK=<скрипт> заменяет ssh; RSYNC_MOCK — rsync.
# ==========================================

# Socket directory for ControlMaster connections / Сокеты multiplex
# Default at load; callers MUST use the ${BS_SSH_SOCKET_DIR:-...} form —
# `unset` removes the variable entirely and set -u would abort otherwise.
: "${BS_SSH_SOCKET_DIR:=${XDG_RUNTIME_DIR:-/tmp}/bs-ssh}"

# Flag parser state (private) / Состояние разбора флагов (приватное)
__SSH_FLAG_HOST=""
__SSH_FLAG_USER=""
__SSH_FLAG_PORT=""
__SSH_FLAG_KEY=""
__SSH_FLAG_TIMEOUT="10"
declare -ga __SSH_FLAG_REST=()

# @private
# @description Parse shared flags: --user, --port, --key, --timeout, --.
# @description Разобрать общие флаги: --user, --port, --key, --timeout, --.
#   After `--` everything goes to __SSH_FLAG_REST (host + command verbatim).
#   После `--` всё уходит в __SSH_FLAG_REST (хост + команда дословно).
# @param $@ arguments / аргументы
# @return 0 ok, 1 unknown option
__ssh::parse_flags() {
  __SSH_FLAG_HOST=""
  __SSH_FLAG_USER=""
  __SSH_FLAG_PORT=""
  __SSH_FLAG_KEY=""
  __SSH_FLAG_TIMEOUT="10"
  __SSH_FLAG_REST=()

  local __pf_after_dd=0 __pf_val
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      --)
        __pf_after_dd=1
        shift ;;
      --user|--port|--key|--timeout)
        __pf_val="${2:?${1} requires a value}"
        case "${1}" in
          --user)    __SSH_FLAG_USER="${__pf_val}" ;;
          --port)    __SSH_FLAG_PORT="${__pf_val}" ;;
          --key)     __SSH_FLAG_KEY="${__pf_val}" ;;
          --timeout) __SSH_FLAG_TIMEOUT="${__pf_val}" ;;
        esac
        shift 2 ;;
      -*)
        if (( __pf_after_dd == 1 )); then
          __SSH_FLAG_REST+=("${1}")
          shift
        else
          log::error "ssh: unknown option: ${1}"
          return 1
        fi ;;
      *)
        if (( __pf_after_dd == 1 )) || is::not_empty "${__SSH_FLAG_HOST}"; then
          __SSH_FLAG_REST+=("${1}")
        else
          __SSH_FLAG_HOST="${1}"
        fi
        shift ;;
    esac
  done
  return 0
}

# @private
# @description ssh binary (mock hook) / бинарник ssh (хук-мок).
# @stdout binary path / путь к бинарнику
__ssh::binary() {
  printf '%s\n' "${SSH_MOCK:-ssh}"
}

# @private
# @description rsync binary (mock hook) / бинарник rsync (хук-мок).
# @stdout binary path / путь к бинарнику
__ssh::rsync_binary() {
  printf '%s\n' "${RSYNC_MOCK:-rsync}"
}

# @private
# @description Validate --port: digits only (blocks injection via rsync -e / ssh).
# @description Проверить --port: только цифры (блокирует инъекции через rsync -e / ssh).
# @param $1 port value / значение порта
# @return 0 ok, 1 invalid
__ssh::validate_port() {
  local -r __vp="${1:?port value required}"
  if [[ ! "${__vp}" =~ ^[0-9]+$ ]]; then
    log::error "ssh: invalid --port '${__vp}' (digits only)"
    return 1
  fi
  return 0
}

# @private
# @description Validate --key: no spaces/control chars, path must exist.
# @description Проверить --key: без пробелов/управляющих символов, путь должен существовать.
# @param $1 key path / путь к ключу
# @return 0 ok, 1 invalid
__ssh::validate_key() {
  local -r __vk="${1:?key path required}"
  if [[ "${__vk}" =~ [[:space:][:cntrl:]] ]]; then
    log::error "ssh: invalid --key '${__vk}' (no spaces or control characters)"
    return 1
  fi
  if ! is::file "${__vk}"; then
    log::error "ssh: --key file not found: ${__vk}"
    return 1
  fi
  return 0
}

# @private
# @description Build a safely-quoted ssh command for rsync -e.
# @description Собрать безопасно экранированную ssh-команду для rsync -e.
#   rsync executes the -e value with sh -c, so every element is quoted
#   with printf %q — user values can never become shell syntax.
#   rsync выполняет значение -e через sh -c, поэтому каждый элемент
#   экранируется через printf %q — значения пользователя не могут
#   превратиться в синтаксис shell.
# @param $1 port (validated) / порт (проверен)
# @param $2 key path (validated) / путь к ключу (проверен)
# @stdout the -e value / значение для -e
__ssh::rsh_cmd() {
  local __rc_port="${1:-}" __rc_key="${2:-}"
  local __rc_bin
  __rc_bin="$(__ssh::binary)"
  printf '%q' "${__rc_bin}"
  printf ' %q' -o BatchMode=yes
  printf ' %q' -o StrictHostKeyChecking=accept-new
  if is::not_empty "${__rc_port}"; then
    printf ' %q' -p "${__rc_port}"
  fi
  if is::not_empty "${__rc_key}"; then
    printf ' %q' -i "${__rc_key}"
  fi
  printf '\n'
}

# @description Run a command on a remote host; propagate the exit code.
# @description Выполнить команду на удалённом хосте; пробросить код возврата.
#   Flags: --user, --port, --key, --timeout. Everything after `--` is the
#   host + command verbatim (so command flags survive). BatchMode=yes.
#   Флаги: --user, --port, --key, --timeout. Всё после `--` — хост + команда
#   дословно (флаги команды не съедаются). BatchMode=yes.
# @param $@ [flags] -- [host] [command...] / хост и команда
# @stdout the remote command output / вывод удалённой команды
# @return the remote exit code / код возврата удалённой команды
# @example
#   if ssh::run --user root -- host "systemctl status app"; then
#     echo "app is running"
#   fi
#   ssh::run -- host "df -h /"
ssh::run() {
  __ssh::parse_flags "$@" || return 1
  # Хост может стоять и после -- (первый аргумент команды)
  # The host may also follow -- (the first command argument)
  local __sh_after_dd=0
  if is::empty "${__SSH_FLAG_HOST}" && (( ${#__SSH_FLAG_REST[@]} > 0 )); then
    __SSH_FLAG_HOST="${__SSH_FLAG_REST[0]}"
    __SSH_FLAG_REST=("${__SSH_FLAG_REST[@]:1}")
    __sh_after_dd=1
  fi
  is::not_empty "${__SSH_FLAG_HOST}" || {
    log::error "ssh::run: host required"
    return 1
  }

  # Строгая валидация флагов / Strict flag validation
  is::empty "${__SSH_FLAG_PORT}" || __ssh::validate_port "${__SSH_FLAG_PORT}" || return 1
  is::empty "${__SSH_FLAG_KEY}"  || __ssh::validate_key "${__SSH_FLAG_KEY}" || return 1

  # Инъекция опций: ssh разбирает ведущий '-' как опцию. --user обязан быть
  # обычным значением; хост — только если явно указан после '--' (тогда ssh
  # получает собственный '--' и значение остаётся хостом, а не опцией).
  # Option injection: ssh parses a leading '-' as an option. --user must be a
  # plain value; the host only when explicitly given after '--' (then ssh
  # receives its own '--' and the value stays a host, not an option).
  local __sh_dd_host=0
  if [[ "${__SSH_FLAG_USER}" == -* ]]; then
    log::error "ssh::run: --user must not start with '-'"
    return 1
  fi
  if [[ "${__SSH_FLAG_HOST}" == -* ]]; then
    if (( __sh_after_dd == 0 )); then
      log::error "ssh::run: host must not start with '-' (use -- for verbatim values)"
      return 1
    fi
    __sh_dd_host=1
  fi

  local __sh_target="${__SSH_FLAG_HOST}"
  if is::not_empty "${__SSH_FLAG_USER}"; then
    __sh_target="${__SSH_FLAG_USER}@${__SSH_FLAG_HOST}"
  fi

  local -a __sh_opts=(
    -o BatchMode=yes
    -o StrictHostKeyChecking=accept-new
    -o ConnectTimeout="${__SSH_FLAG_TIMEOUT}"
  )
  is::empty "${__SSH_FLAG_PORT}" || __sh_opts+=(-p "${__SSH_FLAG_PORT}")
  is::empty "${__SSH_FLAG_KEY}"  || __sh_opts+=(-i "${__SSH_FLAG_KEY}")

  # Переиспользование ControlMaster-соединения / ControlMaster reuse
  local __sh_sock="${BS_SSH_SOCKET_DIR:-${XDG_RUNTIME_DIR:-/tmp}/bs-ssh}/${__SSH_FLAG_HOST//\//_}.sock"
  [[ -S "${__sh_sock}" ]] && __sh_opts+=(-o "ControlPath=${__sh_sock}")

  # Хост после '--' с ведущим '-' передаётся ssh с собственным '--':
  # значение остаётся хостом (не опцией) — инъекция невозможна.
  # A host with a leading '-' after '--' goes to ssh with its own '--':
  # the value stays a host (not an option) — injection is impossible.
  (( __sh_dd_host == 1 )) && __sh_opts+=(--)

  local __sh_bin __sh_rc=0
  __sh_bin="$(__ssh::binary)"
  if (( ${#__SSH_FLAG_REST[@]} == 0 )); then
    "${__sh_bin}" "${__sh_opts[@]}" "${__sh_target}"
    __sh_rc=$?
  else
    "${__sh_bin}" "${__sh_opts[@]}" "${__sh_target}" "${__SSH_FLAG_REST[@]}"
    __sh_rc=$?
  fi
  return "${__sh_rc}"
}

# @description Push a local file/dir to a remote host (rsync, scp fallback).
# @description Отправить локальный файл/каталог на удалённый хост
#   (rsync, fallback scp). Remote format: user@host:/path.
# @param $1 Local path / Локальный путь
# @param $2 Remote destination / Удалённый путь назначения
# @param $@ [--delete] [--port P] [--key K]
# @return the transfer exit code / код возврата передачи
# @example
#   ssh::push ./deploy.sh root@server:/opt/app/
ssh::push() {
  local __sp_local="${1:?local path required}"
  local __sp_remote="${2:?remote destination required (user@host:/path)}"
  shift 2
  local __sp_delete=0 __sp_port="" __sp_key=""
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --delete) __sp_delete=1; shift ;;
      --port)   __sp_port="${2:?--port requires a value}"; shift 2 ;;
      --key)    __sp_key="${2:?--key requires a value}"; shift 2 ;;
      *) log::error "ssh::push: unknown option: ${1}"; return 1 ;;
    esac
  done

  # Валидация до shell-конкатенаций: rsync -e выполняется через sh -c
  # Validate before any shell concatenation: rsync -e is run via sh -c
  is::empty "${__sp_port}" || __ssh::validate_port "${__sp_port}" || return 1
  is::empty "${__sp_key}"  || __ssh::validate_key "${__sp_key}" || return 1

  # -e строится через printf %q — каждый элемент экранирован
  # -e is built with printf %q — every element is quoted
  local __sp_ssh_cmd
  __sp_ssh_cmd="$(__ssh::rsh_cmd "${__sp_port}" "${__sp_key}")"

  local __sp_bin
  __sp_bin="$(__ssh::rsync_binary)"
  local -a __sp_opts=(-az --timeout=30 -e "${__sp_ssh_cmd}")
  (( __sp_delete == 1 )) && __sp_opts+=(--delete)
  "${__sp_bin}" "${__sp_opts[@]}" "${__sp_local}" "${__sp_remote}"
}

# @description Pull a remote file/dir to the local machine.
# @description Забрать удалённый файл/каталог на локальную машину.
# @param $1 Remote source (user@host:/path) / Удалённый источник
# @param $2 Local destination / Локальный путь назначения
# @param $@ [--delete] [--port P] [--key K]
# @return the transfer exit code / код возврата передачи
# @example
#   ssh::pull root@server:/var/log/app.log ./logs/
ssh::pull() {
  local __sp_remote="${1:?remote source required (user@host:/path)}"
  local __sp_local="${2:?local destination required}"
  shift 2
  local __sp_delete=0 __sp_port="" __sp_key=""
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --delete) __sp_delete=1; shift ;;
      --port)   __sp_port="${2:?--port requires a value}"; shift 2 ;;
      --key)    __sp_key="${2:?--key requires a value}"; shift 2 ;;
      *) log::error "ssh::pull: unknown option: ${1}"; return 1 ;;
    esac
  done

  # Валидация до shell-конкатенаций: rsync -e выполняется через sh -c
  # Validate before any shell concatenation: rsync -e is run via sh -c
  is::empty "${__sp_port}" || __ssh::validate_port "${__sp_port}" || return 1
  is::empty "${__sp_key}"  || __ssh::validate_key "${__sp_key}" || return 1

  # -e строится через printf %q — каждый элемент экранирован
  # -e is built with printf %q — every element is quoted
  local __sp_ssh_cmd
  __sp_ssh_cmd="$(__ssh::rsh_cmd "${__sp_port}" "${__sp_key}")"

  local __sp_bin
  __sp_bin="$(__ssh::rsync_binary)"
  local -a __sp_opts=(-az --timeout=30 -e "${__sp_ssh_cmd}")
  (( __sp_delete == 1 )) && __sp_opts+=(--delete)
  "${__sp_bin}" "${__sp_opts[@]}" "${__sp_remote}" "${__sp_local}"
}

# @description Open a persistent ControlMaster connection to a host.
# @description Открыть постоянное ControlMaster-соединение с хостом.
#   Subsequent ssh::run calls reuse it automatically (socket per host).
#   Последующие ssh::run переиспользуют его автоматически (сокет на хост).
# @param $@ same flags/host as ssh::run / как у ssh::run
# @return 0 ok
# @example
#   ssh::multiplex root@build01
#   ssh::run -- root@build01 "make -j"    # reuses the socket
#   ssh::multiplex_close root@build01
ssh::multiplex() {
  __ssh::parse_flags "$@" || return 1
  if is::empty "${__SSH_FLAG_HOST}" && (( ${#__SSH_FLAG_REST[@]} > 0 )); then
    __SSH_FLAG_HOST="${__SSH_FLAG_REST[0]}"
    __SSH_FLAG_REST=("${__SSH_FLAG_REST[@]:1}")
  fi
  is::not_empty "${__SSH_FLAG_HOST}" || {
    log::error "ssh::multiplex: host required"
    return 1
  }

  local __sm_target="${__SSH_FLAG_HOST}"
  if is::not_empty "${__SSH_FLAG_USER}"; then
    __sm_target="${__SSH_FLAG_USER}@${__SSH_FLAG_HOST}"
  fi
  local __sm_sock="${BS_SSH_SOCKET_DIR:-${XDG_RUNTIME_DIR:-/tmp}/bs-ssh}/${__SSH_FLAG_HOST//\//_}.sock"
  if [[ -S "${__sm_sock}" ]]; then
    log::debug "multiplex: socket exists, reusing: ${__sm_sock}"
    return 0
  fi

  mkdir -p "${BS_SSH_SOCKET_DIR:-${XDG_RUNTIME_DIR:-/tmp}/bs-ssh}"
  local __sm_bin
  __sm_bin="$(__ssh::binary)"
  (
    "${__sm_bin}" -M \
      -o ControlMaster=yes \
      -o ControlPersist=300 \
      -o "ControlPath=${__sm_sock}" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=accept-new \
      "${__sm_target}" sleep 1000
  ) >/dev/null 2>&1 &
  disown 2>/dev/null || :
  log::info "multiplex: ControlMaster opened for ${__sm_target}"
  return 0
}

# @description Close the ControlMaster connection to a host.
# @description Закрыть ControlMaster-соединение с хостом.
# @param $@ same flags/host as ssh::run / как у ssh::run
# @return 0 ok
# @example
#   ssh::multiplex_close root@build01
ssh::multiplex_close() {
  __ssh::parse_flags "$@" || return 1
  is::not_empty "${__SSH_FLAG_HOST}" || return 1

  local __sm_target="${__SSH_FLAG_HOST}"
  if is::not_empty "${__SSH_FLAG_USER}"; then
    __sm_target="${__SSH_FLAG_USER}@${__SSH_FLAG_HOST}"
  fi
  local __sm_sock="${BS_SSH_SOCKET_DIR:-${XDG_RUNTIME_DIR:-/tmp}/bs-ssh}/${__SSH_FLAG_HOST//\//_}.sock"
  # Живой ControlMaster — только сокет; обычный файл на этом пути (остаток
  # после падения) не должен ронять set -e вызывающего.
  # A live ControlMaster is a socket only; a leftover regular file at this
  # path must not kill a set -e caller.
  if [[ ! -S "${__sm_sock}" ]]; then
    log::warn "multiplex: no live socket for ${__SSH_FLAG_HOST}, nothing to close"
    return 0
  fi
  local __sm_bin
  __sm_bin="$(__ssh::binary)"
  if ! utils::quiet "${__sm_bin}" -O exit -o "ControlPath=${__sm_sock}" "${__sm_target}"; then
    log::warn "multiplex: failed to close ControlMaster for ${__SSH_FLAG_HOST}"
    return 0
  fi
  return 0
}

# @description Host health battery: connectivity, OS, disk, sudo.
# @description Батарея проверок хоста: связь, ОС, диск, sudo.
# @param $@ same flags/host as ssh::run / как у ssh::run
# @stdout check results / результаты проверок
# @return 0 healthy, 1 connectivity or OS probe failed
# @example
#   if ssh::check --user root -- host db01; then ...
ssh::check() {
  __ssh::parse_flags "$@" || return 1
  if is::empty "${__SSH_FLAG_HOST}" && (( ${#__SSH_FLAG_REST[@]} > 0 )); then
    __SSH_FLAG_HOST="${__SSH_FLAG_REST[0]}"
    __SSH_FLAG_REST=("${__SSH_FLAG_REST[@]:1}")
  fi
  is::not_empty "${__SSH_FLAG_HOST}" || {
    log::error "ssh::check: host required"
    return 1
  }

  local -a __sc_opts=()
  is::empty "${__SSH_FLAG_USER}"    || __sc_opts+=(--user "${__SSH_FLAG_USER}")
  is::empty "${__SSH_FLAG_PORT}"    || __sc_opts+=(--port "${__SSH_FLAG_PORT}")
  is::empty "${__SSH_FLAG_KEY}"     || __sc_opts+=(--key "${__SSH_FLAG_KEY}")
  is::empty "${__SSH_FLAG_TIMEOUT}" || __sc_opts+=(--timeout "${__SSH_FLAG_TIMEOUT}")

  local __sc_out __sc_rc=0
  local -i __sc_fails=0

  # 1. Базовая связь / Basic connectivity
  if __sc_out="$(ssh::run "${__sc_opts[@]}" -- "${__SSH_FLAG_HOST}" "echo bs-check-ok" 2>/dev/null)"; then
    printf '  [OK] connectivity\n'
  else
    printf '  [FAIL] connectivity\n'
    __sc_fails=1
  fi

  # 2. ОС и ядро / OS and kernel
  if __sc_out="$(ssh::run "${__sc_opts[@]}" -- "${__SSH_FLAG_HOST}" "uname -srm" 2>/dev/null)"; then
    printf '  [OK] os: %s\n' "$(printf '%s\n' "${__sc_out}" | head -n1)"
  else
    printf '  [FAIL] os probe\n'
    __sc_fails=1
  fi

  # 3. Диск / / Disk usage
  if __sc_out="$(ssh::run "${__sc_opts[@]}" -- "${__SSH_FLAG_HOST}" "df -h / | tail -n1" 2>/dev/null)"; then
    printf '  [OK] disk /: %s used\n' "$(printf '%s\n' "${__sc_out}" | awk '{print $5}' | tail -n1)"
  else
    printf '  [WARN] disk probe failed\n'
  fi

  # 4. Passwordless sudo / Sudo без пароля
  if __sc_out="$(ssh::run "${__sc_opts[@]}" -- "${__SSH_FLAG_HOST}" "sudo -n true 2>/dev/null && echo sudo-ok" 2>/dev/null)"; then
    if [[ "${__sc_out}" == *sudo-ok* ]]; then
      printf '  [OK] sudo: passwordless\n'
    else
      printf '  [WARN] sudo: requires password\n'
    fi
  else
    printf '  [WARN] sudo probe failed\n'
  fi

  if (( __sc_fails == 0 )); then
    printf '%s: healthy\n' "${__SSH_FLAG_HOST}"
    return 0
  fi
  printf '%s: unhealthy\n' "${__SSH_FLAG_HOST}"
  return 1
}