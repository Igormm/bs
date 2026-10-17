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

# @description Print the interpreter line of FILE (first line, only if it is #!).
# @description Печатает строку интерпретатора FILE (первую, только если это #!).
# @param $1 file / файл
bs_shebang_read() {
  [ -f "$1" ] || return 1
  IFS= read -r __bs_sb_l < "$1" || [ -n "$__bs_sb_l" ] || return 1
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
#   rc 0 = works; rc 1 = broken (reason on stdout).
# @description Работает ли строка shebang на этой машине? При сбое печатает причину.
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
      # env: the first word of the argument is the program (skip -S and options)
      # env: первое слово аргумента — программа (пропускаем -S и опции)
      for __bs_sb_w in $__bs_sb_a; do
        case "$__bs_sb_w" in -*|*=*) continue ;; esac
        command -v "$__bs_sb_w" >/dev/null 2>&1 \
          || { printf 'not found in PATH: %s\n' "$__bs_sb_w"; return 1; }
        break
      done
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
    if [ -x /usr/bin/env ]; then __bs_sb_mode=portable; else __bs_sb_mode=env; fi
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

# @description Does the shebang line start the program PROG (directly or via env)?
# @param $1 shebang line / строка shebang
# @param $2 program / программа
bs_shebang_is_for() {
  __bs_sb_r=$(bs_shebang_parse "$1")
  case "$__bs_sb_r" in
    "$2"|*"/$2"|"$2 "*|*"/$2 "*|*" $2"|*" $2 "*) return 0 ;;
  esac
  return 1
}

# @description Replace the first line of FILE, keeping the rest and the file mode.
#   Does nothing (rc 0) if the line is already the same. rc 2 = no shebang to replace.
# @description Заменить первую строку FILE, сохранив остальное и права файла.
# @param $1 file / файл
# @param $2 new shebang line / новая строка shebang
bs_shebang_rewrite() {
  __bs_sb_old=$(bs_shebang_read "$1") || return 2
  [ "$__bs_sb_old" = "$2" ] && return 0
  __bs_sb_tmp="$1.shebang.$$"
  { printf '%s\n' "$2"; tail -n +2 "$1"; } > "$__bs_sb_tmp" || { rm -f "$__bs_sb_tmp"; return 1; }
  # cat > file keeps the mode, owner and symlink / cat > file сохраняет права, владельца и ссылку
  cat "$__bs_sb_tmp" > "$1" || { rm -f "$__bs_sb_tmp"; return 1; }
  rm -f "$__bs_sb_tmp"
}
