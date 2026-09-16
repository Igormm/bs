#!/usr/bin/env bash

# PATH management functions

# Ask a yes/no question, default is "No" / Вопрос да/нет, по умолчанию «нет»
confirm() {
  local prompt="${1:-Are you sure?}"
  local answer
  printf "%s [y/N] " "${prompt}" >&2
  read -r answer || return 1
  case "${answer}" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# Print PATH hint after local install / Подсказка про PATH после локальной установки
print_path_hint() {
  cat <<EOF
Добавьте каталог с bs в PATH / Add the bs bin directory to PATH:

  export PATH="${BIN_DIR}:\$PATH"

Например, для bash / For bash, for example:
  echo 'export PATH="${BIN_DIR}:\$PATH"' >> ~/.bashrc
  source ~/.bashrc

Или выполните авто-настройку / Or run the automatic setup:
  ./install.sh --local --update-path
EOF
}

# Update ~/.bashrc with PATH line (with confirmation)
update_path_bashrc() {
  local bashrc="${HOME}/.bashrc"
  local line='export PATH="$HOME/.local/bin:$PATH"'

  is::file "${bashrc}" || touch "${bashrc}"

  if grep -Fqx "${line}" "${bashrc}"; then
    printf "PATH уже настроен в %s\n" "${bashrc}"
    return 0
  fi

  if confirm "Добавить PATH в ${bashrc}?"; then
    printf "\n%s\n" "${line}" >> "${bashrc}"
    printf "Добавлено. Применить: source ~/.bashrc\n"
  else
    printf "Пропущено.\n"
  fi
}

# Удалить строку PATH, добавленную установщиком, из rc-файла (идемпотентно).
# Удаляется только точное совпадение строки; пользовательские правки не трогаем.
# Remove the installer-added PATH line from an rc file (idempotent).
# Only an exact line match is removed; user edits are left untouched.
remove_path_entry() {
  local rc_file="$1"
  local line='export PATH="$HOME/.local/bin:$PATH"'
  local tmp_file

  if ! is::file "${rc_file}"; then
    return 0
  fi

  if ! utils::quiet grep -Fqx "${line}" "${rc_file}"; then
    return 0
  fi

  # grep -Fvx исключает только точные совпадения; при пустом результате
  # (файл состоял лишь из этой строки) оставляем пустой файл.
  # utils::attempt сохраняет stdout — в отличие от utils::ignore.
  tmp_file="${rc_file}.bs.$$.tmp"
  utils::attempt grep -Fvx "${line}" "${rc_file}" > "${tmp_file}"
  mv "${tmp_file}" "${rc_file}"
  printf "Удалена строка PATH из %s\nPath line removed from %s\n" "${rc_file}" "${rc_file}"
}

# Auto add PATH to bash/zsh (idempotent)
auto_update_path() {
  local bashrc="${HOME}/.bashrc"
  local zshrc="${HOME}/.zshrc"
  local line='export PATH="$HOME/.local/bin:$PATH"'

  # bashrc
  if is::file "${bashrc}" || ! is::file "${zshrc}"; then
    if ! utils::quiet_err grep -Fqx "${line}" "${bashrc}"; then
      printf "\n%s\n" "${line}" >> "${bashrc}"
      printf "Автоматически добавлено ~/.local/bin в PATH в %s\n" "${bashrc}"
    else
      printf "PATH уже настроен в %s\n" "${bashrc}"
    fi
  fi

  # zshrc
  if is::file "${zshrc}"; then
    if ! utils::quiet_err grep -Fqx "${line}" "${zshrc}"; then
      printf "\n%s\n" "${line}" >> "${zshrc}"
      printf "Автоматически добавлено ~/.local/bin в PATH в %s\n" "${zshrc}"
    else
      printf "PATH уже настроен в %s\n" "${zshrc}"
    fi
  fi
}