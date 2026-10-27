#!/usr/bin/env bs
# shellcheck shell=bash
# examples/store_c_backend.sh — optional C backend (persistent store) demo
# examples/store_c_backend.sh — демо опционального C backend (персистентное хранилище)
#
# bs_store по умолчанию держит значения в памяти процесса. C backend
# (libexec/bs-store.c + scripts/build_store_helper.sh) кладёт их в файл, так
# что значение переживает процесс. Схема/@ops/валидация остаются в shell —
# C хранит только значения.
# bs_store keeps values in the process memory by default. The C backend
# (libexec/bs-store.c + scripts/build_store_helper.sh) puts them in a file, so
# the value survives the process. The schema/@ops/validation stay in the
# shell — C stores values only.
#
# Попробуйте / Try it:
#   bs run examples/store_c_backend.sh
#
# Ограничение: значение без перевода строки (протокол — по строке).
# Limitation: no newline in a value (the protocol is line-based).

log() { printf '%s\n' "$1"; }

backend="$(sh scripts/build_store_helper.sh 2>/dev/null || true)"
if [ -z "$backend" ]; then
  log 'no C compiler — using the in-memory store / нет компилятора — хранилище в памяти'
fi
file="${BS_STORE_FILE:-"${HOME}/.cache/bs/example.db"}"

if [ -n "$backend" ]; then
  # 1. Протокол бинарника напрямую / the binary protocol directly
  printf '41\n' | "$backend" set "$file" TTL
  log "direct get  -> $("$backend" get "$file" TTL)"
  log "direct list -> $("$backend" list "$file")"

  # 2. Тот же файл — через bs_store / the same file through bs_store
  export BS_STORE_BACKEND="$backend"
  export BS_STORE_FILE="$file"
  bs_var_declare TTL 'type=int;ops=read,write,unset'
  rc=0; bs_store_set TTL 77 || rc=$?; log "store set 77 -> rc=$rc"
  printf 'store get -> %s (переживёт процесс / survives the process)\n' "$(bs_store_get TTL)"

  # В другом процессе, с теми же BS_STORE_BACKEND и BS_STORE_FILE:
  #   bs_store_get TTL   # 77
  # In another process, with the same BS_STORE_BACKEND and BS_STORE_FILE:
  #   bs_store_get TTL   # 77
fi
