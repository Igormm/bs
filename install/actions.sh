#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, printf, test, cp/mv/rm/mkdir/mktemp; списки строк — массивы из core/data.sh / valid POSIX sh: case, printf, test, cp/mv/rm/mkdir/mktemp; row lists are arrays from core/data.sh
# @tier core — builtins, cp, mv, rm, mkdir, rmdir, chmod, grep, date, id; works everywhere
# shellcheck disable=SC2034  # INSTALL_ACTION is read by notice.sh / читается в notice.sh
#
# Installation and uninstallation functions
# Функции установки и удаления
#
# bs_do_install и bs_do_uninstall — действия точки входа install.sh: на отказе они зовут exit
# (как и прежние do_install/do_uninstall); остальные функции возвращают код.
# bs_do_install and bs_do_uninstall are the actions of the install.sh entry point: on a refusal
# they call exit (as the old do_install/do_uninstall did); the other functions return a code.
#
# ИМЕНА / NAMES
#   Real functions: bs_write_install_manifest, bs_install_rollback, bs_install_tx_fail,
#   bs_install_step, bs_install_write_wrapper, bs_install_transaction, bs_install_completion,
#   bs_uninstall_completion, bs_do_install, bs_install_kind_of_target, bs_do_uninstall; in bash and
#   zsh also write_install_manifest, install_rollback, … do_install, do_uninstall (the old names).
#   Настоящие функции — bs_*; в bash и zsh — ещё и прежние write_install_manifest,
#   install_rollback, … do_install, do_uninstall.

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# bs_shebang_fix: подогнать shebang под машину (Termux: нет /usr/bin/env и /bin/sh)
# bs_shebang_fix: adapt the shebang to the machine (Termux: no /usr/bin/env, no /bin/sh)
# shellcheck disable=SC1090,SC1091
. "${BS_BOOTSTRAP_DIR}/shebang.sh"

# Записать манифест установки: как, откуда и куда поставлена эта копия BS.
# Его читают `bs env`, `bs update` и `bs uninstall`.
# Write the install manifest: how, from where and where this BS copy was
# installed. Read by `bs env`, `bs update` and `bs uninstall`.
# $1 — каталог, куда писать (по умолчанию TARGET_LIB; при установке — staging)
bs_write_install_manifest() {
  __bs_act_dest=${1:-${TARGET_LIB}}
  __bs_act_commit=""
  __bs_act_repo=""
  if bs_utils_has git && [ -e "${SOURCE_ROOT}/.git" ]; then
    __bs_act_commit="$(git -C "${SOURCE_ROOT}" rev-parse HEAD 2>/dev/null)" || __bs_act_commit=""
    __bs_act_repo="$(git -C "${SOURCE_ROOT}" remote get-url origin 2>/dev/null)" || __bs_act_repo=""
  fi
  # Вид установки: local/system — стандартные места, иначе custom (как у bs update).
  # Install kind: local/system for standard locations, otherwise custom (like bs update).
  __bs_act_kind="custom"
  for __bs_act_k in local system; do
    if [ "$(bs_install_std_lib "${__bs_act_k}" 2>/dev/null)" = "${TARGET_LIB}" ] \
       && [ "$(bs_install_std_bin "${__bs_act_k}" 2>/dev/null)" = "${TARGET_BIN}" ]; then
      __bs_act_kind="${__bs_act_k}"
    fi
  done
  {
    printf '# BS install manifest — written by install.sh, updated by bs update\n'
    printf 'mode=%s\n' "${__bs_act_kind}"
    printf 'prefix=%s\n' "${PREFIX}"
    printf 'lib=%s\n' "${TARGET_LIB}"
    printf 'bin=%s\n' "${TARGET_BIN}"
    printf 'version=%s\n' "$(bs_version_get)"
    printf 'source=%s\n' "${SOURCE_ROOT}"
    printf 'source_repo=%s\n' "${__bs_act_repo}"
    printf 'source_commit=%s\n' "${__bs_act_commit}"
    printf 'installed_at=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf 'installed_by=%s\n' "${SUDO_USER:-${USER:-$(id -un)}}"
  } > "${__bs_act_dest}/.install"
}

# Состояние транзакции установки (см. bs_install_rollback).
# Install transaction state (see bs_install_rollback).
INSTALL_TX_STAGE=""    # временный каталог с новой копией / staging dir with the new copy
INSTALL_TX_BACKUP=""   # прежняя установка, отложенная в сторону / old install set aside
INSTALL_TX_WTMP=""     # временный wrapper / temporary wrapper
INSTALL_TX_SWAPPED=0   # 1 — новая lib уже на месте TARGET_LIB
INSTALL_TX_ERR=""      # текст ошибки последнего шага / error text of the last step

# Откат: убрать временное, вернуть прежнюю установку. Идемпотентен.
# Roll back: drop temporaries, restore the previous install. Idempotent.
bs_install_rollback() {
  if [ -n "${INSTALL_TX_WTMP}" ]; then rm -f -- "${INSTALL_TX_WTMP}" 2>/dev/null; fi
  if [ "${INSTALL_TX_SWAPPED}" = "1" ]; then
    rm -rf -- "${TARGET_LIB}" 2>/dev/null
    INSTALL_TX_SWAPPED=0
    if [ -n "${INSTALL_TX_BACKUP}" ] && [ -e "${INSTALL_TX_BACKUP}" ]; then
      mv -- "${INSTALL_TX_BACKUP}" "${TARGET_LIB}" 2>/dev/null
      INSTALL_TX_BACKUP=""
    fi
  elif [ -n "${INSTALL_TX_BACKUP}" ] && [ -e "${INSTALL_TX_BACKUP}" ] && [ ! -e "${TARGET_LIB}" ]; then
    # lib отложена, но не заменена — вернуть на место
    # set aside but not replaced — put it back
    mv -- "${INSTALL_TX_BACKUP}" "${TARGET_LIB}" 2>/dev/null
    INSTALL_TX_BACKUP=""
  fi
  if [ -n "${INSTALL_TX_STAGE}" ]; then rm -rf -- "${INSTALL_TX_STAGE}" 2>/dev/null; fi
  INSTALL_TX_STAGE="" INSTALL_TX_WTMP=""
  return 0
}

# Сообщение о сбое установки (после отката). $1 RU шаг, $2 EN шаг, $3 было ли старое
# Install failure message (after rollback). $1 RU step, $2 EN step, $3 had old
bs_install_tx_fail() {
  __bs_act_ru=$1
  __bs_act_en=$2
  __bs_act_had=$3
  # переводы строки в причине — пробелами / newlines in the reason become spaces
  __bs_act_nl='
'
  __bs_act_reason=$(bs_str_replace "${INSTALL_TX_ERR}" "${__bs_act_nl}" " ")
  bs_install_rollback
  __bs_act_keep_ru="Установленных файлов нет, временное убрано"
  __bs_act_keep_en="No installed files; temporaries removed"
  if [ "${__bs_act_had}" = "1" ]; then
    __bs_act_keep_ru="Прежняя установка не тронута: ${TARGET_LIB}"
    __bs_act_keep_en="The previous install is untouched: ${TARGET_LIB}"
  fi
  bs_install_error "Установка не выполнена: ${__bs_act_ru}" \
    "Install failed: ${__bs_act_en}" \
    "Причина / Reason: ${__bs_act_reason:-неизвестна / unknown}" \
    "${__bs_act_keep_ru} / ${__bs_act_keep_en}" \
    "Проверьте свободное место (df -h) и права / Check free space (df -h) and permissions"
  exit 1
}

# Выполнить команду, сохранив её stderr в INSTALL_TX_ERR (ошибка → 1).
# Run a command, keeping its stderr in INSTALL_TX_ERR (failure → 1).
bs_install_step() {
  INSTALL_TX_ERR=""
  if INSTALL_TX_ERR="$("$@" 2>&1)"; then
    return 0
  fi
  return 1
}

# Записать wrapper (POSIX sh: он только передаёт управление bs) / Write the wrapper
# (POSIX sh: it only hands over to bs)
bs_install_write_wrapper() {
  printf '#!/bin/sh\nexport BS_ROOT="%s"\nexec "${BS_ROOT}/bs" "$@"\n' "$1" > "$2" && chmod 0755 "$2" \
    && bs_shebang_fix "$2"
}

# Транзакционная установка: копия во временный каталог рядом с TARGET_LIB,
# затем атомарный rename. При сбое временное убирается, прежняя установка
# остаётся на месте. $1 — 1, если TARGET_LIB уже была (её заменяем).
# Transactional install: copy into a temporary directory next to TARGET_LIB,
# then an atomic rename. On failure the temporaries are removed and the
# previous install stays in place. $1 — 1 if TARGET_LIB already existed.
bs_install_transaction() {
  __bs_act_had=$1
  __bs_act_lstate=$2
  INSTALL_TX_STAGE="${LIB_DIR}/.bs.install.$$"
  INSTALL_TX_BACKUP=""
  INSTALL_TX_WTMP="${BIN_DIR}/.bs.wrapper.$$"
  INSTALL_TX_SWAPPED=0

  # Ctrl-C / kill в середине установки не должны оставлять разрушенное состояние.
  # Ctrl-C / kill mid-install must not leave a broken state behind.
  trap 'bs_install_rollback; exit 130' INT TERM HUP

  bs_install_step mkdir -p -- "${BIN_DIR}" "${LIB_DIR}" \
    || bs_install_tx_fail "не удалось создать каталоги ${BIN_DIR}, ${LIB_DIR}" "cannot create ${BIN_DIR}, ${LIB_DIR}" 0

  bs_install_step mkdir -- "${INSTALL_TX_STAGE}" \
    || bs_install_tx_fail "не удалось создать временный каталог ${INSTALL_TX_STAGE}" "cannot create the temporary directory ${INSTALL_TX_STAGE}" 0

  for __bs_act_item in bootstrap core bs lib; do
    bs_install_step cp -a -- "${SOURCE_ROOT}/${__bs_act_item}" "${INSTALL_TX_STAGE}/" \
      || bs_install_tx_fail "не удалось скопировать ${__bs_act_item}" "cannot copy ${__bs_act_item}" "${__bs_act_had}"
  done

  # shebang копии bs — под эту машину (Termux: $PREFIX/bin/env вместо /usr/bin/env)
  # the shebang of the bs copy — for this machine (Termux: $PREFIX/bin/env, not /usr/bin/env)
  bs_install_step bs_shebang_fix "${INSTALL_TX_STAGE}/bs" \
    || bs_install_tx_fail "не удалось подогнать shebang у bs" "cannot adapt the shebang of bs" "${__bs_act_had}"

  # Манифест — тоже в staging: после rename копия сразу полная.
  # The manifest goes to staging too: after the rename the copy is complete.
  bs_install_step bs_write_install_manifest "${INSTALL_TX_STAGE}" \
    || bs_install_tx_fail "не удалось записать манифест" "cannot write the manifest" "${__bs_act_had}"

  # Wrapper — POSIX sh, не bash: bs сам находит подходящий bash. Во временный файл рядом с целевым (rename в одном каталоге).
  # The wrapper goes to a temporary file next to the target (same-dir rename).
  bs_install_step bs_install_write_wrapper "${TARGET_LIB}" "${INSTALL_TX_WTMP}" \
    || bs_install_tx_fail "не удалось создать wrapper" "cannot create the wrapper" "${__bs_act_had}"

  # Подмена lib: прежнюю (если есть) откладываем, новую переименовываем.
  # Swap lib: set the old one aside (if any), rename the new one in.
  if [ "${__bs_act_lstate}" = "empty" ]; then
    bs_install_step rmdir -- "${TARGET_LIB}" \
      || bs_install_tx_fail "не удалось заменить пустой каталог ${TARGET_LIB}" "cannot replace the empty directory ${TARGET_LIB}" "${__bs_act_had}"
  elif [ "${__bs_act_had}" = "1" ]; then
    INSTALL_TX_BACKUP="${LIB_DIR}/.bs.backup.$$"
    bs_install_step mv -- "${TARGET_LIB}" "${INSTALL_TX_BACKUP}" \
      || { INSTALL_TX_BACKUP=""; bs_install_tx_fail "не удалось отложить прежнюю установку" "cannot set the previous install aside" "${__bs_act_had}"; }
  fi
  bs_install_step mv -- "${INSTALL_TX_STAGE}" "${TARGET_LIB}" \
    || bs_install_tx_fail "не удалось поставить новую копию на место" "cannot move the new copy into place" "${__bs_act_had}"
  INSTALL_TX_SWAPPED=1
  INSTALL_TX_STAGE=""

  bs_install_step mv -f -- "${INSTALL_TX_WTMP}" "${TARGET_BIN}" \
    || bs_install_tx_fail "не удалось установить wrapper ${TARGET_BIN}" "cannot install the wrapper ${TARGET_BIN}" "${__bs_act_had}"
  INSTALL_TX_WTMP=""

  # Успех: отложенную копию можно убрать.
  # Success: the set-aside copy can go.
  if [ -n "${INSTALL_TX_BACKUP}" ]; then
    rm -rf -- "${INSTALL_TX_BACKUP}" 2>/dev/null \
      || bs_install_note "не удалось удалить временную копию ${INSTALL_TX_BACKUP} — удалите вручную" \
                         "could not remove the temporary copy ${INSTALL_TX_BACKUP} — remove it manually"
    INSTALL_TX_BACKUP=""
  fi
  INSTALL_TX_SWAPPED=0
  trap - INT TERM HUP
  return 0
}

# Дополнение bash (share/bash-completion/completions/bs). Не критично для
# работы bs: сбой копирования — предупреждение, установка остаётся успешной.
# Bash completion. Not critical for bs itself: a copy failure is a warning,
# the installation stays successful.
bs_install_completion() {
  __bs_act_src="${SOURCE_ROOT}/share/bash-completion/completions/bs"
  if [ ! -f "${__bs_act_src}" ]; then return 0; fi
  if mkdir -p -- "$(dirname -- "${TARGET_COMPLETION}")" 2>/dev/null \
     && cp -a -- "${__bs_act_src}" "${TARGET_COMPLETION}" 2>/dev/null; then
    printf "Установлено bash-completion / bash completion installed: %s\n" "${TARGET_COMPLETION}"
  else
    bs_install_note "не удалось установить bash-completion в ${TARGET_COMPLETION} (bs работает и без него)" \
                    "could not install the bash completion to ${TARGET_COMPLETION} (bs works without it)"
  fi
  return 0
}

# Удалить дополнение, только если это файл BS (есть функция _bs_complete)
# Remove the completion only if it is BS's own file (has _bs_complete)
bs_uninstall_completion() {
  if [ ! -f "${TARGET_COMPLETION:-}" ]; then return 0; fi
  if grep -q '_bs_complete' -- "${TARGET_COMPLETION}" 2>/dev/null; then
    rm -f -- "${TARGET_COMPLETION}"
    printf "Удален / Removed: %s\n" "${TARGET_COMPLETION}"
  else
    bs_install_note "${TARGET_COMPLETION} не принадлежит BS — оставлен на месте" \
                    "${TARGET_COMPLETION} is not BS's file — left in place"
  fi
  return 0
}

# Install
bs_do_install() {
  INSTALL_ACTION="install"
  bs_install_validate_paths || exit 1

  __bs_act_lstate=$(bs_install_lib_state "${TARGET_LIB}")
  __bs_act_bstate=$(bs_install_bin_state "${TARGET_BIN}" "${TARGET_LIB}")
  __bs_act_broot=$(bs_install_wrapper_root "${TARGET_BIN}")

  # Отказ: под TARGET_LIB лежит не установка BS — ничего не удаляем.
  # Refusal: TARGET_LIB is not a BS install — nothing is deleted.
  case "${__bs_act_lstate}" in
    source|symlink|file|foreign)
      bs_install_error "${TARGET_LIB} уже существует и это не установка BS — установка отменена, ничего не удалено" \
        "${TARGET_LIB} already exists and is not a BS install — aborted, nothing was deleted" \
        "Причина / Reason: $(bs_install_lib_reason "${__bs_act_lstate}")" \
        "Другое место / Another location:  PREFIX=\$HOME/opt/bs ./install.sh --local   (или LIB_DIR=... / or LIB_DIR=...)"
      exit 1 ;;
  esac
  # Отказ: TARGET_BIN занят чужим файлом или wrapper'ом живой установки BS.
  # Refusal: TARGET_BIN is somebody else's file or a live BS wrapper.
  case "${__bs_act_bstate}" in
    foreign)
      bs_install_error "${TARGET_BIN} уже существует и это не wrapper BS (нет строки export BS_ROOT=) — установка отменена, файл не тронут" \
        "${TARGET_BIN} already exists and is not a BS wrapper (no export BS_ROOT= line) — aborted, the file is untouched" \
        "Другое место / Another location:  BIN_DIR=\$HOME/bin $(bs_install_cmd install)" \
        "Либо переименуйте/удалите файл сами / Or rename/remove the file yourself"
      exit 1 ;;
    other)
      bs_install_error "${TARGET_BIN} — wrapper другой установки BS (${__bs_act_broot}, версия $(bs_install_version_of "${__bs_act_broot}")) — установка отменена" \
        "${TARGET_BIN} is the wrapper of another BS install (${__bs_act_broot}, version $(bs_install_version_of "${__bs_act_broot}")) — aborted" \
        "Перезапись переключила бы ту установку на новую копию / Overwriting it would switch that install to the new copy." \
        "Обновить ту установку / Update that one:  bs update --lib ${__bs_act_broot}" \
        "Другой BIN_DIR / Another BIN_DIR:  BIN_DIR=\$HOME/bin $(bs_install_cmd install)"
      exit 1 ;;
  esac

  # Уже установлено в это место.
  # Already installed at this location.
  if [ "${__bs_act_lstate}" = "bs" ] && [ "${__bs_act_bstate}" = "here" ]; then
    __bs_act_upd="bs update"
    __bs_act_repo_upd=""
    __bs_act_rc_cmp=0
    bs_arr_clear bs_act_rows
    case "$(bs_install_kind_of_target)" in
      local)  __bs_act_upd="bs update --local";  __bs_act_repo_upd="update --local" ;;
      system) __bs_act_upd="sudo bs update --system"; __bs_act_repo_upd="update --system" ;;
      *)      __bs_act_upd="bs update --lib ${TARGET_LIB}"; __bs_act_repo_upd="update --lib ${TARGET_LIB}" ;;
    esac
    __bs_act_inst_v=$(bs_install_version_of "${TARGET_LIB}")
    __bs_act_src_v=$(bs_version_get)
    bs_arr_push bs_act_rows "• ${TARGET_LIB} — версия / version ${__bs_act_inst_v} (источник / source: ${__bs_act_src_v})"
    # Сравнение версий: что именно предлагать пользователю
    # Version comparison: what exactly to suggest
    if [ "${__bs_act_inst_v}" != "?" ]; then
      bs_version_compare "${__bs_act_inst_v}" "${__bs_act_src_v}" || __bs_act_rc_cmp=$?
      case "${__bs_act_rc_cmp}" in
        2) bs_arr_push bs_act_rows "Доступно обновление / An update is available: ${__bs_act_inst_v} → ${__bs_act_src_v}" ;;
        0) bs_arr_push bs_act_rows "Установлена та же версия / The same version is installed" ;;
        1) bs_arr_push bs_act_rows "Установленная версия НОВЕЕ этого источника / The installed version is NEWER than this source — обновление понизит её / updating would downgrade it" ;;
      esac
    fi
    bs_arr_push bs_act_rows "Установка не выполнена, ничего не изменено / Nothing was changed"
    # Команда из репозитория работает всегда: ей не нужен PATH
    # The repository command always works: it does not need PATH
    __bs_act_repo_bs="./bs"
    if [ "${SOURCE_ROOT}" != "${PWD}" ]; then __bs_act_repo_bs="${SOURCE_ROOT}/bs"; fi
    if [ "${__bs_act_repo_upd}" = "update --system" ]; then __bs_act_repo_bs="sudo ${__bs_act_repo_bs}"; fi
    bs_arr_push bs_act_rows "Обновить из этого репозитория / Update from this repository:" "  ${__bs_act_repo_bs} ${__bs_act_repo_upd}"
    bs_arr_push bs_act_rows "Или установленной копией / Or with the installed copy:" "  ${__bs_act_upd}"
    # Видна ли команда bs в PATH этой оболочки (а не в PATH установщика)
    # Is the bs command visible in the PATH of this shell (not the installer's)
    __bs_act_seen=$(PATH="${INSTALL_ORIG_PATH:-${PATH}}" command -v bs 2>/dev/null || true)
    if [ -z "${__bs_act_seen}" ]; then
      bs_arr_push bs_act_rows "ВНИМАНИЕ / NOTE: команда bs не найдена в PATH этой оболочки / the bs command is not in the PATH of this shell (${BIN_DIR} отсутствует / is missing)"
      bs_arr_push bs_act_rows "Исправить / Fix:  $(bs_shell_reload_hint "$(bs_install_user_shell)")  (или новый терминал / or a new terminal);" "  ./install.sh --local --update-path  — дописать строку в rc-файл / add the line to the rc file"
    elif [ "${__bs_act_seen}" != "${TARGET_BIN}" ]; then
      bs_arr_push bs_act_rows "ВНИМАНИЕ / NOTE: по команде bs запускается другая копия / the bs command runs another copy: ${__bs_act_seen}"
    fi
    bs_arr_push bs_act_rows "Переустановить / Reinstall:" "  $(bs_install_cmd uninstall)" "  $(bs_install_cmd install)"
    bs_arr_push bs_act_rows "Другое место / Another location:" "  PREFIX=/opt/bs ./install.sh  (BIN_DIR=... LIB_DIR=...)"
    eval "$(bs_arr_to_args bs_act_rows)"
    bs_install_box "УЖЕ УСТАНОВЛЕНО / ALREADY INSTALLED" "$@"
    exit 1
  fi

  # Права записи: проверяем каталоги, а не EUID.
  # Write access: the directories are tested, not the EUID.
  bs_install_require_writable "${BIN_DIR}" "BIN_DIR" || exit 1
  bs_install_require_writable "${LIB_DIR}" "LIB_DIR" || exit 1

  # «Полуустановка»: чиним переустановкой и говорим, что нашли.
  # A "half install": repaired by reinstalling, saying what was found.
  bs_arr_clear bs_act_half
  if [ "${__bs_act_lstate}" = "bs" ] && [ "${__bs_act_bstate}" = "missing" ]; then
    bs_arr_push bs_act_half "• найдена lib без wrapper / lib found without a wrapper: ${TARGET_LIB}"
    bs_arr_push bs_act_half "• wrapper ${TARGET_BIN} будет создан / will be created"
  elif [ "${__bs_act_lstate}" = "bs" ] && [ "${__bs_act_bstate}" = "stale" ]; then
    bs_arr_push bs_act_half "• найдена lib, а wrapper указывает на несуществующую ${__bs_act_broot} / lib found, wrapper points to a missing ${__bs_act_broot}"
  elif [ "${__bs_act_lstate}" != "bs" ] && [ "${__bs_act_bstate}" = "here" ]; then
    bs_arr_push bs_act_half "• найден wrapper ${TARGET_BIN} без lib ${TARGET_LIB} / wrapper found without the lib"
  elif [ "${__bs_act_lstate}" != "bs" ] && [ "${__bs_act_bstate}" = "stale" ]; then
    bs_arr_push bs_act_half "• wrapper ${TARGET_BIN} указывает на несуществующую ${__bs_act_broot} и будет заменён / wrapper points to a missing ${__bs_act_broot} and will be replaced"
  fi
  if [ "$(bs_arr_len bs_act_half)" -gt 0 ]; then
    bs_arr_push bs_act_half "Переустановка исправит это / Reinstalling repairs it"
    eval "$(bs_arr_to_args bs_act_half)"
    bs_install_box "НЕПОЛНАЯ УСТАНОВКА — ЧИНИМ / PARTIAL INSTALL — REPAIRING" "$@"
  fi

  printf "Установка BS (%s)\n" "${MODE}"
  printf "  SOURCE_ROOT: %s\n" "${SOURCE_ROOT}"
  printf "  PREFIX:      %s\n" "${PREFIX}"
  printf "  TARGET_LIB:  %s\n" "${TARGET_LIB}"
  printf "  TARGET_BIN:  %s\n" "${TARGET_BIN}"

  __bs_act_had_old=0
  if [ "${__bs_act_lstate}" = "bs" ]; then __bs_act_had_old=1; fi
  bs_install_transaction "${__bs_act_had_old}" "${__bs_act_lstate}"
  bs_install_completion

  printf "Готово.\n"

  # Рамка о других установках — ДО настройки PATH: bs_auto_update_path в терминале
  # заменяет процесс новой оболочкой (exec), и всё, что стоит после неё,
  # пользователь не увидел бы (предупреждение, что bs запускает другую копию).
  # The "other installs" frame goes BEFORE the PATH setup: in a terminal
  # bs_auto_update_path replaces the process with a fresh shell (exec), so anything
  # after it would never be seen (the warning that bs runs another copy).
  bs_install_report_others install

  # local: PATH в rc-файлах; иначе — подсказка, если BIN_DIR не в PATH.
  # local: PATH in the rc files; otherwise a hint when BIN_DIR is not in PATH.
  if [ "${MODE}" = "local" ]; then
    bs_auto_update_path
  elif ! bs_install_in_path "${BIN_DIR}"; then
    printf "\n"
    bs_print_path_hint
  fi
}

# Вид цели: local | system | custom (по стандартным местам).
# Target kind: local | system | custom (by standard locations).
bs_install_kind_of_target() {
  for __bs_act_ktk in local system; do
    if [ "$(bs_install_std_lib "${__bs_act_ktk}" 2>/dev/null)" = "${TARGET_LIB}" ] \
       && [ "$(bs_install_std_bin "${__bs_act_ktk}" 2>/dev/null)" = "${TARGET_BIN}" ]; then
      printf '%s' "${__bs_act_ktk}"
      return 0
    fi
  done
  printf 'custom'
}

# Uninstall
bs_do_uninstall() {
  INSTALL_ACTION="uninstall"
  bs_install_validate_paths || exit 1

  __bs_act_lstate=$(bs_install_lib_state "${TARGET_LIB}")
  __bs_act_bstate=$(bs_install_bin_state "${TARGET_BIN}" "${TARGET_LIB}")
  __bs_act_broot=$(bs_install_wrapper_root "${TARGET_BIN}")

  __bs_act_rm_lib=0
  __bs_act_rm_bin=0
  bs_arr_clear bs_act_kept
  bs_arr_clear bs_act_found
  # lib: удаляем только установку BS (не репозиторий, не чужой каталог).
  # lib: only a BS install is removed (never a checkout or a foreign dir).
  case "${__bs_act_lstate}" in
    bs)      __bs_act_rm_lib=1; bs_arr_push bs_act_found "lib: ${TARGET_LIB}" ;;
    missing) ;;
    empty)   bs_arr_push bs_act_kept "• ${TARGET_LIB} — пустой каталог, не трогаю / empty directory, left alone" ;;
    *)       bs_arr_push bs_act_kept "• ${TARGET_LIB} — не удаляю: $(bs_install_lib_reason "${__bs_act_lstate}")" ;;
  esac
  # wrapper: только wrapper BS, указывающий сюда или в никуда.
  # wrapper: only a BS wrapper pointing here or nowhere.
  case "${__bs_act_bstate}" in
    here|stale) __bs_act_rm_bin=1; bs_arr_push bs_act_found "wrapper: ${TARGET_BIN}" ;;
    missing)    ;;
    other)      bs_arr_push bs_act_kept "• ${TARGET_BIN} — wrapper другой установки (${__bs_act_broot}), не трогаю / wrapper of another install, left alone" ;;
    foreign)    bs_arr_push bs_act_kept "• ${TARGET_BIN} — не wrapper BS (нет export BS_ROOT=), не трогаю / not a BS wrapper, left alone" ;;
  esac

  # Нечего удалять — это не ошибка.
  # Nothing to remove is not an error.
  if [ "${__bs_act_rm_lib}" -eq 0 ] && [ "${__bs_act_rm_bin}" -eq 0 ]; then
    bs_arr_clear bs_act_rows
    if [ "${__bs_act_lstate}" = "missing" ] && [ "${__bs_act_bstate}" = "missing" ]; then
      bs_arr_push bs_act_rows "• BS не установлена / BS is not installed: ${TARGET_LIB}, ${TARGET_BIN}"
      if [ "${INSTALL_AUTODETECT:-0}" = "1" ]; then
        bs_arr_push bs_act_rows "• проверено / checked: ${BS_SYSTEM_PREFIX}/lib/bs, ${HOME:-<HOME не задан / unset>}/.local/lib/bs"
      fi
    fi
    # kept → rows, по одной строке / kept → rows, one line at a time
    __bs_act_ki=0
    __bs_act_kn=$(bs_arr_len bs_act_kept)
    while [ "${__bs_act_ki}" -lt "${__bs_act_kn}" ]; do
      bs_arr_get bs_act_kept "${__bs_act_ki}" __bs_act_krow
      bs_arr_push bs_act_rows "${__bs_act_krow}"
      __bs_act_ki=$((__bs_act_ki + 1))
    done
    for __bs_act_kind in system local; do
      __bs_act_other=$(bs_install_std_lib "${__bs_act_kind}") || continue
      if [ "${__bs_act_other}" = "${TARGET_LIB}" ]; then continue; fi
      if [ "$(bs_install_lib_state "${__bs_act_other}")" = "bs" ]; then
        if [ "${__bs_act_kind}" = "system" ]; then
          __bs_act_c="sudo ./install.sh uninstall"
          if [ "$(bs_install_euid)" -eq 0 ]; then __bs_act_c="./install.sh uninstall"; fi
          bs_arr_push bs_act_rows "• но есть системная установка / but a system install exists: ${__bs_act_other} (версия / version $(bs_install_version_of "${__bs_act_other}"))"
          bs_arr_push bs_act_rows "  Удалить её / Remove it:  ${__bs_act_c}"
        else
          bs_arr_push bs_act_rows "• но есть локальная установка / but a local install exists: ${__bs_act_other} (версия / version $(bs_install_version_of "${__bs_act_other}"))"
          bs_arr_push bs_act_rows "  Удалить её / Remove it:  ./install.sh --local uninstall"
        fi
      fi
    done
    if [ "$(bs_install_euid)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
      bs_arr_push bs_act_rows "• запущено через sudo (HOME=${HOME:-}): локальную установку пользователя ${SUDO_USER} удаляйте без sudo / local installs of ${SUDO_USER} are removed without sudo"
    fi
    eval "$(bs_arr_to_args bs_act_rows)"
    bs_install_box "УДАЛЯТЬ НЕЧЕГО / NOTHING TO REMOVE" "$@"
    return 0
  fi

  # Права записи нужны только там, где будем удалять.
  # Write access is needed only where something is removed.
  if [ "${__bs_act_rm_bin}" -eq 1 ]; then bs_install_require_writable "${BIN_DIR}" "BIN_DIR" || exit 1; fi
  if [ "${__bs_act_rm_lib}" -eq 1 ]; then bs_install_require_writable "${LIB_DIR}" "LIB_DIR" || exit 1; fi

  printf "Удаление BS (%s)\n" "${MODE}"
  printf "  TARGET_BIN: %s\n" "${TARGET_BIN}"
  printf "  TARGET_LIB: %s\n" "${TARGET_LIB}"

  # Дополнение bash убираем вместе с установкой — но только своё
  # Remove the bash completion along with the install — but only our own file
  if [ "${__bs_act_rm_lib}" -eq 1 ] || [ "${__bs_act_rm_bin}" -eq 1 ]; then
    bs_uninstall_completion
  fi

  # Сначала lib, потом wrapper: при сбое rm остаётся рабочая команда bs и
  # удаление можно повторить (раньше wrapper исчезал, а lib оставалась
  # частично удалённой; под set -e сбой был ещё и молчаливым).
  # lib first, wrapper second: if rm fails, a working bs command stays and the
  # removal can be repeated (the wrapper used to vanish while the lib was left
  # half-deleted; under set -e the failure was also silent).
  if [ "${__bs_act_rm_lib}" -eq 1 ]; then
    if ! rm -rf -- "${TARGET_LIB}"; then
      bs_install_error "Удаление не выполнено: не удалось удалить ${TARGET_LIB} (часть файлов могла быть удалена)"         "Uninstall failed: cannot remove ${TARGET_LIB} (some files may be gone)"         "Wrapper оставлен. Исправьте права и удалите остаток вручную / The wrapper is kept. Fix the permissions and remove the rest by hand: chmod -R u+w ${TARGET_LIB} && rm -rf ${TARGET_LIB}"
      exit 1
    fi
    printf "Удален / Removed: %s\n" "${TARGET_LIB}"
  else
    printf "Нет каталога / No directory: %s\n" "${TARGET_LIB}"
  fi
  if [ "${__bs_act_rm_bin}" -eq 1 ]; then
    rm -f -- "${TARGET_BIN}"
    printf "Удален / Removed: %s\n" "${TARGET_BIN}"
  else
    printf "Нет wrapper / No wrapper: %s\n" "${TARGET_BIN}"
  fi

  if [ "$(bs_arr_len bs_act_kept)" -gt 0 ]; then
    eval "$(bs_arr_to_args bs_act_kept)"
    bs_install_box "ЧАСТЬ НЕ УДАЛЕНА / PART LEFT IN PLACE" "$@"
  fi

  # Do NOT wipe user's ~/.local trees; only tidy empty parents
  if [ "${MODE}" = "local" ]; then
    # rmdir удаляет ТОЛЬКО пустые каталоги: если в ~/.local/bin или
    # ~/.local/lib есть другие файлы — они остаются нетронутыми.
    # rmdir removes ONLY empty dirs: any other files in ~/.local/bin or
    # ~/.local/lib are left untouched.
    if [ -d "${BIN_DIR}" ] && bs_utils_quiet_err rmdir "${BIN_DIR}"; then
      printf "Удален пустой каталог: %s\n" "${BIN_DIR}"
    fi
    if [ -d "${LIB_DIR}" ] && bs_utils_quiet_err rmdir "${LIB_DIR}"; then
      printf "Удален пустой каталог: %s\n" "${LIB_DIR}"
    fi
    # PATH-строка нужна, пока жива стандартная локальная установка: удаление
    # custom-копии её не трогает. Иначе — только точное совпадение строки.
    # The PATH line is needed while the standard local install lives: removing
    # a custom copy leaves it. Otherwise only the exact installer line goes.
    if [ -n "$(bs_install_wrapper_root "${HOME}/.local/bin/bs")" ]; then
      printf "PATH-строка в rc-файлах оставлена: жива локальная установка %s\nPATH line kept in rc files: the local install %s still exists\n" \
        "${HOME}/.local/bin/bs" "${HOME}/.local/bin/bs"
    else
      bs_remove_path_entries_all
    fi
  fi

  printf "Готово.\n"
  bs_install_report_others uninstall
}

bs_shell_alias bs_write_install_manifest write_install_manifest
bs_shell_alias bs_install_rollback install_rollback
bs_shell_alias bs_install_tx_fail install_tx_fail
bs_shell_alias bs_install_step install_step
bs_shell_alias bs_install_write_wrapper install_write_wrapper
bs_shell_alias bs_install_transaction install_transaction
bs_shell_alias bs_install_completion install_completion
bs_shell_alias bs_uninstall_completion uninstall_completion
bs_shell_alias bs_do_install do_install
bs_shell_alias bs_install_kind_of_target install_kind_of_target
bs_shell_alias bs_do_uninstall do_uninstall
