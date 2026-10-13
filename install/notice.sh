#!/usr/bin/env bash
# @tier core — bash 4+ only (gated by bootstrap/bs.sh), works everywhere
# @tier core — только bash 4+ (гейт в bootstrap/bs.sh), работает везде

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

# @global BS_SYSTEM_PREFIX — Env: префикс «системной» установки (категория: env)
# @global BS_SYSTEM_PREFIX — Env: prefix of the "system" install (category: env)
# Системная установка: lib = $BS_SYSTEM_PREFIX/lib/bs, wrapper = .../bin/bs.
# Тесты задают его внутри mktemp -d — реальный /usr/local не затрагивается.
BS_SYSTEM_PREFIX="${BS_SYSTEM_PREFIX:-/usr/local}"
BS_SYSTEM_PREFIX="${BS_SYSTEM_PREFIX%/}"
[[ -n "${BS_SYSTEM_PREFIX}" ]] || BS_SYSTEM_PREFIX="/usr/local"

# Тестовый хук: подменить EUID (проверка ветки sudo --local без root). Влияет
# только на сообщения и отказы, не на реальные права записи.
# Test hook: override EUID (to exercise the sudo --local branch without root).
# Affects messages and refusals only, never real write access.
INSTALL_EUID_OVERRIDE="${BS_INSTALL_FAKE_EUID:-}"

# Рамка уведомления (копия update_box() из bs: паддинг и перенос по символам,
# цвет как у логгера; через printf, а не log::*).
# Notice frame (a copy of update_box() from bs: character-based padding and
# wrapping, logger-like colour; printf, not log::*).
# $1 title, $2.. rows
install_box() {
  # Символы, а не байты, даже в локали C/POSIX (CI, ssh без LANG).
  # Characters, not bytes, even in the C/POSIX locale (CI, ssh without LANG).
  local LC_ALL=C.UTF-8
  local -r title="$1"
  shift
  local -r inner=58
  local -a body=()
  local text
  for text in "$@"; do
    while (( ${#text} > inner )); do
      # Перенос по пробелу внутри окна (команды не рвутся посреди слова);
      # если пробела нет — режем по символам.
      # Wrap at a space inside the window (commands are not split mid-word);
      # without one, cut by characters.
      local chunk="${text:0:inner}" cut="${inner}"
      if [[ "${text:inner:1}" != " " ]]; then
        local head_part="${chunk% *}"
        [[ "${head_part}" != "${chunk}" ]] && (( ${#head_part} > 12 )) && cut="${#head_part}"
      fi
      body+=("${text:0:cut}")
      text="${text:cut}"
      text="${text# }"
    done
    body+=("${text}")
  done

  local color_b='' color_reset=''
  if log::__is_color_enabled 1; then
    color_b=$'\033[34m'
    color_reset=$'\033[0m'
  fi
  local rule
  printf -v rule '%*s' "${inner}" ''
  rule="${rule// /─}"
  local title_row
  printf -v title_row '%*s' "$(( (inner - ${#title}) / 2 ))" ''
  title_row+="${title}"

  # Паддинг по символам: printf '%-*s' считает БАЙТЫ и ломает кириллицу.
  # Pad by CHARACTERS: printf '%-*s' measures BYTES and breaks Cyrillic.
  local n
  (( n = inner - ${#title_row} )) && (( n > 0 )) && printf -v title_row '%s%*s' "${title_row}" "${n}" ''
  printf '%s╭%s╮%s\n' "${color_b}" "${rule}" "${color_reset}"
  printf '%s│%s│%s\n' "${color_b}" "${title_row}" "${color_reset}"
  printf '%s├%s┤%s\n' "${color_b}" "${rule}" "${color_reset}"
  local line
  for line in "${body[@]}"; do
    (( n = inner - ${#line} )) && (( n > 0 )) && printf -v line '%s%*s' "${line}" "${n}" ''
    printf '%s│%s│%s\n' "${color_b}" "${line}" "${color_reset}"
  done
  printf '%s╰%s╯%s\n' "${color_b}" "${rule}" "${color_reset}"
}

# Реальный отказ: ERROR (RU, затем EN) и подсказки в stderr. Не завершает
# процесс — вызывающий делает exit 1.
# A real refusal: ERROR (RU, then EN) and hints on stderr. Does not exit —
# the caller does `exit 1`.
# $1 RU, $2 EN, $3.. hint lines
install_error() {
  local -r ru="$1" en="$2"
  shift 2
  printf 'ERROR: %s\n       %s\n' "${ru}" "${en}" >&2
  local hint
  for hint in "$@"; do
    printf '  %s\n' "${hint}" >&2
  done
}

# Одиночное заметное уведомление (stdout), RU затем EN.
# A single visible notice (stdout), RU then EN.
install_note() {
  printf 'ВНИМАНИЕ: %s\nNOTE: %s\n' "$1" "$2"
}

# ---------------------------------------------------------------------------
# Стандартные места / Standard locations
# ---------------------------------------------------------------------------

# Каталог lib стандартной установки: system | local. Для local без HOME — 1.
# Lib directory of a standard install: system | local. 1 for local without HOME.
install_std_lib() {
  case "$1" in
    system) printf '%s' "${BS_SYSTEM_PREFIX}/lib/bs" ;;
    local)  [[ -n "${HOME:-}" ]] || return 1; printf '%s' "${HOME}/.local/lib/bs" ;;
    *) return 1 ;;
  esac
}

# Путь wrapper'а стандартной установки / Wrapper path of a standard install
install_std_bin() {
  case "$1" in
    system) printf '%s' "${BS_SYSTEM_PREFIX}/bin/bs" ;;
    local)  [[ -n "${HOME:-}" ]] || return 1; printf '%s' "${HOME}/.local/bin/bs" ;;
    *) return 1 ;;
  esac
}

# Есть ли следы стандартной установки (каталог lib или wrapper BS)?
# Are there traces of a standard install (lib dir or a BS wrapper)?
install_std_present() {
  local lib bin
  lib="$(install_std_lib "$1")" || return 1
  bin="$(install_std_bin "$1")" || return 1
  [[ -d "${lib}" ]] && return 0
  [[ -n "$(install_wrapper_root "${bin}")" ]]
}

# Команда запуска установщика для действия $1 (install|uninstall) с теми же
# режимом и переопределениями, что у текущего запуска.
# The installer command for action $1 matching the current mode and overrides.
install_cmd() {
  local -r action="$1"
  local cmd="./install.sh"
  [[ "${MODE}" == "local" ]] && cmd+=" --local"
  [[ "${action}" == "install" ]] || cmd+=" ${action}"
  local env_part=""
  [[ -n "${INSTALL_USER_PREFIX:-}"  ]] && env_part+="PREFIX=${INSTALL_USER_PREFIX} "
  [[ -n "${INSTALL_USER_BIN_DIR:-}" ]] && env_part+="BIN_DIR=${INSTALL_USER_BIN_DIR} "
  [[ -n "${INSTALL_USER_LIB_DIR:-}" ]] && env_part+="LIB_DIR=${INSTALL_USER_LIB_DIR} "
  if [[ "${MODE}" == "system" && "${INSTALL_EUID_OVERRIDE:-${EUID:-$(id -u)}}" -ne 0 ]]; then
    if [[ -n "${env_part}" ]]; then
      printf 'sudo env %s%s' "${env_part}" "${cmd}"
    else
      printf 'sudo %s' "${cmd}"
    fi
  else
    printf '%s%s' "${env_part}" "${cmd}"
  fi
}

# ---------------------------------------------------------------------------
# Классификация состояния / State classification
# ---------------------------------------------------------------------------

# BS_ROOT из wrapper'а BS; пусто, если файл не wrapper BS (нет строки
# `export BS_ROOT=`, не обычный файл, симлинк).
# BS_ROOT from a BS wrapper; empty when the file is not a BS wrapper (no
# `export BS_ROOT=` line, not a regular file, a symlink).
install_wrapper_root() {
  local -r file="$1" re='^export BS_ROOT="(.*)"[[:space:]]*$'
  local line
  [[ -f "${file}" && ! -L "${file}" ]] || return 0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" =~ ${re} ]]; then
      printf '%s' "${BASH_REMATCH[1]}"
      return 0
    fi
  done < "${file}" 2>/dev/null
  return 0
}

# Состояние каталога lib / State of a lib directory:
#   missing  — нет / absent          empty   — пустой каталог / empty dir
#   bs       — установка BS / a BS install
#   source   — исходный чекаут (.git, tests/) или каталог-источник
#   symlink  — символическая ссылка / a symlink
#   file     — не каталог / not a directory
#   foreign  — чужой каталог / somebody else's directory
install_lib_state() {
  local -r dir="$1"
  if [[ -L "${dir}" ]]; then printf 'symlink'; return 0; fi
  if [[ ! -e "${dir}" ]]; then printf 'missing'; return 0; fi
  if [[ ! -d "${dir}" ]]; then printf 'file'; return 0; fi
  if [[ -z "$(ls -A -- "${dir}" 2>/dev/null)" ]]; then printf 'empty'; return 0; fi

  local real_dir real_src
  real_dir="$(cd -- "${dir}" 2>/dev/null && pwd -P)" || real_dir="${dir}"
  real_src="$(cd -- "${SOURCE_ROOT}" 2>/dev/null && pwd -P)" || real_src="${SOURCE_ROOT}"
  if [[ -e "${dir}/.git" || -d "${dir}/tests" \
        || "${real_dir}" == "${real_src}" || "${real_src}/" == "${real_dir}/"* ]]; then
    printf 'source'
    return 0
  fi
  # Установка BS: файлы запуска, либо манифест BS (повреждённая, но своя).
  # A BS install: the launch files, or a BS manifest (damaged but ours).
  if [[ -f "${dir}/bootstrap/init.sh" && -f "${dir}/bs" ]]; then
    printf 'bs'
    return 0
  fi
  if [[ -f "${dir}/.install" ]] && grep -q '^# BS install manifest' "${dir}/.install" 2>/dev/null; then
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
install_bin_state() {
  local -r file="$1" lib="$2"
  if [[ ! -e "${file}" && ! -L "${file}" ]]; then printf 'missing'; return 0; fi
  local root
  root="$(install_wrapper_root "${file}")"
  if [[ -z "${root}" ]]; then printf 'foreign'; return 0; fi
  if [[ "${root}" == "${lib}" ]]; then printf 'here'; return 0; fi
  if [[ "$(install_lib_state "${root}")" == "bs" ]]; then printf 'other'; else printf 'stale'; fi
}

# Версия установки в каталоге $1 или "?" / Version of the install in $1, or "?"
install_version_of() {
  local v
  v="$(bs::version::of "$1")"
  printf '%s' "${v:-?}"
}

# Человекочитаемая причина состояния lib (RU / EN)
# Human-readable reason for a lib state (RU / EN)
install_lib_reason() {
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
install_validate_paths() {
  local name val
  for name in PREFIX BIN_DIR LIB_DIR; do
    val="${!name}"
    if [[ "${val}" != /* ]]; then
      install_error "${name} должен быть абсолютным путём: «${val}»" \
        "${name} must be an absolute path: \"${val}\"" \
        "Пример / Example: ${name}=\$HOME/opt/bs ./install.sh --local"
      return 1
    fi
  done
  if [[ "${TARGET_LIB}" == *[\"\$\`\\]* || "${TARGET_LIB}" == *$'\n'* ]]; then
    install_error "Путь «${TARGET_LIB}» содержит запрещённые символы (кавычка, \$, обратная кавычка, \\, перевод строки)" \
      "Path \"${TARGET_LIB}\" contains forbidden characters (quote, \$, backtick, backslash, newline)" \
      "Они попали бы в wrapper как код. Выберите другой PREFIX / LIB_DIR." \
      "They would end up in the wrapper as code. Pick another PREFIX / LIB_DIR."
    return 1
  fi
  if [[ "${TARGET_BIN}" == "${TARGET_LIB}" ]]; then
    install_error "BIN_DIR и LIB_DIR совпадают (${BIN_DIR}): wrapper и каталог lib получили бы одно имя" \
      "BIN_DIR and LIB_DIR are the same (${BIN_DIR}): the wrapper and the lib directory would share a name" \
      "Задайте разные каталоги / Use different directories: BIN_DIR=... LIB_DIR=..."
    return 1
  fi
  return 0
}

# Ближайший существующий предок пути (сам путь, если существует).
# The nearest existing ancestor of a path (the path itself if it exists).
install_nearest_existing() {
  local dir="$1"
  while [[ ! -e "${dir}" && ! -L "${dir}" && "${dir}" != "/" && "${dir}" != "." ]]; do
    dir="$(dirname -- "${dir}")"
  done
  printf '%s' "${dir}"
}

# Можно ли создать/удалить записи в каталоге $1 (учитывая, что его ещё может
# не быть: проверяется ближайший существующий предок)? Проверяется реальная
# возможность записи, а не EUID: PREFIX=/opt/x, доступный пользователю,
# работает без root. При отказе печатает ERROR+подсказки, возвращает 1.
# Can entries be created/removed in $1 (it may not exist yet: the nearest
# existing ancestor is tested)? Real writability is tested, not EUID: a
# user-owned PREFIX=/opt/x works without root. On refusal prints an ERROR
# with hints and returns 1.
install_require_writable() {
  local -r dir="$1" what="$2"
  local near
  near="$(install_nearest_existing "${dir}")"
  if [[ ! -d "${near}" ]]; then
    install_error "${what} ${dir}: «${near}» существует, но не каталог" \
      "${what} ${dir}: \"${near}\" exists but is not a directory" \
      "Выберите другой путь / Choose another path: PREFIX=... ./install.sh"
    return 1
  fi
  [[ -w "${near}" && -x "${near}" ]] && return 0

  local -a hints=()
  if [[ "${MODE}" == "local" ]]; then
    hints+=("Проверьте права на «${near}» (chmod / владелец) или выберите другой PREFIX." \
            "Check the permissions of \"${near}\" (chmod / owner) or pick another PREFIX.")
  else
    hints+=("С правами администратора / With administrator rights:  $(install_cmd "${INSTALL_ACTION:-install}")")
    hints+=("Без root, в ~/.local / Without root, into ~/.local:  ./install.sh --local")
    hints+=("Или в свой каталог / Or into your own directory:  PREFIX=\$HOME/opt/bs ./install.sh")
  fi
  install_error "Нет прав записи для ${what} ${dir} (ближайший существующий каталог: ${near})" \
    "No write permission for ${what} ${dir} (nearest existing directory: ${near})" \
    "${hints[@]}"
  return 1
}

# HOME для local-режима: задан, абсолютный, существует.
# HOME for local mode: set, absolute, exists.
install_require_home() {
  if [[ -z "${HOME:-}" ]]; then
    install_error "Переменная HOME не задана или пуста: --local ставит в \$HOME/.local и правит \$HOME/.bashrc" \
      "HOME is unset or empty: --local installs into \$HOME/.local and edits \$HOME/.bashrc" \
      "Задайте / Set it:  HOME=/home/you ./install.sh --local" \
      "Либо системная установка / Or a system install:  sudo ./install.sh"
    return 1
  fi
  if [[ "${HOME}" != /* || ! -d "${HOME}" ]]; then
    install_error "HOME указывает не на существующий абсолютный каталог: «${HOME}»" \
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
install_check_sudo_local() {
  local -r action="$1"
  local euid="${INSTALL_EUID_OVERRIDE:-${EUID:-$(id -u)}}"
  [[ "${euid}" -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]] || return 0

  local sudo_home="${BS_INSTALL_SUDO_HOME:-}"
  if [[ -z "${sudo_home}" ]]; then
    sudo_home="$(getent passwd "${SUDO_USER}" 2>/dev/null | cut -d: -f6)" || sudo_home=""
  fi

  if [[ -n "${sudo_home}" && "${HOME%/}" == "${sudo_home%/}" ]]; then
    # Удаление rc-строки сохраняет владельца файла — отказ нужен для установки.
    # Uninstall keeps file ownership, so only install is refused.
    [[ "${action}" == "install" ]] || return 0
    install_error "sudo с --local ставит BS от root в домашний каталог пользователя ${SUDO_USER} (${HOME}): файлы стали бы принадлежать root" \
      "sudo with --local would install BS as root into the home of ${SUDO_USER} (${HOME}): the files would become root-owned" \
      "Запустите без sudo / Run without sudo:  ./install.sh --local" \
      "Для всей системы / For the whole system:  sudo ./install.sh"
    return 1
  fi
  install_note "запущено через sudo: установка пойдёт для root (HOME=${HOME}), а не для пользователя ${SUDO_USER}" \
               "started via sudo: BS goes to root (HOME=${HOME}), not to user ${SUDO_USER}"
  return 0
}

# ---------------------------------------------------------------------------
# Другие установки и порядок PATH / Other installs and PATH order
# ---------------------------------------------------------------------------

# Каталог $1 есть в PATH запустившей оболочки? / Is $1 in the caller's PATH?
install_in_path() {
  case ":${INSTALL_ORIG_PATH:-${PATH}}:" in
    *":${1%/}:"*) return 0 ;;
    *) return 1 ;;
  esac
}

# Какой из wrapper'ов $@ запустится по команде `bs` (порядок PATH).
# Which of the wrappers $@ runs for the `bs` command (PATH order).
install_first_in_path() {
  local -a dirs=()
  local dir cand
  IFS=: read -ra dirs <<< "${INSTALL_ORIG_PATH:-${PATH}}" || true
  for dir in "${dirs[@]}"; do
    [[ -n "${dir}" ]] || continue
    for cand in "$@"; do
      if [[ "${dir%/}/bs" == "${cand}" ]]; then
        printf '%s' "${cand}"
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
install_report_others() {
  local -r action="$1"
  local kind lib bin
  local -a rows=()
  local -a other_bins=()
  local -a other_kinds=()
  for kind in system local; do
    lib="$(install_std_lib "${kind}")" || continue
    bin="$(install_std_bin "${kind}")" || continue
    [[ "${lib}" == "${TARGET_LIB}" ]] && continue
    if [[ "$(install_lib_state "${lib}")" == "bs" ]]; then
      other_bins+=("${bin}")
      other_kinds+=("${kind}")
      rows+=("• ${kind}: ${lib} — версия / version $(install_version_of "${lib}")")
    fi
  done
  (( ${#other_bins[@]} > 0 )) || return 0

  local title cmd i
  if [[ "${action}" == "install" ]]; then
    title="ЕСТЬ ДРУГАЯ УСТАНОВКА / ANOTHER INSTALL EXISTS"
    rows+=("• эта / this: ${TARGET_LIB} — версия / version $(install_version_of "${TARGET_LIB}")")
    local first
    first="$(install_first_in_path "${TARGET_BIN}" "${other_bins[@]}")"
    if [[ -z "${first}" ]]; then
      rows+=("PATH: ни одна копия не найдена в PATH / no copy is found in PATH")
    elif [[ "${first}" == "${TARGET_BIN}" ]]; then
      rows+=("PATH: команда bs запускает НОВУЮ копию (${first}) / bs runs the NEW copy")
    else
      rows+=("PATH: команда bs запускает ДРУГУЮ копию (${first}), а не новую / bs runs the OTHER copy, not the new one")
      rows+=("Поставьте ${BIN_DIR} в PATH раньше или удалите лишнюю / Put ${BIN_DIR} earlier in PATH or remove the extra copy")
    fi
  else
    title="ОСТАЛАСЬ ДРУГАЯ УСТАНОВКА / ANOTHER INSTALL REMAINS"
  fi
  for i in "${!other_kinds[@]}"; do
    if [[ "${other_kinds[i]}" == "system" ]]; then
      cmd="sudo ./install.sh uninstall"
      [[ "${INSTALL_EUID_OVERRIDE:-${EUID:-$(id -u)}}" -eq 0 ]] && cmd="./install.sh uninstall"
    else
      cmd="./install.sh --local uninstall"
    fi
    rows+=("Удалить ${other_kinds[i]} / Remove ${other_kinds[i]}:  ${cmd}")
  done
  install_box "${title}" "${rows[@]}"
}
