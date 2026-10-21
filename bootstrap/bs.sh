#!/usr/bin/env bash
#
# bootstrap/bs.sh — pre-kernel root namespace, available BEFORE the loader
# bootstrap/bs.sh — корневой namespace bs::, доступный ДО загрузки loader'а
# @tier core — pure Bash 4+, no GNU tools: works everywhere
# @tier core — чистый Bash 4+, без GNU-инструментов: работает везде
# @shell bash4 — pre-kernel bash layer (call stack, BASH_REMATCH, BASH_SOURCE, bs::cli::*); the POSIX part is bootstrap/base.sh and bootstrap/shell.sh
# @shell bash4 — pre-kernel слой на bash (стек вызовов, BASH_REMATCH, BASH_SOURCE, bs::cli::*); POSIX-часть — bootstrap/base.sh и bootstrap/shell.sh
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

# POSIX-часть pre-kernel (bootstrap/base.sh: bs_strict, bs_append_local_bin_to_path, bs_shell_*)
# подключает реестр оболочек bootstrap/shell.sh; её же подключают оболочки, не являющиеся bash.
# The POSIX part of the pre-kernel (bootstrap/base.sh: bs_strict, bs_append_local_bin_to_path,
# bs_shell_*) sources the shell registry bootstrap/shell.sh; shells other than bash source it too.
# Каталог bootstrap/ задают init.sh и точки входа; запасной путь — от BS_ROOT / BS_ENTRY_DIR
# The bootstrap/ directory is set by init.sh and the entry points; fallback: from BS_ROOT / BS_ENTRY_DIR
: "${BS_BOOTSTRAP_DIR:=${BS_ROOT:-${BS_ENTRY_DIR:-.}}/bootstrap}"
if [[ -f "${BS_BOOTSTRAP_DIR}/base.sh" ]]; then
  # shellcheck source=bootstrap/base.sh
  source "${BS_BOOTSTRAP_DIR}/base.sh"
fi

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

# @description Put the file of stack frame LEVEL into variable NAME (no subshell).
# @description Положить файл кадра стека LEVEL в переменную NAME (без подоболочки).
# @param $1 variable name / имя переменной
# @param $2 level (default 0) / уровень (по умолчанию 0)
# @returns 0; 2 if the variable name is not an identifier / 2, если имя не идентификатор
bs::stack_file_to() {
  [[ "${1:-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 2
  printf -v "$1" '%s' "${BASH_SOURCE[$(( ${2:-0} + 1 ))]:-unknown}"
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

# Результат последнего `[[ строка =~ regex ]]` в коде вызывающего. Единственное место,
# которое знает про BASH_REMATCH; вызывать сразу после сопоставления.
# The result of the caller's last `[[ string =~ regex ]]`. The only place that knows
# BASH_REMATCH; call it right after the match.

# @description Capture group N of the last regex match (empty if absent; 0 = whole match).
# @description Группа N последнего сопоставления с регулярным выражением (пусто, если нет; 0 — всё совпадение).
# @param $1 group number / номер группы
bs::regex::group() {
  printf '%s\n' "${BASH_REMATCH[${1:?group number required}]:-}"
}

# @description Number of captured items of the last regex match (group 0 included).
# @description Число захваченных элементов последнего сопоставления (включая группу 0).
bs::regex::count() {
  printf '%d\n' "${#BASH_REMATCH[@]}"
}

# @description Copy the groups of the last regex match into the caller's array.
# @description Скопировать группы последнего сопоставления в массив вызывающего.
# @param $1 array name / имя массива
bs::regex::captures() {
  local -n __bs_rx_out="${1:?array name required}"
  __bs_rx_out=("${BASH_REMATCH[@]}")
}

# @description Send `set -x` traces to the open file descriptor FD.
# @description Направить трассировку `set -x` в открытый дескриптор FD.
# @param $1 fd / дескриптор
bs::trace_to_fd() {
  BASH_XTRACEFD="${1:?fd required}"
}

# @description Make `set -x` traces show "file:line:" (PS4).
# @description Трассировка `set -x` показывает «файл:строка:» (PS4).
bs::trace_prefix() {
  # shellcheck disable=SC2016  # PS4 раскрывается при трассировке / PS4 expands at trace time
  PS4='+ ${BASH_SOURCE##*/}:${LINENO}: '
}

# ==========================================
# Source vs executed / Подключён или исполнен
#
# Определение оболочки и гейт версии — в bootstrap/base.sh (POSIX): bs_shell_name, bs_shell_host,
# bs_shell_version, bs_shell_ok, bs_shell_ensure_version. Здесь осталось только то, что читает BASH_SOURCE.
# The shell detection and the version gate are in bootstrap/base.sh (POSIX): bs_shell_name,
# bs_shell_host, bs_shell_version, bs_shell_ok, bs_shell_ensure_version. Only what reads BASH_SOURCE stays here.
# ==========================================

# @description Sourced vs executed for the DIRECT CALLER: 0 sourced, 1 executed.
# @description Source vs исполнение ПРЯМОГО ВЫЗЫВАЮЩЕГО: 0 при source, 1 при исполнении.
# Файл-вызывающий равен $0 только если он исполнен напрямую; при source $0 —
# скрипт-хозяин. Библиотечный режим — только bash (гейт в init.sh), ветки zsh нет.
# The caller file equals $0 only when executed directly; when sourced, $0 is the
# host script. Library mode is bash only (the gate in init.sh): no zsh branch.
# @return 0 caller is sourced / вызывающий подключён через source; 1 executed
bs::shell::is_sourced() {
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

# POSIX-часть команд (die, help, version, env, list, …) — bootstrap/cli.sh; здесь остальные, на bash
# The POSIX part of the commands (die, help, version, env, list, …) is bootstrap/cli.sh; the rest, in bash, is here
if [[ -f "${BS_BOOTSTRAP_DIR}/cli.sh" ]]; then
  # shellcheck source=bootstrap/cli.sh
  source "${BS_BOOTSTRAP_DIR}/cli.sh"
fi

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

bs::cli::run_cmd() {
  [[ $# -eq 0 ]] && bs::cli::die "run: script path required"
  local script=$1; shift
  is::file "$script" || bs::cli::die "run: file not found: $script"
  # Запускаем скрипт в новом bash с уже загруженным BS-окружением
  # Сбрасываем унаследованный BS_INITIALIZED, иначе init.sh пропустит загрузку
  BS_RUN_SCRIPT="$script" exec "$(bs::shell::host)" -c '
    unset BS_INITIALIZED
    source "'"${BS_ROOT}/bootstrap/init.sh"'"
    bs::strict
    script=$1; shift
    source "$script" "$@"
  ' "$script" "$script" "$@"
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
  if ! utils::quiet_err "$(bs::shell::host)" -n "$script"; then
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
  # RETURN-ловушка живёт и после возврата из функции: без сброса она сработала бы ещё раз у вызывающего,
  # где tmp_dir уже нет (под set -u это ошибка) / a RETURN trap outlives the function: without the reset it would fire
  # again in the caller, where tmp_dir is gone (an error under set -u)
  trap - RETURN

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
