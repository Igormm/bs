#!/usr/bin/env bash
# @shell bash4 — bash 4.2+ file behind a POSIX prologue: sh/dash/zsh/bash 3.2 re-run it in bash (bootstrap/trampoline.sh)
# @shell bash4 — файл bash 4.2+ за POSIX-прологом: sh/dash/zsh/bash 3.2 перезапускают его в bash (bootstrap/trampoline.sh)
# 
#  BS Framework – STAGE-1 BOOT-LOADER
#  Назначение / Purpose:
#    - проверить среду (bash≥4);
#    - максимально быстро найти BS_ROOT;
#    - передать управление скрипту bs (stage-2).
#  Exit-codes:
#    0 – успешный запуск bs;
#    1 – bash слишком старый;
#    2 – не найден BS_ROOT или отсутствует bs.
# 

# --- POSIX-пролог (валиден в sh/dash/ash/zsh/bash) / POSIX prologue ---------
# Если запущены не bash 4+ (sh install.sh, zsh ./bs, bash 3.2, bash как sh),
# перезапускаемся в подходящем bash или объясняем, что поставить. В bash 4+
# это одна проверка. Текст пролога одинаков во всех точках входа (тест).
# Unless run by bash 4+ (sh install.sh, zsh ./bs, bash 3.2, bash as sh), re-run
# in a capable bash or explain what to install. In bash 4+ it is one test.
if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO:-0}" -lt 4 ] \
   || { case ":${SHELLOPTS:-}:" in *:posix:*) true ;; *) false ;; esac; }; then
  # zsh меняет $0 внутри подключаемого файла — путь точки входа запоминаем здесь
  # zsh changes $0 inside a sourced file — the entry point path is saved here
  __bs_s=$0
  __bs_p=$0
  __bs_r=$(readlink -f -- "$0" 2>/dev/null) && [ -n "$__bs_r" ] && __bs_p=$__bs_r
  case $__bs_p in */*) __bs_p=${__bs_p%/*} ;; *) __bs_p=. ;; esac
  # shellcheck disable=SC1091
  . "$__bs_p/bootstrap/trampoline.sh"
fi
unset __BS_TRAMPOLINE __bs_p __bs_r __bs_s
# --- конец пролога / end of the prologue ------------------------------------

# 1. Определяем каталог, где лежит boot.sh
BOOT_DIR=$(cd -- "$(dirname -- "$(readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")")" &>/dev/null && pwd)

# 2. Pre-kernel root namespace: shell version gate (bash 3.2-compatible)
#    Строгий режим — через pre-kernel хелпер bs::strict (bootstrap/bs.sh).
#    Strict mode comes from the pre-kernel helper bs::strict (bootstrap/bs.sh).
if [[ -f "${BOOT_DIR}/bootstrap/bs.sh" ]]; then
  source "${BOOT_DIR}/bootstrap/bs.sh"
  bs::strict
  bs::shell::ensure_version 4 || exit 1
else
  printf 'ERROR: bootstrap/bs.sh not found in %s\n' "$BOOT_DIR" >&2
  exit 1
fi

# 3. BS_ROOT: приоритет поиска
#  1) Уже экспортирован внешним скриптом
#  2) Рядом лежит файл «bs» и bootstrap/init.sh
#  3) Системные/пользовательские префиксы
if [[ -z "${BS_ROOT:-}" ]]; then
  if [[ -f "${BOOT_DIR}/bs" && -f "${BOOT_DIR}/bootstrap/init.sh" ]]; then
    BS_ROOT=$BOOT_DIR
  else
    for prefix in "${HOME}/.local/lib/bs" "/usr/local/lib/bs"; do
      if [[ -f "${prefix}/bs" && -f "${prefix}/bootstrap/init.sh" ]]; then
        BS_ROOT=$prefix
        break
      fi
    done
  fi
fi

# 4. Валидация
if [[ -z "${BS_ROOT:-}" ]]; then
  printf 'ERROR: BS framework not found (searched: repo, ~/.local/lib/bs, /usr/local/lib/bs)\n' >&2
  exit 2
fi

if [[ ! -x "${BS_ROOT}/bs" ]]; then
  printf 'ERROR: bs script not found or not executable in BS_ROOT=%s\n' "$BS_ROOT" >&2
  exit 2
fi

# 5. Передаём управление «настоящему» фреймворку
#    Все аргументы, STDIN/STDERR/STDOUT остаются без изменений.
exec "${BS_ROOT}/bs" "$@"