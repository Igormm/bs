#!/usr/bin/env bash
# @tier core — bash 4+ only (the installer runs in bash; see bootstrap/trampoline.sh)
# @tier core — только bash 4+ (установщик работает в bash; см. bootstrap/trampoline.sh)
# @shell bash4 — runs in bash; WRITES for every shell through the registry
# @shell bash4 — исполняется в bash; ПИШЕТ для любой оболочки через реестр

# PATH management functions — the shell of the USER, not the shell of the
# installer: the rc file, the PATH syntax and the reload command come from
# the registry in bootstrap/shell.sh (bash, zsh, ash/dash/sh, ksh, osh, fish, nu).
# Функции PATH — для оболочки ПОЛЬЗОВАТЕЛЯ, а не оболочки установщика: rc-файл,
# синтаксис PATH и команда перезагрузки берутся из реестра bootstrap/shell.sh.

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

# Оболочка пользователя (по реестру), считается один раз за запуск.
# The user's shell (from the registry), computed once per run.
install_user_shell() {
  if [[ -z "${INSTALL_USER_SHELL:-}" ]]; then
    INSTALL_USER_SHELL="$(bs_shell_user)"
  fi
  printf '%s\n' "${INSTALL_USER_SHELL}"
}

# Строка PATH для стандартного ~/.local/bin в синтаксисе семейства.
# The PATH line for the standard ~/.local/bin in the syntax of a family.
path_manager_line() {
  bs_shell_path_line "$1" '$HOME/.local/bin'
}

# Print PATH hint after local install / Подсказка про PATH после локальной установки
print_path_hint() {
  local fam rc line reload
  fam="$(install_user_shell)"
  bs_shell_known "${fam}" || fam="bash"
  rc="$(bs_shell_rc_file "${fam}")"
  line="$(bs_shell_path_line "${fam}" "${BIN_DIR}")"
  reload="$(bs_shell_reload_hint "${fam}")"
  cat <<EOF
Каталога ${BIN_DIR} нет в PATH — команда bs не найдётся / ${BIN_DIR} is not in PATH — the bs command will not be found.
Добавьте каталог с bs в PATH / Add the bs bin directory to PATH (shell: ${fam}):

  ${line}

Строку — в ${rc}, затем в этом терминале / Put the line into ${rc}, then in this terminal:
  ${reload}
EOF
  # Авто-настройка умеет только стандартный ~/.local/bin.
  # The automatic setup handles only the standard ~/.local/bin.
  if [[ "${MODE:-}" == "local" && "${BIN_DIR}" == "${HOME:-}/.local/bin" ]]; then
    printf '\nИли выполните авто-настройку / Or run the automatic setup:\n  ./install.sh --local --update-path\n'
  fi
}

# Удалить строку PATH, добавленную установщиком, из rc-файла (идемпотентно).
# Удаляется только точное совпадение строки; пользовательские правки не трогаем.
# Remove the installer-added PATH line from an rc file (idempotent).
# Only an exact line match is removed; user edits are left untouched.
#
# $1 — rc-файл / rc file; $2 — строка (по умолчанию строка POSIX-оболочек) /
# the line (default: the POSIX-shell line)
#
# Вопросы, возникавшие при удалении / Questions raised during uninstall:
#   - ручной guard вроде `if ! [[ "$PATH" =~ "$HOME/.local/bin:..." ]]` в
#     начале .bashrc НЕ удаляется: это не точное совпадение строки, и
#     grep -Fvx его пропускает (защита пользовательских правок).
#     A manual guard like `if ! [[ "$PATH" =~ "$HOME/.local/bin:..." ]]`
#     at the top of .bashrc is NOT removed: it is not an exact line match,
#     so grep -Fvx skips it (user-edit protection).
#   - read-only rc-файл: запись падает, функция возвращает 1, вызывающий код
#     (do_uninstall) продолжает с || true — удаление не прерывается.
#     A read-only rc file: the write fails, the function returns 1 and the
#     caller (do_uninstall) continues with || true — uninstall is not aborted.
remove_path_entry() {
  local rc_file="$1"
  local line="${2:-export PATH=\"\$HOME/.local/bin:\$PATH\"}"
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

  # Файл, который создал сам установщик (fish: conf.d/bs.fish), без нашей
  # строки пуст — убираем и его; чужие файлы остаются.
  # A file the installer created itself (fish: conf.d/bs.fish) is empty
  # without our line — it goes too; other people's files stay.
  if [[ "${rc_file}" == */conf.d/bs.fish ]] && ! grep -q '[^[:space:]]' -- "${rc_file}" 2>/dev/null; then
    rm -f -- "${rc_file}"
    printf "Удалён пустой файл %s\n" "${rc_file}"
  fi
  return 0
}

# Убрать строку PATH из rc-файлов ВСЕХ известных оболочек (каждая — в своём
# синтаксисе). Нужна при удалении: оболочку пользователя могли сменить после
# установки. Общие файлы (~/.profile у dash/ash/ksh) обрабатываются один раз.
# Remove the PATH line from the rc files of ALL known shells (each in its own
# syntax). Needed on uninstall: the user may have changed the shell since the
# install. Shared files (~/.profile of dash/ash/ksh) are handled once.
remove_path_entries_all() {
  local fam rc line key
  local -A done_keys=()
  for fam in bash zsh sh ksh osh fish nu; do
    rc="$(bs_shell_rc_file "${fam}")" || continue
    line="$(path_manager_line "${fam}")"
    key="${rc}|${line}"
    [[ -z "${done_keys[${key}]:-}" ]] || continue
    done_keys["${key}"]=1
    remove_path_entry "${rc}" "${line}" || true
  done
  return 0
}

# Цели авто-настройки: «семейство<TAB>rc-файл». Оболочка пользователя (файл
# создаётся, если его нет) и уже существующие rc bash и zsh (как всегда было).
# Auto-setup targets: "family<TAB>rc file". The user's shell (the file is
# created if missing) and the bash and zsh rc files that already exist (as it
# always was).
path_manager_targets() {
  local user fam rc
  local -A seen=()
  user="$(install_user_shell)"
  if bs_shell_known "${user}"; then
    rc="$(bs_shell_rc_file "${user}")"
    seen["${rc}"]=1
    printf '%s\t%s\n' "${user}" "${rc}"
  fi
  for fam in bash zsh; do
    rc="$(bs_shell_rc_file "${fam}")"
    [[ -f "${rc}" && -z "${seen[${rc}]:-}" ]] || continue
    seen["${rc}"]=1
    printf '%s\t%s\n' "${fam}" "${rc}"
  done
}

# Auto add PATH for the user's shell (idempotent)
auto_update_path() {
  local user reload fam rc
  user="$(install_user_shell)"

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

  if ! bs_shell_known "${user}"; then
    install_box "ОБОЛОЧКА НЕ РАСПОЗНАНА / SHELL NOT RECOGNISED" \
      "• оболочка '${user}' не известна установщику / the shell '${user}' is not known to the installer" \
      "PATH настроен для bash и zsh (если их rc-файлы есть); для вашей оболочки добавьте ${BIN_DIR} в PATH сами / PATH is set for bash and zsh (when their rc files exist); add ${BIN_DIR} to PATH in your shell yourself"
  fi

  while IFS=$'\t' read -r fam rc; do
    [[ -n "${fam}" ]] || continue
    path_manager_add_for "${fam}" "${rc}"
  done < <(path_manager_targets)

  # Установщик — дочерний процесс и не может изменить PATH запустившей его
  # оболочки: rc-файл подхватит только новый терминал. Подсказываем команду
  # для текущего.
  # The installer is a child process and cannot change the PATH of the shell
  # that started it: only a new terminal reads the rc file. Hint the command
  # for the current one.
  if ! install_in_path "${BIN_DIR}" && bs_shell_known "${user}"; then
    reload="$(bs_shell_reload_hint "${user}")"
    local login_bin flags
    login_bin="$(bs_shell_login_path)"
    flags="$(bs_shell_fresh_flags "${user}")"

    # В терминале применяем сами: заменяем установщик новой оболочкой
    # пользователя — она читает rc-файл, как при source. Сделать source в
    # уже запущенной оболочке дочерний процесс не может. Только если логин-оболочка —
    # именно та оболочка, для которой мы писали PATH.
    # In a terminal apply it ourselves: replace the installer with a fresh
    # user shell — it reads the rc file, just like source would. A child
    # process cannot source into the shell that is already running. Only when
    # the login shell is exactly the shell we wrote the PATH for.
    if [[ -t 0 && -t 1 && -x "${login_bin}" \
          && "$(bs_shell_of_name "${login_bin}")" == "${user}" ]]; then
      log::header "PATH ПРИМЕНЁН / PATH APPLIED"
      log::success "выполнено: ${reload} — запущена новая оболочка ${user}, bs доступен"
      log::success "done: ${reload} — a fresh ${user} is started, bs is available"
      log::info "exit — вернуться в прежнюю оболочку / back to the previous shell"
      # shellcheck disable=SC2086  # flags — либо пусто, либо один флаг
      exec "${login_bin}" ${flags}
    fi

    printf "\nВ ЭТОМ терминале bs появится после / In THIS terminal run:\n"
    printf "  %s\n" "${reload}"
    printf "или откройте новый терминал / or open a new terminal.\n"
  fi
}

# Добавить строку PATH для семейства $1 в rc-файл $2. Для nushell файл не
# создаётся: пустой env.nu помешал бы nu создать свою конфигурацию — вместо
# этого печатается точная строка.
# Add the PATH line for family $1 to rc file $2. For nushell the file is not
# created: a bare env.nu would keep nu from creating its own configuration —
# the exact line is printed instead.
path_manager_add_for() {
  local -r fam="$1" rc="$2"
  local line
  line="$(path_manager_line "${fam}")"
  if [[ "${fam}" == "nu" && ! -f "${rc}" ]]; then
    printf "ВНИМАНИЕ: %s не существует — nushell не настроен; добавьте строку сами:\nNOTE: %s does not exist — nushell is not set up; add the line yourself:\n  %s\n" \
      "${rc}" "${rc}" "${line}"
    return 0
  fi
  path_manager_add_line "${rc}" "${line}"
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
  if mkdir -p -- "$(dirname -- "${rc}")" 2>/dev/null \
     && printf "\n%s\n" "${line}" >> "${rc}" 2>/dev/null; then
    printf "Автоматически добавлено ~/.local/bin в PATH в %s\n" "${rc}"
  else
    printf "ВНИМАНИЕ: не удалось записать в %s (нет прав?). Добавьте строку вручную:\nNOTE: cannot write to %s (read-only?). Add the line by hand:\n  %s\n" \
      "${rc}" "${rc}" "${line}"
  fi
  return 0
}
