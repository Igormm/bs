#!/usr/bin/env bs
# shellcheck shell=bash
#
# lib/io/files.sh — File System Helper (FSH) for BS
# lib/io/files.sh — FSH: высокоуровневые файловые операции с dry-run,
# логированием и обработкой ошибок.
#
# This module provides a consistent API for copying, moving, removing,
# synchronizing and filtering files/directories. It honors FRAMEWORK_DRY_RUN
# and FRAMEWORK_DEBUG from core/const.
#
# Usage / Использование:
#   load "lib/io/files"
#   io::files::copy_file  "src.txt" "dst.txt" [atomic] [backup_suffix]
#   io::files::copy_dir   "src_dir" "dst_dir" [atomic] [backup_suffix]
#   io::files::sync_dir   "src_dir" "dst_dir" true
#   io::files::copy_matching "src_dir" "dst_dir" "*.sh *.md" "*.tmp"
#   io::files::move       "old.txt" "new.txt" [atomic_fallback] [backup_suffix]
#   io::files::cut        "old.txt" "new.txt"
#   io::files::remove     "tmp_dir" true
#   io::files::ensure_dir "my_dir" "755"
#
# Environment defaults / Переменные окружения по умолчанию:
#   BS_FILES_ATOMIC=true|false
#   BS_FILES_ATOMIC_FALLBACK=true|false
#   BS_FILES_BACKUP_SUFFIX=.suffix
#
# @depends core/const, core/logger, core/utils, lib/system/permissions

# Source Guard / Защита от повторной загрузки
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/prereq.sh"
bs::guard "IO_FILES" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "../system/permissions.sh"

# Module version / Версия модуля
declare -g IO_FILES_VERSION="1.0.0"
declare -g IO_FILES_LOADED="1"

# ==========================================
# Private helpers / Приватные вспомогательные функции
# ==========================================

# @private
# @description Execute command, honoring dry-run and debug modes.
# @description Выполнить команду с учётом dry-run и debug.
# @param $@ Command and arguments / Команда и аргументы
# @return 0 in dry-run, command exit code otherwise / 0 в dry-run, иначе код команды
io::files::__exec() {
  if [[ "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]; then
    log::warn "[DRY-RUN] $*"
    return "${E_SUCCESS}"
  fi

  if [[ "${FRAMEWORK_DEBUG:-false}" == "true" ]]; then
    log::debug "[io::files] execute: $*"
  fi

  "$@"
}

# @private
# @description Return portable recursive copy flags.
# @description Вернуть переносимые флаги рекурсивного копирования.
# @stdout Copy flags for cp / Флаги для cp
io::files::__cp_dir_flags() {
  if [[ "$(uname -s)" == "Linux" ]]; then
    printf '%s\n' "-a"
  else
    printf '%s\n' "-R" "-p"
  fi
}

# @private
# @description Check if rsync is available.
# @description Проверить наличие rsync.
# @return 0 if rsync found, 1 otherwise / 0 если rsync есть, 1 иначе
io::files::__has_rsync() {
  utils::has rsync
}

# @private
# @description Validate that source and destination are non-empty.
# @description Проверить, что источник и назначение заданы.
# @param $1 Source / Источник
# @param $2 Destination / Назначение
# @return E_INVALID if empty, E_SUCCESS otherwise / E_INVALID если пусто
io::files::__require_two_paths() {
  local src="${1:-}"
  local dst="${2:-}"

  if [[ -z "${src}" || -z "${dst}" ]]; then
    log::warn "Source and destination paths are required"
    return "${E_INVALID}"
  fi

  return "${E_SUCCESS}"
}

# @private
# @description Check if a string represents "true".
# @description Проверить, что строка равна "true".
# @param $1 Value / Значение
# @return 0 if true, 1 otherwise / 0 если true
io::files::__is_true() {
  [[ "${1:-}" == "true" ]]
}

# @private
# @description Generate a temporary path next to destination for atomic operations.
# @description Сгенерировать временный путь рядом с назначением для атомарных операций.
# @param $1 Destination path / Путь назначения
# @param $2 true if temporary directory is needed / true если нужен временный каталог
# @stdout Temporary path / Временный путь
# @return 0 on success, 1 on failure / 0 при успехе
io::files::__atomic_temp() {
  local dst="${1:-}"
  local is_dir="${2:-false}"
  local parent_dir

  parent_dir="$(dirname -- "${dst}")"
  if [[ ! -d "${parent_dir}" ]]; then
    log::error "Parent directory does not exist for atomic temp: ${parent_dir}"
    return 1
  fi

  local base
  base="$(basename -- "${dst}")"

  if [[ "${is_dir}" == "true" ]]; then
    mktemp -d "${parent_dir}/${base}.tmp.XXXXXX"
  else
    mktemp "${parent_dir}/${base}.tmp.XXXXXX"
  fi
}

# @private
# @description Clean up a temporary path, ignoring errors.
# @description Удалить временный путь, игнорируя ошибки.
# @param $1 Path to clean / Путь для удаления
io::files::__cleanup_temp() {
  local path="${1:-}"
  [[ -n "${path}" && -e "${path}" ]] || return 0
  utils::ignore rm -rf -- "${path}"
}

# @private
# @description Backup destination if it exists and suffix is provided.
# @description Создать резервную копию назначения, если оно существует и задан суффикс.
# @param $1 Destination path / Путь назначения
# @param $2 Backup suffix / Суффикс резервной копии
# @return 0 on success or nothing to do, 1 on backup failure
io::files::__backup_if_needed() {
  local dst="${1:-}"
  local suffix="${2:-}"

  [[ -n "${suffix}" ]] || return 0
  io::files::exists "${dst}" || return 0

  local backup="${dst}${suffix}"
  log::info "Creating backup: ${dst} -> ${backup}"

  if [[ "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]; then
    log::warn "[DRY-RUN] mv -- ${dst} ${backup}"
    return 0
  fi

  if ! mv -- "${dst}" "${backup}"; then
    log::error "Failed to create backup: ${dst} -> ${backup}"
    return 1
  fi
  return 0
}

# @private
# @description Replace destination atomically with temporary path.
# @description Атомарно заменить назначение временным путём.
# @param $1 Temporary path / Временный путь
# @param $2 Destination path / Путь назначения
# @param $3 true if temporary path is a directory / true если временный путь — каталог
# @return 0 on success, 1 on failure / 0 при успехе
io::files::__atomic_replace() {
  local temp_path="${1:-}"
  local dst="${2:-}"
  local is_dir="${3:-false}"

  if [[ -z "${temp_path}" || -z "${dst}" ]]; then
    log::warn "atomic_replace: temp and dst required"
    return 1
  fi

  if [[ "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]; then
    log::warn "[DRY-RUN] mv -- ${temp_path} ${dst}"
    return 0
  fi

  if [[ "${is_dir}" == "true" && -d "${dst}" ]]; then
    local old_dir
    old_dir="$(mktemp -d "${dst}.old.XXXXXX")"
    if ! mv -- "${dst}" "${old_dir}/old"; then
      log::error "Failed to move existing destination aside: ${dst}"
      io::files::__cleanup_temp "${old_dir}"
      return 1
    fi
    if ! mv -- "${temp_path}" "${dst}"; then
      log::error "Failed to move temp directory into place: ${temp_path} -> ${dst}"
      mv -- "${old_dir}/old" "${dst}" >/dev/null 2>&1 || true
      io::files::__cleanup_temp "${old_dir}"
      return 1
    fi
    io::files::__cleanup_temp "${old_dir}"
  else
    if ! mv -- "${temp_path}" "${dst}"; then
      log::error "Failed to move temp into place: ${temp_path} -> ${dst}"
      return 1
    fi
  fi

  return 0
}

# @private
# @description Atomically copy a single file using temp + rename.
# @description Атомарно скопировать один файл через временный файл + rename.
# @param $1 Source file / Исходный файл
# @param $2 Destination / Назначение
# @return 0 on success, 1 on failure / 0 при успехе
io::files::__atomic_copy_file() {
  local src="${1:-}"
  local dst="${2:-}"
  local temp_path

  temp_path="$(io::files::__atomic_temp "${dst}" false)"
  [[ -n "${temp_path}" ]] || return 1

  if [[ "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]; then
    log::warn "[DRY-RUN] atomic copy: cp -p -- ${src} ${temp_path}; mv -- ${temp_path} ${dst}"
    return 0
  fi

  if ! cp -p -- "${src}" "${temp_path}"; then
    log::error "Failed to copy source to temp: ${src} -> ${temp_path}"
    io::files::__cleanup_temp "${temp_path}"
    return 1
  fi

  if ! io::files::__atomic_replace "${temp_path}" "${dst}" false; then
    io::files::__cleanup_temp "${temp_path}"
    return 1
  fi

  return 0
}

# @private
# @description Atomically copy a directory using temp directory + rename.
# @description Атомарно скопировать каталог через временный каталог + rename.
# @param $1 Source directory / Исходный каталог
# @param $2 Destination / Назначение
# @return 0 on success, 1 on failure / 0 при успехе
io::files::__atomic_copy_dir() {
  local src="${1:-}"
  local dst="${2:-}"
  local temp_path

  temp_path="$(io::files::__atomic_temp "${dst}" true)"
  [[ -n "${temp_path}" ]] || return 1

  if [[ "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]; then
    log::warn "[DRY-RUN] atomic copy dir: cp -a ${src}/. ${temp_path}/; mv -- ${temp_path} ${dst}"
    return 0
  fi

  if ! cp -a -- "${src}/." "${temp_path}/"; then
    log::error "Failed to copy directory contents to temp: ${src} -> ${temp_path}"
    io::files::__cleanup_temp "${temp_path}"
    return 1
  fi

  if ! io::files::__atomic_replace "${temp_path}" "${dst}" true; then
    io::files::__cleanup_temp "${temp_path}"
    return 1
  fi

  return 0
}

# ==========================================
# Inspection / Проверки
# ==========================================

# @description Check if path exists.
# @description Проверить существование пути.
# @param $1 Path / Путь
# @return 0 if exists, 1 otherwise / 0 если существует
io::files::exists() {
  local path="${1:-}"
  [[ -n "${path}" && -e "${path}" ]]
}

# @description Check if path is a regular file.
# @description Проверить, что путь — обычный файл.
# @param $1 Path / Путь
# @return 0 if regular file, 1 otherwise / 0 если файл
io::files::is_file() {
  local path="${1:-}"
  [[ -n "${path}" && -f "${path}" ]]
}

# @description Check if path is a directory.
# @description Проверить, что путь — каталог.
# @param $1 Path / Путь
# @return 0 if directory, 1 otherwise / 0 если каталог
io::files::is_dir() {
  local path="${1:-}"
  [[ -n "${path}" && -d "${path}" ]]
}

# ==========================================
# Directory creation / Создание каталогов
# ==========================================

# @description Ensure directory exists; optionally set mode.
# @description Создать каталог, если его нет; опционально задать права.
# @param $1 Directory path / Путь к каталогу
# @param [$2] Mode (octal, e.g. "755") / Права (восьмеричные, например "755")
# @return 0 on success, error code otherwise / 0 при успехе
io::files::ensure_dir() {
  local dir_path="${1:-}"
  local mode="${2:-}"

  if [[ -z "${dir_path}" ]]; then
    log::warn "Directory path is required"
    return "${E_INVALID}"
  fi

  log::info "Ensuring directory: ${dir_path}"

  if ! io::files::__exec mkdir -p -- "${dir_path}"; then
    log::error "Failed to create directory: ${dir_path}"
    return "${LIB_ERROR_FILE_OPERATION}"
  fi

  if [[ -n "${mode}" ]]; then
    if [[ "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]; then
      log::warn "[DRY-RUN] chmod ${mode} ${dir_path}"
    elif ! system::permissions::chmod "${dir_path}" "${mode}"; then
      return "${LIB_ERROR_FILE_OPERATION}"
    fi
  fi

  return "${E_SUCCESS}"
}

# ==========================================
# Copy / Копирование
# ==========================================

# @description Copy a single file preserving attributes.
# @description Скопировать один файл с сохранением атрибутов.
#   With atomic=true the file is first written to a temp file next to the
#   destination and then renamed into place. If backup_suffix is set and the
#   destination already exists, it is renamed to dst<suffix> before copying.
#   При atomic=true файл сначала пишется во временный файл рядом с
#   назначением, затем atomically переименовывается. Если backup_suffix задан
#   и назначение существует, оно переименовывается в dst<suffix>.
# @param $1 Source file / Исходный файл
# @param $2 Destination / Назначение
# @param [$3=false] Atomic copy (true/false) / Атомарное копирование
# @param [$4=""] Backup suffix (or BS_FILES_BACKUP_SUFFIX env default) /
#   Суффикс резервной копии
# @return 0 on success, error code otherwise / 0 при успехе
# @example
#   io::files::copy_file "src.txt" "dst.txt"
#   io::files::copy_file "src.txt" "dst.txt" true ".bak"
io::files::copy_file() {
  local src="${1:-}"
  local dst="${2:-}"
  local atomic="${3:-${BS_FILES_ATOMIC:-false}}"
  local backup_suffix="${4:-${BS_FILES_BACKUP_SUFFIX:-}}"

  io::files::__require_two_paths "${src}" "${dst}" || return $?

  if [[ "${src}" == "${dst}" ]]; then
    log::warn "Source and destination are the same: ${src}"
    return "${E_INVALID}"
  fi

  if ! io::files::exists "${src}"; then
    log::error "Source not found: ${src}"
    return "${LIB_ERROR_FILE_NOT_FOUND}"
  fi

  if ! io::files::is_file "${src}"; then
    log::error "Source is not a file: ${src}"
    return "${LIB_ERROR_FILE_OPERATION}"
  fi

  log::info "Copying file: ${src} -> ${dst} (atomic=${atomic})"

  local parent_dir
  parent_dir="$(dirname -- "${dst}")"
  if [[ ! -d "${parent_dir}" ]]; then
    if ! io::files::ensure_dir "${parent_dir}"; then
      return "${LIB_ERROR_FILE_OPERATION}"
    fi
  fi

  if ! io::files::__backup_if_needed "${dst}" "${backup_suffix}"; then
    return "${LIB_ERROR_FILE_OPERATION}"
  fi

  if io::files::__is_true "${atomic}"; then
    if ! io::files::__atomic_copy_file "${src}" "${dst}"; then
      log::error "Failed to atomically copy file: ${src} -> ${dst}"
      return "${LIB_ERROR_FILE_OPERATION}"
    fi
  else
    if ! io::files::__exec cp -p -- "${src}" "${dst}"; then
      log::error "Failed to copy file: ${src} -> ${dst}"
      return "${LIB_ERROR_FILE_OPERATION}"
    fi
  fi

  return "${E_SUCCESS}"
}

# @description Recursively copy a directory.
# @description Рекурсивно скопировать каталог.
#   With atomic=true the directory is first copied to a temp directory next to
#   the destination and then swapped into place.
#   При atomic=true каталог сначала копируется во временный каталог рядом с
#   назначением, затем заменяется atomically.
# @param $1 Source directory / Исходный каталог
# @param $2 Destination / Назначение
# @param [$3=false] Atomic copy (true/false) / Атомарное копирование
# @param [$4=""] Backup suffix (or BS_FILES_BACKUP_SUFFIX env default) /
#   Суффикс резервной копии
# @return 0 on success, error code otherwise / 0 при успехе
# @example
#   io::files::copy_dir "src_dir" "dst_dir"
#   io::files::copy_dir "src_dir" "dst_dir" true ".bak"
io::files::copy_dir() {
  local src="${1:-}"
  local dst="${2:-}"
  local atomic="${3:-${BS_FILES_ATOMIC:-false}}"
  local backup_suffix="${4:-${BS_FILES_BACKUP_SUFFIX:-}}"

  io::files::__require_two_paths "${src}" "${dst}" || return $?

  if [[ "${src}" == "${dst}" ]]; then
    log::warn "Source and destination are the same: ${src}"
    return "${E_INVALID}"
  fi

  if ! io::files::is_dir "${src}"; then
    log::error "Source is not a directory: ${src}"
    return "${LIB_ERROR_FILE_OPERATION}"
  fi

  log::info "Copying directory: ${src} -> ${dst} (atomic=${atomic})"

  local parent_dir
  parent_dir="$(dirname -- "${dst}")"
  if [[ ! -d "${parent_dir}" ]]; then
    if ! io::files::ensure_dir "${parent_dir}"; then
      return "${LIB_ERROR_FILE_OPERATION}"
    fi
  fi

  if ! io::files::__backup_if_needed "${dst}" "${backup_suffix}"; then
    return "${LIB_ERROR_FILE_OPERATION}"
  fi

  if io::files::__is_true "${atomic}"; then
    if ! io::files::__atomic_copy_dir "${src}" "${dst}"; then
      log::error "Failed to atomically copy directory: ${src} -> ${dst}"
      return "${LIB_ERROR_FILE_OPERATION}"
    fi
  else
    local -a cp_flags=()
    read -ra cp_flags <<< "$(io::files::__cp_dir_flags)"

    if ! io::files::__exec cp "${cp_flags[@]}" -- "${src}" "${dst}"; then
      log::error "Failed to copy directory: ${src} -> ${dst}"
      return "${LIB_ERROR_FILE_OPERATION}"
    fi
  fi

  return "${E_SUCCESS}"
}

# @description Synchronize destination directory with source.
# @description Синхронизовать каталог назначения с источником.
#   With delete=true destination becomes a mirror of source.
#   При delete=true назначение становится зеркалом источника.
# @param $1 Source directory / Исходный каталог
# @param $2 Destination directory / Каталог назначения
# @param [$3=false] Delete extra files in destination / Удалять лишние файлы в назначении
# @return 0 on success, error code otherwise / 0 при успехе
io::files::sync_dir() {
  local src="${1:-}"
  local dst="${2:-}"
  local delete="${3:-false}"

  io::files::__require_two_paths "${src}" "${dst}" || return $?

  if ! io::files::is_dir "${src}"; then
    log::error "Source is not a directory: ${src}"
    return "${LIB_ERROR_FILE_OPERATION}"
  fi

  log::info "Syncing directory: ${src} -> ${dst} (delete=${delete})"

  if ! io::files::ensure_dir "${dst}"; then
    return "${LIB_ERROR_FILE_OPERATION}"
  fi

  # Prefer rsync when available / Предпочитаем rsync, если есть
  if io::files::__has_rsync; then
    local -a rsync_flags=("-a")
    if [[ "${delete}" == "true" ]]; then
      rsync_flags+=("--delete")
    fi

    if ! io::files::__exec rsync "${rsync_flags[@]}" -- "${src}/" "${dst}/"; then
      log::error "Failed to sync directory via rsync: ${src} -> ${dst}"
      return "${LIB_ERROR_FILE_OPERATION}"
    fi
    return "${E_SUCCESS}"
  fi

  # Fallback: cp + optional manual cleanup / Fallback: cp + ручная очистка
  local -a cp_flags=()
  read -ra cp_flags <<< "$(io::files::__cp_dir_flags)"

  if ! io::files::__exec cp "${cp_flags[@]}" -- "${src}/." "${dst}/"; then
    log::error "Failed to copy contents: ${src} -> ${dst}"
    return "${LIB_ERROR_FILE_OPERATION}"
  fi

  if [[ "${delete}" == "true" ]]; then
    local dst_item
    local rel_path
    while IFS= read -r -d '' dst_item; do
      rel_path="${dst_item#${dst}/}"
      if [[ ! -e "${src}/${rel_path}" ]]; then
        log::debug "Removing extra item: ${dst_item}"
        if ! io::files::remove "${dst_item}" true; then
          log::error "Failed to remove extra item: ${dst_item}"
          return "${LIB_ERROR_FILE_OPERATION}"
        fi
      fi
    done < <(find "${dst}" -mindepth 1 -depth -print0)
  fi

  return "${E_SUCCESS}"
}

# @description Copy files matching include globs, excluding exclude globs.
# @description Скопировать файлы по маскам include, исключая exclude.
#   Globs are space-separated shell patterns matched against basename.
#   Маски — разделённые пробелом шаблоны, сопоставляемые с именем файла.
# @param $1 Source directory / Исходный каталог
# @param $2 Destination directory / Каталог назначения
# @param [$3] Include globs / Маски включения (например "*.sh *.md")
# @param [$4] Exclude globs / Маски исключения (например "*.tmp")
# @return 0 on success, error code otherwise / 0 при успехе
io::files::copy_matching() {
  local src="${1:-}"
  local dst="${2:-}"
  local include="${3:-}"
  local exclude="${4:-}"

  io::files::__require_two_paths "${src}" "${dst}" || return $?

  if ! io::files::is_dir "${src}"; then
    log::error "Source is not a directory: ${src}"
    return "${LIB_ERROR_FILE_OPERATION}"
  fi

  if ! io::files::ensure_dir "${dst}"; then
    return "${LIB_ERROR_FILE_OPERATION}"
  fi

  log::info "Copying matching files from ${src} to ${dst} (include='${include}', exclude='${exclude}')"

  local -a find_args=("${src}" "-type" "f")
  local -a include_args=()
  local -a exclude_args=()

  if [[ -n "${include}" ]]; then
    local -a include_patterns=()
    read -ra include_patterns <<< "${include}"
    local pattern
    local first=1
    for pattern in "${include_patterns[@]}"; do
      if [[ "${first}" -eq 1 ]]; then
        include_args+=("(" "-name" "${pattern}")
        first=0
      else
        include_args+=("-o" "-name" "${pattern}")
      fi
    done
    include_args+=(")")
  fi

  if [[ -n "${exclude}" ]]; then
    local -a exclude_patterns=()
    read -ra exclude_patterns <<< "${exclude}"
    local pattern
    local first=1
    for pattern in "${exclude_patterns[@]}"; do
      if [[ "${first}" -eq 1 ]]; then
        exclude_args+=("!" "(" "-name" "${pattern}")
        first=0
      else
        exclude_args+=("-o" "-name" "${pattern}")
      fi
    done
    exclude_args+=(")")
  fi

  if [[ ${#include_args[@]} -gt 0 ]]; then
    find_args+=("${include_args[@]}")
  fi
  if [[ ${#exclude_args[@]} -gt 0 ]]; then
    find_args+=("${exclude_args[@]}")
  fi

  local file
  local rel_path
  local target
  local target_dir

  while IFS= read -r -d '' file; do
    rel_path="${file#${src}/}"
    target="${dst}/${rel_path}"
    target_dir="$(dirname -- "${target}")"

    if ! io::files::ensure_dir "${target_dir}"; then
      return "${LIB_ERROR_FILE_OPERATION}"
    fi

    if ! io::files::__exec cp -p -- "${file}" "${target}"; then
      log::error "Failed to copy matching file: ${file} -> ${target}"
      return "${LIB_ERROR_FILE_OPERATION}"
    fi
  done < <(find "${find_args[@]}" -print0)

  return "${E_SUCCESS}"
}

# ==========================================
# Move / cut / Перемещение / вырезание
# ==========================================

# @description Move file or directory to destination.
# @description Переместить файл или каталог.
#   If atomic_fallback=true and a direct mv fails (e.g. cross-device move),
#   the function falls back to copy + remove. If backup_suffix is set and the
#   destination already exists, it is renamed to dst<suffix> before moving.
#   Если atomic_fallback=true и прямой mv не удался (например, разные ФС),
#   функция делает fallback на copy + remove. Если backup_suffix задан и
#   назначение существует, оно переименовывается в dst<suffix>.
# @param $1 Source / Источник
# @param $2 Destination / Назначение
# @param [$3=true] Use copy+remove fallback if mv fails /
#   Использовать fallback copy+remove при неудаче mv
# @param [$4=""] Backup suffix (or BS_FILES_BACKUP_SUFFIX env default) /
#   Суффикс резервной копии
# @return 0 on success, error code otherwise / 0 при успехе
# @example
#   io::files::move "old.txt" "new.txt"
#   io::files::move "old.txt" "new.txt" true ".bak"
io::files::move() {
  local src="${1:-}"
  local dst="${2:-}"
  local atomic_fallback="${3:-${BS_FILES_ATOMIC_FALLBACK:-true}}"
  local backup_suffix="${4:-${BS_FILES_BACKUP_SUFFIX:-}}"

  io::files::__require_two_paths "${src}" "${dst}" || return $?

  if ! io::files::exists "${src}"; then
    log::error "Source not found: ${src}"
    return "${LIB_ERROR_FILE_NOT_FOUND}"
  fi

  log::info "Moving: ${src} -> ${dst} (atomic_fallback=${atomic_fallback})"

  local parent_dir
  parent_dir="$(dirname -- "${dst}")"
  if [[ ! -d "${parent_dir}" ]]; then
    if ! io::files::ensure_dir "${parent_dir}"; then
      return "${LIB_ERROR_FILE_OPERATION}"
    fi
  fi

  if ! io::files::__backup_if_needed "${dst}" "${backup_suffix}"; then
    return "${LIB_ERROR_FILE_OPERATION}"
  fi

  if io::files::__exec mv -- "${src}" "${dst}"; then
    return "${E_SUCCESS}"
  fi

  log::warn "Direct move failed: ${src} -> ${dst}"

  if ! io::files::__is_true "${atomic_fallback}"; then
    log::error "Failed to move: ${src} -> ${dst}"
    return "${LIB_ERROR_FILE_OPERATION}"
  fi

  log::info "Trying atomic fallback (copy + remove): ${src} -> ${dst}"

  if [[ "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]; then
    log::warn "[DRY-RUN] cp -a ${src} ${dst}; rm -rf -- ${src}"
    return "${E_SUCCESS}"
  fi

  local -a cp_flags=()
  if io::files::is_dir "${src}"; then
    if io::files::is_dir "${dst}"; then
      cp_flags=("-a")
      if ! cp "${cp_flags[@]}" -- "${src}/." "${dst}/"; then
        log::error "Failed to copy directory contents in move fallback: ${src} -> ${dst}"
        return "${LIB_ERROR_FILE_OPERATION}"
      fi
    else
      read -ra cp_flags <<< "$(io::files::__cp_dir_flags)"
      if ! cp "${cp_flags[@]}" -- "${src}" "${dst}"; then
        log::error "Failed to copy directory in move fallback: ${src} -> ${dst}"
        return "${LIB_ERROR_FILE_OPERATION}"
      fi
    fi
  else
    cp_flags=("-p")
    if ! cp "${cp_flags[@]}" -- "${src}" "${dst}"; then
      log::error "Failed to copy file in move fallback: ${src} -> ${dst}"
      return "${LIB_ERROR_FILE_OPERATION}"
    fi
  fi

  if ! io::files::remove "${src}" true; then
    log::error "Failed to remove source after move fallback: ${src}"
    return "${LIB_ERROR_FILE_OPERATION}"
  fi

  return "${E_SUCCESS}"
}

# @description Cut (= move) file or directory to destination.
# @description Вырезать (= переместить) файл или каталог.
# @param $1 Source / Источник
# @param $2 Destination / Назначение
# @return 0 on success, error code otherwise / 0 при успехе
io::files::cut() {
  log::info "Cutting: ${1:-} -> ${2:-}"
  io::files::move "$@"
}

# ==========================================
# Remove / Удаление
# ==========================================

# @description Remove file or directory. Directories require recursive=true.
# @description Удалить файл или каталог. Для каталога нужен recursive=true.
# @param $1 Path / Путь
# @param [$2=false] Recursive / Рекурсивное удаление (true/false)
# @return 0 on success, error code otherwise / 0 при успехе
io::files::remove() {
  local path="${1:-}"
  local recursive="${2:-false}"

  if [[ -z "${path}" ]]; then
    log::warn "Path is required"
    return "${E_INVALID}"
  fi

  if ! io::files::exists "${path}"; then
    log::debug "Path does not exist, nothing to remove: ${path}"
    return "${E_SUCCESS}"
  fi

  if io::files::is_dir "${path}"; then
    if [[ "${recursive}" != "true" ]]; then
      log::error "Directory requires recursive=true: ${path}"
      return "${LIB_ERROR_FILE_OPERATION}"
    fi
    log::info "Removing directory recursively: ${path}"
    if ! io::files::__exec rm -r -- "${path}"; then
      log::error "Failed to remove directory: ${path}"
      return "${LIB_ERROR_FILE_OPERATION}"
    fi
  else
    log::info "Removing file: ${path}"
    if ! io::files::__exec rm -- "${path}"; then
      log::error "Failed to remove file: ${path}"
      return "${LIB_ERROR_FILE_OPERATION}"
    fi
  fi

  return "${E_SUCCESS}"
}
