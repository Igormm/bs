#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: case, printf, test, find/sort/sed/git; команды, не требующие bash / valid POSIX sh: case, printf, test, find/sort/sed/git; the commands that do not need bash
# @tier core — builtins, find, sort, git (optional); works everywhere
#
# bootstrap/cli.sh — команды bs, которые работают в любой оболочке (POSIX-часть bs::cli::*)
# bootstrap/cli.sh — the bs commands that run in any shell (the POSIX part of bs::cli::*)
#
# Остальные команды (lang-doc, lsp, chat, api, ts, audit, doctor, build, rfc, run, update,
# uninstall, where, init-shell, shebang, call, repl) пока в bootstrap/bs.sh на bash; в оболочке
# без bash bs_cli_delegate отвечает, что команде нужен bash. Тела функций вызывают ядро и
# выполняются только после его загрузки.
# The other commands (lang-doc, lsp, chat, api, ts, audit, doctor, build, rfc, run, update,
# uninstall, where, init-shell, shebang, call, repl) are still in bootstrap/bs.sh in bash; in a
# shell without bash bs_cli_delegate answers that the command needs bash. The function bodies call
# the kernel and run only after it is loaded.
#
# ИМЕНА / NAMES
#   Real functions: bs_cli_die, bs_cli_need_bash, bs_cli_delegate, bs_cli_help, bs_cli_help_cmd,
#   bs_cli_short_sha, bs_cli_install_info_get, bs_cli_update_manifest_valid,
#   bs_cli_bs_full_info_lines, bs_cli_bs_running_block, bs_cli_version_cmd, bs_cli_env_cmd,
#   bs_cli_list_cmd; in bash and zsh also bs::cli::die, bs::cli::help, … (the old names).
#   Настоящие функции — bs_cli_*; в bash и zsh — ещё и прежние bs::cli::die, bs::cli::help, …

# Примечание: строгий режим (set -euo pipefail) и IFS задаются только в точках входа
# Note: strict mode (set -euo pipefail) and IFS are set only in entry points

# Простой self-guard: файл подключают bs.sh и сам bs, до ядра bs_guard ещё нет
# A raw self-guard: bs.sh and bs itself source this file, and bs_guard does not exist before the kernel
case "${__BS_CLI_SOURCED:-}" in
  1) return 0 2>/dev/null ;;
esac
__BS_CLI_SOURCED=1

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

# @description Справка по командам bs / The help of the bs commands
bs_cli_help() {
  cat <<HELP
BS Framework $(bs_version_get) – command launcher & shebang interpreter
Usage: bs [command] [args...]
       bs help <command>   Show detailed help for a command

Info / Информация:
  help, -h, --help    Show this help / показать эту справку
  help <command>      Show detailed help for a command / справка по команде
  version [--full]    Print framework version (--full: build and install info) / версия (--full: сборка и установка)
  env                 Show environment (BS_ROOT, PATH, install manifest) / окружение
  doctor              Check framework integrity / проверка целостности

Modules / Модули:
  list                List available modules (core/, lib/) / список модулей
  lang-doc            JSON index of function docs (LSP metadata) / индекс функций
  lsp                 Run language server (JSON-RPC over stdin/stdout) / LSP

Development / Разработка:
  run <script> [args] Execute script inside BS environment / запуск скрипта
  build <script>      Assemble a standalone self-extracting script / сборка
  repl                Interactive REPL (BS shell) / интерактивная консоль
  calc                RPN calculator / калькулятор ОПН
  rfc [number]        RFC helpers (1925, 3986, 4122, 4180) / RFC
  api <sub> [args]    OpenAPI 3.x client / OpenAPI-клиент
  ts <command>        TypeScript toolchain / TS-тулчейн
  audit [roots]       GNU-only tool audit / аудит GNU-зависимостей
  chat [opts]         Interactive LLM chat / чат с LLM

Maintenance / Обслуживание:
  update [opts]       Update installed copies from a local repo or GitHub / обновление
  uninstall [opts]    Remove installed BS copies / удаление
  where [--deep]      Find every trace of BS on this machine / все следы BS на машине
  init-shell [SHELL]  PATH snippet for your shell: bash zsh ash dash ksh fish nu / snippet для вашей оболочки
  call FUNC [ARGS]    Call a kernel/library function from any shell (fish, nu, dash...) / вызвать функцию из любой оболочки
  shebang <cmd>       Check and rewrite #! lines for this machine (Termux: no /usr/bin/env) / проверка и правка #! для этой машины
  --strict-shell[=SHELL]  (before the command) refuse lib/ modules whose @shell tier does not fit the shell bs was started from, or the NAMED SHELL (--strict-shell=dash: will it work in dash) / отказывать модулям lib/, чей tier @shell не подходит оболочке запуска или УКАЗАННОЙ оболочке

Shebang mode:
  #!/usr/bin/env bs
  (set BS_SHEBANG=1 internally)

Examples:
  bs doctor
  bs help build
  bs run ./examples/deploy.sh --prod
  bs list | grep system
HELP
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
    version)        printf 'Usage: bs version [--full]\n\nPrint the framework version; --full adds the root, install kind, source and last update.\n' ;;
    env)            printf 'Usage: bs env\n\nShow BS_ROOT, PATH and the install manifest.\n' ;;
    list)           bs_cli_list_cmd --help ;;
    lang-doc)       bs_cli_delegate lang-doc bs::cli::lang_doc_cmd --help ;;
    lsp)            bs_cli_delegate lsp bs::cli::lsp_cmd --help ;;
    chat)           bs_cli_delegate chat bs::cli::chat_cmd --help ;;
    api)            bs_cli_delegate api bs::cli::api_cmd --help ;;
    ts)             bs_cli_delegate ts bs::cli::ts_cmd --help ;;
    audit)          bs_cli_delegate audit bs::cli::audit_cmd --help ;;
    doctor)         bs_cli_delegate doctor bs::cli::doctor_cmd --help ;;
    run)            printf 'Usage: bs run <script> [args...]\n\nExecute a script inside the BS environment.\n' ;;
    build)          bs_cli_delegate build bs::cli::build_cmd --help ;;
    repl)           printf 'Usage: bs repl\n\nInteractive REPL (BS shell).\n' ;;
    calc)           printf 'Usage: bs calc [expression]\n\nRPN calculator on dc.\n' ;;
    update|sync)    bs_cli_delegate update bs::cli::update_cmd --help ;;
    uninstall)      bs_cli_delegate uninstall bs::cli::uninstall_cmd --help ;;
    where)          bs_cli_delegate where bs::cli::where_cmd --help ;;
    init-shell)     bs_cli_delegate init-shell bs::cli::init_shell_usage ;;
    shebang)        bs_cli_delegate shebang bs::cli::shebang_usage ;;
    call)           bs_cli_delegate call bs::cli::call_usage ;;
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

# @private Строки сведений о запущенной копии — ровно то, что `bs version --full`
# печатает после строки версии: root, вид установки, источник, последнее
# обновление. Читает манифест и git, чужой код не запускает. Те же строки идут
# в начале и в каждой рамке `bs update` / `bs uninstall`.
# @private The detail lines about the running copy — exactly what
# `bs version --full` prints after the version line: root, install kind,
# source, last update. Reads the manifest and git, runs no foreign code. The
# same lines open every `bs update` / `bs uninstall` run and notice box.
bs_cli_bs_full_info_lines() {
  printf '  %-10s %s\n' "root:" "${BS_ROOT}"
  if [ -e "${BS_ROOT}/.install" ] && ! bs_cli_update_manifest_valid "${BS_ROOT}/.install"; then
    printf '  %-10s %s\n' "install:" \
      "manifest unreadable or corrupt / манифест повреждён: ${BS_ROOT}/.install (bs update recreates it)"
  elif [ -f "${BS_ROOT}/.install" ]; then
    __bs_cli_imode=$(bs_cli_install_info_get "${BS_ROOT}" mode)
    __bs_cli_iat=$(bs_cli_install_info_get "${BS_ROOT}" installed_at)
    __bs_cli_iby=$(bs_cli_install_info_get "${BS_ROOT}" installed_by)
    __bs_cli_isrc=$(bs_cli_install_info_get "${BS_ROOT}" source)
    __bs_cli_isc=$(bs_cli_install_info_get "${BS_ROOT}" source_commit)
    __bs_cli_uat=$(bs_cli_install_info_get "${BS_ROOT}" updated_at)
    __bs_cli_ufrom=$(bs_cli_install_info_get "${BS_ROOT}" updated_from)
    __bs_cli_ucom=$(bs_cli_install_info_get "${BS_ROOT}" updated_commit)
    printf '  %-10s %s, installed %s by %s\n' "install:" \
      "${__bs_cli_imode:-?}" "${__bs_cli_iat:-?}" "${__bs_cli_iby:-?}"
    printf '  %-10s %s @ %s\n' "source:" \
      "${__bs_cli_isrc:-?}" "$(bs_cli_short_sha "${__bs_cli_isc:-}")"
    if [ -n "${__bs_cli_uat}" ]; then
      printf '  %-10s %s from %s @ %s\n' "updated:" "${__bs_cli_uat}" \
        "${__bs_cli_ufrom:-?}" "$(bs_cli_short_sha "${__bs_cli_ucom:-}")"
    fi
  elif [ -e "${BS_ROOT}/.git" ] && bs_utils_has git; then
    printf '  %-10s source checkout, commit %s (%s)%s\n' "install:" \
      "$(git -C "${BS_ROOT}" rev-parse --short=7 HEAD 2>/dev/null || printf '?')" \
      "$(git -C "${BS_ROOT}" log -1 --format=%cd --date=short 2>/dev/null || printf '?')" \
      "$(if [ -n "$(git -C "${BS_ROOT}" status --porcelain 2>/dev/null)" ]; then printf ', with uncommitted changes'; fi)"
  elif [ -e "${BS_ROOT}/.git" ] || [ -d "${BS_ROOT}/tests" ]; then
    printf '  %-10s source checkout (git not available, commit unknown / git недоступен)\n' "install:"
  else
    printf '  %-10s %s\n' "install:" \
      "no manifest (installed by an older installer)"
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
  echo 'Available modules:'
  __bs_cli_lc=0
  __bs_cli_lfiles=$(find "${BS_ROOT}/core" "${BS_ROOT}/lib" -type f -name '*.sh' 2>/dev/null | sort)
  if [ -n "${__bs_cli_lfiles}" ]; then
    while IFS= read -r __bs_cli_lf; do
      if [ -f "${__bs_cli_lf}" ]; then
        printf '  %s\n' "${__bs_cli_lf#"${BS_ROOT}"/}"
        __bs_cli_lc=$((__bs_cli_lc + 1))
      fi
    done <<LIST_END
${__bs_cli_lfiles}
LIST_END
  fi
  printf '%d modules\n' "${__bs_cli_lc}"
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
