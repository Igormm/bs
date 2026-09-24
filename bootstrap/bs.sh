#!/usr/bin/env bash
#
# bootstrap/bs.sh — pre-kernel root namespace, available BEFORE the loader
# bootstrap/bs.sh — корневой namespace bs::, доступный ДО загрузки loader'а
# @tier core — pure Bash 4+, no GNU tools: works everywhere
# @tier core — чистый Bash 4+, без GNU-инструментов: работает везде
#
# This file has no dependencies and must stay bash-3.2-compatible (pure
# builtins, no associative arrays): it is sourced by entry points and by
# bootstrap/init.sh before the kernel (core/) loads, so the shell version
# gate can run on any interpreter the framework must reject.
# Файл не имеет зависимостей и обязан оставаться совместимым с bash 3.2
# (чистые builtins, без ассоциативных массивов): его подключают точки входа
# и bootstrap/init.sh до загрузки ядра (core/), чтобы гейт версии оболочки
# отработал на любом интерпретаторе, который фреймворк должен отклонить.

# Raw self-guard: bs::guard lives in core/prereq.sh, which is loaded via the
# loader — this file runs before that, so it cannot use it.
# Простой self-guard: bs::guard живёт в core/prereq.sh и грузится через
# loader — этот файл выполняется раньше, поэтому использовать её нельзя.
[[ -n "${__BS_SH_SOURCED:-}" ]] && return 0
readonly __BS_SH_SOURCED=1

# ==========================================
# PATH / Local bin
# ==========================================

# @description Prepend ~/.local/bin to PATH once (local installs).
# @description Добавить ~/.local/bin в PATH один раз (локальные установки).
bs::append_local_bin_to_path() {
  local -r needle="${HOME:-}/.local/bin"
  case ":${PATH}:" in
    *":${needle}:"*) return 0 ;;
    *) export PATH="${needle}:${PATH}" ;;
  esac
}

# ==========================================
# Script directory / Каталог скрипта
# ==========================================

# @description Print the absolute (physical) directory of the caller's file.
# @description Вывести абсолютный (физический) каталог файла вызывающего.
# @description Replaces the boilerplate: "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)".
# @description Заменяет шаблон: "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)".
# @param $1 Optional BASH_SOURCE index (default 1 = immediate caller).
# @param $1 Индекс BASH_SOURCE (по умолчанию 1 = непосредственный вызывающий).
# @stdout Absolute directory path (pwd -P).
# @stdout Абсолютный путь каталога (pwd -P).
# @returns 0 on success; 1 if the directory cannot be resolved.
# @returns 0 при успехе; 1, если каталог не удаётся определить.
bs::script_dir() {
  local -r idx="${1:-1}"
  (cd -- "$(dirname -- "${BASH_SOURCE[${idx}]}")" >/dev/null 2>&1 && pwd -P)
}

# ==========================================
# Shell detection / Определение оболочки
#
# Рантайм-определение через BASH_VERSION/ZSH_VERSION (а НЕ $SHELL — это
# логин-оболочка, она врёт при source из другой оболочки). Все хелперы —
# чистые builtins, доступны априори, до загрузки ядра.
# Runtime detection via BASH_VERSION/ZSH_VERSION (NOT $SHELL — that is the
# login shell and lies when sourcing from another shell). All helpers are
# pure builtins, available a priori, before the kernel loads.
# ==========================================

# @description Current shell name: bash/zsh/unknown.
# @description Имя текущей оболочки: bash/zsh/unknown.
# @stdout shell name / имя оболочки
bs::shell::name() {
  if [[ -n "${BASH_VERSION:-}" ]]; then
    printf 'bash\n'
  elif [[ -n "${ZSH_VERSION:-}" ]]; then
    printf 'zsh\n'
  else
    printf 'unknown\n'
  fi
  return 0
}

# @description Major shell version (bash: BASH_VERSINFO[0], zsh: ZSH_VERSION).
# @description Старшая версия оболочки (bash: BASH_VERSINFO[0], zsh: ZSH_VERSION).
# @stdout major version / старшая версия
bs::shell::version() {
  if [[ -n "${BASH_VERSION:-}" ]]; then
    printf '%s\n' "${BASH_VERSINFO[0]:-0}"
  elif [[ -n "${ZSH_VERSION:-}" ]]; then
    printf '%s\n' "${ZSH_VERSION%%.*}"
  else
    printf '0\n'
  fi
  return 0
}

# @description Capability gate: bash 4+ = full kernel (0/1).
# @description Гейт возможностей: bash 4+ = полное ядро (0/1).
# @stdout 1 bash 4+, 0 otherwise / 1 для bash 4+, 0 иначе
bs::shell::ok() {
  if [[ -n "${BASH_VERSION:-}" ]] && (( BASH_VERSINFO[0] >= 4 )); then
    printf '1\n'
  else
    printf '0\n'
  fi
  return 0
}

# @description Sourced vs executed for the DIRECT CALLER: 0 sourced, 1 executed.
# @description Source vs исполнение ПРЯМОГО ВЫЗЫВАЮЩЕГО: 0 при source, 1 при исполнении.
# bash: файл-вызывающий (BASH_SOURCE[1]) равен $0 только если он исполнен
# напрямую; при source $0 — имя оболочки/скрипта-хозяина. zsh: контекст
# исполнения через ZSH_EVAL_CONTEXT ($0 в zsh при source = имя файла).
# In bash the caller file (BASH_SOURCE[1]) equals $0 only when executed
# directly; when sourced, $0 is the host shell/script. zsh uses
# ZSH_EVAL_CONTEXT ($0 becomes the file name when sourced).
# @return 0 caller is sourced / вызывающий подключён через source; 1 executed
bs::shell::is_sourced() {
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    [[ "${ZSH_EVAL_CONTEXT}" != toplevel* ]]
    return $?
  fi
  [[ "${BASH_SOURCE[1]:-}" != "$0" ]]
  return $?
}

# @description Gate: ensure the runtime shell meets a major version requirement.
# @description Гейт: проверить, что текущая оболочка не старше требуемой версии.
# @description Runtime detection via BASH_VERSION/ZSH_VERSION (NOT $SHELL);
# @description Рантайм-детект через BASH_VERSION/ZSH_VERSION (не $SHELL);
# @description silent on success, error to stderr on failure, never exits.
# @description молчит при успехе, ошибка в stderr при провале, не вызывает exit.
# @arg $1 int Required major version, default 4.
# @arg $1 int Требуемая старшая версия, по умолчанию 4.
# @exitcode 0 version ok / версия подходит
# @exitcode 1 too old or undetectable / старая или не определена
bs::shell::ensure_version() {
  local -r required="${1:-4}"
  if ! [[ "${required}" =~ ^[0-9]+$ ]]; then
    printf 'ERROR: ensure_version: required version must be a number, got %s\n' "${required}" >&2
    return 1
  fi
  local name major
  name="$(bs::shell::name)"
  major="$(bs::shell::version)"
  if [[ "${name}" == "unknown" || "${major}" -lt "${required}" ]]; then
    printf 'ERROR: %s %s+ required, found %s\n' "${name}" "${required}" "${major}" >&2
    return 1
  fi
  return 0
}