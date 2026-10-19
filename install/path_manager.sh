#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, printf, test, grep/mktemp/cat; карты — из core/data.sh; ПИШЕТ rc-файлы любой оболочки через реестр / valid POSIX sh: case, printf, test, grep/mktemp/cat; maps come from core/data.sh; WRITES the rc files of every shell through the registry
# @tier core — builtins, grep, mktemp, cat, dirname; works everywhere
#
# PATH management functions — the shell of the USER, not the shell of the
# installer: the rc file, the PATH syntax and the reload command come from
# the registry in bootstrap/shell.sh (bash, zsh, ash/dash/sh, ksh, osh, fish, nu).
# Функции PATH — для оболочки ПОЛЬЗОВАТЕЛЯ, а не оболочки установщика: rc-файл,
# синтаксис PATH и команда перезагрузки берутся из реестра bootstrap/shell.sh.
#
# ИМЕНА / NAMES
#   Real functions: bs_confirm, bs_install_user_shell, bs_path_manager_line, bs_print_path_hint,
#   bs_remove_path_entry, bs_remove_path_entries_all, bs_path_manager_targets, bs_auto_update_path,
#   bs_path_manager_add_for, bs_path_manager_add_line; in bash and zsh also the old names
#   confirm, install_user_shell, print_path_hint, … (aliases).
#   Настоящие функции — bs_*; в bash и zsh — ещё и прежние confirm, install_user_shell,
#   print_path_hint, … (псевдонимы).

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# Ask a yes/no question, default is "No" / Вопрос да/нет, по умолчанию «нет»
# @param $1 prompt / вопрос
bs_confirm() {
  printf "%s [y/N] " "${1:-Are you sure?}" >&2
  read -r __bs_pm_answer || return 1
  case "${__bs_pm_answer}" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# Оболочка пользователя (по реестру), считается один раз за запуск.
# The user's shell (from the registry), computed once per run.
bs_install_user_shell() {
  if [ -z "${INSTALL_USER_SHELL:-}" ]; then
    INSTALL_USER_SHELL="$(bs_shell_user)"
  fi
  printf '%s\n' "${INSTALL_USER_SHELL}"
}

# Строка PATH для стандартного ~/.local/bin в синтаксисе семейства.
# The PATH line for the standard ~/.local/bin in the syntax of a family.
bs_path_manager_line() {
  # shellcheck disable=SC2016  # $HOME должен попасть в rc-файл как текст / $HOME must reach the rc file as text
  bs_shell_path_line "$1" '$HOME/.local/bin'
}

# Print PATH hint after local install / Подсказка про PATH после локальной установки
bs_print_path_hint() {
  __bs_pm_fam=$(bs_install_user_shell)
  bs_shell_known "${__bs_pm_fam}" || __bs_pm_fam="bash"
  __bs_pm_rc=$(bs_shell_rc_file "${__bs_pm_fam}")
  __bs_pm_line=$(bs_shell_path_line "${__bs_pm_fam}" "${BIN_DIR}")
  __bs_pm_reload=$(bs_shell_reload_hint "${__bs_pm_fam}")
  cat <<EOF
Каталога ${BIN_DIR} нет в PATH — команда bs не найдётся / ${BIN_DIR} is not in PATH — the bs command will not be found.
Добавьте каталог с bs в PATH / Add the bs bin directory to PATH (shell: ${__bs_pm_fam}):

  ${__bs_pm_line}

Строку — в ${__bs_pm_rc}, затем в этом терминале / Put the line into ${__bs_pm_rc}, then in this terminal:
  ${__bs_pm_reload}
EOF
  # Авто-настройка умеет только стандартный ~/.local/bin.
  # The automatic setup handles only the standard ~/.local/bin.
  if [ "${MODE:-}" = "local" ] && [ "${BIN_DIR}" = "${HOME:-}/.local/bin" ]; then
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
#     (bs_do_uninstall) продолжает с || true — удаление не прерывается.
#     A read-only rc file: the write fails, the function returns 1 and the
#     caller (bs_do_uninstall) continues with || true — uninstall is not aborted.
bs_remove_path_entry() {
  __bs_pm_rcf=$1
  # строка POSIX-оболочек по умолчанию; в переменной, чтобы кавычки не зависели от оболочки / the default POSIX-shell line, in a variable so the quotes do not depend on the shell
  # shellcheck disable=SC2016  # строка для rc-файла: $HOME и $PATH не раскрываются / a line for an rc file: $HOME and $PATH are not expanded
  __bs_pm_dl='export PATH="$HOME/.local/bin:$PATH"'
  __bs_pm_ln=${2:-$__bs_pm_dl}

  if [ ! -f "${__bs_pm_rcf}" ]; then
    return 0
  fi

  if ! bs_utils_quiet grep -Fqx "${__bs_pm_ln}" "${__bs_pm_rcf}"; then
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
  __bs_pm_tmp=$(mktemp 2>/dev/null) || __bs_pm_tmp=""
  if [ -z "${__bs_pm_tmp}" ]; then
    printf "Не удалось создать временный файл для %s\n" "${__bs_pm_rcf}" >&2
    return 1
  fi
  if ! bs_utils_attempt grep -Fvx "${__bs_pm_ln}" "${__bs_pm_rcf}" > "${__bs_pm_tmp}"; then
    rm -f "${__bs_pm_tmp}"
    printf "Не удалось прочитать %s\n" "${__bs_pm_rcf}" >&2
    return 1
  fi
  if ! cat -- "${__bs_pm_tmp}" > "${__bs_pm_rcf}" 2>/dev/null; then
    rm -f "${__bs_pm_tmp}"
    printf "Не удалось изменить %s (нет прав записи?) — удалите строку PATH вручную\nCannot modify %s (read-only?) — remove the PATH line by hand\n" "${__bs_pm_rcf}" "${__bs_pm_rcf}" >&2
    return 1
  fi
  rm -f "${__bs_pm_tmp}"
  printf "Удалена строка PATH из %s\nPath line removed from %s\n" "${__bs_pm_rcf}" "${__bs_pm_rcf}"

  # Файл, который создал сам установщик (fish: conf.d/bs.fish), без нашей
  # строки пуст — убираем и его; чужие файлы остаются.
  # A file the installer created itself (fish: conf.d/bs.fish) is empty
  # without our line — it goes too; other people's files stay.
  case "${__bs_pm_rcf}" in
    */conf.d/bs.fish)
      if ! grep -q '[^[:space:]]' -- "${__bs_pm_rcf}" 2>/dev/null; then
        rm -f -- "${__bs_pm_rcf}"
        printf "Удалён пустой файл %s\n" "${__bs_pm_rcf}"
      fi ;;
  esac
  return 0
}

# Убрать строку PATH из rc-файлов ВСЕХ известных оболочек (каждая — в своём
# синтаксисе). Нужна при удалении: оболочку пользователя могли сменить после
# установки. Общие файлы (~/.profile у dash/ash/ksh) обрабатываются один раз.
# Remove the PATH line from the rc files of ALL known shells (each in its own
# syntax). Needed on uninstall: the user may have changed the shell since the
# install. Shared files (~/.profile of dash/ash/ksh) are handled once.
bs_remove_path_entries_all() {
  bs_map_clear bs_pm_done
  for __bs_pm_efam in bash zsh sh ksh osh fish nu; do
    __bs_pm_erc=$(bs_shell_rc_file "${__bs_pm_efam}") || continue
    __bs_pm_eline=$(bs_path_manager_line "${__bs_pm_efam}")
    __bs_pm_ekey="${__bs_pm_erc}|${__bs_pm_eline}"
    if bs_map_has bs_pm_done "${__bs_pm_ekey}"; then continue; fi
    bs_map_set bs_pm_done "${__bs_pm_ekey}" 1
    bs_remove_path_entry "${__bs_pm_erc}" "${__bs_pm_eline}" || true
  done
  return 0
}

# Цели авто-настройки: «семейство<TAB>rc-файл». Оболочка пользователя (файл
# создаётся, если его нет) и уже существующие rc bash и zsh (как всегда было).
# Auto-setup targets: "family<TAB>rc file". The user's shell (the file is
# created if missing) and the bash and zsh rc files that already exist (as it
# always was).
bs_path_manager_targets() {
  bs_map_clear bs_pm_seen
  __bs_pm_tuser=$(bs_install_user_shell)
  if bs_shell_known "${__bs_pm_tuser}"; then
    __bs_pm_trc=$(bs_shell_rc_file "${__bs_pm_tuser}")
    bs_map_set bs_pm_seen "${__bs_pm_trc}" 1
    printf '%s\t%s\n' "${__bs_pm_tuser}" "${__bs_pm_trc}"
  fi
  for __bs_pm_tfam in bash zsh; do
    __bs_pm_trc=$(bs_shell_rc_file "${__bs_pm_tfam}")
    if [ -f "${__bs_pm_trc}" ] && ! bs_map_has bs_pm_seen "${__bs_pm_trc}"; then
      bs_map_set bs_pm_seen "${__bs_pm_trc}" 1
      printf '%s\t%s\n' "${__bs_pm_tfam}" "${__bs_pm_trc}"
    fi
  done
}

# Auto add PATH for the user's shell (idempotent)
bs_auto_update_path() {
  __bs_pm_user=$(bs_install_user_shell)

  # Авто-настройка пишет строку с $HOME/.local/bin. Для другого BIN_DIR она
  # была бы неверной (и её не снял бы uninstall) — объясняем и отдаём подсказку.
  # The auto setup writes a $HOME/.local/bin line. For another BIN_DIR it
  # would be wrong (and uninstall would not remove it) — explain and hint.
  if [ "${BIN_DIR}" != "${HOME}/.local/bin" ]; then
    bs_install_box "АВТО-НАСТРОЙКА PATH НЕ ВЫПОЛНЕНА / PATH AUTO-SETUP SKIPPED" \
      "• BIN_DIR=${BIN_DIR} — не стандартный ~/.local/bin / is not the standard ~/.local/bin" \
      "Авто-настройка знает только ~/.local/bin; rc-файлы не изменены / The auto setup knows only ~/.local/bin; rc files are untouched"
    if ! bs_install_in_path "${BIN_DIR}"; then
      bs_print_path_hint
    fi
    return 0
  fi

  if ! bs_shell_known "${__bs_pm_user}"; then
    bs_install_box "ОБОЛОЧКА НЕ РАСПОЗНАНА / SHELL NOT RECOGNISED" \
      "• оболочка '${__bs_pm_user}' не известна установщику / the shell '${__bs_pm_user}' is not known to the installer" \
      "PATH настроен для bash и zsh (если их rc-файлы есть); для вашей оболочки добавьте ${BIN_DIR} в PATH сами / PATH is set for bash and zsh (when their rc files exist); add ${BIN_DIR} to PATH in your shell yourself"
  fi

  # Цели собираются заранее: цикл читает их из here-document в ТЕКУЩЕЙ оболочке.
  # The targets are collected first: the loop reads them from a here-document in the CURRENT shell.
  __bs_pm_targets=$(bs_path_manager_targets)
  __bs_pm_tab=$(printf '\t')
  if [ -n "${__bs_pm_targets}" ]; then
    while IFS="${__bs_pm_tab}" read -r __bs_pm_tfam2 __bs_pm_trc2; do
      if [ -z "${__bs_pm_tfam2}" ]; then continue; fi
      bs_path_manager_add_for "${__bs_pm_tfam2}" "${__bs_pm_trc2}"
    done <<EOF
${__bs_pm_targets}
EOF
  fi

  # Установщик — дочерний процесс и не может изменить PATH запустившей его
  # оболочки: rc-файл подхватит только новый терминал. Подсказываем команду
  # для текущего.
  # The installer is a child process and cannot change the PATH of the shell
  # that started it: only a new terminal reads the rc file. Hint the command
  # for the current one.
  if ! bs_install_in_path "${BIN_DIR}" && bs_shell_known "${__bs_pm_user}"; then
    __bs_pm_reload=$(bs_shell_reload_hint "${__bs_pm_user}")
    __bs_pm_login=$(bs_shell_login_path)
    __bs_pm_flags=$(bs_shell_fresh_flags "${__bs_pm_user}")

    # В терминале применяем сами: заменяем установщик новой оболочкой
    # пользователя — она читает rc-файл, как при source. Сделать source в
    # уже запущенной оболочке дочерний процесс не может. Только если логин-оболочка —
    # именно та оболочка, для которой мы писали PATH.
    # In a terminal apply it ourselves: replace the installer with a fresh
    # user shell — it reads the rc file, just like source would. A child
    # process cannot source into the shell that is already running. Only when
    # the login shell is exactly the shell we wrote the PATH for.
    if [ -t 0 ] && [ -t 1 ] && [ -x "${__bs_pm_login}" ] \
       && [ "$(bs_shell_of_name "${__bs_pm_login}")" = "${__bs_pm_user}" ]; then
      bs_log_header "PATH ПРИМЕНЁН / PATH APPLIED"
      bs_log_success "выполнено: ${__bs_pm_reload} — запущена новая оболочка ${__bs_pm_user}, bs доступен"
      bs_log_success "done: ${__bs_pm_reload} — a fresh ${__bs_pm_user} is started, bs is available"
      bs_log_info "exit — вернуться в прежнюю оболочку / back to the previous shell"
      # shellcheck disable=SC2086  # flags — либо пусто, либо один флаг
      exec "${__bs_pm_login}" ${__bs_pm_flags}
    fi

    printf "\nВ ЭТОМ терминале bs появится после / In THIS terminal run:\n"
    printf "  %s\n" "${__bs_pm_reload}"
    printf "или откройте новый терминал / or open a new terminal.\n"
  fi
}

# Добавить строку PATH для семейства $1 в rc-файл $2. Для nushell файл не
# создаётся: пустой env.nu помешал бы nu создать свою конфигурацию — вместо
# этого печатается точная строка.
# Add the PATH line for family $1 to rc file $2. For nushell the file is not
# created: a bare env.nu would keep nu from creating its own configuration —
# the exact line is printed instead.
bs_path_manager_add_for() {
  __bs_pm_afam=$1
  __bs_pm_arc=$2
  __bs_pm_aline=$(bs_path_manager_line "${__bs_pm_afam}")
  if ! bs_shell_rc_create_ok "${__bs_pm_afam}" && [ ! -f "${__bs_pm_arc}" ]; then
    printf "ВНИМАНИЕ: %s не существует — nushell не настроен; добавьте строку сами:\nNOTE: %s does not exist — nushell is not set up; add the line yourself:\n  %s\n" \
      "${__bs_pm_arc}" "${__bs_pm_arc}" "${__bs_pm_aline}"
    return 0
  fi
  bs_path_manager_add_line "${__bs_pm_arc}" "${__bs_pm_aline}"
}

# Добавить строку PATH в rc-файл $1 (идемпотентно, только точное совпадение
# строки). Нельзя записать — объясняем и не обрываем установку.
# Add the PATH line $2 to rc file $1 (idempotent, exact line match only).
# If it cannot be written, explain instead of aborting the install.
bs_path_manager_add_line() {
  __bs_pm_lrc=$1
  __bs_pm_lline=$2
  if bs_utils_quiet_err grep -Fqx "${__bs_pm_lline}" "${__bs_pm_lrc}"; then
    printf "PATH уже настроен в %s\n" "${__bs_pm_lrc}"
    return 0
  fi
  if mkdir -p -- "$(dirname -- "${__bs_pm_lrc}")" 2>/dev/null \
     && printf "\n%s\n" "${__bs_pm_lline}" >> "${__bs_pm_lrc}" 2>/dev/null; then
    printf "Автоматически добавлено ~/.local/bin в PATH в %s\n" "${__bs_pm_lrc}"
  else
    printf "ВНИМАНИЕ: не удалось записать в %s (нет прав?). Добавьте строку вручную:\nNOTE: cannot write to %s (read-only?). Add the line by hand:\n  %s\n" \
      "${__bs_pm_lrc}" "${__bs_pm_lrc}" "${__bs_pm_lline}"
  fi
  return 0
}

bs_shell_alias bs_confirm confirm
bs_shell_alias bs_install_user_shell install_user_shell
bs_shell_alias bs_path_manager_line path_manager_line
bs_shell_alias bs_print_path_hint print_path_hint
bs_shell_alias bs_remove_path_entry remove_path_entry
bs_shell_alias bs_remove_path_entries_all remove_path_entries_all
bs_shell_alias bs_path_manager_targets path_manager_targets
bs_shell_alias bs_auto_update_path auto_update_path
bs_shell_alias bs_path_manager_add_for path_manager_add_for
bs_shell_alias bs_path_manager_add_line path_manager_add_line
