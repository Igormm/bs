#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, printf, test, find/sort/sed/git; команды, не требующие bash / valid POSIX sh: case, printf, test, find/sort/sed/git; the commands that do not need bash
# @tier core — builtins, find, sort, git (optional); works everywhere
#
# bootstrap/cli.sh — команды bs, которые работают в любой оболочке (POSIX-часть bs::cli::*)
# bootstrap/cli.sh — the bs commands that run in any shell (the POSIX part of bs::cli::*)
#
# Остальные команды (lang-doc, lsp, chat, api, ts, audit, build, rfc, run, repl),
# запускающие код lib/, пока в bootstrap/bs.sh на bash; в оболочке
# без bash bs_cli_delegate отвечает, что команде нужен bash. Тела функций вызывают ядро и
# выполняются только после его загрузки.
# The other commands (lang-doc, lsp, chat, api, ts, audit, build, rfc, run, repl),
# which run lib/ code, are still in bootstrap/bs.sh in bash; in a
# shell without bash bs_cli_delegate answers that the command needs bash. The function bodies call
# the kernel and run only after it is loaded.
#
# ИМЕНА / NAMES
#   Real functions: bs_cli_die, bs_cli_need_bash, bs_cli_delegate, bs_cli_maybe_exec_script, bs_cli_help, bs_cli_help_cmd,
#   bs_cli_short_sha, bs_cli_install_info_get, bs_cli_update_manifest_valid,
#   bs_cli_bs_full_info_lines, bs_cli_bs_running_block, bs_cli_version_cmd, bs_cli_env_cmd,
#   bs_cli_list_cmd, bs_cli_init_shell_*, bs_cli_shebang_*, bs_cli_call_*, bs_cli_doctor_cmd,
#   bs_cli_uninstall_cmd, bs_cli_where_cmd (with bs_cli_where_*), bs_cli_update_cmd (with the
#   bs_cli_update_* steps: fetch, lock, apply, rollback, manifest, …), and the helpers that update,
#   uninstall and where share (bs_cli_update_box, bs_cli_update_die, bs_cli_update_missing_lines,
#   bs_cli_bs_running_info, bs_cli_path_hits, …); in bash and zsh also
#   bs::cli::die, bs::cli::help, … (the old names).
#   Настоящие функции — bs_cli_*; в bash и zsh — ещё и прежние bs::cli::die, bs::cli::help, …

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# Простой self-guard: файл подключают bs.sh и сам bs, до ядра bs_guard ещё нет
# A raw self-guard: bs.sh and bs itself source this file, and bs_guard does not exist before the kernel
case "${__BS_CLI_SOURCED:-}" in
  1) return 0 2>/dev/null ;;
esac
__BS_CLI_SOURCED=1

# Терминал ли вывод — решаем один раз при загрузке файла: bs_cli_paint зовут
# внутри "$(...)", где stdout уже труба и `-t 1` всегда ложно. Запоминаем
# состояние настоящего stdout процесса до всех подстановок.
# Whether the output is a terminal is decided once when the file is loaded:
# bs_cli_paint is called inside "$(...)", where stdout is already a pipe and
# `-t 1` is always false. Remember the real stdout of the process before any
# substitution.
if [ -t 1 ]; then __bs_cli_color_tty=1; else __bs_cli_color_tty=0; fi

# @description Завершить с сообщением об ошибке и очисткой / Exit with an error message and the cleanup
# @param $@ message / сообщение
bs_cli_die() {
  bs_error_exit "$*"
}

# @description Команде нужен bash: объяснить и завершить / The command needs bash: explain and exit
# @param $1 command name / имя команды
bs_cli_need_bash() {
  bs_error_exit "bs $1: команда пока требует bash 4.2+, а запущено: $(bs_shell_family) (установите: apk add bash / apt install bash / dnf install bash) / bs $1: the command still needs bash 4.2+, running: $(bs_shell_family) (install: apk add bash / apt install bash / dnf install bash)"
}

# @description Вызвать команду, живущую в bash-слое (bs.sh); без неё — объяснить / Call a command that lives in the bash layer (bs.sh); without it, explain
# @param $1 command name for the message / имя команды для сообщения
# @param $2 function / функция
# @param $@ arguments / аргументы
bs_cli_delegate() {
  __bs_cli_dn=$1
  __bs_cli_df=$2
  shift 2
  if command -v "${__bs_cli_df}" >/dev/null 2>&1; then
    "${__bs_cli_df}" "$@"
  else
    bs_cli_need_bash "${__bs_cli_dn}"
  fi
}

# @private
# @description Для `bs run script` и shebang-режима сразу exec в bash, который
#   загружает ядро один раз; иначе ядро грузилось бы и в этом процессе, и в дочернем.
#   Вызывается до загрузки ядра, поэтому не использует bs_cli_die/ядро.
#   Возвращает 1, если аргументы — не run и не файл (обычный путь диспетчера).
# @description For `bs run script` and the shebang mode, exec at once into the bash
#   that loads the kernel once; otherwise the kernel would load in this process and
#   in the child. Called before the kernel, so it uses neither bs_cli_die nor core.
#   Returns 1 when the arguments are neither run nor a file (the normal dispatch path).
# @param $@ the entry-point arguments / аргументы точки входа
bs_cli_maybe_exec_script() {
  # Ранний exec возможен только при bash 4.2+ в текущей оболочке; иначе обычный
  # путь ниже скажет bs_cli_need_bash (например, Alpine без bash).
  # The early exec needs bash 4.2+ in the current shell; otherwise the normal path
  # below reports bs_cli_need_bash (for example, Alpine without bash).
  bs_shell_host_ok || return 1

  __bs_cli_es_script=''
  case "${1:-}" in
    run)
      shift
      if [ $# -lt 1 ]; then
        printf 'BS: error: run: script path required\n' >&2
        exit 2
      fi
      __bs_cli_es_script=$1
      shift
      if [ ! -f "$__bs_cli_es_script" ]; then
        printf 'BS: error: run: file not found: %s\n' "$__bs_cli_es_script" >&2
        exit 2
      fi ;;
    '') ;;
    *)
      case "$1" in
        help|-h|--help|version|env|list|lang-doc|lsp|chat|sync|rfc|api|ts|audit|doctor|build|repl|calc|init-shell|shebang|call|update|uninstall|where) ;;
        *)
          if [ -f "$1" ]; then
            __bs_cli_es_script=$1
            shift
          fi ;;
      esac ;;
  esac
  [ -n "$__bs_cli_es_script" ] || return 1

  # shellcheck disable=SC2034  # BS_RUN_SCRIPT читает bs::is_main в дочернем процессе / BS_RUN_SCRIPT is read by bs::is_main in the child
  BS_RUN_SCRIPT=$__bs_cli_es_script
  export BS_RUN_SCRIPT
  exec "$(bs_shell_host)" -c '
    unset BS_INITIALIZED
    . "$1/bootstrap/init.sh" || exit 1
    bs_strict
    __bs_cli_es_child_script=$2
    shift 2
    . "$__bs_cli_es_child_script" "$@"
  ' bs "$BS_ROOT" "$__bs_cli_es_script" "$@"
}

# @description Справка по командам bs / The help of the bs commands
bs_cli_help() {
  printf 'BS Framework %s – command launcher & shebang interpreter\n' "$(bs_version_get)"
  printf 'Usage: %s [command] [args...]\n' "$(bs_cli_paint cmd 'bs')"
  printf '       %s <command>   Show detailed help for a command\n' "$(bs_cli_paint cmd 'bs help')"

  bs_cli_help_head 'Info / Информация:'
  bs_cli_help_row 'help, -h, --help' 'Show this help / показать эту справку'
  bs_cli_help_row 'help <command>' 'Show detailed help for a command / справка по команде'
  bs_cli_help_row 'version [--full]' 'Print framework version (--full: build and install info) / версия (--full: сборка и установка)'
  bs_cli_help_row 'env' 'Show environment (BS_ROOT, PATH, install manifest) / окружение'
  bs_cli_help_row 'doctor' 'Check framework integrity / проверка целостности'

  bs_cli_help_head 'Modules / Модули:'
  bs_cli_help_row 'list' 'List available modules (core/, lib/) / список модулей'
  bs_cli_help_row 'lang-doc' 'JSON index of function docs (LSP metadata) / индекс функций'
  bs_cli_help_row 'lsp' 'Run language server (JSON-RPC over stdin/stdout) / LSP'

  bs_cli_help_head 'Development / Разработка:'
  bs_cli_help_row 'run <script> [args]' 'Execute script inside BS environment / запуск скрипта'
  bs_cli_help_row 'build <script>' 'Assemble a standalone self-extracting script / сборка'
  bs_cli_help_row 'repl' 'Interactive REPL (BS shell) / интерактивная консоль'
  bs_cli_help_row 'calc' 'RPN calculator / калькулятор ОПН'
  bs_cli_help_row 'rfc [number]' 'RFC helpers (1925, 3986, 4122, 4180) / RFC'
  bs_cli_help_row 'api <sub> [args]' 'OpenAPI 3.x client / OpenAPI-клиент'
  bs_cli_help_row 'ts <command>' 'TypeScript toolchain / TS-тулчейн'
  bs_cli_help_row 'audit [roots]' 'GNU-only tool audit / аудит GNU-зависимостей'
  bs_cli_help_row 'chat [opts]' 'Interactive LLM chat / чат с LLM'

  bs_cli_help_head 'Maintenance / Обслуживание:'
  bs_cli_help_row 'update [opts]' 'Update installed copies from a local repo or GitHub / обновление'
  bs_cli_help_row 'uninstall [opts]' 'Remove installed BS copies / удаление'
  bs_cli_help_row 'where [--deep]' 'Find every trace of BS on this machine / все следы BS на машине'
  bs_cli_help_row 'init-shell [SHELL]' 'PATH snippet for your shell: bash zsh ash dash ksh fish nu / snippet для вашей оболочки'
  bs_cli_help_row 'call FUNC [ARGS]' 'Call a kernel/library function from any shell (fish, nu, dash...) / вызвать функцию из любой оболочки'
  bs_cli_help_row 'shebang <cmd>' 'Check and rewrite #! lines for this machine (Termux: no /usr/bin/env) / проверка и правка #! для этой машины'
  bs_cli_help_row '--strict-shell[=SHELL]' '(before the command) refuse lib/ modules whose @shell tier does not fit the shell bs was started from, or the NAMED SHELL (--strict-shell=dash: will it work in dash) / отказывать модулям lib/, чей tier @shell не подходит оболочке запуска или УКАЗАННОЙ оболочке'

  bs_cli_help_head 'Shebang mode:'
  printf '  #!/usr/bin/env %s\n' "$(bs_cli_paint cmd 'bs')"
  printf '  (set BS_SHEBANG=1 internally)\n'

  bs_cli_help_head 'Examples:'
  printf '  %s\n' "$(bs_cli_paint cmd 'bs doctor')"
  printf '  %s\n' "$(bs_cli_paint cmd 'bs help build')"
  printf '  %s\n' "$(bs_cli_paint cmd 'bs run ./examples/deploy.sh --prod')"
  printf '  %s\n' "$(bs_cli_paint cmd 'bs list | grep system')"
}

# @private Строка справки: имя команды (подсвечено) + описание / A help row: the
#   command name (highlighted) + the description
bs_cli_help_row() {
  __bs_cli_hn=$(printf '%-20s' "${1-}")
  printf '  %s %s\n' "$(bs_cli_paint cmd "${__bs_cli_hn}")" "${2-}"
}

# @private Заголовок раздела справки / A help section header
bs_cli_help_head() {
  printf '%s\n' "$(bs_cli_paint head "$1")"
}

# @description Показать подробную справку по одной команде через её --help / Show detailed help for a single command by calling its --help
# @param $1 Command name / имя команды
bs_cli_help_cmd() {
  __bs_cli_hc=${1:-}
  if [ -z "${__bs_cli_hc}" ]; then
    bs_cli_help
    return 0
  fi
  case "${__bs_cli_hc}" in
    help|-h|--help)
      # встроенная справка bash, если она есть, иначе эта / the bash built-in help when there is one, else this one
      if command -v help >/dev/null 2>&1; then help; else bs_cli_help; fi ;;
    version)        printf 'Usage: bs version [--full]\n\nPrint the framework version; --full adds the path, install kind, source and last update.\n' ;;
    env)            printf 'Usage: bs env\n\nShow BS_ROOT, PATH and the install manifest.\n' ;;
    list)           bs_cli_list_cmd --help ;;
    lang-doc)       bs_cli_delegate lang-doc bs::cli::lang_doc_cmd --help ;;
    lsp)            bs_cli_delegate lsp bs::cli::lsp_cmd --help ;;
    chat)           bs_cli_delegate chat bs::cli::chat_cmd --help ;;
    api)            bs_cli_delegate api bs::cli::api_cmd --help ;;
    ts)             bs_cli_delegate ts bs::cli::ts_cmd --help ;;
    audit)          bs_cli_delegate audit bs::cli::audit_cmd --help ;;
    doctor)         bs_cli_doctor_cmd --help ;;
    run)            printf 'Usage: bs run <script> [args...]\n\nExecute a script inside the BS environment.\n' ;;
    build)          bs_cli_delegate build bs::cli::build_cmd --help ;;
    repl)           printf 'Usage: bs repl\n\nInteractive REPL (BS shell).\n' ;;
    calc)           printf 'Usage: bs calc [expression]\n\nRPN calculator on dc.\n' ;;
    update|sync)    bs_cli_update_cmd --help ;;
    uninstall)      bs_cli_uninstall_cmd --help ;;
    where)          bs_cli_where_cmd --help ;;
    init-shell)     bs_cli_init_shell_usage ;;
    shebang)        bs_cli_shebang_usage ;;
    call)           bs_cli_call_usage ;;
    rfc)            bs_cli_delegate rfc bs::cli::rfc_cmd --help ;;
    *)              bs_cli_die "help: unknown command: ${__bs_cli_hc}" ;;
  esac
}

# @private Первые 7 символов хеша коммита / First 7 characters of a commit hash
bs_cli_short_sha() {
  printf '%s' "$(bs_str_head "${1-}" 7)"
}

# @private Значение ключа из манифеста установки (<lib>/.install, key=value).
# @private Value of a key from the install manifest (<lib>/.install, key=value).
# @param $1 Install directory / Каталог установки
# @param $2 Key / Ключ
bs_cli_install_info_get() {
  __bs_cli_if="$1/.install"
  __bs_cli_ik=$2
  if [ ! -f "${__bs_cli_if}" ]; then return 0; fi
  while IFS= read -r __bs_cli_il; do
    case "${__bs_cli_il}" in
      "${__bs_cli_ik}="*)
        printf '%s\n' "${__bs_cli_il#*=}"
        return 0 ;;
    esac
  done < "${__bs_cli_if}"
  return 0
}

# @private Манифест читаем и выглядит как key=value с mode=.
# @private The manifest is readable key=value text with a mode= line.
bs_cli_update_manifest_valid() {
  __bs_cli_mh=0
  if [ ! -f "$1" ] || [ ! -r "$1" ]; then return 1; fi
  while IFS= read -r __bs_cli_ml || [ -n "${__bs_cli_ml}" ]; do
    case "${__bs_cli_ml}" in
      ''|'#'*) ;;
      mode=*) __bs_cli_mh=1 ;;
      [a-z_]*=*) ;;
      *) return 1 ;;
    esac
  done < "$1"
  [ "${__bs_cli_mh}" -eq 1 ]
}

# @private Colour only when the output is a terminal and the colour gate is on.
# @private Цвет только для терминала и при включённом гейте цвета.
bs_cli_color_on() {
  if [ -n "${BS_CLI_INFO_NO_COLOR:-}" ]; then return 1; fi
  if [ -n "${NO_COLOR:-}" ]; then return 1; fi
  case "${BS_LOG_COLOR:-auto}" in
    always) return 0 ;;
    never) return 1 ;;
  esac
  # bs_cli_paint is called inside "$(...)", where stdout is a pipe: use the
  # terminal state saved when this file was loaded.
  # bs_cli_paint вызывается внутри "$(...)", где stdout — труба: берём
  # состояние терминала, сохранённое при загрузке файла.
  if [ "$#" -eq 0 ] && [ -n "${__bs_cli_color_tty:-}" ]; then
    [ "${__bs_cli_color_tty}" = 1 ]
    return
  fi
  [ -t "${1:-1}" ]
}

# @private Wrap text in the colour of an install kind; no-op without a terminal.
# @private Окрасить текст цветом вида установки; без терминала — без изменений.
# @param $1 kind: local|system|custom|checkout|bad|warn / вид установки
# @param $2 text / текст
bs_cli_paint() {
  if ! bs_cli_color_on; then
    printf '%s' "$2"
    return 0
  fi
  case "$1" in
    local)    __bs_cli_pc='1;32' ;;
    system)   __bs_cli_pc='1;33' ;;
    custom)   __bs_cli_pc='1;35' ;;
    checkout) __bs_cli_pc='1;36' ;;
    path)     __bs_cli_pc='1;34' ;;
    commit)   __bs_cli_pc='1;36' ;;
    commit_same) __bs_cli_pc='1;32' ;;
    commit_diff) __bs_cli_pc='1;33' ;;
    bad)      __bs_cli_pc='1;31' ;;
    warn)     __bs_cli_pc='1;33' ;;
    cmd)      __bs_cli_pc='1;36' ;;
    head)     __bs_cli_pc='1;1' ;;
    *)        __bs_cli_pc='0' ;;
  esac
  printf '\033[%sm%s\033[0m' "${__bs_cli_pc}" "$2"
}

# @private Строки сведений о запущенной копии — ровно то, что `bs version --full`
# печатает после строки версии: path, вид установки, источник, последнее
# обновление. Вид установки выделен цветом в терминале. Читает манифест и git,
# чужой код не запускает. Те же строки идут в начале и в каждой рамке
# `bs update` / `bs uninstall`.
# @private The detail lines about the running copy — exactly what
# `bs version --full` prints after the version line: path, install kind,
# source, last update. The install kind is coloured in a terminal. Reads the
# manifest and git, runs no foreign code. The same lines open every
# `bs update` / `bs uninstall` run and notice box.
bs_cli_bs_full_info_lines() {
  printf '  %-10s %s\n' "path:" "${BS_ROOT}"
  if [ -e "${BS_ROOT}/.install" ] && ! bs_cli_update_manifest_valid "${BS_ROOT}/.install"; then
    printf '  %-10s %s\n' "install:" \
      "$(bs_cli_paint bad "manifest unreadable or corrupt / манифест повреждён: ${BS_ROOT}/.install (bs update recreates it)")"
  elif [ -f "${BS_ROOT}/.install" ]; then
    __bs_cli_imode=$(bs_cli_install_info_get "${BS_ROOT}" mode)
    __bs_cli_iat=$(bs_cli_install_info_get "${BS_ROOT}" installed_at)
    __bs_cli_iby=$(bs_cli_install_info_get "${BS_ROOT}" installed_by)
    __bs_cli_isrc=$(bs_cli_install_info_get "${BS_ROOT}" source)
    __bs_cli_isc=$(bs_cli_install_info_get "${BS_ROOT}" source_commit)
    __bs_cli_uat=$(bs_cli_install_info_get "${BS_ROOT}" updated_at)
    __bs_cli_ufrom=$(bs_cli_install_info_get "${BS_ROOT}" updated_from)
    __bs_cli_ucom=$(bs_cli_install_info_get "${BS_ROOT}" updated_commit)
    case "${__bs_cli_imode:-}" in
      local)  __bs_cli_ikind=local ;;
      system) __bs_cli_ikind=system ;;
      *)      __bs_cli_ikind=custom ;;
    esac
    printf '  %-10s %s, installed %s by %s\n' "install:" \
      "$(bs_cli_paint "${__bs_cli_ikind}" "${__bs_cli_imode:-?}")" \
      "${__bs_cli_iat:-?}" "${__bs_cli_iby:-?}"
    printf '  %-10s %s @ %s\n' "source:" \
      "$(bs_cli_paint path "${__bs_cli_isrc:-?}")" \
      "$(bs_cli_paint commit "$(bs_cli_short_sha "${__bs_cli_isc:-}")")"
    if [ -n "${__bs_cli_uat}" ]; then
      __bs_cli_ucom_short="$(bs_cli_short_sha "${__bs_cli_ucom:-}")"
      if [ -n "${__bs_cli_isc}" ] && [ -n "${__bs_cli_ucom}" ] && [ "${__bs_cli_isc}" != "${__bs_cli_ucom}" ]; then
        __bs_cli_ucolour=commit_diff
        __bs_cli_udiff=' (differs / отличается)'
      elif [ -n "${__bs_cli_isc}" ] && [ -n "${__bs_cli_ucom}" ]; then
        __bs_cli_ucolour=commit_same
        __bs_cli_udiff=''
      else
        __bs_cli_ucolour=commit
        __bs_cli_udiff=''
      fi
      printf '  %-10s %s from %s @ %s%s\n' "updated:" "${__bs_cli_uat}" \
        "$(bs_cli_paint path "${__bs_cli_ufrom:-?}")" \
        "$(bs_cli_paint "${__bs_cli_ucolour}" "${__bs_cli_ucom_short}")" "${__bs_cli_udiff}"
    fi
  elif [ -e "${BS_ROOT}/.git" ] && bs_utils_has git; then
    printf '  %-10s %s, commit %s (%s)%s\n' "install:" \
      "$(bs_cli_paint checkout 'source checkout')" \
      "$(bs_cli_paint commit "$(git -C "${BS_ROOT}" rev-parse --short=7 HEAD 2>/dev/null || printf '?')")" \
      "$(git -C "${BS_ROOT}" log -1 --format=%cd --date=short 2>/dev/null || printf '?')" \
      "$(if [ -n "$(git -C "${BS_ROOT}" status --porcelain 2>/dev/null)" ]; then printf ', with uncommitted changes'; fi)"
  elif [ -e "${BS_ROOT}/.git" ] || [ -d "${BS_ROOT}/tests" ]; then
    printf '  %-10s %s (git not available, commit unknown / git недоступен)\n' "install:" \
      "$(bs_cli_paint checkout 'source checkout')"
  else
    printf '  %-10s %s\n' "install:" \
      "$(bs_cli_paint warn "no manifest (installed by an older installer)")"
  fi
}

# @private Сведения о запущенной копии одним блоком: заголовок с версией и
# строки bs_cli_bs_full_info_lines. Первая строка «Запущен / Running: bs ВЕРСИЯ».
# @private The running copy as one block: a heading with the version and the
# bs_cli_bs_full_info_lines rows. The first line is "Запущен / Running: bs VERSION".
bs_cli_bs_running_block() {
  printf 'Запущен / Running: bs %s\n' "$(bs_version_get)"
  bs_cli_bs_full_info_lines
}

# bs version [--full]: номер версии; с --full — откуда взята эта копия BS
# bs version [--full]: the version number; --full adds where this BS copy is from
bs_cli_version_cmd() {
  case "${1:-}" in
    "")          bs_version_print; return 0 ;;
    -f|--full)   bs_version_print ;;
    *)           bs_cli_die "version: unknown argument: $1 (try: bs version --full)" ;;
  esac

  bs_cli_bs_full_info_lines
  printf '  codename:  %s\n' "$(bs_version_codename)"
}

# bs env: BS_ROOT, PATH и манифест установки / BS_ROOT, PATH and the install manifest
bs_cli_env_cmd() {
  printf 'BS_ROOT=%s\nPATH=%s\n' "$BS_ROOT" "$PATH"
  # Как установлена эта копия (манифест пишет install.sh)
  # How this copy was installed (the manifest is written by install.sh)
  if [ -e "${BS_ROOT}/.install" ] && ! bs_cli_update_manifest_valid "${BS_ROOT}/.install"; then
    printf '\nInstall manifest unreadable or corrupt / манифест повреждён: %s (bs update recreates it)\n' "${BS_ROOT}/.install"
  elif [ -f "${BS_ROOT}/.install" ]; then
    printf '\nInstall manifest (%s):\n' "${BS_ROOT}/.install"
    while IFS= read -r __bs_cli_el; do
      case "${__bs_cli_el}" in
        ''|'#'*) ;;
        *) printf '  %s\n' "${__bs_cli_el}" ;;
      esac
    done < "${BS_ROOT}/.install"
  elif [ -d "${BS_ROOT}/tests" ]; then
    printf '\nInstall: source checkout (not installed) / исходный репозиторий\n'
  else
    printf '\nInstall: no manifest (installed by an older installer) / манифеста нет\n'
  fi
}

# bs list: модули core/ и lib/ / the modules of core/ and lib/
bs_cli_list_cmd() {
  printf '%s\n' "$(bs_cli_paint head 'Available modules:')"
  __bs_cli_lc=0
  __bs_cli_lfiles=$(find "${BS_ROOT}/core" "${BS_ROOT}/lib" -type f -name '*.sh' 2>/dev/null | sort)
  if [ -n "${__bs_cli_lfiles}" ]; then
    while IFS= read -r __bs_cli_lf; do
      if [ -f "${__bs_cli_lf}" ]; then
        printf '  %s\n' "$(bs_cli_paint path "${__bs_cli_lf#"${BS_ROOT}"/}")"
        __bs_cli_lc=$((__bs_cli_lc + 1))
      fi
    done <<LIST_END
${__bs_cli_lfiles}
LIST_END
  fi
  printf '%s\n' "$(bs_cli_paint head "${__bs_cli_lc} modules")"
}

# @private Каталог с командой bs для PATH: из манифеста (bin=), иначе рядом с
# установкой (<prefix>/bin), иначе сам BS_ROOT (репозиторий с лаунчером bs).
# Для ~/.local/bin возвращается буквальный $HOME/.local/bin — как в установщике.
# @private The directory with the bs command for PATH: from the manifest
# (bin=), else next to the install (<prefix>/bin), else BS_ROOT itself (a
# repository with the bs launcher). ~/.local/bin is returned as a literal
# $HOME/.local/bin — as the installer writes it.
bs_cli_init_shell_bin_dir() {
  __bs_cli_ib=$(bs_cli_install_info_get "${BS_ROOT}" bin)
  if [ -n "${__bs_cli_ib}" ]; then
    __bs_cli_id=$(dirname -- "${__bs_cli_ib}")
  elif [ -f "${BS_ROOT%/lib/bs}/bin/bs" ]; then
    __bs_cli_id="${BS_ROOT%/lib/bs}/bin"
  else
    __bs_cli_id="${BS_ROOT}"
  fi
  if [ "${__bs_cli_id}" = "${HOME}/.local/bin" ]; then
    # shellcheck disable=SC2016  # $HOME должен попасть в rc-файл как текст / $HOME must reach the rc file as text
    printf '%s' '$HOME/.local/bin'
  else
    printf '%s' "${__bs_cli_id}"
  fi
}

bs_cli_init_shell_usage() {
  printf 'Usage: bs init-shell [SHELL | --list]\n\n'
  printf 'Print what to add to the rc file of your shell so that the bs command is found,\n'
  printf 'in the syntax of that shell, and how to apply it in the current terminal.\n'
  printf 'SHELL: bash zsh ash dash sh ksh mksh oksh osh fish nu (default: your shell).\n'
  # «--» нужен: строка начинается с «--list», и printf принял бы её за свою опцию (прежняя версия печатала ошибку)
  # «--» is needed: the string starts with "--list" and printf would take it for its own option (the old version printed an error)
  printf -- '--list  show every known shell: rc file, reload command, BS tier.\n\n'
  printf 'Tiers: native (bash 4.2+: library and commands), hosted (other shells: the bs\n'
  printf 'command, run by a bash 4.2+), unsupported (no bash 4.2+ on the machine).\n'
  printf 'Печатает, что добавить в rc-файл вашей оболочки, чтобы находилась команда bs,\n'
  printf 'в синтаксисе этой оболочки, и как применить это в текущем терминале.\n'
}

bs_cli_init_shell_cmd() {
  __bs_cli_ifam=""
  __bs_cli_iarg=${1:-}
  case "${__bs_cli_iarg}" in
    -h|--help) bs_cli_init_shell_usage; return 0 ;;
    --list)
      printf '%-6s %-9s %-52s %s\n' "shell" "tier" "rc file" "reload"
      for __bs_cli_if2 in bash zsh ash dash sh ksh mksh oksh osh fish nu; do
        printf '%-6s %-9s %-52s %s\n' "${__bs_cli_if2}" "$(bs_shell_tier "${__bs_cli_if2}")" \
          "$(bs_shell_rc_file "${__bs_cli_if2}")" "$(bs_shell_reload_hint "${__bs_cli_if2}")"
      done
      return 0 ;;
    "") __bs_cli_ifam="$(bs_shell_user)" ;;
    *)
      __bs_cli_ifam="$(bs_shell_of_name "${__bs_cli_iarg}")"
      if [ "${__bs_cli_ifam}" = "unknown" ]; then
        bs_cli_die "init-shell: unknown shell: ${__bs_cli_iarg} (known: bash zsh ash dash sh ksh mksh oksh osh fish nu; see: bs init-shell --list)"
      fi
      ;;
  esac
  bs_shell_known "${__bs_cli_ifam}" \
    || bs_cli_die "init-shell: no rc recipe for the shell '${__bs_cli_ifam}' (see: bs init-shell --list)"

  __bs_cli_irc="$(bs_shell_rc_file "${__bs_cli_ifam}")"
  __bs_cli_itier="$(bs_shell_tier "${__bs_cli_ifam}")"
  __bs_cli_idir="$(bs_cli_init_shell_bin_dir)"
  printf '# BS for %s (tier: %s) - add to %s\n' "${__bs_cli_ifam}" "${__bs_cli_itier}" "${__bs_cli_irc}"
  if bs_shell_can_source "${__bs_cli_ifam}"; then
    # Только bash 4.2+ может подключить BS как библиотеку (source)
    # Only bash 4.2+ can source BS as a library
    printf 'export BS_ROOT="%s"\n' "${BS_ROOT}"
    # shellcheck disable=SC2016  # ${BS_ROOT} раскроет rc-файл, не мы
    printf 'source "${BS_ROOT}/bootstrap/init.sh"\n'
  fi
  bs_shell_path_line "${__bs_cli_ifam}" "${__bs_cli_idir}"
  printf '# apply in this terminal: %s\n' "$(bs_shell_reload_hint "${__bs_cli_ifam}")"
  if ! bs_shell_can_source "${__bs_cli_ifam}"; then
    printf '# %s\n' "$(bs_shell_tier_desc "${__bs_cli_itier}")"
  fi
}

bs_cli_shebang_usage() {
  printf 'Usage: bs shebang <command> [options]\n\n'
  printf 'Manage the first line (#!) of scripts so that it works on THIS machine.\n'
  # shellcheck disable=SC2016  # $PREFIX — текст справки / $PREFIX is help text
  printf 'Termux has no /usr/bin/env: env lives in $PREFIX/bin/env.\n\n'
  printf 'Commands:\n'
  printf '  info                      this machine: env path, Termux, which modes work\n'
  printf '  line [--mode M] [--prog P] print the shebang line for the mode\n'
  printf '  check [PATH...]           does the shebang of each file work here (default: bs entry points)\n'
  printf '  set [--mode M] [--prog P] [--dry-run] PATH...   rewrite the shebang of files / directories\n\n'
  printf 'Modes: portable (#!/usr/bin/env P) | env (env found on this machine) | abs (full path of P) | auto (default)\n'
  printf 'set rewrites only files whose shebang already starts P (default P=bs); exit 1 if check finds a broken file.\n'
  printf 'Управляет первой строкой (#!) скриптов, чтобы она работала на ЭТОЙ машине.\n'
  # shellcheck disable=SC2016  # $PREFIX — текст справки / $PREFIX is help text
  printf 'В Termux нет /usr/bin/env: env лежит в $PREFIX/bin/env.\n'
}

# @private Files to look at: the arguments, directories expanded (shebang files only).
bs_cli_shebang_files() {
  for __bs_cli_sp in "$@"; do
    case "${__bs_cli_sp}" in
      -*) __bs_cli_sp="./${__bs_cli_sp}" ;;
    esac
    if [ -d "${__bs_cli_sp}" ]; then
      find "${__bs_cli_sp}" -type f -not -path '*/.git/*' -print
    elif [ -e "${__bs_cli_sp}" ]; then
      printf '%s\n' "${__bs_cli_sp}"
    else
      printf 'bs shebang: no such file: %s\n' "${__bs_cli_sp}" >&2
      return 1
    fi
  done
}

bs_cli_shebang_cmd() {
  __bs_cli_ssub=${1:-}
  case "${__bs_cli_ssub}" in
    ""|-h|--help|help) bs_cli_shebang_usage; return 0 ;;
  esac
  shift
  # shellcheck disable=SC1090,SC1091
  . "${BS_BOOTSTRAP_DIR}/shebang.sh" || bs_cli_die "shebang: bootstrap/shebang.sh not found"

  __bs_cli_smode="auto"
  __bs_cli_sprog="bs"
  __bs_cli_sdry=0
  bs_arr_clear bs_cli_spaths
  while [ $# -gt 0 ]; do
    __bs_cli_sarg=$1
    shift
    case "${__bs_cli_sarg}" in
      --mode=*) __bs_cli_smode="${__bs_cli_sarg#--mode=}" ;;
      --mode)   __bs_cli_smode="${1:?--mode needs a value}"; shift ;;
      --prog=*) __bs_cli_sprog="${__bs_cli_sarg#--prog=}" ;;
      --prog)   __bs_cli_sprog="${1:?--prog needs a value}"; shift ;;
      --dry-run) __bs_cli_sdry=1 ;;
      -h|--help) bs_cli_shebang_usage; return 0 ;;
      -*) bs_cli_die "shebang: unknown option: ${__bs_cli_sarg}" ;;
      *) bs_arr_push bs_cli_spaths "${__bs_cli_sarg}" ;;
    esac
  done

  __bs_cli_src=0
  eval "$(bs_arr_to_args bs_cli_spaths)"
  for __bs_cli_sp2 in "$@"; do
    [ -e "${__bs_cli_sp2}" ] || bs_cli_die "shebang: no such file or directory: ${__bs_cli_sp2}"
  done
  case "${__bs_cli_ssub}" in
    info)
      __bs_cli_se="$(bs_shebang_env_path || true)"
      printf 'termux:    %s\n' "$(bs_shebang_is_termux && echo yes || echo no)"
      printf 'env:       %s\n' "${__bs_cli_se:-not found}"
      printf '/usr/bin/env: %s\n' "$(if [ -x /usr/bin/env ]; then echo present; else echo absent; fi)"
      for __bs_cli_sm in portable env abs; do
        __bs_cli_sl="$(bs_shebang_line "${__bs_cli_sm}" "${__bs_cli_sprog}" 2>/dev/null || echo '-')"
        printf '%-9s  %s\n' "${__bs_cli_sm}" "${__bs_cli_sl}"
      done
      printf 'auto:      %s\n' "$(bs_shebang_line auto "${__bs_cli_sprog}" 2>/dev/null || echo '-')"
      ;;
    line)
      bs_shebang_line "${__bs_cli_smode}" "${__bs_cli_sprog}" || return 1
      ;;
    check)
      if [ "$(bs_arr_len bs_cli_spaths)" -eq 0 ]; then
        bs_arr_new bs_cli_spaths "${BS_ROOT}/bs" "${BS_ROOT}/install.sh" "${BS_ROOT}/boot.sh"
      fi
      eval "$(bs_arr_to_args bs_cli_spaths)"
      __bs_cli_sfiles=$(bs_cli_shebang_files "$@") || true
      if [ -n "${__bs_cli_sfiles}" ]; then
        while IFS= read -r __bs_cli_sf; do
          __bs_cli_sl="$(bs_shebang_read "${__bs_cli_sf}")" || continue
          if __bs_cli_why="$(bs_shebang_works "${__bs_cli_sl}")"; then
            printf 'ok      %s  %s\n' "${__bs_cli_sf}" "${__bs_cli_sl}"
          else
            printf 'BROKEN  %s  %s  (%s)\n' "${__bs_cli_sf}" "${__bs_cli_sl}" "${__bs_cli_why}"
            __bs_cli_src=1
          fi
        done <<SHEBANG_END
${__bs_cli_sfiles}
SHEBANG_END
      fi
      if [ "${__bs_cli_src}" -ne 0 ]; then
        printf 'fix: bs shebang set --prog <program> <file>  (Termux: install termux-exec, or use --mode env)\n' >&2
      fi
      return "${__bs_cli_src}"
      ;;
    set)
      [ "$(bs_arr_len bs_cli_spaths)" -gt 0 ] || bs_cli_die "shebang set: give at least one file or directory"
      __bs_cli_sn=0
      __bs_cli_snew="$(bs_shebang_line "${__bs_cli_smode}" "${__bs_cli_sprog}")" || return 1
      eval "$(bs_arr_to_args bs_cli_spaths)"
      __bs_cli_sfiles=$(bs_cli_shebang_files "$@") || true
      if [ -n "${__bs_cli_sfiles}" ]; then
        while IFS= read -r __bs_cli_sf; do
          __bs_cli_sl="$(bs_shebang_read "${__bs_cli_sf}")" || continue
          bs_shebang_is_for "${__bs_cli_sl}" "${__bs_cli_sprog}" || continue
          [ "${__bs_cli_sl}" = "${__bs_cli_snew}" ] && continue
          if [ "${__bs_cli_sdry}" -eq 1 ]; then
            printf 'would change  %s\n  %s\n  -> %s\n' "${__bs_cli_sf}" "${__bs_cli_sl}" "${__bs_cli_snew}"
          else
            bs_shebang_rewrite "${__bs_cli_sf}" "${__bs_cli_snew}" || { printf 'failed        %s\n' "${__bs_cli_sf}" >&2; __bs_cli_src=1; continue; }
            printf 'changed       %s\n  %s\n  -> %s\n' "${__bs_cli_sf}" "${__bs_cli_sl}" "${__bs_cli_snew}"
          fi
          __bs_cli_sn=$((__bs_cli_sn + 1))
        done <<SHEBANG_END
${__bs_cli_sfiles}
SHEBANG_END
      fi
      printf '%d file(s) %s\n' "${__bs_cli_sn}" "$(if [ "${__bs_cli_sdry}" -eq 1 ]; then echo 'would change'; else echo changed; fi)"
      return "${__bs_cli_src}"
      ;;
    *) bs_cli_die "shebang: unknown command: ${__bs_cli_ssub} (see: bs shebang --help)" ;;
  esac
}

bs_cli_call_usage() {
  printf 'Usage: bs call [--load MODULE]... FUNCTION [ARGS...]\n\n'
  printf 'Call a function of the BS kernel or of a library module from ANY shell\n'
  printf '(dash, ash, ksh, fish, nushell, ...): the function runs in the bash that bs\n'
  printf 'starts; its stdout and stderr are yours, its exit code becomes the exit code.\n\n'
  printf '  --load MODULE   load lib/... or core/... first (repeat for several), e.g. lib/io/streams\n'
  printf '  FUNCTION        a function that exists after loading: utils::human_size, log::info, ...\n\n'
  printf 'Examples:\n'
  printf '  bs call utils::human_size 1536000\n'
  printf '  bs call --load lib/system/info system::info::os\n'
  printf '  fish: set size (bs call utils::human_size 1536000)\n\n'
  printf 'Exit: 0..255 of the function; 2 bad usage or name; 127 no such function.\n'
  printf 'Вызывает функцию ядра или модуля BS из ЛЮБОЙ оболочки: функция исполняется в\n'
  printf 'bash, который запускает bs; её stdout/stderr и код выхода становятся вашими.\n'
}

# @private Мост для оболочек без bash-синтаксиса (fish, nu, dash, ash, ksh): вызов функции
# ядра как команды. Имя проверяется по шаблону и по тому, что функция существует, —
# произвольная команда через мост не исполняется.
# @private Bridge for shells without bash syntax: call a kernel function as a command.
# The name is checked against a pattern and for being a defined function — an
# arbitrary command does not run through the bridge.
bs_cli_call_cmd() {
  bs_arr_clear bs_cli_cmods
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) bs_cli_call_usage; return 0 ;;
      --load)    [ $# -ge 2 ] || { printf 'bs call: --load needs a module\n' >&2; return 2; }
                 bs_arr_push bs_cli_cmods "$2"; shift 2 ;;
      --load=*)  bs_arr_push bs_cli_cmods "${1#--load=}"; shift ;;
      --)        shift; break ;;
      -*)        printf 'bs call: unknown option: %s\n' "$1" >&2; return 2 ;;
      *)         break ;;
    esac
  done
  [ $# -ge 1 ] || { bs_cli_call_usage >&2; return 2; }
  __bs_cli_cfn=$1
  shift
  # аргументы функции — в массив: позиционные параметры понадобятся для обхода модулей
  # the function arguments go into an array: the positional parameters are needed to walk the modules
  bs_arr_new bs_cli_cargs "$@"
  eval "$(bs_arr_to_args bs_cli_cmods)"
  for __bs_cli_cm in "$@"; do
    case "${__bs_cli_cm}" in
      core/?*|lib/?*) ;;
      *) printf 'bs call: bad module path: %s\n' "${__bs_cli_cm}" >&2; return 2 ;;
    esac
    case "${__bs_cli_cm#*/}" in
      *[!A-Za-z0-9_/.-]*|*..*) printf 'bs call: bad module path: %s\n' "${__bs_cli_cm}" >&2; return 2 ;;
    esac
    bs_load "${__bs_cli_cm}" || return 1
  done
  case "${__bs_cli_cfn}" in
    ''|[!A-Za-z_]*|*[!A-Za-z0-9_:]*) printf 'bs call: bad function name: %s\n' "${__bs_cli_cfn}" >&2; return 2 ;;
  esac
  # только функция: `command -V` на английском (LC_ALL=C), в ответе должно быть слово function
  # only a function: `command -V` in English (LC_ALL=C), the answer must contain the word function
  __bs_cli_ct=$(LC_ALL=C command -V "${__bs_cli_cfn}" 2>&1) || __bs_cli_ct=''
  case "${__bs_cli_ct}" in
    *function*) ;;
    *)
      printf 'bs call: no such function: %s (load its module: --load lib/...)\n' "${__bs_cli_cfn}" >&2
      return 127 ;;
  esac
  eval "$(bs_arr_to_args bs_cli_cargs)"
  "${__bs_cli_cfn}" "$@"
}

# bs doctor: проверка целостности установки / the integrity check of the installation
bs_cli_doctor_cmd() {
  __bs_cli_dfail=0
  __bs_cli_dpass=0
  __bs_cli_dstart=$(bs_utils_now_ms)

  # Вектор возможностей / Capability vector
  if [ "${1:-}" = "--capabilities" ]; then
    if [ "${BS_KERNEL_MODE:-}" != full ]; then bs_cli_need_bash "doctor --capabilities"; fi
    bs_load "lib/platform/facts"
    platform::dump
    return 0
  fi
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    printf 'Usage: bs doctor [--capabilities]\n'
    printf '  --capabilities  print the platform capability vector\n'
    return 0
  fi

  bs_log_info "BS doctor report"
  bs_log_info "BS_ROOT: ${BS_ROOT}"

  # Единая таблица статусов: STATUS | ITEM | DETAIL
  # One aligned status table: STATUS | ITEM | DETAIL
  bs_log_info "$(printf '  %-8s | %-30s | %s' "STATUS" "ITEM" "DETAIL")"
  bs_log_info "$(printf '  %-8s | %-30s | %s' "--------" "------------------------------" "--------")"

  # The bash version gate already ran in the POSIX prologue (bs_shell_host_ok)
  # — no re-check here.
  # Гейт версии bash уже отработал в POSIX-прологе (bs_shell_host_ok) —
  # повторная проверка не нужна.

  # Required core files / Обязательные файлы ядра
  for __bs_cli_df2 in bootstrap/init.sh bootstrap/loader.sh bootstrap/base.sh bootstrap/cli.sh bootstrap/bs.sh bootstrap/shell.sh bootstrap/trampoline.sh core/prereq.sh core/lang.sh core/const.sh core/var.sh core/var-schema.sh core/store.sh core/regex.sh core/str.sh core/num.sh core/msg.sh core/logger.sh core/errorhandler.sh core/version.sh core/quiet.sh core/fmt.sh core/data.sh core/utils.sh core/config.sh core/deps.sh core/calc.sh core/args.sh core/args-completion.sh; do
    if [ -f "${BS_ROOT}/${__bs_cli_df2}" ]; then
      bs_log_success "$(printf '  %-8s | %-30s | %s' "OK" "${__bs_cli_df2}" "required core file")"
      __bs_cli_dpass=$((__bs_cli_dpass + 1))
    else
      bs_log_error "$(printf '  %-8s | %-30s | %s' "FAIL" "${__bs_cli_df2}" "required core file missing")"
      __bs_cli_dfail=1
    fi
  done

  # Мосты совместимости: init.sh грузит их в режиме full (bash) / Compatibility bridges: init.sh loads them in the full mode (bash)
  for __bs_cli_df2 in lib/compat/deps.sh lib/compat/lang.sh lib/compat/args.sh; do
    if [ -f "${BS_ROOT}/${__bs_cli_df2}" ]; then
      bs_log_success "$(printf '  %-8s | %-30s | %s' "OK" "${__bs_cli_df2}" "compat bridge (bash)")"
      __bs_cli_dpass=$((__bs_cli_dpass + 1))
    else
      bs_log_error "$(printf '  %-8s | %-30s | %s' "FAIL" "${__bs_cli_df2}" "compat bridge missing")"
      __bs_cli_dfail=1
    fi
  done

  # Required directories / Обязательные директории
  for __bs_cli_dd in core lib; do
    if [ -d "${BS_ROOT}/${__bs_cli_dd}" ]; then
      bs_log_success "$(printf '  %-8s | %-30s | %s' "OK" "dir ${__bs_cli_dd}" "required directory")"
      __bs_cli_dpass=$((__bs_cli_dpass + 1))
    else
      bs_log_error "$(printf '  %-8s | %-30s | %s' "FAIL" "dir ${__bs_cli_dd}" "required directory missing")"
      __bs_cli_dfail=1
    fi
  done

  # Оболочка: кто исполняет BS, чья оболочка у пользователя, tier, аннотации модулей
  # The shell: who runs BS, whose shell the user has, the tier, module annotations
  __bs_cli_dfam="$(bs_shell_family)"
  __bs_cli_duser="$(bs_shell_user)"
  __bs_cli_dtier="$(bs_shell_tier "${__bs_cli_duser}")"
  bs_log_success "$(printf '  %-8s | %-30s | %s' "OK" "shell (host)" "${__bs_cli_dfam} $(bs_shell_version_string)")"
  bs_log_success "$(printf '  %-8s | %-30s | %s' "OK" "shell (yours)" "${__bs_cli_duser}, tier ${__bs_cli_dtier}")"
  bs_log_info "$(printf '  %-8s | %-30s | %s' "" "" "$(bs_shell_tier_desc "${__bs_cli_dtier}")")"
  __bs_cli_dpass=$((__bs_cli_dpass + 2))
  __bs_cli_dap="$(grep -rlE '^# @shell posix' "${BS_ROOT}/bootstrap" "${BS_ROOT}/core" "${BS_ROOT}/lib" 2>/dev/null | wc -l || true)"
  __bs_cli_dab="$(grep -rlE '^# @shell bash4' "${BS_ROOT}/bootstrap" "${BS_ROOT}/core" "${BS_ROOT}/lib" 2>/dev/null | wc -l || true)"
  bs_log_success "$(printf '  %-8s | %-30s | %s' "OK" "module shell tiers" "posix=$((__bs_cli_dap)) bash4=$((__bs_cli_dab)) (без аннотации = bash4 / unmarked = bash4)")"
  __bs_cli_dpass=$((__bs_cli_dpass + 1))

  # Optional external tools / Опциональные внешние инструменты
  for __bs_cli_do in shellcheck jq curl wget kubectl; do
    if bs_utils_has "${__bs_cli_do}"; then
      bs_log_success "$(printf '  %-8s | %-30s | %s' "OK" "tool ${__bs_cli_do}" "found")"
      __bs_cli_dpass=$((__bs_cli_dpass + 1))
    else
      bs_log_warn "$(printf '  %-8s | %-30s | %s' "OPTIONAL" "tool ${__bs_cli_do}" "not found")"
    fi
  done

  # Optional dependency check for lib modules / Проверка опциональных зависимостей lib-модулей
  if command -v bs_deps_check_module >/dev/null 2>&1; then
    for __bs_cli_dm in lib/integration/result lib/integration/http lib/integration/llm lib/integration/k8s; do
      if [ -f "${BS_ROOT}/${__bs_cli_dm}.sh" ]; then
        if bs_utils_quiet bs_deps_check_module "${__bs_cli_dm}"; then
          bs_log_success "$(printf '  %-8s | %-30s | %s' "OK" "module ${__bs_cli_dm}" "dependencies satisfied")"
          __bs_cli_dpass=$((__bs_cli_dpass + 1))
        else
          __bs_cli_dmiss="$(bs_utils_attempt bs_deps_list_missing "${__bs_cli_dm}")"
          bs_log_warn "$(printf '  %-8s | %-30s | %s' "OPTIONAL" "module ${__bs_cli_dm}" "missing dependencies: ${__bs_cli_dmiss}")"
        fi
      fi
    done
  fi

  __bs_cli_dend=$(bs_utils_now_ms)
  if [ "${__bs_cli_dfail}" -eq 0 ]; then
    bs_log_success "doctor: все ${__bs_cli_dpass} проверок пройдено / all ${__bs_cli_dpass} checks passed ($(bs_num_sub "${__bs_cli_dend}" "${__bs_cli_dstart}") ms)"
  else
    bs_log_error "doctor: ${__bs_cli_dpass} пройдено, ${__bs_cli_dfail} ПРОВАЛЕНО / ${__bs_cli_dpass} passed, ${__bs_cli_dfail} FAILED ($(bs_num_sub "${__bs_cli_dend}" "${__bs_cli_dstart}") ms)"
  fi

  return "${__bs_cli_dfail}"
}


# ==========================================================================
# Общие помощники update / uninstall / where
# Shared helpers of update / uninstall / where
# ==========================================================================

# Системный каталог установки; префикс переопределяется BS_SYSTEM_PREFIX
# (по умолчанию /usr/local) — тесты моделируют system-установку без root.
# System install directory; the prefix is overridden by BS_SYSTEM_PREFIX
# (default /usr/local) so tests can model a system install without root.
bs_cli_update_system_lib() {
  printf '%s/lib/bs\n' "${BS_SYSTEM_PREFIX:-/usr/local}"
}

# @private Каталог установки из обёртки `bs` (install.sh пишет в неё
# export BS_ROOT="..."). Пустой вывод, если файл — не обёртка.
# @private Install directory named by a `bs` wrapper (install.sh writes
# export BS_ROOT="..." into it). Empty output if the file is not a wrapper.
# @param $1 Path to a `bs` executable / Путь к исполняемому `bs`
bs_cli_update_wrapper_root() {
  __bs_cli_wn=0
  while IFS= read -r __bs_cli_wl; do
    if [ "${__bs_cli_wn}" -ge 5 ]; then break; fi
    __bs_cli_wn=$((__bs_cli_wn + 1))
    case "${__bs_cli_wl}" in
      'export BS_ROOT="'*'"')
        __bs_cli_wm=${__bs_cli_wl#'export BS_ROOT="'}
        __bs_cli_wm=${__bs_cli_wm%'"'}
        case "${__bs_cli_wm}" in
          ''|*'"'*|*\$*) ;;
          *)
            printf '%s\n' "${__bs_cli_wm}"
            return 0 ;;
        esac ;;
    esac
  done < "$1" 2>/dev/null
  return 0
}

# @private Вид запущенной копии: mode из манифеста, source checkout, no manifest.
# @private Kind of the running copy: manifest mode, source checkout, no manifest.
bs_cli_bs_running_kind() {
  __bs_cli_rkm="$(bs_cli_install_info_get "${BS_ROOT}" mode)"
  if [ -n "${__bs_cli_rkm}" ]; then
    printf '%s' "${__bs_cli_rkm}"
  elif [ -e "${BS_ROOT}/.git" ] || [ -d "${BS_ROOT}/tests" ]; then
    printf 'source checkout'
  elif [ -e "${BS_ROOT}/.install" ]; then
    printf 'manifest unreadable'
  else
    printf 'no manifest'
  fi
}

# @private Компактная сводка запущенной копии (те же данные, что bs version
# --full): версия | root | вид | коммит | последнее обновление. Только чтение
# манифеста и git, чужой код не запускается.
# @private Compact summary of the running copy (same data as bs version
# --full). Reads the manifest and git only; no foreign code is run.
bs_cli_bs_running_info() {
  __bs_cli_rik="$(bs_cli_bs_running_kind)"
  __bs_cli_rio="bs $(bs_version_get) | ${BS_ROOT} | ${__bs_cli_rik}"
  if [ "${__bs_cli_rik}" = "source checkout" ]; then
    if [ -e "${BS_ROOT}/.git" ] && bs_utils_has git; then
      __bs_cli_ric="$(git -C "${BS_ROOT}" rev-parse --short=7 HEAD 2>/dev/null)" || __bs_cli_ric=""
      __bs_cli_rid=""
      if [ -n "$(git -C "${BS_ROOT}" status --porcelain 2>/dev/null)" ]; then __bs_cli_rid=", with uncommitted changes"; fi
      if [ -n "${__bs_cli_ric}" ]; then __bs_cli_rio="${__bs_cli_rio} | commit ${__bs_cli_ric}${__bs_cli_rid}"; fi
    fi
  elif [ -f "${BS_ROOT}/.install" ]; then
    __bs_cli_ris="$(bs_cli_install_info_get "${BS_ROOT}" source_commit)"
    __bs_cli_rio="${__bs_cli_rio} | installed $(bs_cli_install_info_get "${BS_ROOT}" installed_at) by $(bs_cli_install_info_get "${BS_ROOT}" installed_by)"
    __bs_cli_rio="${__bs_cli_rio} | source $(bs_cli_install_info_get "${BS_ROOT}" source) @ $(bs_cli_short_sha "${__bs_cli_ris}")"
    __bs_cli_riu="$(bs_cli_install_info_get "${BS_ROOT}" updated_at)"
    if [ -n "${__bs_cli_riu}" ]; then
      __bs_cli_rio="${__bs_cli_rio} | updated ${__bs_cli_riu} from $(bs_cli_install_info_get "${BS_ROOT}" updated_from) @ $(bs_cli_short_sha "$(bs_cli_install_info_get "${BS_ROOT}" updated_commit)")"
    fi
  fi
  printf '%s' "${__bs_cli_rio}"
}

# @private Подготовить сводки (один раз за запуск) / prepare summaries once
bs_cli_update_ctx() {
  if [ -n "${UPDATE_RUN_INFO:-}" ]; then return 0; fi
  UPDATE_RUN_INFO="$(bs_cli_bs_running_info)"
  UPDATE_RUN_BLOCK="$(BS_CLI_INFO_NO_COLOR=1 bs_cli_bs_running_block)"
  UPDATE_RUN_SHORT="Запущен / Running: ${UPDATE_RUN_INFO}"
  return 0
}

# ERROR/WARN с короткой сводкой запущенной копии в конце.
# ERROR/WARN with the short running-copy summary appended.
bs_cli_update_die() {
  bs_cli_update_ctx
  bs_log_error "$1 (${UPDATE_RUN_SHORT})"
  bs_exit "${2:-1}"
}

bs_cli_update_warn() {
  bs_cli_update_ctx
  bs_log_warn "$1 (${UPDATE_RUN_SHORT})"
  return 0
}

# Значение флага: непустое и не похожее на другой флаг (--ref --github).
# A flag value: non-empty and not another flag (--ref --github).
bs_cli_update_flag_value() {
  __bs_cli_fv_flag=$1
  __bs_cli_fv_what=$2
  shift 2
  __bs_cli_fv_bad=0
  if [ $# -lt 1 ] || [ -z "$1" ]; then
    __bs_cli_fv_bad=1
  else
    case "$1" in -*) __bs_cli_fv_bad=1 ;; esac
  fi
  if [ "${__bs_cli_fv_bad}" = 1 ]; then
    bs_cli_update_die "update: ${__bs_cli_fv_flag} требует значение / requires ${__bs_cli_fv_what}"
  fi
}

bs_cli_update_realpath() {
  readlink -f -- "$1" 2>/dev/null || printf '%s\n' "$1"
}

# @private Каталог похож на установку BS: bs + bootstrap/init.sh либо .install.
# @private The directory looks like a BS install: bs + bootstrap/init.sh or .install.
bs_cli_update_is_install() {
  [ -d "$1" ] || return 1
  if [ -f "$1/bs" ] && [ -f "$1/bootstrap/init.sh" ]; then return 0; fi
  [ -f "$1/.install" ]
}

# @private Исходный репозиторий (.git или tests/): не установка / a source checkout
bs_cli_update_is_checkout() {
  [ -e "$1/.git" ] || [ -d "$1/tests" ]
}

# @private Чего не хватает каталогу-источнику (по строке на пункт).
# @private What a source directory lacks (one item per line).
bs_cli_update_source_missing() {
  __bs_cli_sm_d=$1
  if [ ! -d "${__bs_cli_sm_d}" ]; then
    printf '%s\n' "каталог не найден / directory not found"
    return 0
  fi
  if [ ! -f "${__bs_cli_sm_d}/bs" ]; then printf '%s\n' "bs"; fi
  if [ ! -f "${__bs_cli_sm_d}/bootstrap/init.sh" ]; then printf '%s\n' "bootstrap/init.sh"; fi
  if [ ! -f "${__bs_cli_sm_d}/bootstrap/loader.sh" ]; then printf '%s\n' "bootstrap/loader.sh"; fi
  for __bs_cli_sm_f in bootstrap/shell.sh bootstrap/trampoline.sh bootstrap/shebang.sh bootstrap/bs.sh core/prereq.sh; do
    if [ ! -f "${__bs_cli_sm_d}/${__bs_cli_sm_f}" ]; then printf '%s\n' "${__bs_cli_sm_f}"; fi
  done
  if [ ! -d "${__bs_cli_sm_d}/core" ]; then printf '%s\n' "core/"; fi
  if [ ! -d "${__bs_cli_sm_d}/lib" ]; then printf '%s\n' "lib/"; fi
  if [ ! -f "${__bs_cli_sm_d}/core/version.sh" ]; then
    printf '%s\n' "core/version.sh"
  elif [ -z "$(bs_version_of "${__bs_cli_sm_d}")" ]; then
    printf '%s\n' "core/version.sh: версия не читается / no readable version"
  fi
  return 0
}

# @private Обёртка установки: из манифеста, иначе из пути .../lib/bs.
# @private The wrapper of an install: from the manifest, else from .../lib/bs.
bs_cli_update_install_wrapper() {
  __bs_cli_iw="$(bs_cli_install_info_get "$1" bin)"
  if [ -z "${__bs_cli_iw}" ]; then
    case "$1" in
      */lib/bs) __bs_cli_iw="${1%/lib/bs}/bin/bs" ;;
    esac
  fi
  printf '%s' "${__bs_cli_iw}"
}

# @private Домашний каталог пользователя SUDO_USER (пусто, если неизвестен).
# @private Home directory of SUDO_USER (empty if unknown).
bs_cli_update_sudo_home() {
  if [ -z "${SUDO_USER:-}" ]; then return 0; fi
  bs_utils_has getent || return 0
  getent passwd "${SUDO_USER}" 2>/dev/null | cut -d: -f6 || true
}

# @private Пояснение, почему цель не найдена, и что делать (строки для рамки).
# @param $1 Target / цель; $2 kind: local|system|lib|auto
# @private Why a target is missing and what to do (box lines).
bs_cli_update_missing_lines() {
  __bs_cli_ml_t=$1
  __bs_cli_ml_kind=$2
  __bs_cli_ml_verb=${3:-update}
  __bs_cli_ml_sys="$(bs_cli_update_system_lib)"
  __bs_cli_ml_loc="${HOME}/.local/lib/bs"
  case "${__bs_cli_ml_kind}" in
    local)
      printf '%s\n' "• ${__bs_cli_ml_t} — локальной установки нет / no local install"
      if bs_cli_update_is_install "${__bs_cli_ml_sys}" && ! bs_cli_update_is_checkout "${__bs_cli_ml_sys}"; then
        __bs_cli_ml_ver="$(bs_version_of "${__bs_cli_ml_sys}")"
        printf '%s\n' "  но найдена системная / but a system install exists: ${__bs_cli_ml_sys} (версия/version ${__bs_cli_ml_ver:-?})" \
          "  → bs ${__bs_cli_ml_verb} --system   или / or   bs ${__bs_cli_ml_verb}"
      else
        printf '%s\n' "  BS не установлена / BS is not installed → ./install.sh --local"
      fi
      if [ "$(bs_cli_euid)" -eq 0 ] || [ -n "${SUDO_USER:-}" ]; then
        printf '%s\n' "  вы root/sudo (HOME=${HOME}): ~ — это домашний каталог root / you run as root: ~ is root's home"
        __bs_cli_ml_sh="$(bs_cli_update_sudo_home)"
        if [ -n "${__bs_cli_ml_sh}" ] && [ "${__bs_cli_ml_sh}" != "${HOME}" ]; then
          printf '%s\n' "  установка пользователя ${SUDO_USER} / its local install: ${__bs_cli_ml_sh}/.local/lib/bs" \
            "  → bs ${__bs_cli_ml_verb} --lib ${__bs_cli_ml_sh}/.local/lib/bs"
        fi
      fi ;;
    system)
      printf '%s\n' "• ${__bs_cli_ml_t} — системной установки нет / no system install"
      if bs_cli_update_is_install "${__bs_cli_ml_loc}" && ! bs_cli_update_is_checkout "${__bs_cli_ml_loc}"; then
        __bs_cli_ml_ver="$(bs_version_of "${__bs_cli_ml_loc}")"
        printf '%s\n' "  но найдена локальная / but a local install exists: ${__bs_cli_ml_loc} (версия/version ${__bs_cli_ml_ver:-?})" \
          "  → bs ${__bs_cli_ml_verb} --local   или / or   bs ${__bs_cli_ml_verb}"
      else
        printf '%s\n' "  BS не установлена / BS is not installed → ./install.sh --local  (sudo ./install.sh)"
      fi ;;
    *)
      printf '%s\n' "• ${__bs_cli_ml_t} — каталог не найден / directory not found" \
        "  проверьте путь (обычно …/lib/bs) / check the path (usually …/lib/bs)" \
        "  установить / install: PREFIX=<dir> ./install.sh   или / or   ./install.sh --local" ;;
  esac
}

# @private Добавить строки текста в массив (построчно) / Append the lines of a text to an array
# @param $1 array name / имя массива
# @param $2 text / текст
bs_cli_push_lines() {
  if [ -z "${2-}" ]; then return 0; fi
  __bs_cli_pl_name=$1
  bs_arr_from_lines bs_cli_pushtmp "$2"
  eval "$(bs_arr_to_args bs_cli_pushtmp)"
  bs_arr_push "${__bs_cli_pl_name}" "$@"
}

# @private Рамка-уведомление БЕЗ лог-префиксов — таймстампы ломают рамку
# (bs_log_header страдает этим при включённых таймстампах).
# @private Boxed notice printed WITHOUT log prefixes — timestamps would
# break the frame (bs_log_header suffers from this in timestamped output).
# @param $1 Title / Заголовок
# @param $@ Body lines, hard-wrapped at inner width / Строки тела с переносом
bs_cli_update_box() {
  __bs_cli_ub_title=$1
  shift
  __bs_cli_ub_inner=58
  # Первая строка тела — какая копия bs печатает это уведомление.
  # First body line: which bs copy prints this notice.
  bs_cli_update_ctx
  bs_arr_from_lines bs_cli_ub_rows "${UPDATE_RUN_BLOCK}"
  bs_arr_push bs_cli_ub_rows ""
  bs_arr_push bs_cli_ub_rows "$@"
  bs_arr_clear bs_cli_ub_body
  eval "$(bs_arr_to_args bs_cli_ub_rows)"
  for __bs_cli_ub_text in "$@"; do
    while [ "$(bs_str_width "${__bs_cli_ub_text}")" -gt "${__bs_cli_ub_inner}" ]; do
      __bs_cli_ub_chunk=$(bs_str_head "${__bs_cli_ub_text}" "${__bs_cli_ub_inner}")
      bs_arr_push bs_cli_ub_body "${__bs_cli_ub_chunk}"
      __bs_cli_ub_text=${__bs_cli_ub_text#"${__bs_cli_ub_chunk}"}
    done
    bs_arr_push bs_cli_ub_body "${__bs_cli_ub_text}"
  done

  __bs_cli_ub_cb=''
  __bs_cli_ub_cr=''
  if bs_log_is_color_enabled 1; then
    __bs_cli_ub_cb=$(printf '\033[34m')
    __bs_cli_ub_cr=$(printf '\033[0m')
  fi
  __bs_cli_ub_rule=$(bs_str_repeat '─' "${__bs_cli_ub_inner}")
  __bs_cli_ub_tw=$(bs_str_width "${__bs_cli_ub_title}")
  __bs_cli_ub_pad=$((__bs_cli_ub_inner - __bs_cli_ub_tw))
  __bs_cli_ub_pad=$((__bs_cli_ub_pad / 2))
  # слишком длинный заголовок: прежний printf '%*s' с отрицательной шириной давал |ширину| пробелов
  # a title wider than the frame: the old printf '%*s' with a negative width gave |width| spaces
  if [ "${__bs_cli_ub_pad}" -lt 0 ]; then __bs_cli_ub_pad=$((0 - __bs_cli_ub_pad)); fi
  __bs_cli_ub_row="$(bs_str_repeat ' ' "${__bs_cli_ub_pad}")${__bs_cli_ub_title}"

  # Паддинг по символам: printf '%-*s' считает БАЙТЫ и ломает кириллицу.
  # Pad by CHARACTERS: printf '%-*s' measures BYTES and breaks Cyrillic.
  __bs_cli_ub_w=$(bs_str_width "${__bs_cli_ub_row}")
  __bs_cli_ub_n=$((__bs_cli_ub_inner - __bs_cli_ub_w))
  if [ "${__bs_cli_ub_n}" -gt 0 ]; then
    __bs_cli_ub_row="${__bs_cli_ub_row}$(bs_str_repeat ' ' "${__bs_cli_ub_n}")"
  fi
  printf '%s╭%s╮%s\n' "${__bs_cli_ub_cb}" "${__bs_cli_ub_rule}" "${__bs_cli_ub_cr}"
  printf '%s│%s│%s\n' "${__bs_cli_ub_cb}" "${__bs_cli_ub_row}" "${__bs_cli_ub_cr}"
  printf '%s├%s┤%s\n' "${__bs_cli_ub_cb}" "${__bs_cli_ub_rule}" "${__bs_cli_ub_cr}"
  eval "$(bs_arr_to_args bs_cli_ub_body)"
  for __bs_cli_ub_line in "$@"; do
    __bs_cli_ub_w=$(bs_str_width "${__bs_cli_ub_line}")
    __bs_cli_ub_n=$((__bs_cli_ub_inner - __bs_cli_ub_w))
    if [ "${__bs_cli_ub_n}" -gt 0 ]; then
      __bs_cli_ub_line="${__bs_cli_ub_line}$(bs_str_repeat ' ' "${__bs_cli_ub_n}")"
    fi
    printf '%s│%s│%s\n' "${__bs_cli_ub_cb}" "${__bs_cli_ub_line}" "${__bs_cli_ub_cr}"
  done
  printf '%s╰%s╯%s\n' "${__bs_cli_ub_cb}" "${__bs_cli_ub_rule}" "${__bs_cli_ub_cr}"
}

# @private Эффективный uid: EUID там, где он есть (bash, zsh, ksh), иначе id -u.
# @private The effective uid: EUID where the shell has it (bash, zsh, ksh), else id -u.
bs_cli_euid() {
  if [ -n "${EUID:-}" ]; then
    printf '%s\n' "${EUID}"
  else
    id -u
  fi
}

# bs uninstall: удалить установленные копии BS (каталог lib + обёртка)
# bs uninstall: remove installed BS copies (lib tree + wrapper)
bs_cli_uninstall_cmd() {
  bs_arr_clear bs_cli_un_targets
  bs_arr_clear bs_cli_un_kinds
  bs_arr_clear bs_cli_un_skipped
  __bs_cli_un_explicit=0
  __bs_cli_un_verbose=0
  __bs_cli_un_banner=1
  for __bs_cli_un_a in "$@"; do
    case "${__bs_cli_un_a}" in
      -h|--help) __bs_cli_un_banner=0 ;;
    esac
  done
  bs_cli_update_ctx
  if [ "${__bs_cli_un_banner}" -ne 0 ]; then printf '%s\n' "${UPDATE_RUN_BLOCK}"; fi

  while [ $# -gt 0 ]; do
    case "${1:-}" in
      --local)
        __bs_cli_un_explicit=1
        bs_arr_push bs_cli_un_targets "${HOME:-}/.local/lib/bs"
        bs_arr_push bs_cli_un_kinds local
        shift ;;
      --system)
        __bs_cli_un_explicit=1
        bs_arr_push bs_cli_un_targets "$(bs_cli_update_system_lib)"
        bs_arr_push bs_cli_un_kinds system
        shift ;;
      --lib)
        shift
        bs_cli_update_flag_value "--lib" "a target directory" "$@"
        __bs_cli_un_explicit=1
        bs_arr_push bs_cli_un_targets "$1"
        bs_arr_push bs_cli_un_kinds lib
        shift ;;
      -v|--verbose)
        __bs_cli_un_verbose=1
        shift ;;
      -h|--help)
        printf 'Использование / Usage: bs uninstall [--local] [--system] [--lib DIR] [-v]\n\n'
        printf 'Удаляет установленные копии BS (каталог lib + обёртка).\n'
        printf 'Removes installed BS copies (lib tree + wrapper).\n'
        printf '  --local   ~/.local/lib/bs and its wrapper in ~/.local/bin\n'
        # shellcheck disable=SC2016
        printf '  --system  $BS_SYSTEM_PREFIX/lib/bs (default /usr/local) and its wrapper (needs root)\n'
        printf '  --lib DIR a custom install directory\n'
        printf 'Without flags: every detected install (local + system).\n'
        printf 'Safety / Безопасность: only directories that are unmistakably BS installs\n'
        printf '(bs + bootstrap/init.sh) are removed; a source checkout (.git/tests) is\n'
        printf 'refused; a wrapper is deleted only when it points back at the target.\n'
        printf 'Every notice shows which bs copy printed it. Removing the copy bs runs\n'
        printf 'from is allowed and announced. Exit code 1 if nothing could be removed.\n'
        printf 'PATH lines in rc files are cleaned by: ./install.sh --local uninstall\n'
        return 0 ;;
      *)
        bs_cli_update_die "uninstall: неизвестный аргумент / unknown argument: $1 (bs uninstall --help)" ;;
    esac
  done

  # Детект установок / Detect installs
  if [ "${__bs_cli_un_explicit}" -eq 0 ]; then
    if [ -d "${HOME:-}/.local/lib/bs" ]; then
      bs_arr_push bs_cli_un_targets "${HOME:-}/.local/lib/bs"
      bs_arr_push bs_cli_un_kinds auto
    fi
    if [ -d "$(bs_cli_update_system_lib)" ]; then
      bs_arr_push bs_cli_un_targets "$(bs_cli_update_system_lib)"
      bs_arr_push bs_cli_un_kinds auto
    fi
  fi

  __bs_cli_un_count=$(bs_arr_len bs_cli_un_targets)
  if [ "${__bs_cli_un_count}" -eq 0 ]; then
    bs_cli_update_box "УДАЛЯТЬ НЕЧЕГО / NOTHING TO UNINSTALL" \
      "Установок BS не найдено / no BS installs found." \
      "Укажите каталог / point to one: bs uninstall --lib DIR"
    exit 1
  fi

  __bs_cli_un_ok=0
  __bs_cli_un_seen=""
  __bs_cli_un_idx=0
  while [ "${__bs_cli_un_idx}" -lt "${__bs_cli_un_count}" ]; do
    __bs_cli_un_raw=''
    __bs_cli_un_kind=''
    bs_arr_get bs_cli_un_targets "${__bs_cli_un_idx}" __bs_cli_un_raw
    bs_arr_get bs_cli_un_kinds "${__bs_cli_un_idx}" __bs_cli_un_kind
    __bs_cli_un_idx=$((__bs_cli_un_idx + 1))
    __bs_cli_un_tin=${__bs_cli_un_raw%/}
    if [ ! -d "${__bs_cli_un_tin}" ]; then
      bs_cli_push_lines bs_cli_un_skipped "$(bs_cli_update_missing_lines "${__bs_cli_un_tin}" "${__bs_cli_un_kind}" uninstall)"
      continue
    fi
    __bs_cli_un_target=$(bs_cli_update_realpath "${__bs_cli_un_tin}")
    case "${__bs_cli_un_seen}" in
      *"|${__bs_cli_un_target}|"*) continue ;;
    esac
    __bs_cli_un_seen="${__bs_cli_un_seen} |${__bs_cli_un_target}|"
    # Безопасность: удаляем только каталоги, которые однозначно являются BS
    # Safety: only remove directories that are unmistakably BS installs
    if [ ! -f "${__bs_cli_un_target}/bs" ] || [ ! -f "${__bs_cli_un_target}/bootstrap/init.sh" ]; then
      bs_arr_push bs_cli_un_skipped "• ${__bs_cli_un_target} — не установка BS (нет bs + bootstrap/init.sh); не тронут / not a BS install; left untouched"
      continue
    fi
    # Никогда не удалять исходный чекаут: у него есть .git или tests/.
    # Never remove the source checkout: it has .git or tests/.
    if [ -e "${__bs_cli_un_target}/.git" ] || [ -d "${__bs_cli_un_target}/tests" ]; then
      bs_arr_push bs_cli_un_skipped "• ${__bs_cli_un_target} — исходный репозиторий (.git/tests), не установка; не тронут / source checkout; refusing to remove"
      continue
    fi
    # Обёртка — из манифеста, иначе выводится из пути .../lib/bs.
    # The wrapper comes from the manifest, else from a .../lib/bs path.
    __bs_cli_un_wrapper=$(bs_cli_update_install_wrapper "${__bs_cli_un_target}")
    # lib задан симлинком и манифест без bin=: путь обёртки выводится из него
    # lib given as a symlink and a manifest without bin=: derive it from the link
    if [ -z "${__bs_cli_un_wrapper}" ]; then
      __bs_cli_un_wrapper=$(bs_cli_update_install_wrapper "${__bs_cli_un_tin}")
    fi
    __bs_cli_un_bin=${__bs_cli_un_wrapper%/*}
    __bs_cli_un_mine=0
    if [ -n "${__bs_cli_un_wrapper}" ] && [ -f "${__bs_cli_un_wrapper}" ]; then
      if grep -Fq "BS_ROOT=\"${__bs_cli_un_target}\"" "${__bs_cli_un_wrapper}" 2>/dev/null; then
        __bs_cli_un_mine=1
      else
        # Обёртка может называть lib через симлинк (~/.local/lib/bs -> ...):
        # сравниваем и заданный путь, и реальный.
        # The wrapper may name the lib through a symlink: compare both the
        # given path and the real one.
        __bs_cli_un_wroot=$(bs_cli_update_wrapper_root "${__bs_cli_un_wrapper}")
        if [ -n "${__bs_cli_un_wroot}" ]; then
          if [ "${__bs_cli_un_wroot%/}" = "${__bs_cli_un_tin}" ] \
             || [ "$(bs_cli_update_realpath "${__bs_cli_un_wroot}")" = "${__bs_cli_un_target}" ]; then
            __bs_cli_un_mine=1
          fi
        fi
      fi
    fi
    __bs_cli_un_denied=0
    if [ ! -w "${__bs_cli_un_target%/*}" ]; then __bs_cli_un_denied=1; fi
    if [ "${__bs_cli_un_mine}" -eq 1 ] && [ ! -w "${__bs_cli_un_bin}" ]; then __bs_cli_un_denied=1; fi
    if [ "${__bs_cli_un_denied}" -eq 1 ]; then
      bs_arr_push bs_cli_un_skipped "• ${__bs_cli_un_target} — нет прав на удаление / no permission to remove (try: sudo bs uninstall --system)"
      continue
    fi
    bs_log_info "uninstalling ${__bs_cli_un_target}"
    if [ "${__bs_cli_un_target}" = "$(bs_cli_update_realpath "${BS_ROOT}")" ]; then
      bs_log_info "uninstall: удаляется копия, из которой запущен bs — это нормально / removing the copy bs runs from — this is fine"
    fi
    __bs_cli_un_removed=0
    if [ "${__bs_cli_un_mine}" -eq 0 ] && [ -n "${__bs_cli_un_wrapper}" ] && [ -f "${__bs_cli_un_wrapper}" ]; then
      bs_cli_update_warn "uninstall: wrapper not matching this install, left in place: ${__bs_cli_un_wrapper} / обёртка не от этой установки, оставлена"
    fi

    # rm -rf на защищённый target безопасен: выше проверено, что это настоящая
    # BS-установка, не чекаут и записываемый каталог.
    # Обёртку удаляем ПОСЛЕ каталога: при сбое rm остаётся рабочая команда bs,
    # и удаление можно повторить.
    # rm -rf on the guarded target is safe: it is a real BS install, not a
    # checkout, and writable. The wrapper goes AFTER the directory: if rm
    # fails, a working bs command is left and the removal can be retried.
    if ! rm -rf -- "${__bs_cli_un_target}"; then
      bs_arr_push bs_cli_un_skipped "• ${__bs_cli_un_target} — удаление не удалось (часть файлов могла быть удалена; обёртка оставлена; остаток удалите вручную) / removal failed (some files may be gone; the wrapper is kept; remove the rest by hand)"
      continue
    fi
    if [ "${__bs_cli_un_verbose}" -eq 1 ]; then
      bs_log_info "  removed: ${__bs_cli_un_target}"
    fi
    # Симлинк на каталог установки больше никуда не ведёт: убираем и его
    # The symlink to the install directory points nowhere now: drop it too
    if [ -L "${__bs_cli_un_tin}" ]; then
      rm -f -- "${__bs_cli_un_tin}" || true
    fi
    if [ "${__bs_cli_un_mine}" -eq 1 ]; then
      rm -f -- "${__bs_cli_un_wrapper}"
      __bs_cli_un_removed=1
      if [ "${__bs_cli_un_verbose}" -eq 1 ]; then
        bs_log_info "  removed: ${__bs_cli_un_wrapper}"
      fi
    fi
    # rmdir удаляет только пустой bin_dir; чужие файлы не трогаются.
    # rmdir removes only an empty bin_dir; foreign files are never touched.
    if [ "${__bs_cli_un_removed}" -ne 0 ]; then
      rmdir -- "${__bs_cli_un_bin}" 2>/dev/null || true
    fi
    __bs_cli_un_ok=1
  done

  if [ "${__bs_cli_un_ok}" -eq 0 ]; then
    eval "$(bs_arr_to_args bs_cli_un_skipped)"
    bs_cli_update_box "НИЧЕГО НЕ УДАЛЕНО / NOTHING REMOVED" "$@"
    exit 1
  fi
  __bs_cli_un_nskip=$(bs_arr_len bs_cli_un_skipped)
  if [ "${__bs_cli_un_nskip}" -gt 0 ]; then
    eval "$(bs_arr_to_args bs_cli_un_skipped)"
    bs_cli_update_box "ЧАСТЬ ПРОПУЩЕНА / SOME TARGETS SKIPPED" "$@"
  fi
  bs_log_success "uninstall done"
  if [ "${__bs_cli_un_nskip}" -ne 0 ]; then exit 1; fi
  return 0
}


# ==========================================================================
# bs where: все следы BS на машине / every trace of BS on this machine
# ==========================================================================

# Строка отчёта: подпись выравнивается по СИМВОЛАМ (printf %-Ns считает байты и
# ломает колонки с кириллицей).
# A report row: the label is padded by CHARACTERS (printf %-Ns counts bytes and
# breaks columns with Cyrillic).
# @param $1 Label / подпись; $2 Value / значение
bs_cli_where_row() {
  __bs_cli_wr_w=$(bs_str_width "$1")
  if [ "${__bs_cli_wr_w}" -lt 15 ]; then
    __bs_cli_wr_n=$((15 - __bs_cli_wr_w))
  else
    __bs_cli_wr_n=1
  fi
  printf '    %s%s%s\n' "$1" "$(bs_str_repeat ' ' "${__bs_cli_wr_n}")" "$2"
}

# @private Состояние каталога как BS: missing | file | foreign | checkout |
# install | nomanifest | badmanifest.
# @private State of a directory as BS: missing | file | foreign | checkout |
# install | nomanifest | badmanifest.
# @param $1 Directory / Каталог
bs_cli_where_classify() {
  if [ ! -e "$1" ]; then printf 'missing'; return 0; fi
  if [ ! -d "$1" ]; then printf 'file'; return 0; fi
  if [ ! -f "$1/bs" ] || [ ! -f "$1/bootstrap/init.sh" ]; then
    printf 'foreign'; return 0
  fi
  if [ -e "$1/.git" ] || [ -d "$1/tests" ]; then printf 'checkout'; return 0; fi
  if [ ! -e "$1/.install" ]; then printf 'nomanifest'; return 0; fi
  if bs_cli_update_manifest_valid "$1/.install"; then
    printf 'install'
  else
    printf 'badmanifest'
  fi
}

# @private Вид установки по пути, если манифеста нет / install kind by path
bs_cli_where_kind_by_path() {
  if [ "$1" = "${HOME}/.local/lib/bs" ]; then
    printf 'local'
  elif [ "$1" = "$(bs_cli_update_system_lib)" ]; then
    printf 'system'
  else
    printf 'custom'
  fi
}

# @private Размер каталога в человекочитаемом виде (с ограничением по времени)
# @private Directory size, human readable (with a time limit)
bs_cli_where_size() {
  __bs_cli_ws_kb=$(timeout 5 du -sk -- "$1" 2>/dev/null | cut -f1 || true)
  case "${__bs_cli_ws_kb}" in
    ''|*[!0-9]*) printf '?' ;;
    *)
      if [ "${__bs_cli_ws_kb}" -ge 1024 ]; then
        printf '%d.%d MB' "$((__bs_cli_ws_kb / 1024))" "$((__bs_cli_ws_kb % 1024 * 10 / 1024))"
      else
        printf '%d KB' "${__bs_cli_ws_kb}"
      fi ;;
  esac
}

# shellcheck disable=SC2016  # обратные кавычки в тексте справки / backticks in the help text
bs_cli_where_help() {
  printf 'Usage: bs where [--deep]\n\n'
  printf 'Show every trace of BS on this machine, read-only: the running copy,\n'
  printf 'every `bs` found in PATH (wrappers and launchers), installs (local,\n'
  printf 'system, custom) with version/manifest/owner/leftovers, source checkouts,\n'
  printf 'lines in shell rc files, data and cache directories, environment\n'
  printf 'variables, and a summary with the commands that fix what looks wrong.\n'
  printf 'Nothing is changed and no found copy of bs is run.\n\n'
  printf '  --deep   also search for BS copies under ~, /opt, /usr/local, /srv\n'
  printf '           (depth-limited, 30 s at most)\n'
  printf 'Показывает все следы BS на машине: запущенную копию, все `bs` в PATH,\n'
  printf 'установки (local/system/custom), репозитории, строки в rc-файлах,\n'
  printf 'каталоги данных и кэша, переменные окружения и итог с командами.\n'
  printf 'Ничего не меняет и найденные копии bs не запускает.\n'
}

# Замечание / подсказка без повторов
# A problem / hint, without duplicates
bs_cli_where_problem() {
  if bs_arr_contains bs_cli_wh_problems "$1"; then return 0; fi
  bs_arr_push bs_cli_wh_problems "$1"
}

bs_cli_where_hint() {
  if bs_arr_contains bs_cli_wh_hints "$1"; then return 0; fi
  bs_arr_push bs_cli_wh_hints "$1"
}

# Кандидат в каталог BS (без повторов, по реальному пути)
# A candidate BS directory (deduplicated by real path)
bs_cli_where_add() {
  __bs_cli_wa_p=${1%/}
  if [ -z "${__bs_cli_wa_p}" ]; then return 0; fi
  __bs_cli_wa_r=$(readlink -f -- "${__bs_cli_wa_p}" 2>/dev/null || printf '%s' "${__bs_cli_wa_p}")
  if bs_arr_contains bs_cli_wh_cands "${__bs_cli_wa_r}"; then return 0; fi
  bs_arr_push bs_cli_wh_cands "${__bs_cli_wa_r}"
}

# @private Остатки прерванных обновлений и установок рядом с установкой (по строке).
# @private Leftovers of interrupted updates and installs next to an install (one per line).
# @param $1 Install directory / Каталог установки
bs_cli_where_leftovers() {
  for __bs_cli_wl_pat in '.update.*' '.update-old.*' '.update-lock' '.install.bad'; do
    find "$1" -maxdepth 1 -name "${__bs_cli_wl_pat}" 2>/dev/null | sort
  done
  find "$(dirname -- "$1")" -maxdepth 1 -name '.bs.install.*' 2>/dev/null | sort
}

# bs where: все следы BS на машине (только чтение) / every trace of BS on this machine (read-only)
bs_cli_where_cmd() {
  # В строгом режиме bs IFS = перевод строки/табуляция; здесь нужны пробелы
  # In bs strict mode IFS is newline/tab; this function needs spaces
  __bs_cli_wh_ifs=${IFS}
  IFS=' '
  bs_cli_where_main "$@"
  __bs_cli_wh_rc=$?
  IFS=${__bs_cli_wh_ifs}
  return "${__bs_cli_wh_rc}"
}

bs_cli_where_main() {
  __bs_cli_wh_deep=0
  # извлечение пути из rc-строк — через bs_re_find (grep -oE + awk-fallback)
  # path extraction from rc lines — via bs_re_find (grep -oE with an awk fallback)
  bs_load "core/regex" 2>/dev/null || true
  while [ $# -gt 0 ]; do
    case "$1" in
      --deep)    __bs_cli_wh_deep=1; shift ;;
      -h|--help) bs_cli_where_help; return 0 ;;
      *)         bs_cli_die "where: unknown argument: $1 (try: bs where --help)" ;;
    esac
  done

  bs_arr_clear bs_cli_wh_cands
  bs_arr_clear bs_cli_wh_problems
  bs_arr_clear bs_cli_wh_hints
  bs_arr_clear bs_cli_wh_checkouts
  bs_arr_clear bs_cli_wh_ivpaths
  __bs_cli_wh_n=0
  __bs_cli_wh_first=""

  printf '== Запущено сейчас / Running now ==\n'
  bs_cli_bs_running_block
  bs_cli_where_add "${BS_ROOT}"

  # Оболочка: кто исполняет код BS, чья оболочка у пользователя, tier
  # The shell: who runs the BS code, whose shell the user has, the tier
  __bs_cli_wh_ushell=$(bs_shell_user)
  __bs_cli_wh_utier=$(bs_shell_tier "${__bs_cli_wh_ushell}")
  printf '\n== Оболочка / Shell ==\n'
  bs_cli_where_row "хозяин:" "$(bs_shell_family) $(bs_shell_version_string) (исполняет код BS / runs the BS code)"
  bs_cli_where_row "ваша:" "${__bs_cli_wh_ushell}  (login: $(bs_shell_login), parent: $(bs_shell_parent))"
  bs_cli_where_row "tier:" "${__bs_cli_wh_utier}"
  printf '    %s\n' "$(bs_shell_tier_desc "${__bs_cli_wh_utier}")"

  # --- bs в PATH ---
  printf '\n== Команда bs в PATH / The bs command in PATH ==\n'
  bs_cli_path_hits bs_cli_wh_hits "${BS_CALLER_PATH:-${PATH}}"
  __bs_cli_wh_nhits=$(bs_arr_len bs_cli_wh_hits)
  if [ "${__bs_cli_wh_nhits}" -eq 0 ]; then
    printf '  bs не найдена в PATH этой оболочки / bs is not in the PATH of this shell\n'
    bs_cli_where_problem "bs не найдена в PATH этой оболочки / bs is not in the PATH of this shell"
    if [ -x "${HOME}/.local/bin/bs" ]; then
      # shellcheck disable=SC2016
      bs_cli_where_hint "$(bs_shell_path_line "${__bs_cli_wh_ushell}" '$HOME/.local/bin')   (в этом терминале сразу / in this terminal right away; shell: ${__bs_cli_wh_ushell})"
    fi
    bs_cli_where_hint "$(bs_shell_reload_hint "${__bs_cli_wh_ushell}")  (или новый терминал / or a new terminal)"
    bs_cli_where_hint "./install.sh --local --update-path   (если строки PATH нет в rc-файле / if the rc file lacks the PATH line)"
  fi
  eval "$(bs_arr_to_args bs_cli_wh_hits)"
  for __bs_cli_wh_hit in "$@"; do
    __bs_cli_wh_n=$((__bs_cli_wh_n + 1))
    __bs_cli_wh_real=$(readlink -f -- "${__bs_cli_wh_hit}" 2>/dev/null || printf '%s' "${__bs_cli_wh_hit}")
    __bs_cli_wh_root=$(bs_cli_update_wrapper_root "${__bs_cli_wh_real}")
    __bs_cli_wh_what=""
    if [ -n "${__bs_cli_wh_root}" ]; then
      if [ -d "${__bs_cli_wh_root}" ]; then
        __bs_cli_wh_what="wrapper → ${__bs_cli_wh_root} (версия / version $(bs_version_of "${__bs_cli_wh_root}"))"
        bs_cli_where_add "${__bs_cli_wh_root}"
      else
        __bs_cli_wh_what="wrapper → ${__bs_cli_wh_root} — КАТАЛОГ НЕ СУЩЕСТВУЕТ / DIRECTORY MISSING"
        bs_cli_where_problem "обёртка ${__bs_cli_wh_hit} указывает на несуществующий ${__bs_cli_wh_root} / wrapper ${__bs_cli_wh_hit} points to a missing ${__bs_cli_wh_root}"
        bs_cli_where_hint "rm ${__bs_cli_wh_hit}  (или переустановить / or reinstall: ./install.sh --local)"
      fi
    elif [ -f "$(dirname -- "${__bs_cli_wh_real}")/bootstrap/init.sh" ]; then
      __bs_cli_wh_root=$(dirname -- "${__bs_cli_wh_real}")
      __bs_cli_wh_what="лаунчер каталога / launcher of ${__bs_cli_wh_root} (версия / version $(bs_version_of "${__bs_cli_wh_root}"))"
      bs_cli_where_add "${__bs_cli_wh_root}"
    else
      __bs_cli_wh_what="не похоже на BS / does not look like BS"
    fi
    __bs_cli_wh_mark=""
    if [ "${__bs_cli_wh_n}" -eq 1 ]; then
      __bs_cli_wh_mark="   ← запускается по команде bs / runs as \`bs\`"
      __bs_cli_wh_first=${__bs_cli_wh_root}
    fi
    printf '  %d. %s — %s%s\n' "${__bs_cli_wh_n}" "${__bs_cli_wh_hit}" "${__bs_cli_wh_what}" "${__bs_cli_wh_mark}"
  done

  # --- Кандидаты из стандартных мест, манифестов, rc-файлов и (--deep) поиска ---
  bs_cli_where_add "${HOME}/.local/lib/bs"
  bs_cli_where_add "$(bs_cli_update_system_lib)"
  if [ -n "${BS_HOME:-}" ]; then bs_cli_where_add "${BS_HOME}"; fi

  # rc-файлы ВСЕХ известных оболочек (bash, zsh, sh/ash/dash, ksh, osh, fish, nu)
  # из реестра bootstrap/shell.sh, плюс /etc/profile.d
  # rc files of ALL known shells (bash, zsh, sh/ash/dash, ksh, osh, fish, nu)
  # from the registry bootstrap/shell.sh, plus /etc/profile.d
  bs_arr_from_lines bs_cli_wh_rcfiles "$(bs_shell_all_rc_files)"
  __bs_cli_wh_pd=$(find /etc/profile.d -maxdepth 1 -name '*.sh' 2>/dev/null | sort || true)
  while IFS= read -r __bs_cli_wh_f; do
    if [ -n "${__bs_cli_wh_f}" ] && [ -f "${__bs_cli_wh_f}" ]; then bs_arr_push bs_cli_wh_rcfiles "${__bs_cli_wh_f}"; fi
  done <<EOF
${__bs_cli_wh_pd}
EOF

  # Пути из строк вида source ".../bootstrap/init.sh"
  # Paths from lines like source ".../bootstrap/init.sh"
  eval "$(bs_arr_to_args bs_cli_wh_rcfiles)"
  for __bs_cli_wh_f in "$@"; do
    if [ ! -r "${__bs_cli_wh_f}" ]; then continue; fi
    __bs_cli_wh_lines=$(grep -E '/bootstrap/init\.sh' "${__bs_cli_wh_f}" 2>/dev/null | grep -vE '^[[:space:]]*#' || true)
    while IFS= read -r __bs_cli_wh_line; do
      if [ -z "${__bs_cli_wh_line}" ]; then continue; fi
      __bs_cli_wh_m=$(bs_re_find "${__bs_cli_wh_line}" '[~/$][^"'"'"' ]*/bootstrap/init\.sh' | sed -n '1p' || true)
      if [ -z "${__bs_cli_wh_m}" ]; then continue; fi
      __bs_cli_wh_path=${__bs_cli_wh_m%/bootstrap/init.sh}
      # shellcheck disable=SC2016
      case "${__bs_cli_wh_path}" in
        '~'*)       __bs_cli_wh_path=${HOME}${__bs_cli_wh_path#'~'} ;;
        '$HOME'*)   __bs_cli_wh_path=${HOME}${__bs_cli_wh_path#'$HOME'} ;;
        '${HOME}'*) __bs_cli_wh_path=${HOME}${__bs_cli_wh_path#'${HOME}'} ;;
      esac
      case "${__bs_cli_wh_path}" in
        *\$*) ;;
        /*)   bs_cli_where_add "${__bs_cli_wh_path}" ;;
      esac
    done <<EOF
${__bs_cli_wh_lines}
EOF
  done

  if [ "${__bs_cli_wh_deep}" -eq 1 ]; then
    for __bs_cli_wh_r in "${HOME}" /opt /usr/local /srv; do
      if [ ! -d "${__bs_cli_wh_r}" ]; then continue; fi
      __bs_cli_wh_found=$(timeout 30 find "${__bs_cli_wh_r}" -xdev -maxdepth 5 \
        \( -name .git -o -name node_modules -o -name .cache -o -name proc \) -prune -o \
        -type f -path '*/bootstrap/init.sh' -print 2>/dev/null || true)
      while IFS= read -r __bs_cli_wh_f; do
        if [ -n "${__bs_cli_wh_f}" ]; then
          bs_cli_where_add "$(dirname -- "$(dirname -- "${__bs_cli_wh_f}")")"
        fi
      done <<EOF
${__bs_cli_wh_found}
EOF
    done
  fi

  # Источники установок из манифестов (откуда ставили) — это тоже следы
  # Install sources from the manifests (where they came from) are traces too
  eval "$(bs_arr_to_args bs_cli_wh_cands)"
  for __bs_cli_wh_c in "$@"; do
    __bs_cli_wh_src=$(bs_cli_install_info_get "${__bs_cli_wh_c}" source)
    if [ -n "${__bs_cli_wh_src}" ] && [ -d "${__bs_cli_wh_src}" ]; then bs_cli_where_add "${__bs_cli_wh_src}"; fi
  done

  # --- Установки ---
  printf '\n== Установки BS / BS installs ==\n'
  __bs_cli_wh_ninst=0
  __bs_cli_wh_versions=" "
  eval "$(bs_arr_to_args bs_cli_wh_cands)"
  for __bs_cli_wh_c in "$@"; do
    __bs_cli_wh_cls=$(bs_cli_where_classify "${__bs_cli_wh_c}")
    case "${__bs_cli_wh_cls}" in
      missing) continue ;;
      checkout) bs_arr_push bs_cli_wh_checkouts "${__bs_cli_wh_c}"; continue ;;
      foreign|file)
        # Чужое показываем только в стандартных местах BS
        # Foreign things are reported only at the standard BS places
        if [ "${__bs_cli_wh_c}" = "${HOME}/.local/lib/bs" ] || [ "${__bs_cli_wh_c}" = "$(bs_cli_update_system_lib)" ]; then
          printf '  %s\n' "${__bs_cli_wh_c}"
          bs_cli_where_row "состояние:" "существует, но это НЕ установка BS / exists but is NOT a BS install (${__bs_cli_wh_cls})"
          bs_cli_where_problem "${__bs_cli_wh_c} занят чужим / ${__bs_cli_wh_c} is occupied by something that is not BS"
        fi
        continue ;;
    esac
    __bs_cli_wh_ninst=$((__bs_cli_wh_ninst + 1))
    __bs_cli_wh_run=""
    if [ "${__bs_cli_wh_c}" = "$(readlink -f -- "${BS_ROOT}")" ]; then __bs_cli_wh_run='   ← запущена сейчас / running now'; fi
    printf '  %s%s\n' "${__bs_cli_wh_c}" "${__bs_cli_wh_run}"
    __bs_cli_wh_mode=$(bs_cli_install_info_get "${__bs_cli_wh_c}" mode)
    if [ -z "${__bs_cli_wh_mode}" ]; then __bs_cli_wh_mode=$(bs_cli_where_kind_by_path "${__bs_cli_wh_c}"); fi
    bs_cli_where_row "вид / kind:" "${__bs_cli_wh_mode}, версия / version $(bs_version_of "${__bs_cli_wh_c}")"
    __bs_cli_wh_versions="${__bs_cli_wh_versions}$(bs_version_of "${__bs_cli_wh_c}") "
    bs_arr_push bs_cli_wh_ivpaths "${__bs_cli_wh_c}"
    case "${__bs_cli_wh_cls}" in
      nomanifest)
        bs_cli_where_row "манифест:" "нет (установлено старым установщиком) / none (older installer)"
        bs_cli_where_problem "${__bs_cli_wh_c}: нет манифеста / no manifest"
        bs_cli_where_hint "bs update --lib ${__bs_cli_wh_c}   (создаст манифест / creates the manifest)" ;;
      badmanifest)
        bs_cli_where_row "манифест:" "ПОВРЕЖДЁН / CORRUPT: ${__bs_cli_wh_c}/.install"
        bs_cli_where_problem "${__bs_cli_wh_c}: повреждённый манифест / corrupt manifest"
        bs_cli_where_hint "bs update --lib ${__bs_cli_wh_c}   (пересоздаст манифест / recreates the manifest)" ;;
      install)
        bs_cli_where_row "установлено:" "$(bs_cli_install_info_get "${__bs_cli_wh_c}" installed_at) by $(bs_cli_install_info_get "${__bs_cli_wh_c}" installed_by)"
        __bs_cli_wh_src=$(bs_cli_install_info_get "${__bs_cli_wh_c}" source)
        __bs_cli_wh_gone=""
        if [ -n "${__bs_cli_wh_src}" ] && [ ! -d "${__bs_cli_wh_src}" ]; then __bs_cli_wh_gone='   (каталога больше нет / directory is gone)'; fi
        bs_cli_where_row "источник:" "${__bs_cli_wh_src:-?} @ $(bs_cli_short_sha "$(bs_cli_install_info_get "${__bs_cli_wh_c}" source_commit)")${__bs_cli_wh_gone}"
        if [ -n "$(bs_cli_install_info_get "${__bs_cli_wh_c}" updated_at)" ]; then
          bs_cli_where_row "обновлено:" "$(bs_cli_install_info_get "${__bs_cli_wh_c}" updated_at) from $(bs_cli_install_info_get "${__bs_cli_wh_c}" updated_from) @ $(bs_cli_short_sha "$(bs_cli_install_info_get "${__bs_cli_wh_c}" updated_commit)")"
        fi ;;
    esac
    # Обёртка этой установки
    # The wrapper of this install
    __bs_cli_wh_bin=$(bs_cli_install_info_get "${__bs_cli_wh_c}" bin)
    if [ -z "${__bs_cli_wh_bin}" ]; then __bs_cli_wh_bin="${__bs_cli_wh_c%/lib/bs}/bin/bs"; fi
    if [ -f "${__bs_cli_wh_bin}" ]; then
      __bs_cli_wh_wrap=$(bs_cli_update_wrapper_root "${__bs_cli_wh_bin}")
      if [ "$(readlink -f -- "${__bs_cli_wh_wrap:-/nonexistent}" 2>/dev/null)" = "${__bs_cli_wh_c}" ]; then
        case ":${BS_CALLER_PATH:-${PATH}}:" in
          *":$(dirname -- "${__bs_cli_wh_bin}"):"*) __bs_cli_wh_inpath=' (каталог в PATH / directory in PATH)' ;;
          *)                                        __bs_cli_wh_inpath=' (каталога НЕТ в PATH / directory NOT in PATH)' ;;
        esac
        bs_cli_where_row "wrapper:" "${__bs_cli_wh_bin}${__bs_cli_wh_inpath}"
      else
        bs_cli_where_row "wrapper:" "${__bs_cli_wh_bin} — указывает на ${__bs_cli_wh_wrap:-?}, не сюда / points to ${__bs_cli_wh_wrap:-?}, not here"
        if [ -n "${__bs_cli_wh_wrap}" ] && [ -d "${__bs_cli_wh_wrap}" ]; then
          bs_cli_where_problem "${__bs_cli_wh_bin} ведёт не в ${__bs_cli_wh_c} / ${__bs_cli_wh_bin} does not lead to ${__bs_cli_wh_c}"
        else
          bs_cli_where_problem "обёртка ${__bs_cli_wh_bin} указывает на несуществующий ${__bs_cli_wh_wrap:-?} / wrapper ${__bs_cli_wh_bin} points to a missing ${__bs_cli_wh_wrap:-?}"
          bs_cli_where_hint "rm ${__bs_cli_wh_bin}  (или переустановить / or reinstall: ./install.sh --local)"
        fi
      fi
    else
      bs_cli_where_row "wrapper:" "нет / none (ожидался / expected: ${__bs_cli_wh_bin})"
      if [ "${__bs_cli_wh_cls}" != checkout ]; then
        __bs_cli_wh_flag=""
        if [ "${__bs_cli_wh_mode}" = local ]; then __bs_cli_wh_flag='--local'; fi
        bs_cli_where_problem "${__bs_cli_wh_c}: нет обёртки, команда bs её не найдёт / no wrapper"
        bs_cli_where_hint "./install.sh ${__bs_cli_wh_flag}   (починит обёртку / repairs the wrapper)"
      fi
    fi
    __bs_cli_wh_owner=$(stat -c %U -- "${__bs_cli_wh_c}" 2>/dev/null || printf '?')
    if [ -w "${__bs_cli_wh_c}" ]; then
      __bs_cli_wh_access="доступна на запись / writable"
    else
      __bs_cli_wh_access="только чтение, нужен sudo / read-only, needs sudo"
    fi
    bs_cli_where_row "владелец:" "${__bs_cli_wh_owner}, ${__bs_cli_wh_access}"
    # Остатки упавших обновлений и установок
    # Leftovers of failed updates and installs
    bs_arr_clear bs_cli_wh_left
    __bs_cli_wh_ltxt=$(bs_cli_where_leftovers "${__bs_cli_wh_c}")
    while IFS= read -r __bs_cli_wh_f; do
      if [ -n "${__bs_cli_wh_f}" ] && [ -e "${__bs_cli_wh_f}" ]; then bs_arr_push bs_cli_wh_left "${__bs_cli_wh_f}"; fi
    done <<EOF
${__bs_cli_wh_ltxt}
EOF
    if [ "$(bs_arr_len bs_cli_wh_left)" -gt 0 ]; then
      bs_cli_where_row "остатки:" "$(bs_arr_join bs_cli_wh_left ' ')"
      bs_cli_where_problem "${__bs_cli_wh_c}: остатки прерванных операций / leftovers of interrupted operations"
      bs_cli_where_hint "bs update --lib ${__bs_cli_wh_c}   (очистит остатки / cleans the leftovers)"
    fi
  done
  if [ "${__bs_cli_wh_ninst}" -eq 0 ]; then printf '  установок не найдено / no installs found\n'; fi

  # --- Репозитории ---
  printf '\n== Репозитории BS / BS source checkouts ==\n'
  if [ "$(bs_arr_len bs_cli_wh_checkouts)" -eq 0 ]; then
    printf '  не найдено / none found\n'
  fi
  eval "$(bs_arr_to_args bs_cli_wh_checkouts)"
  for __bs_cli_wh_c in "$@"; do
    __bs_cli_wh_run=""
    if [ "${__bs_cli_wh_c}" = "$(readlink -f -- "${BS_ROOT}")" ]; then __bs_cli_wh_run='   ← запущен сейчас / running now'; fi
    printf '  %s%s\n' "${__bs_cli_wh_c}" "${__bs_cli_wh_run}"
    __bs_cli_wh_git=""
    if [ -e "${__bs_cli_wh_c}/.git" ] && bs_utils_has git; then
      __bs_cli_wh_git=", commit $(git -C "${__bs_cli_wh_c}" rev-parse --short=7 HEAD 2>/dev/null || printf '?')"
    fi
    bs_cli_where_row "версия / ver.:" "$(bs_version_of "${__bs_cli_wh_c}")${__bs_cli_wh_git}"
  done

  # --- Следы в оболочке ---
  printf '\n== Следы в оболочке / Shell traces ==\n'
  __bs_cli_wh_hitsn=0
  eval "$(bs_arr_to_args bs_cli_wh_rcfiles)"
  for __bs_cli_wh_f in "$@"; do
    if [ ! -r "${__bs_cli_wh_f}" ]; then continue; fi
    # shellcheck disable=SC2016  # $HOME в шаблоне grep — текст / $HOME in the grep pattern is text
    __bs_cli_wh_lines=$(grep -nE -- '(bootstrap/init\.sh|BS_ROOT|\.local/lib/bs|/lib/bs/|bs init-shell|export PATH="\$HOME/\.local/bin:\$PATH"|contains -- "\$HOME/\.local/bin"|path join "\.local" "bin")' "${__bs_cli_wh_f}" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|${__bs_cli_wh_f}:|" || true)
    if [ -z "${__bs_cli_wh_lines}" ]; then continue; fi
    while IFS= read -r __bs_cli_wh_line; do
      printf '  %s\n' "$(bs_str_head "${__bs_cli_wh_line}" 150)"
      __bs_cli_wh_hitsn=$((__bs_cli_wh_hitsn + 1))
    done <<EOF
${__bs_cli_wh_lines}
EOF
  done
  if [ "${__bs_cli_wh_hitsn}" -eq 0 ]; then printf '  в rc-файлах строк про BS нет / no BS lines in the rc files\n'; fi
  case ":${BS_CALLER_PATH:-${PATH}}:" in
    *":${HOME}/.local/bin:"*) printf '  PATH этой оболочки содержит / contains %s/.local/bin\n' "${HOME}" ;;
    *) printf '  PATH этой оболочки НЕ содержит / does NOT contain %s/.local/bin\n' "${HOME}" ;;
  esac

  # --- Данные и кэш ---
  printf '\n== Данные и кэш / Data and cache ==\n'
  __bs_cli_wh_datan=0
  __bs_cli_wh_dseen="|"
  for __bs_cli_wh_d in "${XDG_CONFIG_HOME:-${HOME}/.config}/bs" "${HOME}/.config/bs" \
      "${HOME}/.config/bs_frameworks" "${XDG_CACHE_HOME:-${HOME}/.cache}/bs" \
      "${XDG_STATE_HOME:-${HOME}/.local/state}/bs" "${XDG_DATA_HOME:-${HOME}/.local/share}/bs" \
      "${BS_BUILD_CACHE_DIR:-}"; do
    if [ ! -d "${__bs_cli_wh_d}" ]; then continue; fi
    case "${__bs_cli_wh_dseen}" in
      *"|${__bs_cli_wh_d}|"*) continue ;;
    esac
    __bs_cli_wh_dseen="${__bs_cli_wh_dseen}${__bs_cli_wh_d}|"
    printf '  %s — %s\n' "${__bs_cli_wh_d}" "$(bs_cli_where_size "${__bs_cli_wh_d}")"
    __bs_cli_wh_datan=$((__bs_cli_wh_datan + 1))
  done
  if [ "${__bs_cli_wh_datan}" -eq 0 ]; then printf '  не найдено / none found\n'; fi

  # --- Переменные окружения ---
  printf '\n== Переменные окружения / Environment ==\n'
  __bs_cli_wh_envn=0
  for __bs_cli_wh_v in BS_SYSTEM_PREFIX BS_UPDATE_REPO BS_BUILD_CACHE_DIR PREFIX BIN_DIR LIB_DIR; do
    __bs_cli_wh_val=""
    bs_var_get "${__bs_cli_wh_v}" __bs_cli_wh_val || true
    if [ -n "${__bs_cli_wh_val}" ]; then
      printf '  %s=%s\n' "${__bs_cli_wh_v}" "${__bs_cli_wh_val}"
      __bs_cli_wh_envn=$((__bs_cli_wh_envn + 1))
    fi
  done
  if [ "${__bs_cli_wh_envn}" -eq 0 ]; then
    printf '  не заданы (BS_ROOT/BS_HOME выставляет сам bs) / none set (BS_ROOT/BS_HOME are set by bs itself)\n'
  fi

  # --- Итог ---
  printf '\n== Итог / Summary ==\n'
  printf '  установок / installs: %d,  репозиториев / checkouts: %d,  bs в PATH / bs in PATH: %d\n' \
    "${__bs_cli_wh_ninst}" "$(bs_arr_len bs_cli_wh_checkouts)" "$(bs_arr_len bs_cli_wh_hits)"
  # Разные версии: уникальные, в порядке появления (IFS здесь — пробел)
  # Different versions: unique, in order of appearance (IFS is a space here)
  __bs_cli_wh_uniq=""
  __bs_cli_wh_nuniq=0
  for __bs_cli_wh_v in ${__bs_cli_wh_versions}; do
    case " ${__bs_cli_wh_uniq} " in
      *" ${__bs_cli_wh_v} "*) ;;
      *)
        __bs_cli_wh_uniq="${__bs_cli_wh_uniq}${__bs_cli_wh_uniq:+ }${__bs_cli_wh_v}"
        __bs_cli_wh_nuniq=$((__bs_cli_wh_nuniq + 1)) ;;
    esac
  done
  if [ "${__bs_cli_wh_nuniq}" -gt 1 ]; then
    bs_cli_where_problem "установки разных версий / installs of different versions: ${__bs_cli_wh_uniq}"
    bs_cli_where_hint "bs update   (обновит все найденные установки / updates every detected install)"
  fi
  if [ -n "${__bs_cli_wh_first}" ] && [ -d "${__bs_cli_wh_first}" ] && [ ! -d "${BS_ROOT}/tests" ] \
     && [ "$(readlink -f -- "${__bs_cli_wh_first}")" != "$(readlink -f -- "${BS_ROOT}")" ]; then
    bs_cli_where_problem "сейчас запущена не та копия, что по команде bs: ${BS_ROOT} вместо ${__bs_cli_wh_first} / the running copy is not the one behind \`bs\`"
  fi
  # Установка старее найденного репозитория — обновление доступно
  # An install older than a found checkout — an update is available
  __bs_cli_wh_c=''
  __bs_cli_wh_ck=''
  __bs_cli_wh_ni=$(bs_arr_len bs_cli_wh_ivpaths)
  __bs_cli_wh_i=0
  while [ "${__bs_cli_wh_i}" -lt "${__bs_cli_wh_ni}" ]; do
    bs_arr_get bs_cli_wh_ivpaths "${__bs_cli_wh_i}" __bs_cli_wh_c
    __bs_cli_wh_i=$((__bs_cli_wh_i + 1))
    __bs_cli_wh_iv=$(bs_version_of "${__bs_cli_wh_c}")
    __bs_cli_wh_nk=$(bs_arr_len bs_cli_wh_checkouts)
    __bs_cli_wh_k=0
    while [ "${__bs_cli_wh_k}" -lt "${__bs_cli_wh_nk}" ]; do
      bs_arr_get bs_cli_wh_checkouts "${__bs_cli_wh_k}" __bs_cli_wh_ck
      __bs_cli_wh_k=$((__bs_cli_wh_k + 1))
      __bs_cli_wh_cv=$(bs_version_of "${__bs_cli_wh_ck}")
      if [ -z "${__bs_cli_wh_iv}" ] || [ -z "${__bs_cli_wh_cv}" ]; then continue; fi
      __bs_cli_wh_cmp=0
      bs_version_compare "${__bs_cli_wh_iv}" "${__bs_cli_wh_cv}" || __bs_cli_wh_cmp=$?
      if [ "${__bs_cli_wh_cmp}" -eq 2 ]; then
        bs_cli_where_problem "установка ${__bs_cli_wh_c} (${__bs_cli_wh_iv}) старее репозитория ${__bs_cli_wh_ck} (${__bs_cli_wh_cv}) / the install ${__bs_cli_wh_c} (${__bs_cli_wh_iv}) is older than the checkout ${__bs_cli_wh_ck} (${__bs_cli_wh_cv})"
        bs_cli_where_hint "cd ${__bs_cli_wh_ck} && ./bs update --lib ${__bs_cli_wh_c}"
      fi
    done
  done
  if [ "$(bs_arr_len bs_cli_wh_problems)" -eq 0 ]; then
    printf '  ✓ всё согласовано / everything looks consistent\n'
  else
    printf '  Что вызывает вопросы / What looks wrong:\n'
    eval "$(bs_arr_to_args bs_cli_wh_problems)"
    for __bs_cli_wh_p in "$@"; do printf '   • %s\n' "${__bs_cli_wh_p}"; done
    if [ "$(bs_arr_len bs_cli_wh_hints)" -gt 0 ]; then
      printf '  Что сделать / What to do:\n'
      eval "$(bs_arr_to_args bs_cli_wh_hints)"
      for __bs_cli_wh_p in "$@"; do printf '   → %s\n' "${__bs_cli_wh_p}"; done
    fi
  fi
  return 0
}


# ==========================================================================
# bs update: источник, замки, откат, манифест / source, locks, rollback, manifest
# ==========================================================================

# Перевод строки для склейки текста: $'\n' в POSIX sh нет.
# A newline for joining text: POSIX sh has no $'\n'.
# @global BS_CLI_NL — CLI: символ перевода строки (категория: constant)
# @global BS_CLI_NL — CLI: the newline character (category: constant)
BS_CLI_NL='
'
bs_shell_readonly BS_CLI_NL

# URL репозитория по умолчанию для `bs update --github` (переопределяется
# флагом --repo или переменной BS_UPDATE_REPO).
# Default repository URL for `bs update --github` (override with --repo or
# the BS_UPDATE_REPO variable).
# @global UPDATE_DEFAULT_REPO — Update: репозиторий по умолчанию для --github (категория: constant)
# @global UPDATE_DEFAULT_REPO — Update: default repository for --github (category: constant)
UPDATE_DEFAULT_REPO="https://github.com/Igormm/bs"
bs_shell_readonly UPDATE_DEFAULT_REPO

# @global UPDATE_FETCH_DIR — Update: каталог со скачанным источником; удаляется стеком cleanup (категория: private)
# @global UPDATE_FETCH_DIR — Update: directory with the downloaded source; removed by the cleanup stack (category: private)
UPDATE_FETCH_DIR=""

# @global UPDATE_INF_TARGET — Update: цель, чья замена в процессе (категория: private)
# @global UPDATE_INF_TARGET — Update: the target being replaced (category: private)
UPDATE_INF_TARGET=""
# @global UPDATE_INF_TMP — Update: временный каталог незавершённой замены (категория: private)
# @global UPDATE_INF_TMP — Update: temp directory of an unfinished swap (category: private)
UPDATE_INF_TMP=""
# @global UPDATE_INF_OLD — Update: каталог со старыми частями незавершённой замены (категория: private)
# @global UPDATE_INF_OLD — Update: directory with the old parts of an unfinished swap (category: private)
UPDATE_INF_OLD=""
# @global UPDATE_INF_SUDO — Update: "sudo" или пусто для незавершённой замены (категория: private)
# @global UPDATE_INF_SUDO — Update: "sudo" or empty for an unfinished swap (category: private)
UPDATE_INF_SUDO=""

# Занятые замки — два массива слоя данных (создаются при первом bs_arr_push):
#   bs_cli_ul_locks — каталоги-замки; bs_cli_ul_sudo — "sudo" или пусто для каждого.
# Held locks — two data-layer arrays (created by the first bs_arr_push):
#   bs_cli_ul_locks — the lock directories; bs_cli_ul_sudo — "sudo" or empty for each.

# @private Все исполняемые `bs` в PATH, по порядку, с повторами — как `type -aP bs`
# в bash: пустой элемент PATH значит текущий каталог, каталог без хвостового «/»
# получает его. Результат в массив $1.
# @private Every executable `bs` in PATH, in order, repeats kept — like bash's
# `type -aP bs`: an empty PATH element means the current directory, a directory
# without a trailing "/" gets one. The result goes to the array $1.
# @param $1 Array name / имя массива
# @param $2 PATH string / строка PATH
bs_cli_path_hits() {
  __bs_cli_ph_name=$1
  bs_arr_clear "${__bs_cli_ph_name}"
  __bs_cli_ph_rest="$2:"
  while [ -n "${__bs_cli_ph_rest}" ]; do
    __bs_cli_ph_dir=${__bs_cli_ph_rest%%:*}
    __bs_cli_ph_rest=${__bs_cli_ph_rest#*:}
    case "${__bs_cli_ph_dir}" in
      '') __bs_cli_ph_file=./bs ;;
      */) __bs_cli_ph_file=${__bs_cli_ph_dir}bs ;;
      *)  __bs_cli_ph_file=${__bs_cli_ph_dir}/bs ;;
    esac
    if [ -x "${__bs_cli_ph_file}" ] && [ ! -d "${__bs_cli_ph_file}" ]; then
      bs_arr_push "${__bs_cli_ph_name}" "${__bs_cli_ph_file}"
    fi
  done
}

# @private Запустить команду с ограничением по времени, если есть timeout.
# @private Run a command with a time limit when timeout exists.
# @param $1 Seconds / секунды
# @param $@ Command / команда
bs_cli_with_timeout() {
  __bs_cli_wt_secs=$1
  shift
  if bs_utils_has timeout; then
    timeout "${__bs_cli_wt_secs}" "$@"
  else
    "$@"
  fi
}

bs_cli_update_fetch_cleanup() {
  if [ -n "${UPDATE_FETCH_DIR}" ]; then rm -rf -- "${UPDATE_FETCH_DIR}"; fi
  return 0
}

# @private Скачать репозиторий во временный каталог: git clone (shallow),
# иначе tar-архив через curl/wget. Путь кладётся в UPDATE_FETCH_DIR.
# При неудаче — сообщение с причиной (нет git/curl, нет сети, нет такой
# ветки/тега, это не репозиторий); временный каталог убирает стек cleanup.
# @private Download the repository into a temp dir: shallow git clone, else
# a tarball via curl/wget. The path is stored in UPDATE_FETCH_DIR. On failure
# the message names the cause (no git/curl, no network, no such branch/tag,
# not a repository); the temp dir is removed by the cleanup stack.
# @param $1 Repo URL / URL репозитория
# @param $2 Branch or tag / Ветка или тег
bs_cli_update_fetch() {
  __bs_cli_uf_repo=${1%.git}
  __bs_cli_uf_ref=$2
  UPDATE_FETCH_DIR="$(mktemp -d)" \
    || bs_cli_update_die "update: cannot create a temporary directory / не удалось создать временный каталог"
  bs_cleanup_add bs_cli_update_fetch_cleanup
  __bs_cli_uf_dest="${UPDATE_FETCH_DIR}/src"
  if ! bs_utils_has git && ! bs_utils_has curl && ! bs_utils_has wget; then
    bs_cli_update_die "update: нужен git или curl/wget для --github / need git or curl/wget for --github (or use: bs update --from <repo-path>)"
  fi

  __bs_cli_uf_err=""
  __bs_cli_uf_reach=0
  if bs_utils_has git; then
    # подоболочка: GIT_TERMINAL_PROMPT=0 не утекает в окружение bs / a subshell keeps GIT_TERMINAL_PROMPT=0 out of the bs environment
    if __bs_cli_uf_err="$(GIT_TERMINAL_PROMPT=0; export GIT_TERMINAL_PROMPT; bs_cli_with_timeout 120 git clone --quiet --depth 1 --branch "${__bs_cli_uf_ref}" -- "${__bs_cli_uf_repo}" "${__bs_cli_uf_dest}" 2>&1)"; then
      return 0
    fi
    rm -rf -- "${__bs_cli_uf_dest}"
    if (GIT_TERMINAL_PROMPT=0; export GIT_TERMINAL_PROMPT; bs_cli_with_timeout 120 git ls-remote --exit-code -- "${__bs_cli_uf_repo}" HEAD >/dev/null 2>&1); then
      __bs_cli_uf_reach=1
    fi
  fi
  if [ "${__bs_cli_uf_reach}" -eq 1 ]; then
    bs_cli_update_die "update: ветка/тег '${__bs_cli_uf_ref}' не найден в ${__bs_cli_uf_repo} / branch or tag '${__bs_cli_uf_ref}' not found in ${__bs_cli_uf_repo} (--ref REF)"
  fi
  mkdir -p -- "${__bs_cli_uf_dest}"

  __bs_cli_uf_archive="${__bs_cli_uf_repo}/archive/${__bs_cli_uf_ref}.tar.gz"
  if bs_utils_has curl; then
    if curl -fsSL -- "${__bs_cli_uf_archive}" 2>/dev/null | bs_utils_quiet tar -xz -C "${__bs_cli_uf_dest}" --strip-components=1; then
      return 0
    fi
  elif bs_utils_has wget; then
    if wget -qO- -- "${__bs_cli_uf_archive}" 2>/dev/null | bs_utils_quiet tar -xz -C "${__bs_cli_uf_dest}" --strip-components=1; then
      return 0
    fi
  fi
  __bs_cli_uf_note=""
  if [ -n "${__bs_cli_uf_err}" ]; then __bs_cli_uf_note=" [git: ${__bs_cli_uf_err%%"${BS_CLI_NL}"*}]"; fi
  bs_cli_update_die "update: не удалось получить ${__bs_cli_uf_repo} (${__bs_cli_uf_ref}): нет сети, репозиторий не найден или ветки/тега нет / cannot fetch ${__bs_cli_uf_repo} (${__bs_cli_uf_ref}): no network, repository or ref not found${__bs_cli_uf_note}"
}

# @private Сравнить локальный checkout с удалённой веткой, ничего не меняя
# в репозитории (ls-remote, без fetch). Печатает одно слово:
#   same     — HEAD совпадает с удалённой веткой
#   ahead    — локально есть коммиты, которых нет на удалённой стороне
#   behind   — на удалённой стороне есть код, которого нет локально
#              (в т.ч. разошедшиеся истории)
#   unknown  — не git-checkout, нет сети или нет такой ветки
# @private Compare a local checkout with the remote branch without touching
# the repository (ls-remote, no fetch). Prints one word: same | ahead |
# behind (remote has code the checkout lacks, diverged included) | unknown.
# @param $1 Local checkout / Локальный checkout
# @param $2 Repo URL / URL репозитория
# @param $3 Branch / Ветка
bs_cli_update_local_state() {
  __bs_cli_ls_dir=$1
  __bs_cli_ls_repo=${2%.git}
  __bs_cli_ls_ref=$3
  if ! bs_utils_has git || [ ! -e "${__bs_cli_ls_dir}/.git" ]; then
    printf 'unknown\n'
    return 0
  fi
  __bs_cli_ls_remote="$(GIT_TERMINAL_PROMPT=0; export GIT_TERMINAL_PROMPT; bs_cli_with_timeout 15 git ls-remote -- "${__bs_cli_ls_repo}" "refs/heads/${__bs_cli_ls_ref}" 2>/dev/null | cut -f1)" || __bs_cli_ls_remote=""
  __bs_cli_ls_head="$(git -C "${__bs_cli_ls_dir}" rev-parse HEAD 2>/dev/null)" || __bs_cli_ls_head=""
  if [ -z "${__bs_cli_ls_remote}" ] || [ -z "${__bs_cli_ls_head}" ]; then
    printf 'unknown\n'
  elif [ "${__bs_cli_ls_remote}" = "${__bs_cli_ls_head}" ]; then
    printf 'same\n'
  elif bs_utils_quiet git -C "${__bs_cli_ls_dir}" merge-base --is-ancestor "${__bs_cli_ls_remote}" HEAD; then
    printf 'ahead\n'
  else
    printf 'behind\n'
  fi
}

# @private Вернуть прежние части из old-каталога и убрать временные.
# @private Restore the previous parts from the old dir and drop the temp dirs.
# @param $1 Target / $2 temp dir / $3 old dir / $4 "sudo" or empty
bs_cli_update_rollback() {
  __bs_cli_rb_target=$1
  __bs_cli_rb_tmp=$2
  __bs_cli_rb_old=$3
  __bs_cli_rb_sudo=$4
  if [ -z "${__bs_cli_rb_target}" ]; then return 0; fi
  for __bs_cli_rb_part in bs bootstrap core lib; do
    if [ -e "${__bs_cli_rb_old}/${__bs_cli_rb_part}" ]; then
      if [ "${__bs_cli_rb_part}" = "bs" ]; then
        ${__bs_cli_rb_sudo} mv -f -- "${__bs_cli_rb_old}/bs" "${__bs_cli_rb_target}/bs" || true
      else
        ${__bs_cli_rb_sudo} rm -rf -- "${__bs_cli_rb_target}/${__bs_cli_rb_part}" || true
        ${__bs_cli_rb_sudo} mv -- "${__bs_cli_rb_old}/${__bs_cli_rb_part}" "${__bs_cli_rb_target}/${__bs_cli_rb_part}" || true
      fi
    elif [ -e "${__bs_cli_rb_old}/.added-${__bs_cli_rb_part}" ]; then
      ${__bs_cli_rb_sudo} rm -rf -- "${__bs_cli_rb_target}/${__bs_cli_rb_part}" || true
    fi
  done
  ${__bs_cli_rb_sudo} rm -rf -- "${__bs_cli_rb_tmp}" "${__bs_cli_rb_old}" || true
}

# @private EXIT/сигнал: незавершённая замена откатывается, замки снимаются.
# @private EXIT/signal: an unfinished swap is rolled back and locks released.
bs_cli_update_inflight_cleanup() {
  if [ -n "${UPDATE_INF_TARGET}" ]; then
    bs_cli_update_rollback "${UPDATE_INF_TARGET}" "${UPDATE_INF_TMP}" "${UPDATE_INF_OLD}" "${UPDATE_INF_SUDO}"
    UPDATE_INF_TARGET=""
  fi
  __bs_cli_ic_n=$(bs_arr_len bs_cli_ul_locks)
  __bs_cli_ic_i=0
  while [ "${__bs_cli_ic_i}" -lt "${__bs_cli_ic_n}" ]; do
    __bs_cli_ic_lock=''
    __bs_cli_ic_sudo=''
    bs_arr_get bs_cli_ul_locks "${__bs_cli_ic_i}" __bs_cli_ic_lock
    bs_arr_get bs_cli_ul_sudo "${__bs_cli_ic_i}" __bs_cli_ic_sudo
    __bs_cli_ic_i=$((__bs_cli_ic_i + 1))
    if [ -z "${__bs_cli_ic_lock}" ]; then continue; fi
    if [ -n "${__bs_cli_ic_sudo}" ]; then
      sudo rm -rf -- "${__bs_cli_ic_lock}" || true
    else
      rm -rf -- "${__bs_cli_ic_lock}" || true
    fi
  done
  bs_arr_clear bs_cli_ul_locks
  bs_arr_clear bs_cli_ul_sudo
  return 0
}

# @private Убрать хвосты упавших запусков (.update.PID / .update-old.PID,
# чей процесс мёртв). Незавершённая замена откатывается; завершённая
# (маркер .committed) просто удаляется.
# @private Drop leftovers of crashed runs (.update.PID / .update-old.PID whose
# process is dead). An unfinished swap is rolled back; a committed one
# (.committed marker) is simply deleted.
# @param $1 Target / $2 optional "sudo"
bs_cli_update_cleanup_stale() {
  __bs_cli_cs_target=$1
  __bs_cli_cs_sudo=${2:-}
  __bs_cli_cs_list=$(
    for __bs_cli_cs_pat in '.update.*' '.update-old.*'; do
      find "${__bs_cli_cs_target}" -maxdepth 1 -name "${__bs_cli_cs_pat}" 2>/dev/null | sort
    done
  )
  while IFS= read -r __bs_cli_cs_d; do
    if [ -z "${__bs_cli_cs_d}" ] || [ ! -d "${__bs_cli_cs_d}" ]; then continue; fi
    __bs_cli_cs_pid=${__bs_cli_cs_d##*.}
    case "${__bs_cli_cs_pid}" in
      ''|*[!0-9]*) continue ;;
    esac
    if kill -0 "${__bs_cli_cs_pid}" 2>/dev/null; then continue; fi
    case "${__bs_cli_cs_d}" in
      */.update-old.*)
        if [ ! -e "${__bs_cli_cs_d}/.committed" ]; then
          bs_cli_update_rollback "${__bs_cli_cs_target}" "${__bs_cli_cs_target}/.update.${__bs_cli_cs_pid}" "${__bs_cli_cs_d}" "${__bs_cli_cs_sudo}"
          bs_log_info "update: восстановлена установка после прерванного запуска / restored after an interrupted run: ${__bs_cli_cs_target}"
        fi ;;
    esac
    ${__bs_cli_cs_sudo} rm -rf -- "${__bs_cli_cs_d}" || true
  done <<EOF
${__bs_cli_cs_list}
EOF
  return 0
}

# @private Взять замок цели (mkdir атомарен; pid устаревшего замка проверяется).
# @private Take the target lock (mkdir is atomic; a stale lock pid is checked).
# @param $1 Target / $2 optional "sudo"
# @return 0 got it, 1 another update is running
bs_cli_update_lock() {
  __bs_cli_lk_target=$1
  __bs_cli_lk_sudo=${2:-}
  __bs_cli_lk_dir="${__bs_cli_lk_target}/.update-lock"
  for __bs_cli_lk_try in 1 2; do
    if ${__bs_cli_lk_sudo} mkdir -- "${__bs_cli_lk_dir}" 2>/dev/null; then
      printf '%s\n' "$$" | ${__bs_cli_lk_sudo} tee -- "${__bs_cli_lk_dir}/pid" >/dev/null || true
      bs_arr_push bs_cli_ul_locks "${__bs_cli_lk_dir}"
      bs_arr_push bs_cli_ul_sudo "${__bs_cli_lk_sudo}"
      return 0
    fi
    __bs_cli_lk_pid=""
    if [ -r "${__bs_cli_lk_dir}/pid" ]; then
      IFS= read -r __bs_cli_lk_pid < "${__bs_cli_lk_dir}/pid" || true
    fi
    case "${__bs_cli_lk_pid}" in
      ''|*[!0-9]*) ;;
      *)
        if kill -0 "${__bs_cli_lk_pid}" 2>/dev/null; then return 1; fi ;;
    esac
    ${__bs_cli_lk_sudo} rm -rf -- "${__bs_cli_lk_dir}" || return 1
  done
  return 1
}

# @param $1 Target / цель
bs_cli_update_unlock() {
  __bs_cli_ul_n=$(bs_arr_len bs_cli_ul_locks)
  __bs_cli_ul_i=0
  while [ "${__bs_cli_ul_i}" -lt "${__bs_cli_ul_n}" ]; do
    __bs_cli_ul_lock=''
    __bs_cli_ul_sudo=''
    bs_arr_get bs_cli_ul_locks "${__bs_cli_ul_i}" __bs_cli_ul_lock
    bs_arr_get bs_cli_ul_sudo "${__bs_cli_ul_i}" __bs_cli_ul_sudo
    if [ "${__bs_cli_ul_lock}" = "$1/.update-lock" ]; then
      if [ -n "${__bs_cli_ul_sudo}" ]; then
        sudo rm -rf -- "${__bs_cli_ul_lock}" || true
      else
        rm -rf -- "${__bs_cli_ul_lock}" || true
      fi
      # место не удаляется (индексы остальных замков не сдвигаются) — запись пустеет
      # the slot is not removed (the indexes of the other locks stay) — the entry is emptied
      bs_arr_set bs_cli_ul_locks "${__bs_cli_ul_i}" ""
      bs_arr_set bs_cli_ul_sudo "${__bs_cli_ul_i}" ""
    fi
    __bs_cli_ul_i=$((__bs_cli_ul_i + 1))
  done
  return 0
}

# @private Починить shebang файла под эту машину (bs_shebang_fix), от имени sudo при необходимости.
# @private Repair the shebang of a file for this machine (bs_shebang_fix), as sudo if needed.
# @param $1 file / файл
# @param $2 optional command prefix (sudo) / необязательный префикс (sudo)
bs_cli_update_fix_shebang() {
  __bs_cli_fs_file=$1
  __bs_cli_fs_sudo=${2:-}
  # bash 4.2+ есть — тот же bash, что исполняет bs; нет — POSIX-оболочка sh (bootstrap/shebang.sh — @shell posix)
  # a bash 4.2+ exists — the same bash that runs bs; none — the POSIX shell sh (bootstrap/shebang.sh is @shell posix)
  if bs_shell_host_ok; then
    __bs_cli_fs_host=$(bs_shell_host)
  else
    __bs_cli_fs_host='sh'
  fi
  # shellcheck disable=SC2016  # скрипт для дочерней оболочки, $1 и $2 раскрывает она / the child shell script: it expands $1 and $2
  ${__bs_cli_fs_sudo} "${__bs_cli_fs_host}" -c '. "$1"; bs_shebang_fix "$2"' _ "${BS_BOOTSTRAP_DIR}/shebang.sh" "${__bs_cli_fs_file}"
}

# @private Самопроверка установленной копии: bs version печатает версию источника.
# bs запускается КАК ПРОГРАММА (через свой shebang), чтобы сломанный shebang
# (Termux без /usr/bin/env) не проходил проверку.
# @private Smoke test of the installed copy: bs version prints the source's version.
# bs runs AS A PROGRAM (through its own shebang), so a broken shebang (Termux
# without /usr/bin/env) does not pass the test.
# @param $1 Target / $2 expected version
bs_cli_update_smoke() {
  __bs_cli_sk_t=$1
  __bs_cli_sk_want=$2
  if bs_utils_has timeout; then
    __bs_cli_sk_out="$(env -u BS_INITIALIZED -u BS_VERSION BS_ROOT="${__bs_cli_sk_t}" BS_HOME="${__bs_cli_sk_t}" BS_SILENT=1 \
      timeout 60 "${__bs_cli_sk_t}/bs" version 2>&1)" || return 1
  else
    __bs_cli_sk_out="$(env -u BS_INITIALIZED -u BS_VERSION BS_ROOT="${__bs_cli_sk_t}" BS_HOME="${__bs_cli_sk_t}" BS_SILENT=1 \
      "${__bs_cli_sk_t}/bs" version 2>&1)" || return 1
  fi
  case "${__bs_cli_sk_out}" in
    *"version: ${__bs_cli_sk_want}"*) return 0 ;;
  esac
  return 1
}

# @private Заменить части установки: новое — во временный каталог, старое —
# в .update-old.PID, затем smoke-test; при любом сбое — откат.
# @private Replace install parts: new into a temp dir, old into
# .update-old.PID, then smoke test; any failure rolls back.
# @param $1 Target / $2 source / $3 expected version / $4 optional "sudo"
# @return 0 ok, 1 copy/swap failed, 2 smoke test failed (both rolled back)
bs_cli_update_apply() {
  __bs_cli_ap_target=$1
  __bs_cli_ap_from=$2
  __bs_cli_ap_want=$3
  __bs_cli_ap_sudo=${4:-}
  __bs_cli_ap_tmp="${__bs_cli_ap_target}/.update.$$"
  __bs_cli_ap_old="${__bs_cli_ap_target}/.update-old.$$"
  ${__bs_cli_ap_sudo} rm -rf -- "${__bs_cli_ap_tmp}" "${__bs_cli_ap_old}" || return 1
  ${__bs_cli_ap_sudo} mkdir -p -- "${__bs_cli_ap_tmp}" "${__bs_cli_ap_old}" \
    || { ${__bs_cli_ap_sudo} rm -rf -- "${__bs_cli_ap_tmp}" "${__bs_cli_ap_old}"; return 1; }
  UPDATE_INF_TARGET="${__bs_cli_ap_target}"
  UPDATE_INF_TMP="${__bs_cli_ap_tmp}"
  UPDATE_INF_OLD="${__bs_cli_ap_old}"
  UPDATE_INF_SUDO="${__bs_cli_ap_sudo}"
  if ! ${__bs_cli_ap_sudo} cp -a "${__bs_cli_ap_from}/bootstrap" "${__bs_cli_ap_from}/core" "${__bs_cli_ap_from}/lib" "${__bs_cli_ap_from}/bs" "${__bs_cli_ap_tmp}/"; then
    bs_cli_update_rollback "${__bs_cli_ap_target}" "${__bs_cli_ap_tmp}" "${__bs_cli_ap_old}" "${UPDATE_INF_SUDO}"
    UPDATE_INF_TARGET=""
    return 1
  fi
  # shebang bs и обёртки — под эту машину (Termux: нет /usr/bin/env, /bin/sh)
  # the shebang of bs and of the wrapper — for this machine (Termux: no /usr/bin/env, /bin/sh)
  bs_cli_update_fix_shebang "${__bs_cli_ap_tmp}/bs" "${__bs_cli_ap_sudo}" \
    || bs_cli_update_warn "update: не удалось подогнать shebang у ${__bs_cli_ap_tmp}/bs / could not adapt the shebang"
  __bs_cli_ap_wrapper="$(bs_cli_update_install_wrapper "${__bs_cli_ap_target}")"
  if [ -n "${__bs_cli_ap_wrapper}" ] && [ -f "${__bs_cli_ap_wrapper}" ]; then
    bs_cli_update_fix_shebang "${__bs_cli_ap_wrapper}" "${__bs_cli_ap_sudo}" \
      || bs_cli_update_warn "update: не удалось подогнать shebang у обёртки ${__bs_cli_ap_wrapper} / could not adapt the wrapper shebang"
  fi
  __bs_cli_ap_ok=1
  for __bs_cli_ap_part in bs bootstrap core lib; do
    if [ "${__bs_cli_ap_part}" = "bs" ]; then
      if [ -e "${__bs_cli_ap_target}/bs" ]; then
        ${__bs_cli_ap_sudo} cp -a -- "${__bs_cli_ap_target}/bs" "${__bs_cli_ap_old}/bs" || { __bs_cli_ap_ok=0; break; }
      else
        ${__bs_cli_ap_sudo} touch -- "${__bs_cli_ap_old}/.added-bs" || { __bs_cli_ap_ok=0; break; }
      fi
      ${__bs_cli_ap_sudo} mv -f -- "${__bs_cli_ap_tmp}/bs" "${__bs_cli_ap_target}/bs" || { __bs_cli_ap_ok=0; break; }
    else
      if [ -e "${__bs_cli_ap_target}/${__bs_cli_ap_part}" ]; then
        ${__bs_cli_ap_sudo} mv -- "${__bs_cli_ap_target}/${__bs_cli_ap_part}" "${__bs_cli_ap_old}/${__bs_cli_ap_part}" || { __bs_cli_ap_ok=0; break; }
      else
        ${__bs_cli_ap_sudo} touch -- "${__bs_cli_ap_old}/.added-${__bs_cli_ap_part}" || { __bs_cli_ap_ok=0; break; }
      fi
      ${__bs_cli_ap_sudo} mv -- "${__bs_cli_ap_tmp}/${__bs_cli_ap_part}" "${__bs_cli_ap_target}/${__bs_cli_ap_part}" || { __bs_cli_ap_ok=0; break; }
    fi
  done
  if [ "${__bs_cli_ap_ok}" -eq 0 ]; then
    bs_cli_update_rollback "${__bs_cli_ap_target}" "${__bs_cli_ap_tmp}" "${__bs_cli_ap_old}" "${UPDATE_INF_SUDO}"
    UPDATE_INF_TARGET=""
    return 1
  fi
  if ! bs_cli_update_smoke "${__bs_cli_ap_target}" "${__bs_cli_ap_want}"; then
    bs_cli_update_rollback "${__bs_cli_ap_target}" "${__bs_cli_ap_tmp}" "${__bs_cli_ap_old}" "${UPDATE_INF_SUDO}"
    UPDATE_INF_TARGET=""
    return 2
  fi
  ${__bs_cli_ap_sudo} touch -- "${__bs_cli_ap_old}/.committed" || true
  UPDATE_INF_TARGET=""
  ${__bs_cli_ap_sudo} rm -rf -- "${__bs_cli_ap_tmp}" "${__bs_cli_ap_old}" || true
  return 0
}

# @private Обновить манифест установки после update: дата, источник, коммит.
# Нет манифеста (старый установщик) — создаётся; повреждённый — сохраняется
# как .install.bad и создаётся заново.
# @private Refresh the install manifest after an update: date, source,
# commit. A missing manifest (older installer) is created; a corrupt one is
# kept as .install.bad and recreated.
# @param $1 Install directory / Каталог установки
# @param $2 Source directory / Каталог-источник
# @param $3 Source label (path or URL@ref) / Метка источника
# @param $4 Optional "sudo" / Необязательный sudo
bs_cli_update_manifest() {
  __bs_cli_mf_target=$1
  __bs_cli_mf_from=$2
  __bs_cli_mf_label=$3
  __bs_cli_mf_sudo=${4:-}
  __bs_cli_mf_file="${__bs_cli_mf_target}/.install"
  __bs_cli_mf_content=""
  __bs_cli_mf_commit=""
  if [ -d "${__bs_cli_mf_file}" ]; then
    bs_cli_update_warn "update: ${__bs_cli_mf_file} — каталог, манифест не записан / is a directory, manifest not written"
    return 0
  fi
  if bs_cli_update_manifest_valid "${__bs_cli_mf_file}"; then
    while IFS= read -r __bs_cli_mf_line || [ -n "${__bs_cli_mf_line}" ]; do
      case "${__bs_cli_mf_line}" in
        version=*|updated_at=*|updated_from=*|updated_commit=*) ;;
        *) __bs_cli_mf_content="${__bs_cli_mf_content}${__bs_cli_mf_line}${BS_CLI_NL}" ;;
      esac
    done < "${__bs_cli_mf_file}"
  else
    if [ -e "${__bs_cli_mf_file}" ]; then
      ${__bs_cli_mf_sudo} mv -f -- "${__bs_cli_mf_file}" "${__bs_cli_mf_file}.bad" 2>/dev/null || ${__bs_cli_mf_sudo} rm -f -- "${__bs_cli_mf_file}" || true
      bs_cli_update_warn "update: манифест повреждён или нечитаем, создан заново (старый: ${__bs_cli_mf_file}.bad) / manifest corrupt or unreadable, recreated (old one: ${__bs_cli_mf_file}.bad)"
    fi
    __bs_cli_mf_mode="custom"
    if [ "${__bs_cli_mf_target}" = "${HOME}/.local/lib/bs" ]; then __bs_cli_mf_mode="local"; fi
    if [ "${__bs_cli_mf_target}" = "$(bs_cli_update_system_lib)" ]; then __bs_cli_mf_mode="system"; fi
    __bs_cli_mf_content="${__bs_cli_mf_content}# BS install manifest — written by install.sh, updated by bs update${BS_CLI_NL}"
    __bs_cli_mf_content="${__bs_cli_mf_content}mode=${__bs_cli_mf_mode}${BS_CLI_NL}"
    __bs_cli_mf_content="${__bs_cli_mf_content}prefix=${__bs_cli_mf_target%/lib/bs}${BS_CLI_NL}"
    __bs_cli_mf_content="${__bs_cli_mf_content}lib=${__bs_cli_mf_target}${BS_CLI_NL}"
    __bs_cli_mf_content="${__bs_cli_mf_content}bin=${__bs_cli_mf_target%/lib/bs}/bin/bs${BS_CLI_NL}"
  fi
  if bs_utils_has git && [ -e "${__bs_cli_mf_from}/.git" ]; then
    __bs_cli_mf_commit="$(git -C "${__bs_cli_mf_from}" rev-parse HEAD 2>/dev/null)" || __bs_cli_mf_commit=""
  fi
  # Версия ИСТОЧНИКА, а не запущенного bs / the SOURCE version, not the running bs
  __bs_cli_mf_version="$(bs_version_of "${__bs_cli_mf_from}")"
  if [ -z "${__bs_cli_mf_version}" ]; then __bs_cli_mf_version="$(bs_version_get)"; fi
  __bs_cli_mf_content="${__bs_cli_mf_content}version=${__bs_cli_mf_version}${BS_CLI_NL}"
  __bs_cli_mf_content="${__bs_cli_mf_content}updated_at=$(date '+%Y-%m-%d %H:%M:%S')${BS_CLI_NL}"
  __bs_cli_mf_content="${__bs_cli_mf_content}updated_from=${__bs_cli_mf_label}${BS_CLI_NL}"
  __bs_cli_mf_content="${__bs_cli_mf_content}updated_commit=${__bs_cli_mf_commit}${BS_CLI_NL}"
  printf '%s' "${__bs_cli_mf_content}" | ${__bs_cli_mf_sudo} tee -- "${__bs_cli_mf_file}" >/dev/null \
    || bs_cli_update_warn "update: cannot write the install manifest: ${__bs_cli_mf_file}"
  return 0
}

# @private Кто из обёрток `bs` в PATH что запускает (по порядку PATH).
# @private Which `bs` wrapper in PATH runs which copy (in PATH order).
bs_cli_update_path_summary() {
  printf 'bs в PATH по порядку / bs in PATH, in order:\n'
  bs_cli_path_hits bs_cli_ps_hits "${PATH}"
  __bs_cli_ps_n=$(bs_arr_len bs_cli_ps_hits)
  __bs_cli_ps_i=0
  while [ "${__bs_cli_ps_i}" -lt "${__bs_cli_ps_n}" ]; do
    __bs_cli_ps_w=''
    bs_arr_get bs_cli_ps_hits "${__bs_cli_ps_i}" __bs_cli_ps_w
    __bs_cli_ps_i=$((__bs_cli_ps_i + 1))
    __bs_cli_ps_root="$(bs_cli_update_wrapper_root "${__bs_cli_ps_w}")"
    if [ -n "${__bs_cli_ps_root}" ]; then
      __bs_cli_ps_first=""
      if [ "${__bs_cli_ps_i}" -eq 1 ]; then __bs_cli_ps_first=' ← запускается первой / runs first'; fi
      printf '  %d. %s → %s (version %s)%s\n' "${__bs_cli_ps_i}" "${__bs_cli_ps_w}" "${__bs_cli_ps_root}" \
        "$(bs_version_of "${__bs_cli_ps_root}")" "${__bs_cli_ps_first}"
    else
      printf '  %d. %s (не обёртка BS / not a BS wrapper)\n' "${__bs_cli_ps_i}" "${__bs_cli_ps_w}"
    fi
  done
  if [ "${__bs_cli_ps_n}" -eq 0 ]; then printf '  (bs не найден в PATH / bs not found in PATH)\n'; fi
  return 0
}

# @private Можно ли безопасно подтянуть репозиторий: это git-репозиторий, в нём
# нет незакоммиченных правок отслеживаемых файлов и у ветки есть upstream.
# Печатает причину отказа (одной строкой) и возвращает 1, если нельзя.
# @private Can the repository be pulled safely: a git repository, no uncommitted
# changes to tracked files, and the branch has an upstream. Prints the reason
# (one line) and returns 1 when it cannot.
# @param $1 Repository / Репозиторий
bs_cli_update_pull_blocker() {
  if ! bs_utils_has git || [ ! -e "$1/.git" ]; then
    printf 'не git-репозиторий (или нет git) / not a git repository (or no git)'
    return 1
  fi
  if [ -n "$(git -C "$1" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    printf 'есть незакоммиченные правки отслеживаемых файлов / uncommitted changes to tracked files'
    return 1
  fi
  if ! git -C "$1" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    printf 'у текущей ветки нет upstream (detached HEAD?) / the current branch has no upstream'
    return 1
  fi
  return 0
}

# @private git pull --ff-only в репозитории: только перемотка вперёд, история
# не переписывается, ничего не сливается. Возвращает 1 с объяснением при отказе.
# @private git pull --ff-only in the repository: a fast-forward only, history
# is never rewritten, nothing is merged. Returns 1 with an explanation on refusal.
# @param $1 Repository / Репозиторий
bs_cli_update_pull_checkout() {
  __bs_cli_pc_dir=$1
  if ! __bs_cli_pc_why="$(bs_cli_update_pull_blocker "${__bs_cli_pc_dir}")"; then
    bs_cli_update_warn "update: git pull пропущен для ${__bs_cli_pc_dir}: ${__bs_cli_pc_why}"
    return 1
  fi
  __bs_cli_pc_before="$(git -C "${__bs_cli_pc_dir}" rev-parse --short=7 HEAD 2>/dev/null || printf '?')"
  if ! __bs_cli_pc_out="$(GIT_TERMINAL_PROMPT=0; export GIT_TERMINAL_PROMPT; bs_cli_with_timeout 120 git -C "${__bs_cli_pc_dir}" pull --ff-only 2>&1)"; then
    bs_cli_update_warn "update: git pull --ff-only не удался в ${__bs_cli_pc_dir} (история разошлась или нет сети) / failed (diverged history or no network): $(bs_str_replace "${__bs_cli_pc_out}" "${BS_CLI_NL}" ' | ')"
    return 1
  fi
  __bs_cli_pc_after="$(git -C "${__bs_cli_pc_dir}" rev-parse --short=7 HEAD 2>/dev/null || printf '?')"
  if [ "${__bs_cli_pc_before}" = "${__bs_cli_pc_after}" ]; then
    bs_log_info "update: репозиторий уже актуален / the repository is already up to date: ${__bs_cli_pc_dir} @ ${__bs_cli_pc_after}"
  else
    bs_log_info "update: репозиторий подтянут / the repository was pulled: ${__bs_cli_pc_dir} ${__bs_cli_pc_before} → ${__bs_cli_pc_after}"
  fi
  return 0
}

# @private Итог по трём сущностям: установка, репозиторий, GitHub. Расхождение
# между установкой и репозиторием (examples/ и tests/ старее bs) раньше никак
# не показывалось — отсюда «обновил, а флага нет».
# @private The outcome for the three things: the install, the repository and
# GitHub. A mismatch between the install and the repository (examples/ and
# tests/ older than bs) used to go unnoticed — hence "updated, yet no flag".
# @param $1 Repository around (may be empty) / Репозиторий рядом (может быть пуст)
# @param $2 Its relation to the remote: same|ahead|behind|unknown / Отношение к удалённому
# @param $3 Version that was installed / Установленная версия
bs_cli_update_state_summary() {
  __bs_cli_ss_checkout=$1
  __bs_cli_ss_state=$2
  __bs_cli_ss_inst=$3
  if [ -z "${__bs_cli_ss_checkout}" ]; then return 0; fi
  __bs_cli_ss_commit=""
  __bs_cli_ss_ok=1
  __bs_cli_ss_rc=0
  __bs_cli_ss_repo="$(bs_version_of "${__bs_cli_ss_checkout}")"
  if [ -e "${__bs_cli_ss_checkout}/.git" ] && bs_utils_has git; then
    __bs_cli_ss_commit="$(git -C "${__bs_cli_ss_checkout}" rev-parse --short=7 HEAD 2>/dev/null || true)"
  fi
  case "${__bs_cli_ss_state}" in
    same)   __bs_cli_ss_rel="совпадает с GitHub / same as GitHub" ;;
    ahead)  __bs_cli_ss_rel="впереди GitHub (есть непушенные коммиты) / ahead of GitHub" ;;
    behind) __bs_cli_ss_rel="ОТСТАЁТ от GitHub / BEHIND GitHub"; __bs_cli_ss_ok=0 ;;
    *)      __bs_cli_ss_rel="связь с GitHub не проверена (нет сети?) / relation to GitHub unknown" ;;
  esac
  if [ -n "${__bs_cli_ss_inst}" ] && [ -n "${__bs_cli_ss_repo}" ]; then
    bs_version_compare "${__bs_cli_ss_repo}" "${__bs_cli_ss_inst}" || __bs_cli_ss_rc=$?
    if [ "${__bs_cli_ss_rc}" -eq 2 ]; then __bs_cli_ss_ok=0; fi
  fi
  __bs_cli_ss_cm=""
  if [ -n "${__bs_cli_ss_commit}" ]; then __bs_cli_ss_cm=", commit ${__bs_cli_ss_commit}"; fi
  printf '\n== Состояние после обновления / State after the update ==\n'
  printf '  Установка / Install:   версия / version %s\n' "${__bs_cli_ss_inst:-?}"
  printf '  Репозиторий / Repo:    %s — версия / version %s%s — %s\n' \
    "${__bs_cli_ss_checkout}" "${__bs_cli_ss_repo:-?}" "${__bs_cli_ss_cm}" "${__bs_cli_ss_rel}"
  if [ "${__bs_cli_ss_ok}" -eq 1 ]; then
    printf '  Вердикт / Verdict:     установка и репозиторий согласованы / the install and the repository agree\n'
  else
    printf '  Вердикт / Verdict:     ⚠ examples/ и tests/ репозитория старее установки (bs update их не копирует) / the repository is older than the install\n'
    printf '  Что сделать / Fix:     bs update --pull   (или / or:  git -C %s pull)\n' "${__bs_cli_ss_checkout}"
  fi
}

# @private Дописать в конец массива $1 все элементы массива $2.
# @private Append every element of the array $2 to the end of the array $1.
# @param $1 Destination / назначение; $2 source / источник
bs_cli_arr_append() {
  __bs_cli_aa_dst=$1
  eval "$(bs_arr_to_args "$2")"
  bs_arr_push "${__bs_cli_aa_dst}" "$@"
}

# shellcheck disable=SC2016  # $BS_SYSTEM_PREFIX и обратные кавычки — текст справки / $BS_SYSTEM_PREFIX and backticks are help text
bs_cli_update_help() {
  printf 'Использование / Usage: bs update [--local] [--system] [--lib DIR]\n'
  printf '                 [--from DIR | --github [--repo URL] [--ref REF]] [-v]\n\n'
  printf 'Применяет изменения фреймворка к установленным копиям, без переустановки.\n'
  printf 'Applies framework changes to installed copies without reinstalling.\n'
  printf 'Targets / Цели:\n'
  printf '  --local   ~/.local/lib/bs                (local install / локальная)\n'
  printf '  --system  $BS_SYSTEM_PREFIX/lib/bs       (system install, default prefix /usr/local, needs root)\n'
  printf '  --lib DIR a custom install directory / свой каталог установки\n'
  printf '            (flags may be combined and repeated; duplicates are merged)\n'
  printf 'Source / Источник:\n'
  printf '  --from DIR  local repo checkout / локальный репозиторий\n'
  printf '  --pull      first fast-forward the local repo (git pull --ff-only): bs update does\n'
  printf '              not touch the repository, so examples/ and tests/ stay old without it\n'
  printf '              / сначала подтянуть локальный репозиторий; examples/ иначе не обновятся\n'
  printf '  --github    download from GitHub (%s)\n' "${UPDATE_DEFAULT_REPO}"
  printf '  --repo URL  another repository (or BS_UPDATE_REPO); implies --github\n'
  printf '  --ref REF   branch or tag (default: main); implies --github\n'
  printf 'Default source: the repo in CWD (./bs update); from an installed copy\n'
  printf 'with no repo around — GitHub. A local git checkout is compared with\n'
  printf 'GitHub first (non-interactive: warns, uses local).\n'
  printf 'Without target flags: every detected install — ~/.local/lib/bs, the\n'
  printf 'system one, the copy bs runs from, the one behind `bs` in PATH.\n'
  printf 'Safety / Безопасность:\n'
  printf '  - the target must be a BS install (bs + bootstrap/init.sh, or .install);\n'
  printf '    a source checkout (.git / tests/) is never a target\n'
  printf '    цель обязана быть установкой BS, чужие каталоги не трогаются\n'
  printf '  - the source must have bs, bootstrap/{init,loader}.sh, core/, lib/ and a\n'
  printf '    readable core/version.sh; checked BEFORE any write\n'
  printf '  - old files are kept aside, the new copy is smoke-tested (bs version),\n'
  printf '    on failure or Ctrl-C the previous version is restored\n'
  printf '  - two updates of one target do not run at once (lock)\n'
  printf 'Every notice shows which bs copy printed it: "Запущен / Running: bs VER | ROOT | KIND".\n'
  printf 'Environment: BS_SYSTEM_PREFIX (default /usr/local) — system install prefix\n'
  printf '(lib=$BS_SYSTEM_PREFIX/lib/bs, wrapper=$BS_SYSTEM_PREFIX/bin/bs);\n'
  printf 'BS_UPDATE_REPO — default repository for --github.\n'
  printf 'Exit code: 0 updated / nothing to do; 1 a target or the source was refused or failed.\n'
}

# bs update: применить изменения фреймворка к установленным копиям / apply framework changes to installed copies
bs_cli_update_cmd() {
  __bs_cli_uc_from=${BS_ROOT}
  __bs_cli_uc_from_explicit=0
  __bs_cli_uc_github=0
  __bs_cli_uc_pull=0
  __bs_cli_uc_repo=${BS_UPDATE_REPO:-${UPDATE_DEFAULT_REPO}}
  __bs_cli_uc_repo_set=0
  __bs_cli_uc_ref_set=0
  __bs_cli_uc_ref=main
  bs_arr_clear bs_cli_uc_targets
  bs_arr_clear bs_cli_uc_kinds
  __bs_cli_uc_explicit=0
  __bs_cli_uc_verbose=0
  __bs_cli_uc_banner=1
  for __bs_cli_uc_a in "$@"; do
    case "${__bs_cli_uc_a}" in
      -h|--help) __bs_cli_uc_banner=0 ;;
    esac
  done
  bs_cli_update_ctx
  # Первая строка любого реального запуска: какая копия bs работает.
  # First line of every real run: which bs copy is running.
  if [ "${__bs_cli_uc_banner}" -eq 1 ]; then
    printf '%s\n' "${UPDATE_RUN_BLOCK}"
  fi
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  bs_cleanup_add bs_cli_update_inflight_cleanup

  while [ $# -gt 0 ]; do
    case "${1:-}" in
      --local)
        __bs_cli_uc_explicit=1
        bs_arr_push bs_cli_uc_targets "${HOME}/.local/lib/bs"
        bs_arr_push bs_cli_uc_kinds local
        shift ;;
      --system)
        __bs_cli_uc_explicit=1
        bs_arr_push bs_cli_uc_targets "$(bs_cli_update_system_lib)"
        bs_arr_push bs_cli_uc_kinds system
        shift ;;
      --lib)
        shift
        bs_cli_update_flag_value "--lib" "a target directory" "$@"
        __bs_cli_uc_explicit=1
        bs_arr_push bs_cli_uc_targets "$1"
        bs_arr_push bs_cli_uc_kinds lib
        shift ;;
      --from)
        shift
        bs_cli_update_flag_value "--from" "a source directory" "$@"
        if [ "${__bs_cli_uc_from_explicit}" -eq 1 ] && [ "${__bs_cli_uc_from}" != "$1" ]; then
          bs_cli_update_die "update: --from указан дважды с разными значениями / given twice with different values: ${__bs_cli_uc_from} и/and $1"
        fi
        __bs_cli_uc_from=$1
        __bs_cli_uc_from_explicit=1
        shift ;;
      --github)
        __bs_cli_uc_github=1
        shift ;;
      --pull)
        __bs_cli_uc_pull=1
        shift ;;
      --repo)
        shift
        bs_cli_update_flag_value "--repo" "a repository URL" "$@"
        case "$1" in
          *[[:space:]]*) bs_cli_update_die "update: --repo не может содержать пробелы / must not contain whitespace: '$1'" ;;
        esac
        if [ "${__bs_cli_uc_repo_set}" -eq 1 ] && [ "${__bs_cli_uc_repo}" != "$1" ]; then
          bs_cli_update_die "update: --repo указан дважды с разными значениями / given twice with different values"
        fi
        __bs_cli_uc_github=1
        __bs_cli_uc_repo=$1
        __bs_cli_uc_repo_set=1
        shift ;;
      --ref)
        shift
        bs_cli_update_flag_value "--ref" "a branch or tag" "$@"
        case "$1" in
          ''|*[!A-Za-z0-9._/@+-]*) bs_cli_update_die "update: недопустимое имя ветки/тега / invalid branch or tag name: '$1'" ;;
        esac
        if [ "${__bs_cli_uc_ref_set}" -eq 1 ] && [ "${__bs_cli_uc_ref}" != "$1" ]; then
          bs_cli_update_die "update: --ref указан дважды с разными значениями / given twice with different values"
        fi
        __bs_cli_uc_github=1
        __bs_cli_uc_ref=$1
        __bs_cli_uc_ref_set=1
        shift ;;
      -v|--verbose)
        __bs_cli_uc_verbose=1
        shift ;;
      -h|--help)
        bs_cli_update_help
        return 0 ;;
      *)
        bs_cli_update_die "update: неизвестный аргумент / unknown argument: $1 (bs update --help)" ;;
    esac
  done

  # Источник: --from и --github исключают друг друга.
  # Source: --from and --github are mutually exclusive.
  if [ "${__bs_cli_uc_github}" -eq 1 ] && [ "${__bs_cli_uc_from_explicit}" -eq 1 ]; then
    bs_cli_update_die "update: --from и --github несовместимы / are mutually exclusive"
  fi
  # Локальный checkout рядом (для сверки с GitHub): CWD-репозиторий, иначе
  # BS_ROOT, если это репозиторий, а не установленная копия (в ней нет tests/).
  # Local checkout around (to compare with GitHub): the CWD repo, else BS_ROOT
  # when it is a repo and not an installed copy (which has no tests/).
  __bs_cli_uc_checkout=""
  if [ "${__bs_cli_uc_from_explicit}" -eq 1 ]; then
    __bs_cli_uc_checkout=${__bs_cli_uc_from}
  elif [ -f "${PWD}/bs" ] && [ -d "${PWD}/core" ] && [ -d "${PWD}/tests" ]; then
    __bs_cli_uc_checkout=${PWD}
  elif [ -d "${__bs_cli_uc_from}/tests" ]; then
    __bs_cli_uc_checkout=${__bs_cli_uc_from}
  fi

  if [ "${__bs_cli_uc_github}" -eq 0 ] && [ "${__bs_cli_uc_from_explicit}" -eq 0 ]; then
    if [ -n "${__bs_cli_uc_checkout}" ]; then
      __bs_cli_uc_from=${__bs_cli_uc_checkout}
    else
      # Развилка: bs запущен из установленной копии и репозитория рядом
      # нет — локального источника нет, берём с GitHub.
      # Fork: bs runs from an installed copy and there is no repo around —
      # no local source, so fetch from GitHub.
      __bs_cli_uc_github=1
    fi
  fi

  # Конфликт источников: локальный checkout и GitHub могут расходиться.
  # Source conflict: the local checkout and GitHub may differ.
  __bs_cli_uc_state="unknown"
  # --pull: сначала подтянуть сам репозиторий (bs update его не трогает)
  # --pull: first pull the repository itself (bs update does not touch it)
  if [ "${__bs_cli_uc_pull}" -eq 1 ]; then
    if [ -z "${__bs_cli_uc_checkout}" ]; then
      bs_cli_update_die "update: --pull: рядом нет репозитория BS — запустите из его каталога или укажите --from DIR / no BS repository around: run from its directory or pass --from DIR"
    fi
    bs_cli_update_pull_checkout "${__bs_cli_uc_checkout}" \
      || bs_cli_update_die "update: --pull не выполнен, ничего не изменено / --pull failed, nothing was changed"
  fi
  if [ -n "${__bs_cli_uc_checkout}" ]; then
    __bs_cli_uc_state="$(bs_cli_update_local_state "${__bs_cli_uc_checkout}" "${__bs_cli_uc_repo}" "${__bs_cli_uc_ref}")"
  fi
  if [ "${__bs_cli_uc_github}" -eq 0 ] && [ "${__bs_cli_uc_state}" = "behind" ]; then
    bs_cli_update_warn "update: local repo is behind ${__bs_cli_uc_repo%.git}@${__bs_cli_uc_ref} — it lacks new code / локальный репозиторий отстаёт от GitHub"
    bs_cli_update_warn "update:   ${__bs_cli_uc_checkout}"
    if [ "${__bs_cli_uc_from_explicit}" -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
      __bs_cli_uc_answer=""
      __bs_cli_uc_why=""
      __bs_cli_uc_dflt="p"
      __bs_cli_uc_why="$(bs_cli_update_pull_blocker "${__bs_cli_uc_checkout}")" || __bs_cli_uc_dflt="g"
      if [ "${__bs_cli_uc_dflt}" = "g" ]; then
        printf 'Подтянуть репозиторий нельзя: %s / cannot pull: %s\n' "${__bs_cli_uc_why}" "${__bs_cli_uc_why}"
        printf 'Источник / Source: [g]ithub · [l]ocal · [a]bort? [%s] ' "$(bs_cli_paint cmd "${__bs_cli_uc_dflt}")"
      else
        printf 'Источник / Source: [p]ull (рекомендуется / recommended) · [g]ithub · [l]ocal · [a]bort? [%s] ' "$(bs_cli_paint cmd "${__bs_cli_uc_dflt}")"
      fi
      read -r __bs_cli_uc_answer || __bs_cli_uc_answer="a"
      if [ -z "${__bs_cli_uc_answer}" ]; then __bs_cli_uc_answer=${__bs_cli_uc_dflt}; fi
      case "$(bs_str_lower "${__bs_cli_uc_answer}")" in
        p|pull)
          bs_cli_update_pull_checkout "${__bs_cli_uc_checkout}" \
            || bs_cli_update_die "update: git pull не удался, ничего не изменено / git pull failed, nothing was changed"
          __bs_cli_uc_state="$(bs_cli_update_local_state "${__bs_cli_uc_checkout}" "${__bs_cli_uc_repo}" "${__bs_cli_uc_ref}")" ;;
        g|github) __bs_cli_uc_github=1 ;;
        l|local)  : ;;
        *)        bs_cli_update_die "update: aborted / отменено" ;;
      esac
    else
      bs_cli_update_warn "update: installing the LOCAL code; for the newest run: bs update --pull (или / or git pull), or bs update --github"
    fi
  fi
  if [ "${__bs_cli_uc_github}" -eq 1 ] && [ "${__bs_cli_uc_state}" = "behind" ]; then
    # bs update ставит только bs, bootstrap, core, lib: examples/ и tests/
    # репозитория остаются прежними — это не ошибка, но об этом нужно сказать
    # bs update installs bs, bootstrap, core and lib only: examples/ and
    # tests/ of the repository stay as they are — not an error, but say so
    bs_cli_update_warn "update: репозиторий ${__bs_cli_uc_checkout} отстаёт от GitHub и НЕ обновлён (bs update ставит только bs, bootstrap, core, lib; examples/ и tests/ не затрагиваются). Обновить репозиторий: bs update --pull (или git -C ${__bs_cli_uc_checkout} pull) / the repository is behind GitHub and was NOT updated (examples/ and tests/ are not touched)"
  fi
  if [ "${__bs_cli_uc_github}" -eq 1 ] && [ -n "${__bs_cli_uc_checkout}" ]; then
    if [ "${__bs_cli_uc_state}" = "ahead" ]; then
      bs_cli_update_warn "update: local repo has commits not pushed to ${__bs_cli_uc_repo%.git}@${__bs_cli_uc_ref} — GitHub lacks them / на GitHub нет локальных коммитов: ${__bs_cli_uc_checkout}"
    fi
    if bs_utils_has git && [ -e "${__bs_cli_uc_checkout}/.git" ] \
       && [ -n "$(git -C "${__bs_cli_uc_checkout}" status --porcelain -- bs bootstrap core lib 2>/dev/null)" ]; then
      bs_cli_update_warn "update: local repo has uncommitted changes — they are NOT installed from GitHub / незакоммиченные правки не попадут в установку: ${__bs_cli_uc_checkout}"
    fi
  fi

  # Запуск от root/sudo: ~ — каталог root, а не пользователя.
  # Run as root/sudo: ~ is root's home, not the user's.
  if [ "${__bs_cli_uc_explicit}" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    __bs_cli_uc_sudo_home="$(bs_cli_update_sudo_home)"
    if [ -n "${__bs_cli_uc_sudo_home}" ] && [ "${__bs_cli_uc_sudo_home}" != "${HOME}" ] && bs_cli_update_is_install "${__bs_cli_uc_sudo_home}/.local/lib/bs"; then
      bs_log_info "update: запущено через sudo: ~ = ${HOME}. Локальная установка ${SUDO_USER} (${__bs_cli_uc_sudo_home}/.local/lib/bs) не затронута — обновите её без sudo: bs update --local / run via sudo: its local install is untouched"
    fi
  fi

  # Детект установок: стандартные каталоги, установленная копия, из которой
  # запущен bs, и каталог из обёртки `bs` в PATH (нестандартный --lib).
  # Detect installs: the standard directories, the installed copy bs runs
  # from, and the directory named by the `bs` wrapper in PATH (custom --lib).
  if [ "${__bs_cli_uc_explicit}" -eq 0 ]; then
    bs_arr_new bs_cli_uc_found "${HOME}/.local/lib/bs" "$(bs_cli_update_system_lib)"
    if [ ! -d "${BS_ROOT}/tests" ]; then bs_arr_push bs_cli_uc_found "${BS_ROOT}"; fi
    bs_cli_path_hits bs_cli_uc_hits "${PATH}"
    eval "$(bs_arr_to_args bs_cli_uc_hits)"
    for __bs_cli_uc_wrapper in "$@"; do
      __bs_cli_uc_wroot="$(bs_cli_update_wrapper_root "${__bs_cli_uc_wrapper}")"
      if [ -z "${__bs_cli_uc_wroot}" ]; then continue; fi
      if [ ! -d "${__bs_cli_uc_wroot}" ]; then
        # Сломанная обёртка: раньше молча игнорировалась / was silently ignored
        bs_cli_update_warn "update: обёртка ${__bs_cli_uc_wrapper} указывает на несуществующий ${__bs_cli_uc_wroot} — переустановите или удалите её / the wrapper points to a missing directory — reinstall or delete it"
        continue
      fi
      bs_arr_push bs_cli_uc_found "${__bs_cli_uc_wroot}"
    done
    bs_arr_clear bs_cli_uc_seen
    eval "$(bs_arr_to_args bs_cli_uc_found)"
    for __bs_cli_uc_dir in "$@"; do
      __bs_cli_uc_dir=${__bs_cli_uc_dir%/}
      if [ ! -d "${__bs_cli_uc_dir}" ]; then continue; fi
      if [ "${__bs_cli_uc_dir}" = "${__bs_cli_uc_checkout%/}" ]; then continue; fi
      if bs_arr_contains bs_cli_uc_seen "${__bs_cli_uc_dir}"; then continue; fi
      bs_arr_push bs_cli_uc_seen "${__bs_cli_uc_dir}"
      bs_arr_push bs_cli_uc_targets "${__bs_cli_uc_dir}"
      bs_arr_push bs_cli_uc_kinds auto
    done
  fi

  if [ "$(bs_arr_len bs_cli_uc_targets)" -eq 0 ]; then
    bs_cli_update_box "BS НЕ УСТАНОВЛЕНА / BS NOT INSTALLED" \
      "Установок BS не найдено / no BS installs found." \
      "" \
      "Установите / Install:" \
      "  ./install.sh --local        (для себя / for you)" \
      "  sudo ./install.sh           (для всех / system-wide)" \
      "или укажите каталог / or point to one: bs update --lib DIR"
    exit 1
  fi
  __bs_cli_uc_label=${__bs_cli_uc_from}
  if [ "${__bs_cli_uc_github}" -eq 1 ]; then
    __bs_cli_uc_label="${__bs_cli_uc_repo%.git}@${__bs_cli_uc_ref}"
    bs_log_info "fetching ${__bs_cli_uc_label}"
    bs_cli_update_fetch "${__bs_cli_uc_repo}" "${__bs_cli_uc_ref}"
    __bs_cli_uc_from="${UPDATE_FETCH_DIR}/src"
  fi
  # Источник проверяется ДО любых записей в цели.
  # The source is verified BEFORE anything is written to a target.
  bs_arr_from_lines bs_cli_uc_srcmiss "$(bs_cli_update_source_missing "${__bs_cli_uc_from}")"
  if [ "$(bs_arr_len bs_cli_uc_srcmiss)" -gt 0 ]; then
    bs_arr_new bs_cli_uc_lines "Источник не годится / unusable source: ${__bs_cli_uc_label}" "Не хватает / missing:"
    eval "$(bs_arr_to_args bs_cli_uc_srcmiss)"
    for __bs_cli_uc_m in "$@"; do bs_arr_push bs_cli_uc_lines "  • ${__bs_cli_uc_m}"; done
    bs_arr_push bs_cli_uc_lines "" "Ничего не изменено / nothing was changed." \
      "Нужен репозиторий BS: bs, bootstrap/{init,loader}.sh, core/, lib/ / a BS repository is required"
    eval "$(bs_arr_to_args bs_cli_uc_lines)"
    bs_cli_update_box "ИСТОЧНИК НЕ ПОДХОДИТ / INVALID SOURCE" "$@"
    exit 1
  fi
  __bs_cli_uc_from_real="$(bs_cli_update_realpath "${__bs_cli_uc_from}")"

  __bs_cli_uc_ok=0
  __bs_cli_uc_new_ver="$(bs_version_of "${__bs_cli_uc_from}")"
  bs_arr_clear bs_cli_uc_same
  bs_arr_clear bs_cli_uc_miss
  bs_arr_clear bs_cli_uc_ro
  bs_arr_clear bs_cli_uc_uptodate
  bs_arr_clear bs_cli_uc_bad
  bs_arr_clear bs_cli_uc_fail
  bs_arr_clear bs_cli_uc_done
  __bs_cli_uc_seen_real="|"
  __bs_cli_uc_count=$(bs_arr_len bs_cli_uc_targets)
  __bs_cli_uc_idx=0
  while [ "${__bs_cli_uc_idx}" -lt "${__bs_cli_uc_count}" ]; do
    __bs_cli_uc_raw=''
    __bs_cli_uc_kind=''
    bs_arr_get bs_cli_uc_targets "${__bs_cli_uc_idx}" __bs_cli_uc_raw
    bs_arr_get bs_cli_uc_kinds "${__bs_cli_uc_idx}" __bs_cli_uc_kind
    __bs_cli_uc_idx=$((__bs_cli_uc_idx + 1))
    __bs_cli_uc_tin=${__bs_cli_uc_raw%/}
    if [ -z "${__bs_cli_uc_tin}" ]; then __bs_cli_uc_tin="/"; fi
    if [ ! -d "${__bs_cli_uc_tin}" ]; then
      if [ -e "${__bs_cli_uc_tin}" ]; then
        bs_arr_push bs_cli_uc_bad "• ${__bs_cli_uc_tin} — это не каталог / not a directory"
      else
        bs_cli_push_lines bs_cli_uc_miss "$(bs_cli_update_missing_lines "${__bs_cli_uc_tin}" "${__bs_cli_uc_kind}")"
      fi
      continue
    fi
    __bs_cli_uc_target="$(bs_cli_update_realpath "${__bs_cli_uc_tin}")"
    case "${__bs_cli_uc_seen_real}" in
      *"|${__bs_cli_uc_target}|"*) continue ;;
    esac
    __bs_cli_uc_seen_real="${__bs_cli_uc_seen_real}${__bs_cli_uc_target}|"
    if [ -L "${__bs_cli_uc_tin}" ]; then
      bs_log_info "update: ${__bs_cli_uc_tin} — символическая ссылка → ${__bs_cli_uc_target} / is a symlink"
    fi
    if [ "${__bs_cli_uc_from_real}" = "${__bs_cli_uc_target}" ]; then
      # В финальную рамку, а не WARN в цикле: «ничего не обновлено» — это
      # не ошибка, а приглашение запустить update из репозитория.
      # Collected for the final box, not a per-target WARN.
      bs_arr_push bs_cli_uc_same "${__bs_cli_uc_target}"
      continue
    fi
    # Защита от чужих каталогов: цель обязана быть установкой BS, иначе
    # rm -rf core/lib/bootstrap стёр бы чужие данные.
    # Guard against foreign directories: the target must be a BS install,
    # else replacing core/lib/bootstrap would erase someone's data.
    if bs_cli_update_is_checkout "${__bs_cli_uc_target}"; then
      bs_arr_push bs_cli_uc_bad "• ${__bs_cli_uc_target} — исходный репозиторий (.git/tests), не установка; не тронут / a source checkout, not an install; left untouched"
      continue
    fi
    if ! bs_cli_update_is_install "${__bs_cli_uc_target}"; then
      bs_arr_push bs_cli_uc_bad "• ${__bs_cli_uc_target} — не установка BS (нет bs + bootstrap/init.sh и нет .install); не тронут / not a BS install; left untouched"
      continue
    fi
    case "${__bs_cli_uc_from_real}" in
      "${__bs_cli_uc_target}"/*)
        bs_arr_push bs_cli_uc_bad "• ${__bs_cli_uc_target} — источник ${__bs_cli_uc_from_real} внутри цели: обновление стёрло бы его / the source is inside the target"
        continue ;;
    esac
    case "${__bs_cli_uc_target}" in
      "${__bs_cli_uc_from_real}"/bootstrap/*|"${__bs_cli_uc_from_real}"/core/*|"${__bs_cli_uc_from_real}"/lib/*)
        bs_arr_push bs_cli_uc_bad "• ${__bs_cli_uc_target} — цель внутри копируемых каталогов источника / the target is inside the source's bootstrap/core/lib"
        continue ;;
    esac
    # Установка без обёртки: bs из PATH её не найдёт.
    # An install without a wrapper: bs from PATH will not find it.
    __bs_cli_uc_wrap_path="$(bs_cli_update_install_wrapper "${__bs_cli_uc_target}")"
    if [ -n "${__bs_cli_uc_wrap_path}" ] && [ ! -e "${__bs_cli_uc_wrap_path}" ]; then
      bs_cli_update_warn "update: у установки ${__bs_cli_uc_target} нет обёртки ${__bs_cli_uc_wrap_path} — команда bs из PATH её не запустит; восстановить: ./install.sh (--local) / no wrapper"
    fi
    # Уже актуально: содержимое совпадает — копировать нечего.
    # Already up to date: identical content — nothing to copy.
    if cmp -s "${__bs_cli_uc_from}/bs" "${__bs_cli_uc_target}/bs" \
       && diff -rq "${__bs_cli_uc_from}/bootstrap" "${__bs_cli_uc_target}/bootstrap" >/dev/null 2>&1 \
       && diff -rq "${__bs_cli_uc_from}/core" "${__bs_cli_uc_target}/core" >/dev/null 2>&1 \
       && diff -rq "${__bs_cli_uc_from}/lib" "${__bs_cli_uc_target}/lib" >/dev/null 2>&1; then
      bs_arr_push bs_cli_uc_uptodate "${__bs_cli_uc_target}"
      continue
    fi
    # Нет прав на запись: в терминале повышаем права через sudo сами; без
    # терминала — только предупреждение.
    # Not writable: in a terminal elevate with sudo ourselves; without one warn.
    __bs_cli_uc_root=""
    if [ ! -w "${__bs_cli_uc_target}" ]; then
      if [ -t 0 ] && bs_utils_has sudo; then
        bs_log_info "update: ${__bs_cli_uc_target} needs root — using sudo / нужны права root"
        __bs_cli_uc_root=sudo
      else
        bs_cli_update_warn "update: target not writable: ${__bs_cli_uc_target} (try: sudo bs update --system)"
        bs_arr_push bs_cli_uc_ro "${__bs_cli_uc_target}"
        continue
      fi
    fi
    __bs_cli_uc_old_ver="$(bs_version_of "${__bs_cli_uc_target}")"
    bs_log_info "syncing ${__bs_cli_uc_label} -> ${__bs_cli_uc_target}" \
      "(version ${__bs_cli_uc_old_ver:-?} → ${__bs_cli_uc_new_ver})"
    # Откат на более старую версию — не ошибка, но о нём стоит сказать вслух
    # Installing an OLDER version is not an error, but worth saying aloud
    if [ -n "${__bs_cli_uc_old_ver}" ]; then
      __bs_cli_uc_rc_cmp=0
      bs_version_compare "${__bs_cli_uc_old_ver}" "${__bs_cli_uc_new_ver}" || __bs_cli_uc_rc_cmp=$?
      if [ "${__bs_cli_uc_rc_cmp}" -eq 1 ]; then
        bs_cli_update_warn "update: DOWNGRADE ${__bs_cli_uc_old_ver} → ${__bs_cli_uc_new_ver} (the source is older than the install): ${__bs_cli_uc_target}"
      fi
    fi
    bs_cli_update_cleanup_stale "${__bs_cli_uc_target}" "${__bs_cli_uc_root}"
    if ! bs_cli_update_lock "${__bs_cli_uc_target}" "${__bs_cli_uc_root}"; then
      bs_arr_push bs_cli_uc_fail "• ${__bs_cli_uc_target} — уже идёт другое обновление этой цели (замок ${__bs_cli_uc_target}/.update-lock); повторите позже / another update of this target is running; retry later"
      continue
    fi
    __bs_cli_uc_rc_apply=0
    bs_cli_update_apply "${__bs_cli_uc_target}" "${__bs_cli_uc_from}" "${__bs_cli_uc_new_ver}" "${__bs_cli_uc_root}" || __bs_cli_uc_rc_apply=$?
    if [ "${__bs_cli_uc_rc_apply}" -eq 1 ]; then
      bs_cli_update_unlock "${__bs_cli_uc_target}"
      bs_cli_update_warn "update: copy failed for ${__bs_cli_uc_target} (нет места/прав?); прежняя версия сохранена / disk full or no permission? the previous version is kept"
      bs_arr_push bs_cli_uc_fail "• ${__bs_cli_uc_target} — копирование не удалось (нет места/прав?); прежняя версия сохранена / copy failed; the previous version is kept"
      continue
    elif [ "${__bs_cli_uc_rc_apply}" -eq 2 ]; then
      bs_cli_update_unlock "${__bs_cli_uc_target}"
      bs_cli_update_warn "update: самопроверка не прошла (bs version), прежняя версия ${__bs_cli_uc_old_ver:-?} восстановлена / smoke test failed, previous version restored: ${__bs_cli_uc_target}"
      bs_arr_push bs_cli_uc_fail "• ${__bs_cli_uc_target} — новая копия не прошла самопроверку; прежняя версия ${__bs_cli_uc_old_ver:-?} восстановлена / new copy failed the smoke test; rolled back"
      continue
    fi
    bs_cli_update_manifest "${__bs_cli_uc_target}" "${__bs_cli_uc_from}" "${__bs_cli_uc_label}" "${__bs_cli_uc_root}"
    bs_cli_update_unlock "${__bs_cli_uc_target}"
    __bs_cli_uc_ok=1
    bs_arr_push bs_cli_uc_done "${__bs_cli_uc_target}: ${__bs_cli_uc_old_ver:-?} → ${__bs_cli_uc_new_ver}"
    if [ "${__bs_cli_uc_verbose}" -eq 1 ]; then
      bs_log_info "  files: $(find "${__bs_cli_uc_from}/core" "${__bs_cli_uc_from}/lib" -name '*.sh' | wc -l) modules copied"
    fi
  done

  bs_arr_clear bs_cli_uc_reasons
  eval "$(bs_arr_to_args bs_cli_uc_same)"
  for __bs_cli_uc_p in "$@"; do
    bs_arr_push bs_cli_uc_reasons "• ${__bs_cli_uc_p} — источник совпадает с целью (bs запущен из этой копии) / source equals target (running from this copy)"
  done
  bs_cli_arr_append bs_cli_uc_reasons bs_cli_uc_miss
  eval "$(bs_arr_to_args bs_cli_uc_ro)"
  for __bs_cli_uc_p in "$@"; do
    bs_arr_push bs_cli_uc_reasons "• ${__bs_cli_uc_p} — нет прав на запись / not writable (try: sudo bs update --system)"
  done
  bs_cli_arr_append bs_cli_uc_reasons bs_cli_uc_bad
  bs_cli_arr_append bs_cli_uc_reasons bs_cli_uc_fail
  eval "$(bs_arr_to_args bs_cli_uc_uptodate)"
  for __bs_cli_uc_p in "$@"; do
    bs_arr_push bs_cli_uc_reasons "• ${__bs_cli_uc_p} — уже актуально / already up to date (version $(bs_version_of "${__bs_cli_uc_p}"))"
  done
  if [ "$(bs_arr_len bs_cli_uc_same)" -gt 0 ]; then
    bs_arr_push bs_cli_uc_reasons \
      "" \
      "Запустите из каталога репозитория / Run from the repo directory:" \
      "  cd <repo> && ./bs update" \
      "или укажите источник / or pass the source:" \
      "  bs update --from <repo-path>" \
      "или обновитесь с GitHub / or update from GitHub:" \
      "  bs update --github"
  fi
  # Отказ: цели, что не удалось обновить. Автопоиск: отказ от чужого/сломанного
  # каталога не считается ошибкой запуска.
  # Failures: targets that could not be updated. In autodetect mode refusing a
  # foreign/broken directory is not a run failure.
  __bs_cli_uc_failures=0
  if [ "$(bs_arr_len bs_cli_uc_miss)" -gt 0 ]; then __bs_cli_uc_failures=1; fi
  __bs_cli_uc_nro=$(bs_arr_len bs_cli_uc_ro)
  __bs_cli_uc_nfail=$(bs_arr_len bs_cli_uc_fail)
  __bs_cli_uc_failures=$((__bs_cli_uc_failures + __bs_cli_uc_nro + __bs_cli_uc_nfail))
  if [ "${__bs_cli_uc_explicit}" -ne 0 ]; then
    __bs_cli_uc_nbad=$(bs_arr_len bs_cli_uc_bad)
    __bs_cli_uc_failures=$((__bs_cli_uc_failures + __bs_cli_uc_nbad))
  fi

  if [ "${__bs_cli_uc_ok}" -eq 1 ]; then
    bs_log_header "UPDATE COMPLETE / ОБНОВЛЕНИЕ ЗАВЕРШЕНО"
    printf '%s\n' "${UPDATE_RUN_BLOCK}"
    eval "$(bs_arr_to_args bs_cli_uc_done)"
    for __bs_cli_uc_p in "$@"; do
      printf '  ✓ %s\n' "${__bs_cli_uc_p}"
    done
    bs_cli_update_path_summary
    bs_cli_update_state_summary "${__bs_cli_uc_checkout}" "${__bs_cli_uc_state}" "${__bs_cli_uc_new_ver}"
    if [ "$(bs_arr_len bs_cli_uc_reasons)" -gt 0 ]; then
      __bs_cli_uc_title="ПРОПУЩЕНО / SKIPPED"
      if [ "${__bs_cli_uc_failures}" -ne 0 ]; then __bs_cli_uc_title="ЧАСТЬ ЦЕЛЕЙ ПРОПУЩЕНА / SOME TARGETS SKIPPED"; fi
      eval "$(bs_arr_to_args bs_cli_uc_reasons)"
      bs_cli_update_box "${__bs_cli_uc_title}" "$@"
    fi
    if [ "${__bs_cli_uc_failures}" -eq 0 ]; then
      bs_log_success "sync done — changes are live without reinstalling"
      return 0
    fi
    bs_cli_update_die "update: часть целей не обновлена / some targets were not updated (см. выше / see above)"
  fi

  # Итоговая рамка вместо сырого ERROR: понятно, что случилось и что делать.
  # A framed summary instead of a raw ERROR: clear what happened and what to do.
  __bs_cli_uc_title="ОБНОВЛЕНИЙ НЕТ / NO UPDATES"
  if [ "${__bs_cli_uc_failures}" -ne 0 ]; then __bs_cli_uc_title="ОБНОВЛЕНИЕ НЕ ВЫПОЛНЕНО / UPDATE NOT DONE"; fi
  eval "$(bs_arr_to_args bs_cli_uc_reasons)"
  bs_cli_update_box "${__bs_cli_uc_title}" "$@"
  if [ "${__bs_cli_uc_failures}" -eq 0 ]; then
    bs_cli_update_state_summary "${__bs_cli_uc_checkout}" "${__bs_cli_uc_state}" "${__bs_cli_uc_new_ver}"
  fi
  if [ "${__bs_cli_uc_failures}" -ne 0 ]; then exit 1; fi
  return 0
}

bs_shell_alias bs_cli_die bs::cli::die
bs_shell_alias bs_cli_help bs::cli::help
bs_shell_alias bs_cli_help_cmd bs::cli::help_cmd
bs_shell_alias bs_cli_short_sha bs::cli::short_sha
bs_shell_alias bs_cli_install_info_get bs::cli::install_info_get
bs_shell_alias bs_cli_update_manifest_valid bs::cli::update_manifest_valid
bs_shell_alias bs_cli_bs_full_info_lines bs::cli::bs_full_info_lines
bs_shell_alias bs_cli_bs_running_block bs::cli::bs_running_block
bs_shell_alias bs_cli_version_cmd bs::cli::version_cmd
bs_shell_alias bs_cli_env_cmd bs::cli::env_cmd
bs_shell_alias bs_cli_list_cmd bs::cli::list_cmd
bs_shell_alias bs_cli_init_shell_bin_dir bs::cli::init_shell_bin_dir
bs_shell_alias bs_cli_init_shell_usage bs::cli::init_shell_usage
bs_shell_alias bs_cli_init_shell_cmd bs::cli::init_shell_cmd
bs_shell_alias bs_cli_shebang_usage bs::cli::shebang_usage
bs_shell_alias bs_cli_shebang_files bs::cli::shebang_files
bs_shell_alias bs_cli_shebang_cmd bs::cli::shebang_cmd
bs_shell_alias bs_cli_call_usage bs::cli::call_usage
bs_shell_alias bs_cli_call_cmd bs::cli::call_cmd
bs_shell_alias bs_cli_doctor_cmd bs::cli::doctor_cmd
bs_shell_alias bs_cli_euid bs::cli::euid
bs_shell_alias bs_cli_update_system_lib bs::cli::update_system_lib
bs_shell_alias bs_cli_update_wrapper_root bs::cli::update_wrapper_root
bs_shell_alias bs_cli_bs_running_kind bs::cli::bs_running_kind
bs_shell_alias bs_cli_bs_running_info bs::cli::bs_running_info
bs_shell_alias bs_cli_update_ctx bs::cli::update_ctx
bs_shell_alias bs_cli_update_die bs::cli::update_die
bs_shell_alias bs_cli_update_warn bs::cli::update_warn
bs_shell_alias bs_cli_update_flag_value bs::cli::update_flag_value
bs_shell_alias bs_cli_update_realpath bs::cli::update_realpath
bs_shell_alias bs_cli_update_is_install bs::cli::update_is_install
bs_shell_alias bs_cli_update_is_checkout bs::cli::update_is_checkout
bs_shell_alias bs_cli_update_source_missing bs::cli::update_source_missing
bs_shell_alias bs_cli_update_install_wrapper bs::cli::update_install_wrapper
bs_shell_alias bs_cli_update_sudo_home bs::cli::update_sudo_home
bs_shell_alias bs_cli_update_missing_lines bs::cli::update_missing_lines
bs_shell_alias bs_cli_push_lines bs::cli::push_lines
bs_shell_alias bs_cli_update_box bs::cli::update_box
bs_shell_alias bs_cli_uninstall_cmd bs::cli::uninstall_cmd
bs_shell_alias bs_cli_where_row bs::cli::where_row
bs_shell_alias bs_cli_where_classify bs::cli::where_classify
bs_shell_alias bs_cli_where_kind_by_path bs::cli::where_kind_by_path
bs_shell_alias bs_cli_where_size bs::cli::where_size
bs_shell_alias bs_cli_where_help bs::cli::where_help
bs_shell_alias bs_cli_where_cmd bs::cli::where_cmd
bs_shell_alias bs_cli_update_fetch_cleanup bs::cli::update_fetch_cleanup
bs_shell_alias bs_cli_update_fetch bs::cli::update_fetch
bs_shell_alias bs_cli_update_local_state bs::cli::update_local_state
bs_shell_alias bs_cli_update_rollback bs::cli::update_rollback
bs_shell_alias bs_cli_update_inflight_cleanup bs::cli::update_inflight_cleanup
bs_shell_alias bs_cli_update_cleanup_stale bs::cli::update_cleanup_stale
bs_shell_alias bs_cli_update_lock bs::cli::update_lock
bs_shell_alias bs_cli_update_unlock bs::cli::update_unlock
bs_shell_alias bs_cli_update_fix_shebang bs::cli::update_fix_shebang
bs_shell_alias bs_cli_update_smoke bs::cli::update_smoke
bs_shell_alias bs_cli_update_apply bs::cli::update_apply
bs_shell_alias bs_cli_update_manifest bs::cli::update_manifest
bs_shell_alias bs_cli_update_path_summary bs::cli::update_path_summary
bs_shell_alias bs_cli_update_pull_blocker bs::cli::update_pull_blocker
bs_shell_alias bs_cli_update_pull_checkout bs::cli::update_pull_checkout
bs_shell_alias bs_cli_update_state_summary bs::cli::update_state_summary
bs_shell_alias bs_cli_update_cmd bs::cli::update_cmd
