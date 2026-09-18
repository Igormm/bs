#!/usr/bin/env bs
# shellcheck shell=bash
# lib/rfc/uuid.sh — RFC 4122 / RFC 9562: UUID generation
# lib/rfc/uuid.sh — RFC 4122 / RFC 9562: генерация UUID

# @depends core/lang

# Source Guard
bs::guard "LIB_RFC_UUID" || return 0

# Dependencies
bs::source_relative "../../core/lang.sh"

# ==========================================
# RFC 4122 / RFC 9562 — UUID
#
# uuid::gen        — version 4 (random) / версия 4 (случайный)
# uuid::gen_v7     — version 7 (time-ordered, RFC 9562) / версия 7
# uuid::validate   — format + version check / проверка формата и версии
# Randomness: /dev/urandom via od (POSIX); $RANDOM fallback.
# Случайность: /dev/urandom через od (POSIX); fallback на $RANDOM.
# ==========================================

# @private
# @description N hex characters from /dev/urandom.
# @description N hex-символов из /dev/urandom.
# @param $1 Count / Количество
# @stdout hex string / hex-строка
uuid::__rand_hex() {
  local -r __uu_n="$1"
  if [[ -r /dev/urandom ]]; then
    od -An -N "$(( (__uu_n + 1) / 2 ))" -tx1 /dev/urandom 2>/dev/null \
      | tr -d ' \n' | head -c "${__uu_n}"
    printf '\n'
  else
    local __uu_out="" __uu_r
    while [[ ${#__uu_out} -lt __uu_n ]]; do
      printf -v __uu_r '%04x' "$(( RANDOM ))"
      __uu_out+="${__uu_r}"
    done
    printf '%s\n' "${__uu_out:0:__uu_n}"
  fi
}

# @description Generate a version-4 UUID (random, RFC 4122 §4.4).
# @description Сгенерировать UUID версии 4 (случайный, RFC 4122 §4.4).
# @stdout UUID string / строка UUID
# @example
#   uuid::gen    # e.g. 0f8fad5b-d9cb-469f-a165-70867728950e
uuid::gen() {
  local __uu_hex __uu_variant
  __uu_hex="$(uuid::__rand_hex 32)"
  printf -v __uu_variant '%x' "$(( 8 + (0x${__uu_hex:16:1}) % 4 ))"
  printf '%s-%s-%s-%s-%s\n' \
    "${__uu_hex:0:8}" \
    "${__uu_hex:8:4}" \
    "4${__uu_hex:13:3}" \
    "${__uu_variant}${__uu_hex:17:3}" \
    "${__uu_hex:20:12}"
}

# @description Generate a version-7 UUID (time-ordered, RFC 9562 §5.7).
# @description Сгенерировать UUID версии 7 (упорядочен по времени, RFC 9562).
#   48-bit Unix-ms timestamp + random tail. Requires GNU date (%3N).
#   48-битная метка Unix-ms + случайный хвост. Требует GNU date (%3N).
# @stdout UUID string / строка UUID
# @example
#   uuid::gen_v7
uuid::gen_v7() {
  local __uu_ts __uu_hex __uu_variant
  __uu_ts="$(date +%s%3N 2>/dev/null || printf '%s000' "$(date +%s)")"
  __uu_ts="$(printf '%012x' "$(( 10#${__uu_ts} ))" 2>/dev/null || printf '%012x' 0)"
  __uu_hex="$(uuid::__rand_hex 20)"
  printf -v __uu_variant '%x' "$(( 8 + (0x${__uu_hex:3:1}) % 4 ))"
  printf '%s-%s-%s-%s-%s\n' \
    "${__uu_ts:0:8}" \
    "${__uu_ts:8:4}" \
    "7${__uu_hex:0:3}" \
    "${__uu_variant}${__uu_hex:4:3}" \
    "${__uu_hex:7:12}"
}

# @description Validate a UUID string (RFC 4122 §3 format).
# @description Проверить строку UUID (формат RFC 4122 §3).
# @param $1 UUID string / Строка UUID
# @param $2 [optional] Expected version 4/7 (any if omitted)
#        Ожидаемая версия 4/7 (любая, если не задана)
# @return 0 valid, 1 invalid
# @example
#   uuid::validate "$(uuid::gen)" && echo ok
uuid::validate() {
  local -r __uu_uuid="${1-}"
  local -r __uu_ver="${2-}"
  [[ "${__uu_uuid}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || return 1
  if is::not_empty "${__uu_ver}"; then
    [[ "${__uu_uuid:14:1}" == "${__uu_ver}" ]] || return 1
  fi
  return 0
}