#!/usr/bin/env bash

# Installation and uninstallation functions

# Install
do_install() {
  # Root required for system mode
  if [[ "${MODE}" == "system" ]]; then
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
      printf "ERROR: Нужны права root. Запустите: sudo ./install.sh\n" >&2
      exit 1
    fi
  fi

  if is_already_installed; then
    printf "Предупреждение: BS уже установлена в %s\n" "${TARGET_LIB}"
    printf "Удалите сначала старую версию: ./install.sh %s uninstall\n" "${MODE:+--$MODE}"
    printf "Или используйте переопределения: PREFIX=... BIN_DIR=... LIB_DIR=...\n"
    exit 1
  fi

  printf "Установка BS (%s)\n" "${MODE}"
  printf "  SOURCE_ROOT: %s\n" "${SOURCE_ROOT}"
  printf "  PREFIX:      %s\n" "${PREFIX}"
  printf "  TARGET_LIB:  %s\n" "${TARGET_LIB}"
  printf "  TARGET_BIN:  %s\n" "${TARGET_BIN}"

  # Ensure dirs
  mkdir -p "${BIN_DIR}"
  mkdir -p "${LIB_DIR}"

  # Clean target lib
  rm -rf "${TARGET_LIB}"
  mkdir -p "${TARGET_LIB}"

  # Copy payload
  cp -a "${SOURCE_ROOT}/bootstrap" "${TARGET_LIB}/"
  cp -a "${SOURCE_ROOT}/core"      "${TARGET_LIB}/"
  cp -a "${SOURCE_ROOT}/bs"        "${TARGET_LIB}/"   # main launcher
  cp -a "${SOURCE_ROOT}/lib"       "${TARGET_LIB}/"

  # Create wrapper
  if [[ "${MODE}" == "local" ]]; then
    cat >"${TARGET_BIN}" <<'WRAP'
#!/usr/bin/env bash
export BS_ROOT="$HOME/.local/lib/bs"
exec "$BS_ROOT/bs" "$@"
WRAP
  else
    cat >"${TARGET_BIN}" <<'WRAP'
#!/usr/bin/env bash
export BS_ROOT="/usr/local/lib/bs"
exec "$BS_ROOT/bs" "$@"
WRAP
  fi
  chmod 0755 "${TARGET_BIN}"

  printf "Готово.\n"

  # For local installs, auto update PATH
  if [[ "${MODE}" == "local" ]]; then
    auto_update_path
  fi
}

# Uninstall
do_uninstall() {
  # Root required for system mode
  if [[ "${MODE}" == "system" ]]; then
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
      printf "ERROR: Нужны права root. Запустите: sudo ./install.sh\n" >&2
      exit 1
    fi
  fi

  printf "Удаление BS (%s)\n" "${MODE}"
  printf "  TARGET_BIN: %s\n" "${TARGET_BIN}"
  printf "  TARGET_LIB: %s\n" "${TARGET_LIB}"

  # Remove wrapper
  if [[ -f "${TARGET_BIN}" ]]; then
    rm -f "${TARGET_BIN}"
    printf "Удален: %s\n" "${TARGET_BIN}"
  else
    printf "Нет файла: %s\n" "${TARGET_BIN}"
  fi

  # Remove libs
  if [[ -d "${TARGET_LIB}" ]]; then
    rm -rf "${TARGET_LIB}"
    printf "Удален: %s\n" "${TARGET_LIB}"
  else
    printf "Нет каталога: %s\n" "${TARGET_LIB}"
  fi

  # Do NOT wipe user's ~/.local trees; only tidy empty parents
  if [[ "${MODE}" == "local" ]]; then
    # Attempt to remove empty BIN_DIR
    if [[ -d "${BIN_DIR}" ]] && rmdir "${BIN_DIR}" 2>/dev/null; then
      printf "Удален пустой каталог: %s\n" "${BIN_DIR}"
    fi
    # Attempt to remove empty LIB_DIR
    if [[ -d "${LIB_DIR}" ]] && rmdir "${LIB_DIR}" 2>/dev/null; then
      printf "Удален пустой каталог: %s\n" "${LIB_DIR}"
    fi
  fi

  printf "Готово.\n"
}