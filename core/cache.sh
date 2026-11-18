#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: манифест key=value, файлы, cksum; sqlite3/C-бэкенд — опциональные пробы / valid POSIX sh: a key=value manifest, files, cksum; sqlite3/C backend are optional probes
# @tier core — builtins + cksum/date/mv; sqlite3 and the C store are optional L3 probes
# @depends core/data
#
# core/cache.sh — трёхуровневый кеш с человекочитаемым манифестом
# core/cache.sh — a three-level cache with a human-readable manifest
#
# ЗАЧЕМ / WHY
#   Дорогие чистые вычисления BS (инвентари, пробы, генерации) хочется не повторять.
#   Этот модуль даёт кеш из трёх уровней с прозрачным манифестом: никакого сокрытия
#   данных — значения лежат обычными файлами/строками, манифест читается cat/grep.
#   Expensive pure BS computations (inventories, probes, generations) should not be
#   repeated. This module gives a three-level cache with a transparent manifest: no
#   data hiding — values are plain files/strings, the manifest reads with cat/grep.
#
# УСТРОЙСТВО / LAYOUT
#   L1 hot  — словари процесса cacheV/cacheF (bs_map_*): чтение значения без форков,
#             живёт в процессе; попадание обновляет манифест (это форки).
#   L2 warm — файлы <dir>/v/<id> + манифест <dir>/manifest: переживает процессы.
#   L3 cold — проба бэкендов: sqlite3 (<dir>/l3.db) → C-бэкенд BS_STORE_BACKEND
#             (<dir>/l3.store, значения в base64) → файлы <dir>/l3/<id>.
#   L1 hot  — the process maps cacheV/cacheF (bs_map_*): reading a value is fork-free,
#             lives in the process; a hit updates the manifest (that forks).
#   L2 warm — the files <dir>/v/<id> + the manifest <dir>/manifest: survives processes.
#   L3 cold — a backend probe: sqlite3 (<dir>/l3.db) → the C backend BS_STORE_BACKEND
#             (<dir>/l3.store, values in base64) → the files <dir>/l3/<id>.
#   Манифест — строки «id=eN key=K fp=F level=L size=S created=C ttl=T hits=H used=U»;
#   id = cksum(key+fp) — content-addressed. Запись манифеста атомарна (temp+mv).
#   The manifest is lines "id=eN key=K fp=F level=L size=S created=C ttl=T hits=H used=U";
#   id = cksum(key+fp) — content-addressed. The manifest write is atomic (temp+mv).
#
# ПРАВИЛА / RULES
#   * Ключ и отпечаток (fp) — [A-Za-z0-9_./:@=-]+, без пробелов/переводов строк (код 2).
#     The key and the fingerprint (fp) are [A-Za-z0-9_./:@=-]+, no spaces/newlines (code 2).
#   * Попадание — только при совпадении fp и непросроченном ttl; иначе промах (1).
#     A hit requires a matching fp and an unexpired ttl; otherwise a miss (1).
#   * put пишет L1+L2+L3 (write-through); get поднимает значение L3→L2→L1 (promotion);
#     prune удаляет просроченное и вытесняет L2/L3 по бюджету (LRU по used).
#     put writes L1+L2+L3 (write-through); get promotes L3→L2→L1; prune removes the
#     expired and evicts L2/L3 over budget (LRU by used).
#   * Значение — строка; завершающие переводы строки срезаются чтением $(cat …)
#     (ограничение shell, как у построчного протокола C-бэкенда).
#     A value is a string; trailing newlines are trimmed by the $(cat …) read
#     (a shell limitation, as with the line-based C backend protocol).
#   * Манифест редактируем: мусорные строки пропускаются при загрузке; id — только
#     e<цифры>[x…], числа без ведущих нулей; ttl ≤ 2000000000 (32-битный mksh).
#     The manifest is editable: garbage lines are skipped at load; id is only
#     e<digits>[x…], numbers without leading zeros; ttl ≤ 2000000000 (32-bit mksh).
#   * Каталог помечается файлом .bs-cache при init; clear отказывает без маркера.
#     The directory is marked with .bs-cache at init; clear refuses without the marker.
#   * Один писатель: параллельные писатели — последний mv побеждает; блокировки нет.
#     One writer: concurrent writers — the last mv wins; there is no lock.
#   * Коды: 0 успех; 1 промах/нет такого; 2 плохое имя/аргумент; 3 сбой носителя.
#     Codes: 0 ok; 1 miss/no such thing; 2 bad name/argument; 3 storage failure.
#   * Бюджеты: BS_CACHE_L2_BYTES (10 MiB), BS_CACHE_L3_BYTES (100 MiB); каталог:
#     BS_CACHE_DIR, иначе ${XDG_CACHE_HOME:-$HOME/.cache}/bs/cache.
#     Budgets: BS_CACHE_L2_BYTES (10 MiB), BS_CACHE_L3_BYTES (100 MiB); directory:
#     BS_CACHE_DIR, else ${XDG_CACHE_HOME:-$HOME/.cache}/bs/cache.
#
# ИМЕНА / NAMES: пространство bs_ (bs_cache_*); псевдонимы cache::* — в bash и zsh.
#   Namespace bs_ (bs_cache_*); the cache::* aliases exist in bash and zsh.

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# shellcheck disable=SC2154  # поля манифеста читаются через IFS read, ShellCheck их не видит / manifest fields are read via IFS read, which ShellCheck cannot follow
bs_guard CACHE || return 0

# Dependencies / Зависимости
bs_source_relative "data.sh"

# @global __bs_cache_dir — State: cache root directory (category: state)
# @global __bs_cache_dir — Состояние: корневой каталог кеша (категория: state)
__bs_cache_dir=''
# @global __bs_cache_l3 — State: L3 backend after the probe: sqlite|cstore|files (category: state)
# @global __bs_cache_l3 — Состояние: бэкенд L3 после пробы: sqlite|cstore|files (категория: state)
__bs_cache_l3=''
# @global __bs_cache_ready — State: 1 after bs_cache_init (category: state)
# @global __bs_cache_ready — Состояние: 1 после bs_cache_init (категория: state)
__bs_cache_ready=0
# @global __bs_cache_misses — State: process-local miss counter for stats (category: state)
# @global __bs_cache_misses — Состояние: счётчик промахов процесса для статистики (категория: state)
__bs_cache_misses=0

# Служебное / Helpers

# @private
# @description Проверить ключ или отпечаток / Check a key or fingerprint
# @param $1 token / токен
bs_cache__token() {
  case "${1-}" in
    ''|*[!A-Za-z0-9_./:@=-]*)
      printf 'bs_cache: invalid key/fingerprint: %s\n' "${1-}" >&2
      return 2 ;;
  esac
  return 0
}

# @private
# @description Каталог кеша по умолчанию / The default cache directory
bs_cache__default_dir() {
  printf '%s\n' "${BS_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/bs/cache}"
}

# @private
# @description Проба бэкенда L3: BS_CACHE_L3 (явный выбор) → sqlite3 → C-бэкенд
#   (BS_STORE_BACKEND + base64) → файлы / Probe the L3 backend: BS_CACHE_L3 (explicit
#   choice) → sqlite3 → the C backend (BS_STORE_BACKEND + base64) → files
bs_cache__probe() {
  case "${BS_CACHE_L3:-}" in
    sqlite)
      if command -v sqlite3 >/dev/null 2>&1; then
        __bs_cache_l3=sqlite
        return 0
      fi
      printf 'bs_cache: BS_CACHE_L3=sqlite but sqlite3 is missing, falling back\n' >&2 ;;
    cstore)
      if [ -n "${BS_STORE_BACKEND:-}" ] && [ -x "${BS_STORE_BACKEND}" ] && command -v base64 >/dev/null 2>&1; then
        __bs_cache_l3=cstore
        return 0
      fi
      printf 'bs_cache: BS_CACHE_L3=cstore needs an executable BS_STORE_BACKEND and base64, falling back\n' >&2 ;;
    files)
      __bs_cache_l3=files
      return 0 ;;
    '') ;;
    *)
      printf 'bs_cache: unknown BS_CACHE_L3: %s (sqlite|cstore|files)\n' "$BS_CACHE_L3" >&2 ;;
  esac
  if command -v sqlite3 >/dev/null 2>&1; then
    __bs_cache_l3=sqlite
  elif [ -n "${BS_STORE_BACKEND:-}" ] && [ -x "${BS_STORE_BACKEND}" ] && command -v base64 >/dev/null 2>&1; then
    __bs_cache_l3=cstore
  else
    __bs_cache_l3=files
  fi
  return 0
}

# @private
# @description Декодировать base64 (проба -d/-D) / Decode base64 (probe -d/-D)
# @stdin encoded / закодированное
# @stdout decoded / декодированное
bs_cache__b64dec() {
  if printf 'eA==' | base64 -d >/dev/null 2>&1; then
    base64 -d
  else
    base64 -D
  fi
}

# @private
# @description ID записи: e<cksum(key|fp)>; разделитель исключает склейку токенов,
#   суффикс x — коллизии CRC32 с другим ключом (проверяется по манифесту).
#   The entry ID: e<cksum(key|fp)>; the separator excludes token gluing, an x suffix
#   handles CRC32 collisions with another key (checked against the manifest).
# @param $1 key / ключ
# @param $2 fp / отпечаток
bs_cache__id() {
  __bs_cache_id="e$(printf '%s|%s' "${1}" "${2}" | cksum | cut -d' ' -f1)"
  while bs_cache__id_taken "$__bs_cache_id" "${1}"; do
    __bs_cache_id="${__bs_cache_id}x"
  done
}

# @private
# @description ID занят ДРУГИМ ключом (статус) / The ID is taken by ANOTHER key (status)
# @param $1 id / ID
# @param $2 key / ключ
bs_cache__id_taken() {
  # Параметры сохраняются ДО eval set --: он затирает $1/$2 (ловушка §12, п.28)
  # The parameters are saved BEFORE eval set --: it clobbers $1/$2 (chapter 12, item 28)
  __bs_cache_tid=${1-}
  __bs_cache_tkey=${2-}
  bs_map_keys_to cacheM cacheIdKeys
  eval "$(bs_arr_to_args cacheIdKeys)"
  for __bs_cache_ik in "$@"; do
    if [ "$__bs_cache_ik" = "$__bs_cache_tkey" ]; then continue; fi
    bs_map_get_to cacheM "$__bs_cache_ik" __bs_cache_im || continue
    if [ "$(bs_cache__meta_field "$__bs_cache_im" 1)" = "$__bs_cache_tid" ]; then
      bs_arr_clear cacheIdKeys
      return 0
    fi
  done
  bs_arr_clear cacheIdKeys
  return 1
}

# @private
# @description Сейчас → __bs_cache_now (epoch seconds, без вывода) / Now → __bs_cache_now (epoch seconds, no output)
bs_cache__now() {
  __bs_cache_now=$(date +%s)
}

# @private
# @description Записать манифест из словаря cacheM атомарно (temp+mv) /
#   Write the manifest from the cacheM map atomically (temp+mv)
bs_cache__save() {
  __bs_cache_mf="${__bs_cache_dir}/manifest.tmp.$$"
  # printf — обычный builtin: сбой редиректа даёт статус, а не убивает dash/ash
  # printf is a regular builtin: a redirect failure gives a status, not a dead dash/ash
  if ! printf '' > "$__bs_cache_mf"; then
    return 3
  fi
  bs_map_each cacheM bs_cache__save_cb
  if mv "$__bs_cache_mf" "${__bs_cache_dir}/manifest"; then
    return 0
  fi
  rm -f "$__bs_cache_mf"
  return 3
}

# @private
# @description Обратный вызов: строка манифеста / Callback: one manifest line
# @param $1 key / ключ
# @param $2 meta (id fp level size created ttl hits used) / мета
bs_cache__save_cb() {
  # Разбор без форков: 8 $(bs_cache__meta_field …) на запись делали hot-путь O(N) форков
  # Fork-free parse: 8 $(bs_cache__meta_field …) per entry made the hot path O(N) forks
  IFS=' ' read -r __bs_cache_s1 __bs_cache_s2 __bs_cache_s3 __bs_cache_s4 \
    __bs_cache_s5 __bs_cache_s6 __bs_cache_s7 __bs_cache_s8 <<EOF
${2-}
EOF
  printf 'id=%s key=%s fp=%s level=%s size=%s created=%s ttl=%s hits=%s used=%s\n' \
    "$__bs_cache_s1" "${1-}" "$__bs_cache_s2" "$__bs_cache_s3" "$__bs_cache_s4" \
    "$__bs_cache_s5" "$__bs_cache_s6" "$__bs_cache_s7" "$__bs_cache_s8" \
    >> "$__bs_cache_mf"
  return 0
}

# @private
# @description Поле меты по номеру (1..8) / A meta field by number (1..8)
# @param $1 meta string / строка меты
# @param $2 field number / номер поля
bs_cache__meta_field() {
  IFS=' ' read -r __bs_cache_m1 __bs_cache_m2 __bs_cache_m3 __bs_cache_m4 \
    __bs_cache_m5 __bs_cache_m6 __bs_cache_m7 __bs_cache_m8 <<EOF
${1-}
EOF
  case "${2-}" in
    1) printf '%s' "$__bs_cache_m1" ;;
    2) printf '%s' "$__bs_cache_m2" ;;
    3) printf '%s' "$__bs_cache_m3" ;;
    4) printf '%s' "$__bs_cache_m4" ;;
    5) printf '%s' "$__bs_cache_m5" ;;
    6) printf '%s' "$__bs_cache_m6" ;;
    7) printf '%s' "$__bs_cache_m7" ;;
    8) printf '%s' "$__bs_cache_m8" ;;
  esac
  return 0
}

# @private
# @description Разобрать строку манифеста в словарь cacheM / Parse a manifest line into cacheM
# @param $1 line / строка
bs_cache__load_line() {
  IFS=' ' read -r __bs_cache_li __bs_cache_lk __bs_cache_lf __bs_cache_ll \
    __bs_cache_ls __bs_cache_lc __bs_cache_lt __bs_cache_lh __bs_cache_lu <<EOF
${1-}
EOF
  case "$__bs_cache_li" in
    id=*) ;;
    *) return 0 ;;
  esac
  # Манифест редактируем вручную: мусорные строки пропускаются, id — только e<цифры>[x…],
  # числа нормализуются (ведущие нули фатальны для $(( )) в dash/bash)
  # The manifest is hand-editable: garbage lines are skipped, id is only e<digits>[x…],
  # numbers are normalized (leading zeros are fatal for $(( )) in dash/bash)
  __bs_cache_vid=${__bs_cache_li#id=}
  case "$__bs_cache_vid" in
    e[0-9]*) ;;
    *) return 0 ;;
  esac
  case "${__bs_cache_vid#e}" in
    *[!0-9x]*|'') return 0 ;;
  esac
  __bs_cache_vkey=${__bs_cache_lk#key=}
  __bs_cache_vfp=${__bs_cache_lf#fp=}
  case "$__bs_cache_vkey" in
    ''|*[!A-Za-z0-9_./:@=-]*) return 0 ;;
  esac
  case "$__bs_cache_vfp" in
    ''|*[!A-Za-z0-9_./:@=-]*) return 0 ;;
  esac
  case "${__bs_cache_ll#level=}" in
    2|3) ;;
    *) return 0 ;;
  esac
  for __bs_cache_vn in "${__bs_cache_ls#size=}" "${__bs_cache_lc#created=}" "${__bs_cache_lt#ttl=}" "${__bs_cache_lh#hits=}" "${__bs_cache_lu#used=}"; do
    case "$__bs_cache_vn" in
      ''|*[!0-9]*) return 0 ;;
    esac
  done
  bs_map_set cacheM "$__bs_cache_vkey" \
    "$__bs_cache_vid $__bs_cache_vfp ${__bs_cache_ll#level=} $(bs_cache__norm "${__bs_cache_ls#size=}") $(bs_cache__norm "${__bs_cache_lc#created=}") $(bs_cache__norm "${__bs_cache_lt#ttl=}") $(bs_cache__norm "${__bs_cache_lh#hits=}") $(bs_cache__norm "${__bs_cache_lu#used=}")"
  return 0
}

# @private
# @description Снять ведущие нули с числа (0 остаётся 0) / Strip leading zeros (0 stays 0)
# @param $1 number / число
bs_cache__norm() {
  __bs_cache_nv=${1-}
  while :; do
    case "$__bs_cache_nv" in
      0?*) __bs_cache_nv=${__bs_cache_nv#0} ;;
      *) break ;;
    esac
  done
  printf '%s' "$__bs_cache_nv"
  return 0
}

# @private
# @description Просрочена ли запись (ttl) / Whether the entry is expired (ttl)
# @param $1 meta / мета
bs_cache__expired() {
  __bs_cache_et=$(bs_cache__meta_field "${1-}" 6)
  __bs_cache_ec=$(bs_cache__meta_field "${1-}" 5)
  if [ "$__bs_cache_et" -gt 0 ] 2>/dev/null; then
    bs_cache__now
    # Вычитание, не сложение: created+ttl переполняет 32-битный mksh
    # Subtraction, not addition: created+ttl overflows 32-bit mksh
    if [ "$(( __bs_cache_now - __bs_cache_ec ))" -gt "$__bs_cache_et" ]; then
      return 0
    fi
  fi
  return 1
}

# @private
# @description Удалить носители записи (L2/L3), не трогая манифест / Remove the entry carriers (L2/L3), not the manifest
# @param $1 key / ключ
# @param $2 meta / мета
bs_cache__drop_carriers() {
  __bs_cache_did=$(bs_cache__meta_field "${2-}" 1)
  rm -f "${__bs_cache_dir}/v/${__bs_cache_did}" "${__bs_cache_dir}/l3/${__bs_cache_did}"
  case "$__bs_cache_l3" in
    sqlite)
      sqlite3 "${__bs_cache_dir}/l3.db" "DELETE FROM cache WHERE key='${1}';" >/dev/null 2>&1 || return 3 ;;
    cstore)
      "$BS_STORE_BACKEND" unset "${__bs_cache_dir}/l3.store" "cache_${__bs_cache_did}" >/dev/null 2>&1 || return 3 ;;
  esac
  return 0
}

# @private
# @description Экранировать одинарные кавычки пути для SQL (' → '') / Escape single quotes of a path for SQL (' → '')
# @param $1 path / путь
bs_cache__sql_path() {
  __bs_cache_sp=${1-}
  __bs_cache_sq=''
  while :; do
    case "$__bs_cache_sp" in
      *\'*)
        __bs_cache_sq="${__bs_cache_sq}${__bs_cache_sp%%\'*}''"
        __bs_cache_sp=${__bs_cache_sp#*\'} ;;
      *)
        __bs_cache_sq="${__bs_cache_sq}${__bs_cache_sp}"
        break ;;
    esac
  done
  printf '%s' "$__bs_cache_sq"
  return 0
}

# @private
# @description Записать значение в L3 / Write a value to L3
# @param $1 key / ключ
# @param $2 id / ID
# @param $3 value / значение
# @param $4 meta without level (fp size created ttl hits used are taken from the caller vars) / мета
bs_cache__l3_put() {
  case "$__bs_cache_l3" in
    sqlite)
      __bs_cache_tf="${__bs_cache_dir}/l3.tmp.$$"
      __bs_cache_tfs=$(bs_cache__sql_path "$__bs_cache_tf")
      printf '%s' "${3-}" > "$__bs_cache_tf"
      sqlite3 "${__bs_cache_dir}/l3.db" \
        "CREATE TABLE IF NOT EXISTS cache(key TEXT PRIMARY KEY, fp TEXT, val BLOB, created INTEGER, ttl INTEGER, hits INTEGER, used INTEGER, size INTEGER);
         INSERT OR REPLACE INTO cache VALUES('${1}','${__bs_cache_pf}',readfile('${__bs_cache_tfs}'),${__bs_cache_pc},${__bs_cache_pt},0,${__bs_cache_pc},${__bs_cache_ps});" >/dev/null 2>&1
      __bs_cache_rc=$?
      rm -f "$__bs_cache_tf"
      [ "$__bs_cache_rc" = 0 ] || return 3 ;;
    cstore)
      printf '%s' "${3-}" | base64 | tr -d '\n' | \
        "$BS_STORE_BACKEND" set "${__bs_cache_dir}/l3.store" "cache_${2}" >/dev/null 2>&1 || return 3 ;;
    files)
      mkdir -p "${__bs_cache_dir}/l3"
      printf '%s' "${3-}" > "${__bs_cache_dir}/l3/${2}" || return 3 ;;
  esac
  return 0
}

# @private
# @description Прочитать значение из L3 → __bs_cache_val / Read a value from L3 → __bs_cache_val
# @param $1 key / ключ
# @param $2 id / ID
bs_cache__l3_get() {
  case "$__bs_cache_l3" in
    sqlite)
      __bs_cache_tf="${__bs_cache_dir}/l3.tmp.$$"
      __bs_cache_tfs=$(bs_cache__sql_path "$__bs_cache_tf")
      rm -f "$__bs_cache_tf"
      sqlite3 "${__bs_cache_dir}/l3.db" \
        "SELECT writefile('${__bs_cache_tfs}', val) FROM cache WHERE key='${1}';" >/dev/null 2>&1 || :
      if [ -f "$__bs_cache_tf" ]; then
        __bs_cache_val=$(cat "$__bs_cache_tf")
        rm -f "$__bs_cache_tf"
        return 0
      fi
      return 1 ;;
    cstore)
      __bs_cache_b6=$("$BS_STORE_BACKEND" get "${__bs_cache_dir}/l3.store" "cache_${2}" 2>/dev/null) || return 1
      __bs_cache_val=$(printf '%s' "$__bs_cache_b6" | bs_cache__b64dec) || return 1
      return 0 ;;
    files)
      if [ -f "${__bs_cache_dir}/l3/${2}" ]; then
        __bs_cache_val=$(cat "${__bs_cache_dir}/l3/${2}")
        return 0
      fi
      return 1 ;;
  esac
  return 1
}

# Публичное API / Public API

# @description Инициализировать кеш: каталог, проба L3, чтение манифеста /
#   Initialize the cache: the directory, the L3 probe, the manifest read
# @param $1 directory (optional, default BS_CACHE_DIR / XDG) / каталог (необязательно)
bs_cache_init() {
  __bs_cache_dir=${1:-$(bs_cache__default_dir)}
  if ! mkdir -p "${__bs_cache_dir}/v"; then
    printf 'bs_cache: cannot create: %s\n' "$__bs_cache_dir" >&2
    return 3
  fi
  # Маркер «это кеш BS»: clear refuses a directory without it (e.g. BS_CACHE_DIR=$HOME)
  # The "this is a BS cache" marker: clear refuses a directory without it
  if ! printf 'bs-cache v1\n' > "${__bs_cache_dir}/.bs-cache"; then
    printf 'bs_cache: cannot write marker: %s\n' "$__bs_cache_dir" >&2
    return 3
  fi
  bs_cache__probe
  if [ "$__bs_cache_l3" = sqlite ]; then
    sqlite3 "${__bs_cache_dir}/l3.db" \
      "CREATE TABLE IF NOT EXISTS cache(key TEXT PRIMARY KEY, fp TEXT, val BLOB, created INTEGER, ttl INTEGER, hits INTEGER, used INTEGER, size INTEGER);" >/dev/null 2>&1 || {
      printf 'bs_cache: sqlite3 failed, falling back to files\n' >&2
      __bs_cache_l3=files
    }
  fi
  bs_map_clear cacheM
  bs_map_clear cacheV
  bs_map_clear cacheF
  if [ -f "${__bs_cache_dir}/manifest" ]; then
    while IFS= read -r __bs_cache_line || [ -n "$__bs_cache_line" ]; do
      bs_cache__load_line "$__bs_cache_line"
    done < "${__bs_cache_dir}/manifest"
  fi
  __bs_cache_ready=1
  return 0
}

# @private
# @description Ленивая инициализация / Lazy initialization
bs_cache__ensure() {
  if [ "$__bs_cache_ready" != 1 ]; then
    bs_cache_init || return 3
  fi
  return 0
}

# @description Отпечаток файлов: cksum содержимого + имена (переносимо, без GNU) /
#   A file fingerprint: cksum of the content + names (portable, no GNU)
# @param $@ files / файлы
# @stdout fingerprint / отпечаток
bs_cache_fp_files() {
  {
    for __bs_cache_ff in "$@"; do
      if [ -f "$__bs_cache_ff" ] && [ -r "$__bs_cache_ff" ]; then
        cksum "$__bs_cache_ff" || printf 'unreadable %s\n' "$__bs_cache_ff"
      elif [ -f "$__bs_cache_ff" ]; then
        printf 'unreadable %s\n' "$__bs_cache_ff"
      else
        printf 'missing %s\n' "$__bs_cache_ff"
      fi
    done
  } | cksum | cut -d' ' -f1
  return 0
}

# @description Положить значение: L1+L2+L3 (write-through), манифест обновляется /
#   Put a value: L1+L2+L3 (write-through), the manifest is updated
# @param $1 key / ключ
# @param $2 fp / отпечаток
# @param $3 value / значение
# @param $4 ttl seconds (optional, 0 = forever) / ttl в секундах (необязательно, 0 = навсегда)
bs_cache_put() {
  bs_cache__ensure || return $?
  bs_cache__token "${1-}" || return 2
  bs_cache__token "${2-}" || return 2
  __bs_cache_pk=$1
  __bs_cache_pf=$2
  __bs_cache_pv=${3-}
  __bs_cache_pt=${4:-0}
  case "$__bs_cache_pt" in
    ''|*[!0-9]*) printf 'bs_cache: ttl must be a non-negative integer\n' >&2; return 2 ;;
  esac
  # Ведущие нули: $((08)) фатален в dash/bash / Leading zeros: $((08)) is fatal in dash/bash
  while :; do
    case "$__bs_cache_pt" in
      0?*) __bs_cache_pt=${__bs_cache_pt#0} ;;
      *) break ;;
    esac
  done
  # Предел 32-битной арифметики mksh (~63 года): test -gt в mksh молча заворачивает
  # большие числа, а test \> не поддерживает zsh — сравниваем длиной и case-шаблоном
  # The 32-bit mksh arithmetic limit (~63 years): test -gt in mksh silently wraps big
  # numbers and zsh lacks test \> — compare by length and a case pattern
  case "$__bs_cache_pt" in
    ???????????*)
      printf 'bs_cache: ttl too large (max 2000000000)\n' >&2
      return 2 ;;
    ??????????)
      case "$__bs_cache_pt" in
        [3-9]*|2*[1-9]*)
          printf 'bs_cache: ttl too large (max 2000000000)\n' >&2
          return 2 ;;
      esac ;;
  esac
  bs_cache__id "$__bs_cache_pk" "$__bs_cache_pf"
  if bs_map_get_to cacheM "$__bs_cache_pk" __bs_cache_old; then
    __bs_cache_oid=$(bs_cache__meta_field "$__bs_cache_old" 1)
    if [ "$__bs_cache_oid" != "$__bs_cache_id" ]; then
      bs_cache__drop_carriers "$__bs_cache_pk" "$__bs_cache_old"
    fi
  fi
  # Байты, не символы: ${#s} считает символы в bash/zsh/ksh и байты в dash/mksh
  # Bytes, not characters: ${#s} counts characters in bash/zsh/ksh, bytes in dash/mksh
  __bs_cache_ps=$(printf '%s' "$__bs_cache_pv" | wc -c | tr -d ' ')
  bs_cache__now
  __bs_cache_pc=$__bs_cache_now
  if ! printf '%s' "$__bs_cache_pv" > "${__bs_cache_dir}/v/${__bs_cache_id}"; then
    return 3
  fi
  if ! bs_cache__l3_put "$__bs_cache_pk" "$__bs_cache_id" "$__bs_cache_pv"; then
    return 3
  fi
  bs_map_set cacheV "$__bs_cache_pk" "$__bs_cache_pv"
  bs_map_set cacheF "$__bs_cache_pk" "$__bs_cache_pf"
  bs_map_set cacheM "$__bs_cache_pk" \
    "${__bs_cache_id} ${__bs_cache_pf} 2 ${__bs_cache_ps} ${__bs_cache_pc} ${__bs_cache_pt} 0 ${__bs_cache_pc}"
  bs_cache__save
}

# @description Взять значение: L1 → L2 → L3 с продвижением вверх; попадание только при
#   совпадении fp и живом ttl. НЕ вызывайте мутирующие обёртки как $(...) — сам get
#   только читает и обновляет статистику, значение берите в переменную.
#   Get a value: L1 → L2 → L3 with promotion; a hit requires a matching fp and a live
#   ttl. The get itself only reads and updates statistics; take the value into a variable.
# @param $1 key / ключ
# @param $2 fp / отпечаток
# @param $3 variable for the value (optional, else stdout) / переменная (необязательно, иначе stdout)
# @returns 0 hit / 1 miss / 2 bad token
bs_cache_get() {
  bs_cache__ensure || return $?
  bs_cache__token "${1-}" || return 2
  bs_cache__token "${2-}" || return 2
  __bs_cache_gk=$1
  __bs_cache_gf=$2
  __bs_cache_gv=${3-}
  # Мета решает всё: fp и ttl проверяются ДО любого уровня, включая L1
  # The meta decides: fp and ttl are checked BEFORE any level, including L1
  if ! bs_map_get_to cacheM "$__bs_cache_gk" __bs_cache_meta; then
    __bs_cache_misses=$((__bs_cache_misses + 1))
    return 1
  fi
  __bs_cache_mfp=$(bs_cache__meta_field "$__bs_cache_meta" 2)
  if [ "$__bs_cache_mfp" != "$__bs_cache_gf" ] || bs_cache__expired "$__bs_cache_meta"; then
    __bs_cache_misses=$((__bs_cache_misses + 1))
    return 1
  fi
  if bs_map_get_to cacheF "$__bs_cache_gk" __bs_cache_l1f && [ "$__bs_cache_l1f" = "$__bs_cache_gf" ] \
    && bs_map_get_to cacheV "$__bs_cache_gk" __bs_cache_val; then
    bs_cache__hit "$__bs_cache_gk"
    bs_cache__out "$__bs_cache_gv"
    return 0
  fi
  __bs_cache_mid=$(bs_cache__meta_field "$__bs_cache_meta" 1)
  if [ -f "${__bs_cache_dir}/v/${__bs_cache_mid}" ]; then
    __bs_cache_val=$(cat "${__bs_cache_dir}/v/${__bs_cache_mid}")
  elif bs_cache__l3_get "$__bs_cache_gk" "$__bs_cache_mid"; then
    # Продвижение L3 → L2 / Promotion L3 → L2
    printf '%s' "$__bs_cache_val" > "${__bs_cache_dir}/v/${__bs_cache_mid}" || return 3
  else
    __bs_cache_misses=$((__bs_cache_misses + 1))
    return 1
  fi
  bs_map_set cacheV "$__bs_cache_gk" "$__bs_cache_val"
  bs_map_set cacheF "$__bs_cache_gk" "$__bs_cache_gf"
  bs_cache__hit "$__bs_cache_gk"
  bs_cache__out "$__bs_cache_gv"
  return 0
}

# @private
# @description Отдать значение в переменную или stdout / Hand the value to a variable or stdout
# @param $1 variable name or empty / имя переменной или пусто
bs_cache__out() {
  if [ -n "${1-}" ]; then
    bs_var_set "$1" "$__bs_cache_val"
    return $?
  fi
  printf '%s\n' "$__bs_cache_val"
  return 0
}

# @private
# @description Учесть попадание: hits+1, used=now, манифест / Record a hit: hits+1, used=now, manifest
# @param $1 key / ключ
bs_cache__hit() {
  bs_map_get_to cacheM "${1-}" __bs_cache_hm || return 0
  __bs_cache_hid=$(bs_cache__meta_field "$__bs_cache_hm" 1)
  __bs_cache_hfp=$(bs_cache__meta_field "$__bs_cache_hm" 2)
  __bs_cache_hsz=$(bs_cache__meta_field "$__bs_cache_hm" 4)
  __bs_cache_hcr=$(bs_cache__meta_field "$__bs_cache_hm" 5)
  __bs_cache_htt=$(bs_cache__meta_field "$__bs_cache_hm" 6)
  __bs_cache_hh=$(bs_cache__meta_field "$__bs_cache_hm" 7)
  bs_cache__now
  # Уровень 2 только при живом файле L2; без файла значение есть в L3 (write-through)
  # Level 2 only with a live L2 file; without the file the value lives in L3 (write-through)
  __bs_cache_hl=3
  if [ -f "${__bs_cache_dir}/v/${__bs_cache_hid}" ]; then
    __bs_cache_hl=2
  fi
  bs_map_set cacheM "${1-}" \
    "${__bs_cache_hid} ${__bs_cache_hfp} ${__bs_cache_hl} ${__bs_cache_hsz} ${__bs_cache_hcr} ${__bs_cache_htt} $(( __bs_cache_hh + 1 )) ${__bs_cache_now}"
  bs_cache__save || :
  return 0
}

# @description Запись существует и fp совпадает (статус) / The entry exists and fp matches (status)
# @param $1 key / ключ
# @param $2 fp / отпечаток
bs_cache_has() {
  bs_cache__ensure || return $?
  bs_cache__token "${1-}" || return 2
  bs_cache__token "${2-}" || return 2
  bs_map_get_to cacheM "${1-}" __bs_cache_hm || return 1
  __bs_cache_hfp=$(bs_cache__meta_field "$__bs_cache_hm" 2)
  if [ "$__bs_cache_hfp" = "$2" ] && ! bs_cache__expired "$__bs_cache_hm"; then
    return 0
  fi
  return 1
}

# @description Удалить запись со всех уровней / Remove an entry from every level
# @param $1 key / ключ
bs_cache_delete() {
  bs_cache__ensure || return $?
  bs_cache__token "${1-}" || return 2
  bs_map_get_to cacheM "${1-}" __bs_cache_dm || return 1
  bs_cache__drop_carriers "${1-}" "$__bs_cache_dm"
  bs_map_remove cacheM "${1-}"
  bs_map_remove cacheV "${1-}" || :
  bs_map_remove cacheF "${1-}" || :
  bs_cache__save
}

# @description Очистить кеш целиком (все уровни и манифест) / Clear the whole cache (every level and the manifest)
bs_cache_clear() {
  # НЕ зовёт ensure/init: init создал бы каталог и маркер ДО проверки, и чужой
  # каталог (BS_CACHE_DIR=$HOME) был бы очищен. Каталог только резолвится.
  # Does NOT call ensure/init: init would create the directory and the marker BEFORE
  # the check, and a foreign directory (BS_CACHE_DIR=$HOME) would be cleared.
  if [ "$__bs_cache_ready" != 1 ]; then
    __bs_cache_dir=$(bs_cache__default_dir)
    bs_cache__probe
    bs_map_clear cacheM
    bs_map_clear cacheV
    bs_map_clear cacheF
  fi
  case "$__bs_cache_dir" in
    ''|/) printf 'bs_cache: refusing to clear %s\n' "$__bs_cache_dir" >&2; return 2 ;;
  esac
  if [ ! -f "${__bs_cache_dir}/.bs-cache" ]; then
    printf 'bs_cache: not a BS cache directory (no .bs-cache marker): %s\n' "$__bs_cache_dir" >&2
    return 2
  fi
  rm -rf "${__bs_cache_dir:?}/v" "${__bs_cache_dir:?}/l3"
  rm -f "${__bs_cache_dir:?}/manifest" "${__bs_cache_dir:?}/l3.db" "${__bs_cache_dir:?}/l3.store" \
    "${__bs_cache_dir:?}/l3.db-journal" "${__bs_cache_dir:?}/l3.db-wal" "${__bs_cache_dir:?}/l3.db-shm"
  if ! mkdir -p "${__bs_cache_dir}/v"; then
    return 3
  fi
  if ! printf 'bs-cache v1\n' > "${__bs_cache_dir}/.bs-cache"; then
    return 3
  fi
  bs_map_clear cacheM
  bs_map_clear cacheV
  bs_map_clear cacheF
  __bs_cache_ready=1
  if [ "$__bs_cache_l3" = sqlite ]; then
    sqlite3 "${__bs_cache_dir}/l3.db" \
      "CREATE TABLE IF NOT EXISTS cache(key TEXT PRIMARY KEY, fp TEXT, val BLOB, created INTEGER, ttl INTEGER, hits INTEGER, used INTEGER, size INTEGER);" >/dev/null 2>&1 || :
  fi
  return 0
}

# @description Просроченное — удалить; сверх бюджета — вытеснить L2 (LRU по used),
#   затем L3 целиком. Бюджеты: BS_CACHE_L2_BYTES / BS_CACHE_L3_BYTES.
#   Remove the expired; over budget — evict L2 (LRU by used), then L3 entirely.
#   Budgets: BS_CACHE_L2_BYTES / BS_CACHE_L3_BYTES.
# @stdout число удалённых записей / the number of removed entries
bs_cache_prune() {
  bs_cache__ensure || return $?
  __bs_cache_pn=0
  __bs_cache_l2b=${BS_CACHE_L2_BYTES:-10485760}
  __bs_cache_l3b=${BS_CACHE_L3_BYTES:-104857600}
  # Просроченные / The expired
  bs_map_keys_to cacheM cachePruneKeys
  eval "$(bs_arr_to_args cachePruneKeys)"
  for __bs_cache_pk in "$@"; do
    bs_map_get_to cacheM "$__bs_cache_pk" __bs_cache_pm || continue
    if bs_cache__expired "$__bs_cache_pm"; then
      bs_cache_delete "$__bs_cache_pk" || :
      __bs_cache_pn=$((__bs_cache_pn + 1))
    fi
  done
  # Бюджет L2: вытесняем самые давно использованные, пока сумма больше бюджета
  # L2 budget: evict the least recently used while the sum is over budget
  while :; do
    __bs_cache_sum=0
    __bs_cache_oldest=''
    __bs_cache_oused=''
    bs_map_keys_to cacheM cachePruneKeys
    eval "$(bs_arr_to_args cachePruneKeys)"
    for __bs_cache_pk in "$@"; do
      bs_map_get_to cacheM "$__bs_cache_pk" __bs_cache_pm || continue
      __bs_cache_pl=$(bs_cache__meta_field "$__bs_cache_pm" 3)
      [ "$__bs_cache_pl" = 2 ] || continue
      __bs_cache_psz=$(bs_cache__meta_field "$__bs_cache_pm" 4)
      __bs_cache_pu=$(bs_cache__meta_field "$__bs_cache_pm" 8)
      __bs_cache_sum=$((__bs_cache_sum + __bs_cache_psz))
      if [ -z "$__bs_cache_oldest" ] || [ "$__bs_cache_pu" -lt "$__bs_cache_oused" ]; then
        __bs_cache_oldest=$__bs_cache_pk
        __bs_cache_oused=$__bs_cache_pu
      fi
    done
    if [ "$__bs_cache_sum" -le "$__bs_cache_l2b" ]; then break; fi
    [ -n "$__bs_cache_oldest" ] || break
    bs_map_get_to cacheM "$__bs_cache_oldest" __bs_cache_pm || break
    __bs_cache_pid=$(bs_cache__meta_field "$__bs_cache_pm" 1)
    rm -f "${__bs_cache_dir}/v/${__bs_cache_pid}"
    bs_map_set cacheM "$__bs_cache_oldest" \
      "$(bs_cache__meta_field "$__bs_cache_pm" 1) $(bs_cache__meta_field "$__bs_cache_pm" 2) 3 $(bs_cache__meta_field "$__bs_cache_pm" 4) $(bs_cache__meta_field "$__bs_cache_pm" 5) $(bs_cache__meta_field "$__bs_cache_pm" 6) $(bs_cache__meta_field "$__bs_cache_pm" 7) $(bs_cache__meta_field "$__bs_cache_pm" 8)"
    bs_map_remove cacheV "$__bs_cache_oldest" || :
    bs_map_remove cacheF "$__bs_cache_oldest" || :
    __bs_cache_pn=$((__bs_cache_pn + 1))
  done
  # Бюджет L3: удаляем самые давно использованные записи целиком
  # L3 budget: remove the least recently used entries entirely
  while :; do
    __bs_cache_sum=0
    __bs_cache_oldest=''
    __bs_cache_oused=''
    bs_map_keys_to cacheM cachePruneKeys
    eval "$(bs_arr_to_args cachePruneKeys)"
    for __bs_cache_pk in "$@"; do
      bs_map_get_to cacheM "$__bs_cache_pk" __bs_cache_pm || continue
      __bs_cache_psz=$(bs_cache__meta_field "$__bs_cache_pm" 4)
      __bs_cache_pu=$(bs_cache__meta_field "$__bs_cache_pm" 8)
      __bs_cache_sum=$((__bs_cache_sum + __bs_cache_psz))
      if [ -z "$__bs_cache_oldest" ] || [ "$__bs_cache_pu" -lt "$__bs_cache_oused" ]; then
        __bs_cache_oldest=$__bs_cache_pk
        __bs_cache_oused=$__bs_cache_pu
      fi
    done
    if [ "$__bs_cache_sum" -le "$__bs_cache_l3b" ]; then break; fi
    [ -n "$__bs_cache_oldest" ] || break
    bs_cache_delete "$__bs_cache_oldest" || break
    __bs_cache_pn=$((__bs_cache_pn + 1))
  done
  bs_arr_clear cachePruneKeys
  printf '%s\n' "$__bs_cache_pn"
  bs_cache__save
}

# @description Статистика: записи по уровням, байты, попадания/промахи, бэкенд L3 /
#   Statistics: entries per level, bytes, hits/misses, the L3 backend
bs_cache_stats() {
  bs_cache__ensure || return $?
  __bs_cache_n1=0
  __bs_cache_n2=0
  __bs_cache_n3=0
  __bs_cache_bytes=0
  __bs_cache_hits=0
  bs_map_keys_to cacheM cacheStatKeys
  eval "$(bs_arr_to_args cacheStatKeys)"
  for __bs_cache_sk in "$@"; do
    bs_map_get_to cacheM "$__bs_cache_sk" __bs_cache_sm || continue
    __bs_cache_sl=$(bs_cache__meta_field "$__bs_cache_sm" 3)
    case "$__bs_cache_sl" in
      2) __bs_cache_n2=$((__bs_cache_n2 + 1)) ;;
      3) __bs_cache_n3=$((__bs_cache_n3 + 1)) ;;
    esac
    __bs_cache_bytes=$((__bs_cache_bytes + $(bs_cache__meta_field "$__bs_cache_sm" 4)))
    __bs_cache_hits=$((__bs_cache_hits + $(bs_cache__meta_field "$__bs_cache_sm" 7)))
  done
  bs_arr_clear cacheStatKeys
  __bs_cache_n1=$(bs_map_count cacheV)
  printf 'dir=%s\nl3=%s\nl1=%s\nl2=%s\nl3_entries=%s\nbytes=%s\nhits=%s\nmisses=%s\n' \
    "$__bs_cache_dir" "$__bs_cache_l3" "$__bs_cache_n1" "$__bs_cache_n2" "$__bs_cache_n3" \
    "$__bs_cache_bytes" "$__bs_cache_hits" "$__bs_cache_misses"
  return 0
}

# @description Манифест как есть (прозрачность: cat/grep) / The manifest as is (transparency: cat/grep)
bs_cache_list() {
  bs_cache__ensure || return $?
  if [ -f "${__bs_cache_dir}/manifest" ]; then
    cat "${__bs_cache_dir}/manifest"
  fi
  return 0
}

# CLI / bs cache

# @description Точка входа команды «bs cache» / The entry point of the "bs cache" command
# @param $@ subcommand and args / подкоманда и аргументы
bs_cache_main() {
  __bs_cache_cmd=${1:-stats}
  if [ $# -gt 0 ]; then shift; fi
  case "$__bs_cache_cmd" in
    help|-h|--help)
      printf '%s\n' \
        'Usage: bs cache <subcommand> [args]' \
        '' \
        '  stats                 уровни, байты, попадания / levels, bytes, hits' \
        '  list                  манифест как есть / the manifest as is' \
        '  get KEY [--fp F]      значение / the value' \
        '  put KEY VALUE [--fp F] [--ttl N]   положить / put' \
        '  delete KEY            удалить / remove' \
        '  prune                 просроченное + бюджеты / expired + budgets' \
        '  clear                 очистить всё / clear everything' \
        '' \
        'Dir: BS_CACHE_DIR or ${XDG_CACHE_HOME:-~/.cache}/bs/cache' \
        'L3: sqlite3 -> BS_STORE_BACKEND (C) -> files; budgets BS_CACHE_L2_BYTES / BS_CACHE_L3_BYTES'
      return 0 ;;
    stats)
      if [ $# -gt 0 ]; then printf 'bs cache stats: unexpected argument: %s\n' "$1" >&2; return 2; fi
      bs_cache_stats
      return $? ;;
    list)
      __bs_cache_out=$(bs_cache_list)
      if [ -z "$__bs_cache_out" ]; then
        printf '%s\n' \
          '╭──────────────────────────────────────────╮' \
          '│ Кеш пуст / CACHE EMPTY                   │' \
          '╰──────────────────────────────────────────╯' \
          '  записей нет / no entries' \
          '  далее / next: bs cache put KEY VALUE'
        return 0
      fi
      printf '%s\n' "$__bs_cache_out"
      return 0 ;;
    get)
      __bs_cache_key=''
      __bs_cache_fp=cli
      __bs_cache_ddash=0
      while [ $# -gt 0 ]; do
        case "$1" in
          --) __bs_cache_ddash=1; shift ;;
          --fp)
            if [ $# -lt 2 ]; then printf 'bs cache get: --fp needs a value\n' >&2; return 2; fi
            case "$2" in -*) printf 'bs cache get: --fp needs a value (use --fp=VALUE for a leading dash)\n' >&2; return 2 ;; esac
            __bs_cache_fp=$2; shift 2 ;;
          --fp=*) __bs_cache_fp=${1#--fp=}; shift ;;
          -*)
            if [ "$__bs_cache_ddash" = 1 ]; then
              if [ -n "$__bs_cache_key" ]; then printf 'bs cache get: unexpected argument: %s\n' "$1" >&2; return 2; fi
              __bs_cache_key=$1
            else
              printf 'bs cache get: unknown flag: %s\n' "$1" >&2; return 2
            fi
            shift ;;
          *)
            if [ -n "$__bs_cache_key" ]; then printf 'bs cache get: unexpected argument: %s\n' "$1" >&2; return 2; fi
            __bs_cache_key=$1; shift ;;
        esac
      done
      if [ -z "$__bs_cache_key" ]; then
        printf 'bs cache get: KEY required\n' >&2
        return 2
      fi
      if bs_cache_get "$__bs_cache_key" "$__bs_cache_fp"; then
        return 0
      else
        __bs_cache_grc=$?
      fi
      if [ "$__bs_cache_grc" = 2 ]; then return 2; fi
      printf 'bs cache: miss: %s\n' "$__bs_cache_key" >&2
      return 1 ;;
    put)
      __bs_cache_key=''
      __bs_cache_val=''
      __bs_cache_fp=cli
      __bs_cache_ttl=0
      __bs_cache_haveval=0
      __bs_cache_ddash=0
      while [ $# -gt 0 ]; do
        case "$1" in
          --) shift; __bs_cache_ddash=1 ;;
          --fp)
            if [ $# -lt 2 ]; then printf 'bs cache put: --fp needs a value\n' >&2; return 2; fi
            case "$2" in -*) printf 'bs cache put: --fp needs a value (use --fp=VALUE for a leading dash)\n' >&2; return 2 ;; esac
            __bs_cache_fp=$2; shift 2 ;;
          --fp=*) __bs_cache_fp=${1#--fp=}; shift ;;
          --ttl)
            if [ $# -lt 2 ]; then printf 'bs cache put: --ttl needs a value\n' >&2; return 2; fi
            case "$2" in -*) printf 'bs cache put: --ttl needs a value (use --ttl=VALUE)\n' >&2; return 2 ;; esac
            __bs_cache_ttl=$2; shift 2 ;;
          --ttl=*) __bs_cache_ttl=${1#--ttl=}; shift ;;
          -*)
            if [ "$__bs_cache_ddash" = 1 ]; then
              if [ -z "$__bs_cache_key" ]; then
                __bs_cache_key=$1
              elif [ "$__bs_cache_haveval" = 0 ]; then
                __bs_cache_val=$1
                __bs_cache_haveval=1
              else
                printf 'bs cache put: unexpected argument: %s\n' "$1" >&2; return 2
              fi
            else
              printf 'bs cache put: unknown flag: %s\n' "$1" >&2; return 2
            fi
            shift ;;
          *)
            if [ -z "$__bs_cache_key" ]; then
              __bs_cache_key=$1
            elif [ "$__bs_cache_haveval" = 0 ]; then
              __bs_cache_val=$1
              __bs_cache_haveval=1
            else
              printf 'bs cache put: unexpected argument: %s\n' "$1" >&2
              return 2
            fi
            shift ;;
        esac
      done
      if [ -z "$__bs_cache_key" ] || [ "$__bs_cache_haveval" != 1 ]; then
        printf 'bs cache put: KEY and VALUE required\n' >&2
        return 2
      fi
      if bs_cache_put "$__bs_cache_key" "$__bs_cache_fp" "$__bs_cache_val" "$__bs_cache_ttl"; then
        printf 'bs cache: put %s (fp=%s, ttl=%s)\n' "$__bs_cache_key" "$__bs_cache_fp" "$__bs_cache_ttl"
        return 0
      else
        return $?
      fi ;;
    delete)
      if [ $# -lt 1 ]; then
        printf 'bs cache delete: KEY required\n' >&2
        return 2
      fi
      if [ $# -gt 1 ]; then
        printf 'bs cache delete: unexpected argument: %s\n' "$2" >&2
        return 2
      fi
      if bs_cache_delete "$1"; then
        printf 'bs cache: deleted %s\n' "$1"
        return 0
      else
        __bs_cache_drc=$?
      fi
      if [ "$__bs_cache_drc" = 2 ]; then return 2; fi
      printf 'bs cache: no entry: %s\n' "$1" >&2
      return 1 ;;
    prune)
      if [ $# -gt 0 ]; then printf 'bs cache prune: unexpected argument: %s\n' "$1" >&2; return 2; fi
      bs_cache_prune
      return $? ;;
    clear)
      if [ $# -gt 0 ]; then printf 'bs cache clear: unexpected argument: %s\n' "$1" >&2; return 2; fi
      if bs_cache_clear; then
        printf 'bs cache: cleared\n'
        return 0
      else
        return $?
      fi ;;
    *)
      printf 'bs cache: unknown subcommand: %s (see: bs cache help)\n' "$__bs_cache_cmd" >&2
      return 2 ;;
  esac
}

# Псевдонимы cache::* — только в bash и zsh / The cache::* aliases — bash and zsh only
bs_shell_alias bs_cache_init cache::init
bs_shell_alias bs_cache_fp_files cache::fp_files
bs_shell_alias bs_cache_put cache::put
bs_shell_alias bs_cache_get cache::get
bs_shell_alias bs_cache_has cache::has
bs_shell_alias bs_cache_delete cache::delete
bs_shell_alias bs_cache_clear cache::clear
bs_shell_alias bs_cache_prune cache::prune
bs_shell_alias bs_cache_stats cache::stats
bs_shell_alias bs_cache_list cache::list
bs_shell_alias bs_cache_main cache::main
