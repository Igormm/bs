#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, printf, test, ls/grep/cut/id; рамка считает символы UTF-8 через bs_str_width / valid POSIX sh: case, printf, test, ls/grep/cut/id; the frame counts UTF-8 characters through bs_str_width
# @tier core — builtins, ls, grep, cut, id, getent, tr and wc; works everywhere
#
# Installer notices and install-state classification.
# Уведомления установщика и классификация состояния установки.
#
# Принцип: любое действие за пределами очевидной логики объясняется
# двуязычным (RU первым) уведомлением с точными командами.
# Безобидное «ничего не сделано» — рамка «…НЕТ / NO …», exit 0 (см. навык
# bs-cli-noop-output); реальный отказ — ERROR с причиной и подсказкой, exit 1.
# Principle: anything beyond the obvious logic is explained by a bilingual
# (RU first) notice with exact commands. A harmless "nothing done" is a
# «…НЕТ / NO …» frame, exit 0; a real refusal is an ERROR with a reason
# and a hint, exit 1.
#
# Два слоя / Two layers
#   bs_install_error, bs_install_note, bs_install_require_home, bs_install_check_sudo_local работают
#   ДО ядра (install.sh зовёт их раньше bootstrap): только printf и test. Остальное — после ядра
#   (рамка использует bs_str_*, bs_arr_*, логгер).
#   bs_install_error, bs_install_note, bs_install_require_home and bs_install_check_sudo_local run
#   BEFORE the kernel (install.sh calls them ahead of the bootstrap): only printf and test. The rest
#   comes after the kernel (the frame uses bs_str_*, bs_arr_* and the logger).
#
# ИМЕНА / NAMES
#   Real functions: bs_install_box, bs_install_error, bs_install_note, bs_install_euid,
#   bs_install_std_lib, bs_install_std_bin, bs_install_std_present, bs_install_cmd,
#   bs_install_wrapper_root, bs_install_lib_state, bs_install_bin_state, bs_install_version_of,
#   bs_install_lib_reason, bs_install_validate_paths, bs_install_nearest_existing,
#   bs_install_require_writable, bs_install_require_home, bs_install_check_sudo_local,
#   bs_install_in_path, bs_install_first_in_path, bs_install_report_others; in bash and zsh also
#   the old names install_box, install_error, … (aliases).
#   Настоящие функции — bs_install_*; в bash и zsh — ещё и прежние install_box, install_error, …
#   (псевдонимы).

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# @global BS_SYSTEM_PREFIX — Env: префикс «системной» установки (категория: env)
# @global BS_SYSTEM_PREFIX — Env: prefix of the "system" install (category: env)
# Системная установка: lib = $BS_SYSTEM_PREFIX/lib/bs, wrapper = .../bin/bs.
# Тесты задают его внутри mktemp -d — реальный /usr/local не затрагивается.
BS_SYSTEM_PREFIX="${BS_SYSTEM_PREFIX:-/usr/local}"
BS_SYSTEM_PREFIX="${BS_SYSTEM_PREFIX%/}"
if [ -z "${BS_SYSTEM_PREFIX}" ]; then BS_SYSTEM_PREFIX="/usr/local"; fi

# Тестовый хук: подменить EUID (проверка ветки sudo --local без root). Влияет
# только на сообщения и отказы, не на реальные права записи.
# Test hook: override EUID (to exercise the sudo --local branch without root).
# Affects messages and refusals only, never real write access.
INSTALL_EUID_OVERRIDE="${BS_INSTALL_FAKE_EUID:-}"

# @description EUID с учётом тестового хука (id -u: в dash и ash нет EUID) / The EUID with the test hook applied (id -u: dash and ash have no EUID)
# @stdout number / число
bs_install_euid() {
  if [ -n "${INSTALL_EUID_OVERRIDE:-}" ]; then
    printf '%s\n' "${INSTALL_EUID_OVERRIDE}"
  else
    id -u
  fi
}

# Рамка уведомления (копия update_box() из bs: паддинг и перенос по символам,
# цвет как у логгера; через printf, а не bs_log_*).
# Notice frame (a copy of update_box() from bs: character-based padding and
# wrapping, logger-like colour; printf, not bs_log_*).
# $1 title, $2.. rows
bs_install_box() {
  __bs_ntc_title=${1-}
  shift
  __bs_ntc_inner=58
  # Символы UTF-8, а не байты, в любой оболочке и локали: ширину даёт bs_str_width.
  # UTF-8 characters, not bytes, in every shell and locale: bs_str_width gives the width.
  bs_arr_clear bs_ntc_body
  for __bs_ntc_text in "$@"; do
    while [ "$(bs_str_width "${__bs_ntc_text}")" -gt "${__bs_ntc_inner}" ]; do
      # Перенос по пробелу внутри окна (команды не рвутся посреди слова);
      # если пробела нет — режем по символам.
      # Wrap at a space inside the window (commands are not split mid-word);
      # without one, cut by characters.
      __bs_ntc_chunk=$(bs_str_head "${__bs_ntc_text}" "${__bs_ntc_inner}")
      __bs_ntc_cut=${__bs_ntc_chunk}
      __bs_ntc_after=${__bs_ntc_text#"${__bs_ntc_chunk}"}
      case "${__bs_ntc_after}" in
        ' '*) ;;
        *)
          __bs_ntc_headpart=${__bs_ntc_chunk% *}
          if [ "${__bs_ntc_headpart}" != "${__bs_ntc_chunk}" ] \
             && [ "$(bs_str_width "${__bs_ntc_headpart}")" -gt 12 ]; then
            __bs_ntc_cut=${__bs_ntc_headpart}
          fi ;;
      esac
      bs_arr_push bs_ntc_body "${__bs_ntc_cut}"
      __bs_ntc_text=${__bs_ntc_text#"${__bs_ntc_cut}"}
      __bs_ntc_text=${__bs_ntc_text# }
    done
    bs_arr_push bs_ntc_body "${__bs_ntc_text}"
  done

  __bs_ntc_cb=''
  __bs_ntc_cr=''
  if bs_log_is_color_enabled 1; then
    __bs_ntc_cb=$(printf '\033[34m')
    __bs_ntc_cr=$(printf '\033[0m')
  fi
  __bs_ntc_rule=$(bs_str_repeat '─' "${__bs_ntc_inner}")
  __bs_ntc_tw=$(bs_str_width "${__bs_ntc_title}")
  __bs_ntc_pad=$((__bs_ntc_inner - __bs_ntc_tw))
  __bs_ntc_pad=$((__bs_ntc_pad / 2))
  # слишком длинный заголовок: прежний printf '%*s' с отрицательной шириной давал |ширину| пробелов / a title wider than the frame: the old printf '%*s' with a negative width gave |width| spaces
  if [ "${__bs_ntc_pad}" -lt 0 ]; then __bs_ntc_pad=$((0 - __bs_ntc_pad)); fi
  __bs_ntc_row="$(bs_str_repeat ' ' "${__bs_ntc_pad}")${__bs_ntc_title}"

  # Паддинг по символам: printf '%-*s' считает БАЙТЫ и ломает кириллицу.
  # Pad by CHARACTERS: printf '%-*s' measures BYTES and breaks Cyrillic.
  __bs_ntc_w=$(bs_str_width "${__bs_ntc_row}")
  __bs_ntc_n=$((__bs_ntc_inner - __bs_ntc_w))
  if [ "${__bs_ntc_n}" -gt 0 ]; then
    __bs_ntc_row="${__bs_ntc_row}$(bs_str_repeat ' ' "${__bs_ntc_n}")"
  fi
  printf '%s╭%s╮%s\n' "${__bs_ntc_cb}" "${__bs_ntc_rule}" "${__bs_ntc_cr}"
  printf '%s│%s│%s\n' "${__bs_ntc_cb}" "${__bs_ntc_row}" "${__bs_ntc_cr}"
  printf '%s├%s┤%s\n' "${__bs_ntc_cb}" "${__bs_ntc_rule}" "${__bs_ntc_cr}"
  eval "$(bs_arr_to_args bs_ntc_body)"
  for __bs_ntc_line in "$@"; do
    __bs_ntc_w=$(bs_str_width "${__bs_ntc_line}")
    __bs_ntc_n=$((__bs_ntc_inner - __bs_ntc_w))
    if [ "${__bs_ntc_n}" -gt 0 ]; then
      __bs_ntc_line="${__bs_ntc_line}$(bs_str_repeat ' ' "${__bs_ntc_n}")"
    fi
    printf '%s│%s│%s\n' "${__bs_ntc_cb}" "${__bs_ntc_line}" "${__bs_ntc_cr}"
  done
  printf '%s╰%s╯%s\n' "${__bs_ntc_cb}" "${__bs_ntc_rule}" "${__bs_ntc_cr}"
}

# Реальный отказ: ERROR (RU, затем EN) и подсказки в stderr. Не завершает
# процесс — вызывающий делает exit 1.
# A real refusal: ERROR (RU, then EN) and hints on stderr. Does not exit —
# the caller does `exit 1`.
# $1 RU, $2 EN, $3.. hint lines
bs_install_error() {
  printf 'ERROR: %s\n       %s\n' "${1-}" "${2-}" >&2
  shift 2
  for __bs_ntc_hint in "$@"; do
    printf '  %s\n' "${__bs_ntc_hint}" >&2
  done
}

# Одиночное заметное уведомление (stdout), RU затем EN.
# A single visible notice (stdout), RU then EN.
bs_install_note() {
  printf 'ВНИМАНИЕ: %s\nNOTE: %s\n' "$1" "$2"
}

# ---------------------------------------------------------------------------
# Стандартные места / Standard locations
# ---------------------------------------------------------------------------

# Каталог lib стандартной установки: system | local. Для local без HOME — 1.
# Lib directory of a standard install: system | local. 1 for local without HOME.
bs_install_std_lib() {
  case "$1" in
    system) printf '%s' "${BS_SYSTEM_PREFIX}/lib/bs" ;;
    local)  if [ -z "${HOME:-}" ]; then return 1; fi; printf '%s' "${HOME}/.local/lib/bs" ;;
    *) return 1 ;;
  esac
}

# Путь wrapper'а стандартной установки / Wrapper path of a standard install
bs_install_std_bin() {
  case "$1" in
    system) printf '%s' "${BS_SYSTEM_PREFIX}/bin/bs" ;;
    local)  if [ -z "${HOME:-}" ]; then return 1; fi; printf '%s' "${HOME}/.local/bin/bs" ;;
    *) return 1 ;;
  esac
}

# Есть ли следы стандартной установки (каталог lib или wrapper BS)?
# Are there traces of a standard install (lib dir or a BS wrapper)?
bs_install_std_present() {
  __bs_ntc_pl=$(bs_install_std_lib "$1") || return 1
  __bs_ntc_pb=$(bs_install_std_bin "$1") || return 1
  if [ -d "${__bs_ntc_pl}" ]; then return 0; fi
  [ -n "$(bs_install_wrapper_root "${__bs_ntc_pb}")" ]
}

# Команда запуска установщика для действия $1 (install|uninstall) с теми же
# режимом и переопределениями, что у текущего запуска.
# The installer command for action $1 matching the current mode and overrides.
bs_install_cmd() {
  __bs_ntc_action=$1
  __bs_ntc_c="./install.sh"
  if [ "${MODE}" = "local" ]; then __bs_ntc_c="${__bs_ntc_c} --local"; fi
  if [ "${__bs_ntc_action}" != "install" ]; then __bs_ntc_c="${__bs_ntc_c} ${__bs_ntc_action}"; fi
  __bs_ntc_env=""
  if [ -n "${INSTALL_USER_PREFIX:-}"  ]; then __bs_ntc_env="${__bs_ntc_env}PREFIX=${INSTALL_USER_PREFIX} "; fi
  if [ -n "${INSTALL_USER_BIN_DIR:-}" ]; then __bs_ntc_env="${__bs_ntc_env}BIN_DIR=${INSTALL_USER_BIN_DIR} "; fi
  if [ -n "${INSTALL_USER_LIB_DIR:-}" ]; then __bs_ntc_env="${__bs_ntc_env}LIB_DIR=${INSTALL_USER_LIB_DIR} "; fi
  if [ "${MODE}" = "system" ] && [ "$(bs_install_euid)" -ne 0 ]; then
    if [ -n "${__bs_ntc_env}" ]; then
      printf 'sudo env %s%s' "${__bs_ntc_env}" "${__bs_ntc_c}"
    else
      printf 'sudo %s' "${__bs_ntc_c}"
    fi
  else
    printf '%s%s' "${__bs_ntc_env}" "${__bs_ntc_c}"
  fi
}

# ---------------------------------------------------------------------------
# Классификация состояния / State classification
# ---------------------------------------------------------------------------

# BS_ROOT из wrapper'а BS; пусто, если файл не wrapper BS (нет строки
# `export BS_ROOT=`, не обычный файл, симлинк).
# BS_ROOT from a BS wrapper; empty when the file is not a BS wrapper (no
# `export BS_ROOT=` line, not a regular file, a symlink).
bs_install_wrapper_root() {
  __bs_ntc_wf=$1
  if [ ! -f "${__bs_ntc_wf}" ] || [ -L "${__bs_ntc_wf}" ]; then return 0; fi
  while IFS= read -r __bs_ntc_wl || [ -n "${__bs_ntc_wl}" ]; do
    case "${__bs_ntc_wl}" in
      'export BS_ROOT="'*)
        __bs_ntc_wr=${__bs_ntc_wl#'export BS_ROOT="'}
        # завершающие пробельные символы после кавычки отбрасываем / trailing blanks after the quote are dropped
        __bs_ntc_wr=${__bs_ntc_wr%"${__bs_ntc_wr##*[! 	]}"}
        case "${__bs_ntc_wr}" in
          *'"')
            printf '%s' "${__bs_ntc_wr%\"}"
            return 0 ;;
        esac ;;
    esac
  done < "${__bs_ntc_wf}" 2>/dev/null
  return 0
}

# Состояние каталога lib / State of a lib directory:
#   missing  — нет / absent          empty   — пустой каталог / empty dir
#   bs       — установка BS / a BS install
#   source   — исходный чекаут (.git, tests/) или каталог-источник
#   symlink  — символическая ссылка / a symlink
#   file     — не каталог / not a directory
#   foreign  — чужой каталог / somebody else's directory
bs_install_lib_state() {
  __bs_ntc_dir=$1
  if [ -L "${__bs_ntc_dir}" ]; then printf 'symlink'; return 0; fi
  if [ ! -e "${__bs_ntc_dir}" ]; then printf 'missing'; return 0; fi
  if [ ! -d "${__bs_ntc_dir}" ]; then printf 'file'; return 0; fi
  # ls не сработал — считаем каталог чужим, а не пустым: пустой каталог установщик вправе заменить
  # ls failed — the directory counts as foreign, not empty: the installer may replace an empty directory
  __bs_ntc_ls=$(ls -A -- "${__bs_ntc_dir}" 2>/dev/null) || { printf 'foreign'; return 0; }
  if [ -z "${__bs_ntc_ls}" ]; then printf 'empty'; return 0; fi

  __bs_ntc_rd=$(cd -- "${__bs_ntc_dir}" 2>/dev/null && pwd -P) || __bs_ntc_rd=${__bs_ntc_dir}
  __bs_ntc_rs=$(cd -- "${SOURCE_ROOT}" 2>/dev/null && pwd -P) || __bs_ntc_rs=${SOURCE_ROOT}
  if [ -e "${__bs_ntc_dir}/.git" ] || [ -d "${__bs_ntc_dir}/tests" ] || [ "${__bs_ntc_rd}" = "${__bs_ntc_rs}" ]; then
    printf 'source'
    return 0
  fi
  case "${__bs_ntc_rs}/" in
    "${__bs_ntc_rd}/"*)
      printf 'source'
      return 0 ;;
  esac
  # Установка BS: файлы запуска, либо манифест BS (повреждённая, но своя).
  # A BS install: the launch files, or a BS manifest (damaged but ours).
  if [ -f "${__bs_ntc_dir}/bootstrap/init.sh" ] && [ -f "${__bs_ntc_dir}/bs" ]; then
    printf 'bs'
    return 0
  fi
  if [ -f "${__bs_ntc_dir}/.install" ] && grep -q '^# BS install manifest' "${__bs_ntc_dir}/.install" 2>/dev/null; then
    printf 'bs'
    return 0
  fi
  printf 'foreign'
}

# Состояние wrapper'а $1 относительно lib $2 / Wrapper $1 state relative to lib $2:
#   missing — нет           here    — wrapper BS, указывает на $2
#   stale   — wrapper BS, указывает на несуществующую установку
#   other   — wrapper BS, указывает на другую живую установку
#   foreign — чужой файл/каталог/симлинк
bs_install_bin_state() {
  __bs_ntc_bf=$1
  __bs_ntc_bl=$2
  if [ ! -e "${__bs_ntc_bf}" ] && [ ! -L "${__bs_ntc_bf}" ]; then printf 'missing'; return 0; fi
  __bs_ntc_br=$(bs_install_wrapper_root "${__bs_ntc_bf}")
  if [ -z "${__bs_ntc_br}" ]; then printf 'foreign'; return 0; fi
  if [ "${__bs_ntc_br}" = "${__bs_ntc_bl}" ]; then printf 'here'; return 0; fi
  if [ "$(bs_install_lib_state "${__bs_ntc_br}")" = "bs" ]; then printf 'other'; else printf 'stale'; fi
}

# Версия установки в каталоге $1 или "?" / Version of the install in $1, or "?"
bs_install_version_of() {
  __bs_ntc_v=$(bs_version_of "$1")
  printf '%s' "${__bs_ntc_v:-?}"
}

# Человекочитаемая причина состояния lib (RU / EN)
# Human-readable reason for a lib state (RU / EN)
bs_install_lib_reason() {
  case "$1" in
    source)  printf 'это исходный репозиторий или каталог-источник (.git, tests/) / it is a source checkout or the source directory (.git, tests/)' ;;
    symlink) printf 'это символическая ссылка / it is a symbolic link' ;;
    file)    printf 'это не каталог / it is not a directory' ;;
    foreign) printf 'не похоже на установку BS (нет bootstrap/init.sh и bs) / does not look like a BS install (no bootstrap/init.sh and bs)' ;;
    *)       printf '%s' "$1" ;;
  esac
}

# ---------------------------------------------------------------------------
# Проверки окружения / Environment checks
# ---------------------------------------------------------------------------

# Пути должны быть абсолютными и без символов, ломающих wrapper.
# Paths must be absolute and free of characters that would break the wrapper.
# Возвращает 0, если всё в порядке; иначе печатает ERROR и возвращает 1.
bs_install_validate_paths() {
  for __bs_ntc_name in PREFIX BIN_DIR LIB_DIR; do
    bs_var_get "${__bs_ntc_name}" __bs_ntc_val || __bs_ntc_val=''
    case "${__bs_ntc_val}" in
      /*) ;;
      *)
        bs_install_error "${__bs_ntc_name} должен быть абсолютным путём: «${__bs_ntc_val}»" \
          "${__bs_ntc_name} must be an absolute path: \"${__bs_ntc_val}\"" \
          "Пример / Example: ${__bs_ntc_name}=\$HOME/opt/bs ./install.sh --local"
        return 1 ;;
    esac
  done
  __bs_ntc_bad=0
  case "${TARGET_LIB}" in
    *\"*|*\$*|*\`*|*\\*|*'
'*) __bs_ntc_bad=1 ;;
  esac
  if [ "${__bs_ntc_bad}" = 1 ]; then
    bs_install_error "Путь «${TARGET_LIB}» содержит запрещённые символы (кавычка, \$, обратная кавычка, \\, перевод строки)" \
      "Path \"${TARGET_LIB}\" contains forbidden characters (quote, \$, backtick, backslash, newline)" \
      "Они попали бы в wrapper как код. Выберите другой PREFIX / LIB_DIR." \
      "They would end up in the wrapper as code. Pick another PREFIX / LIB_DIR."
    return 1
  fi
  if [ "${TARGET_BIN}" = "${TARGET_LIB}" ]; then
    bs_install_error "BIN_DIR и LIB_DIR совпадают (${BIN_DIR}): wrapper и каталог lib получили бы одно имя" \
      "BIN_DIR and LIB_DIR are the same (${BIN_DIR}): the wrapper and the lib directory would share a name" \
      "Задайте разные каталоги / Use different directories: BIN_DIR=... LIB_DIR=..."
    return 1
  fi
  return 0
}

# Ближайший существующий предок пути (сам путь, если существует).
# The nearest existing ancestor of a path (the path itself if it exists).
bs_install_nearest_existing() {
  __bs_ntc_ne=$1
  while [ ! -e "${__bs_ntc_ne}" ] && [ ! -L "${__bs_ntc_ne}" ] && [ "${__bs_ntc_ne}" != "/" ] && [ "${__bs_ntc_ne}" != "." ]; do
    __bs_ntc_ne=$(dirname -- "${__bs_ntc_ne}")
  done
  printf '%s' "${__bs_ntc_ne}"
}

# Можно ли создать/удалить записи в каталоге $1 (учитывая, что его ещё может
# не быть: проверяется ближайший существующий предок)? Проверяется реальная
# возможность записи, а не EUID: PREFIX=/opt/x, доступный пользователю,
# работает без root. При отказе печатает ERROR+подсказки, возвращает 1.
# Can entries be created/removed in $1 (it may not exist yet: the nearest
# existing ancestor is tested)? Real writability is tested, not EUID: a
# user-owned PREFIX=/opt/x works without root. On refusal prints an ERROR
# with hints and returns 1.
bs_install_require_writable() {
  __bs_ntc_wdir=$1
  __bs_ntc_what=$2
  __bs_ntc_near=$(bs_install_nearest_existing "${__bs_ntc_wdir}")
  if [ ! -d "${__bs_ntc_near}" ]; then
    bs_install_error "${__bs_ntc_what} ${__bs_ntc_wdir}: «${__bs_ntc_near}» существует, но не каталог" \
      "${__bs_ntc_what} ${__bs_ntc_wdir}: \"${__bs_ntc_near}\" exists but is not a directory" \
      "Выберите другой путь / Choose another path: PREFIX=... ./install.sh"
    return 1
  fi
  if [ -w "${__bs_ntc_near}" ] && [ -x "${__bs_ntc_near}" ]; then return 0; fi

  if [ "${MODE}" = "local" ]; then
    bs_install_error "Нет прав записи для ${__bs_ntc_what} ${__bs_ntc_wdir} (ближайший существующий каталог: ${__bs_ntc_near})" \
      "No write permission for ${__bs_ntc_what} ${__bs_ntc_wdir} (nearest existing directory: ${__bs_ntc_near})" \
      "Проверьте права на «${__bs_ntc_near}» (chmod / владелец) или выберите другой PREFIX." \
      "Check the permissions of \"${__bs_ntc_near}\" (chmod / owner) or pick another PREFIX."
  else
    bs_install_error "Нет прав записи для ${__bs_ntc_what} ${__bs_ntc_wdir} (ближайший существующий каталог: ${__bs_ntc_near})" \
      "No write permission for ${__bs_ntc_what} ${__bs_ntc_wdir} (nearest existing directory: ${__bs_ntc_near})" \
      "С правами администратора / With administrator rights:  $(bs_install_cmd "${INSTALL_ACTION:-install}")" \
      "Без root, в ~/.local / Without root, into ~/.local:  ./install.sh --local" \
      "Или в свой каталог / Or into your own directory:  PREFIX=\$HOME/opt/bs ./install.sh"
  fi
  return 1
}

# HOME для local-режима: задан, абсолютный, существует.
# HOME for local mode: set, absolute, exists.
bs_install_require_home() {
  if [ -z "${HOME:-}" ]; then
    bs_install_error "Переменная HOME не задана или пуста: --local ставит в \$HOME/.local и правит rc-файл вашей оболочки" \
      "HOME is unset or empty: --local installs into \$HOME/.local and edits the rc file of your shell" \
      "Задайте / Set it:  HOME=/home/you ./install.sh --local" \
      "Либо системная установка / Or a system install:  sudo ./install.sh"
    return 1
  fi
  __bs_ntc_hok=1
  case "${HOME}" in
    /*) if [ ! -d "${HOME}" ]; then __bs_ntc_hok=0; fi ;;
    *) __bs_ntc_hok=0 ;;
  esac
  if [ "${__bs_ntc_hok}" = 0 ]; then
    bs_install_error "HOME указывает не на существующий абсолютный каталог: «${HOME}»" \
      "HOME is not an existing absolute directory: \"${HOME}\"" \
      "Исправьте HOME / Fix HOME:  HOME=/home/you ./install.sh --local"
    return 1
  fi
  return 0
}

# sudo ./install.sh --local: файлы стали бы принадлежать root в домашнем
# каталоге пользователя, который вызвал sudo.
# sudo ./install.sh --local: files would become root-owned inside the home
# directory of the user who called sudo.
# $1 install|uninstall. Возвращает 1 (после ERROR) — отказ; иначе 0.
bs_install_check_sudo_local() {
  __bs_ntc_sa=$1
  __bs_ntc_euid=$(bs_install_euid)
  if [ "${__bs_ntc_euid}" -ne 0 ] || [ -z "${SUDO_USER:-}" ] || [ "${SUDO_USER}" = "root" ]; then
    return 0
  fi

  __bs_ntc_sh="${BS_INSTALL_SUDO_HOME:-}"
  if [ -z "${__bs_ntc_sh}" ]; then
    __bs_ntc_sh=$(getent passwd "${SUDO_USER}" 2>/dev/null | cut -d: -f6) || __bs_ntc_sh=""
  fi

  if [ -n "${__bs_ntc_sh}" ] && [ "${HOME%/}" = "${__bs_ntc_sh%/}" ]; then
    # Удаление rc-строки сохраняет владельца файла — отказ нужен для установки.
    # Uninstall keeps file ownership, so only install is refused.
    if [ "${__bs_ntc_sa}" != "install" ]; then return 0; fi
    bs_install_error "sudo с --local ставит BS от root в домашний каталог пользователя ${SUDO_USER} (${HOME}): файлы стали бы принадлежать root" \
      "sudo with --local would install BS as root into the home of ${SUDO_USER} (${HOME}): the files would become root-owned" \
      "Запустите без sudo / Run without sudo:  ./install.sh --local" \
      "Для всей системы / For the whole system:  sudo ./install.sh"
    return 1
  fi
  bs_install_note "запущено через sudo: установка пойдёт для root (HOME=${HOME}), а не для пользователя ${SUDO_USER}" \
                  "started via sudo: BS goes to root (HOME=${HOME}), not to user ${SUDO_USER}"
  return 0
}

# ---------------------------------------------------------------------------
# Другие установки и порядок PATH / Other installs and PATH order
# ---------------------------------------------------------------------------

# Каталог $1 есть в PATH запустившей оболочки? / Is $1 in the caller's PATH?
bs_install_in_path() {
  case ":${INSTALL_ORIG_PATH:-${PATH}}:" in
    *":${1%/}:"*) return 0 ;;
    *) return 1 ;;
  esac
}

# Какой из wrapper'ов $@ запустится по команде `bs` (порядок PATH).
# Which of the wrappers $@ runs for the `bs` command (PATH order).
bs_install_first_in_path() {
  __bs_ntc_rest="${INSTALL_ORIG_PATH:-${PATH}}:"
  while [ -n "${__bs_ntc_rest}" ]; do
    __bs_ntc_pd=${__bs_ntc_rest%%:*}
    __bs_ntc_rest=${__bs_ntc_rest#*:}
    if [ -z "${__bs_ntc_pd}" ]; then continue; fi
    for __bs_ntc_cand in "$@"; do
      if [ "${__bs_ntc_pd%/}/bs" = "${__bs_ntc_cand}" ]; then
        printf '%s' "${__bs_ntc_cand}"
        return 0
      fi
    done
  done
  return 0
}

# Рамка о других установках BS (system / local), отличных от текущей цели.
# $1 install|uninstall. Ничего не печатает, если других установок нет.
# A frame about other BS installs (system / local) besides the current
# target. Prints nothing when there are none.
bs_install_report_others() {
  __bs_ntc_ra=$1
  bs_arr_clear bs_ntc_rows
  bs_arr_clear bs_ntc_obins
  bs_arr_clear bs_ntc_okinds
  for __bs_ntc_kind in system local; do
    __bs_ntc_lib=$(bs_install_std_lib "${__bs_ntc_kind}") || continue
    __bs_ntc_bin=$(bs_install_std_bin "${__bs_ntc_kind}") || continue
    if [ "${__bs_ntc_lib}" = "${TARGET_LIB}" ]; then continue; fi
    if [ "$(bs_install_lib_state "${__bs_ntc_lib}")" = "bs" ]; then
      bs_arr_push bs_ntc_obins "${__bs_ntc_bin}"
      bs_arr_push bs_ntc_okinds "${__bs_ntc_kind}"
      bs_arr_push bs_ntc_rows "• ${__bs_ntc_kind}: ${__bs_ntc_lib} — версия / version $(bs_install_version_of "${__bs_ntc_lib}")"
    fi
  done
  if [ "$(bs_arr_len bs_ntc_obins)" -eq 0 ]; then return 0; fi

  if [ "${__bs_ntc_ra}" = "install" ]; then
    __bs_ntc_title="ЕСТЬ ДРУГАЯ УСТАНОВКА / ANOTHER INSTALL EXISTS"
    bs_arr_push bs_ntc_rows "• эта / this: ${TARGET_LIB} — версия / version $(bs_install_version_of "${TARGET_LIB}")"
    eval "$(bs_arr_to_args bs_ntc_obins)"
    __bs_ntc_first=$(bs_install_first_in_path "${TARGET_BIN}" "$@")
    if [ -z "${__bs_ntc_first}" ]; then
      bs_arr_push bs_ntc_rows "PATH: ни одна копия не найдена в PATH / no copy is found in PATH"
    elif [ "${__bs_ntc_first}" = "${TARGET_BIN}" ]; then
      bs_arr_push bs_ntc_rows "PATH: команда bs запускает НОВУЮ копию (${__bs_ntc_first}) / bs runs the NEW copy"
    else
      bs_arr_push bs_ntc_rows "PATH: команда bs запускает ДРУГУЮ копию (${__bs_ntc_first}), а не новую / bs runs the OTHER copy, not the new one"
      bs_arr_push bs_ntc_rows "Поставьте ${BIN_DIR} в PATH раньше или удалите лишнюю / Put ${BIN_DIR} earlier in PATH or remove the extra copy"
    fi
  else
    __bs_ntc_title="ОСТАЛАСЬ ДРУГАЯ УСТАНОВКА / ANOTHER INSTALL REMAINS"
  fi
  __bs_ntc_i=0
  __bs_ntc_cnt=$(bs_arr_len bs_ntc_okinds)
  while [ "${__bs_ntc_i}" -lt "${__bs_ntc_cnt}" ]; do
    bs_arr_get bs_ntc_okinds "${__bs_ntc_i}" __bs_ntc_kind
    if [ "${__bs_ntc_kind}" = "system" ]; then
      __bs_ntc_cmd="sudo ./install.sh uninstall"
      if [ "$(bs_install_euid)" -eq 0 ]; then __bs_ntc_cmd="./install.sh uninstall"; fi
    else
      __bs_ntc_cmd="./install.sh --local uninstall"
    fi
    bs_arr_push bs_ntc_rows "Удалить ${__bs_ntc_kind} / Remove ${__bs_ntc_kind}:  ${__bs_ntc_cmd}"
    __bs_ntc_i=$((__bs_ntc_i + 1))
  done
  eval "$(bs_arr_to_args bs_ntc_rows)"
  bs_install_box "${__bs_ntc_title}" "$@"
}

bs_shell_alias bs_install_box install_box
bs_shell_alias bs_install_error install_error
bs_shell_alias bs_install_note install_note
bs_shell_alias bs_install_std_lib install_std_lib
bs_shell_alias bs_install_std_bin install_std_bin
bs_shell_alias bs_install_std_present install_std_present
bs_shell_alias bs_install_cmd install_cmd
bs_shell_alias bs_install_wrapper_root install_wrapper_root
bs_shell_alias bs_install_lib_state install_lib_state
bs_shell_alias bs_install_bin_state install_bin_state
bs_shell_alias bs_install_version_of install_version_of
bs_shell_alias bs_install_lib_reason install_lib_reason
bs_shell_alias bs_install_validate_paths install_validate_paths
bs_shell_alias bs_install_nearest_existing install_nearest_existing
bs_shell_alias bs_install_require_writable install_require_writable
bs_shell_alias bs_install_require_home install_require_home
bs_shell_alias bs_install_check_sudo_local install_check_sudo_local
bs_shell_alias bs_install_in_path install_in_path
bs_shell_alias bs_install_first_in_path install_first_in_path
bs_shell_alias bs_install_report_others install_report_others
