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
Каталога ${BIN_DIR} нет в PATH — команда bs не найдётся / ${BIN_DIR} is not in PATH — the bs command will not be found.
Добавьте каталог с bs в PATH / Add the bs bin directory to PATH:

  export PATH="${BIN_DIR}:\$PATH"

Например, для bash / For bash, for example:
  echo 'export PATH="${BIN_DIR}:\$PATH"' >> ~/.bashrc
  source ~/.bashrc
EOF
  # Авто-настройка умеет только стандартный ~/.local/bin.
  # The automatic setup handles only the standard ~/.local/bin.
  if [[ "${MODE:-}" == "local" && "${BIN_DIR}" == "${HOME:-}/.local/bin" ]]; then
    printf '\nИли выполните авто-настройку / Or run the automatic setup:\n  ./install.sh --local --update-path\n'
  fi
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
  # (файл состоял лишь из этой строки) остаётся пустой файл.
  # Перезапись на месте (cat >), а не mv: сохраняет владельца, права и
  # симлинк (rc-файл из dotfiles-репозитория) — mv заменил бы их, а под
  # sudo сделал бы файл root-овым. Временный файл — в TMPDIR.
  # Rewrite in place (cat >), not mv: keeps owner, mode and symlink (an rc
  # file managed by a dotfiles repo) — mv would replace them and, under
  # sudo, make the file root-owned. The temporary file lives in TMPDIR.
  tmp_file="$(mktemp 2>/dev/null)" || tmp_file=""
  if [[ -z "${tmp_file}" ]]; then
    printf "Не удалось создать временный файл для %s\n" "${rc_file}" >&2
    return 1
  fi
  if ! utils::attempt grep -Fvx "${line}" "${rc_file}" > "${tmp_file}"; then
    rm -f "${tmp_file}"
    printf "Не удалось прочитать %s\n" "${rc_file}" >&2
    return 1
  fi
  if ! cat -- "${tmp_file}" > "${rc_file}" 2>/dev/null; then
    rm -f "${tmp_file}"
    printf "Не удалось изменить %s (нет прав записи?) — удалите строку PATH вручную\nCannot modify %s (read-only?) — remove the PATH line by hand\n" "${rc_file}" "${rc_file}" >&2
    return 1
  fi
  rm -f "${tmp_file}"
  printf "Удалена строка PATH из %s\nPath line removed from %s\n" "${rc_file}" "${rc_file}"
}

# Auto add PATH to bash/zsh (idempotent)
auto_update_path() {
  local bashrc="${HOME}/.bashrc"
  local zshrc="${HOME}/.zshrc"
  local line='export PATH="$HOME/.local/bin:$PATH"'

  # Авто-настройка пишет строку с $HOME/.local/bin. Для другого BIN_DIR она
  # была бы неверной (и её не снял бы uninstall) — объясняем и отдаём подсказку.
  # The auto setup writes a $HOME/.local/bin line. For another BIN_DIR it
  # would be wrong (and uninstall would not remove it) — explain and hint.
  if [[ "${BIN_DIR}" != "${HOME}/.local/bin" ]]; then
    install_box "АВТО-НАСТРОЙКА PATH НЕ ВЫПОЛНЕНА / PATH AUTO-SETUP SKIPPED" \
      "• BIN_DIR=${BIN_DIR} — не стандартный ~/.local/bin / is not the standard ~/.local/bin" \
      "Авто-настройка знает только ~/.local/bin; rc-файлы не изменены / The auto setup knows only ~/.local/bin; rc files are untouched"
    if ! install_in_path "${BIN_DIR}"; then
      print_path_hint
    fi
    return 0
  fi

  # bashrc
  if is::file "${bashrc}" || ! is::file "${zshrc}"; then
    path_manager_add_line "${bashrc}" "${line}"
  fi

  # zshrc
  if is::file "${zshrc}"; then
    path_manager_add_line "${zshrc}" "${line}"
  fi

  # Установщик — дочерний процесс и не может изменить PATH запустившей его
  # оболочки: rc-файл подхватит только новый терминал. Подсказываем команду
  # для текущего.
  # The installer is a child process and cannot change the PATH of the shell
  # that started it: only a new terminal reads the rc file. Hint the command
  # for the current one.
  if ! install_in_path "${BIN_DIR}"; then
    local shell_name="${SHELL:-}"
    shell_name="${shell_name##*/}"
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

# Добавить строку PATH в rc-файл $1 (идемпотентно, только точное совпадение
# строки). Нельзя записать — объясняем и не обрываем установку.
# Add the PATH line $2 to rc file $1 (idempotent, exact line match only).
# If it cannot be written, explain instead of aborting the install.
path_manager_add_line() {
  local -r rc="$1" line="$2"
  if utils::quiet_err grep -Fqx "${line}" "${rc}"; then
    printf "PATH уже настроен в %s\n" "${rc}"
    return 0
  fi
  if printf "\n%s\n" "${line}" >> "${rc}" 2>/dev/null; then
    printf "Автоматически добавлено ~/.local/bin в PATH в %s\n" "${rc}"
  else
    printf "ВНИМАНИЕ: не удалось записать в %s (нет прав?). Добавьте строку вручную:\nNOTE: cannot write to %s (read-only?). Add the line by hand:\n  %s\n" \
      "${rc}" "${rc}" "${line}"
  fi
  return 0
}
