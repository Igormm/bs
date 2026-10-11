#!/usr/bin/env bash

# Installation and uninstallation functions

# Записать манифест установки: как, откуда и куда поставлена эта копия BS.
# Его читают `bs env`, `bs update` и `bs uninstall`.
# Write the install manifest: how, from where and where this BS copy was
# installed. Read by `bs env`, `bs update` and `bs uninstall`.
write_install_manifest() {
  local commit="" repo=""
  if utils::has git && [[ -e "${SOURCE_ROOT}/.git" ]]; then
    commit="$(git -C "${SOURCE_ROOT}" rev-parse HEAD 2>/dev/null)" || commit=""
    repo="$(git -C "${SOURCE_ROOT}" remote get-url origin 2>/dev/null)" || repo=""
  fi
  {
    printf '# BS install manifest — written by install.sh, updated by bs update\n'
    printf 'mode=%s\n' "${MODE}"
    printf 'prefix=%s\n' "${PREFIX}"
    printf 'lib=%s\n' "${TARGET_LIB}"
    printf 'bin=%s\n' "${TARGET_BIN}"
    printf 'version=%s\n' "${BS_VERSION:-unknown}"
    printf 'source=%s\n' "${SOURCE_ROOT}"
    printf 'source_repo=%s\n' "${repo}"
    printf 'source_commit=%s\n' "${commit}"
    printf 'installed_at=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf 'installed_by=%s\n' "${SUDO_USER:-${USER:-$(id -un)}}"
  } > "${TARGET_LIB}/.install"
}

# Install
do_install() {
  # Root required for system mode
  if [[ "${MODE}" == "system" ]]; then
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
      printf "ERROR: Нужны права root. Запустите: sudo ./install.sh\n" >&2
      printf "       Или установите без root, в ~/.local: ./install.sh --local\n\n" >&2
      usage >&2
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

  # Create wrapper with real paths from the chosen PREFIX
  # Создать wrapper с реальными путями из выбранного PREFIX
  cat >"${TARGET_BIN}" <<WRAP
#!/usr/bin/env bash
export BS_ROOT="${TARGET_LIB}"
exec "\${BS_ROOT}/bs" "\$@"
WRAP
  chmod 0755 "${TARGET_BIN}"

  write_install_manifest

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
  if is::file "${TARGET_BIN}"; then
    rm -f "${TARGET_BIN}"
    printf "Удален: %s\n" "${TARGET_BIN}"
  else
    printf "Нет файла: %s\n" "${TARGET_BIN}"
  fi

  # Remove libs
  if is::dir "${TARGET_LIB}"; then
    # Безопасность: как и bs uninstall, installer не удаляет исходный чекаут
    # или рабочий BS_ROOT. Если TARGET_LIB содержит .git или совпадает с
    # SOURCE_ROOT — это репозиторий, а не установленная копия.
    # Safety: like bs uninstall, the installer never removes the source
    # checkout or the running BS_ROOT. A TARGET_LIB with .git, or equal to
    # SOURCE_ROOT, is the repo itself, not an installed copy.
    if [[ -d "${TARGET_LIB}/.git" || "${TARGET_LIB}" == "${SOURCE_ROOT}" ]]; then
      printf "ПРЕДУПРЕЖДЕНИЕ: %s — исходный репозиторий, пропускаем\n" "${TARGET_LIB}" >&2
      printf "WARNING: %s is the source checkout, skipping\n" "${TARGET_LIB}" >&2
    else
      rm -rf "${TARGET_LIB}"
      printf "Удален: %s\n" "${TARGET_LIB}"
    fi
  else
    printf "Нет каталога: %s\n" "${TARGET_LIB}"
  fi

  # Do NOT wipe user's ~/.local trees; only tidy empty parents
  if [[ "${MODE}" == "local" ]]; then
    # rmdir удаляет ТОЛЬКО пустые каталоги: если в ~/.local/bin или
    # ~/.local/lib есть другие файлы — они остаются нетронутыми.
    # rmdir removes ONLY empty dirs: any other files in ~/.local/bin or
    # ~/.local/lib are left untouched.
    # Attempt to remove empty BIN_DIR
    if is::dir "${BIN_DIR}" && utils::quiet_err rmdir "${BIN_DIR}"; then
      printf "Удален пустой каталог: %s\n" "${BIN_DIR}"
    fi
    # Attempt to remove empty LIB_DIR
    if is::dir "${LIB_DIR}" && utils::quiet_err rmdir "${LIB_DIR}"; then
      printf "Удален пустой каталог: %s\n" "${LIB_DIR}"
    fi
    # PATH-строка удаляется только точным совпадением строки, добавленной
    # установщиком; ручные guard'ы пользователя (например if ! [[ "$PATH" =~ ...
    # в начале .bashrc) остаются нетронутыми.
    # Only the exact installer-added line is removed; user's manual PATH
    # guards (e.g. `if ! [[ "$PATH" =~ ...` at the top of .bashrc) survive.
    # PATH-чистка не должна прерывать удаление при ошибке записи rc-файла
    remove_path_entry "${HOME}/.bashrc" || true
    remove_path_entry "${HOME}/.zshrc" || true
  fi

  printf "Готово.\n"
}