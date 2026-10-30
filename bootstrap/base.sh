#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, printf, export; версия оболочки — из реестра bootstrap/shell.sh / valid POSIX sh: case, printf, export; the shell version comes from the registry bootstrap/shell.sh
# @tier core — builtins only; works everywhere
#
# bootstrap/base.sh — pre-kernel помощники на POSIX: строгий режим, ~/.local/bin в PATH, гейт версии
# bootstrap/base.sh — pre-kernel helpers in POSIX: strict mode, ~/.local/bin in PATH, the version gate
#
# ЗАЧЕМ / WHY
#   Это та часть бывшего bootstrap/bs.sh, которая не держится на bash: её подключают точки входа,
#   init.sh и загрузчик ДО ядра, в том числе в dash и ash. Часть, которая читает стек вызовов,
#   BASH_REMATCH и BASH_SOURCE, осталась в bootstrap/bs.sh (bash).
#   This is the part of the former bootstrap/bs.sh that does not depend on bash: the entry points,
#   init.sh and the loader source it BEFORE the kernel, in dash and ash too. The part that reads
#   the call stack, BASH_REMATCH and BASH_SOURCE stayed in bootstrap/bs.sh (bash).
#
# ИМЕНА / NAMES
#   Real functions: bs_strict, bs_append_local_bin_to_path, bs_shell_name, bs_shell_host,
#   bs_shell_version, bs_shell_ok, bs_shell_ensure_version; in bash and zsh also bs::strict,
#   bs::append_local_bin_to_path, bs::shell::name, bs::shell::host, bs::shell::version,
#   bs::shell::ok, bs::shell::ensure_version (the old names).
#   Настоящие функции: bs_strict, bs_append_local_bin_to_path, bs_shell_name, bs_shell_host,
#   bs_shell_version, bs_shell_ok, bs_shell_ensure_version; в bash и zsh — ещё и прежние имена.

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# Простой self-guard: bs_guard живёт в core/prereq.sh, который грузится позже этого файла
# A raw self-guard: bs_guard lives in core/prereq.sh, which loads after this file
case "${__BS_BASE_SOURCED:-}" in
  1) return 0 2>/dev/null ;;
esac
__BS_BASE_SOURCED=1

# POSIX-реестр оболочек (bootstrap/shell.sh): определение семейства, rc-файлы, строки PATH, tier.
# Каталог bootstrap/ задают init.sh и точки входа; запасной путь — от BS_ROOT / BS_ENTRY_DIR.
# The POSIX shell registry (bootstrap/shell.sh): family detection, rc files, PATH lines, tier.
# The bootstrap/ directory is set by init.sh and the entry points; fallback: from BS_ROOT / BS_ENTRY_DIR.
: "${BS_BOOTSTRAP_DIR:=${BS_ROOT:-${BS_ENTRY_DIR:-.}}/bootstrap}"
if [ -f "${BS_BOOTSTRAP_DIR}/shell.sh" ]; then
  # shellcheck disable=SC1091
  . "${BS_BOOTSTRAP_DIR}/shell.sh"
fi

# Строгий режим / Strict mode

# @description Enable strict mode (set -eu, pipefail where it exists) and a safe IFS.
# @description Включить строгий режим (set -eu, pipefail там, где он есть) и безопасный IFS.
# @description Pre-kernel equivalent of utils::strict (core/utils.sh): available BEFORE the loader
# @description runs, so entry points (bs, boot.sh) enable strict mode via a named helper.
# @description Pre-kernel аналог utils::strict (core/utils.sh): доступна ДО запуска loader'а,
# @description чтобы точки входа (bs, boot.sh) включали строгий режим именованной функцией.
# @note Entry points only, never inside library modules.
# @note Только в точках входа, никогда в библиотечных модулях.
bs_strict() {
  bs_shell_strict
}

# PATH / Local bin

# @description Prepend ~/.local/bin to PATH once (local installs).
# @description Добавить ~/.local/bin в PATH один раз (локальные установки).
bs_append_local_bin_to_path() {
  __bs_bs_needle="${HOME:-}/.local/bin"
  case ":${PATH}:" in
    *":${__bs_bs_needle}:"*) return 0 ;;
    *) export PATH="${__bs_bs_needle}:${PATH}" ;;
  esac
}

# Определение оболочки / Shell detection
#
# Определение — в реестре bootstrap/shell.sh (bs_shell_family и версии): это единственное место,
# знающее BASH_VERSION/ZSH_VERSION; здесь только обёртки.
# The detection lives in the registry bootstrap/shell.sh (bs_shell_family and the version
# functions): the only place that knows BASH_VERSION/ZSH_VERSION; only wrappers are here.

# @description Current shell name: bash, zsh, dash, ash, ksh, ... or unknown.
# @description Имя текущей оболочки: bash, zsh, dash, ash, ksh, ... или unknown.
# @stdout shell name / имя оболочки
bs_shell_name() {
  bs_shell_family
}

# @description Absolute path of the interpreter that runs this code (the host bash),
#   to start child shells in the SAME bash instead of whichever `bash` is first in PATH.
# @description Абсолютный путь интерпретатора, исполняющего этот код (host bash):
#   дочерние оболочки запускаются в ТОМ ЖЕ bash, а не в первом попавшемся в PATH.
# @stdout path / путь
bs_shell_host() {
  if bs_shell_host_ok && bs_shell_self_path 2>/dev/null; then
    return 0
  fi
  bs_shell_host_find 2>/dev/null || printf 'bash\n'
}

# @description Major shell version (bash: BASH_VERSINFO[0], zsh: ZSH_VERSION).
# @description Старшая версия оболочки (bash: BASH_VERSINFO[0], zsh: ZSH_VERSION).
# @stdout major version / старшая версия
bs_shell_version() {
  bs_shell_version_major
}

# @description Capability gate: bash 4.2+ = full kernel (0/1).
# @description Гейт возможностей: bash 4.2+ = полное ядро (0/1).
# @stdout 1 bash 4.2+, 0 otherwise / 1 для bash 4.2+, 0 иначе
bs_shell_ok() {
  if bs_shell_host_ok; then printf '1\n'; else printf '0\n'; fi
  return 0
}

# @description Gate: ensure the runtime shell meets a version requirement.
# @description Гейт: проверить, что текущая оболочка не старше требуемой версии.
# @description Checks the version of the running shell (bs_shell_version_*), not its kind;
# @description Проверяет версию работающей оболочки (bs_shell_version_*), а не её вид;
# @description silent on success, error to stderr on failure, never exits.
# @description молчит при успехе, ошибка в stderr при провале, не вызывает exit.
# @param $1 Required major version, default 4 / Требуемая старшая версия, по умолчанию 4
# @param $2 Required minor version, default 2 (framework needs bash 4.2+) / Требуемая младшая, по умолчанию 2
# @returns 0 version ok / версия подходит; 1 too old, not a number or undetectable / старая, не число или не определена
bs_shell_ensure_version() {
  __bs_bs_rmaj=${1:-4}
  __bs_bs_rmin=${2:-2}
  case "${__bs_bs_rmaj}${__bs_bs_rmin}" in
    *[!0-9]*)
      printf 'ERROR: ensure_version: required version must be numbers, got %s.%s\n' "$__bs_bs_rmaj" "$__bs_bs_rmin" >&2
      return 1 ;;
  esac
  __bs_bs_maj=$(bs_shell_version_major)
  __bs_bs_min=$(bs_shell_version_minor)
  if [ "$__bs_bs_maj" -lt "$__bs_bs_rmaj" ] \
     || { [ "$__bs_bs_maj" -eq "$__bs_bs_rmaj" ] && [ "$__bs_bs_min" -lt "$__bs_bs_rmin" ]; }; then
    printf 'ERROR: %s %s.%s+ required, found %s.%s\n' "$(bs_shell_family)" "$__bs_bs_rmaj" "$__bs_bs_rmin" "$__bs_bs_maj" "$__bs_bs_min" >&2
    return 1
  fi
  return 0
}

bs_shell_alias bs_strict bs::strict
bs_shell_alias bs_append_local_bin_to_path bs::append_local_bin_to_path
bs_shell_alias bs_shell_name bs::shell::name
bs_shell_alias bs_shell_host bs::shell::host
bs_shell_alias bs_shell_version bs::shell::version
bs_shell_alias bs_shell_ok bs::shell::ok
bs_shell_alias bs_shell_ensure_version bs::shell::ensure_version
