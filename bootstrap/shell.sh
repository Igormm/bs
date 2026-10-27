#!/bin/sh
# shellcheck shell=sh
#
# bootstrap/shell.sh — POSIX shell registry: who runs, who the user is, what
# each shell needs (rc file, PATH line, reload command) and how well BS works
# in it (tier)
# bootstrap/shell.sh — POSIX-реестр оболочек: кто исполняет код, какая
# оболочка у пользователя, что нужно каждой (rc-файл, строка PATH, команда
# перезагрузки) и насколько хорошо в ней работает BS (tier)
#
# @shell posix — valid POSIX sh: can be sourced by dash, ash/busybox, bash,
# @shell posix — zsh, ksh; no arrays, no [[ ]], no "::" in function names
# @shell posix — валидный POSIX sh: подключается из dash, ash/busybox, bash,
# @shell posix — zsh, ksh; без массивов, без [[ ]], без "::" в именах функций
# @tier core — builtins plus readlink/ps/getent when present; works everywhere
# @tier core — builtin'ы плюс readlink/ps/getent, если есть; работает везде
#
# WHY A SEPARATE POSIX FILE / ЗАЧЕМ ОТДЕЛЬНЫЙ POSIX-ФАЙЛ
#   The BS kernel is bash 4.2+ code. This file is the part that must work in
#   ANY Bourne-family shell, because it decides what to do when the shell is
#   not bash (see bootstrap/trampoline.sh) and tells the installer how to set
#   PATH up for the user's own shell (bash, zsh, ash/dash, ksh, fish, nushell).
#   Ядро BS — код для bash 4.2+. Этот файл обязан работать в ЛЮБОЙ оболочке
#   семейства Bourne: он решает, что делать, когда оболочка не bash (см.
#   bootstrap/trampoline.sh), и подсказывает установщику, как настроить PATH
#   под собственную оболочку пользователя (bash, zsh, ash/dash, ksh, fish, nu).
#
# NAMING / ИМЕНА
#   Real functions are bs_shell_* (valid identifiers: dash rejects "a::b").
#   In bash and zsh the same functions are also available as bs::shell::*.
#   Настоящие функции — bs_shell_* (dash не принимает "a::b"). В bash и zsh
#   те же функции доступны и как bs::shell::*.

# Повторное подключение безвредно / sourcing twice is harmless
case "${__BS_SHELL_SOURCED:-}" in
  1) return 0 2>/dev/null ;;
esac
__BS_SHELL_SOURCED=1

# Идемпотентность: файл подключают пролог точки входа, трамплин и bs.sh
# Idempotent: sourced by the entry-point prologue, the trampoline and bs.sh
[ -z "${__BS_SHELL_SH:-}" ] || return 0
__BS_SHELL_SH=1

# ==========================================
# Names / Имена
# ==========================================

# @description Canonical family of a shell name or path.
# @description Каноническое семейство оболочки по имени или пути.
# @param $1 Name or path, e.g. -bash, /usr/bin/zsh, busybox / Имя или путь
# @stdout bash|zsh|dash|ash|sh|ksh|mksh|oksh|osh|fish|nu|unknown
bs_shell_of_name() {
  __bs_n=${1:-}
  __bs_n=${__bs_n##*/}
  __bs_n=${__bs_n#-}
  case "$__bs_n" in
    bash|rbash|bash-*|bash[0-9]*) printf 'bash\n' ;;
    zsh|zsh-*|zsh[0-9]*)          printf 'zsh\n' ;;
    dash)                         printf 'dash\n' ;;
    ash|busybox|hush)             printf 'ash\n' ;;
    sh)                           printf 'sh\n' ;;
    mksh)                         printf 'mksh\n' ;;
    oksh)                         printf 'oksh\n' ;;
    ksh|ksh93|ksh88|pdksh|lksh|ksh[0-9]*) printf 'ksh\n' ;;
    osh|ysh|oils|oils-for-unix)   printf 'osh\n' ;;
    fish)                         printf 'fish\n' ;;
    nu|nushell)                   printf 'nu\n' ;;
    *)                            printf 'unknown\n' ;;
  esac
}

# @description Family of the process with the given pid, from the kernel.
# @description Семейство процесса по pid — по данным ядра.
# @param $1 pid
# @stdout family / семейство
bs_shell__proc_family() {
  __bs_pn=''
  if [ -r "/proc/$1/exe" ]; then
    __bs_pn=$(readlink "/proc/$1/exe" 2>/dev/null)
    __bs_pn=${__bs_pn##*/}
  fi
  if [ -z "$__bs_pn" ] && [ -r "/proc/$1/comm" ]; then
    read -r __bs_pn < "/proc/$1/comm" 2>/dev/null || __bs_pn=''
  fi
  if [ -z "$__bs_pn" ]; then
    __bs_pn=$(ps -p "$1" -o comm= 2>/dev/null)
    __bs_pn=${__bs_pn##*/}
  fi
  bs_shell_of_name "$__bs_pn"
}

# ==========================================
# Detection / Определение
# ==========================================

# @description Family of the interpreter that runs THIS code (not $SHELL).
# @description Семейство интерпретатора, исполняющего ЭТОТ код (не $SHELL).
# @stdout family / семейство
bs_shell_family() {
  # Oils притворяется bash (BASH_VERSION задан) — проверяем его первым
  # Oils pretends to be bash (BASH_VERSION is set) — it is checked first
  if [ -n "${OILS_VERSION:-}${OIL_VERSION:-}" ]; then
    printf 'osh\n'
  elif [ -n "${BASH_VERSION:-}" ]; then
    printf 'bash\n'
  elif [ -n "${ZSH_VERSION:-}" ]; then
    printf 'zsh\n'
  elif [ -n "${KSH_VERSION:-}" ]; then
    case "$KSH_VERSION" in
      *MIRBSD*)    printf 'mksh\n' ;;
      *"PD KSH"*)  printf 'oksh\n' ;;
      *)           printf 'ksh\n' ;;
    esac
  else
    bs_shell__proc_family "$$"
  fi
}

# @description Login shell family: of a user (getent) or of $SHELL.
# @description Семейство логин-оболочки: пользователя (getent) или $SHELL.
# @param $1 Optional user name / Необязательное имя пользователя
# @stdout family / семейство
bs_shell_login() {
  bs_shell_of_name "$(bs_shell_login_path "${1:-}")"
}

# @description Path of the login shell binary: of the given user (getent), else
#   the one the environment names.
# @description Путь к бинарнику логин-оболочки: заданного пользователя (getent),
#   иначе названной окружением.
# @param $1 user name (optional) / имя пользователя (необязательно)
# @stdout path / путь
bs_shell_login_path() {
  __bs_lp=''
  if [ -n "${1:-}" ] && command -v getent >/dev/null 2>&1; then
    __bs_lp=$(getent passwd "$1" 2>/dev/null | cut -d: -f7)
  fi
  [ -n "$__bs_lp" ] || __bs_lp=${SHELL:-}
  printf '%s\n' "$__bs_lp"
}

# @description Family of the parent process (the shell the user typed in).
# @description Семейство родительского процесса (оболочки, где набрана команда).
# @stdout family / семейство
bs_shell_parent() {
  bs_shell__proc_family "${PPID:-0}"
}

# @description The USER's shell — the one whose rc files must be edited.
#   Order: BS_USER_SHELL override, the parent process, the login shell (of
#   SUDO_USER under sudo), else bash.
# @description Оболочка ПОЛЬЗОВАТЕЛЯ — чьи rc-файлы нужно править. Порядок:
#   BS_USER_SHELL, родительский процесс, логин-оболочка (SUDO_USER под sudo),
#   иначе bash.
# @stdout family / семейство
bs_shell_user() {
  if [ -n "${BS_USER_SHELL:-}" ]; then
    __bs_us=$(bs_shell_of_name "$BS_USER_SHELL")
    if [ "$__bs_us" != unknown ]; then
      printf '%s\n' "$__bs_us"
      return 0
    fi
  fi
  __bs_us=$(bs_shell_parent)
  case "$__bs_us" in
    unknown|sh) ;;
    *) printf '%s\n' "$__bs_us"; return 0 ;;
  esac
  __bs_who=''
  if [ "$(id -u 2>/dev/null)" = 0 ] && [ -n "${SUDO_USER:-}" ]; then
    __bs_who=$SUDO_USER
  fi
  __bs_us=$(bs_shell_login "$__bs_who")
  case "$__bs_us" in
    unknown) printf 'bash\n' ;;
    *)       printf '%s\n' "$__bs_us" ;;
  esac
}

# ==========================================
# Registry: rc files, PATH line, reload / Реестр
# ==========================================

# @description The rc file where the PATH line for a family goes.
# @description rc-файл, куда идёт строка PATH для семейства.
# @param $1 family / семейство
# @stdout absolute path / абсолютный путь
# @return 1 for a family without a known rc file / 1 для неизвестного семейства
bs_shell_rc_file() {
  case "${1:-}" in
    bash)                        printf '%s\n' "${HOME:-}/.bashrc" ;;
    zsh)                         printf '%s\n' "${ZDOTDIR:-${HOME:-}}/.zshrc" ;;
    dash|ash|sh|ksh|mksh|oksh)   printf '%s\n' "${HOME:-}/.profile" ;;
    osh)                         printf '%s\n' "${HOME:-}/.config/oils/oshrc" ;;
    fish) printf '%s\n' "${XDG_CONFIG_HOME:-${HOME:-}/.config}/fish/conf.d/bs.fish" ;;
    nu)   printf '%s\n' "${XDG_CONFIG_HOME:-${HOME:-}/.config}/nushell/env.nu" ;;
    *) return 1 ;;
  esac
}

# @description Files that may carry BS traces for a family (user and system).
# @description Файлы, где могут быть следы BS для семейства (пользовательские и системные).
# @param $1 family / семейство
# @stdout one path per line / по пути в строке
bs_shell_rc_scan() {
  __bs_h=${HOME:-}
  __bs_x=${XDG_CONFIG_HOME:-$__bs_h/.config}
  case "${1:-}" in
    bash) printf '%s\n' "$__bs_h/.bashrc" "$__bs_h/.bash_profile" "$__bs_h/.bash_login" \
            "$__bs_h/.profile" /etc/profile /etc/bash.bashrc /etc/bashrc ;;
    zsh)  printf '%s\n' "${ZDOTDIR:-$__bs_h}/.zshrc" "${ZDOTDIR:-$__bs_h}/.zprofile" \
            "${ZDOTDIR:-$__bs_h}/.zshenv" "${ZDOTDIR:-$__bs_h}/.zlogin" \
            /etc/zshrc /etc/zsh/zshrc /etc/zsh/zshenv /etc/zprofile ;;
    dash|ash|sh) printf '%s\n' "$__bs_h/.profile" /etc/profile ;;
    ksh|mksh|oksh) printf '%s\n' "$__bs_h/.profile" "$__bs_h/.kshrc" "$__bs_h/.mkshrc" /etc/profile ;;
    osh)  printf '%s\n' "$__bs_h/.config/oils/oshrc" "$__bs_h/.oshrc" ;;
    fish) printf '%s\n' "$__bs_x/fish/config.fish" "$__bs_x/fish/conf.d/bs.fish" ;;
    nu)   printf '%s\n' "$__bs_x/nushell/env.nu" "$__bs_x/nushell/config.nu" ;;
    *) return 1 ;;
  esac
}

# @description Every rc file of every known family (duplicates removed).
# @description Все rc-файлы всех известных семейств (без повторов).
# @stdout one path per line / по пути в строке
bs_shell_all_rc_files() {
  for __bs_fa in bash zsh sh ksh osh fish nu; do
    bs_shell_rc_scan "$__bs_fa"
  done | awk '!seen[$0]++'
}

# @description The exact line that adds a directory to PATH, in the syntax of
#   the family. Installer and uninstaller use the same text (exact match).
# @description Точная строка, добавляющая каталог в PATH, в синтаксисе
#   семейства. Установщик и удаление используют один и тот же текст.
# @param $1 family / семейство
# @param $2 directory; $HOME/... is kept literal / каталог; $HOME/... остаётся буквальным
# @stdout the line / строка
# shellcheck disable=SC2016  # $HOME и $PATH в выводе намеренно буквальные
bs_shell_path_line() {
  __bs_pf=${1:-}
  __bs_pd=${2:-}
  case "$__bs_pf" in
    nu)
      case "$__bs_pd" in
        '$HOME/'*)
          __bs_rest=${__bs_pd#'$HOME/'}
          __bs_segs=''
          while [ -n "$__bs_rest" ]; do
            __bs_seg=${__bs_rest%%/*}
            case "$__bs_rest" in
              */*) __bs_rest=${__bs_rest#*/} ;;
              *)   __bs_rest='' ;;
            esac
            [ -z "$__bs_seg" ] || __bs_segs="$__bs_segs \"$__bs_seg\""
          done
          printf '%s\n' "\$env.PATH = (\$env.PATH | prepend (\$env.HOME | path join$__bs_segs) | uniq)" ;;
        *)
          printf '%s\n' "\$env.PATH = (\$env.PATH | prepend \"$__bs_pd\" | uniq)" ;;
      esac ;;
    fish)
      printf '%s\n' "contains -- \"$__bs_pd\" \$PATH; or set -gx PATH \"$__bs_pd\" \$PATH" ;;
    *)
      printf '%s\n' "export PATH=\"$__bs_pd:\$PATH\"" ;;
  esac
}

# @description The command that applies the rc file in the CURRENT terminal.
# @description Команда, применяющая rc-файл в ТЕКУЩЕМ терминале.
# @param $1 family / семейство
# @stdout command / команда
bs_shell_reload_hint() {
  case "${1:-}" in
    bash)                      printf 'source ~/.bashrc\n' ;;
    zsh)                       printf 'source ~/.zshrc\n' ;;
    dash|ash|sh|ksh|mksh|oksh) printf '. ~/.profile\n' ;;
    osh)                       printf 'source ~/.config/oils/oshrc\n' ;;
    fish)                      printf 'source ~/.config/fish/conf.d/bs.fish\n' ;;
    nu)                        printf 'exec nu\n' ;;
    *)                         printf 'open a new terminal\n' ;;
  esac
}

# @description Flags that make a fresh interactive shell read the PATH file.
# @description Флаги, чтобы новая интерактивная оболочка прочитала файл с PATH.
# @param $1 family / семейство
# @stdout flags or nothing / флаги или пусто
bs_shell_fresh_flags() {
  case "${1:-}" in
    dash|ash|sh|ksh|mksh|oksh) printf '%s\n' '-l' ;;
    *) : ;;
  esac
}

# @description Does the family have a registry entry (rc file, PATH syntax)?
# @description Есть ли у семейства запись в реестре (rc-файл, синтаксис PATH)?
# @param $1 family / семейство
# @return 0 known, 1 unknown / 0 известно, 1 нет
bs_shell_known() {
  case "${1:-}" in
    bash|zsh|dash|ash|sh|ksh|mksh|oksh|osh|fish|nu) return 0 ;;
    *) return 1 ;;
  esac
}

# ==========================================
# Host and tier / Хозяин и tier
# ==========================================

# @description Strict mode for an entry point, in every shell: errexit, nounset, pipefail
#   where the shell has it (bash, zsh, busybox ash; not dash), IFS = newline + tab.
#   Entry points only, never inside library modules.
# @description Строгий режим точки входа в любой оболочке: errexit, nounset, pipefail
#   там, где он есть (bash, zsh, busybox ash; в dash нет), IFS = перевод строки + табуляция.
#   Только в точках входа, никогда в библиотечных модулях.
bs_shell_strict() {
  set -eu
  # pipefail есть не везде: имя опции в переменной, проверка в подоболочке — dash не пострадает
  # pipefail is not everywhere: the option name is in a variable, probed in a subshell — dash is not hurt
  __bs_pf=pipefail
  if (set -o "$__bs_pf") 2>/dev/null; then
    set -o "$__bs_pf"
  fi
  IFS=$(printf '\n\t')
}

# @description Absolute path of the interpreter running this code.
# @description Абсолютный путь интерпретатора, исполняющего этот код.
# @stdout path / путь
bs_shell_self_path() {
  case $(bs_shell_family) in
    bash) if [ -n "${BASH:-}" ] && [ -x "${BASH}" ]; then printf '%s\n' "${BASH}"; return 0; fi ;;
  esac
  __bs_sp=$(readlink "/proc/$$/exe" 2>/dev/null) || __bs_sp=''
  if [ -n "$__bs_sp" ] && [ -x "$__bs_sp" ]; then
    printf '%s\n' "$__bs_sp"
  else
    return 1
  fi
}

# @description Can BS be sourced as a library from this shell family? (only bash:
#   BS is bash code; other shells use the `bs` command)
# @description Можно ли подключить BS как библиотеку (source) из этого семейства?
#   (только bash: BS — код на bash; остальные работают командой `bs`)
# @param $1 family / семейство
# @return 0 yes, 1 no / 0 да, 1 нет
bs_shell_can_source() {
  [ "${1:-}" = bash ]
}

# @description May the installer create the rc file of this family from scratch?
#   nushell: no — a bare env.nu would keep nu from creating its own configuration.
# @description Может ли установщик создать rc-файл этого семейства с нуля?
#   nushell: нет — «голый» env.nu помешал бы nu создать собственную конфигурацию.
# @param $1 family / семейство
# @return 0 yes, 1 no / 0 да, 1 нет
bs_shell_rc_create_ok() {
  [ "${1:-}" != nu ]
}

# @description Default login shell for a new account: the one the environment
#   names if it is listed in /etc/shells, else /bin/sh.
# @description Оболочка по умолчанию для новой учётной записи: названная окружением,
#   если она есть в /etc/shells, иначе /bin/sh.
# @stdout path / путь
bs_shell_default_login_path() {
  __bs_dl=$(bs_shell_login_path)
  if [ -n "$__bs_dl" ] && [ -x "$__bs_dl" ] && grep -qxF "$__bs_dl" /etc/shells 2>/dev/null; then
    printf '%s\n' "$__bs_dl"
  else
    printf '/bin/sh\n'
  fi
}

# @description Version string of the running shell (the one variable that holds it:
#   BASH_VERSION, ZSH_VERSION, KSH_VERSION, OILS_VERSION); "unknown" if none.
# @description Строка версии работающей оболочки (единственное место, знающее
#   BASH_VERSION, ZSH_VERSION, KSH_VERSION, OILS_VERSION); «unknown», если нет.
# @stdout version / версия
bs_shell_version_string() {
  case $(bs_shell_family) in
    osh)   printf '%s\n' "${OILS_VERSION:-${OIL_VERSION:-unknown}}" ;;
    bash)  printf '%s\n' "${BASH_VERSION:-unknown}" ;;
    zsh)   printf '%s\n' "${ZSH_VERSION:-unknown}" ;;
    ksh|mksh|oksh) printf '%s\n' "${KSH_VERSION:-unknown}" ;;
    *)     printf 'unknown\n' ;;
  esac
}

# @description Major version of the running shell (0 if unknown).
# @description Старшая версия работающей оболочки (0, если неизвестна).
# @stdout number / число
bs_shell_version_major() {
  __bs_vs=$(bs_shell_version_string)
  __bs_vs=${__bs_vs%%[!0-9.]*}
  case $__bs_vs in
    [0-9]*) printf '%s\n' "${__bs_vs%%.*}" ;;
    *)      printf '0\n' ;;
  esac
}

# @description Minor version of the running shell (0 if unknown).
# @description Младшая версия работающей оболочки (0, если неизвестна).
# @stdout number / число
bs_shell_version_minor() {
  __bs_vs=$(bs_shell_version_string)
  __bs_vs=${__bs_vs%%[!0-9.]*}
  case $__bs_vs in
    [0-9]*.[0-9]*) __bs_vr=${__bs_vs#*.}; printf '%s\n' "${__bs_vr%%.*}" ;;
    *)             printf '0\n' ;;
  esac
}

# @description Is the interpreter running THIS code a capable host (bash 4.2+)?
# @description Годится ли интерпретатор, исполняющий ЭТОТ код, в хозяева (bash 4.2+)?
# @return 0 yes, 1 no / 0 да, 1 нет
bs_shell_host_ok() {
  [ "$(bs_shell_family)" = bash ] || return 1
  # shellcheck disable=SC3028  # SHELLOPTS есть в bash / exists in bash
  # shellcheck disable=SC3028  # SHELLOPTS есть только в bash; ветка выполняется только там / SHELLOPTS exists only in bash; the branch runs only there
  case ":${SHELLOPTS:-}:" in *:posix:*) return 1 ;; esac
  __bs_hmaj=$(bs_shell_version_major)
  __bs_hmin=$(bs_shell_version_minor)
  [ "$__bs_hmaj" -gt 4 ] && return 0
  [ "$__bs_hmaj" -eq 4 ] && [ "$__bs_hmin" -ge 2 ]
}

# @description Is the given executable a bash 4.2+? (it is asked, not assumed)
# @description Это bash 4.2+? (исполняемый файл опрашивается, а не предполагается)
# @param $1 path / путь
# @return 0 yes, 1 no / 0 да, 1 нет
# shellcheck disable=SC2016  # скрипт для -c разбирает дочерний bash
bs_shell__bash_ok() {
  [ -x "$1" ] || return 1
  # Версию спрашиваем у самого кандидата и сверяем напечатанное: двоичный файл, который
  # игнорирует -c и просто выходит с 0 (например /bin/true), bash 4.2+ не считается.
  # We ask the candidate itself and check what it printed: a binary that ignores -c and just
  # exits 0 (for example /bin/true) is not a bash 4.2+.
  __bs_bv=$("$1" -c 'printf "%s.%s" "${BASH_VERSINFO[0]:-0}" "${BASH_VERSINFO[1]:-0}"' 2>/dev/null) || return 1
  case "$__bs_bv" in
    [0-9]*.[0-9]*) ;;
    *) return 1 ;;
  esac
  __bs_bmaj=${__bs_bv%%.*}
  __bs_bmin=${__bs_bv#*.}
  [ "$__bs_bmaj" -gt 4 ] && return 0
  [ "$__bs_bmaj" -eq 4 ] && [ "$__bs_bmin" -ge 2 ]
}

# @description Find a bash 4.2+ on this machine: BS_HOST_BASH (authoritative
#   when set), then PATH and the usual places.
# @description Найти bash 4.2+ на машине: BS_HOST_BASH (главнее всего, если
#   задан), затем PATH и привычные места.
# @stdout path / путь
# @return 0 found, 1 not found / 0 найден, 1 нет
bs_shell_host_find() {
  if [ -n "${BS_HOST_BASH:-}" ]; then
    if bs_shell__bash_ok "$BS_HOST_BASH"; then
      printf '%s\n' "$BS_HOST_BASH"
      return 0
    fi
    return 1
  fi
  __bs_hc=$(command -v bash 2>/dev/null)
  for __bs_hc in "$__bs_hc" /usr/local/bin/bash /opt/homebrew/bin/bash \
      /opt/local/bin/bash /usr/pkg/bin/bash /usr/bin/bash /bin/bash; do
    if [ -n "$__bs_hc" ] && bs_shell__bash_ok "$__bs_hc"; then
      printf '%s\n' "$__bs_hc"
      return 0
    fi
  done
  return 1
}

# @description Tier of BS for a user shell:
#   native      - the shell is bash 4.2+: library (source) and commands work;
#   hosted      - another shell: BS runs as the command `bs`, executed by a
#                 bash 4.2+ found on the machine; PATH/rc/hints fit that shell;
#   unsupported - no bash 4.2+ on the machine: BS cannot run at all.
# @description Tier BS для оболочки пользователя: native / hosted / unsupported.
# @param $1 family; default: the user's shell / семейство; по умолчанию — оболочка пользователя
# @stdout native|hosted|unsupported
bs_shell_tier() {
  __bs_tf=${1:-}
  [ -n "$__bs_tf" ] || __bs_tf=$(bs_shell_user)
  if [ "$__bs_tf" = bash ] && bs_shell_host_ok; then
    printf 'native\n'
  elif bs_shell_host_find >/dev/null 2>&1; then
    printf 'hosted\n'
  else
    printf 'unsupported\n'
  fi
}

# @description Can bootstrap/cli.sh serve this command in any POSIX shell,
#   without the bash layer? The trampoline asks this before looking for bash,
#   so a POSIX command does not pay for a bash re-exec.
# @description Может ли bootstrap/cli.sh обслужить эту команду в любой
#   POSIX-оболочке, без bash-слоя? Трамплин спрашивает это до поиска bash,
#   поэтому POSIX-команда не платит за перезапуск в bash.
# @param $@ command and its arguments / команда и её аргументы
# @return 0 yes, 1 no / 0 да, 1 нет
bs_shell_posix_command() {
  __bs_pc_cmd=${1:-help}
  if [ $# -gt 0 ]; then shift; fi
  case $__bs_pc_cmd in
    help|-h|--help)
      # help of a command that bs_cli_help_cmd delegates to the bash layer
      # справка команды, которую bs_cli_help_cmd отдаёт bash-слою
      case ${1:-} in
        lang-doc|lsp|chat|api|ts|audit|build|rfc)
          unset __bs_pc_cmd
          return 1 ;;
      esac
      unset __bs_pc_cmd
      return 0 ;;
    version|env|list|calc|init-shell|shebang|uninstall|where|update|sync)
      unset __bs_pc_cmd
      return 0 ;;
    doctor|call) ;;
    *)
      unset __bs_pc_cmd
      return 1 ;;
  esac

  # doctor --capabilities loads lib/platform/facts, a bash4 module
  # doctor --capabilities грузит lib/platform/facts — модуль bash4
  if [ "$__bs_pc_cmd" = doctor ]; then
    for __bs_pc_a in "$@"; do
      case $__bs_pc_a in
        --capabilities)
          unset __bs_pc_cmd __bs_pc_a
          return 1 ;;
      esac
    done
    unset __bs_pc_cmd __bs_pc_a
    return 0
  fi

  # call: no --load means the full kernel; core/ modules are POSIX.
  # A "::" name exists only where the shell supports it, otherwise bash.
  # call: без --load нужен полный ярус; модули core/ — POSIX.
  # Имя с "::" есть только там, где оболочка его принимает, иначе bash.
  __bs_pc_loaded=0
  __bs_pc_fn=
  while [ $# -gt 0 ]; do
    case $1 in
      --load)
        [ $# -ge 2 ] || break
        case $2 in
          core/*) ;;
          *)
            unset __bs_pc_cmd __bs_pc_loaded __bs_pc_fn
            return 1 ;;
        esac
        __bs_pc_loaded=1
        shift 2 ;;
      --load=*)
        case ${1#--load=} in
          core/*) ;;
          *)
            unset __bs_pc_cmd __bs_pc_loaded __bs_pc_fn
            return 1 ;;
        esac
        __bs_pc_loaded=1
        shift ;;
      --)     shift
              [ $# -ge 1 ] && __bs_pc_fn=$1
              break ;;
      -*)     shift ;;
      *)      __bs_pc_fn=$1
              break ;;
    esac
  done
  # No --load: the bridge may need any core or lib function -> bash.
  # Без --load мосту может понадобиться любая функция ядра или lib -> bash.
  if [ "$__bs_pc_loaded" = 0 ]; then
    unset __bs_pc_cmd __bs_pc_loaded __bs_pc_fn
    return 1
  fi
  case $__bs_pc_fn in
    *::*)
      unset __bs_pc_cmd __bs_pc_loaded __bs_pc_fn
      return 1 ;;
  esac
  unset __bs_pc_cmd __bs_pc_loaded __bs_pc_fn
  return 0
}

# @description Tier of a file: the first word of its "# @shell" line (default bash4).
# @description Tier файла: первое слово его строки "# @shell" (по умолчанию bash4).
# @param $1 file / файл
# @stdout tier / tier
bs_shell_file_tier() {
  __bs_ft=bash4
  __bs_fn=0
  if [ -r "${1:-}" ]; then
    while [ "$__bs_fn" -lt 40 ] && IFS= read -r __bs_fl; do
      __bs_fn=$((__bs_fn + 1))
      case $__bs_fl in
        '# @shell '*)
          __bs_ft=${__bs_fl#'# @shell '}
          __bs_ft=${__bs_ft%% *}
          break ;;
      esac
    done < "$1"
  fi
  printf '%s\n' "$__bs_ft"
}

# @description Canonical form of one tier word. Synonyms: sh, shell, posix ->
#   posix; bash, bash4 -> bash4; fs, fish -> fish; nu, nushell -> nu; the names
#   of other shells go through bs_shell_of_name; an unknown word stays as is.
# @description Каноническая форма одного слова tier. Синонимы: sh, shell, posix ->
#   posix; bash, bash4 -> bash4; fs, fish -> fish; nu, nushell -> nu; имена
#   других оболочек проходят через bs_shell_of_name; неизвестное слово остаётся.
# @param $1 word / слово
# @stdout canonical word / каноническое слово
bs_shell_tier_word() {
  case "${1:-}" in
    posix|sh|shell) printf 'posix\n' ;;
    bash4|bash)     printf 'bash4\n' ;;
    fs|fish)        printf 'fish\n' ;;
    *)
      __bs_tw=$(bs_shell_of_name "${1:-}")
      if [ "$__bs_tw" = unknown ]; then printf '%s\n' "${1:-}"; else printf '%s\n' "$__bs_tw"; fi ;;
  esac
}

# @description May a file of this tier run when BS was started from this shell?
#   posix — from any; bash4 — only from bash 4.2+; any other word (zsh, fish,
#   nu, ...) — only from the shell of that name. The tier may be a list: a,b;
#   words may be synonyms (see bs_shell_tier_word), the shell too (fs, nushell).
# @description Можно ли исполнять файл этого tier, если BS запущен из этой оболочки?
#   posix — из любой; bash4 — только из bash 4.2+; любое другое слово (zsh,
#   fish, nu, ...) — только из оболочки с этим именем. Tier может быть списком: a,b;
#   слова могут быть синонимами (см. bs_shell_tier_word), оболочка — тоже (fs, nushell).
# @param $1 tier / tier
# @param $2 origin shell / исходная оболочка
# @return 0 allowed, 1 not allowed / 0 можно, 1 нельзя
bs_shell_tier_allows() {
  case "${2:-}" in
    fs) __bs_to=fish ;;
    *)
      __bs_to=$(bs_shell_of_name "${2:-}")
      [ "$__bs_to" != unknown ] || __bs_to=${2:-} ;;
  esac
  __bs_tl=${1:-bash4}
  # список режем подстановкой параметров: zsh не делит неокавыченную переменную по IFS,
  # а менять IFS здесь незачем
  # the list is cut with parameter expansion: zsh does not split an unquoted variable by IFS,
  # and there is no need to touch IFS here
  while [ -n "$__bs_tl" ]; do
    __bs_tk=${__bs_tl%%,*}
    case "$__bs_tl" in *,*) __bs_tl=${__bs_tl#*,} ;; *) __bs_tl= ;; esac
    [ -n "$__bs_tk" ] || continue
    __bs_tk=$(bs_shell_tier_word "$__bs_tk")
    [ "$__bs_tk" != posix ] || return 0
    [ "$__bs_tk" != "$__bs_to" ] || return 0
    if [ "$__bs_tk" = bash4 ] && [ "$__bs_to" = bash ]; then return 0; fi
  done
  return 1
}

# @description One-line bilingual description of a tier.
# @description Однострочное двуязычное описание tier.
# @param $1 tier / tier
# @stdout text / текст
bs_shell_tier_desc() {
  case "${1:-}" in
    native)
      printf '%s\n' "bash 4.2+: библиотека (source) и команды BS работают в этой оболочке / bash 4.2+: the library (source) and the BS commands run in this shell" ;;
    hosted)
      printf '%s\n' "оболочка не исполняет код BS сама: BS работает командой bs, её выполняет bash 4.2+ ($(bs_shell_host_find 2>/dev/null)); PATH и rc настроены под вашу оболочку / this shell does not run BS code itself: BS runs as the bs command executed by bash 4.2+ ($(bs_shell_host_find 2>/dev/null)); PATH and rc fit your shell" ;;
    unsupported)
      printf '%s\n' "bash 4.2+ не найден, BS не запустится: установите bash (apk add bash / apt install bash / dnf install bash / brew install bash) или задайте BS_HOST_BASH / bash 4.2+ not found, BS cannot run: install bash (apk add bash / apt install bash / dnf install bash / brew install bash) or set BS_HOST_BASH" ;;
    *)
      printf '%s\n' "tier неизвестен / unknown tier" ;;
  esac
}

# @description Is the code running in a subshell (( ), $( ), pipeline)? A branch per shell:
#   bash BASH_SUBSHELL, zsh ZSH_SUBSHELL; in the other shells traps are reset in a subshell, so
#   there is nothing to guard and the answer is "not a subshell".
# @description Исполняется ли код в подоболочке (( ), $( ), конвейер)? Ветка на оболочку: bash —
#   BASH_SUBSHELL, zsh — ZSH_SUBSHELL; в остальных оболочках trap'ы в подоболочке сбрасываются,
#   охранять нечего, и ответ «не подоболочка».
# @return 0 in a subshell, 1 in the main shell / 0 в подоболочке, 1 в основной оболочке
bs_shell_in_subshell() {
  if [ -n "${BASH_VERSION:-}" ]; then
    # shellcheck disable=SC3028  # ветка выполняется только в bash / the branch runs only in bash
    [ "${BASH_SUBSHELL:-0}" -gt 0 ]
  elif [ -n "${ZSH_VERSION:-}" ]; then
    # shellcheck disable=SC3028  # ветка выполняется только в zsh / the branch runs only in zsh
    [ "${ZSH_SUBSHELL:-0}" -gt 0 ]
  else
    return 1
  fi
}

# ==========================================
# Read-only variables / Переменные только для чтения
# ==========================================

# @description Make variables read-only in the GLOBAL scope (NAME or NAME=value).
#   Plain `readonly` inside a function is function-local in zsh, so zsh gets its
#   own branch (`readonly -g`); bash, dash and the rest use `readonly`.
# @description Сделать переменные read-only в ГЛОБАЛЬНОЙ области (NAME или NAME=значение).
#   Обычный `readonly` внутри функции в zsh локален для функции, поэтому у zsh своя
#   ветка (`readonly -g`); bash, dash и остальные — `readonly`.
# @param $@ NAME or NAME=value / NAME или NAME=значение
bs_shell_readonly() {
  if [ -n "${ZSH_VERSION:-}" ]; then
    # shellcheck disable=SC3045  # -g есть только в zsh; ветка выполняется только там / -g exists only in zsh; the branch runs only there
    readonly -g "$@"
  else
    readonly "$@"
  fi
}

# ==========================================
# Namespaced aliases / Имена с пространством имён
# ==========================================

# @description Make NS::name an alias of a POSIX function in bash and zsh (dash and
#   other shells reject "::" in function names, so there the alias is skipped).
# @description Сделать NS::name псевдонимом POSIX-функции в bash и zsh (dash и
#   прочие отвергают "::" в именах функций, там псевдоним пропускается).
# @param $1 real function name, e.g. bs_guard / настоящее имя функции
# @param $2 namespaced name, e.g. bs::guard / имя с пространством имён
bs_shell_alias() {
  # Ответ bs_shell__ns_ok не меняется за время жизни процесса: проверяем один
  # раз при подключении реестра, а не на каждый из ~120 псевдонимов.
  # The bs_shell__ns_ok answer does not change for the life of the process: check
  # it once when the registry is sourced, not for each of ~120 aliases.
  [ "${__bs_sh_ns_ok:-0}" = 1 ] || return 0
  eval "$2() { $1 \"\$@\"; }"
}

# @description True when this shell accepts "::" in function names: zsh, and bash
#   outside POSIX mode (bash started as sh rejects them: "not a valid identifier";
#   the trampoline re-runs such a bash in normal mode anyway).
# @description Истина, если оболочка принимает "::" в именах функций: zsh и bash
#   вне режима POSIX (bash, запущенный как sh, их отвергает: «not a valid
#   identifier»; трамплин всё равно перезапускает такой bash в обычном режиме).
bs_shell__ns_ok() {
  [ -n "${ZSH_VERSION:-}" ] && return 0
  [ -n "${BASH_VERSION:-}" ] || return 1
  # shellcheck disable=SC3028  # SHELLOPTS есть только в bash; ветка выполняется только там / SHELLOPTS exists only in bash; the branch runs only there
  case ":${SHELLOPTS:-}:" in
    *:posix:*) return 1 ;;
  esac
  return 0
}

# @global __bs_sh_ns_ok — Shell: cached "::" support answer: 1 yes, 0 no (category: private)
# @global __bs_sh_ns_ok — Shell: закэшированный ответ про "::": 1 да, 0 нет (категория: private)
if bs_shell__ns_ok; then
  __bs_sh_ns_ok=1
else
  __bs_sh_ns_ok=0
fi

# ==========================================
# bs::shell::* names for bash and zsh / имена bs::shell::* для bash и zsh
# ==========================================

# eval: dash не должен разбирать "::" в именах даже в непройденной ветке
# eval: dash must not parse "::" in names even in a branch that is not taken
if bs_shell__ns_ok; then
  for __bs_fn in of_name family login parent user rc_file rc_scan all_rc_files \
      path_line reload_hint fresh_flags known host_ok host_find tier tier_desc \
      login_path can_source rc_create_ok default_login_path version_string version_major version_minor strict self_path file_tier tier_word tier_allows in_subshell posix_command; do
    eval "bs::shell::${__bs_fn}() { bs_shell_${__bs_fn} \"\$@\"; }"
  done
fi
