#!/usr/bin/env bs
# shellcheck shell=bash
# examples/variable_metadata.sh — variable metadata + enforced store demo
# examples/variable_metadata.sh — демо метаданных переменных и принудительного хранилища
#
# Показывает слой метаданных (bs_var_*) и хранилище (bs_store_*): схемы,
# валидацию по @type/@range и запрет операций по @ops. Статусы: 0 ok, 1 нет
# значения, 2 плохое имя, 3 запрещено @ops, 4 значение не прошло валидацию.
# Shows the metadata layer (bs_var_*) and the store (bs_store_*): schemas,
# @type/@range validation and @ops enforcement. Statuses: 0 ok, 1 no value,
# 2 bad name, 3 denied by @ops, 4 failed validation.
#
# Попробуйте / Try it:
#   bs run examples/variable_metadata.sh
#
# Где живёт механика / Where the mechanics lives:
#   core/var.sh (метаданные), core/store.sh (хранилище), core/var-schema.sh
#   (сгенерированный манифест), scripts/gen_var_schema.sh и
#   scripts/check_var_contracts.sh (инструменты).

log() { printf '%s\n' "$1"; }

# --- Метаданные: валидация на записи / validation on write ---
bs_var_declare PORT 'type=port;ops=read,write;default=8080'
rc=0; bs_var_set PORT 9090  || rc=$?; log "set PORT 9090  -> rc=$rc"
rc=0; bs_var_set PORT 99999 || rc=$?; log "set PORT 99999 -> rc=$rc (вне 1..65535)"
printf 'get PORT -> %s\n' "$(bs_var_get PORT)"

# --- Хранилище: нет прямого $имя / no direct $name ---
bs_var_declare TTL 'type=int;ops=read,write,unset'
rc=0; bs_store_set TTL 30   || rc=$?; log "store set 30   -> rc=$rc"
printf 'store get -> %s\n' "$(bs_store_get TTL)"
rc=0; bs_store_set TTL nope || rc=$?; log "store set nope -> rc=$rc (не int)"

bs_var_declare TOKEN 'type=string;ops=write'
rc=0; bs_store_set TOKEN abc || rc=$?; log "store set TOKEN-> rc=$rc"
rc=0; bs_store_get TOKEN     || rc=$?; log "store get TOKEN-> rc=$rc (read запрещён)"

# --- Read-only константа / read-only constant ---
bs_var_declare K 'type=int;ops=read'
rc=0; bs_store_set K 7      || rc=$?;  log "store set K    -> rc=$rc (write запрещён)"

# --- Интроспекция / introspection ---
log "schema PORT = $(bs_var_schema PORT)"
log "schema TTL  = $(bs_var_schema TTL)"
