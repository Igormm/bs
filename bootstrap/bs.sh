#!/usr/bin/env bash
#
# bootstrap/bs.sh — pre-kernel root namespace, available BEFORE the loader
# bootstrap/bs.sh — корневой namespace bs::, доступный ДО загрузки loader'а
# @tier core — pure Bash 4+, no GNU tools: works everywhere
# @tier core — чистый Bash 4+, без GNU-инструментов: работает везде
# @shell bash4 — pre-kernel bash layer; the POSIX part is bootstrap/shell.sh
# @shell bash4 — pre-kernel слой на bash; POSIX-часть — bootstrap/shell.sh
#
# This file has no dependencies and must stay bash-3.2-compatible (pure
# builtins, no associative arrays): it is sourced by entry points and by
# bootstrap/init.sh before the kernel (core/) loads, so the shell version
# gate can run on any interpreter the framework must reject.
# Файл не имеет зависимостей и обязан оставаться совместимым с bash 3.2
# (чистые builtins, без ассоциативных массивов): его подключают точки входа
# и bootstrap/init.sh до загрузки ядра (core/), чтобы гейт версии оболочки
# отработал на любом интерпретаторе, который фреймворк должен отклонить.

# Raw self-guard: bs::guard lives in core/prereq.sh, which is loaded via the
# loader — this file runs before that, so it cannot use it.
# Простой self-guard: bs::guard живёт в core/prereq.sh и грузится через
# loader — этот файл выполняется раньше, поэтому использовать её нельзя.
[[ -n "${__BS_SH_SOURCED:-}" ]] && return 0
readonly __BS_SH_SOURCED=1

# POSIX-реестр оболочек (bootstrap/shell.sh): определение семейства, rc-файлы,
# строки PATH, tier. Его же подключают оболочки, не являющиеся bash.
# The POSIX shell registry (bootstrap/shell.sh): family detection, rc files,
# PATH lines, tier. Shells other than bash source it too.
if [[ -n "${BASH_SOURCE[0]:-}" && -f "$(dirname -- "${BASH_SOURCE[0]}")/shell.sh" ]]; then
  # shellcheck source=bootstrap/shell.sh
  source "$(dirname -- "${BASH_SOURCE[0]}")/shell.sh"
fi

# ==========================================
# Strict mode / Строгий режим
# ==========================================

# @description Enable strict bash mode (set -euo pipefail) and a safe IFS.
# @description Включить строгий режим bash (set -euo pipefail) и безопасный IFS.
# @description Pre-kernel equivalent of utils::strict (core/utils.sh): available
# @description BEFORE the loader runs, so plain-bash entry points (bs, boot.sh)
# @description can enable strict mode via a named helper instead of a raw line.
# @description Pre-kernel аналог utils::strict (core/utils.sh): доступна ДО
# @description запуска loader'а, чтобы обычные bash-точки входа (bs, boot.sh)
# @description включали строгий режим именованной функцией, а не сырой строкой.
# @note Entry points only, never inside library modules.
# @note Только в точках входа, никогда в библиотечных модулях.
bs::strict() {
  set -euo pipefail
  IFS=$'\n\t'
}

# ==========================================
# PATH / Local bin
# ==========================================

# @description Prepend ~/.local/bin to PATH once (local installs).
# @description Добавить ~/.local/bin в PATH один раз (локальные установки).
bs::append_local_bin_to_path() {
  local -r needle="${HOME:-}/.local/bin"
  case ":${PATH}:" in
    *":${needle}:"*) return 0 ;;
    *) export PATH="${needle}:${PATH}" ;;
  esac
}

# ==========================================
# Script directory / Каталог скрипта
# ==========================================

# @description Print the absolute (physical) directory of the caller's file.
# @description Вывести абсолютный (физический) каталог файла вызывающего.
# @description Replaces the boilerplate: "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)".
# @description Заменяет шаблон: "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)".
# @param $1 Optional BASH_SOURCE index (default 1 = immediate caller).
# @param $1 Индекс BASH_SOURCE (по умолчанию 1 = непосредственный вызывающий).
# @stdout Absolute directory path (pwd -P).
# @stdout Абсолютный путь каталога (pwd -P).
# @returns 0 on success; 1 if the directory cannot be resolved.
# @returns 0 при успехе; 1, если каталог не удаётся определить.
bs::script_dir() {
  local -r idx="${1:-1}"
  # Индекс за пределами стека под set -u дал бы unbound variable / an
  # out-of-range index under set -u would crash with unbound variable
  (( idx >= 0 && idx < ${#BASH_SOURCE[@]} )) || return 1
  (cd -- "$(dirname -- "${BASH_SOURCE[${idx}]}")" >/dev/null 2>&1 && pwd -P)
}

# @description Print the absolute (physical) path of the caller's file.
# @description Вывести абсолютный (физический) путь файла вызывающего.
# @stdout Absolute file path / Абсолютный путь файла
# @returns 0 on success; 1 if the file cannot be resolved.
bs::script_path() {
  (( ${#BASH_SOURCE[@]} > 1 )) || return 1
  readlink -f -- "${BASH_SOURCE[1]}" 2>/dev/null || printf '%s\n' "${BASH_SOURCE[1]}"
}

# Стек вызовов. Уровень 0 — вызывающий хелпер (его файл, строка вызова, функция),
# 1 — его вызывающий и так далее. Единственное место, знающее про BASH_SOURCE,
# BASH_LINENO и FUNCNAME для трассировок.
# The call stack. Level 0 is the caller of the helper (its file, the line of the
# call, its function), 1 is its caller, and so on. The only place that knows
# BASH_SOURCE, BASH_LINENO and FUNCNAME for backtraces.

# @description Number of frames above the helper (levels 0 .. depth-1).
# @description Число кадров стека над хелпером (уровни 0 .. depth-1).
# @stdout depth / глубина
bs::stack_depth() {
  printf '%d\n' "$(( ${#FUNCNAME[@]} - 1 ))"
}

# @description File of the stack frame at LEVEL ("unknown" if absent).
# @description Файл кадра стека на уровне LEVEL («unknown», если нет).
# @param $1 level / уровень
bs::stack_file() {
  printf '%s\n' "${BASH_SOURCE[$(( ${1:-0} + 1 ))]:-unknown}"
}

# @description Line (of the call) of the stack frame at LEVEL (0 if absent).
# @description Строка (вызова) кадра стека на уровне LEVEL (0, если нет).
# @param $1 level / уровень
bs::stack_line() {
  printf '%s\n' "${BASH_LINENO[${1:-0}]:-0}"
}

# @description Function of the stack frame at LEVEL ("main" if absent).
# @description Функция кадра стека на уровне LEVEL («main», если нет).
# @param $1 level / уровень
bs::stack_func() {
  printf '%s\n' "${FUNCNAME[$(( ${1:-0} + 1 ))]:-main}"
}

# @description Make `set -x` traces show "file:line:" (PS4).
# @description Трассировка `set -x` показывает «файл:строка:» (PS4).
bs::trace_prefix() {
  # shellcheck disable=SC2016  # PS4 раскрывается при трассировке / PS4 expands at trace time
  PS4='+ ${BASH_SOURCE##*/}:${LINENO}: '
}

# ==========================================
# Shell detection / Определение оболочки
#
# Рантайм-определение через BASH_VERSION/ZSH_VERSION (а НЕ $SHELL — это
# логин-оболочка, она врёт при source из другой оболочки). Все хелперы —
# чистые builtins, доступны априори, до загрузки ядра.
# Runtime detection via BASH_VERSION/ZSH_VERSION (NOT $SHELL — that is the
# login shell and lies when sourcing from another shell). All helpers are
# pure builtins, available a priori, before the kernel loads.
# ==========================================

# @description Current shell name: bash, zsh, dash, ash, ksh, ... or unknown.
# @description Имя текущей оболочки: bash, zsh, dash, ash, ksh, ... или unknown.
# @stdout shell name / имя оболочки
bs::shell::name() {
  if [[ -n "${BASH_VERSION:-}" ]]; then
    printf 'bash\n'
  elif [[ -n "${ZSH_VERSION:-}" ]]; then
    printf 'zsh\n'
  elif declare -F bs_shell_family >/dev/null 2>&1; then
    bs_shell_family
  else
    printf 'unknown\n'
  fi
  return 0
}

# @description Full version string of the running shell (bash: BASH_VERSION).
# @description Полная строка версии работающей оболочки (bash: BASH_VERSION).
# @stdout version / версия
bs::shell::version_string() {
  if [[ -n "${BASH_VERSION:-}" ]]; then
    printf '%s\n' "${BASH_VERSION}"
  elif [[ -n "${ZSH_VERSION:-}" ]]; then
    printf '%s\n' "${ZSH_VERSION}"
  else
    printf 'unknown\n'
  fi
  return 0
}

# @description Major shell version (bash: BASH_VERSINFO[0], zsh: ZSH_VERSION).
# @description Старшая версия оболочки (bash: BASH_VERSINFO[0], zsh: ZSH_VERSION).
# @stdout major version / старшая версия
bs::shell::version() {
  if [[ -n "${BASH_VERSION:-}" ]]; then
    printf '%s\n' "${BASH_VERSINFO[0]:-0}"
  elif [[ -n "${ZSH_VERSION:-}" ]]; then
    printf '%s\n' "${ZSH_VERSION%%.*}"
  else
    printf '0\n'
  fi
  return 0
}

# @description Capability gate: bash 4.2+ = full kernel (0/1).
# @description Гейт возможностей: bash 4.2+ = полное ядро (0/1).
# @stdout 1 bash 4.2+, 0 otherwise / 1 для bash 4.2+, 0 иначе
bs::shell::ok() {
  if [[ -n "${BASH_VERSION:-}" ]] && (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2) )); then
    printf '1\n'
  else
    printf '0\n'
  fi
  return 0
}

# @description Sourced vs executed for the DIRECT CALLER: 0 sourced, 1 executed.
# @description Source vs исполнение ПРЯМОГО ВЫЗЫВАЮЩЕГО: 0 при source, 1 при исполнении.
# bash: файл-вызывающий (BASH_SOURCE[1]) равен $0 только если он исполнен
# напрямую; при source $0 — имя оболочки/скрипта-хозяина. zsh: контекст
# исполнения через ZSH_EVAL_CONTEXT ($0 в zsh при source = имя файла).
# In bash the caller file (BASH_SOURCE[1]) equals $0 only when executed
# directly; when sourced, $0 is the host shell/script. zsh uses
# ZSH_EVAL_CONTEXT ($0 becomes the file name when sourced).
# @return 0 caller is sourced / вызывающий подключён через source; 1 executed
bs::shell::is_sourced() {
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    [[ "${ZSH_EVAL_CONTEXT}" != toplevel* ]]
    return $?
  fi
  [[ "${BASH_SOURCE[1]:-}" != "$0" ]]
  return $?
}

# @description Is the caller's file the program being run (executed directly or
#   by `bs run`), not a module sourced by it? Replaces the copy-pasted guard.
# @description Файл вызывающего — запускаемая программа (напрямую или через
#   `bs run`), а не подключённый ею модуль? Заменяет копируемый охранник.
# @example
#   if bs::is_main; then main "$@"; fi
# @return 0 the caller's file is the running program / запускаемая программа; 1 sourced module
bs::is_main() {
  [[ "${BASH_SOURCE[1]:-}" == "$0" || "${BASH_SOURCE[1]:-}" == "${BS_RUN_SCRIPT:-}" ]]
}

# @description Gate: ensure the runtime shell meets a version requirement.
# @description Гейт: проверить, что текущая оболочка не старше требуемой версии.
# @description Checks the bash version only (BASH_VERSINFO), not the shell kind;
# @description Проверяет только версию bash (BASH_VERSINFO), а не вид оболочки;
# @description silent on success, error to stderr on failure, never exits.
# @description молчит при успехе, ошибка в stderr при провале, не вызывает exit.
# @arg $1 int Required major version, default 4.
# @arg $2 int Required minor version, default 2 (framework needs bash 4.2+).
# @arg $1 int Требуемая старшая версия, по умолчанию 4.
# @arg $2 int Требуемая младшая версия, по умолчанию 2 (фреймворку нужен bash 4.2+).
# @exitcode 0 version ok / версия подходит
# @exitcode 1 too old or undetectable / старая или не определена
bs::shell::ensure_version() {
  local -r required_major="${1:-4}"
  local -r required_minor="${2:-2}"
  if ! [[ "${required_major}" =~ ^[0-9]+$ ]] || ! [[ "${required_minor}" =~ ^[0-9]+$ ]]; then
    printf 'ERROR: ensure_version: required version must be numbers, got %s.%s\n' "${required_major}" "${required_minor}" >&2
    return 1
  fi
  local -r major="${BASH_VERSINFO[0]:-0}" minor="${BASH_VERSINFO[1]:-0}"
  if (( major < required_major || ( major == required_major && minor < required_minor ) )); then
    printf 'ERROR: bash %s.%s+ required, found %s.%s\n' "${required_major}" "${required_minor}" "${major}" "${minor}" >&2
    return 1
  fi
  return 0
}

# ==========================================================================
# CLI-команды bs / bs CLI commands
#
# Перенесено из файла bs. Здесь только ОПРЕДЕЛЕНИЯ: тела вызывают log::, utils::
# и прочее из ядра, но выполняются только после загрузки ядра (bs их вызывает из
# диспетчера). Имена в пространстве bs::cli::, чтобы не затенять `help`/`die`
# в чужих скриптах.
# Moved from the bs file. DEFINITIONS only: the bodies call log::, utils:: and
# other kernel code but run only after the kernel is loaded (bs calls them from
# its dispatcher). Names live in bs::cli:: so they do not shadow `help`/`die`
# in other people's scripts.
# ==========================================================================

# 6. Утилитные функции
bs::cli::die()  { error::exit "$*"; }

bs::cli::help() {
  cat <<HELP
BS Framework $(bs::version::get) – command launcher & shebang interpreter
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
  --strict-shell      (before the command) refuse lib/ modules whose @shell tier does not fit the shell bs was started from / отказывать модулям lib/, чей tier @shell не подходит оболочке запуска

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

# @description Show detailed help for a single command by calling its --help.
# @description Показать подробную справку по одной команде через её --help.
# @param $1 Command name / имя команды
bs::cli::help_cmd() {
  local cmd="${1:-}"
  if is::empty "${cmd}"; then
    bs::cli::help
    return 0
  fi
  case "${cmd}" in
    help|-h|--help) help ;;
    version)        printf 'Usage: bs version [--full]\n\nPrint the framework version; --full adds the root, install kind, source and last update.\n' ;;
    env)            printf 'Usage: bs env\n\nShow BS_ROOT, PATH and the install manifest.\n' ;;
    list)           bs::cli::list_cmd --help ;;
    lang-doc)       bs::cli::lang_doc_cmd --help ;;
    lsp)            bs::cli::lsp_cmd --help ;;
    chat)           bs::cli::chat_cmd --help ;;
    api)            bs::cli::api_cmd --help ;;
    ts)             bs::cli::ts_cmd --help ;;
    audit)          bs::cli::audit_cmd --help ;;
    doctor)         bs::cli::doctor_cmd --help ;;
    run)            printf 'Usage: bs run <script> [args...]\n\nExecute a script inside the BS environment.\n' ;;
    build)          bs::cli::build_cmd --help ;;
    repl)           printf 'Usage: bs repl\n\nInteractive REPL (BS shell).\n' ;;
    calc)           printf 'Usage: bs calc [expression]\n\nRPN calculator on dc.\n' ;;
    update|sync)    bs::cli::update_cmd --help ;;
    uninstall)      bs::cli::uninstall_cmd --help ;;
    where)          bs::cli::where_cmd --help ;;
    init-shell)     bs::cli::init_shell_usage ;;
    rfc)            bs::cli::rfc_cmd --help ;;
    *)              bs::cli::die "help: unknown command: ${cmd}" ;;
  esac
}

# @private Первые 7 символов хеша коммита / First 7 characters of a commit hash
bs::cli::short_sha() { printf '%s' "${1:0:7}"; }

# @private Строки сведений о запущенной копии — ровно то, что `bs version --full`
# печатает после строки версии: root, вид установки, источник, последнее
# обновление. Читает манифест и git, чужой код не запускает. Те же строки идут
# в начале и в каждой рамке `bs update` / `bs uninstall`.
# @private The detail lines about the running copy — exactly what
# `bs version --full` prints after the version line: root, install kind,
# source, last update. Reads the manifest and git, runs no foreign code. The
# same lines open every `bs update` / `bs uninstall` run and notice box.
bs::cli::bs_full_info_lines() {
  local key
  local -A info=()
  printf '  %-10s %s\n' "root:" "${BS_ROOT}"
  if [[ -e "${BS_ROOT}/.install" ]] && ! bs::cli::update_manifest_valid "${BS_ROOT}/.install"; then
    printf '  %-10s %s\n' "install:" \
      "manifest unreadable or corrupt / манифест повреждён: ${BS_ROOT}/.install (bs update recreates it)"
  elif [[ -f "${BS_ROOT}/.install" ]]; then
    for key in mode installed_at installed_by source source_commit \
               updated_at updated_from updated_commit; do
      info["${key}"]="$(bs::cli::install_info_get "${BS_ROOT}" "${key}")"
    done
    printf '  %-10s %s, installed %s by %s\n' "install:" \
      "${info[mode]:-?}" "${info[installed_at]:-?}" "${info[installed_by]:-?}"
    printf '  %-10s %s @ %s\n' "source:" \
      "${info[source]:-?}" "$(bs::cli::short_sha "${info[source_commit]:-}")"
    if [[ -n "${info[updated_at]}" ]]; then
      printf '  %-10s %s from %s @ %s\n' "updated:" "${info[updated_at]}" \
        "${info[updated_from]:-?}" "$(bs::cli::short_sha "${info[updated_commit]:-}")"
    fi
  elif [[ -e "${BS_ROOT}/.git" ]] && utils::has git; then
    printf '  %-10s source checkout, commit %s (%s)%s\n' "install:" \
      "$(git -C "${BS_ROOT}" rev-parse --short=7 HEAD 2>/dev/null || printf '?')" \
      "$(git -C "${BS_ROOT}" log -1 --format=%cd --date=short 2>/dev/null || printf '?')" \
      "$([[ -n "$(git -C "${BS_ROOT}" status --porcelain 2>/dev/null)" ]] && printf ', with uncommitted changes' || true)"
  elif [[ -e "${BS_ROOT}/.git" || -d "${BS_ROOT}/tests" ]]; then
    printf '  %-10s source checkout (git not available, commit unknown / git недоступен)\n' "install:"
  else
    printf '  %-10s %s\n' "install:" \
      "no manifest (installed by an older installer)"
  fi
}

# @private Сведения о запущенной копии одним блоком: заголовок с версией и
# строки bs::cli::bs_full_info_lines. Первая строка «Запущен / Running: bs ВЕРСИЯ».
# @private The running copy as one block: a heading with the version and the
# bs::cli::bs_full_info_lines rows. The first line is "Запущен / Running: bs VERSION".
bs::cli::bs_running_block() {
  printf 'Запущен / Running: bs %s\n' "$(bs::version::get)"
  bs::cli::bs_full_info_lines
}

# bs version [--full]: номер версии; с --full — откуда взята эта копия BS
# bs version [--full]: the version number; --full adds where this BS copy is from
bs::cli::version_cmd() {
  case "${1:-}" in
    "")          bs::version::print; return 0 ;;
    -f|--full)   bs::version::print ;;
    *)           bs::cli::die "version: unknown argument: $1 (try: bs version --full)" ;;
  esac

  bs::cli::bs_full_info_lines
}

# @private Значение ключа из манифеста установки (<lib>/.install, key=value).
# @private Value of a key from the install manifest (<lib>/.install, key=value).
# @param $1 Install directory / Каталог установки
# @param $2 Key / Ключ
bs::cli::install_info_get() {
  local -r file="$1/.install" key="$2"
  local line
  [[ -f "${file}" ]] || return 0
  while IFS= read -r line; do
    if [[ "${line}" == "${key}="* ]]; then
      printf '%s\n' "${line#*=}"
      return 0
    fi
  done < "${file}"
  return 0
}

bs::cli::env_cmd() {
  printf 'BS_ROOT=%s\nPATH=%s\n' "$BS_ROOT" "$PATH"
  # Как установлена эта копия (манифест пишет install.sh)
  # How this copy was installed (the manifest is written by install.sh)
  if [[ -e "${BS_ROOT}/.install" ]] && ! bs::cli::update_manifest_valid "${BS_ROOT}/.install"; then
    printf '\nInstall manifest unreadable or corrupt / манифест повреждён: %s (bs update recreates it)\n' "${BS_ROOT}/.install"
  elif [[ -f "${BS_ROOT}/.install" ]]; then
    printf '\nInstall manifest (%s):\n' "${BS_ROOT}/.install"
    local line
    while IFS= read -r line; do
      [[ -z "${line}" || "${line}" == '#'* ]] || printf '  %s\n' "${line}"
    done < "${BS_ROOT}/.install"
  elif is::dir "${BS_ROOT}/tests"; then
    printf '\nInstall: source checkout (not installed) / исходный репозиторий\n'
  else
    printf '\nInstall: no manifest (installed by an older installer) / манифеста нет\n'
  fi
}

bs::cli::list_cmd() {
  echo 'Available modules:'
  local file
  local count=0
  while IFS= read -r file; do
    if is::file "${file}"; then
      printf '  %s\n' "${file#"${BS_ROOT}"/}"
      count=$(( count + 1 ))
    fi
  done < <(find "${BS_ROOT}/core" "${BS_ROOT}/lib" -type f -name '*.sh' 2>/dev/null | sort)
  printf '%d modules\n' "${count}"
}

bs::cli::lang_doc_cmd() {
  local file=""
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      --file)
        shift
        [[ $# -ge 1 ]] || bs::cli::die "lang-doc: --file requires a path"
        file="$1"
        shift ;;
      -h|--help)
        printf 'Usage: bs lang-doc [--file path]\n\n'
        printf 'Emits a JSON array of {name, file, description, params, returns,\n'
        printf 'stdout, example, deprecated} for every documented function in\n'
        printf 'core/ and lib/. With --file, only that file is parsed.\n'
        printf 'Requires jq (optional dev dependency).\n'
        return 0 ;;
      *)
        bs::cli::die "lang-doc: unknown argument: $1" ;;
    esac
  done

  load "lib/data/langdoc"
  is::command jq || bs::cli::die "lang-doc: jq is required (optional dev tool)"

  if is::not_empty "${file}"; then
    is::file "${file}" || bs::cli::die "lang-doc: file not found: ${file}"
    langdoc::parse_file "${file}" | jq -s -c .
  else
    langdoc::index "${BS_ROOT}"
  fi
}

bs::cli::lsp_cmd() {
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      -h|--help)
        printf 'Usage: bs lsp\n\n'
        printf 'Runs a minimal Language Server (JSON-RPC 2.0 over stdin/stdout,\n'
        printf 'Content-Length framing): initialize, hover, completion,\n'
        printf 'full text sync. The function index over BS_ROOT is built lazily.\n'
        printf 'Requires jq. Wire it up in VS Code / Neovim as a custom server.\n'
        return 0 ;;
      *)
        bs::cli::die "lsp: unknown argument: $1" ;;
    esac
  done

  load "lib/data/langdoc"
  load "lib/data/lsp"
  is::command jq || bs::cli::die "lsp: jq is required (optional dev tool)"
  lsp::server
}

bs::cli::chat_cmd() {
  local provider="${BS_CHAT_PROVIDER:-}"
  local model="${BS_CHAT_MODEL:-}"
  local system_prompt="${BS_CHAT_SYSTEM:-You are a helpful assistant for the BS framework.}"
  local one_shot="" limit=20 show_raw=0 url="" api_key=""
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      --provider)
        shift
        [[ $# -ge 1 ]] || bs::cli::die "chat: --provider requires a name"
        provider="$1"
        shift ;;
      --model|-m)
        shift
        [[ $# -ge 1 ]] || bs::cli::die "chat: --model requires a name"
        model="$1"
        shift ;;
      --system|-s)
        shift
        [[ $# -ge 1 ]] || bs::cli::die "chat: --system requires a prompt"
        system_prompt="$1"
        shift ;;
      --one-shot)
        shift
        [[ $# -ge 1 ]] || bs::cli::die "chat: --one-shot requires a message"
        one_shot="$1"
        shift ;;
      --history)
        shift
        [[ $# -ge 1 ]] || bs::cli::die "chat: --history requires a number"
        limit="$1"
        shift ;;
      --url)
        shift
        [[ $# -ge 1 ]] || bs::cli::die "chat: --url requires an endpoint (e.g. http://pi.local:8080/v1/chat/completions)"
        url="$1"
        shift ;;
      --api-key)
        shift
        [[ $# -ge 1 ]] || bs::cli::die "chat: --api-key requires a key"
        api_key="$1"
        shift ;;
      --show-raw)
        show_raw=1
        shift ;;
      -h|--help)
        printf 'Usage: bs chat [--provider p] [--model m] [--system text]\n'
        printf '          [--one-shot msg] [--history N] [--url URL] [--api-key KEY]\n\n'
        printf 'Interactive multi-turn chat with an LLM.\n'
        printf 'Providers: openai (API key required) or ollama (local).\n'
        printf 'A custom local model (e.g. Phi Pi) plugs in as an OpenAI-compatible\n'
        printf 'endpoint: bs chat --url http://host:port/v1/chat/completions --model phi-pi\n'
        printf 'Env defaults: BS_CHAT_PROVIDER, BS_CHAT_MODEL, BS_CHAT_SYSTEM.\n'
        printf 'Requires curl and jq.\n'
        return 0 ;;
      *)
        if is::empty "${one_shot}"; then
          one_shot="$1"
        else
          bs::cli::die "chat: unexpected argument: $1"
        fi
        shift ;;
    esac
  done

  load "lib/integration/llm"
  load "lib/integration/chat"
  is::command curl || bs::cli::die "chat: curl is required"
  is::command jq || bs::cli::die "chat: jq is required"

  # Дефолтный провайдер: ollama, если доступен, иначе openai
  # Default provider: ollama when reachable, otherwise openai
  if is::empty "${provider}"; then
    if llm::is_available ollama; then
      provider="ollama"
    else
      provider="openai"
    fi
  fi
  if is::empty "${model}"; then
    if [[ "${provider}" == "ollama" ]]; then
      model="${LLM_OLLAMA_MODEL:-llama3}"
    else
      model="${LLM_OPENAI_MODEL:-gpt-3.5-turbo}"
    fi
  fi

  # Переопределение эндпоинта / Endpoint override
  if is::not_empty "${url}"; then
    if [[ "${provider}" == "ollama" ]]; then
      export LLM_OLLAMA_HOST="${url}"
    else
      export LLM_OPENAI_URL="${url}"
    fi
  fi
  if is::not_empty "${api_key}"; then
    export OPENAI_API_KEY="${api_key}"
  fi

  chat::repl "${provider}" "${model}" "${system_prompt}" "${one_shot}" "${limit}" "${show_raw}"
}

bs::cli::doctor_cmd() {
  local fail=0
  local pass=0
  local start_ms
  start_ms=$(utils::now_ms)

  # Вектор возможностей / Capability vector
  if [[ "${1:-}" == "--capabilities" ]]; then
    load "lib/platform/facts"
    platform::dump
    return 0
  fi
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    printf 'Usage: bs doctor [--capabilities]\n'
    printf '  --capabilities  print the platform capability vector\n'
    return 0
  fi

  log::info "BS doctor report"
  log::info "BS_ROOT: ${BS_ROOT}"

  # Единая таблица статусов: STATUS | ITEM | DETAIL
  # One aligned status table: STATUS | ITEM | DETAIL
  log::info "$(printf '  %-8s | %-30s | %s' "STATUS" "ITEM" "DETAIL")"
  log::info "$(printf '  %-8s | %-30s | %s' "--------" "------------------------------" "--------")"

  # Bash version gate already ran in the pre-kernel namespace
  # (bootstrap/bs.sh::bs::shell::ensure_version) — no re-check here.
  # Гейт версии bash уже отработал в pre-kernel namespace
  # (bootstrap/bs.sh::bs::shell::ensure_version) — повторная проверка не нужна.

  # Required core files / Обязательные файлы ядра
  local req=(bootstrap/init.sh bootstrap/loader.sh bootstrap/bs.sh bootstrap/shell.sh bootstrap/trampoline.sh core/prereq.sh core/lang.sh core/const.sh core/logger.sh core/errorhandler.sh core/version.sh core/utils.sh core/config.sh core/deps.sh core/repl.sh core/calc.sh)
  local f
  for f in "${req[@]}"; do
    if is::file "${BS_ROOT}/${f}"; then
      log::success "$(printf '  %-8s | %-30s | %s' "OK" "${f}" "required core file")"
      pass=$(( pass + 1 ))
    else
      log::error "$(printf '  %-8s | %-30s | %s' "FAIL" "${f}" "required core file missing")"
      fail=1
    fi
  done

  # Required directories / Обязательные директории
  local d
  for d in core lib; do
    if is::dir "${BS_ROOT}/${d}"; then
      log::success "$(printf '  %-8s | %-30s | %s' "OK" "dir ${d}" "required directory")"
      pass=$(( pass + 1 ))
    else
      log::error "$(printf '  %-8s | %-30s | %s' "FAIL" "dir ${d}" "required directory missing")"
      fail=1
    fi
  done

  # Оболочка: кто исполняет BS, чья оболочка у пользователя, tier, аннотации модулей
  # The shell: who runs BS, whose shell the user has, the tier, module annotations
  local dfam duser dtier
  dfam="$(bs_shell_family)"
  duser="$(bs_shell_user)"
  dtier="$(bs_shell_tier "${duser}")"
  log::success "$(printf '  %-8s | %-30s | %s' "OK" "shell (host)" "${dfam} ${BASH_VERSION}")"
  log::success "$(printf '  %-8s | %-30s | %s' "OK" "shell (yours)" "${duser}, tier ${dtier}")"
  log::info "$(printf '  %-8s | %-30s | %s' "" "" "$(bs_shell_tier_desc "${dtier}")")"
  pass=$(( pass + 2 ))
  local ann_posix ann_bash4
  ann_posix="$(grep -rlE '^# @shell posix' "${BS_ROOT}/bootstrap" "${BS_ROOT}/core" "${BS_ROOT}/lib" 2>/dev/null | wc -l || true)"
  ann_bash4="$(grep -rlE '^# @shell bash4' "${BS_ROOT}/bootstrap" "${BS_ROOT}/core" "${BS_ROOT}/lib" 2>/dev/null | wc -l || true)"
  log::success "$(printf '  %-8s | %-30s | %s' "OK" "module shell tiers" "posix=${ann_posix} bash4=${ann_bash4} (без аннотации = bash4 / unmarked = bash4)")"
  pass=$(( pass + 1 ))

  # Optional external tools / Опциональные внешние инструменты
  local opt
  for opt in shellcheck jq curl wget kubectl; do
    if is::command "${opt}"; then
      log::success "$(printf '  %-8s | %-30s | %s' "OK" "tool ${opt}" "found")"
      pass=$(( pass + 1 ))
    else
      log::warn "$(printf '  %-8s | %-30s | %s' "OPTIONAL" "tool ${opt}" "not found")"
    fi
  done

  # Optional dependency check for lib modules / Проверка опциональных зависимостей lib-модулей
  if is::function deps::check_module; then
    local module
    for module in lib/integration/result lib/integration/http lib/integration/llm lib/integration/k8s; do
      if is::file "${BS_ROOT}/${module}.sh"; then
        if utils::quiet deps::check_module "${module}"; then
          log::success "$(printf '  %-8s | %-30s | %s' "OK" "module ${module}" "dependencies satisfied")"
          pass=$(( pass + 1 ))
        else
          local missing
          missing="$(utils::attempt deps::list_missing "${module}")"
          log::warn "$(printf '  %-8s | %-30s | %s' "OPTIONAL" "module ${module}" "missing dependencies: ${missing}")"
        fi
      fi
    done
  fi

  local end_ms
  end_ms=$(utils::now_ms)
  log::info "doctor: ${pass} passed, ${fail} failed ($(( end_ms - start_ms )) ms)"

  return "$fail"
}

bs::cli::run_cmd() {
  [[ $# -eq 0 ]] && bs::cli::die "run: script path required"
  local script=$1; shift
  is::file "$script" || bs::cli::die "run: file not found: $script"
  # Запускаем скрипт в новом bash с уже загруженным BS-окружением
  # Сбрасываем унаследованный BS_INITIALIZED, иначе init.sh пропустит загрузку
  BS_RUN_SCRIPT="$script" exec bash -c '
    unset BS_INITIALIZED
    source "'"${BS_ROOT}/bootstrap/init.sh"'"
    bs::strict
    script=$1; shift
    source "$script" "$@"
  ' bash "$script" "$@"
}

# Build helper: base64 with -w0 fallback for busybox / base64 с fallback на busybox
bs_build::b64() {
  if printf '' | base64 -w0 >/dev/null 2>&1; then
    base64 -w0
  else
    base64 | tr -d '\n'
  fi
}

# Build helper: robust sha256 (coreutils, busybox-less systems, macOS) / sha256 с fallback
bs_build::sha256() {
  if utils::has sha256sum; then
    sha256sum | awk '{print $1}'
  elif utils::has shasum; then
    shasum -a 256 | awk '{print $1}'
  else
    cksum | awk '{print $1}'
  fi
}

# Runtime preamble of the generated standalone file.
# Не зависит от фреймворка: распаковывает себя в кэш и запускает bs.
# Framework-independent: extracts itself into a cache dir and execs bs.
bs_build::preamble() {
  cat <<'PREAMBLE'
#!/usr/bin/env bash
# BS standalone application — generated by `bs build` / собрано командой `bs build`.
# Self-extracting: unpacks the bundled framework into a cache dir, then execs bs.
set -euo pipefail

bs_seek::b64() {
  if printf '' | base64 -w0 >/dev/null 2>&1; then
    base64 -w0
  else
    base64 | tr -d '\n'
  fi
}

bs_seek::sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    cksum | awk '{print $1}'
  fi
}

bs_seek::main() {
local line payload
  line="$(grep -n '^#__BS_BUILD_PAYLOAD__' "$0" | head -n 1 | cut -d: -f1 || true)"
  [[ -n "${line}" ]] || { echo "bs: payload marker not found in $0" >&2; exit 1; }
  payload="$(sed -n "$((line + 1)),\$p" "$0")"
  [[ -n "${payload}" ]] || { echo "bs: empty payload in $0" >&2; exit 1; }

  local hash cache_root root tmp
  hash="$(printf '%s' "${payload}" | bs_seek::sha256)"
  cache_root="${BS_BUILD_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/bs}"
  root="${cache_root}/${hash}"

  if [[ ! -x "${root}/bs" ]]; then
    mkdir -p "${cache_root}"
    tmp="$(mktemp -d "${cache_root}/extract.XXXXXX")"
    printf '%s' "${payload}" | base64 -d | tar -xz -C "${tmp}"
    mv "${tmp}" "${root}" 2>/dev/null || rm -rf "${tmp}"
  fi

  export BS_ROOT="${root}"
  export BS_HOME="${root}"
  export BS_SILENT=1
  export BS_CACHE_DIR="${root}"
  exec "${root}/bs" run "${root}/app/main.sh" "$@"
}

bs_seek::main "$@"
PREAMBLE
}

# Assemble a standalone self-extracting script / Собрать standalone-скрипт
# @usage bs build <script.sh> [--output file]
bs::cli::build_cmd() {
  local script="" out_file=""
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      -h|--help)
        printf 'Usage: bs build <script.sh> [--output file]\n\n'
        printf 'Assembles a standalone self-extracting script: framework and\n'
        printf 'the app are bundled (gzip+base64) and extracted to a cache dir\n'
        printf 'at first run. Cache: $XDG_CACHE_HOME/bs or BS_BUILD_CACHE_DIR.\n'
        return 0 ;;
      --output)
        shift
        [[ $# -ge 1 ]] || bs::cli::die "build: --output requires a path"
        out_file="$1"; shift ;;
      *)
        if is::empty "${script}"; then
          script="$1"
        else
          bs::cli::die "build: unexpected extra argument: $1"
        fi
        shift ;;
    esac
  done

  is::not_empty "${script}" || bs::cli::die "build: script path required"
  is::file "$script" || bs::cli::die "build: file not found: $script"
  if ! utils::quiet_err bash -n "$script"; then
    bs::cli::die "build: bash syntax errors in: $script"
  fi

  [[ -n "$out_file" ]] || out_file="${script%.sh}.standalone.sh"

  local tmp_dir app_dir
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' RETURN

  # Спрятать app под app/main.sh внутри payload
  # The app is bundled as app/main.sh inside the payload
  app_dir="${tmp_dir}/app"
  mkdir -p "${app_dir}"
  utils::quiet cp -- "$script" "${app_dir}/main.sh" || bs::cli::die "build: cannot read script: $script"

  # Бандл: рантайм-дерево (bootstrap core lib bs) + app/ одним tar-потоком.
  # Конкатенация двух tar-архивов читается далеко не всеми tar'ами,
  # поэтому используем один вызов с двумя -C.
  # Bundle: runtime tree (bootstrap core lib bs) + app/ in one tar stream.
  # Two concatenated tar archives are not readable by every tar,
  # so use a single invocation with two -C.
  # base64 до bash-переменной: gzip содержит NUL-байты, которые
  # command substitution молча вырезает.
  # Base64 before the bash variable: gzip contains NULs which
  # command substitution silently strips.
  local payload hash
  payload="$(
    tar -C "${BS_ROOT}" -c -f - bootstrap core lib bs \
        -C "${tmp_dir}" app \
    | gzip | bs_build::b64
  )"
  hash="$(printf '%s' "${payload}" | bs_build::sha256)"

  # Output written under a temp name, then moved — атомарность и права
  local out_tmp
  out_tmp="${out_file}.bs-build.$$"
  bs_build::preamble > "${out_tmp}"
  printf '%s\n' "#__BS_BUILD_PAYLOAD__" >> "${out_tmp}"
  printf '%s\n' "${payload}" >> "${out_tmp}"
  chmod 0755 "${out_tmp}"
  mv -f -- "${out_tmp}" "${out_file}"
  rm -rf "${tmp_dir}"

  printf 'Built: %s\n' "${out_file}"
  printf 'Framework bundle: %s bytes (payload hash %s)\n' "$(( ${#payload} ))" "${hash}"
}

bs::cli::rfc_cmd() {
  local -r rfc_dir="${BS_ROOT}/lib/rfc"
  case "${1:-}" in
    -h|--help)
      printf 'Usage: bs rfc [number]\n\n'
      printf 'Lists implemented RFC modules; with a number, shows or runs\n'
      printf 'that RFC (e.g. bs rfc 1925 — the twelve networking truths).\n'
      return 0 ;;
    ""|list)
      local file name
      for file in "${rfc_dir}"/*.sh; do
        name="$(basename "${file}" .sh)"
        printf '  %-12s %s\n' "${name}" "$(grep -m1 -o 'RFC [0-9]*:.*' "${file}" | sed 's/^RFC [0-9]*: //')"
      done
      return 0 ;;
    1925)
      load "lib/rfc/rfc1925"
      rfc1925::truths
      ;;
    3986)
      load "lib/rfc/uri"
      printf 'RFC 3986 — URI. Functions: uri::parse, uri::dump, uri::decode, uri::encode.\n'
      printf 'Example:\n  uri::parse "https://user:pw@host:8080/p?a=1#f"\n  echo "${URI_HOST}:${URI_PORT}"\n'
      ;;
    4122)
      load "lib/rfc/uuid"
      printf 'RFC 4122/9562 — UUID. Functions: uuid::gen, uuid::gen_v7, uuid::validate.\n'
      printf 'Example:\n  uuid::gen\n'
      ;;
    4180)
      load "lib/rfc/csv"
      printf 'RFC 4180 — CSV. Functions: csv::rows, csv::fields.\n'
      printf 'Example:\n  csv::fields "a,\"b,c\"" f && printf "%%s\\n" "${f[1]}"\n'
      ;;
    *)
      bs::cli::die "rfc: unknown RFC: $1 (implemented: 1925, 3986, 4122, 4180)"
      ;;
  esac
}

bs::cli::api_cmd() {
  local sub="${1:-}"
  shift || true

  load "lib/api/openapi"

  case "${sub}" in
    load)
      local name="${1-}" source="${2-}"
      if [[ $# -lt 2 ]] || is::empty "${name}" || is::empty "${source}"; then
        bs::cli::die "api load: requires NAME and FILE-or-URL (e.g. bs api load petstore ./openapi.json)"
      fi
      api::spec::load "${name}" "${source}" || bs::cli::die "api load: failed"
      ;;
    list)
      api::spec::list
      ;;
    info)
      [[ $# -ge 1 ]] || bs::cli::die "api info: requires spec NAME"
      api::spec::info "$1"
      ;;
    paths)
      [[ $# -ge 1 ]] || bs::cli::die "api paths: requires spec NAME (use --method GET to filter)"
      api::paths "$@"
      ;;
    call)
      [[ $# -ge 3 ]] || bs::cli::die "api call: requires NAME METHOD PATH (e.g. bs api call petstore GET /pets --json)"
      api::call "$@" || bs::cli::die "api call: failed"
      ;;
    drop)
      [[ $# -ge 1 ]] || bs::cli::die "api drop: requires spec NAME"
      api::spec::drop "$1"
      ;;
    -h|--help|"")
      printf 'Usage: bs api <subcommand> [args]\n\n'
      printf 'OpenAPI 3.x client / OpenAPI 3.x клиент\n'
      printf '  load NAME FILE|URL   load a spec (URL is cached) / загрузить схему\n'
      printf '  list                 loaded specs / загруженные схемы\n'
      printf '  info NAME            title, version, server / заголовок, версия, сервер\n'
      printf '  paths NAME [--method M]  list operations / список операций\n'
      printf '  call NAME METHOD PATH [--name VALUE ...] [--token T] [--body B] [--json]\n'
      printf '  drop NAME            unload a spec / выгрузить схему\n\n'
      printf 'Examples / Примеры:\n'
      printf '  bs api load petstore https://petstore3.swagger.io/api/v3/openapi.json\n'
      printf '  bs api call petstore GET /pet/{petId} --petId 1 --json\n'
      return 0 ;;
    *)
      bs::cli::die "api: unknown subcommand: ${sub} (see: bs api --help)"
      ;;
  esac
}

bs::cli::audit_cmd() {
  local -r audit_gnu_tools='grep[[:space:]]+-P|sed[[:space:]]+-z|sha256sum|stat[[:space:]]+-c|date[[:space:]]+\+%N|readlink[[:space:]]+-f|head[[:space:]]+-c'
  local audit_roots_str="${1:-core lib}"
  # IFS в CLI = $'\n\t' (без пробела) — префикс IFS=' ' только для read
  local -a audit_roots=()
  IFS=' ' read -ra audit_roots <<< "${audit_roots_str}"
  local file n bad=0
  for file in $(find "${audit_roots[@]}" -name '*.sh' 2>/dev/null | sort); do
    n="$(grep -cE "${audit_gnu_tools}" "${file}" 2>/dev/null || true)"
    if (( n > 0 )); then
      local tier
      tier="$(grep -m1 '^# @tier' "${file}" | awk '{print $3}' || true)"
      printf '  %-40s GNU-only: %-3d tier: %s\n' "${file}" "${n}" "${tier:-unspecified}"
      bad=1
    fi
  done
  if (( bad == 0 )); then
    printf 'No GNU-only tool usage found in %s\n' "${audit_roots_str}"
  fi
  return 0
}

# @private Каталог с командой bs для PATH: из манифеста (bin=), иначе рядом с
# установкой (<prefix>/bin), иначе сам BS_ROOT (репозиторий с лаунчером bs).
# Для ~/.local/bin возвращается буквальный $HOME/.local/bin — как в установщике.
# @private The directory with the bs command for PATH: from the manifest
# (bin=), else next to the install (<prefix>/bin), else BS_ROOT itself (a
# repository with the bs launcher). ~/.local/bin is returned as a literal
# $HOME/.local/bin — as the installer writes it.
bs::cli::init_shell_bin_dir() {
  local bin dir
  bin="$(bs::cli::install_info_get "${BS_ROOT}" bin)"
  if [[ -n "${bin}" ]]; then
    dir="$(dirname -- "${bin}")"
  elif [[ -f "${BS_ROOT%/lib/bs}/bin/bs" ]]; then
    dir="${BS_ROOT%/lib/bs}/bin"
  else
    dir="${BS_ROOT}"
  fi
  if [[ "${dir}" == "${HOME}/.local/bin" ]]; then
    printf '%s' '$HOME/.local/bin'
  else
    printf '%s' "${dir}"
  fi
}

bs::cli::init_shell_usage() {
  printf 'Usage: bs init-shell [SHELL | --list]\n\n'
  printf 'Print what to add to the rc file of your shell so that the bs command is found,\n'
  printf 'in the syntax of that shell, and how to apply it in the current terminal.\n'
  printf 'SHELL: bash zsh ash dash sh ksh mksh oksh osh fish nu (default: your shell).\n'
  printf '--list  show every known shell: rc file, reload command, BS tier.\n\n'
  printf 'Tiers: native (bash 4.2+: library and commands), hosted (other shells: the bs\n'
  printf 'command, run by a bash 4.2+), unsupported (no bash 4.2+ on the machine).\n'
  printf 'Печатает, что добавить в rc-файл вашей оболочки, чтобы находилась команда bs,\n'
  printf 'в синтаксисе этой оболочки, и как применить это в текущем терминале.\n'
}

bs::cli::init_shell_cmd() {
  local fam="" arg="${1:-}"
  case "${arg}" in
    -h|--help) bs::cli::init_shell_usage; return 0 ;;
    --list)
      local f
      printf '%-6s %-9s %-52s %s\n' "shell" "tier" "rc file" "reload"
      for f in bash zsh ash dash sh ksh mksh oksh osh fish nu; do
        printf '%-6s %-9s %-52s %s\n' "${f}" "$(bs_shell_tier "${f}")" \
          "$(bs_shell_rc_file "${f}")" "$(bs_shell_reload_hint "${f}")"
      done
      return 0 ;;
    "") fam="$(bs_shell_user)" ;;
    *)
      fam="$(bs_shell_of_name "${arg}")"
      [[ "${fam}" != "unknown" ]] \
        || bs::cli::die "init-shell: unknown shell: ${arg} (known: bash zsh ash dash sh ksh mksh oksh osh fish nu; see: bs init-shell --list)"
      ;;
  esac
  bs_shell_known "${fam}" \
    || bs::cli::die "init-shell: no rc recipe for the shell '${fam}' (see: bs init-shell --list)"

  local rc tier dir
  rc="$(bs_shell_rc_file "${fam}")"
  tier="$(bs_shell_tier "${fam}")"
  dir="$(bs::cli::init_shell_bin_dir)"
  printf '# BS for %s (tier: %s) - add to %s\n' "${fam}" "${tier}" "${rc}"
  if [[ "${fam}" == "bash" ]]; then
    # Только bash 4.2+ может подключить BS как библиотеку (source)
    # Only bash 4.2+ can source BS as a library
    printf 'export BS_ROOT="%s"\n' "${BS_ROOT}"
    # shellcheck disable=SC2016  # ${BS_ROOT} раскроет rc-файл, не мы
    printf 'source "${BS_ROOT}/bootstrap/init.sh"\n'
  fi
  bs_shell_path_line "${fam}" "${dir}"
  printf '# apply in this terminal: %s\n' "$(bs_shell_reload_hint "${fam}")"
  if [[ "${fam}" != "bash" ]]; then
    printf '# %s\n' "$(bs_shell_tier_desc "${tier}")"
  fi
}

# @private Boxed notice printed WITHOUT log prefixes — timestamps would
# break the frame (log::header suffers from this in timestamped output).
# Рамка-уведомление БЕЗ лог-префиксов — таймстампы ломают рамку
# (log::header страдает этим при включённых таймстампах).
# @param $1 Title / Заголовок
# @param $@ Body lines, hard-wrapped at inner width / Строки тела с переносом
bs::cli::update_box() {
  local -r title="$1"
  shift
  local -r inner=58
  local -a body=()
  local text
  # Первая строка тела — какая копия bs печатает это уведомление.
  # First body line: which bs copy prints this notice.
  bs::cli::update_ctx
  local -a run_rows=()
  mapfile -t run_rows <<< "${UPDATE_RUN_BLOCK}"
  set -- "${run_rows[@]}" "" "$@"
  for text in "$@"; do
    while (( ${#text} > inner )); do
      body+=("${text:0:inner}")
      text="${text:inner}"
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

  # Паддинг вручную по символам: bash printf '%-*s' считает ширину в БАЙТАХ,
  # с кириллицей рамка разъезжается. ${#x} считает символы (= клетки для
  # кириллицы и глифов рамки).
  # Pad by CHARACTERS: bash printf '%-*s' measures width in BYTES, which
  # breaks the frame with Cyrillic. ${#x} counts chars (= cells here).
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

# URL репозитория по умолчанию для `bs update --github` (переопределяется
# флагом --repo или переменной BS_UPDATE_REPO).
# Default repository URL for `bs update --github` (override with --repo or
# the BS_UPDATE_REPO variable).
readonly UPDATE_DEFAULT_REPO="https://github.com/Igormm/bs"

# @private Каталог со скачанным источником; удаляется стеком cleanup.
# @private Directory with the downloaded source; removed by the cleanup stack.
UPDATE_FETCH_DIR=""

bs::cli::update_fetch_cleanup() {
  [[ -n "${UPDATE_FETCH_DIR}" ]] && rm -rf -- "${UPDATE_FETCH_DIR}"
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
bs::cli::update_fetch() {
  local -r repo="${1%.git}"
  local -r ref="$2"
  UPDATE_FETCH_DIR="$(mktemp -d)" \
    || bs::cli::update_die "update: cannot create a temporary directory / не удалось создать временный каталог"
  cleanup::add bs::cli::update_fetch_cleanup
  local -r dest="${UPDATE_FETCH_DIR}/src"
  if ! utils::has git && ! utils::has curl && ! utils::has wget; then
    bs::cli::update_die "update: нужен git или curl/wget для --github / need git or curl/wget for --github (or use: bs update --from <repo-path>)"
  fi
  local -a limit=()
  utils::has timeout && limit=(timeout 120)

  local err="" repo_reachable=0
  if utils::has git; then
    if err="$(GIT_TERMINAL_PROMPT=0 "${limit[@]}" git clone --quiet --depth 1 --branch "${ref}" -- "${repo}" "${dest}" 2>&1)"; then
      return 0
    fi
    rm -rf -- "${dest}"
    if GIT_TERMINAL_PROMPT=0 "${limit[@]}" git ls-remote --exit-code -- "${repo}" HEAD >/dev/null 2>&1; then
      repo_reachable=1
    fi
  fi
  if (( repo_reachable == 1 )); then
    bs::cli::update_die "update: ветка/тег '${ref}' не найден в ${repo} / branch or tag '${ref}' not found in ${repo} (--ref REF)"
  fi
  mkdir -p -- "${dest}"

  local -r archive="${repo}/archive/${ref}.tar.gz"
  if utils::has curl; then
    if curl -fsSL -- "${archive}" 2>/dev/null | utils::quiet tar -xz -C "${dest}" --strip-components=1; then
      return 0
    fi
  elif utils::has wget; then
    if wget -qO- -- "${archive}" 2>/dev/null | utils::quiet tar -xz -C "${dest}" --strip-components=1; then
      return 0
    fi
  fi
  bs::cli::update_die "update: не удалось получить ${repo} (${ref}): нет сети, репозиторий не найден или ветки/тега нет / cannot fetch ${repo} (${ref}): no network, repository or ref not found${err:+ [git: ${err%%$'\n'*}]}"
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
bs::cli::update_local_state() {
  local -r dir="$1" repo="${2%.git}" ref="$3"
  if ! utils::has git || ! [[ -e "${dir}/.git" ]]; then
    printf 'unknown\n'
    return 0
  fi
  local -a limit=()
  utils::has timeout && limit=(timeout 15)
  local remote_sha head_sha
  remote_sha="$(GIT_TERMINAL_PROMPT=0 "${limit[@]}" git ls-remote -- "${repo}" "refs/heads/${ref}" 2>/dev/null | cut -f1)" || remote_sha=""
  head_sha="$(git -C "${dir}" rev-parse HEAD 2>/dev/null)" || head_sha=""
  if [[ -z "${remote_sha}" || -z "${head_sha}" ]]; then
    printf 'unknown\n'
  elif [[ "${remote_sha}" == "${head_sha}" ]]; then
    printf 'same\n'
  elif utils::quiet git -C "${dir}" merge-base --is-ancestor "${remote_sha}" HEAD; then
    printf 'ahead\n'
  else
    printf 'behind\n'
  fi
}

# @private Каталог установки из обёртки `bs` (install.sh пишет в неё
# export BS_ROOT="..."). Пустой вывод, если файл — не обёртка.
# @private Install directory named by a `bs` wrapper (install.sh writes
# export BS_ROOT="..." into it). Empty output if the file is not a wrapper.
# @param $1 Path to a `bs` executable / Путь к исполняемому `bs`
bs::cli::update_wrapper_root() {
  local -r file="$1"
  local -r re='^export BS_ROOT="([^"$]+)"$'
  local line n=0
  while IFS= read -r line && (( n++ < 5 )); do
    if [[ "${line}" =~ ${re} ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  done < "${file}" 2>/dev/null
  return 0
}

# Системный каталог установки; префикс переопределяется BS_SYSTEM_PREFIX
# (по умолчанию /usr/local) — тесты моделируют system-установку без root.
# System install directory; the prefix is overridden by BS_SYSTEM_PREFIX
# (default /usr/local) so tests can model a system install without root.
bs::cli::update_system_lib() { printf '%s/lib/bs\n' "${BS_SYSTEM_PREFIX:-/usr/local}"; }

# @private Вид запущенной копии: mode из манифеста, source checkout, no manifest.
# @private Kind of the running copy: manifest mode, source checkout, no manifest.
bs::cli::bs_running_kind() {
  local mode=""
  mode="$(bs::cli::install_info_get "${BS_ROOT}" mode)"
  if [[ -n "${mode}" ]]; then
    printf '%s' "${mode}"
  elif [[ -e "${BS_ROOT}/.git" || -d "${BS_ROOT}/tests" ]]; then
    printf 'source checkout'
  elif [[ -e "${BS_ROOT}/.install" ]]; then
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
bs::cli::bs_running_info() {
  local kind commit="" dirty="" out upd="" src=""
  kind="$(bs::cli::bs_running_kind)"
  out="bs $(bs::version::get) | ${BS_ROOT} | ${kind}"
  if [[ "${kind}" == "source checkout" ]]; then
    if [[ -e "${BS_ROOT}/.git" ]] && utils::has git; then
      commit="$(git -C "${BS_ROOT}" rev-parse --short=7 HEAD 2>/dev/null)" || commit=""
      [[ -z "$(git -C "${BS_ROOT}" status --porcelain 2>/dev/null)" ]] || dirty=", with uncommitted changes"
      [[ -z "${commit}" ]] || out+=" | commit ${commit}${dirty}"
    fi
  elif [[ -f "${BS_ROOT}/.install" ]]; then
    src="$(bs::cli::install_info_get "${BS_ROOT}" source_commit)"
    out+=" | installed $(bs::cli::install_info_get "${BS_ROOT}" installed_at) by $(bs::cli::install_info_get "${BS_ROOT}" installed_by)"
    out+=" | source $(bs::cli::install_info_get "${BS_ROOT}" source) @ $(bs::cli::short_sha "${src}")"
    upd="$(bs::cli::install_info_get "${BS_ROOT}" updated_at)"
    if [[ -n "${upd}" ]]; then
      out+=" | updated ${upd} from $(bs::cli::install_info_get "${BS_ROOT}" updated_from) @ $(bs::cli::short_sha "$(bs::cli::install_info_get "${BS_ROOT}" updated_commit)")"
    fi
  fi
  printf '%s' "${out}"
}

# @private Подготовить сводки (один раз за запуск) / prepare summaries once
bs::cli::update_ctx() {
  [[ -n "${UPDATE_RUN_INFO}" ]] && return 0
  UPDATE_RUN_INFO="$(bs::cli::bs_running_info)"
  UPDATE_RUN_BLOCK="$(bs::cli::bs_running_block)"
  UPDATE_RUN_SHORT="Запущен / Running: ${UPDATE_RUN_INFO}"
  return 0
}

# ERROR/WARN с короткой сводкой запущенной копии в конце.
# ERROR/WARN with the short running-copy summary appended.
bs::cli::update_die() {
  bs::cli::update_ctx
  log::error "$1 (${UPDATE_RUN_SHORT})"
  bs::exit "${2:-1}"
}

bs::cli::update_warn() {
  bs::cli::update_ctx
  log::warn "$1 (${UPDATE_RUN_SHORT})"
  return 0
}

# Значение флага: непустое и не похожее на другой флаг (--ref --github).
# A flag value: non-empty and not another flag (--ref --github).
bs::cli::update_flag_value() {
  local -r flag="$1" what="$2"
  shift 2
  if [[ $# -lt 1 || -z "$1" || "$1" == -* ]]; then
    bs::cli::update_die "update: ${flag} требует значение / requires ${what}"
  fi
}

bs::cli::update_realpath() { readlink -f -- "$1" 2>/dev/null || printf '%s\n' "$1"; }

# @private Каталог похож на установку BS: bs + bootstrap/init.sh либо .install.
# @private The directory looks like a BS install: bs + bootstrap/init.sh or .install.
bs::cli::update_is_install() {
  [[ -d "$1" ]] && { [[ -f "$1/bs" && -f "$1/bootstrap/init.sh" ]] || [[ -f "$1/.install" ]]; }
}

# @private Исходный репозиторий (.git или tests/): не установка / a source checkout
bs::cli::update_is_checkout() { [[ -e "$1/.git" || -d "$1/tests" ]]; }

# @private Чего не хватает каталогу-источнику (по строке на пункт).
# @private What a source directory lacks (one item per line).
bs::cli::update_source_missing() {
  local -r d="$1"
  if [[ ! -d "${d}" ]]; then
    printf '%s\n' "каталог не найден / directory not found"
    return 0
  fi
  [[ -f "${d}/bs" ]] || printf '%s\n' "bs"
  [[ -f "${d}/bootstrap/init.sh" ]] || printf '%s\n' "bootstrap/init.sh"
  [[ -f "${d}/bootstrap/loader.sh" ]] || printf '%s\n' "bootstrap/loader.sh"
  [[ -d "${d}/core" ]] || printf '%s\n' "core/"
  [[ -d "${d}/lib" ]] || printf '%s\n' "lib/"
  if [[ ! -f "${d}/core/version.sh" ]]; then
    printf '%s\n' "core/version.sh"
  elif [[ -z "$(bs::version::of "${d}")" ]]; then
    printf '%s\n' "core/version.sh: версия не читается / no readable version"
  fi
  return 0
}

# @private Манифест читаем и выглядит как key=value с mode=.
# @private The manifest is readable key=value text with a mode= line.
bs::cli::update_manifest_valid() {
  local line has=0
  [[ -f "$1" && -r "$1" ]] || return 1
  while IFS= read -r line || [[ -n "${line}" ]]; do
    case "${line}" in
      ''|'#'*) ;;
      mode=*) has=1 ;;
      [a-z_]*=*) ;;
      *) return 1 ;;
    esac
  done < "$1"
  (( has == 1 ))
}

# @private Обёртка установки: из манифеста, иначе из пути .../lib/bs.
# @private The wrapper of an install: from the manifest, else from .../lib/bs.
bs::cli::update_install_wrapper() {
  local w=""
  w="$(bs::cli::install_info_get "$1" bin)"
  if [[ -z "${w}" && "$1" == */lib/bs ]]; then
    w="${1%/lib/bs}/bin/bs"
  fi
  printf '%s' "${w}"
}

# @private Домашний каталог пользователя SUDO_USER (пусто, если неизвестен).
# @private Home directory of SUDO_USER (empty if unknown).
bs::cli::update_sudo_home() {
  [[ -n "${SUDO_USER:-}" ]] || return 0
  utils::has getent || return 0
  getent passwd "${SUDO_USER}" 2>/dev/null | cut -d: -f6 || true
}

# @private Пояснение, почему цель не найдена, и что делать (строки для рамки).
# @param $1 Target / цель; $2 kind: local|system|lib|auto
# @private Why a target is missing and what to do (box lines).
bs::cli::update_missing_lines() {
  local -r t="$1" kind="$2" verb="${3:-update}"
  local sys loc ver sh
  sys="$(bs::cli::update_system_lib)"
  loc="${HOME}/.local/lib/bs"
  case "${kind}" in
    local)
      printf '%s\n' "• ${t} — локальной установки нет / no local install"
      if bs::cli::update_is_install "${sys}" && ! bs::cli::update_is_checkout "${sys}"; then
        ver="$(bs::version::of "${sys}")"
        printf '%s\n' "  но найдена системная / but a system install exists: ${sys} (версия/version ${ver:-?})" \
          "  → bs ${verb} --system   или / or   bs ${verb}"
      else
        printf '%s\n' "  BS не установлена / BS is not installed → ./install.sh --local"
      fi
      if (( EUID == 0 )) || [[ -n "${SUDO_USER:-}" ]]; then
        printf '%s\n' "  вы root/sudo (HOME=${HOME}): ~ — это домашний каталог root / you run as root: ~ is root's home"
        sh="$(bs::cli::update_sudo_home)"
        if [[ -n "${sh}" && "${sh}" != "${HOME}" ]]; then
          printf '%s\n' "  установка пользователя ${SUDO_USER} / its local install: ${sh}/.local/lib/bs" \
            "  → bs ${verb} --lib ${sh}/.local/lib/bs"
        fi
      fi ;;
    system)
      printf '%s\n' "• ${t} — системной установки нет / no system install"
      if bs::cli::update_is_install "${loc}" && ! bs::cli::update_is_checkout "${loc}"; then
        ver="$(bs::version::of "${loc}")"
        printf '%s\n' "  но найдена локальная / but a local install exists: ${loc} (версия/version ${ver:-?})" \
          "  → bs ${verb} --local   или / or   bs ${verb}"
      else
        printf '%s\n' "  BS не установлена / BS is not installed → ./install.sh --local  (sudo ./install.sh)"
      fi ;;
    *)
      printf '%s\n' "• ${t} — каталог не найден / directory not found" \
        "  проверьте путь (обычно …/lib/bs) / check the path (usually …/lib/bs)" \
        "  установить / install: PREFIX=<dir> ./install.sh   или / or   ./install.sh --local" ;;
  esac
}

UPDATE_LOCKS=()           # занятые каталоги-замки / held lock dirs

UPDATE_LOCK_SUDO=()       # "sudo" или "" для каждого замка

UPDATE_INF_TARGET=""      # цель, чья замена в процессе / target being replaced

UPDATE_INF_TMP=""

UPDATE_INF_OLD=""

UPDATE_INF_SUDO=""

# @private Вернуть прежние части из old-каталога и убрать временные.
# @private Restore the previous parts from the old dir and drop the temp dirs.
bs::cli::update_rollback() {
  local -r target="$1" tmp="$2" old="$3" sudo="$4"
  local part
  local -a r=()
  [[ -z "${sudo}" ]] || r=(sudo)
  for part in bs bootstrap core lib; do
    if [[ -e "${old}/${part}" ]]; then
      if [[ "${part}" == "bs" ]]; then
        "${r[@]}" mv -f -- "${old}/bs" "${target}/bs" || true
      else
        "${r[@]}" rm -rf -- "${target:?}/${part}" || true
        "${r[@]}" mv -- "${old}/${part}" "${target}/${part}" || true
      fi
    elif [[ -e "${old}/.added-${part}" ]]; then
      "${r[@]}" rm -rf -- "${target:?}/${part}" || true
    fi
  done
  "${r[@]}" rm -rf -- "${tmp}" "${old}" || true
}

# @private EXIT/сигнал: незавершённая замена откатывается, замки снимаются.
# @private EXIT/signal: an unfinished swap is rolled back and locks released.
bs::cli::update_inflight_cleanup() {
  local i
  if [[ -n "${UPDATE_INF_TARGET}" ]]; then
    bs::cli::update_rollback "${UPDATE_INF_TARGET}" "${UPDATE_INF_TMP}" "${UPDATE_INF_OLD}" "${UPDATE_INF_SUDO}"
    UPDATE_INF_TARGET=""
  fi
  for i in "${!UPDATE_LOCKS[@]}"; do
    if [[ -n "${UPDATE_LOCK_SUDO[i]}" ]]; then
      sudo rm -rf -- "${UPDATE_LOCKS[i]}" || true
    else
      rm -rf -- "${UPDATE_LOCKS[i]}" || true
    fi
  done
  UPDATE_LOCKS=()
  UPDATE_LOCK_SUDO=()
  return 0
}

# @private Убрать хвосты упавших запусков (.update.PID / .update-old.PID,
# чей процесс мёртв). Незавершённая замена откатывается; завершённая
# (маркер .committed) просто удаляется.
# @private Drop leftovers of crashed runs (.update.PID / .update-old.PID whose
# process is dead). An unfinished swap is rolled back; a committed one
# (.committed marker) is simply deleted.
# @param $1 Target / $2 optional "sudo"
bs::cli::update_cleanup_stale() {
  local -r target="$1" sudo="${2:-}"
  local d pid
  local -a r=()
  [[ -z "${sudo}" ]] || r=(sudo)
  for d in "${target}"/.update.* "${target}"/.update-old.*; do
    [[ -d "${d}" ]] || continue
    pid="${d##*.}"
    [[ "${pid}" =~ ^[0-9]+$ ]] || continue
    kill -0 "${pid}" 2>/dev/null && continue
    if [[ "${d}" == */.update-old.* && ! -e "${d}/.committed" ]]; then
      bs::cli::update_rollback "${target}" "${target}/.update.${pid}" "${d}" "${sudo}"
      log::info "update: восстановлена установка после прерванного запуска / restored after an interrupted run: ${target}"
    fi
    "${r[@]}" rm -rf -- "${d}" || true
  done
  return 0
}

# @private Взять замок цели (mkdir атомарен; pid устаревшего замка проверяется).
# @private Take the target lock (mkdir is atomic; a stale lock pid is checked).
# @return 0 got it, 1 another update is running
bs::cli::update_lock() {
  local -r target="$1" sudo="${2:-}"
  local -r lock="${target}/.update-lock"
  local pid=""
  local -a r=()
  [[ -z "${sudo}" ]] || r=(sudo)
  for _ in 1 2; do
    if "${r[@]}" mkdir -- "${lock}" 2>/dev/null; then
      printf '%s\n' "$$" | "${r[@]}" tee -- "${lock}/pid" >/dev/null || true
      UPDATE_LOCKS+=("${lock}")
      UPDATE_LOCK_SUDO+=("${sudo}")
      return 0
    fi
    pid=""
    [[ -r "${lock}/pid" ]] && pid="$(<"${lock}/pid")"
    if [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null; then
      return 1
    fi
    "${r[@]}" rm -rf -- "${lock}" || return 1
  done
  return 1
}

bs::cli::update_unlock() {
  local i
  for i in "${!UPDATE_LOCKS[@]}"; do
    if [[ "${UPDATE_LOCKS[i]}" == "$1/.update-lock" ]]; then
      if [[ -n "${UPDATE_LOCK_SUDO[i]}" ]]; then sudo rm -rf -- "${UPDATE_LOCKS[i]}" || true
      else rm -rf -- "${UPDATE_LOCKS[i]}" || true; fi
      unset 'UPDATE_LOCKS[i]' 'UPDATE_LOCK_SUDO[i]'
    fi
  done
  return 0
}

# @private Самопроверка установленной копии: bs version печатает версию источника.
# @private Smoke test of the installed copy: bs version prints the source's version.
bs::cli::update_smoke() {
  local -r t="$1" want="$2"
  local out
  local -a limit=()
  utils::has timeout && limit=(timeout 60)
  out="$(env -u BS_INITIALIZED -u BS_VERSION BS_ROOT="${t}" BS_HOME="${t}" BS_SILENT=1 \
    "${limit[@]}" bash "${t}/bs" version 2>&1)" || return 1
  [[ "${out}" == *"version: ${want}"* ]]
}

# @private Заменить части установки: новое — во временный каталог, старое —
# в .update-old.PID, затем smoke-test; при любом сбое — откат.
# @private Replace install parts: new into a temp dir, old into
# .update-old.PID, then smoke test; any failure rolls back.
# @return 0 ok, 1 copy/swap failed, 2 smoke test failed (both rolled back)
bs::cli::update_apply() {
  local -r target="$1" from="$2" want="$3"
  shift 3
  local -a r=("$@")
  local -r tmp="${target}/.update.$$" old="${target}/.update-old.$$"
  local part
  "${r[@]}" rm -rf -- "${tmp}" "${old}" || return 1
  "${r[@]}" mkdir -p -- "${tmp}" "${old}" || { "${r[@]}" rm -rf -- "${tmp}" "${old}"; return 1; }
  UPDATE_INF_TARGET="${target}" UPDATE_INF_TMP="${tmp}" UPDATE_INF_OLD="${old}"
  UPDATE_INF_SUDO="${r[*]:-}"
  if ! "${r[@]}" cp -a "${from}/bootstrap" "${from}/core" "${from}/lib" "${from}/bs" "${tmp}/"; then
    bs::cli::update_rollback "${target}" "${tmp}" "${old}" "${UPDATE_INF_SUDO}"
    UPDATE_INF_TARGET=""
    return 1
  fi
  local ok=1
  for part in bs bootstrap core lib; do
    if [[ "${part}" == "bs" ]]; then
      if [[ -e "${target}/bs" ]]; then
        "${r[@]}" cp -a -- "${target}/bs" "${old}/bs" || { ok=0; break; }
      else
        "${r[@]}" touch -- "${old}/.added-bs" || { ok=0; break; }
      fi
      "${r[@]}" mv -f -- "${tmp}/bs" "${target}/bs" || { ok=0; break; }
    else
      if [[ -e "${target}/${part}" ]]; then
        "${r[@]}" mv -- "${target}/${part}" "${old}/${part}" || { ok=0; break; }
      else
        "${r[@]}" touch -- "${old}/.added-${part}" || { ok=0; break; }
      fi
      "${r[@]}" mv -- "${tmp}/${part}" "${target}/${part}" || { ok=0; break; }
    fi
  done
  if (( ok == 0 )); then
    bs::cli::update_rollback "${target}" "${tmp}" "${old}" "${UPDATE_INF_SUDO}"
    UPDATE_INF_TARGET=""
    return 1
  fi
  if ! bs::cli::update_smoke "${target}" "${want}"; then
    bs::cli::update_rollback "${target}" "${tmp}" "${old}" "${UPDATE_INF_SUDO}"
    UPDATE_INF_TARGET=""
    return 2
  fi
  "${r[@]}" touch -- "${old}/.committed" || true
  UPDATE_INF_TARGET=""
  "${r[@]}" rm -rf -- "${tmp}" "${old}" || true
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
# @param $@ Optional command prefix (sudo) / Необязательный префикс (sudo)
bs::cli::update_manifest() {
  local -r target="$1" from="$2" label="$3"
  shift 3
  local -r file="${target}/.install"
  local content="" line commit=""
  if [[ -d "${file}" ]]; then
    bs::cli::update_warn "update: ${file} — каталог, манифест не записан / is a directory, manifest not written"
    return 0
  fi
  if bs::cli::update_manifest_valid "${file}"; then
    while IFS= read -r line || [[ -n "${line}" ]]; do
      case "${line}" in
        version=*|updated_at=*|updated_from=*|updated_commit=*) ;;
        *) content+="${line}"$'\n' ;;
      esac
    done < "${file}"
  else
    if [[ -e "${file}" ]]; then
      "$@" mv -f -- "${file}" "${file}.bad" 2>/dev/null || "$@" rm -f -- "${file}" || true
      bs::cli::update_warn "update: манифест повреждён или нечитаем, создан заново (старый: ${file}.bad) / manifest corrupt or unreadable, recreated (old one: ${file}.bad)"
    fi
    local mode="custom"
    [[ "${target}" == "${HOME}/.local/lib/bs" ]] && mode="local"
    [[ "${target}" == "$(bs::cli::update_system_lib)" ]] && mode="system"
    content+="# BS install manifest — written by install.sh, updated by bs update"$'\n'
    content+="mode=${mode}"$'\n'
    content+="prefix=${target%/lib/bs}"$'\n'
    content+="lib=${target}"$'\n'
    content+="bin=${target%/lib/bs}/bin/bs"$'\n'
  fi
  if utils::has git && [[ -e "${from}/.git" ]]; then
    commit="$(git -C "${from}" rev-parse HEAD 2>/dev/null)" || commit=""
  fi
  # Версия ИСТОЧНИКА, а не запущенного bs / the SOURCE version, not the running bs
  local version
  version="$(bs::version::of "${from}")"
  [[ -n "${version}" ]] || version="$(bs::version::get)"
  content+="version=${version}"$'\n'
  content+="updated_at=$(date '+%Y-%m-%d %H:%M:%S')"$'\n'
  content+="updated_from=${label}"$'\n'
  content+="updated_commit=${commit}"$'\n'
  printf '%s' "${content}" | "$@" tee -- "${file}" >/dev/null \
    || bs::cli::update_warn "update: cannot write the install manifest: ${file}"
  return 0
}

# @private Кто из обёрток `bs` в PATH что запускает (по порядку PATH).
# @private Which `bs` wrapper in PATH runs which copy (in PATH order).
bs::cli::update_path_summary() {
  local w root i=0
  printf 'bs в PATH по порядку / bs in PATH, in order:\n'
  while IFS= read -r w; do
    i=$(( i + 1 ))
    root="$(bs::cli::update_wrapper_root "${w}")"
    if [[ -n "${root}" ]]; then
      printf '  %d. %s → %s (version %s)%s\n' "${i}" "${w}" "${root}" \
        "$(bs::version::of "${root}")" "$([[ ${i} -eq 1 ]] && printf ' ← запускается первой / runs first')"
    else
      printf '  %d. %s (не обёртка BS / not a BS wrapper)\n' "${i}" "${w}"
    fi
  done < <(type -aP bs 2>/dev/null)
  (( i > 0 )) || printf '  (bs не найден в PATH / bs not found in PATH)\n'
  return 0
}

# @private Можно ли безопасно подтянуть репозиторий: это git-репозиторий, в нём
# нет незакоммиченных правок отслеживаемых файлов и у ветки есть upstream.
# Печатает причину отказа (одной строкой) и возвращает 1, если нельзя.
# @private Can the repository be pulled safely: a git repository, no uncommitted
# changes to tracked files, and the branch has an upstream. Prints the reason
# (one line) and returns 1 when it cannot.
# @param $1 Repository / Репозиторий
bs::cli::update_pull_blocker() {
  local -r dir="$1"
  if ! utils::has git || [[ ! -e "${dir}/.git" ]]; then
    printf 'не git-репозиторий (или нет git) / not a git repository (or no git)'
    return 1
  fi
  if [[ -n "$(git -C "${dir}" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
    printf 'есть незакоммиченные правки отслеживаемых файлов / uncommitted changes to tracked files'
    return 1
  fi
  if ! git -C "${dir}" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
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
bs::cli::update_pull_checkout() {
  local -r dir="$1"
  local why out before after
  if ! why="$(bs::cli::update_pull_blocker "${dir}")"; then
    bs::cli::update_warn "update: git pull пропущен для ${dir}: ${why}"
    return 1
  fi
  before="$(git -C "${dir}" rev-parse --short=7 HEAD 2>/dev/null || printf '?')"
  local -a limit=()
  utils::has timeout && limit=(timeout 120)
  if ! out="$(GIT_TERMINAL_PROMPT=0 "${limit[@]}" git -C "${dir}" pull --ff-only 2>&1)"; then
    bs::cli::update_warn "update: git pull --ff-only не удался в ${dir} (история разошлась или нет сети) / failed (diverged history or no network): ${out//$'\n'/ | }"
    return 1
  fi
  after="$(git -C "${dir}" rev-parse --short=7 HEAD 2>/dev/null || printf '?')"
  if [[ "${before}" == "${after}" ]]; then
    log::info "update: репозиторий уже актуален / the repository is already up to date: ${dir} @ ${after}"
  else
    log::info "update: репозиторий подтянут / the repository was pulled: ${dir} ${before} → ${after}"
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
bs::cli::update_state_summary() {
  local -r checkout="$1" state="$2" inst_ver="$3"
  [[ -n "${checkout}" ]] || return 0
  local repo_ver commit="" rel verdict_ok=1 rc=0
  repo_ver="$(bs::version::of "${checkout}")"
  if [[ -e "${checkout}/.git" ]] && utils::has git; then
    commit="$(git -C "${checkout}" rev-parse --short=7 HEAD 2>/dev/null || true)"
  fi
  case "${state}" in
    same)   rel="совпадает с GitHub / same as GitHub" ;;
    ahead)  rel="впереди GitHub (есть непушенные коммиты) / ahead of GitHub" ;;
    behind) rel="ОТСТАЁТ от GitHub / BEHIND GitHub"; verdict_ok=0 ;;
    *)      rel="связь с GitHub не проверена (нет сети?) / relation to GitHub unknown" ;;
  esac
  if [[ -n "${inst_ver}" && -n "${repo_ver}" ]]; then
    bs::version::compare "${repo_ver}" "${inst_ver}" || rc=$?
    (( rc != 2 )) || verdict_ok=0
  fi
  printf '\n== Состояние после обновления / State after the update ==\n'
  printf '  Установка / Install:   версия / version %s\n' "${inst_ver:-?}"
  printf '  Репозиторий / Repo:    %s — версия / version %s%s — %s\n' \
    "${checkout}" "${repo_ver:-?}" "${commit:+, commit ${commit}}" "${rel}"
  if (( verdict_ok == 1 )); then
    printf '  Вердикт / Verdict:     установка и репозиторий согласованы / the install and the repository agree\n'
  else
    printf '  Вердикт / Verdict:     ⚠ examples/ и tests/ репозитория старее установки (bs update их не копирует) / the repository is older than the install\n'
    printf '  Что сделать / Fix:     bs update --pull   (или / or:  git -C %s pull)\n' "${checkout}"
  fi
}

bs::cli::update_cmd() {
  local from="${BS_ROOT}"
  local from_explicit=0
  local github=0
  local pull=0
  local repo="${BS_UPDATE_REPO:-${UPDATE_DEFAULT_REPO}}"
  local repo_set=0 ref_set=0
  local ref="main"
  local -a targets=() tkinds=()
  local explicit=0
  local verbose=0
  local a banner=1
  for a in "$@"; do
    [[ "${a}" == "-h" || "${a}" == "--help" ]] && banner=0
  done
  bs::cli::update_ctx
  # Первая строка любого реального запуска: какая копия bs работает.
  # First line of every real run: which bs copy is running.
  if (( banner == 1 )); then
    printf '%s\n' "${UPDATE_RUN_BLOCK}"
  fi
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  cleanup::add bs::cli::update_inflight_cleanup

  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      --local)
        explicit=1
        targets+=("${HOME}/.local/lib/bs"); tkinds+=(local)
        shift ;;
      --system)
        explicit=1
        targets+=("$(bs::cli::update_system_lib)"); tkinds+=(system)
        shift ;;
      --lib)
        shift
        bs::cli::update_flag_value "--lib" "a target directory" "$@"
        explicit=1
        targets+=("$1"); tkinds+=(lib)
        shift ;;
      --from)
        shift
        bs::cli::update_flag_value "--from" "a source directory" "$@"
        if (( from_explicit == 1 )) && [[ "${from}" != "$1" ]]; then
          bs::cli::update_die "update: --from указан дважды с разными значениями / given twice with different values: ${from} и/and $1"
        fi
        from="$1"
        from_explicit=1
        shift ;;
      --github)
        github=1
        shift ;;
      --pull)
        pull=1
        shift ;;
      --repo)
        shift
        bs::cli::update_flag_value "--repo" "a repository URL" "$@"
        [[ "$1" != *[[:space:]]* ]] \
          || bs::cli::update_die "update: --repo не может содержать пробелы / must not contain whitespace: '$1'"
        if (( repo_set == 1 )) && [[ "${repo}" != "$1" ]]; then
          bs::cli::update_die "update: --repo указан дважды с разными значениями / given twice with different values"
        fi
        github=1
        repo="$1"; repo_set=1
        shift ;;
      --ref)
        shift
        bs::cli::update_flag_value "--ref" "a branch or tag" "$@"
        [[ "$1" =~ ^[A-Za-z0-9._/@+-]+$ ]] \
          || bs::cli::update_die "update: недопустимое имя ветки/тега / invalid branch or tag name: '$1'"
        if (( ref_set == 1 )) && [[ "${ref}" != "$1" ]]; then
          bs::cli::update_die "update: --ref указан дважды с разными значениями / given twice with different values"
        fi
        github=1
        ref="$1"; ref_set=1
        shift ;;
      -v|--verbose)
        verbose=1
        shift ;;
      -h|--help)
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
        return 0 ;;
      *)
        bs::cli::update_die "update: неизвестный аргумент / unknown argument: $1 (bs update --help)" ;;
    esac
  done

  # Источник: если CWD — каталог репозитория, используем его.
  # Source: if CWD is the repo directory, use it as the source.
  if (( github == 1 && from_explicit == 1 )); then
    bs::cli::update_die "update: --from и --github несовместимы / are mutually exclusive"
  fi
  # Источник: если CWD — каталог репозитория, используем его.
  # Source: if CWD is the repo directory, use it as the source.
  if (( github == 1 && from_explicit == 1 )); then
    bs::cli::update_die "update: --from and --github are mutually exclusive"
  fi
  # Локальный checkout рядом (для сверки с GitHub): CWD-репозиторий, иначе
  # BS_ROOT, если это репозиторий, а не установленная копия (в ней нет tests/).
  # Local checkout around (to compare with GitHub): the CWD repo, else BS_ROOT
  # when it is a repo and not an installed copy (which has no tests/).
  local checkout=""
  if (( from_explicit == 1 )); then
    checkout="${from}"
  elif [[ -f "${PWD}/bs" && -d "${PWD}/core" && -d "${PWD}/tests" ]]; then
    checkout="${PWD}"
  elif is::dir "${from}/tests"; then
    checkout="${from}"
  fi

  if (( github == 0 && from_explicit == 0 )); then
    if [[ -n "${checkout}" ]]; then
      from="${checkout}"
    else
      # Развилка: bs запущен из установленной копии и репозитория рядом
      # нет — локального источника нет, берём с GitHub.
      # Fork: bs runs from an installed copy and there is no repo around —
      # no local source, so fetch from GitHub.
      github=1
    fi
  fi

  # Конфликт источников: локальный checkout и GitHub могут расходиться.
  # Source conflict: the local checkout and GitHub may differ.
  local state="unknown"
  # --pull: сначала подтянуть сам репозиторий (bs update его не трогает)
  # --pull: first pull the repository itself (bs update does not touch it)
  if (( pull == 1 )); then
    if [[ -z "${checkout}" ]]; then
      bs::cli::update_die "update: --pull: рядом нет репозитория BS — запустите из его каталога или укажите --from DIR / no BS repository around: run from its directory or pass --from DIR"
    fi
    bs::cli::update_pull_checkout "${checkout}" \
      || bs::cli::update_die "update: --pull не выполнен, ничего не изменено / --pull failed, nothing was changed"
  fi
  [[ -n "${checkout}" ]] && state="$(bs::cli::update_local_state "${checkout}" "${repo}" "${ref}")"
  if (( github == 0 )) && [[ "${state}" == "behind" ]]; then
    bs::cli::update_warn "update: local repo is behind ${repo%.git}@${ref} — it lacks new code / локальный репозиторий отстаёт от GitHub"
    bs::cli::update_warn "update:   ${checkout}"
    if (( from_explicit == 0 )) && [[ -t 0 && -t 1 ]]; then
      local answer="" why_no_pull="" dflt="p"
      why_no_pull="$(bs::cli::update_pull_blocker "${checkout}")" || dflt="g"
      if [[ "${dflt}" == "g" ]]; then
        printf 'Подтянуть репозиторий нельзя (%s) / cannot pull: %s\n' "${why_no_pull}" "${why_no_pull}"
        printf 'Источник / Source: [g]ithub (репозиторий не изменится / the repo stays old), [l]ocal, [a]bort? [g] '
      else
        printf 'Источник / Source: [p]ull — подтянуть репозиторий и ставить из него (рекомендуется), [g]ithub (репозиторий останется старым), [l]ocal, [a]bort? [p] '
      fi
      read -r answer || answer="a"
      [[ -n "${answer}" ]] || answer="${dflt}"
      case "${answer,,}" in
        p|pull)
          bs::cli::update_pull_checkout "${checkout}" \
            || bs::cli::update_die "update: git pull не удался, ничего не изменено / git pull failed, nothing was changed"
          state="$(bs::cli::update_local_state "${checkout}" "${repo}" "${ref}")" ;;
        g|github) github=1 ;;
        l|local)  : ;;
        *)        bs::cli::update_die "update: aborted / отменено" ;;
      esac
    else
      bs::cli::update_warn "update: installing the LOCAL code; for the newest run: bs update --pull (или / or git pull), or bs update --github"
    fi
  fi
  if (( github == 1 )) && [[ "${state}" == "behind" ]]; then
    # bs update ставит только bs, bootstrap, core, lib: examples/ и tests/
    # репозитория остаются прежними — это не ошибка, но об этом нужно сказать
    # bs update installs bs, bootstrap, core and lib only: examples/ and
    # tests/ of the repository stay as they are — not an error, but say so
    bs::cli::update_warn "update: репозиторий ${checkout} отстаёт от GitHub и НЕ обновлён (bs update ставит только bs, bootstrap, core, lib; examples/ и tests/ не затрагиваются). Обновить репозиторий: bs update --pull (или git -C ${checkout} pull) / the repository is behind GitHub and was NOT updated (examples/ and tests/ are not touched)"
  fi
  if (( github == 1 )) && [[ -n "${checkout}" ]]; then
    if [[ "${state}" == "ahead" ]]; then
      bs::cli::update_warn "update: local repo has commits not pushed to ${repo%.git}@${ref} — GitHub lacks them / на GitHub нет локальных коммитов: ${checkout}"
    fi
    if utils::has git && [[ -e "${checkout}/.git" ]] \
       && [[ -n "$(git -C "${checkout}" status --porcelain -- bs bootstrap core lib 2>/dev/null)" ]]; then
      bs::cli::update_warn "update: local repo has uncommitted changes — they are NOT installed from GitHub / незакоммиченные правки не попадут в установку: ${checkout}"
    fi
  fi

  # Запуск от root/sudo: ~ — каталог root, а не пользователя.
  # Run as root/sudo: ~ is root's home, not the user's.
  if (( explicit == 0 )) && [[ -n "${SUDO_USER:-}" ]]; then
    local sudo_home
    sudo_home="$(bs::cli::update_sudo_home)"
    if [[ -n "${sudo_home}" && "${sudo_home}" != "${HOME}" ]] && bs::cli::update_is_install "${sudo_home}/.local/lib/bs"; then
      log::info "update: запущено через sudo: ~ = ${HOME}. Локальная установка ${SUDO_USER} (${sudo_home}/.local/lib/bs) не затронута — обновите её без sudo: bs update --local / run via sudo: its local install is untouched"
    fi
  fi

  # Детект установок: стандартные каталоги, установленная копия, из которой
  # запущен bs, и каталог из обёртки `bs` в PATH (нестандартный --lib).
  # Detect installs: the standard directories, the installed copy bs runs
  # from, and the directory named by the `bs` wrapper in PATH (custom --lib).
  if (( explicit == 0 )); then
    local -a found=("${HOME}/.local/lib/bs" "$(bs::cli::update_system_lib)")
    is::dir "${BS_ROOT}/tests" || found+=("${BS_ROOT}")
    local wrapper wrapper_root
    while IFS= read -r wrapper; do
      wrapper_root="$(bs::cli::update_wrapper_root "${wrapper}")"
      [[ -n "${wrapper_root}" ]] || continue
      if ! is::dir "${wrapper_root}"; then
        # Сломанная обёртка: раньше молча игнорировалась / was silently ignored
        bs::cli::update_warn "update: обёртка ${wrapper} указывает на несуществующий ${wrapper_root} — переустановите или удалите её / the wrapper points to a missing directory — reinstall or delete it"
        continue
      fi
      found+=("${wrapper_root}")
    done < <(type -aP bs 2>/dev/null)
    local dir seen=$'\n'
    for dir in "${found[@]}"; do
      dir="${dir%/}"
      is::dir "${dir}" || continue
      [[ "${dir}" == "${checkout%/}" ]] && continue
      [[ "${seen}" == *$'\n'"${dir}"$'\n'* ]] && continue
      seen+="${dir}"$'\n'
      targets+=("${dir}"); tkinds+=(auto)
    done
  fi

  if (( ${#targets[@]} == 0 )); then
    bs::cli::update_box "BS НЕ УСТАНОВЛЕНА / BS NOT INSTALLED" \
      "Установок BS не найдено / no BS installs found." \
      "" \
      "Установите / Install:" \
      "  ./install.sh --local        (для себя / for you)" \
      "  sudo ./install.sh           (для всех / system-wide)" \
      "или укажите каталог / or point to one: bs update --lib DIR"
    exit 1
  fi
  local source_label="${from}"
  if (( github == 1 )); then
    source_label="${repo%.git}@${ref}"
    log::info "fetching ${source_label}"
    bs::cli::update_fetch "${repo}" "${ref}"
    from="${UPDATE_FETCH_DIR}/src"
  fi
  # Источник проверяется ДО любых записей в цели.
  # The source is verified BEFORE anything is written to a target.
  local -a src_missing=()
  mapfile -t src_missing < <(bs::cli::update_source_missing "${from}")
  if (( ${#src_missing[@]} > 0 )); then
    local -a lines=("Источник не годится / unusable source: ${source_label}" "Не хватает / missing:")
    local m
    for m in "${src_missing[@]}"; do lines+=("  • ${m}"); done
    lines+=("" "Ничего не изменено / nothing was changed." \
      "Нужен репозиторий BS: bs, bootstrap/{init,loader}.sh, core/, lib/ / a BS repository is required")
    bs::cli::update_box "ИСТОЧНИК НЕ ПОДХОДИТ / INVALID SOURCE" "${lines[@]}"
    exit 1
  fi
  local from_real
  from_real="$(bs::cli::update_realpath "${from}")"

  local target tin tkind ok=0 new_ver old_ver rc_apply idx
  local -i rc_cmp
  new_ver="$(bs::version::of "${from}")"
  local -a same_paths=() miss_lines=() ro_paths=() uptodate_paths=() bad_lines=() fail_lines=() done_lines=() seen_real=()
  local wrap_path
  for idx in "${!targets[@]}"; do
    tin="${targets[idx]%/}"
    [[ -n "${tin}" ]] || tin="/"
    tkind="${tkinds[idx]}"
    if ! is::dir "${tin}"; then
      if [[ -e "${tin}" ]]; then
        bad_lines+=("• ${tin} — это не каталог / not a directory")
      else
        mapfile -t -O "${#miss_lines[@]}" miss_lines < <(bs::cli::update_missing_lines "${tin}" "${tkind}")
      fi
      continue
    fi
    target="$(bs::cli::update_realpath "${tin}")"
    if [[ "${seen_real[*]:-}" == *"|${target}|"* ]]; then
      continue
    fi
    seen_real+=("|${target}|")
    if [[ -L "${tin}" ]]; then
      log::info "update: ${tin} — символическая ссылка → ${target} / is a symlink"
    fi
    if [[ "${from_real}" == "${target}" ]]; then
      # В финальную рамку, а не WARN в цикле: «ничего не обновлено» — это
      # не ошибка, а приглашение запустить update из репозитория.
      # Collected for the final box, not a per-target WARN.
      same_paths+=("${target}")
      continue
    fi
    # Защита от чужих каталогов: цель обязана быть установкой BS, иначе
    # rm -rf core/lib/bootstrap стёр бы чужие данные.
    # Guard against foreign directories: the target must be a BS install,
    # else replacing core/lib/bootstrap would erase someone's data.
    if bs::cli::update_is_checkout "${target}"; then
      bad_lines+=("• ${target} — исходный репозиторий (.git/tests), не установка; не тронут / a source checkout, not an install; left untouched")
      continue
    fi
    if ! bs::cli::update_is_install "${target}"; then
      bad_lines+=("• ${target} — не установка BS (нет bs + bootstrap/init.sh и нет .install); не тронут / not a BS install; left untouched")
      continue
    fi
    if [[ "${from_real}" == "${target}"/* ]]; then
      bad_lines+=("• ${target} — источник ${from_real} внутри цели: обновление стёрло бы его / the source is inside the target")
      continue
    fi
    if [[ "${target}" == "${from_real}"/bootstrap/* || "${target}" == "${from_real}"/core/* || "${target}" == "${from_real}"/lib/* ]]; then
      bad_lines+=("• ${target} — цель внутри копируемых каталогов источника / the target is inside the source's bootstrap/core/lib")
      continue
    fi
    # Установка без обёртки: bs из PATH её не найдёт.
    # An install without a wrapper: bs from PATH will not find it.
    wrap_path="$(bs::cli::update_install_wrapper "${target}")"
    if [[ -n "${wrap_path}" && ! -e "${wrap_path}" ]]; then
      bs::cli::update_warn "update: у установки ${target} нет обёртки ${wrap_path} — команда bs из PATH её не запустит; восстановить: ./install.sh (--local) / no wrapper"
    fi
    # Уже актуально: содержимое совпадает — копировать нечего.
    # Already up to date: identical content — nothing to copy.
    if cmp -s "${from}/bs" "${target}/bs" \
       && diff -rq "${from}/bootstrap" "${target}/bootstrap" >/dev/null 2>&1 \
       && diff -rq "${from}/core" "${target}/core" >/dev/null 2>&1 \
       && diff -rq "${from}/lib" "${target}/lib" >/dev/null 2>&1; then
      uptodate_paths+=("${target}")
      continue
    fi
    # Нет прав на запись: в терминале повышаем права через sudo сами; без
    # терминала — только предупреждение.
    # Not writable: in a terminal elevate with sudo ourselves; without one warn.
    local -a as_root=()
    as_root=()
    if ! [[ -w "${target}" ]]; then
      if [[ -t 0 ]] && utils::has sudo; then
        log::info "update: ${target} needs root — using sudo / нужны права root"
        as_root=(sudo)
      else
        bs::cli::update_warn "update: target not writable: ${target} (try: sudo bs update --system)"
        ro_paths+=("${target}")
        continue
      fi
    fi
    old_ver="$(bs::version::of "${target}")"
    log::info "syncing ${source_label} -> ${target}" \
      "(version ${old_ver:-?} → ${new_ver})"
    # Откат на более старую версию — не ошибка, но о нём стоит сказать вслух
    # Installing an OLDER version is not an error, but worth saying aloud
    if [[ -n "${old_ver}" ]]; then
      rc_cmp=0
      bs::version::compare "${old_ver}" "${new_ver}" || rc_cmp=$?
      if (( rc_cmp == 1 )); then
        bs::cli::update_warn "update: DOWNGRADE ${old_ver} → ${new_ver} (the source is older than the install): ${target}"
      fi
    fi
    bs::cli::update_cleanup_stale "${target}" "${as_root[*]:-}"
    if ! bs::cli::update_lock "${target}" "${as_root[*]:-}"; then
      fail_lines+=("• ${target} — уже идёт другое обновление этой цели (замок ${target}/.update-lock); повторите позже / another update of this target is running; retry later")
      continue
    fi
    rc_apply=0
    bs::cli::update_apply "${target}" "${from}" "${new_ver}" "${as_root[@]}" || rc_apply=$?
    if (( rc_apply == 1 )); then
      bs::cli::update_unlock "${target}"
      bs::cli::update_warn "update: copy failed for ${target} (нет места/прав?); прежняя версия сохранена / disk full or no permission? the previous version is kept"
      fail_lines+=("• ${target} — копирование не удалось (нет места/прав?); прежняя версия сохранена / copy failed; the previous version is kept")
      continue
    elif (( rc_apply == 2 )); then
      bs::cli::update_unlock "${target}"
      bs::cli::update_warn "update: самопроверка не прошла (bs version), прежняя версия ${old_ver:-?} восстановлена / smoke test failed, previous version restored: ${target}"
      fail_lines+=("• ${target} — новая копия не прошла самопроверку; прежняя версия ${old_ver:-?} восстановлена / new copy failed the smoke test; rolled back")
      continue
    fi
    bs::cli::update_manifest "${target}" "${from}" "${source_label}" "${as_root[@]}"
    bs::cli::update_unlock "${target}"
    ok=1
    done_lines+=("${target}: ${old_ver:-?} → ${new_ver}")
    if (( verbose == 1 )); then
      log::info "  files: $(find "${from}/core" "${from}/lib" -name '*.sh' | wc -l) modules copied"
    fi
  done

  local -a reasons=()
  local p
  for p in "${same_paths[@]}"; do
    reasons+=("• ${p} — источник совпадает с целью (bs запущен из этой копии) / source equals target (running from this copy)")
  done
  reasons+=("${miss_lines[@]}")
  for p in "${ro_paths[@]}"; do
    reasons+=("• ${p} — нет прав на запись / not writable (try: sudo bs update --system)")
  done
  reasons+=("${bad_lines[@]}")
  reasons+=("${fail_lines[@]}")
  for p in "${uptodate_paths[@]}"; do
    reasons+=("• ${p} — уже актуально / already up to date (version $(bs::version::of "${p}"))")
  done
  if (( ${#same_paths[@]} > 0 )); then
    reasons+=("")
    reasons+=("Запустите из каталога репозитория / Run from the repo directory:")
    reasons+=("  cd <repo> && ./bs update")
    reasons+=("или укажите источник / or pass the source:")
    reasons+=("  bs update --from <repo-path>")
    reasons+=("или обновитесь с GitHub / or update from GitHub:")
    reasons+=("  bs update --github")
  fi
  # Отказ: цели, что не удалось обновить. Автопоиск: отказ от чужого/сломанного
  # каталога не считается ошибкой запуска.
  # Failures: targets that could not be updated. In autodetect mode refusing a
  # foreign/broken directory is not a run failure.
  local -i failures=$(( ${#miss_lines[@]} > 0 ? 1 : 0 ))
  failures+=$(( ${#ro_paths[@]} + ${#fail_lines[@]} ))
  (( explicit == 0 )) || failures+=${#bad_lines[@]}

  if (( ok == 1 )); then
    log::header "UPDATE COMPLETE / ОБНОВЛЕНИЕ ЗАВЕРШЕНО"
    printf '%s\n' "${UPDATE_RUN_BLOCK}"
    for p in "${done_lines[@]}"; do
      printf '  ✓ %s\n' "${p}"
    done
    bs::cli::update_path_summary
    bs::cli::update_state_summary "${checkout}" "${state}" "${new_ver}"
    if (( ${#reasons[@]} > 0 )); then
      local skip_title="ПРОПУЩЕНО / SKIPPED"
      (( failures == 0 )) || skip_title="ЧАСТЬ ЦЕЛЕЙ ПРОПУЩЕНА / SOME TARGETS SKIPPED"
      bs::cli::update_box "${skip_title}" "${reasons[@]}"
    fi
    if (( failures == 0 )); then
      log::success "sync done — changes are live without reinstalling"
      return 0
    fi
    bs::cli::update_die "update: часть целей не обновлена / some targets were not updated (см. выше / see above)"
  fi

  # Итоговая рамка вместо сырого ERROR: понятно, что случилось и что делать.
  # A framed summary instead of a raw ERROR: clear what happened and what to do.
  local title="ОБНОВЛЕНИЙ НЕТ / NO UPDATES"
  (( failures == 0 )) || title="ОБНОВЛЕНИЕ НЕ ВЫПОЛНЕНО / UPDATE NOT DONE"
  bs::cli::update_box "${title}" "${reasons[@]}"
  (( failures > 0 )) || bs::cli::update_state_summary "${checkout}" "${state}" "${new_ver}"
  (( failures == 0 )) || exit 1
  return 0
}

bs::cli::uninstall_cmd() {
  local -a targets=() tkinds=()
  local explicit=0
  local verbose=0
  local banner=1 a
  for a in "$@"; do
    [[ "${a}" == "-h" || "${a}" == "--help" ]] && banner=0
  done
  bs::cli::update_ctx
  (( banner == 0 )) || printf '%s\n' "${UPDATE_RUN_BLOCK}"

  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      --local)
        explicit=1
        targets+=("${HOME:-}/.local/lib/bs"); tkinds+=(local)
        shift ;;
      --system)
        explicit=1
        targets+=("$(bs::cli::update_system_lib)"); tkinds+=(system)
        shift ;;
      --lib)
        shift
        bs::cli::update_flag_value "--lib" "a target directory" "$@"
        explicit=1
        targets+=("$1"); tkinds+=(lib)
        shift ;;
      -v|--verbose)
        verbose=1
        shift ;;
      -h|--help)
        printf 'Использование / Usage: bs uninstall [--local] [--system] [--lib DIR] [-v]\n\n'
        printf 'Удаляет установленные копии BS (каталог lib + обёртка).\n'
        printf 'Removes installed BS copies (lib tree + wrapper).\n'
        printf '  --local   ~/.local/lib/bs and its wrapper in ~/.local/bin\n'
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
        bs::cli::update_die "uninstall: неизвестный аргумент / unknown argument: $1 (bs uninstall --help)" ;;
    esac
  done

  # Детект установок / Detect installs
  if (( explicit == 0 )); then
    if is::dir "${HOME:-}/.local/lib/bs"; then
      targets+=("${HOME:-}/.local/lib/bs"); tkinds+=(auto)
    fi
    if is::dir "$(bs::cli::update_system_lib)"; then
      targets+=("$(bs::cli::update_system_lib)"); tkinds+=(auto)
    fi
  fi

  if (( ${#targets[@]} == 0 )); then
    bs::cli::update_box "УДАЛЯТЬ НЕЧЕГО / NOTHING TO UNINSTALL" \
      "Установок BS не найдено / no BS installs found." \
      "Укажите каталог / point to one: bs uninstall --lib DIR"
    exit 1
  fi

  local target tin tkind ok=0 idx bin_dir wrapper removed_wrapper
  local -a skipped=() seen_real=()
  for idx in "${!targets[@]}"; do
    tin="${targets[idx]%/}"
    tkind="${tkinds[idx]}"
    if ! is::dir "${tin}"; then
      mapfile -t -O "${#skipped[@]}" skipped < <(bs::cli::update_missing_lines "${tin}" "${tkind}" uninstall)
      continue
    fi
    target="$(bs::cli::update_realpath "${tin}")"
    [[ "${seen_real[*]:-}" == *"|${target}|"* ]] && continue
    seen_real+=("|${target}|")
    # Безопасность: удаляем только каталоги, которые однозначно являются BS
    # Safety: only remove directories that are unmistakably BS installs
    if [[ ! -f "${target}/bs" || ! -f "${target}/bootstrap/init.sh" ]]; then
      skipped+=("• ${target} — не установка BS (нет bs + bootstrap/init.sh); не тронут / not a BS install; left untouched")
      continue
    fi
    # Никогда не удалять исходный чекаут: у него есть .git или tests/.
    # Never remove the source checkout: it has .git or tests/.
    if [[ -e "${target}/.git" || -d "${target}/tests" ]]; then
      skipped+=("• ${target} — исходный репозиторий (.git/tests), не установка; не тронут / source checkout; refusing to remove")
      continue
    fi
    # Обёртка — из манифеста, иначе выводится из пути .../lib/bs.
    # The wrapper comes from the manifest, else from a .../lib/bs path.
    wrapper="$(bs::cli::update_install_wrapper "${target}")"
    # lib задан симлинком и манифест без bin=: путь обёртки выводится из него
    # lib given as a symlink and a manifest without bin=: derive it from the link
    [[ -n "${wrapper}" ]] || wrapper="$(bs::cli::update_install_wrapper "${tin}")"
    bin_dir="${wrapper%/*}"
    local wrapper_mine=0
    if [[ -n "${wrapper}" && -f "${wrapper}" ]]; then
      if grep -Fq "BS_ROOT=\"${target}\"" "${wrapper}" 2>/dev/null; then
        wrapper_mine=1
      else
        # Обёртка может называть lib через симлинк (~/.local/lib/bs -> ...):
        # сравниваем и заданный путь, и реальный.
        # The wrapper may name the lib through a symlink: compare both the
        # given path and the real one.
        local wroot
        wroot="$(bs::cli::update_wrapper_root "${wrapper}")"
        if [[ -n "${wroot}" ]] && [[ "${wroot%/}" == "${tin}" || "$(bs::cli::update_realpath "${wroot}")" == "${target}" ]]; then
          wrapper_mine=1
        fi
      fi
    fi
    local denied=0
    [[ -w "${target%/*}" ]] || denied=1
    if (( wrapper_mine == 1 )) && ! [[ -w "${bin_dir}" ]]; then denied=1; fi
    if (( denied == 1 )); then
      skipped+=("• ${target} — нет прав на удаление / no permission to remove (try: sudo bs uninstall --system)")
      continue
    fi
    log::info "uninstalling ${target}"
    if [[ "${target}" == "$(bs::cli::update_realpath "${BS_ROOT}")" ]]; then
      log::info "uninstall: удаляется копия, из которой запущен bs — это нормально / removing the copy bs runs from — this is fine"
    fi
    removed_wrapper=0
    if (( wrapper_mine == 0 )) && [[ -n "${wrapper}" && -f "${wrapper}" ]]; then
      bs::cli::update_warn "uninstall: wrapper not matching this install, left in place: ${wrapper} / обёртка не от этой установки, оставлена"
    fi

    # rm -rf на защищённый target безопасен: выше проверено, что это настоящая
    # BS-установка, не чекаут и записываемый каталог.
    # Обёртку удаляем ПОСЛЕ каталога: при сбое rm остаётся рабочая команда bs,
    # и удаление можно повторить.
    # rm -rf on the guarded target is safe: it is a real BS install, not a
    # checkout, and writable. The wrapper goes AFTER the directory: if rm
    # fails, a working bs command is left and the removal can be retried.
    if ! rm -rf -- "${target}"; then
      skipped+=("• ${target} — удаление не удалось (часть файлов могла быть удалена; обёртка оставлена; остаток удалите вручную) / removal failed (some files may be gone; the wrapper is kept; remove the rest by hand)")
      continue
    fi
    if (( verbose == 1 )); then
      log::info "  removed: ${target}"
    fi
    # Симлинк на каталог установки больше никуда не ведёт: убираем и его
    # The symlink to the install directory points nowhere now: drop it too
    if [[ -L "${tin}" ]]; then
      rm -f -- "${tin}" || true
    fi
    if (( wrapper_mine == 1 )); then
      rm -f -- "${wrapper}"
      removed_wrapper=1
      if (( verbose == 1 )); then
        log::info "  removed: ${wrapper}"
      fi
    fi
    # rmdir удаляет только пустой bin_dir; чужие файлы не трогаются.
    # rmdir removes only an empty bin_dir; foreign files are never touched.
    (( removed_wrapper == 0 )) || rmdir -- "${bin_dir}" 2>/dev/null || true
    ok=1
  done

  if (( ok == 0 )); then
    bs::cli::update_box "НИЧЕГО НЕ УДАЛЕНО / NOTHING REMOVED" "${skipped[@]}"
    exit 1
  fi
  if (( ${#skipped[@]} > 0 )); then
    bs::cli::update_box "ЧАСТЬ ПРОПУЩЕНА / SOME TARGETS SKIPPED" "${skipped[@]}"
  fi
  log::success "uninstall done"
  (( ${#skipped[@]} == 0 )) || exit 1
  return 0
}

bs::cli::ts_cmd() {
  case "${1:-}" in
    -h|--help|"")
      printf 'Usage: bs ts <command> [args]\n\n'
      printf 'TypeScript toolchain and a local mini stack (thriller).\n\n'
      printf '  doctor [dir]     TS environment summary\n'
      printf '  validate [dir]   tsc / eslint / prettier gate\n'
      printf '  port-free PORT   is TCP port free\n'
      printf '  init [dir]       scaffold api + fixtures + public\n'
      printf '  up [dir]         start api (and web if present)\n'
      printf '  down             stop\n'
      printf '  status           pids / ports / alive\n'
      printf '  logs [api|web]   last log lines\n'
      return 0 ;;
  esac
  local -r sub="$1"
  shift || true
  case "${sub}" in
    doctor)
      load "lib/ts/toolchain"
      ts::toolchain::doctor "$@" ;;
    validate)
      load "lib/ts/toolchain"
      ts::toolchain::validate "$@" ;;
    port-free)
      load "lib/ts/toolchain"
      ts::toolchain::port_free "$@" ;;
    init|up|down|status|logs)
      load "lib/ts/stack"
      "ts::stack::${sub}" "$@" ;;
    *)
      bs::cli::die "ts: unknown command: ${sub} (see: bs ts --help)" ;;
  esac
}

# Строка отчёта: подпись выравнивается по СИМВОЛАМ (printf %-Ns считает байты и
# ломает колонки с кириллицей).
# A report row: the label is padded by CHARACTERS (printf %-Ns counts bytes and
# breaks columns with Cyrillic).
bs::cli::where_row() {
  local -r label="$1"
  local pad
  # В локали C ${#x} считает байты: для длины берём UTF-8
  # In the C locale ${#x} counts bytes: use UTF-8 for the length
  local LC_ALL=C.UTF-8
  printf -v pad '%*s' "$(( ${#label} < 15 ? 15 - ${#label} : 1 ))" ''
  printf '    %s%s%s\n' "${label}" "${pad}" "$2"
}

# @private Состояние каталога как BS: missing | file | foreign | checkout |
# install | nomanifest | badmanifest.
# @private State of a directory as BS: missing | file | foreign | checkout |
# install | nomanifest | badmanifest.
# @param $1 Directory / Каталог
bs::cli::where_classify() {
  local -r d="$1"
  if [[ ! -e "${d}" ]]; then printf 'missing'; return 0; fi
  if [[ ! -d "${d}" ]]; then printf 'file'; return 0; fi
  if [[ ! -f "${d}/bs" || ! -f "${d}/bootstrap/init.sh" ]]; then
    printf 'foreign'; return 0
  fi
  if [[ -e "${d}/.git" || -d "${d}/tests" ]]; then printf 'checkout'; return 0; fi
  if [[ ! -e "${d}/.install" ]]; then printf 'nomanifest'; return 0; fi
  if bs::cli::update_manifest_valid "${d}/.install"; then
    printf 'install'
  else
    printf 'badmanifest'
  fi
}

# @private Вид установки по пути, если манифеста нет / install kind by path
bs::cli::where_kind_by_path() {
  local -r d="$1"
  if [[ "${d}" == "${HOME}/.local/lib/bs" ]]; then printf 'local'
  elif [[ "${d}" == "$(bs::cli::update_system_lib)" ]]; then printf 'system'
  else printf 'custom'
  fi
}

# @private Размер каталога в человекочитаемом виде (с ограничением по времени)
# @private Directory size, human readable (with a time limit)
bs::cli::where_size() {
  local kb
  kb="$(timeout 5 du -sk -- "$1" 2>/dev/null | cut -f1 || true)"
  if [[ "${kb}" =~ ^[0-9]+$ ]]; then
    if (( kb >= 1024 )); then printf '%d.%d MB' "$(( kb / 1024 ))" "$(( kb % 1024 * 10 / 1024 ))"
    else printf '%d KB' "${kb}"; fi
  else
    printf '?'
  fi
}

bs::cli::where_help() {
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

bs::cli::where_cmd() {
  local deep=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --deep)    deep=1; shift ;;
      -h|--help) bs::cli::where_help; return 0 ;;
      *)         bs::cli::die "where: unknown argument: $1 (try: bs where --help)" ;;
    esac
  done

  # В строгом режиме bs IFS = перевод строки/табуляция; здесь нужны пробелы
  # In bs strict mode IFS is newline/tab; this function needs spaces
  local IFS=' '
  local -a cands=() problems=() hints=()
  local -A seen=() pseen=()
  local d real hit root cls n=0 first_root=""
  local -a hits=()

  # Замечание / подсказка без повторов
  # A problem / hint, without duplicates
  where_problem() { [[ -z "${pseen[P:$1]:-}" ]] || return 0; pseen["P:$1"]=1; problems+=("$1"); }
  where_hint()    { [[ -z "${pseen[H:$1]:-}" ]] || return 0; pseen["H:$1"]=1; hints+=("$1"); }

  # Кандидат в каталог BS (без повторов, по реальному пути)
  # A candidate BS directory (deduplicated by real path)
  where_add() {
    local p="${1%/}" r
    [[ -n "${p}" ]] || return 0
    r="$(readlink -f -- "${p}" 2>/dev/null || printf '%s' "${p}")"
    [[ -z "${seen[${r}]:-}" ]] || return 0
    seen["${r}"]=1
    cands+=("${r}")
  }

  printf '== Запущено сейчас / Running now ==\n'
  bs::cli::bs_running_block
  where_add "${BS_ROOT}"

  # Оболочка: кто исполняет код BS, чья оболочка у пользователя, tier
  # The shell: who runs the BS code, whose shell the user has, the tier
  local ushell utier
  ushell="$(bs_shell_user)"
  utier="$(bs_shell_tier "${ushell}")"
  printf '\n== Оболочка / Shell ==\n'
  bs::cli::where_row "хозяин:" "$(bs_shell_family) ${BASH_VERSION} (исполняет код BS / runs the BS code)"
  bs::cli::where_row "ваша:" "${ushell}  (login: $(bs_shell_login), parent: $(bs_shell_parent))"
  bs::cli::where_row "tier:" "${utier}"
  printf '    %s\n' "$(bs_shell_tier_desc "${utier}")"

  # --- bs в PATH ---
  printf '\n== Команда bs в PATH / The bs command in PATH ==\n'
  mapfile -t hits < <(PATH="${BS_CALLER_PATH:-${PATH}}" type -aP bs 2>/dev/null || true)
  if (( ${#hits[@]} == 0 )); then
    printf '  bs не найдена в PATH этой оболочки / bs is not in the PATH of this shell\n'
    where_problem "bs не найдена в PATH этой оболочки / bs is not in the PATH of this shell"
    if [[ -x "${HOME}/.local/bin/bs" ]]; then
      where_hint "$(bs_shell_path_line "${ushell}" '$HOME/.local/bin')   (в этом терминале сразу / in this terminal right away; shell: ${ushell})"
    fi
    where_hint "$(bs_shell_reload_hint "${ushell}")  (или новый терминал / or a new terminal)"
    where_hint "./install.sh --local --update-path   (если строки PATH нет в rc-файле / if the rc file lacks the PATH line)"
  fi
  for hit in ${hits[@]+"${hits[@]}"}; do
    n=$(( n + 1 ))
    real="$(readlink -f -- "${hit}" 2>/dev/null || printf '%s' "${hit}")"
    root="$(bs::cli::update_wrapper_root "${real}")"
    local what=""
    if [[ -n "${root}" ]]; then
      if [[ -d "${root}" ]]; then
        what="wrapper → ${root} (версия / version $(bs::version::of "${root}"))"
        where_add "${root}"
      else
        what="wrapper → ${root} — КАТАЛОГ НЕ СУЩЕСТВУЕТ / DIRECTORY MISSING"
        where_problem "обёртка ${hit} указывает на несуществующий ${root} / wrapper ${hit} points to a missing ${root}"
        where_hint "rm ${hit}  (или переустановить / or reinstall: ./install.sh --local)"
      fi
    elif [[ -f "$(dirname -- "${real}")/bootstrap/init.sh" ]]; then
      root="$(dirname -- "${real}")"
      what="лаунчер каталога / launcher of ${root} (версия / version $(bs::version::of "${root}"))"
      where_add "${root}"
    else
      what="не похоже на BS / does not look like BS"
    fi
    local mark=""
    if (( n == 1 )); then
      mark="   ← запускается по команде bs / runs as \`bs\`"
      first_root="${root}"
    fi
    printf '  %d. %s — %s%s\n' "${n}" "${hit}" "${what}" "${mark}"
  done

  # --- Кандидаты из стандартных мест, манифестов, rc-файлов и (--deep) поиска ---
  where_add "${HOME}/.local/lib/bs"
  where_add "$(bs::cli::update_system_lib)"
  [[ -z "${BS_HOME:-}" ]] || where_add "${BS_HOME}"

  # rc-файлы ВСЕХ известных оболочек (bash, zsh, sh/ash/dash, ksh, osh, fish, nu)
  # из реестра bootstrap/shell.sh, плюс /etc/profile.d
  # rc files of ALL known shells (bash, zsh, sh/ash/dash, ksh, osh, fish, nu)
  # from the registry bootstrap/shell.sh, plus /etc/profile.d
  local -a rcfiles=()
  mapfile -t rcfiles < <(bs_shell_all_rc_files)
  local f
  for f in /etc/profile.d/*.sh; do [[ -f "${f}" ]] && rcfiles+=("${f}"); done

  # Пути из строк вида source ".../bootstrap/init.sh"
  local line path_re='([~/$][^"'"'"' ]*)/bootstrap/init\.sh'
  for f in "${rcfiles[@]}"; do
    [[ -r "${f}" ]] || continue
    while IFS= read -r line; do
      [[ "${line}" =~ ^[[:space:]]*# ]] && continue
      if [[ "${line}" =~ ${path_re} ]]; then
        path="${BASH_REMATCH[1]}"
        path="${path/#\~/${HOME}}"; path="${path/#\$HOME/${HOME}}"; path="${path/#\$\{HOME\}/${HOME}}"
        [[ "${path}" == /* && "${path}" != *'$'* ]] && where_add "${path}"
      fi
    done < "${f}"
  done

  if (( deep == 1 )); then
    local -a droots=("${HOME}" /opt /usr/local /srv) found=()
    local r
    for r in "${droots[@]}"; do
      [[ -d "${r}" ]] || continue
      mapfile -t found < <(timeout 30 find "${r}" -xdev -maxdepth 5 \
        \( -name .git -o -name node_modules -o -name .cache -o -name proc \) -prune -o \
        -type f -path '*/bootstrap/init.sh' -print 2>/dev/null || true)
      for f in ${found[@]+"${found[@]}"}; do
        where_add "$(dirname -- "$(dirname -- "${f}")")"
      done
    done
  fi

  # Источники установок из манифестов (откуда ставили) — это тоже следы
  local c src
  for c in "${cands[@]}"; do
    src="$(bs::cli::install_info_get "${c}" source)"
    [[ -n "${src}" && -d "${src}" ]] && where_add "${src}"
  done

  # --- Установки ---
  printf '\n== Установки BS / BS installs ==\n'
  local n_inst=0 owner access wrap exp_bin mode versions=" "
  local -a leftovers=() checkouts=() iv_paths=()
  for c in "${cands[@]}"; do
    cls="$(bs::cli::where_classify "${c}")"
    case "${cls}" in
      missing) continue ;;
      checkout) checkouts+=("${c}"); continue ;;
      foreign|file)
        # Чужое показываем только в стандартных местах BS
        # Foreign things are reported only at the standard BS places
        if [[ "${c}" == "${HOME}/.local/lib/bs" || "${c}" == "$(bs::cli::update_system_lib)" ]]; then
          printf '  %s\n' "${c}"
          bs::cli::where_row "состояние:" "существует, но это НЕ установка BS / exists but is NOT a BS install (${cls})"
          where_problem "${c} занят чужим / ${c} is occupied by something that is not BS"
        fi
        continue ;;
    esac
    n_inst=$(( n_inst + 1 ))
    printf '  %s%s\n' "${c}" "$([[ "${c}" == "$(readlink -f -- "${BS_ROOT}")" ]] && printf '   ← запущена сейчас / running now')"
    mode="$(bs::cli::install_info_get "${c}" mode)"
    [[ -n "${mode}" ]] || mode="$(bs::cli::where_kind_by_path "${c}")"
    bs::cli::where_row "вид / kind:" "${mode}, версия / version $(bs::version::of "${c}")"
    versions+="$(bs::version::of "${c}") "
    iv_paths+=("${c}")
    case "${cls}" in
      nomanifest)  bs::cli::where_row "манифест:" "нет (установлено старым установщиком) / none (older installer)"
                   where_problem "${c}: нет манифеста / no manifest"
                   where_hint "bs update --lib ${c}   (создаст манифест / creates the manifest)" ;;
      badmanifest) bs::cli::where_row "манифест:" "ПОВРЕЖДЁН / CORRUPT: ${c}/.install"
                   where_problem "${c}: повреждённый манифест / corrupt manifest"
                   where_hint "bs update --lib ${c}   (пересоздаст манифест / recreates the manifest)" ;;
      install)
        bs::cli::where_row "установлено:" "$(bs::cli::install_info_get "${c}" installed_at) by $(bs::cli::install_info_get "${c}" installed_by)"
        src="$(bs::cli::install_info_get "${c}" source)"
        bs::cli::where_row "источник:" "${src:-?} @ $(bs::cli::short_sha "$(bs::cli::install_info_get "${c}" source_commit)")$([[ -n "${src}" && ! -d "${src}" ]] && printf '   (каталога больше нет / directory is gone)')"
        if [[ -n "$(bs::cli::install_info_get "${c}" updated_at)" ]]; then
          bs::cli::where_row "обновлено:" "$(bs::cli::install_info_get "${c}" updated_at) from $(bs::cli::install_info_get "${c}" updated_from) @ $(bs::cli::short_sha "$(bs::cli::install_info_get "${c}" updated_commit)")"
        fi ;;
    esac
    # Обёртка этой установки
    exp_bin="$(bs::cli::install_info_get "${c}" bin)"
    [[ -n "${exp_bin}" ]] || exp_bin="${c%/lib/bs}/bin/bs"
    if [[ -f "${exp_bin}" ]]; then
      wrap="$(bs::cli::update_wrapper_root "${exp_bin}")"
      if [[ "$(readlink -f -- "${wrap:-/nonexistent}" 2>/dev/null)" == "${c}" ]]; then
        bs::cli::where_row "wrapper:" "${exp_bin}$(case ":${BS_CALLER_PATH:-${PATH}}:" in *":$(dirname -- "${exp_bin}"):"*) printf ' (каталог в PATH / directory in PATH)';; *) printf ' (каталога НЕТ в PATH / directory NOT in PATH)';; esac)"
      else
        bs::cli::where_row "wrapper:" "${exp_bin} — указывает на ${wrap:-?}, не сюда / points to ${wrap:-?}, not here"
        if [[ -n "${wrap}" && -d "${wrap}" ]]; then
          where_problem "${exp_bin} ведёт не в ${c} / ${exp_bin} does not lead to ${c}"
        else
          where_problem "обёртка ${exp_bin} указывает на несуществующий ${wrap:-?} / wrapper ${exp_bin} points to a missing ${wrap:-?}"
          where_hint "rm ${exp_bin}  (или переустановить / or reinstall: ./install.sh --local)"
        fi
      fi
    else
      bs::cli::where_row "wrapper:" "нет / none (ожидался / expected: ${exp_bin})"
      if [[ "${cls}" != "checkout" ]]; then
        where_problem "${c}: нет обёртки, команда bs её не найдёт / no wrapper"
        where_hint "./install.sh $([[ "${mode}" == local ]] && printf -- '--local')   (починит обёртку / repairs the wrapper)"
      fi
    fi
    owner="$(stat -c %U -- "${c}" 2>/dev/null || printf '?')"
    if [[ -w "${c}" ]]; then access="доступна на запись / writable"
    else access="только чтение, нужен sudo / read-only, needs sudo"; fi
    bs::cli::where_row "владелец:" "${owner}, ${access}"
    # Остатки упавших обновлений и установок
    leftovers=()
    for f in "${c}"/.update.* "${c}"/.update-old.* "${c}"/.update-lock "${c}"/.install.bad \
             "$(dirname -- "${c}")"/.bs.install.*; do
      [[ -e "${f}" ]] && leftovers+=("${f}")
    done
    if (( ${#leftovers[@]} > 0 )); then
      bs::cli::where_row "остатки:" "${leftovers[*]}"
      where_problem "${c}: остатки прерванных операций / leftovers of interrupted operations"
      where_hint "bs update --lib ${c}   (очистит остатки / cleans the leftovers)"
    fi
  done
  (( n_inst > 0 )) || printf '  установок не найдено / no installs found\n'

  # --- Репозитории ---
  printf '\n== Репозитории BS / BS source checkouts ==\n'
  if (( ${#checkouts[@]} == 0 )); then
    printf '  не найдено / none found\n'
  fi
  for c in ${checkouts[@]+"${checkouts[@]}"}; do
    printf '  %s%s\n' "${c}" "$([[ "${c}" == "$(readlink -f -- "${BS_ROOT}")" ]] && printf '   ← запущен сейчас / running now')"
    bs::cli::where_row "версия / ver.:" "$(bs::version::of "${c}")$(if [[ -e "${c}/.git" ]] && utils::has git; then printf ', commit %s' "$(git -C "${c}" rev-parse --short=7 HEAD 2>/dev/null || printf '?')"; fi)"
  done

  # --- Следы в оболочке ---
  printf '\n== Следы в оболочке / Shell traces ==\n'
  local -i hitsn=0
  local pat='(bootstrap/init\.sh|BS_ROOT|\.local/lib/bs|/lib/bs/|bs init-shell|export PATH="\$HOME/\.local/bin:\$PATH"|contains -- "\$HOME/\.local/bin"|path join "\.local" "bin")'
  for f in "${rcfiles[@]}"; do
    [[ -r "${f}" ]] || continue
    while IFS= read -r line; do
      printf '  %s\n' "${line:0:150}"
      hitsn=$(( hitsn + 1 ))
    done < <(grep -nE -- "${pat}" "${f}" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|${f}:|" || true)
  done
  (( hitsn > 0 )) || printf '  в rc-файлах строк про BS нет / no BS lines in the rc files\n'
  case ":${BS_CALLER_PATH:-${PATH}}:" in
    *":${HOME}/.local/bin:"*) printf '  PATH этой оболочки содержит / contains %s/.local/bin\n' "${HOME}" ;;
    *) printf '  PATH этой оболочки НЕ содержит / does NOT contain %s/.local/bin\n' "${HOME}" ;;
  esac

  # --- Данные и кэш ---
  printf '\n== Данные и кэш / Data and cache ==\n'
  local -i datan=0
  local -a ddirs=("${XDG_CONFIG_HOME:-${HOME}/.config}/bs" "${HOME}/.config/bs"
    "${HOME}/.config/bs_frameworks" "${XDG_CACHE_HOME:-${HOME}/.cache}/bs"
    "${XDG_STATE_HOME:-${HOME}/.local/state}/bs" "${XDG_DATA_HOME:-${HOME}/.local/share}/bs")
  [[ -z "${BS_BUILD_CACHE_DIR:-}" ]] || ddirs+=("${BS_BUILD_CACHE_DIR}")
  local -A dseen=()
  for d in "${ddirs[@]}"; do
    [[ -d "${d}" && -z "${dseen[${d}]:-}" ]] || continue
    dseen["${d}"]=1
    printf '  %s — %s\n' "${d}" "$(bs::cli::where_size "${d}")"
    datan=$(( datan + 1 ))
  done
  (( datan > 0 )) || printf '  не найдено / none found\n'

  # --- Переменные окружения ---
  printf '\n== Переменные окружения / Environment ==\n'
  local -i envn=0
  local v
  for v in BS_SYSTEM_PREFIX BS_UPDATE_REPO BS_BUILD_CACHE_DIR PREFIX BIN_DIR LIB_DIR; do
    if [[ -n "${!v:-}" ]]; then printf '  %s=%s\n' "${v}" "${!v}"; envn=$(( envn + 1 )); fi
  done
  (( envn > 0 )) || printf '  не заданы (BS_ROOT/BS_HOME выставляет сам bs) / none set (BS_ROOT/BS_HOME are set by bs itself)\n'

  # --- Итог ---
  printf '\n== Итог / Summary ==\n'
  printf '  установок / installs: %d,  репозиториев / checkouts: %d,  bs в PATH / bs in PATH: %d\n' \
    "${n_inst}" "${#checkouts[@]}" "${#hits[@]}"
  local -a vs=()
  read -ra vs <<< "${versions}"
  local -A vset=()
  for v in ${vs[@]+"${vs[@]}"}; do vset["${v}"]=1; done
  if (( ${#vset[@]} > 1 )); then
    where_problem "установки разных версий / installs of different versions: ${!vset[*]}"
    where_hint "bs update   (обновит все найденные установки / updates every detected install)"
  fi
  if [[ -n "${first_root}" && -d "${first_root}" && ! -d "${BS_ROOT}/tests" ]] \
     && [[ "$(readlink -f -- "${first_root}")" != "$(readlink -f -- "${BS_ROOT}")" ]]; then
    where_problem "сейчас запущена не та копия, что по команде bs: ${BS_ROOT} вместо ${first_root} / the running copy is not the one behind \`bs\`"
  fi
  # Установка старее найденного репозитория — обновление доступно
  # An install older than a found checkout — an update is available
  local ck iv cv
  for c in ${iv_paths[@]+"${iv_paths[@]}"}; do
    iv="$(bs::version::of "${c}")"
    for ck in ${checkouts[@]+"${checkouts[@]}"}; do
      cv="$(bs::version::of "${ck}")"
      [[ -n "${iv}" && -n "${cv}" ]] || continue
      cls=0; bs::version::compare "${iv}" "${cv}" || cls=$?
      if (( cls == 2 )); then
        where_problem "установка ${c} (${iv}) старее репозитория ${ck} (${cv}) / the install ${c} (${iv}) is older than the checkout ${ck} (${cv})"
        where_hint "cd ${ck} && ./bs update --lib ${c}"
      fi
    done
  done
  if (( ${#problems[@]} == 0 )); then
    printf '  ✓ всё согласовано / everything looks consistent\n'
  else
    local p
    printf '  Что вызывает вопросы / What looks wrong:\n'
    for p in "${problems[@]}"; do printf '   • %s\n' "${p}"; done
    if (( ${#hints[@]} > 0 )); then
      printf '  Что сделать / What to do:\n'
      local -A hseen=()
      for p in "${hints[@]}"; do
        [[ -z "${hseen[${p}]:-}" ]] || continue
        hseen["${p}"]=1
        printf '   → %s\n' "${p}"
      done
    fi
  fi
  return 0
}
