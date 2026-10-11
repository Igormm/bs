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
#
# Вопросы, возникавшие при удалении / Questions raised during uninstall:
#   - ручной guard вроде `if ! [[ "$PATH" =~ "$HOME/.local/bin:..." ]]` в
#     начале .bashrc НЕ удаляется: это не точное совпадение строки, и
#     grep -Fvx его пропускает (защита пользовательских правок).
#     A manual guard like `if ! [[ "$PATH" =~ "$HOME/.local/bin:..." ]]`
#     at the top of .bashrc is NOT removed: it is not an exact line match,
#     so grep -Fvx skips it (user-edit protection).
#   - read-only rc-файл: mv падает, функция возвращает 1, вызывающий код
#     (do_uninstall) продолжает с || true — удаление не прерывается.
#     A read-only rc file: mv fails, the function returns 1 and the caller
#     (do_uninstall) continues with || true — uninstall is not aborted.
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
  # tmp-файл создаётся рядом с rc-файлом: mv в пределах одного каталога —
  # атомарный rename, не копирование через файловые системы.
  # The tmp file lives next to the rc file: mv within one directory is an
  # atomic rename, not a cross-filesystem copy.
  tmp_file="${rc_file}.bs.$$.tmp"
  if ! utils::attempt grep -Fvx "${line}" "${rc_file}" > "${tmp_file}"; then
    rm -f "${tmp_file}"
    printf "Не удалось прочитать %s\n" "${rc_file}" >&2
    return 1
  fi
  if ! mv "${tmp_file}" "${rc_file}"; then
    rm -f "${tmp_file}"
    printf "Не удалось изменить %s (нет прав записи?)\n" "${rc_file}" >&2
    return 1
  fi
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

  # Установщик — дочерний процесс и не может изменить PATH запустившей его
  # оболочки: rc-файл подхватит только новый терминал. Подсказываем команду
  # для текущего.
  # The installer is a child process and cannot change the PATH of the shell
  # that started it: only a new terminal reads the rc file. Hint the command
  # for the current one.
  if [[ ":${INSTALL_ORIG_PATH:-${PATH}}:" != *":${BIN_DIR}:"* ]]; then
    local shell_name="${SHELL##*/}"
    local rc_hint="${bashrc}"
    [[ "${shell_name}" == "zsh" ]] && is::file "${zshrc}" && rc_hint="${zshrc}"

    # В терминале применяем сами: заменяем установщик новой оболочкой
    # пользователя — она читает rc-файл, как при source. Сделать source в
    # уже запущенной оболочке дочерний процесс не может.
    # In a terminal apply it ourselves: replace the installer with a fresh
    # user shell — it reads the rc file, just like source would. A child
    # process cannot source into the shell that is already running.
    if [[ -t 0 && -t 1 && -x "${SHELL:-}" && ( "${shell_name}" == "zsh" || "${shell_name}" == "bash" ) ]]; then
      log::header "PATH ПРИМЕНЁН / PATH APPLIED"
      log::success "выполнено: source ${rc_hint} — запущена новая оболочка ${shell_name}, bs доступен"
      log::success "done: source ${rc_hint} — a fresh ${shell_name} is started, bs is available"
      log::info "exit — вернуться в прежнюю оболочку / back to the previous shell"
      exec "${SHELL}"
    fi

    printf "\nВ ЭТОМ терминале bs появится после / In THIS terminal run:\n"
    printf "  source %s\n" "${rc_hint}"
    printf "или откройте новый терминал / or open a new terminal.\n"
  fi
}