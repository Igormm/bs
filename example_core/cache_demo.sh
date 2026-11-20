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
#
# Вывод — по стилю проекта (bs-cli-style, bs-posix-output): рамки, вердикты
# success, данные info; манифест — голые данные без рамок (машинный слой).
# Output follows the project style; the manifest stays plain data.

# v присваивает cache::get через bs_var_set, ShellCheck этого не видит /
# v is assigned by cache::get via bs_var_set, which ShellCheck cannot follow
# shellcheck disable=SC2154

strict::enable

load "core/cache"

demo_dir="$(mktemp -d)"
export BS_CACHE_DIR="${demo_dir}/cache"
cache::init
bs_log_section "Трёхуровневый кеш / Three-level cache"
bs_log_info "  каталог / dir: $BS_CACHE_DIR"
bs_log_info "  бэкенд L3 / L3 backend: $(cache::stats | grep '^l3=' | cut -d= -f2)"

bs_log_section "L1: память процесса / L1: process memory"
cache::put report fp1 "готово / done"
cache::get report fp1 v
bs_log_info "  report=$v"

bs_log_section "Манифест прозрачен / The manifest is transparent"
cache::list | sed 's/^/  /'

bs_log_section "L2: переживает состояние процесса / L2: survives the process state"
bs_map_clear cacheV
bs_map_clear cacheF
cache::init
cache::get report fp1 v
bs_log_info "  после повторной init / after a re-init: $v"

bs_log_section "L3: холодный уровень / L3: the cold level"
rm -f "${BS_CACHE_DIR}"/v/*
cache::get report fp1 v
bs_log_success "из L3 / from L3: $v (продвинуто в L2 / promoted to L2)"

bs_log_section "TTL: запись живёт 1 секунду / TTL: the entry lives 1 second"
cache::put temp fp1 "исчезну / will vanish" 1
sleep 2
if cache::get temp fp1 v 2>/dev/null; then
    bs_log_error "просроченная запись ответила / an expired entry answered"
else
    bs_log_success "просрочено / expired (rc=1)"
fi
bs_log_info "  prune удалил / prune removed: $(cache::prune)"

bs_log_section "Статистика / Stats"
cache::stats | sed 's/^/  /'

cache::clear
rm -rf "$demo_dir"
bs_log_success "очищено / cleared"
