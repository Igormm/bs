#!/usr/bin/env bs
# shellcheck shell=bash
# example_core/cache_demo.sh — the three-level transparent cache of core/cache.sh
# example_core/cache_demo.sh — трёхуровневый прозрачный кеш core/cache.sh
#
# L1 (память процесса) → L2 (файлы) → L3 (sqlite3 / C-бэкенд / файлы),
# манифест key=value, TTL, LRU-вытеснение, продвижение L3→L2.
# L1 (process memory) → L2 (files) → L3 (sqlite3 / C backend / files),
# a key=value manifest, TTL, LRU eviction, promotion L3→L2.
# Запуск / run: ./bs example_core/cache_demo.sh

# v присваивает cache::get через bs_var_set, ShellCheck этого не видит /
# v is assigned by cache::get via bs_var_set, which ShellCheck cannot follow
# shellcheck disable=SC2154

set -euo pipefail

load "core/cache"

demo_dir="$(mktemp -d)"
export BS_CACHE_DIR="${demo_dir}/cache"
cache::init
printf 'Каталог / dir: %s\n' "$BS_CACHE_DIR"
printf 'Бэкенд L3 / L3 backend: %s\n' "$(cache::stats | grep '^l3=' | cut -d= -f2)"

printf '\nL1: запись и чтение в памяти процесса / put and read in process memory\n'
cache::put report fp1 "готово / done"
cache::get report fp1 v
printf '  report=%s\n' "$v"

printf '\nМанифест прозрачен / the manifest is transparent\n'
cache::list | sed 's/^/  /'

printf '\nL2: значение переживает состояние процесса / the value survives the process state\n'
bs_map_clear cacheV
bs_map_clear cacheF
cache::init
cache::get report fp1 v
printf '  после повторной init / after a re-init: %s\n' "$v"

printf '\nL3: файлы L2 удалены — значение берётся из холодного уровня / L2 files removed — the cold level answers\n'
rm -f "${BS_CACHE_DIR}"/v/*
cache::get report fp1 v
printf '  из L3 / from L3: %s (продвинуто в L2 / promoted to L2)\n' "$v"

printf '\nTTL: запись живёт 1 секунду / the entry lives 1 second\n'
cache::put temp fp1 "исчезну / will vanish" 1
sleep 2
if cache::get temp fp1 v 2>/dev/null; then
    printf '  ERROR: expired entry answered\n'
else
    printf '  просрочено / expired (rc=1)\n'
fi
printf '  prune удалил / prune removed: %s\n' "$(cache::prune)"

printf '\nСтатистика / stats\n'
cache::stats | sed 's/^/  /'

cache::clear
rm -rf "$demo_dir"
printf '\nОчищено / cleared\n'
