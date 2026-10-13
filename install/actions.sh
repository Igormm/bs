#!/usr/bin/env bash
# @shell bash4 — installer code: runs in bash 4.2+, writes PATH/rc for the shell of the USER (bootstrap/shell.sh)
# @shell bash4 — код установщика: исполняется в bash 4.2+, пишет PATH/rc для оболочки ПОЛЬЗОВАТЕЛЯ (bootstrap/shell.sh)
# shellcheck disable=SC2034  # INSTALL_ACTION is read by notice.sh / читается в notice.sh

# Installation and uninstallation functions

# Записать манифест установки: как, откуда и куда поставлена эта копия BS.
# Его читают `bs env`, `bs update` и `bs uninstall`.
# Write the install manifest: how, from where and where this BS copy was
# installed. Read by `bs env`, `bs update` and `bs uninstall`.
# $1 — каталог, куда писать (по умолчанию TARGET_LIB; при установке — staging)
write_install_manifest() {
  local -r dest="${1:-${TARGET_LIB}}"
  local commit="" repo=""
  if utils::has git && [[ -e "${SOURCE_ROOT}/.git" ]]; then
    commit="$(git -C "${SOURCE_ROOT}" rev-parse HEAD 2>/dev/null)" || commit=""
    repo="$(git -C "${SOURCE_ROOT}" remote get-url origin 2>/dev/null)" || repo=""
  fi
  # Вид установки: local/system — стандартные места, иначе custom (как у bs update).
  # Install kind: local/system for standard locations, otherwise custom (like bs update).
  local kind="custom" k
  for k in local system; do
    if [[ "$(install_std_lib "${k}" 2>/dev/null)" == "${TARGET_LIB}" \
          && "$(install_std_bin "${k}" 2>/dev/null)" == "${TARGET_BIN}" ]]; then
      kind="${k}"
    fi
  done
  {
    printf '# BS install manifest — written by install.sh, updated by bs update\n'
    printf 'mode=%s\n' "${kind}"
    printf 'prefix=%s\n' "${PREFIX}"
    printf 'lib=%s\n' "${TARGET_LIB}"
    printf 'bin=%s\n' "${TARGET_BIN}"
    printf 'version=%s\n' "$(bs::version::get)"
    printf 'source=%s\n' "${SOURCE_ROOT}"
    printf 'source_repo=%s\n' "${repo}"
    printf 'source_commit=%s\n' "${commit}"
    printf 'installed_at=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf 'installed_by=%s\n' "${SUDO_USER:-${USER:-$(id -un)}}"
  } > "${dest}/.install"
}

# Состояние транзакции установки (см. install_rollback).
# Install transaction state (see install_rollback).
INSTALL_TX_STAGE=""    # временный каталог с новой копией / staging dir with the new copy
INSTALL_TX_BACKUP=""   # прежняя установка, отложенная в сторону / old install set aside
INSTALL_TX_WTMP=""     # временный wrapper / temporary wrapper
INSTALL_TX_SWAPPED=0   # 1 — новая lib уже на месте TARGET_LIB
INSTALL_TX_ERR=""      # текст ошибки последнего шага / error text of the last step

# Откат: убрать временное, вернуть прежнюю установку. Идемпотентен.
# Roll back: drop temporaries, restore the previous install. Idempotent.
install_rollback() {
  [[ -n "${INSTALL_TX_WTMP}" ]] && rm -f -- "${INSTALL_TX_WTMP}" 2>/dev/null
  if [[ "${INSTALL_TX_SWAPPED}" == "1" ]]; then
    rm -rf -- "${TARGET_LIB}" 2>/dev/null
    INSTALL_TX_SWAPPED=0
    if [[ -n "${INSTALL_TX_BACKUP}" && -e "${INSTALL_TX_BACKUP}" ]]; then
      mv -- "${INSTALL_TX_BACKUP}" "${TARGET_LIB}" 2>/dev/null
      INSTALL_TX_BACKUP=""
    fi
  elif [[ -n "${INSTALL_TX_BACKUP}" && -e "${INSTALL_TX_BACKUP}" && ! -e "${TARGET_LIB}" ]]; then
    # lib отложена, но не заменена — вернуть на место
    # set aside but not replaced — put it back
    mv -- "${INSTALL_TX_BACKUP}" "${TARGET_LIB}" 2>/dev/null
    INSTALL_TX_BACKUP=""
  fi
  [[ -n "${INSTALL_TX_STAGE}" ]] && rm -rf -- "${INSTALL_TX_STAGE}" 2>/dev/null
  INSTALL_TX_STAGE="" INSTALL_TX_WTMP=""
  return 0
}

# Сообщение о сбое установки (после отката). $1 RU шаг, $2 EN шаг, $3 было ли старое
# Install failure message (after rollback). $1 RU step, $2 EN step, $3 had old
install_tx_fail() {
  local -r ru="$1" en="$2" had_old="$3"
  local reason="${INSTALL_TX_ERR//$'\n'/ }"
  install_rollback
  local keep_ru="Установленных файлов нет, временное убрано" keep_en="No installed files; temporaries removed"
  if [[ "${had_old}" == "1" ]]; then
    keep_ru="Прежняя установка не тронута: ${TARGET_LIB}"
    keep_en="The previous install is untouched: ${TARGET_LIB}"
  fi
  install_error "Установка не выполнена: ${ru}" \
    "Install failed: ${en}" \
    "Причина / Reason: ${reason:-неизвестна / unknown}" \
    "${keep_ru} / ${keep_en}" \
    "Проверьте свободное место (df -h) и права / Check free space (df -h) and permissions"
  exit 1
}

# Выполнить команду, сохранив её stderr в INSTALL_TX_ERR (ошибка → 1).
# Run a command, keeping its stderr in INSTALL_TX_ERR (failure → 1).
install_step() {
  INSTALL_TX_ERR=""
  if INSTALL_TX_ERR="$("$@" 2>&1)"; then
    return 0
  fi
  return 1
}

# Транзакционная установка: копия во временный каталог рядом с TARGET_LIB,
# затем атомарный rename. При сбое временное убирается, прежняя установка
# остаётся на месте. $1 — 1, если TARGET_LIB уже была (её заменяем).
# Transactional install: copy into a temporary directory next to TARGET_LIB,
# then an atomic rename. On failure the temporaries are removed and the
# previous install stays in place. $1 — 1 if TARGET_LIB already existed.
install_transaction() {
  local -r had_old="$1" lstate="$2"
  INSTALL_TX_STAGE="${LIB_DIR}/.bs.install.$$"
  INSTALL_TX_BACKUP=""
  INSTALL_TX_WTMP="${BIN_DIR}/.bs.wrapper.$$"
  INSTALL_TX_SWAPPED=0

  # Ctrl-C / kill в середине установки не должны оставлять разрушенное состояние.
  # Ctrl-C / kill mid-install must not leave a broken state behind.
  trap 'install_rollback; exit 130' INT TERM HUP

  install_step mkdir -p -- "${BIN_DIR}" "${LIB_DIR}" \
    || install_tx_fail "не удалось создать каталоги ${BIN_DIR}, ${LIB_DIR}" "cannot create ${BIN_DIR}, ${LIB_DIR}" 0

  install_step mkdir -- "${INSTALL_TX_STAGE}" \
    || install_tx_fail "не удалось создать временный каталог ${INSTALL_TX_STAGE}" "cannot create the temporary directory ${INSTALL_TX_STAGE}" 0

  local item
  for item in bootstrap core bs lib; do
    install_step cp -a -- "${SOURCE_ROOT}/${item}" "${INSTALL_TX_STAGE}/" \
      || install_tx_fail "не удалось скопировать ${item}" "cannot copy ${item}" "${had_old}"
  done

  # Манифест — тоже в staging: после rename копия сразу полная.
  # The manifest goes to staging too: after the rename the copy is complete.
  install_step write_install_manifest "${INSTALL_TX_STAGE}" \
    || install_tx_fail "не удалось записать манифест" "cannot write the manifest" "${had_old}"

  # Wrapper — во временный файл рядом с целевым (rename в одном каталоге).
  # The wrapper goes to a temporary file next to the target (same-dir rename).
  install_step bash -c '
    printf "#!/usr/bin/env bash\nexport BS_ROOT=\"%s\"\nexec \"\${BS_ROOT}/bs\" \"\$@\"\n" "$1" > "$2" && chmod 0755 "$2"
  ' _ "${TARGET_LIB}" "${INSTALL_TX_WTMP}" \
    || install_tx_fail "не удалось создать wrapper" "cannot create the wrapper" "${had_old}"

  # Подмена lib: прежнюю (если есть) откладываем, новую переименовываем.
  # Swap lib: set the old one aside (if any), rename the new one in.
  if [[ "${lstate}" == "empty" ]]; then
    install_step rmdir -- "${TARGET_LIB}" \
      || install_tx_fail "не удалось заменить пустой каталог ${TARGET_LIB}" "cannot replace the empty directory ${TARGET_LIB}" "${had_old}"
  elif [[ "${had_old}" == "1" ]]; then
    INSTALL_TX_BACKUP="${LIB_DIR}/.bs.backup.$$"
    install_step mv -- "${TARGET_LIB}" "${INSTALL_TX_BACKUP}" \
      || { INSTALL_TX_BACKUP=""; install_tx_fail "не удалось отложить прежнюю установку" "cannot set the previous install aside" "${had_old}"; }
  fi
  install_step mv -- "${INSTALL_TX_STAGE}" "${TARGET_LIB}" \
    || install_tx_fail "не удалось поставить новую копию на место" "cannot move the new copy into place" "${had_old}"
  INSTALL_TX_SWAPPED=1
  INSTALL_TX_STAGE=""

  install_step mv -f -- "${INSTALL_TX_WTMP}" "${TARGET_BIN}" \
    || install_tx_fail "не удалось установить wrapper ${TARGET_BIN}" "cannot install the wrapper ${TARGET_BIN}" "${had_old}"
  INSTALL_TX_WTMP=""

  # Успех: отложенную копию можно убрать.
  # Success: the set-aside copy can go.
  if [[ -n "${INSTALL_TX_BACKUP}" ]]; then
    rm -rf -- "${INSTALL_TX_BACKUP}" 2>/dev/null \
      || install_note "не удалось удалить временную копию ${INSTALL_TX_BACKUP} — удалите вручную" \
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
install_completion() {
  local -r src="${SOURCE_ROOT}/share/bash-completion/completions/bs"
  [[ -f "${src}" ]] || return 0
  if mkdir -p -- "$(dirname -- "${TARGET_COMPLETION}")" 2>/dev/null \
     && cp -a -- "${src}" "${TARGET_COMPLETION}" 2>/dev/null; then
    printf "Установлено bash-completion / bash completion installed: %s\n" "${TARGET_COMPLETION}"
  else
    install_note "не удалось установить bash-completion в ${TARGET_COMPLETION} (bs работает и без него)" \
                 "could not install the bash completion to ${TARGET_COMPLETION} (bs works without it)"
  fi
  return 0
}

# Удалить дополнение, только если это файл BS (есть функция _bs_complete)
# Remove the completion only if it is BS's own file (has _bs_complete)
uninstall_completion() {
  [[ -f "${TARGET_COMPLETION:-}" ]] || return 0
  if grep -q '_bs_complete' -- "${TARGET_COMPLETION}" 2>/dev/null; then
    rm -f -- "${TARGET_COMPLETION}"
    printf "Удален / Removed: %s\n" "${TARGET_COMPLETION}"
  else
    install_note "${TARGET_COMPLETION} не принадлежит BS — оставлен на месте" \
                 "${TARGET_COMPLETION} is not BS's file — left in place"
  fi
  return 0
}

# Install
do_install() {
  INSTALL_ACTION="install"
  install_validate_paths || exit 1

  local lstate bstate
  lstate="$(install_lib_state "${TARGET_LIB}")"
  bstate="$(install_bin_state "${TARGET_BIN}" "${TARGET_LIB}")"
  local broot
  broot="$(install_wrapper_root "${TARGET_BIN}")"

  # Отказ: под TARGET_LIB лежит не установка BS — ничего не удаляем.
  # Refusal: TARGET_LIB is not a BS install — nothing is deleted.
  case "${lstate}" in
    source|symlink|file|foreign)
      install_error "${TARGET_LIB} уже существует и это не установка BS — установка отменена, ничего не удалено" \
        "${TARGET_LIB} already exists and is not a BS install — aborted, nothing was deleted" \
        "Причина / Reason: $(install_lib_reason "${lstate}")" \
        "Другое место / Another location:  PREFIX=\$HOME/opt/bs ./install.sh --local   (или LIB_DIR=... / or LIB_DIR=...)"
      exit 1 ;;
  esac
  # Отказ: TARGET_BIN занят чужим файлом или wrapper'ом живой установки BS.
  # Refusal: TARGET_BIN is somebody else's file or a live BS wrapper.
  case "${bstate}" in
    foreign)
      install_error "${TARGET_BIN} уже существует и это не wrapper BS (нет строки export BS_ROOT=) — установка отменена, файл не тронут" \
        "${TARGET_BIN} already exists and is not a BS wrapper (no export BS_ROOT= line) — aborted, the file is untouched" \
        "Другое место / Another location:  BIN_DIR=\$HOME/bin $(install_cmd install)" \
        "Либо переименуйте/удалите файл сами / Or rename/remove the file yourself"
      exit 1 ;;
    other)
      install_error "${TARGET_BIN} — wrapper другой установки BS (${broot}, версия $(install_version_of "${broot}")) — установка отменена" \
        "${TARGET_BIN} is the wrapper of another BS install (${broot}, version $(install_version_of "${broot}")) — aborted" \
        "Перезапись переключила бы ту установку на новую копию / Overwriting it would switch that install to the new copy." \
        "Обновить ту установку / Update that one:  bs update --lib ${broot}" \
        "Другой BIN_DIR / Another BIN_DIR:  BIN_DIR=\$HOME/bin $(install_cmd install)"
      exit 1 ;;
  esac

  # Уже установлено в это место.
  # Already installed at this location.
  if [[ "${lstate}" == "bs" && "${bstate}" == "here" ]]; then
    local upd="bs update" repo_upd="" inst_v src_v rc_cmp=0
    local -a rows=()
    case "$(install_kind_of_target)" in
      local)  upd="bs update --local";  repo_upd="update --local" ;;
      system) upd="sudo bs update --system"; repo_upd="update --system" ;;
      *)      upd="bs update --lib ${TARGET_LIB}"; repo_upd="update --lib ${TARGET_LIB}" ;;
    esac
    inst_v="$(install_version_of "${TARGET_LIB}")"
    src_v="$(bs::version::get)"
    rows+=("• ${TARGET_LIB} — версия / version ${inst_v} (источник / source: ${src_v})")
    # Сравнение версий: что именно предлагать пользователю
    # Version comparison: what exactly to suggest
    if [[ "${inst_v}" != "?" ]]; then
      bs::version::compare "${inst_v}" "${src_v}" || rc_cmp=$?
      case "${rc_cmp}" in
        2) rows+=("Доступно обновление / An update is available: ${inst_v} → ${src_v}") ;;
        0) rows+=("Установлена та же версия / The same version is installed") ;;
        1) rows+=("Установленная версия НОВЕЕ этого источника / The installed version is NEWER than this source — обновление понизит её / updating would downgrade it") ;;
      esac
    fi
    rows+=("Установка не выполнена, ничего не изменено / Nothing was changed")
    # Команда из репозитория работает всегда: ей не нужен PATH
    # The repository command always works: it does not need PATH
    local repo_bs="./bs"
    [[ "${SOURCE_ROOT}" == "${PWD}" ]] || repo_bs="${SOURCE_ROOT}/bs"
    [[ "${repo_upd}" == "update --system" ]] && repo_bs="sudo ${repo_bs}"
    rows+=("Обновить из этого репозитория / Update from this repository:" "  ${repo_bs} ${repo_upd}")
    rows+=("Или установленной копией / Or with the installed copy:" "  ${upd}")
    # Видна ли команда bs в PATH этой оболочки (а не в PATH установщика)
    # Is the bs command visible in the PATH of this shell (not the installer's)
    local seen
    seen="$(PATH="${INSTALL_ORIG_PATH:-${PATH}}" command -v bs 2>/dev/null || true)"
    if [[ -z "${seen}" ]]; then
      rows+=("ВНИМАНИЕ / NOTE: команда bs не найдена в PATH этой оболочки / the bs command is not in the PATH of this shell (${BIN_DIR} отсутствует / is missing)")
      rows+=("Исправить / Fix:  $(bs_shell_reload_hint "$(install_user_shell)")  (или новый терминал / or a new terminal);" "  ./install.sh --local --update-path  — дописать строку в rc-файл / add the line to the rc file")
    elif [[ "${seen}" != "${TARGET_BIN}" ]]; then
      rows+=("ВНИМАНИЕ / NOTE: по команде bs запускается другая копия / the bs command runs another copy: ${seen}")
    fi
    rows+=("Переустановить / Reinstall:" "  $(install_cmd uninstall)" "  $(install_cmd install)")
    rows+=("Другое место / Another location:" "  PREFIX=/opt/bs ./install.sh  (BIN_DIR=... LIB_DIR=...)")
    install_box "УЖЕ УСТАНОВЛЕНО / ALREADY INSTALLED" "${rows[@]}"
    exit 1
  fi

  # Права записи: проверяем каталоги, а не EUID.
  # Write access: the directories are tested, not the EUID.
  install_require_writable "${BIN_DIR}" "BIN_DIR" || exit 1
  install_require_writable "${LIB_DIR}" "LIB_DIR" || exit 1

  # «Полуустановка»: чиним переустановкой и говорим, что нашли.
  # A "half install": repaired by reinstalling, saying what was found.
  local -a half=()
  if [[ "${lstate}" == "bs" && "${bstate}" == "missing" ]]; then
    half+=("• найдена lib без wrapper / lib found without a wrapper: ${TARGET_LIB}")
    half+=("• wrapper ${TARGET_BIN} будет создан / will be created")
  elif [[ "${lstate}" == "bs" && "${bstate}" == "stale" ]]; then
    half+=("• найдена lib, а wrapper указывает на несуществующую ${broot} / lib found, wrapper points to a missing ${broot}")
  elif [[ "${lstate}" != "bs" && "${bstate}" == "here" ]]; then
    half+=("• найден wrapper ${TARGET_BIN} без lib ${TARGET_LIB} / wrapper found without the lib")
  elif [[ "${lstate}" != "bs" && "${bstate}" == "stale" ]]; then
    half+=("• wrapper ${TARGET_BIN} указывает на несуществующую ${broot} и будет заменён / wrapper points to a missing ${broot} and will be replaced")
  fi
  if (( ${#half[@]} > 0 )); then
    half+=("Переустановка исправит это / Reinstalling repairs it")
    install_box "НЕПОЛНАЯ УСТАНОВКА — ЧИНИМ / PARTIAL INSTALL — REPAIRING" "${half[@]}"
  fi

  printf "Установка BS (%s)\n" "${MODE}"
  printf "  SOURCE_ROOT: %s\n" "${SOURCE_ROOT}"
  printf "  PREFIX:      %s\n" "${PREFIX}"
  printf "  TARGET_LIB:  %s\n" "${TARGET_LIB}"
  printf "  TARGET_BIN:  %s\n" "${TARGET_BIN}"

  local had_old=0
  [[ "${lstate}" == "bs" ]] && had_old=1
  install_transaction "${had_old}" "${lstate}"
  install_completion

  printf "Готово.\n"

  # Рамка о других установках — ДО настройки PATH: auto_update_path в терминале
  # заменяет процесс новой оболочкой (exec), и всё, что стоит после неё,
  # пользователь не увидел бы (предупреждение, что bs запускает другую копию).
  # The "other installs" frame goes BEFORE the PATH setup: in a terminal
  # auto_update_path replaces the process with a fresh shell (exec), so anything
  # after it would never be seen (the warning that bs runs another copy).
  install_report_others install

  # local: PATH в rc-файлах; иначе — подсказка, если BIN_DIR не в PATH.
  # local: PATH in the rc files; otherwise a hint when BIN_DIR is not in PATH.
  if [[ "${MODE}" == "local" ]]; then
    auto_update_path
  elif ! install_in_path "${BIN_DIR}"; then
    printf "\n"
    print_path_hint
  fi
}

# Вид цели: local | system | custom (по стандартным местам).
# Target kind: local | system | custom (by standard locations).
install_kind_of_target() {
  local k
  for k in local system; do
    if [[ "$(install_std_lib "${k}" 2>/dev/null)" == "${TARGET_LIB}" \
          && "$(install_std_bin "${k}" 2>/dev/null)" == "${TARGET_BIN}" ]]; then
      printf '%s' "${k}"
      return 0
    fi
  done
  printf 'custom'
}

# Uninstall
do_uninstall() {
  INSTALL_ACTION="uninstall"
  install_validate_paths || exit 1

  local lstate bstate broot
  lstate="$(install_lib_state "${TARGET_LIB}")"
  bstate="$(install_bin_state "${TARGET_BIN}" "${TARGET_LIB}")"
  broot="$(install_wrapper_root "${TARGET_BIN}")"

  local rm_lib=0 rm_bin=0
  local -a kept=() found=()
  # lib: удаляем только установку BS (не репозиторий, не чужой каталог).
  # lib: only a BS install is removed (never a checkout or a foreign dir).
  case "${lstate}" in
    bs)      rm_lib=1; found+=("lib: ${TARGET_LIB}") ;;
    missing) ;;
    empty)   kept+=("• ${TARGET_LIB} — пустой каталог, не трогаю / empty directory, left alone") ;;
    *)       kept+=("• ${TARGET_LIB} — не удаляю: $(install_lib_reason "${lstate}")") ;;
  esac
  # wrapper: только wrapper BS, указывающий сюда или в никуда.
  # wrapper: only a BS wrapper pointing here or nowhere.
  case "${bstate}" in
    here|stale) rm_bin=1; found+=("wrapper: ${TARGET_BIN}") ;;
    missing)    ;;
    other)      kept+=("• ${TARGET_BIN} — wrapper другой установки (${broot}), не трогаю / wrapper of another install, left alone") ;;
    foreign)    kept+=("• ${TARGET_BIN} — не wrapper BS (нет export BS_ROOT=), не трогаю / not a BS wrapper, left alone") ;;
  esac

  # Нечего удалять — это не ошибка.
  # Nothing to remove is not an error.
  if (( rm_lib == 0 && rm_bin == 0 )); then
    local -a rows=()
    if [[ "${lstate}" == "missing" && "${bstate}" == "missing" ]]; then
      rows+=("• BS не установлена / BS is not installed: ${TARGET_LIB}, ${TARGET_BIN}")
      if [[ "${INSTALL_AUTODETECT:-0}" == "1" ]]; then
        rows+=("• проверено / checked: ${BS_SYSTEM_PREFIX}/lib/bs, ${HOME:-<HOME не задан / unset>}/.local/lib/bs")
      fi
    fi
    rows+=("${kept[@]}")
    local kind other_lib
    for kind in system local; do
      other_lib="$(install_std_lib "${kind}")" || continue
      [[ "${other_lib}" == "${TARGET_LIB}" ]] && continue
      if [[ "$(install_lib_state "${other_lib}")" == "bs" ]]; then
        if [[ "${kind}" == "system" ]]; then
          local c="sudo ./install.sh uninstall"
          [[ "${INSTALL_EUID_OVERRIDE:-${EUID:-$(id -u)}}" -eq 0 ]] && c="./install.sh uninstall"
          rows+=("• но есть системная установка / but a system install exists: ${other_lib} (версия / version $(install_version_of "${other_lib}"))")
          rows+=("  Удалить её / Remove it:  ${c}")
        else
          rows+=("• но есть локальная установка / but a local install exists: ${other_lib} (версия / version $(install_version_of "${other_lib}"))")
          rows+=("  Удалить её / Remove it:  ./install.sh --local uninstall")
        fi
      fi
    done
    if [[ "${INSTALL_EUID_OVERRIDE:-${EUID:-$(id -u)}}" -eq 0 && -n "${SUDO_USER:-}" ]]; then
      rows+=("• запущено через sudo (HOME=${HOME:-}): локальную установку пользователя ${SUDO_USER} удаляйте без sudo / local installs of ${SUDO_USER} are removed without sudo")
    fi
    install_box "УДАЛЯТЬ НЕЧЕГО / NOTHING TO REMOVE" "${rows[@]}"
    return 0
  fi

  # Права записи нужны только там, где будем удалять.
  # Write access is needed only where something is removed.
  (( rm_bin == 1 )) && { install_require_writable "${BIN_DIR}" "BIN_DIR" || exit 1; }
  (( rm_lib == 1 )) && { install_require_writable "${LIB_DIR}" "LIB_DIR" || exit 1; }

  printf "Удаление BS (%s)\n" "${MODE}"
  printf "  TARGET_BIN: %s\n" "${TARGET_BIN}"
  printf "  TARGET_LIB: %s\n" "${TARGET_LIB}"

  # Дополнение bash убираем вместе с установкой — но только своё
  # Remove the bash completion along with the install — but only our own file
  if (( rm_lib == 1 || rm_bin == 1 )); then
    uninstall_completion
  fi

  # Сначала lib, потом wrapper: при сбое rm остаётся рабочая команда bs и
  # удаление можно повторить (раньше wrapper исчезал, а lib оставалась
  # частично удалённой; под set -e сбой был ещё и молчаливым).
  # lib first, wrapper second: if rm fails, a working bs command stays and the
  # removal can be repeated (the wrapper used to vanish while the lib was left
  # half-deleted; under set -e the failure was also silent).
  if (( rm_lib == 1 )); then
    if ! rm -rf -- "${TARGET_LIB}"; then
      install_error "Удаление не выполнено: не удалось удалить ${TARGET_LIB} (часть файлов могла быть удалена)"         "Uninstall failed: cannot remove ${TARGET_LIB} (some files may be gone)"         "Wrapper оставлен. Исправьте права и удалите остаток вручную / The wrapper is kept. Fix the permissions and remove the rest by hand: chmod -R u+w ${TARGET_LIB} && rm -rf ${TARGET_LIB}"
      exit 1
    fi
    printf "Удален / Removed: %s\n" "${TARGET_LIB}"
  else
    printf "Нет каталога / No directory: %s\n" "${TARGET_LIB}"
  fi
  if (( rm_bin == 1 )); then
    rm -f -- "${TARGET_BIN}"
    printf "Удален / Removed: %s\n" "${TARGET_BIN}"
  else
    printf "Нет wrapper / No wrapper: %s\n" "${TARGET_BIN}"
  fi

  if (( ${#kept[@]} > 0 )); then
    install_box "ЧАСТЬ НЕ УДАЛЕНА / PART LEFT IN PLACE" "${kept[@]}"
  fi

  # Do NOT wipe user's ~/.local trees; only tidy empty parents
  if [[ "${MODE}" == "local" ]]; then
    # rmdir удаляет ТОЛЬКО пустые каталоги: если в ~/.local/bin или
    # ~/.local/lib есть другие файлы — они остаются нетронутыми.
    # rmdir removes ONLY empty dirs: any other files in ~/.local/bin or
    # ~/.local/lib are left untouched.
    if is::dir "${BIN_DIR}" && utils::quiet_err rmdir "${BIN_DIR}"; then
      printf "Удален пустой каталог: %s\n" "${BIN_DIR}"
    fi
    if is::dir "${LIB_DIR}" && utils::quiet_err rmdir "${LIB_DIR}"; then
      printf "Удален пустой каталог: %s\n" "${LIB_DIR}"
    fi
    # PATH-строка нужна, пока жива стандартная локальная установка: удаление
    # custom-копии её не трогает. Иначе — только точное совпадение строки.
    # The PATH line is needed while the standard local install lives: removing
    # a custom copy leaves it. Otherwise only the exact installer line goes.
    if [[ -n "$(install_wrapper_root "${HOME}/.local/bin/bs")" ]]; then
      printf "PATH-строка в rc-файлах оставлена: жива локальная установка %s\nPATH line kept in rc files: the local install %s still exists\n" \
        "${HOME}/.local/bin/bs" "${HOME}/.local/bin/bs"
    else
      remove_path_entries_all
    fi
  fi

  printf "Готово.\n"
  install_report_others uninstall
}
