#!/usr/bin/env bs
# shellcheck shell=bash
# lib/io/tree.sh — create a project file tree from yaml/yml/txt/ini/csv
# lib/io/tree.sh — создать дерево файлов проекта из yaml/yml/txt/ini/csv
# @depends core/const, core/logger, core/utils, core/lang, core/errorhandler, lib/io/files, lib/rfc/csv

# Source Guard
bs::guard "IO_TREE" || return 0

# Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" \
  "../../core/utils.sh" "../../core/lang.sh" \
  "../../core/errorhandler.sh" "files.sh" "../rfc/csv.sh"

# shellcheck disable=SC2034
declare -g IO_TREE_VERSION="1.0.0"
# shellcheck disable=SC2034
declare -g IO_TREE_LOADED="1"

# Canonical entries / Канонические записи
declare -ga IO_TREE_KIND=()
declare -ga IO_TREE_PATH=()
declare -ga IO_TREE_BODY=()
declare -g IO_TREE_DRY_RUN=0
declare -g IO_TREE_FORCE=0

# ==========================================
# Safety / Безопасность
# ==========================================

# @private
# @description Normalize a relative path; reject traversal.
# @description Нормализовать относительный путь; запретить обход.
# @param $1 Path / Путь
# @stdout normalized relative path / нормализованный путь
# @return 0 ok, 1 unsafe or empty (root)
io::tree::__norm_rel() {
  local __tr_raw="${1-}"
  __tr_raw="${__tr_raw//\\//}"
  __tr_raw="${__tr_raw#./}"
  while [[ "${__tr_raw}" == ./* ]]; do
    __tr_raw="${__tr_raw#./}"
  done
  __tr_raw="${__tr_raw%/}"
  while [[ "${__tr_raw}" == *//* ]]; do
    __tr_raw="${__tr_raw//\/\//\/}"
  done
  is::not_empty "${__tr_raw}" || return 1
  [[ "${__tr_raw}" != /* ]] || return 1
  local __tr_rest="${__tr_raw}"
  local __tr_part
  while [[ "${__tr_rest}" == */* ]]; do
    __tr_part="${__tr_rest%%/*}"
    __tr_rest="${__tr_rest#*/}"
    [[ "${__tr_part}" != "." && "${__tr_part}" != ".." ]] || return 1
    is::not_empty "${__tr_part}" || return 1
  done
  [[ "${__tr_rest}" != "." && "${__tr_rest}" != ".." ]] || return 1
  is::not_empty "${__tr_rest}" || return 1
  printf '%s\n' "${__tr_raw}"
  return 0
}

# @private
# @description Join dest root and relative path.
# @description Склеить корень назначения и относительный путь.
io::tree::__join() {
  local -r __tr_root="${1:?}"
  local -r __tr_rel="${2-}"
  if is::empty "${__tr_rel}"; then
    printf '%s\n' "${__tr_root}"
    return 0
  fi
  printf '%s/%s\n' "${__tr_root%/}" "${__tr_rel}"
}

# @private
# @description Add a canonical entry (last write wins on same path).
# @description Добавить каноническую запись (последняя побеждает).
# @param $1 Kind d|f / Тип
# @param $2 Relative path / Относительный путь
# @param $3 [optional] File body / Тело файла
io::tree::__add() {
  local -r __tr_kind="${1:?}"
  local __tr_rel
  __tr_rel="$(io::tree::__norm_rel "${2-}")" || {
    error::throw "unsafe tree path: ${2-}" "${E_INVALID}"
    return "${E_INVALID}"
  }
  local -r __tr_body="${3-}"
  local -i __tr_i
  for (( __tr_i = 0; __tr_i < ${#IO_TREE_PATH[@]}; __tr_i++ )); do
    if [[ "${IO_TREE_PATH[__tr_i]}" == "${__tr_rel}" ]]; then
      IO_TREE_KIND[__tr_i]="${__tr_kind}"
      IO_TREE_BODY[__tr_i]="${__tr_body}"
      return 0
    fi
  done
  IO_TREE_KIND+=("${__tr_kind}")
  IO_TREE_PATH+=("${__tr_rel}")
  IO_TREE_BODY+=("${__tr_body}")
  return 0
}

# @private
# @description Strip tree(1) drawing characters.
# @description Убрать символы отрисовки tree(1).
io::tree::__strip_art() {
  local __tr_s="${1-}"
  __tr_s="${__tr_s//├── /}"
  __tr_s="${__tr_s//└── /}"
  __tr_s="${__tr_s//│   /}"
  __tr_s="${__tr_s//│ /}"
  __tr_s="${__tr_s//|-- /}"
  __tr_s="${__tr_s//\`-- /}"
  __tr_s="${__tr_s//|   /}"
  printf '%s\n' "${__tr_s}"
}

# @private
# @description Count leading spaces (tab = 2).
# @description Посчитать ведущие пробелы (таб = 2).
io::tree::__indent() {
  local __tr_s="${1-}"
  local -i __tr_n=0
  local __tr_c
  while (( ${#__tr_s} > 0 )); do
    __tr_c="${__tr_s:0:1}"
    case "${__tr_c}" in
      ' ') __tr_n=$(( __tr_n + 1 )) ;;
      $'\t') __tr_n=$(( __tr_n + 2 )) ;;
      *) break ;;
    esac
    __tr_s="${__tr_s:1}"
  done
  printf '%s\n' "${__tr_n}"
}

# @private
# @description Unquote a scalar ("..." or '...').
# @description Снять кавычки со скаляра.
io::tree::__unquote() {
  local __tr_s="${1-}"
  if [[ "${#__tr_s}" -ge 2 ]]; then
    if [[ "${__tr_s}" == \"*\" ]]; then
      __tr_s="${__tr_s:1:${#__tr_s}-2}"
      __tr_s="${__tr_s//\\\"/\"}"
    elif [[ "${__tr_s}" == \'*\' ]]; then
      __tr_s="${__tr_s:1:${#__tr_s}-2}"
    fi
  fi
  printf '%s\n' "${__tr_s}"
}

# ==========================================
# Detect / Определение формата
# ==========================================

# @description Detect spec format from path and content.
# @description Определить формат спецификации по пути и содержимому.
# @param $1 File path / Путь к файлу
# @stdout yaml|yml|txt|ini|csv
# @return 0 ok, E_INVALID empty path, LIB_ERROR_FILE_NOT_FOUND missing
io::tree::detect() {
  local -r __tr_file="${1-}"
  if is::empty "${__tr_file}"; then
    error::throw "spec path required" "${E_INVALID}"
    return "${E_INVALID}"
  fi
  if ! is::file "${__tr_file}"; then
    error::throw "spec not found: ${__tr_file}" \
      "${LIB_ERROR_FILE_NOT_FOUND}"
    return "${LIB_ERROR_FILE_NOT_FOUND}"
  fi
  local __tr_base="${__tr_file##*/}"
  local __tr_ext="${__tr_base##*.}"
  __tr_ext="${__tr_ext,,}"
  case "${__tr_ext}" in
    yaml|yml|ini|csv|txt)
      printf '%s\n' "${__tr_ext}"
      return 0
      ;;
  esac
  local __tr_line __tr_first=""
  while IFS= read -r __tr_line || [[ -n "${__tr_line}" ]]; do
    __tr_line="$(str::trim "${__tr_line}")"
    [[ "${__tr_line}" == \#* ]] && continue
    is::not_empty "${__tr_line}" || continue
    __tr_first="${__tr_line}"
    break
  done < "${__tr_file}"
  if [[ "${__tr_first}" == \[* ]]; then
    printf 'ini\n'
  elif [[ "${__tr_first}" == *,* ]]; then
    printf 'csv\n'
  elif [[ "${__tr_first}" == *: ]]; then
    printf 'yaml\n'
  else
    printf 'txt\n'
  fi
  return 0
}

# ==========================================
# Parse / Разбор
# ==========================================

# @description Clear parsed entries.
# @description Очистить разобранные записи.
io::tree::reset() {
  IO_TREE_KIND=()
  IO_TREE_PATH=()
  IO_TREE_BODY=()
  return 0
}

# @description Dump kind and path, one entry per line.
# @description Вывести тип и путь, по записи на строку.
# @stdout "kind<TAB>path"
io::tree::dump() {
  local -i __tr_i
  for (( __tr_i = 0; __tr_i < ${#IO_TREE_PATH[@]}; __tr_i++ )); do
    printf '%s\t%s\n' "${IO_TREE_KIND[__tr_i]}" \
      "${IO_TREE_PATH[__tr_i]}"
  done
  return 0
}

# @description Parse a spec file into IO_TREE_* arrays.
# @description Разобрать файл спецификации в массивы IO_TREE_*.
# @param $1 Spec path / Путь к спецификации
# @param $2 [optional] Format override / Принудительный формат
io::tree::parse() {
  local -r __tr_file="${1-}"
  local __tr_fmt="${2-}"
  if is::empty "${__tr_file}"; then
    error::throw "spec path required" "${E_INVALID}"
    return "${E_INVALID}"
  fi
  if ! is::file "${__tr_file}"; then
    error::throw "spec not found: ${__tr_file}" \
      "${LIB_ERROR_FILE_NOT_FOUND}"
    return "${LIB_ERROR_FILE_NOT_FOUND}"
  fi
  if is::empty "${__tr_fmt}"; then
    __tr_fmt="$(io::tree::detect "${__tr_file}")" || return $?
  fi
  local __tr_text=""
  __tr_text="$(<"${__tr_file}")"
  io::tree::parse_text "${__tr_text}" "${__tr_fmt}"
}

# @description Parse spec text into IO_TREE_* arrays.
# @description Разобрать текст спецификации в массивы IO_TREE_*.
# @param $1 Spec text / Текст
# @param $2 Format yaml|yml|txt|ini|csv / Формат
io::tree::parse_text() {
  local -r __tr_text="${1-}"
  local __tr_fmt="${2-}"
  __tr_fmt="${__tr_fmt,,}"
  [[ "${__tr_fmt}" == "yml" ]] && __tr_fmt="yaml"
  io::tree::reset
  case "${__tr_fmt}" in
    yaml) io::tree::__parse_yaml "${__tr_text}" || return $? ;;
    txt)  io::tree::__parse_txt "${__tr_text}" || return $? ;;
    ini)  io::tree::__parse_ini "${__tr_text}" || return $? ;;
    csv)  io::tree::__parse_csv "${__tr_text}" || return $? ;;
    *)
      error::throw "unknown tree format: ${__tr_fmt}" "${E_INVALID}"
      return "${E_INVALID}"
      ;;
  esac
  return 0
}

# @private
io::tree::__parse_txt() {
  local -r __tr_text="${1-}"
  local -a __tr_lines=()
  local __tr_line
  while IFS= read -r __tr_line || [[ -n "${__tr_line}" ]]; do
    __tr_lines+=("${__tr_line}")
  done <<< "${__tr_text}"

  local -i __tr_indented=0
  local __tr_probe
  for __tr_line in "${__tr_lines[@]}"; do
    __tr_probe="$(str::trim "${__tr_line}")"
    [[ "${__tr_probe}" == \#* ]] && continue
    is::not_empty "${__tr_probe}" || continue
    if [[ "${__tr_line}" =~ ^[[:space:]] ]]; then
      __tr_indented=1
      break
    fi
    if [[ "${__tr_line}" == *"├"* || "${__tr_line}" == *"└"* ]]; then
      __tr_indented=1
      break
    fi
  done

  if (( __tr_indented == 0 )); then
    for __tr_line in "${__tr_lines[@]}"; do
      __tr_line="$(str::trim "${__tr_line}")"
      [[ "${__tr_line}" == \#* ]] && continue
      is::not_empty "${__tr_line}" || continue
      [[ "${__tr_line}" == "." ]] && continue
      if [[ "${__tr_line}" == */ ]]; then
        io::tree::__add d "${__tr_line%/}" || return $?
      else
        io::tree::__add f "${__tr_line}" "" || return $?
      fi
    done
    return 0
  fi

  local -a __tr_si=(-1)
  local -a __tr_sp=("")
  local __tr_stripped __tr_name __tr_parent __tr_rel
  local -i __tr_ind
  for __tr_line in "${__tr_lines[@]}"; do
    __tr_stripped="$(io::tree::__strip_art "${__tr_line}")"
    __tr_name="$(str::trim "${__tr_stripped}")"
    [[ "${__tr_name}" == \#* ]] && continue
    [[ "${__tr_name}" == "." ]] && continue
    is::not_empty "${__tr_name}" || continue
    __tr_ind="$(io::tree::__indent "${__tr_stripped}")"
    while (( ${#__tr_si[@]} > 1 )) && (( __tr_ind <= __tr_si[-1] )); do
      __tr_si=("${__tr_si[@]:0:${#__tr_si[@]}-1}")
      __tr_sp=("${__tr_sp[@]:0:${#__tr_sp[@]}-1}")
    done
    __tr_parent="${__tr_sp[-1]}"
    if is::not_empty "${__tr_parent}"; then
      __tr_rel="${__tr_parent}/${__tr_name%/}"
    else
      __tr_rel="${__tr_name%/}"
    fi
    if [[ "${__tr_name}" == */ ]]; then
      io::tree::__add d "${__tr_rel}" || return $?
      __tr_si+=("${__tr_ind}")
      __tr_sp+=("${__tr_rel}")
    else
      io::tree::__add f "${__tr_rel}" "" || return $?
    fi
  done
  return 0
}

# @private
io::tree::__parse_ini() {
  local -r __tr_text="${1-}"
  local __tr_line __tr_section="." __tr_key __tr_val __tr_rel
  while IFS= read -r __tr_line || [[ -n "${__tr_line}" ]]; do
    __tr_line="$(str::trim "${__tr_line}")"
    [[ "${__tr_line}" == \#* || "${__tr_line}" == \;* ]] && continue
    is::not_empty "${__tr_line}" || continue
    if [[ "${__tr_line}" =~ ^\[(.*)\]$ ]]; then
      __tr_section="$(str::trim "${BASH_REMATCH[1]}")"
      [[ "${__tr_section}" == "root" ]] && __tr_section="."
      if [[ "${__tr_section}" != "." ]]; then
        io::tree::__add d "${__tr_section}" || return $?
      fi
      continue
    fi
    if [[ "${__tr_line}" == *"="* ]]; then
      __tr_key="$(str::trim "${__tr_line%%=*}")"
      __tr_val="$(str::trim "${__tr_line#*=}")"
      __tr_val="$(io::tree::__unquote "${__tr_val}")"
    else
      __tr_key="${__tr_line}"
      __tr_val=""
    fi
    is::not_empty "${__tr_key}" || continue
    if [[ "${__tr_section}" == "." ]]; then
      __tr_rel="${__tr_key%/}"
    else
      __tr_rel="${__tr_section}/${__tr_key%/}"
    fi
    if [[ "${__tr_key}" == */ ]]; then
      io::tree::__add d "${__tr_rel}" || return $?
    else
      io::tree::__add f "${__tr_rel}" "${__tr_val}" || return $?
    fi
  done <<< "${__tr_text}"
  return 0
}

# @private
io::tree::__parse_csv() {
  local -r __tr_text="${1-}"
  local -a __tr_rows=()
  csv::rows "${__tr_text}" __tr_rows
  local __tr_row
  local -a __tr_f=()
  local __tr_path __tr_kind __tr_body
  local -i __tr_header=0
  for __tr_row in "${__tr_rows[@]}"; do
    csv::fields "${__tr_row}" __tr_f
    (( ${#__tr_f[@]} > 0 )) || continue
    __tr_path="$(str::trim "${__tr_f[0]}")"
    if (( __tr_header == 0 )); then
      __tr_header=1
      local __tr_h="${__tr_path,,}"
      if [[ "${__tr_h}" == "path" || "${__tr_h}" == "file" ]]; then
        continue
      fi
    fi
    is::not_empty "${__tr_path}" || continue
    __tr_kind="f"
    __tr_body=""
    if (( ${#__tr_f[@]} >= 2 )); then
      local __tr_k
      __tr_k="$(str::trim "${__tr_f[1]}")"
      __tr_k="${__tr_k,,}"
      case "${__tr_k}" in
        d|dir|directory) __tr_kind="d" ;;
        f|file|"") __tr_kind="f" ;;
        *)
          if [[ "${__tr_path}" == */ ]]; then
            __tr_kind="d"
          else
            __tr_kind="f"
            __tr_body="${__tr_f[1]}"
          fi
          ;;
      esac
    fi
    if (( ${#__tr_f[@]} >= 3 )); then
      __tr_body="${__tr_f[2]}"
    fi
    if [[ "${__tr_path}" == */ ]]; then
      __tr_kind="d"
    fi
    io::tree::__add "${__tr_kind}" "${__tr_path}" "${__tr_body}" \
      || return $?
  done
  return 0
}

# @private
# Restricted YAML mapping tree / Ограниченное YAML-дерево отображений:
# indent maps, `key: value` files, `key:` dirs, `|` block scalars.
io::tree::__parse_yaml() {
  local -r __tr_text="${1-}"
  local -a __tr_lines=()
  local __tr_line
  while IFS= read -r __tr_line || [[ -n "${__tr_line}" ]]; do
    __tr_lines+=("${__tr_line}")
  done <<< "${__tr_text}"

  local -a __tr_si=(-1)
  local -a __tr_sp=("")
  local -i __tr_i=0
  local -i __tr_n=${#__tr_lines[@]}
  local __tr_raw __tr_trim __tr_key __tr_val __tr_parent __tr_rel
  local -i __tr_ind
  for (( __tr_i = 0; __tr_i < __tr_n; __tr_i++ )); do
    __tr_raw="${__tr_lines[__tr_i]}"
    __tr_trim="$(str::trim "${__tr_raw}")"
    [[ "${__tr_trim}" == \#* ]] && continue
    is::not_empty "${__tr_trim}" || continue
    __tr_ind="$(io::tree::__indent "${__tr_raw}")"
    if [[ "${__tr_trim}" != *:* ]]; then
      error::throw "yaml line needs a colon: ${__tr_trim}" \
        "${LIB_ERROR_INVALID_INPUT}"
      return "${LIB_ERROR_INVALID_INPUT}"
    fi
    __tr_key="$(str::trim "${__tr_trim%%:*}")"
    __tr_val="$(str::trim "${__tr_trim#*:}")"
    __tr_key="$(io::tree::__unquote "${__tr_key}")"
    is::not_empty "${__tr_key}" || continue
    while (( ${#__tr_si[@]} > 1 )) && (( __tr_ind <= __tr_si[-1] )); do
      __tr_si=("${__tr_si[@]:0:${#__tr_si[@]}-1}")
      __tr_sp=("${__tr_sp[@]:0:${#__tr_sp[@]}-1}")
    done
    __tr_parent="${__tr_sp[-1]}"
    if is::not_empty "${__tr_parent}"; then
      __tr_rel="${__tr_parent}/${__tr_key%/}"
    else
      __tr_rel="${__tr_key%/}"
    fi
    if [[ "${__tr_val}" == "|" || "${__tr_val}" == "|-" \
        || "${__tr_val}" == ">" || "${__tr_val}" == ">-" ]]; then
      local __tr_block=""
      local -i __tr_base=-1
      local __tr_bl __tr_bt
      local -i __tr_bi
      while (( __tr_i + 1 < __tr_n )); do
        __tr_bl="${__tr_lines[__tr_i + 1]}"
        __tr_bt="$(str::trim "${__tr_bl}")"
        __tr_bi="$(io::tree::__indent "${__tr_bl}")"
        if is::not_empty "${__tr_bt}" && (( __tr_bi <= __tr_ind )); then
          break
        fi
        __tr_i=$(( __tr_i + 1 ))
        if (( __tr_base < 0 )) && is::not_empty "${__tr_bt}"; then
          __tr_base=${__tr_bi}
        fi
        if (( __tr_base >= 0 )); then
          if (( ${#__tr_bl} >= __tr_base )); then
            __tr_bl="${__tr_bl:__tr_base}"
          else
            __tr_bl=""
          fi
        fi
        if is::not_empty "${__tr_block}"; then
          __tr_block+=$'\n'"${__tr_bl}"
        else
          __tr_block="${__tr_bl}"
        fi
      done
      io::tree::__add f "${__tr_rel}" "${__tr_block}" || return $?
      continue
    fi
    if [[ "${__tr_key}" == */ ]] || is::empty "${__tr_val}"; then
      io::tree::__add d "${__tr_rel}" || return $?
      __tr_si+=("${__tr_ind}")
      __tr_sp+=("${__tr_rel}")
    else
      __tr_val="$(io::tree::__unquote "${__tr_val}")"
      io::tree::__add f "${__tr_rel}" "${__tr_val}" || return $?
    fi
  done
  return 0
}

# ==========================================
# Plan / Apply
# ==========================================

# @private
io::tree::__is_dry() {
  [[ "${FRAMEWORK_DRY_RUN:-false}" == "true" \
    || "${IO_TREE_DRY_RUN:-0}" == "1" ]]
}

# @description Print the plan for dest (mkdir/write/skip).
# @description Печать плана для dest (mkdir/write/skip).
# @param $1 Destination root / Корень назначения
# @stdout plan lines
io::tree::plan() {
  local -r __tr_dest="${1-}"
  if is::empty "${__tr_dest}"; then
    error::throw "destination required" "${E_INVALID}"
    return "${E_INVALID}"
  fi
  local -i __tr_i
  local __tr_full
  for (( __tr_i = 0; __tr_i < ${#IO_TREE_PATH[@]}; __tr_i++ )); do
    __tr_full="$(io::tree::__join "${__tr_dest}" \
      "${IO_TREE_PATH[__tr_i]}")"
    if [[ "${IO_TREE_KIND[__tr_i]}" == "d" ]]; then
      if is::dir "${__tr_full}"; then
        printf 'KEEP\tdir\t%s\n' "${IO_TREE_PATH[__tr_i]}"
      else
        printf 'MKDIR\tdir\t%s\n' "${IO_TREE_PATH[__tr_i]}"
      fi
    else
      if is::file "${__tr_full}"; then
        printf 'SKIP\tfile\t%s\n' "${IO_TREE_PATH[__tr_i]}"
      else
        printf 'WRITE\tfile\t%s\n' "${IO_TREE_PATH[__tr_i]}"
      fi
    fi
  done
  return 0
}

# @private
io::tree::__write_file() {
  local -r __tr_path="${1:?}"
  local -r __tr_body="${2-}"
  if io::tree::__is_dry; then
    log::info "[DRY-RUN] write ${__tr_path}"
    return "${E_SUCCESS}"
  fi
  if ! printf '%s' "${__tr_body}" > "${__tr_path}"; then
    error::throw "failed to write ${__tr_path}" \
      "${LIB_ERROR_FILE_OPERATION}"
    return "${LIB_ERROR_FILE_OPERATION}"
  fi
  return "${E_SUCCESS}"
}

# @description Create parsed entries under dest.
# @description Создать разобранные записи под dest.
# @param $1 Destination root / Корень назначения
# @param $2 [optional] 1 = force overwrite / 1 = перезаписать
# @return 0 ok, E_* on error
io::tree::apply() {
  local -r __tr_dest="${1-}"
  local -r __tr_force="${2:-${IO_TREE_FORCE:-0}}"
  if is::empty "${__tr_dest}"; then
    error::throw "destination required" "${E_INVALID}"
    return "${E_INVALID}"
  fi
  if ! io::tree::__is_dry; then
    io::files::ensure_dir "${__tr_dest}" || return $?
  fi

  local -i __tr_i
  local __tr_full __tr_parent
  for (( __tr_i = 0; __tr_i < ${#IO_TREE_PATH[@]}; __tr_i++ )); do
    __tr_full="$(io::tree::__join "${__tr_dest}" \
      "${IO_TREE_PATH[__tr_i]}")"
    if [[ "${IO_TREE_KIND[__tr_i]}" == "d" ]]; then
      if is::file "${__tr_full}"; then
        error::throw "file blocks directory: ${__tr_full}" \
          "${LIB_ERROR_CONFLICT}"
        return "${LIB_ERROR_CONFLICT}"
      fi
      if io::tree::__is_dry; then
        log::info "[DRY-RUN] mkdir ${__tr_full}"
        continue
      fi
      io::files::ensure_dir "${__tr_full}" || return $?
      continue
    fi
    __tr_parent="${__tr_full%/*}"
    if io::tree::__is_dry; then
      log::info "[DRY-RUN] write ${__tr_full}"
      continue
    fi
    io::files::ensure_dir "${__tr_parent}" || return $?
    if is::dir "${__tr_full}"; then
      error::throw "directory blocks file: ${__tr_full}" \
        "${LIB_ERROR_CONFLICT}"
      return "${LIB_ERROR_CONFLICT}"
    fi
    if is::file "${__tr_full}" && [[ "${__tr_force}" != "1" ]]; then
      log::warn "skip existing file: ${__tr_full}"
      continue
    fi
    io::tree::__write_file "${__tr_full}" \
      "${IO_TREE_BODY[__tr_i]}" || return $?
  done
  return "${E_SUCCESS}"
}

# @description Parse a spec and create the tree under dest.
# @description Разобрать спецификацию и создать дерево под dest.
# @param $@ [--force] [--dry-run] [--format FMT] SPEC DEST
# @example
#   io::tree::create tree.yaml /tmp/app
#   io::tree::create --force --format txt paths.txt ./proj
io::tree::create() {
  local __tr_force=0
  local __tr_fmt=""
  local __tr_old_dry="${IO_TREE_DRY_RUN:-0}"
  local __tr_rc=0
  while (( $# > 0 )); do
    case "${1}" in
      --force) __tr_force=1; shift ;;
      --dry-run)
        IO_TREE_DRY_RUN=1
        shift
        ;;
      --format)
        __tr_fmt="${2-}"
        shift 2
        ;;
      --format=*)
        __tr_fmt="${1#*=}"
        shift
        ;;
      --)
        shift
        break
        ;;
      -*)
        error::throw "unknown flag: ${1}" "${E_INVALID}"
        return "${E_INVALID}"
        ;;
      *)
        break
        ;;
    esac
  done
  local -r __tr_spec="${1-}"
  local -r __tr_dest="${2-}"
  if is::empty "${__tr_spec}" || is::empty "${__tr_dest}"; then
    error::throw "usage: io::tree::create [flags] SPEC DEST" \
      "${E_INVALID}"
    return "${E_INVALID}"
  fi
  io::tree::parse "${__tr_spec}" "${__tr_fmt}" || {
    __tr_rc=$?
    IO_TREE_DRY_RUN="${__tr_old_dry}"
    return "${__tr_rc}"
  }
  io::tree::apply "${__tr_dest}" "${__tr_force}" || __tr_rc=$?
  IO_TREE_DRY_RUN="${__tr_old_dry}"
  return "${__tr_rc}"
}
