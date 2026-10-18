#!/bin/sh
# @shell posix — shebang management: no arrays, no [[ ]], no BASH_*; sourced by `bs shebang`
# @shell posix — управление shebang: без массивов, [[ ]] и BASH_*; подключается командой `bs shebang`
#
# bootstrap/shebang.sh — where does the interpreter live on THIS machine, does a
# script's first line work here, and how to rewrite it.
# bootstrap/shebang.sh — где интерпретатор на ЭТОЙ машине, работает ли первая строка
# скрипта здесь и как её переписать.
#
# Why: a shebang needs an absolute path. On most Linux it is /usr/bin/env, on
# Termux (Android) there is no /usr, env lives in $PREFIX/bin/env, and
# `#!/usr/bin/env bs` works only with termux-exec installed.
# Зачем: shebang требует абсолютный путь. На большинстве Linux это /usr/bin/env,
# в Termux (Android) каталога /usr нет, env лежит в $PREFIX/bin/env, а
# `#!/usr/bin/env bs` работает только при установленном termux-exec.
#
# Modes / Режимы:
#   portable  #!/usr/bin/env PROG     — for sharing; works where /usr/bin/env exists
#   env       #!<this machine's env> PROG — env found here ($PREFIX/bin/env on Termux)
#   abs       #!<full path of PROG>   — no env at all; fixed to this install
#   auto      portable if /usr/bin/env exists, else env

[ -n "${__BS_SHEBANG_LOADED:-}" ] && return 0
__BS_SHEBANG_LOADED=1

# @description True on Termux (Android).
# @description Истина в Termux (Android).
bs_shebang_is_termux() {
  [ -n "${TERMUX_VERSION:-}" ] && return 0
  case "${PREFIX:-}" in
    */com.termux/*) return 0 ;;
  esac
  return 1
}

# @description Print the absolute path of env on this machine ("" and rc 1 if none).
# @description Печатает абсолютный путь env на этой машине ("" и rc 1, если нет).
bs_shebang_env_path() {
  __bs_sb_p=""
  for __bs_sb_c in /usr/bin/env /bin/env "${PREFIX:-/nonexistent}/bin/env"; do
    if [ -x "$__bs_sb_c" ]; then
      __bs_sb_p=$__bs_sb_c
      break
    fi
  done
  if [ -z "$__bs_sb_p" ]; then
    __bs_sb_p=$(command -v env 2>/dev/null) || __bs_sb_p=""
    case "$__bs_sb_p" in /*) ;; *) __bs_sb_p="" ;; esac
  fi
  [ -n "$__bs_sb_p" ] || return 1
  printf '%s\n' "$__bs_sb_p"
}

# @description Print the interpreter line of FILE (first line, only if it is #!;
#   a trailing CR of a CRLF file is dropped).
# @description Печатает строку интерпретатора FILE (первую, только если это #!;
#   CR в конце строки CRLF-файла отбрасывается).
# @param $1 file / файл
bs_shebang_read() {
  [ -f "$1" ] || return 1
  __bs_sb_l=""
  IFS= read -r __bs_sb_l < "$1" || [ -n "$__bs_sb_l" ] || return 1
  __bs_sb_cr=$(printf '\r')
  __bs_sb_l=${__bs_sb_l%"$__bs_sb_cr"}
  case "$__bs_sb_l" in
    '#!'*) printf '%s\n' "$__bs_sb_l" ;;
    *) return 1 ;;
  esac
}

# @description Split a shebang line: print "<interpreter> <argument-or-program>".
#   "#!/usr/bin/env bs" -> "/usr/bin/env bs"; "#! /bin/bash -e" -> "/bin/bash -e".
# @description Разобрать строку shebang: печатает "<интерпретатор> <аргумент>".
# @param $1 shebang line / строка shebang
bs_shebang_parse() {
  __bs_sb_r=${1#'#!'}
  __bs_sb_r=${__bs_sb_r# }
  __bs_sb_r=${__bs_sb_r#	}
  printf '%s\n' "$__bs_sb_r"
}

# @description Does the shebang line work on this machine? Prints the reason on failure.
#   rc 0 = works; rc 1 = broken (reason on stdout). If the interpreter is itself a
#   script (#!), its own shebang is checked too (up to 3 hops).
# @description Работает ли строка shebang на этой машине? При сбое печатает причину.
#   Если интерпретатор сам скрипт (#!), проверяется и его shebang (до 3 переходов).
# @param $1 shebang line / строка shebang
bs_shebang_works() {
  __bs_sb_r=$(bs_shebang_parse "$1")
  __bs_sb_i=${__bs_sb_r%% *}
  __bs_sb_a=""
  case "$__bs_sb_r" in *' '*) __bs_sb_a=${__bs_sb_r#* } ;; esac
  case "$__bs_sb_i" in
    /*) ;;
    *) printf 'interpreter path is not absolute: %s\n' "$__bs_sb_i"; return 1 ;;
  esac
  if [ ! -x "$__bs_sb_i" ]; then
    printf 'no such interpreter: %s\n' "$__bs_sb_i"
    return 1
  fi
  case "$__bs_sb_i" in
    */env)
      # env: the first word of the argument is the program (skip options and NAME=value)
      # env: первое слово аргумента — программа (пропускаем опции и NAME=значение)
      # Words are cut by parameter expansion: zsh does not split an unquoted variable.
      # Слова режем подстановкой параметров: zsh не разбивает неокавыченную переменную.
      __bs_sb_rest=$__bs_sb_a
      while [ -n "$__bs_sb_rest" ]; do
        __bs_sb_w=${__bs_sb_rest%% *}
        case "$__bs_sb_rest" in *' '*) __bs_sb_rest=${__bs_sb_rest#* } ;; *) __bs_sb_rest="" ;; esac
        case "$__bs_sb_w" in ''|-*|*=*) continue ;; esac
        command -v "$__bs_sb_w" >/dev/null 2>&1 \
          || { printf 'not found in PATH: %s\n' "$__bs_sb_w"; return 1; }
        break
      done
      ;;
    *)
      # the interpreter is a script: its own first line must work too
      # интерпретатор — скрипт: его собственная первая строка тоже должна работать
      if __bs_sb_n=$(bs_shebang_read "$__bs_sb_i"); then
        if [ "${__BS_SB_DEPTH:-0}" -ge 3 ]; then
          printf 'too many nested interpreters: %s\n' "$__bs_sb_i"
          return 1
        fi
        if ! __bs_sb_why=$( __BS_SB_DEPTH=$(( ${__BS_SB_DEPTH:-0} + 1 )); export __BS_SB_DEPTH; bs_shebang_works "$__bs_sb_n" ); then
          printf '%s is a script and its own shebang is broken: %s\n' "$__bs_sb_i" "$__bs_sb_why"
          return 1
        fi
      fi
      ;;
  esac
  return 0
}

# @description Print the shebang line for a mode.
# @param $1 mode: portable|env|abs|auto / режим
# @param $2 program, default bs / программа
bs_shebang_line() {
  __bs_sb_prog=${2:-bs}
  __bs_sb_mode=${1:-auto}
  if [ "$__bs_sb_mode" = auto ]; then
    if [ -x /usr/bin/env ]; then __bs_sb_mode=portable; else __bs_sb_mode="env"; fi
  fi
  case "$__bs_sb_mode" in
    portable) printf '#!/usr/bin/env %s\n' "$__bs_sb_prog" ;;
    env)
      __bs_sb_e=$(bs_shebang_env_path) || { printf 'env not found on this machine\n' >&2; return 1; }
      printf '#!%s %s\n' "$__bs_sb_e" "$__bs_sb_prog"
      ;;
    abs)
      __bs_sb_f=$(command -v "$__bs_sb_prog" 2>/dev/null) || __bs_sb_f=""
      case "$__bs_sb_f" in
        /*) printf '#!%s\n' "$__bs_sb_f" ;;
        *) printf '%s not found in PATH\n' "$__bs_sb_prog" >&2; return 1 ;;
      esac
      ;;
    *) printf 'unknown mode: %s (portable|env|abs|auto)\n' "$__bs_sb_mode" >&2; return 1 ;;
  esac
}

# @description Is the shebang line EXACTLY "start PROG": "[dir/]PROG" or
#   "[dir/]env PROG", with no extra arguments? Lines with flags (env -S bs --x,
#   sh -c bs) are not touched, so a rewrite never drops them.
# @description Строка shebang РОВНО «запустить PROG»: «[каталог/]PROG» или
#   «[каталог/]env PROG», без лишних аргументов? Строки с флагами не трогаются.
# @param $1 shebang line / строка shebang
# @param $2 program / программа
bs_shebang_is_for() {
  __bs_sb_r=$(bs_shebang_parse "$1")
  __bs_sb_i=${__bs_sb_r%% *}
  __bs_sb_a=""
  case "$__bs_sb_r" in *' '*) __bs_sb_a=${__bs_sb_r#* } ;; esac
  case "$__bs_sb_a" in
    '')
      [ "${__bs_sb_i##*/}" = "$2" ] ;;
    *' '*) return 1 ;;
    *)
      [ "${__bs_sb_i##*/}" = env ] && [ "$__bs_sb_a" = "$2" ] ;;
  esac
}

# @description Replace the first line of FILE, keeping the rest and the file mode.
#   Atomic: the new content is built in a temporary file next to FILE (mode copied
#   with cp -p) and moved over it with mv, so a failure never leaves FILE truncated.
#   Does nothing (rc 0) if the line is already the same. rc 2 = no shebang to replace.
# @description Заменить первую строку FILE, сохранив остальное и права файла.
#   Атомарно: новое содержимое собирается во временном файле рядом (права — cp -p)
#   и переносится mv, поэтому сбой не оставляет FILE усечённым.
# @param $1 file / файл
# @param $2 new shebang line / новая строка shebang
bs_shebang_rewrite() {
  __bs_sb_t=$1
  # a symlink is rewritten through to its target / по символической ссылке правится цель
  if [ -L "$__bs_sb_t" ]; then
    __bs_sb_t=$(readlink -f -- "$__bs_sb_t" 2>/dev/null) || return 1
  fi
  # names starting with "-" must not look like options / имена с «-» не должны выглядеть опциями
  case "$__bs_sb_t" in -*) __bs_sb_t=./$__bs_sb_t ;; esac
  __bs_sb_old=$(bs_shebang_read "$__bs_sb_t") || return 2
  [ "$__bs_sb_old" = "$2" ] && return 0
  __bs_sb_tmp=$(mktemp "$__bs_sb_t.shebang.XXXXXX") || return 1
  if cp -p -- "$__bs_sb_t" "$__bs_sb_tmp" \
     && { printf '%s\n' "$2"; tail -n +2 -- "$__bs_sb_t"; } > "$__bs_sb_tmp" \
     && mv -f -- "$__bs_sb_tmp" "$__bs_sb_t"; then
    return 0
  fi
  rm -f -- "$__bs_sb_tmp"
  return 1
}

# @description Repair the first line of FILE for THIS machine, only if it does not
#   work here. "#!/usr/bin/env PROG" becomes "#!<env found here> PROG" (Termux:
#   $PREFIX/bin/env); "#!/bin/sh" becomes the sh found in PATH. A line that works,
#   a file without #!, and lines with extra flags are left alone. rc 0 = nothing
#   to do or repaired, 1 = could not repair.
# @description Починить первую строку FILE под ЭТУ машину, только если она здесь не
#   работает. «#!/usr/bin/env PROG» превращается в «#!<найденный env> PROG» (Termux:
#   $PREFIX/bin/env); «#!/bin/sh» — в sh из PATH. Рабочая строка, файл без #! и
#   строки с лишними флагами не трогаются. rc 0 = делать нечего или починено.
# @param $1 file / файл
bs_shebang_fix() {
  __bs_sb_fl=$(bs_shebang_read "$1") || return 0
  bs_shebang_works "$__bs_sb_fl" >/dev/null && return 0
  __bs_sb_fp=$(bs_shebang_parse "$__bs_sb_fl")
  __bs_sb_fi=${__bs_sb_fp%% *}
  __bs_sb_fa=""
  case "$__bs_sb_fp" in *' '*) __bs_sb_fa=${__bs_sb_fp#* } ;; esac
  case "$__bs_sb_fa" in *' '*) return 0 ;; esac
  __bs_sb_fb=${__bs_sb_fi##*/}
  case "$__bs_sb_fb" in
    env)
      [ -n "$__bs_sb_fa" ] || return 1
      __bs_sb_fn=$(bs_shebang_line env "$__bs_sb_fa") || return 1
      ;;
    *)
      __bs_sb_fx=$(command -v "$__bs_sb_fb" 2>/dev/null) || return 1
      case "$__bs_sb_fx" in /*) ;; *) return 1 ;; esac
      if [ -n "$__bs_sb_fa" ]; then __bs_sb_fn="#!$__bs_sb_fx $__bs_sb_fa"; else __bs_sb_fn="#!$__bs_sb_fx"; fi
      ;;
  esac
  bs_shebang_rewrite "$1" "$__bs_sb_fn"
}
