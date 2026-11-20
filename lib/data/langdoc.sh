#!/usr/bin/env bs
# shellcheck shell=bash
# lib/data/langdoc.sh — function documentation index (LSP metadata)
# lib/data/langdoc.sh — индекс документации функций (метаданные для LSP)

# @depends core/lang, core/const, core/errorhandler, core/cache
# @tier core
# @shell bash4 — нужны конструкции bash: local/declare flags, process substitution, case/replace expansion / needs bash constructs: local/declare flags, process substitution, case/replace expansion

# Source Guard
bs::guard "LIB_DATA_LANGDOC" || return 0

# Dependencies
bs::source_relative "../../core/lang.sh" "../../core/const.sh" "../../core/errorhandler.sh" "../../core/cache.sh"

# Documentation index / Индекс документации
#
# Parses `# @description` / `@param` / `@return` / `@stdout` / `@example`
# doc comment blocks (column-0 comments immediately followed by a function
# definition) and emits one JSON object per function. Used by `bs lang-doc`
# and by the future `bs lsp` server. Requires jq (optional dev dependency).
# The parser itself is a jq filter (langdoc.jq) — one jq process per file.
# Парсит doc-комментарии `# @description` / `@param` / `@return` / `@stdout`
# / `@example` (комментарии с колонки 0, сразу за которыми идёт определение
# функции) и выдаёт по одному JSON-объекту на функцию. Используется в
# `bs lang-doc` и в будущем LSP-сервере `bs lsp`. Требует jq.
# Сам парсер — jq-фильтр (langdoc.jq): один процесс jq на файл.

# @global LANGDOC_JQ_FILTER — Langdoc: jq filter file path (category: constant)
# @global LANGDOC_JQ_FILTER — Langdoc: путь к файлу jq-фильтра (категория: constant)
readonly LANGDOC_JQ_FILTER="${BS_ROOT}/lib/data/langdoc.jq"

# @description Emit one JSON object per documented function in a file.
# @description Выдать по JSON-объекту на документированную функцию файла.
# @param $1 File path / Путь к файлу
# @stdout compact JSON objects, one per line / компактные JSON-объекты
# @return 0 ok, 1 file missing or jq unavailable
# @example
#   langdoc::parse_file "${BS_ROOT}/core/lang.sh"
langdoc::parse_file() {
  local -r __ld_file="${1:?file required}"
  if ! is::file "${__ld_file}"; then
    log::error "langdoc::parse_file: file not found: ${__ld_file} / файл не найден: ${__ld_file}"
    return 1
  fi
  if ! is::command jq; then
    log::error "langdoc::parse_file: jq is required (install jq) / требуется jq (установите jq)"
    return 1
  fi
  jq -Rs -c --arg file "${__ld_file}" -f "${LANGDOC_JQ_FILTER}" "${__ld_file}"
}

# @description Parse an in-memory text buffer (LSP didOpen/didChange).
# @description Разобрать текстовый буфер в памяти (LSP didOpen/didChange).
# @param $1 Text / Текст
# @param $2 [optional] Pseudo-file name, default <stdin> / Имя псевдо-файла
# @stdout compact JSON objects, one per line / компактные JSON-объекты
# @return 0 ok, 1 jq unavailable
# @example
#   langdoc::parse_text "${buffer}" "file:///tmp/x.sh"
langdoc::parse_text() {
  local -r __ld_text="${1-}"
  local -r __ld_file="${2:-<stdin>}"
  if ! is::command jq; then
    log::error "langdoc::parse_text: jq is required (install jq) / требуется jq (установите jq)"
    return 1
  fi
  printf '%s' "${__ld_text}" | jq -Rs -c --arg file "${__ld_file}" -f "${LANGDOC_JQ_FILTER}"
}

# @description Build the full function index for a BS tree.
# @description Построить полный индекс функций для дерева BS.
# @param $1 [optional] BS root, default ${BS_ROOT} / Корень BS
# @stdout one JSON array / один JSON-массив
# @return 0 ok, 1 jq unavailable
# @example
#   langdoc::index "${BS_ROOT}"
langdoc::index() {
  local -r __ld_root="${1:-${BS_ROOT}}"
  if ! is::command jq; then
    log::error "langdoc::index: jq is required (install jq) / требуется jq (установите jq)"
    return 1
  fi
  # Кеш (core/cache.sh, L2/L3): индекс — дорогой (jq на файл, сотни форков), чистый
  # отпечаток — содержимое+имя каждого файла списка. Изменение любого файла меняет fp.
  # Cache (core/cache.sh, L2/L3): the index is expensive (a jq per file, hundreds of
  # forks); a pure fingerprint — content+name of each listed file. Any file change
  # changes the fp.
  local -a __ld_files=()
  local __ld_file
  while IFS= read -r __ld_file; do
    __ld_files+=("${__ld_file}")
  done < <(find "${__ld_root}/core" "${__ld_root}/lib" -type f -name '*.sh' 2>/dev/null | sort)
  local -r __ld_fp="$(bs_cache_fp_files "${__ld_files[@]}")"
  local __ld_cached
  if cache::get "langdoc-index:${__ld_root}" "${__ld_fp}" __ld_cached; then
    printf '%s\n' "${__ld_cached}"
    return 0
  fi
  local __ld_out
  __ld_out="$(for __ld_file in "${__ld_files[@]}"; do langdoc::parse_file "${__ld_file}"; done | jq -s -c .)" || return 1
  cache::put "langdoc-index:${__ld_root}" "${__ld_fp}" "${__ld_out}" 0 || true
  printf '%s\n' "${__ld_out}"
}

# @description Reflect documented functions by glob pattern (C++26 std::meta).
# @description Рефлексия документированных функций по glob-паттерну.
# @param $1 Glob pattern, default "*" / Glob-паттерн
# @param $2 [optional] BS root / Корень BS
# @stdout "name<TAB>first description line" per match
# @return 0 ok, 1 jq unavailable
# @example
#   langdoc::reflect "arr::*"
langdoc::reflect() {
  local -r __ld_pattern="${1:-*}"
  local -r __ld_root="${2:-${BS_ROOT}}"
  is::command jq || return 1
  local __ld_regex="${__ld_pattern//\*/.*}"
  langdoc::index "${__ld_root}" | jq -r --arg p "${__ld_regex}" \
    '.[] | select(.name | test("^" + $p + "$")) | .name + "\t" + (.description | split("\n")[0])'
}