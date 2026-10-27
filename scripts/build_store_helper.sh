#!/bin/sh
# shellcheck shell=sh
# @shell posix — cc/gcc/clang, cksum, find; no bash constructs / cc/gcc/clang, cksum, find; без конструкций bash
# @tier dev — an optional build step; the runtime needs no compiler / опциональный шаг сборки; рантайму компилятор не нужен
#
# scripts/build_store_helper.sh — собрать опциональный C-бэкенд хранилища
# libexec/bs-store.c в кэш-каталог и напечатать путь бинарника. Это ОПЦИОНАЛЬНО:
# core/store.sh по умолчанию работает в памяти без компилятора; бэкенд подключается
# только когда пользователь задаёт BS_STORE_BACKEND (результат этого скрипта) и
# BS_STORE_FILE (файл, который хранит значения между процессами).
# scripts/build_store_helper.sh — build the optional C store backend libexec/bs-store.c
# into the cache directory and print the binary path. It is OPTIONAL: core/store.sh
# works in memory without a compiler; the backend is used only when the user sets
# BS_STORE_BACKEND (the output of this script) and BS_STORE_FILE (the file that holds
# the values across processes).
#
# Использование / Usage:
#   sh scripts/build_store_helper.sh           # собрать (если ещё нет) и напечатать путь / build and print the path
#   sh scripts/build_store_helper.sh --check   # пересобрать принудительно / force a rebuild
#   CC=/path/cc sh scripts/build_store_helper.sh
#
# Exit 0 — путь напечатан; 1 — нет компилятора (чистый shell-фолбэк в памяти).

set -eu

# Каталог скрипта (не cwd): src ищется рядом с самим скриптом / The script's own
# directory (not the cwd): src is resolved next to the script itself
script_dir=.
case "$0" in
  */*) script_dir=${0%/*} ;;
esac
src="${script_dir}/../libexec/bs-store.c"
check=0
CC=${CC:-}

usage() {
  printf '%s\n' \
    'Usage: scripts/build_store_helper.sh [--check]' \
    '' \
    '  --check  rebuild even when a cached binary exists' \
    '' \
    'Uses the CC variable, else cc/gcc/clang. Prints the binary path on success.'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) check=1 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    --*) usage >&2; exit 2 ;;
    *) break ;;
  esac
  shift
done

[ -f "$src" ] || { printf 'build_store_helper: %s missing\n' "$src" >&2; exit 1; }

find_cc() {
  if [ -n "$CC" ] && command -v "$CC" >/dev/null 2>&1; then return 0; fi
  for c in cc gcc clang; do
    if command -v "$c" >/dev/null 2>&1; then CC=$c; return 0; fi
  done
  return 1
}

find_cc || {
  printf 'build_store_helper: no C compiler (cc/gcc/clang); the in-memory store is the fallback / нет компилятора; фолбэк — хранилище в памяти\n' >&2
  exit 1
}

cache=${BS_CACHE_DIR:-"${XDG_CACHE_HOME:-"$HOME/.cache"}/bs"}
sum=$(cksum "$src" | awk '{print $1}')
out="${cache}/bs-store-${sum}-${CC##*/}"

if [ "$check" = 1 ] || [ ! -x "$out" ]; then
  mkdir -p "$cache" 2>/dev/null || { printf 'build_store_helper: cannot create %s\n' "$cache" >&2; exit 1; }
  umask 077
  tmp="${out}.tmp.$$"
  if "$CC" -std=c99 -O2 -Wall -Wextra -o "$tmp" "$src" 2>/dev/null; then
    mv "$tmp" "$out"
  else
    rm -f "$tmp"
    printf 'build_store_helper: %s failed to compile %s\n' "$CC" "$src" >&2
    exit 1
  fi
fi

printf '%s\n' "$out"
