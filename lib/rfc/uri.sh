#!/usr/bin/env bs
# shellcheck shell=bash
# lib/rfc/uri.sh — RFC 3986: Uniform Resource Identifier (URI) parsing
# lib/rfc/uri.sh — RFC 3986: разбор URI

# @depends core/lang

# Source Guard
bs::guard "LIB_RFC_URI" || return 0

# Dependencies
bs::source_relative "../../core/lang.sh"

# ==========================================
# RFC 3986 — URI / URI
#
# Parses: scheme://user:pass@host:port/path?query#fragment
# per RFC 3986 (IPv6 hosts in [brackets], percent-encoding).
# Sets variables with a prefix (default URI_): URI_SCHEME, URI_USER,
# URI_PASSWORD, URI_HOST, URI_PORT, URI_PATH, URI_QUERY, URI_FRAGMENT.
# Разбирает: scheme://user:pass@host:port/path?query#fragment по RFC 3986
# (IPv6-хосты в [скобках], процент-кодирование). Устанавливает переменные
# с префиксом (по умолчанию URI_): URI_SCHEME, URI_USER, URI_PASSWORD,
# URI_HOST, URI_PORT, URI_PATH, URI_QUERY, URI_FRAGMENT.
# ==========================================

# @description Parse a URI into variables with the given prefix.
# @description Разобрать URI в переменные с заданным префиксом.
#   Components are kept RAW (percent-encoding preserved); use uri::decode
#   to decode. Компоненты сохраняются СЫРЫМИ (процент-кодирование не
#   снимается); для декодирования используйте uri::decode.
# @param $1 URI string / Строка URI
# @param $2 [optional] Variable prefix, default URI_ / Префикс переменных
# @return 0 ok, 1 empty input
# @example
#   uri::parse "https://user:pw@example.com:8080/a/b?x=1#f"
#   echo "${URI_HOST}:${URI_PORT} ${URI_PATH}"   # example.com:8080 /a/b
uri::parse() {
  local -r __ur_input="${1-}"
  local -r __ur_prefix="${2:-URI_}"
  is::not_empty "${__ur_input}" || return 1

  local __ur_rest="${__ur_input}"
  local __ur_scheme="" __ur_user="" __ur_password="" __ur_host="" __ur_port=""
  local __ur_path="" __ur_query="" __ur_fragment=""

  # fragment / фрагмент
  if [[ "${__ur_rest}" == *"#"* ]]; then
    __ur_fragment="${__ur_rest#*#}"
    __ur_rest="${__ur_rest%%#*}"
  fi
  # query / запрос
  if [[ "${__ur_rest}" == *"?"* ]]; then
    __ur_query="${__ur_rest#*\?}"
    __ur_rest="${__ur_rest%%\?*}"
  fi
  # scheme / схема
  if [[ "${__ur_rest}" =~ ^([A-Za-z][A-Za-z0-9+.-]*):(.*)$ ]]; then
    __ur_scheme="${BASH_REMATCH[1]}"
    __ur_rest="${BASH_REMATCH[2]}"
  fi
  # authority + path / владелец + путь
  if [[ "${__ur_rest}" == //* ]]; then
    __ur_rest="${__ur_rest#//}"
    local __ur_authority
    if [[ "${__ur_rest}" == *"/"* ]]; then
      __ur_authority="${__ur_rest%%/*}"
      __ur_path="/${__ur_rest#*/}"
    else
      __ur_authority="${__ur_rest}"
      __ur_path=""
    fi
    # userinfo
    local __ur_auth="${__ur_authority}"
    if [[ "${__ur_auth}" == *"@"* ]]; then
      local __ur_userinfo="${__ur_auth%%@*}"
      __ur_auth="${__ur_auth#*@}"
      if [[ "${__ur_userinfo}" == *":"* ]]; then
        __ur_user="${__ur_userinfo%%:*}"
        __ur_password="${__ur_userinfo#*:}"
      else
        __ur_user="${__ur_userinfo}"
      fi
    fi
    # host:port (IPv6 в скобках / IPv6 in brackets)
    if [[ "${__ur_auth}" == \[*\]* ]]; then
      __ur_host="${__ur_auth%%]*}"
      __ur_host="${__ur_host#[}"
      local __ur_after="${__ur_auth#*]}"
      if [[ "${__ur_after}" == :* ]]; then
        __ur_port="${__ur_after#:}"
      fi
    else
      if [[ "${__ur_auth}" == *":"* ]]; then
        __ur_host="${__ur_auth%%:*}"
        __ur_port="${__ur_auth#*:}"
      else
        __ur_host="${__ur_auth}"
      fi
    fi
  else
    __ur_path="${__ur_rest}"
  fi

  printf -v "${__ur_prefix}SCHEME"    "%s" "${__ur_scheme}"
  printf -v "${__ur_prefix}USER"      "%s" "${__ur_user}"
  printf -v "${__ur_prefix}PASSWORD"  "%s" "${__ur_password}"
  printf -v "${__ur_prefix}HOST"      "%s" "${__ur_host}"
  printf -v "${__ur_prefix}PORT"      "%s" "${__ur_port}"
  printf -v "${__ur_prefix}PATH"      "%s" "${__ur_path}"
  printf -v "${__ur_prefix}QUERY"     "%s" "${__ur_query}"
  printf -v "${__ur_prefix}FRAGMENT"  "%s" "${__ur_fragment}"
  return 0
}

# @description Print parsed URI components as key=value lines.
# @description Вывести компоненты URI как строки ключ=значение.
# @param $1 URI string / Строка URI
# @param $2 [optional] Variable prefix / Префикс переменных
# @stdout one "KEY=VALUE" per line / по строке "KEY=VALUE"
# @example
#   uri::dump "https://example.com:8443/app?q=2"
#   # SCHEME=https  HOST=example.com  PORT=8443  PATH=/app  QUERY=q=2
uri::dump() {
  uri::parse "$@" || return 1
  local -r __ur_prefix="${2:-URI_}"
  local __ur_key __ur_name
  for __ur_key in SCHEME USER PASSWORD HOST PORT PATH QUERY FRAGMENT; do
    __ur_name="${__ur_prefix}${__ur_key}"
    printf '%s=%s\n' "${__ur_key}" "${!__ur_name}"
  done
}

# @description Percent-decode a string (RFC 3986 §2.1).
# @description Процент-декодировать строку (RFC 3986 §2.1).
# @param $1 String / Строка
# @stdout decoded string / декодированная строка
# @example
#   uri::decode "hello%20world%21"    # hello world!
uri::decode() {
  local __ur_s="${1-}" __ur_out="" __ur_hex __ur_c
  while [[ "${__ur_s}" == *%* ]]; do
    __ur_out+="${__ur_s%%\%*}"
    __ur_s="${__ur_s#*\%}"
    __ur_hex="${__ur_s:0:2}"
    if [[ "${__ur_hex}" =~ ^[0-9A-Fa-f]{2}$ ]]; then
      printf -v __ur_c "\\x${__ur_hex}"
      __ur_out+="${__ur_c}"
      __ur_s="${__ur_s:2}"
    else
      __ur_out+="%${__ur_hex}"
      __ur_s="${__ur_s:2}"
    fi
  done
  __ur_out+="${__ur_s}"
  printf '%s' "${__ur_out}"
}

# @description Percent-encode a string (RFC 3986 unreserved only).
# @description Процент-кодировать строку (RFC 3986: только unreserved).
#   Bytes are iterated in the C locale — multibyte UTF-8 is encoded byte
#   by byte. Кодируются байты (locale C) — мультибайтный UTF-8 побайтово.
# @param $1 String / Строка
# @stdout encoded string / закодированная строка
# @example
#   uri::encode "a b/c"    # a%20b%2Fc
uri::encode() {
  local __ur_s="${1-}" __ur_out="" __ur_c __ur_hex
  local -i __ur_i
  local LC_ALL=C
  for (( __ur_i = 0; __ur_i < ${#__ur_s}; __ur_i++ )); do
    __ur_c="${__ur_s:__ur_i:1}"
    case "${__ur_c}" in
      [A-Za-z0-9_.~-])
        __ur_out+="${__ur_c}" ;;
      *)
        printf -v __ur_hex '%%%02X' "'${__ur_c}"
        __ur_out+="${__ur_hex}" ;;
    esac
  done
  printf '%s' "${__ur_out}"
}