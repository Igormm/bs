#!/usr/bin/env bs
# shellcheck shell=bash
# lib/api/openapi.sh — OpenAPI 3.x client: load spec, introspect, call operations
# lib/api/openapi.sh — OpenAPI 3.x клиент: загрузка схемы, интроспекция, вызов операций

# @depends core/lang, core/const, core/logger, core/utils, lib/rfc/uri, lib/integration/http
# @tier gnu-linux

bs::guard "LIB_API_OPENAPI" || return 0

bs::source_relative "../../core/lang.sh" "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "../rfc/uri.sh" "../integration/http.sh"

# ==========================================
# OpenAPI client / OpenAPI-клиент
#
# Dynamic interpreter of an OpenAPI 3.x document: the spec is parsed on
# demand with jq, operations are called through lib/integration/http.
# Parameters are classified automatically by the spec location
# (path/query/header/body) — the caller just passes --name VALUE.
# Динамический интерпретатор документа OpenAPI 3.x: схема разбирается
# на лету через jq, операции выполняются через lib/integration/http.
# Параметры классифицируются автоматически по местоположению в схеме
# (path/query/header/body) — вызывающий передаёт просто --name VALUE.
#
#   api::spec::load petstore --from ./openapi.json
#   api::paths petstore
#   api::call petstore GET /pets --limit 10 --json
# ==========================================

# Loaded specs: name -> spec file path / Загруженные схемы: имя -> путь
declare -gA API_SPECS=()
# Auth tokens: name -> token / Токены: имя -> токен
declare -gA API_SPEC_AUTH=()
# Cache dir for specs fetched from URLs / Кэш для схем, скачанных по URL
declare -g API_SPEC_CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/bs/api"

# @description Load an OpenAPI spec from a file or URL.
# @description Загрузить OpenAPI-схему из файла или URL.
# @param $1 spec name / имя схемы
# @param $2 source: file path or URL / источник: путь или URL
# @return 0 ok, 1 invalid spec, 2 download failed
api::spec::load() {
  local -r name="${1:?spec name required}"
  local -r source="${2:?spec source required (file or URL)}"

  local spec_file="${source}"
  if [[ "${source}" =~ ^https?:// ]]; then
    mkdir -p -- "${API_SPEC_CACHE_DIR}" || return 1
    spec_file="${API_SPEC_CACHE_DIR}/${name}.json"
    if ! http::download "${source}" "${spec_file}" --timeout 30; then
      log::error "api::spec::load: failed to download spec: ${source} (check URL and network)"
      return 2
    fi
    log::info "api::spec::load: cached ${source} -> ${spec_file}"
  fi

  if ! is::file "${spec_file}"; then
    log::error "api::spec::load: spec file not found: ${spec_file} (pass a file path or https:// URL)"
    return 1
  fi

  # Проверка, что это OpenAPI 3.x / Verify it is an OpenAPI 3.x document
  if ! jq -e '.openapi | startswith("3.")' "${spec_file}" >/dev/null 2>&1; then
    log::error "api::spec::load: not an OpenAPI 3.x document: ${spec_file} (field \".openapi\" must start with 3.)"
    return 1
  fi

  API_SPECS["${name}"]="${spec_file}"
  API_SPEC_AUTH["${name}"]=""
  log::debug "api::spec::load: loaded ${name} from ${spec_file}"
  return 0
}

# @description Unload a spec / Выгрузить схему из памяти.
# @param $1 spec name / имя схемы
# @return 0 ok, 1 not loaded
api::spec::drop() {
  local -r name="${1:?spec name required}"
  if [[ -z "${API_SPECS[${name}]+x}" ]]; then
    log::warn "api::spec::drop: spec '${name}' is not loaded"
    return 1
  fi
  unset "API_SPECS[${name}]" "API_SPEC_AUTH[${name}]"
  return 0
}

# @description Set an auth token for a spec (sent as Bearer).
# @description Установить токен авторизации для схемы (отправляется как Bearer).
# @param $1 spec name / имя схемы
# @param $2 token / токен
api::spec::auth() {
  local -r name="${1:?spec name required}"
  local -r token="${2-}"
  if [[ -z "${API_SPECS[${name}]+x}" ]]; then
    log::error "api::spec::auth: spec '${name}' is not loaded (api::spec::load ${name} --from FILE)"
    return 1
  fi
  API_SPEC_AUTH["${name}"]="${token}"
  return 0
}

# @description List loaded specs / Список загруженных схем.
api::spec::list() {
  local name
  if (( ${#API_SPECS[@]} == 0 )); then
    printf 'No specs loaded / Схемы не загружены\n'
    return 0
  fi
  for name in "${!API_SPECS[@]}"; do
    printf '%-20s %s\n' "${name}" "${API_SPECS[${name}]}"
  done
  return 0
}

# @description Show spec info: title, version, server.
# @description Показать информацию о схеме: заголовок, версия, сервер.
# @param $1 spec name / имя схемы
api::spec::info() {
  local -r name="${1:?spec name required}"
  api::__spec_file "${name}" || return 1
  local -r file="${API_SPECS[${name}]}"
  jq -r '"\(.info.title // "untitled") \(.info.version // "") — \(.servers[0].url // "")"' "${file}"
  return 0
}

# @description List operations of a spec: METHOD path — summary.
# @description Список операций схемы: METHOD path — summary.
# @param $1 spec name / имя схемы
# @param $2 [--method METHOD] filter by HTTP method / фильтр по методу
api::paths() {
  local -r name="${1:?spec name required}"
  local method_filter=""
  shift
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      --method)
        method_filter="${2-}"
        shift 2 ;;
      *)
        log::error "api::paths: unknown argument: ${1} (only --method METHOD is supported)"
        return "${E_INVALID}" ;;
    esac
  done
  api::__spec_file "${name}" || return 1
  local -r file="${API_SPECS[${name}]}"

  local line
  while IFS= read -r line; do
    printf '%-6s %s\n' "${line%%$'\t'*}" "${line#*$'\t'}"
  done < <(
    jq -r '
      .paths | to_entries[] |
      .key as $path |
      .value | to_entries[] |
      select(.key == "get" or .key == "post" or .key == "put" or
             .key == "patch" or .key == "delete" or .key == "head" or
             .key == "options" or .key == "trace") |
      (.key | ascii_upcase) as $method |
      select(($method | if "'"${method_filter}"'" == "" then true else . == ("'"${method_filter}"'" | ascii_upcase) end)) |
      [$method, $path, (.value.summary // .value.operationId // "")] | @tsv
    ' "${file}"
  )
  return 0
}

# @description Call an OpenAPI operation.
# @description Вызвать операцию OpenAPI.
# @param $1 spec name / имя схемы
# @param $2 HTTP method / HTTP-метод
# @param $3 path template, e.g. /pets/{petId} / шаблон пути
# @param $@ parameters: --name VALUE for each, --body JSON, --token T, --json
# @stdout response body (raw with --json, pretty-printed otherwise) / тело ответа
# @return 0 ok, 1 validation/spec error, 4 HTTP error
api::call() {
  local -r name="${1:?spec name required}"
  local -r method="$(printf '%s' "${2:?HTTP method required}" | tr '[:lower:]' '[:upper:]')"
  local -r path_tpl="${3:?path required, e.g. /pets/<petId>}"
  shift 3

  api::__spec_file "${name}" || return 1
  local -r file="${API_SPECS[${name}]}"

  local json_mode=0
  local token="${API_SPEC_AUTH[${name}]:-}"
  local body=""
  local -A values=()
  local -a order=()

  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      --json)
        json_mode=1
        shift ;;
      --token)
        token="${2-}"
        shift 2 ;;
      --body)
        body="${2-}"
        shift 2 ;;
      --*)
        local pname="${1#--}"
        if [[ $# -lt 2 ]]; then
          log::error "api::call: missing value for --${pname} (pass: --${pname} VALUE)"
          return 1
        fi
        values["${pname}"]="${2}"
        order+=("${pname}")
        shift 2 ;;
      *)
        log::error "api::call: unknown argument: ${1} (pass parameters as --name VALUE)"
        return 1 ;;
    esac
  done

  # Проверка обязательных / Required check
  local -a missing=()
  local p_name p_in p_req
  while IFS=$'\t' read -r p_name p_in p_req; do
    if [[ "${p_req}" == "true" ]] && [[ -z "${values[${p_name}]+x}" ]] && [[ -z "${body}" || "${p_in}" != "body" ]]; then
      missing+=("${p_name} (${p_in})")
    fi
  done < <(api::__params "${file}" "${path_tpl}" "${method}")
  if (( ${#missing[@]} > 0 )); then
    log::error "api::call: missing required parameter(s): ${missing[*]} (pass: --${missing[0]%% (*} VALUE)"
    return 1
  fi

  # Сборка URL / Build the URL
  local base
  base="$(jq -r '.servers[0].url // ""' "${file}")"
  local path="${path_tpl}"
  local -a query_parts=()
  local -a headers=()
  local p_where=""

  for p_name in "${order[@]}"; do
    p_where="$(api::__param_location "${file}" "${path_tpl}" "${method}" "${p_name}")"
    case "${p_where}" in
      path)
        path="${path//\{${p_name}\}/$(uri::encode "${values[${p_name}]}")}" ;;
      query)
        query_parts+=("${p_name}=$(uri::encode "${values[${p_name}]}")") ;;
      header)
        headers+=("--header" "${p_name}: ${values[${p_name}]}") ;;
      body)
        body="${values[${p_name}]}" ;;
      "")
        log::error "api::call: unknown parameter for ${method} ${path_tpl}: --${p_name} (see: api::paths ${name})"
        return 1 ;;
    esac
  done

  local url="${base}${path}"
  if (( ${#query_parts[@]} > 0 )); then
    local IFS='&'
    url+="?${query_parts[*]}"
  fi
  if is::not_empty "${token}"; then
    headers+=("--header" "Authorization: Bearer ${token}")
  fi
  if is::not_empty "${body}"; then
    headers+=("--data" "${body}")
  fi

  log::debug "api::call: ${method} ${url} (spec: ${name})"

  local rc=0
  local response
  response="$(http::request "${method}" "${url}" "${headers[@]}")" || rc=$?

  if (( rc != 0 )); then
    log::error "api::call: HTTP ${method} ${url} failed (rc=${rc}) — check network, token (--token / api::spec::auth) and server"
    if (( json_mode == 1 )); then
      printf '%s\n' "${response}"
    fi
    return 4
  fi

  if (( json_mode == 1 )); then
    printf '%s\n' "${response}"
  elif printf '%s' "${response}" | jq -e . >/dev/null 2>&1; then
    printf '%s' "${response}" | jq .
  else
    printf '%s\n' "${response}"
  fi
  return 0
}

# @private
# @description Resolve the spec file or fail with a hint.
# @description Найти файл схемы или упасть с подсказкой.
# @param $1 spec name
api::__spec_file() {
  local -r name="$1"
  if [[ -z "${API_SPECS[${name}]+x}" ]] || ! is::file "${API_SPECS[${name}]}"; then
    log::error "api::__spec_file: spec '${name}' is not loaded (api::spec::load ${name} --from FILE-or-URL)"
    return 1
  fi
  return 0
}

# @private
# @description Operation parameters as TSV: name, in, required / true.
# @description Параметры операции как TSV: имя, расположение, required.
api::__params() {
  local -r file="$1" path_tpl="$2" method="$3"
  jq -r '
    ( .paths["'"${path_tpl}"'"].parameters // [] ) as $path_params |
    ( .paths["'"${path_tpl}"'"]["'"${method,,}"'"].parameters // [] ) as $op_params |
    ($path_params + $op_params)[] |
    [.name, .in, (.required // false | tostring)] | @tsv
  ' "${file}"
}

# @private
# @description Parameter location in the spec: path/query/header/body.
# @description Расположение параметра в схеме: path/query/header/body.
api::__param_location() {
  local -r file="$1" path_tpl="$2" method="$3" p_name="$4"
  jq -r '
    ( .paths["'"${path_tpl}"'"].parameters // [] ) as $path_params |
    ( .paths["'"${path_tpl}"'"]["'"${method,,}"'"].parameters // [] ) as $op_params |
    (($path_params + $op_params)[] | select(.name == "'"${p_name}"'") | .in) // ""
  ' "${file}"
}