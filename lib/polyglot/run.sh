#!/usr/bin/env bs
# shellcheck shell=bash
# lib/polyglot/run.sh — run C, C++, Go, Rust, Python and JavaScript code inside a bs script
# lib/polyglot/run.sh — запуск кода на C, C++, Go, Rust, Python и JavaScript внутри скрипта bs

# @depends core/lang, core/const, core/logger, core/utils
# @tier gnu-linux

# Source Guard
bs::guard "LIB_POLYGLOT_RUN" || return 0

# Dependencies
bs::source_relative "../../core/lang.sh" "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# ==========================================
# polyglot::run — a program in another language, two-way data exchange
# polyglot::run — программа на другом языке, обмен данными в обе стороны
#
#   IN  (script → program):  arguments after "--" (argv), environment variables
#                            (--env NAME=VALUE), text on the program's stdin (--input).
#                            Values are never pasted into the source: no code injection.
#   OUT (program → script):  stdout, captured into a variable (--out), an indexed array
#                            (--lines) or an associative array (--map, "key=value" lines);
#                            the exit code (--rc VAR, or the return status).
#   The source comes from stdin (heredoc). Compiled languages are built once and cached
#   by the hash of language + compiler version + flags + source.
#
#   ВХОД (скрипт → программа):  аргументы после "--" (argv), переменные окружения
#                               (--env NAME=VALUE), текст на stdin программы (--input).
#                               Значения не вставляются в исходник: инъекции кода нет.
#   ВЫХОД (программа → скрипт): stdout в переменную (--out), индексный массив (--lines)
#                               или ассоциативный (--map, строки "ключ=значение"); код
#                               возврата (--rc VAR или статус возврата).
#   Исходник — со stdin (heredoc). Компилируемые языки собираются один раз и кэшируются
#   по хешу «язык + версия компилятора + флаги + исходник».
#
# SECURITY: the source is executed with your privileges — feed only code you trust.
# БЕЗОПАСНОСТЬ: исходник исполняется с вашими правами — подавайте только доверенный код.
# ==========================================

# @global POLYGLOT_CACHE_DIR — Hook: cache of compiled programs and sources (category: hook)
# @global POLYGLOT_CACHE_DIR — Хук: кэш скомпилированных программ и исходников (категория: hook)
: "${POLYGLOT_CACHE_DIR:=${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/bs/polyglot}"

# @global POLYGLOT_C_TOOLS — Hook: C compilers to probe, first found wins (category: hook)
# @global POLYGLOT_C_TOOLS — Хук: C-компиляторы, берётся первый найденный (категория: hook)
: "${POLYGLOT_C_TOOLS:=cc gcc clang}"
# @global POLYGLOT_CPP_TOOLS — Hook: C++ compilers to probe (category: hook)
# @global POLYGLOT_CPP_TOOLS — Хук: C++-компиляторы (категория: hook)
: "${POLYGLOT_CPP_TOOLS:=c++ g++ clang++}"
# @global POLYGLOT_GO_TOOLS — Hook: Go tool to probe (category: hook)
# @global POLYGLOT_GO_TOOLS — Хук: инструмент Go (категория: hook)
: "${POLYGLOT_GO_TOOLS:=go}"
# @global POLYGLOT_RUST_TOOLS — Hook: Rust compiler to probe (category: hook)
# @global POLYGLOT_RUST_TOOLS — Хук: компилятор Rust (категория: hook)
: "${POLYGLOT_RUST_TOOLS:=rustc}"
# @global POLYGLOT_PYTHON_TOOLS — Hook: Python interpreters to probe (category: hook)
# @global POLYGLOT_PYTHON_TOOLS — Хук: интерпретаторы Python (категория: hook)
: "${POLYGLOT_PYTHON_TOOLS:=python3 python}"
# @global POLYGLOT_JS_TOOLS — Hook: JavaScript runtimes to probe (category: hook)
# @global POLYGLOT_JS_TOOLS — Хук: рантаймы JavaScript (категория: hook)
: "${POLYGLOT_JS_TOOLS:=node bun}"

# @global POLYGLOT_NPM_TOOLS — Hook: npm to probe for JavaScript dependencies (category: hook)
# @global POLYGLOT_NPM_TOOLS — Хук: npm для зависимостей JavaScript (категория: hook)
: "${POLYGLOT_NPM_TOOLS:=npm}"
# @global POLYGLOT_CARGO_TOOLS — Hook: cargo to probe for Rust dependencies (category: hook)
# @global POLYGLOT_CARGO_TOOLS — Хук: cargo для зависимостей Rust (категория: hook)
: "${POLYGLOT_CARGO_TOOLS:=cargo}"
# @global POLYGLOT_PKGCONFIG_TOOLS — Hook: pkg-config to probe for C/C++ libraries (category: hook)
# @global POLYGLOT_PKGCONFIG_TOOLS — Хук: pkg-config для библиотек C/C++ (категория: hook)
: "${POLYGLOT_PKGCONFIG_TOOLS:=pkg-config pkgconf}"

# @global POLYGLOT_DEPS_OUT — Result of polyglot::__deps_env: environment dir or pkg-config flags (category: state)
# @global POLYGLOT_DEPS_OUT — Результат polyglot::__deps_env: каталог окружения или флаги pkg-config (категория: state)
declare -g POLYGLOT_DEPS_OUT=""
# @global POLYGLOT_RUN_TARGET — Result of polyglot::__prepare: file to run (category: state)
# @global POLYGLOT_RUN_TARGET — Результат polyglot::__prepare: запускаемый файл (категория: state)
declare -g POLYGLOT_RUN_TARGET=""
# @global POLYGLOT_RUN_RUNNER — Result of polyglot::__prepare: interpreter command (category: state)
# @global POLYGLOT_RUN_RUNNER — Результат polyglot::__prepare: команда интерпретатора (категория: state)
declare -ga POLYGLOT_RUN_RUNNER=()
# @global POLYGLOT_RUN_ENV — Result of polyglot::__prepare: extra NAME=VALUE for the run (category: state)
# @global POLYGLOT_RUN_ENV — Результат polyglot::__prepare: дополнительные NAME=VALUE для запуска (категория: state)
declare -ga POLYGLOT_RUN_ENV=()

# @global POLYGLOT_TOOL_IDS — Cache: tool identity (path + version) per tool (category: cache)
# @global POLYGLOT_TOOL_IDS — Кэш: идентичность инструмента (путь + версия) (категория: cache)
declare -gA POLYGLOT_TOOL_IDS=()

# ==========================================
# Language table / Таблица языков
# ==========================================

# @private
# @description Canonical language name for an alias, or empty.
# @description Каноническое имя языка по псевдониму или пусто.
# @param $1 alias / псевдоним
# @stdout c|cpp|go|rust|python|js
polyglot::__lang() {
  case "${1:-}" in
    c) printf 'c\n' ;;
    cpp | c++ | cxx | cc) printf 'cpp\n' ;;
    go | golang) printf 'go\n' ;;
    rust | rs) printf 'rust\n' ;;
    python | python3 | py) printf 'python\n' ;;
    js | javascript | node) printf 'js\n' ;;
    *) return 1 ;;
  esac
}

# @private
# @description File extension of a language / Расширение файла языка.
polyglot::__ext() {
  case "${1}" in
    c) printf 'c\n' ;;
    cpp) printf 'cpp\n' ;;
    go) printf 'go\n' ;;
    rust) printf 'rs\n' ;;
    python) printf 'py\n' ;;
    js) printf 'js\n' ;;
  esac
}

# @private
# @description True for languages that are compiled to a binary / Компилируемые языки.
polyglot::__compiled() {
  case "${1}" in c | cpp | go | rust) return 0 ;; *) return 1 ;; esac
}

# @private
# @description First available tool of a language / Первый доступный инструмент языка.
# @param $1 canonical language / язык
# @stdout tool name / имя инструмента
# @return 0 found, 1 none
polyglot::__tool() {
  local list t
  case "${1}" in
    c) list="${POLYGLOT_C_TOOLS}" ;;
    cpp) list="${POLYGLOT_CPP_TOOLS}" ;;
    go) list="${POLYGLOT_GO_TOOLS}" ;;
    rust) list="${POLYGLOT_RUST_TOOLS}" ;;
    python) list="${POLYGLOT_PYTHON_TOOLS}" ;;
    js) list="${POLYGLOT_JS_TOOLS}" ;;
    *) return 1 ;;
  esac
  local -a tools=()
  IFS=' ' read -r -a tools <<< "${list}"
  for t in "${tools[@]}"; do
    if utils::has "${t}"; then
      printf '%s\n' "${t}"
      return 0
    fi
  done
  return 1
}

# @private
# @description Identity of a tool for the cache key: resolved path and first line of its version.
# @description Идентичность инструмента для ключа кэша: путь и первая строка версии.
# @param $1 tool name / имя инструмента
# @stdout identity / идентичность
polyglot::__tool_id() {
  local -r t="$1"
  if [[ -z "${POLYGLOT_TOOL_IDS["${t}"]:-}" ]]; then
    local v
    v="$("${t}" --version 2>&1 | head -n 1 || true)"
    [[ -n "${v}" ]] || v="$("${t}" version 2>&1 | head -n 1 || true)"
    POLYGLOT_TOOL_IDS["${t}"]="$(command -v "${t}")|${v}"
  fi
  printf '%s\n' "${POLYGLOT_TOOL_IDS["${t}"]}"
}

# @private
# @description Robust content hash (coreutils, macOS, busybox).
# @description Надёжный хеш содержимого (coreutils, macOS, busybox).
# @stdin data / данные
# @stdout hash / хеш
polyglot::__sha256() {
  if utils::has sha256sum; then
    sha256sum | awk '{print $1}'
  elif utils::has shasum; then
    shasum -a 256 | awk '{print $1}'
  else
    cksum | awk '{print $1}'
  fi
}

# @private
# @description Valid shell variable name? / Допустимое имя переменной?
polyglot::__valid_name() {
  [[ "${1:-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}

# ==========================================
# Build / Сборка
# ==========================================

# @private
# @description First tool of a hook list that is installed / Первый установленный инструмент из списка.
# @param $1 space separated names / имена через пробел
polyglot::__first() {
  local -a names=()
  IFS=' ' read -r -a names <<< "${1}"
  local n
  for n in "${names[@]}"; do
    if utils::has "${n}"; then
      printf '%s\n' "${n}"
      return 0
    fi
  done
  return 1
}

# @private
# @description Is a dependency spec safe (no option injection, no shell metacharacters)?
# @description Безопасна ли запись зависимости (без опций и метасимволов)?
polyglot::__dep_valid() {
  [[ "${1:-}" =~ ^[A-Za-z0-9._/@:+=~^-]+$ && "${1}" != -* ]]
}

# @private
# @description Check the package manager a language needs for its dependencies — BEFORE anything
#   is built or run. Prints the reason and an install hint on failure.
# @description Проверить менеджер пакетов, нужный языку для зависимостей, — ДО сборки и запуска.
#   При неудаче печатает причину и подсказку по установке.
# @param $1 canonical language / язык
# @param $2 language tool / инструмент языка
# @return 0 present, LIB_ERROR_DEPENDENCY_MISSING otherwise
polyglot::__check_manager() {
  local -r lang="$1" tool="$2"
  local what="" hint=""
  case "${lang}" in
    python)
      if ! "${tool}" -m pip --version >/dev/null 2>&1; then
        what="pip (${tool} -m pip)"
        hint="apt install python3-pip python3-venv | dnf install python3-pip | apk add py3-pip | brew install python"
      elif ! "${tool}" -m venv --help >/dev/null 2>&1; then
        what="venv (${tool} -m venv)"
        hint="apt install python3-venv | dnf install python3 | apk add python3"
      fi ;;
    js)
      if ! polyglot::__first "${POLYGLOT_NPM_TOOLS}" >/dev/null; then
        what="npm"
        hint="apt install npm | dnf install npm | apk add npm | brew install node"
      fi ;;
    go)
      # зависимости Go ставит сам go (модули) / Go dependencies are fetched by go itself (modules)
      if ! "${tool}" env GOPATH >/dev/null 2>&1; then
        what="go modules (${tool})"
        hint="apt install golang | dnf install golang | apk add go | brew install go"
      fi ;;
    rust)
      if ! polyglot::__first "${POLYGLOT_CARGO_TOOLS}" >/dev/null; then
        what="cargo"
        hint="apt install cargo | dnf install cargo | apk add cargo | brew install rust | https://rustup.rs"
      fi ;;
    c | cpp)
      if ! polyglot::__first "${POLYGLOT_PKGCONFIG_TOOLS}" >/dev/null; then
        what="pkg-config"
        hint="apt install pkg-config | dnf install pkgconf | apk add pkgconf | brew install pkg-config"
      fi ;;
  esac
  if [[ -n "${what}" ]]; then
    log::error "polyglot: ${what} is not available — dependencies for '${lang}' cannot be installed / недоступен ${what}"
    log::error "  install / установите: ${hint}"
    return "${LIB_ERROR_DEPENDENCY_MISSING}"
  fi
  return 0
}

# @private
# @description Environment with the dependencies installed (cached by the hash of language, tool, deps).
#   Python: a venv with pip; JavaScript: node_modules via npm; Go: a module via go get;
#   Rust: a cargo project; C/C++: pkg-config flags. Fills POLYGLOT_RUN_ENV / POLYGLOT_RUN_RUNNER
#   or prints the extra compiler flags.
# @description Окружение с установленными зависимостями (кэш по хешу языка, инструмента, зависимостей).
# @param $1 canonical language / язык
# @param $2 language tool / инструмент языка
# @param $3 dependencies, one per line / зависимости по одной в строке
# @param $4 no-cache (1/0) / без кэша
# @return 0 ok; POLYGLOT_DEPS_OUT holds the environment directory (or the pkg-config flags for C/C++)
polyglot::__deps_env() {
  local -r lang="$1" tool="$2" deps_text="$3" nocache="$4"
  local -a deps=()
  mapfile -t deps <<< "${deps_text}"
  local d
  for d in "${deps[@]}"; do
    polyglot::__dep_valid "${d}" || {
      log::error "polyglot: unsafe dependency spec '${d}' / небезопасная запись зависимости"
      return "${LIB_ERROR_INVALID_ARGS}"
    }
  done

  if [[ "${lang}" == c || "${lang}" == cpp ]]; then
    local pc
    pc="$(polyglot::__first "${POLYGLOT_PKGCONFIG_TOOLS}")"
    for d in "${deps[@]}"; do
      "${pc}" --exists "${d}" 2>/dev/null || {
        log::error "polyglot: library '${d}' not found by ${pc} / библиотека '${d}' не найдена"
        return "${LIB_ERROR_DEPENDENCY_MISSING}"
      }
    done
    POLYGLOT_DEPS_OUT="$("${pc}" --cflags --libs "${deps[@]}")"
    return 0
  fi

  local hash env
  hash="$(printf '%s\0%s\0%s' "${lang}" "$(polyglot::__tool_id "${tool}")" "${deps_text}" | polyglot::__sha256)"
  env="${POLYGLOT_CACHE_DIR}/${lang}-deps/${hash}"
  if [[ "${nocache}" != 1 && -f "${env}/.ready" ]]; then
    POLYGLOT_DEPS_OUT="${env}"
    return 0
  fi
  rm -rf -- "${env}"
  mkdir -p "${env}" || return "${LIB_ERROR_FILE_OPERATION}"
  log::info "polyglot: installing ${#deps[@]} ${lang} dependenc(ies) / установка зависимостей: ${deps[*]}"
  local out="" rc=0
  case "${lang}" in
    python)
      out="$("${tool}" -m venv "${env}" 2>&1 && "${env}/bin/python" -m pip install --quiet --disable-pip-version-check "${deps[@]}" 2>&1)" || rc=$? ;;
    js)
      local npm
      npm="$(polyglot::__first "${POLYGLOT_NPM_TOOLS}")"
      out="$("${npm}" install --silent --no-audit --no-fund --prefix "${env}" "${deps[@]}" 2>&1)" || rc=$? ;;
    go)
      printf 'module bspolyglot\n\ngo 1.20\n' > "${env}/go.mod"
      out="$(cd "${env}" && "${tool}" get "${deps[@]}" 2>&1)" || rc=$? ;;
    rust)
      local cargo_tool
      cargo_tool="$(polyglot::__first "${POLYGLOT_CARGO_TOOLS}")"
      {
        printf '[package]\nname = "bspolyglot"\nversion = "0.0.0"\nedition = "2021"\n\n[dependencies]\n'
        for d in "${deps[@]}"; do
          if [[ "${d}" == *@* ]]; then
            printf '%s = "%s"\n' "${d%%@*}" "${d#*@}"
          else
            printf '%s = "*"\n' "${d}"
          fi
        done
      } > "${env}/Cargo.toml"
      mkdir -p "${env}/src"
      printf 'fn main() {}\n' > "${env}/src/main.rs"
      out="$(cd "${env}" && "${cargo_tool}" fetch --quiet 2>&1)" || rc=$? ;;
  esac
  if (( rc != 0 )); then
    log::error "polyglot: installing dependencies failed / не удалось установить зависимости"
    local line
    while IFS= read -r line; do log::error "  ${line}"; done <<< "${out}"
    rm -rf -- "${env}"
    return "${LIB_ERROR_DEPENDENCY}"
  fi
  : > "${env}/.ready"
  POLYGLOT_DEPS_OUT="${env}"
}

# @private
# @description Prepare the program: write the source into the cache, install dependencies, compile
#   when the language is compiled (or reuse the cached binary). Sets POLYGLOT_RUN_TARGET,
#   POLYGLOT_RUN_RUNNER and POLYGLOT_RUN_ENV.
# @description Подготовить программу: записать исходник в кэш, поставить зависимости, скомпилировать
#   (или взять готовый бинарник). Заполняет POLYGLOT_RUN_TARGET, POLYGLOT_RUN_RUNNER, POLYGLOT_RUN_ENV.
# @param $1 canonical language / язык
# @param $2 tool / инструмент
# @param $3 source / исходник
# @param $4 extra flags (space separated) / дополнительные флаги
# @param $5 no-cache flag (1/0) / без кэша
# @param $6 dependencies, one per line (may be empty) / зависимости по одной в строке
# @return 0 ok, LIB_ERROR_FILE_OPERATION, LIB_ERROR_DEPENDENCY, LIB_ERROR_DEPENDENCY_MISSING
polyglot::__prepare() {
  local -r lang="$1" tool="$2" src="$3" nocache="$5" deps_text="${6-}"
  local flags="$4"
  POLYGLOT_RUN_TARGET=""
  POLYGLOT_RUN_RUNNER=()
  POLYGLOT_RUN_ENV=()

  # Менеджер пакетов проверяется ДО всего остального / the package manager is checked BEFORE anything else
  local env_dir=""
  if [[ -n "${deps_text}" ]]; then
    polyglot::__check_manager "${lang}" "${tool}" || return $?
    POLYGLOT_DEPS_OUT=""
    polyglot::__deps_env "${lang}" "${tool}" "${deps_text}" "${nocache}" || return $?
    if [[ "${lang}" == c || "${lang}" == cpp ]]; then
      flags="${flags} ${POLYGLOT_DEPS_OUT}"
    else
      env_dir="${POLYGLOT_DEPS_OUT}"
    fi
  fi

  local ext hash dir file bin
  ext="$(polyglot::__ext "${lang}")"
  hash="$(printf '%s\0%s\0%s\0%s\0%s' "${lang}" "$(polyglot::__tool_id "${tool}")" "${flags}" "${deps_text}" "${src}" | polyglot::__sha256)"
  dir="${POLYGLOT_CACHE_DIR}/${lang}"
  mkdir -p "${dir}" || return "${LIB_ERROR_FILE_OPERATION}"
  file="${dir}/${hash}.${ext}"
  bin="${dir}/${hash}"

  if ! polyglot::__compiled "${lang}"; then
    if [[ "${nocache}" == 1 || ! -f "${file}" ]]; then
      polyglot::__write_atomic "${file}" "${src}" || return "${LIB_ERROR_FILE_OPERATION}"
    fi
    POLYGLOT_RUN_TARGET="${file}"
    case "${lang}" in
      python)
        if [[ -n "${env_dir}" ]]; then POLYGLOT_RUN_RUNNER=("${env_dir}/bin/python"); else POLYGLOT_RUN_RUNNER=("${tool}"); fi ;;
      js)
        POLYGLOT_RUN_RUNNER=("${tool}")
        [[ -n "${env_dir}" ]] && POLYGLOT_RUN_ENV=("NODE_PATH=${env_dir}/node_modules") ;;
    esac
    return 0
  fi

  if [[ "${nocache}" != 1 && -x "${bin}" ]]; then
    POLYGLOT_RUN_TARGET="${bin}"
    return 0
  fi

  polyglot::__write_atomic "${file}" "${src}" || return "${LIB_ERROR_FILE_OPERATION}"
  local tmp_bin="${bin}.tmp.$$"
  local -a extra=()
  IFS=' ' read -r -a extra <<< "${flags}"
  local err="" rc=0
  case "${lang}" in
    c)    err="$("${tool}" -O2 -x c "${file}" -o "${tmp_bin}" ${extra[@]+"${extra[@]}"} -lm 2>&1)" || rc=$? ;;
    cpp)  err="$("${tool}" -O2 -x c++ "${file}" -o "${tmp_bin}" ${extra[@]+"${extra[@]}"} 2>&1)" || rc=$? ;;
    go)
      if [[ -n "${env_dir}" ]]; then
        cp -- "${file}" "${env_dir}/main.go"
        err="$(cd "${env_dir}" && "${tool}" build -o "${tmp_bin}" ${extra[@]+"${extra[@]}"} . 2>&1)" || rc=$?
      else
        err="$("${tool}" build -o "${tmp_bin}" ${extra[@]+"${extra[@]}"} "${file}" 2>&1)" || rc=$?
      fi ;;
    rust)
      if [[ -n "${env_dir}" ]]; then
        cp -- "${file}" "${env_dir}/src/main.rs"
        local cargo_tool
        cargo_tool="$(polyglot::__first "${POLYGLOT_CARGO_TOOLS}")"
        err="$(cd "${env_dir}" && "${cargo_tool}" build --release --quiet ${extra[@]+"${extra[@]}"} 2>&1)" || rc=$?
        [[ ${rc} -eq 0 ]] && cp -- "${env_dir}/target/release/bspolyglot" "${tmp_bin}"
      else
        err="$("${tool}" -O -o "${tmp_bin}" ${extra[@]+"${extra[@]}"} "${file}" 2>&1)" || rc=$?
      fi ;;
  esac
  if (( rc != 0 )) || [[ ! -x "${tmp_bin}" ]]; then
    log::error "polyglot: ${lang} compilation failed (${tool}) / сборка ${lang} не удалась"
    local line
    while IFS= read -r line; do
      log::error "  ${line}"
    done <<< "${err}"
    rm -f -- "${tmp_bin}"
    return "${LIB_ERROR_DEPENDENCY}"
  fi
  mv -f -- "${tmp_bin}" "${bin}" || return "${LIB_ERROR_FILE_OPERATION}"
  POLYGLOT_RUN_TARGET="${bin}"
}

# @private
# @description Write a file atomically (temp file + rename) / Атомарная запись файла.
polyglot::__write_atomic() {
  local -r target="$1" content="$2"
  local -r tmp="${target}.tmp.$$"
  printf '%s\n' "${content}" > "${tmp}" || return 1
  mv -f -- "${tmp}" "${target}"
}

# ==========================================
# Public API / Публичный API
# ==========================================

# @description List the languages and whether their tool is installed.
# @description Показать языки и установлен ли их инструмент.
# @stdout lines "language<TAB>tool or -"
# @example
#   polyglot::languages
polyglot::languages() {
  local l t
  for l in c cpp go rust python js; do
    t="$(polyglot::__tool "${l}" || true)"
    printf '%s\t%s\n' "${l}" "${t:--}"
  done
}

# @description Report the language tools and the package managers needed for --dep, with install hints.
# @description Показать инструменты языков и менеджеры пакетов для --dep с подсказками по установке.
# @stdout lines "item<TAB>status<TAB>detail"
# @return 0 always; the report says what is missing
polyglot::doctor() {
  local l t m
  for l in c cpp go rust python js; do
    t="$(polyglot::__tool "${l}" || true)"
    polyglot::__row "${l}" "${t}"
  done
  t="$(polyglot::__tool python || true)"
  if [[ -n "${t}" ]] && "${t}" -m pip --version >/dev/null 2>&1; then
    m="${t} -m pip"
  else
    m=""
  fi
  polyglot::__row pip "${m}"
  for l in "npm:${POLYGLOT_NPM_TOOLS}" "cargo:${POLYGLOT_CARGO_TOOLS}" "pkg-config:${POLYGLOT_PKGCONFIG_TOOLS}"; do
    t="$(polyglot::__first "${l#*:}" || true)"
    polyglot::__row "${l%%:*}" "${t}"
  done
  polyglot::__row go-modules "$(polyglot::__tool go || true)"
}

# @private
# @description One doctor row: item, ok|missing, what was found / Строка отчёта doctor.
polyglot::__row() {
  if [[ -n "${2}" ]]; then
    printf '%s\tok\t%s\n' "${1}" "${2}"
  else
    printf '%s\tmissing\t-\n' "${1}"
  fi
}

# @description Run code written in another language and bring the result back.
# @description Выполнить код на другом языке и вернуть результат в скрипт.
# @param $1 Language: c, cpp, go, rust, python, js (aliases: c++, golang, rs, py, javascript, node)
# @param $@ Options:
#   --out VAR       stdout (trailing newlines removed) into the scalar VAR
#   --lines VAR     stdout lines into the indexed array VAR
#   --map VAR       "key=value" lines into the associative array VAR (declare -A first)
#   --rc VAR        exit code of the program into VAR; the function then returns 0
#   --env N=V       environment variable for the program (repeatable)
#   --input TEXT    text on the program's stdin
#   --timeout SEC   kill the program after SEC seconds
#   --flags "…"     extra compiler flags (compiled languages)
#   --dep SPEC      a dependency (repeatable): pip package, npm package, Go module[@ver],
#                   cargo crate[@ver], or a pkg-config library for C/C++; the package
#                   manager is checked BEFORE anything runs (LIB_ERROR_DEPENDENCY_MISSING)
#   --no-cache      rebuild even if a cached binary exists
#   --              everything after is passed to the program as arguments (argv)
# @stdin the source code (heredoc) / исходный код (heredoc)
# @stdout the program's stdout when no --out/--lines/--map is given
# @return the program's exit code (or 0 with --rc); LIB_ERROR_INVALID_ARGS for bad
#   usage; LIB_ERROR_DEPENDENCY_MISSING if the language tool is absent;
#   LIB_ERROR_DEPENDENCY if compilation failed; LIB_ERROR_TIMEOUT on --timeout
# @example
#   polyglot::run python --out answer -- 21 <<'EOF'
#   import sys
#   print(int(sys.argv[1]) * 2)
#   EOF
#   echo "${answer}"        # 42
#
#   declare -A cfg
#   polyglot::run c --map cfg --env NAME=bs <<'EOF'
#   #include <stdio.h>
#   #include <stdlib.h>
#   int main(void) { printf("name=%s\nlen=%d\n", getenv("NAME"), 2); return 0; }
#   EOF
polyglot::run() {
  local _pg_lang
  _pg_lang="$(polyglot::__lang "${1:-}")" || {
    log::error "polyglot::run: unknown language '${1:-}' (c cpp go rust python js) / неизвестный язык"
    return "${LIB_ERROR_INVALID_ARGS}"
  }
  shift

  local _pg_out_var="" _pg_lines_var="" _pg_map_var="" _pg_rc_var="" _pg_input="" _pg_timeout_s="" _pg_flags="" _pg_nocache=0 _pg_has_input=0
  local _pg_deps=""
  local -a _pg_envs=() _pg_args=()
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --out)     _pg_out_var="${2:?--out needs a variable name}"; shift 2 ;;
      --lines)   _pg_lines_var="${2:?--lines needs a variable name}"; shift 2 ;;
      --map)     _pg_map_var="${2:?--map needs a variable name}"; shift 2 ;;
      --rc)      _pg_rc_var="${2:?--rc needs a variable name}"; shift 2 ;;
      --env)     _pg_envs+=("${2:?--env needs NAME=VALUE}"); shift 2 ;;
      --input)   _pg_input="${2-}"; _pg_has_input=1; shift 2 ;;
      --timeout) _pg_timeout_s="${2:?--timeout needs seconds}"; shift 2 ;;
      --flags)   _pg_flags="${2-}"; shift 2 ;;
      --dep)
        polyglot::__dep_valid "${2:-}" || {
          log::error "polyglot::run: unsafe or empty --dep '${2:-}' (a name, optionally @version, no spaces or leading -) / небезопасная или пустая зависимость"
          return "${LIB_ERROR_INVALID_ARGS}"
        }
        _pg_deps+="${2}"$'\n'; shift 2 ;;
      --no-cache) _pg_nocache=1; shift ;;
      --)        shift; _pg_args=("$@"); break ;;
      *)
        log::error "polyglot::run: unknown option '${1}' (arguments for the program go after --) / неизвестная опция"
        return "${LIB_ERROR_INVALID_ARGS}"
        ;;
    esac
  done

  local _pg_v
  for _pg_v in "${_pg_out_var}" "${_pg_lines_var}" "${_pg_map_var}" "${_pg_rc_var}"; do
    [[ -z "${_pg_v}" ]] && continue
    polyglot::__valid_name "${_pg_v}" || {
      log::error "polyglot::run: invalid variable name '${_pg_v}' / неверное имя переменной"
      return "${LIB_ERROR_INVALID_ARGS}"
    }
  done
  local _pg_e
  for _pg_e in ${_pg_envs[@]+"${_pg_envs[@]}"}; do
    [[ "${_pg_e}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || {
      log::error "polyglot::run: --env expects NAME=VALUE, got '${_pg_e}' / ожидается NAME=VALUE"
      return "${LIB_ERROR_INVALID_ARGS}"
    }
  done
  if [[ -n "${_pg_timeout_s}" && ! "${_pg_timeout_s}" =~ ^[0-9]+$ ]]; then
    log::error "polyglot::run: --timeout must be whole seconds / --timeout — целые секунды"
    return "${LIB_ERROR_INVALID_ARGS}"
  fi
  if [[ -n "${_pg_map_var}" ]]; then
    [[ "$(declare -p "${_pg_map_var}" 2>/dev/null)" == "declare -A"* ]] || {
      log::error "polyglot::run: --map '${_pg_map_var}' must be declared with declare -A first / сначала declare -A ${_pg_map_var}"
      return "${LIB_ERROR_INVALID_ARGS}"
    }
  fi

  local _pg_src=""
  IFS= read -r -d '' _pg_src || :
  _pg_src="${_pg_src%$'\n'}"
  if [[ -z "${_pg_src}" ]]; then
    log::error "polyglot::run: empty source (pass the code in a heredoc) / пустой исходник (передайте код через heredoc)"
    return "${LIB_ERROR_INVALID_ARGS}"
  fi

  local _pg_tool
  _pg_tool="$(polyglot::__tool "${_pg_lang}")" || {
    log::error "polyglot::run: no tool for '${_pg_lang}' found (see polyglot::languages) / не найден инструмент для '${_pg_lang}'"
    return "${LIB_ERROR_DEPENDENCY_MISSING}"
  }

  _pg_deps="${_pg_deps%$'\n'}"
  polyglot::__prepare "${_pg_lang}" "${_pg_tool}" "${_pg_src}" "${_pg_flags}" "${_pg_nocache}" "${_pg_deps}" || return $?

  local -a _pg_cmd=()
  if (( ${#_pg_envs[@]} + ${#POLYGLOT_RUN_ENV[@]} > 0 )); then
    _pg_cmd+=(env ${POLYGLOT_RUN_ENV[@]+"${POLYGLOT_RUN_ENV[@]}"} ${_pg_envs[@]+"${_pg_envs[@]}"})
  fi
  if [[ -n "${_pg_timeout_s}" ]]; then
    _pg_cmd+=(timeout "${_pg_timeout_s}")
  fi
  if (( ${#POLYGLOT_RUN_RUNNER[@]} > 0 )); then
    _pg_cmd+=("${POLYGLOT_RUN_RUNNER[@]}" "${POLYGLOT_RUN_TARGET}")
  else
    _pg_cmd+=("${POLYGLOT_RUN_TARGET}")
  fi
  _pg_cmd+=(${_pg_args[@]+"${_pg_args[@]}"})

  local _pg_out="" _pg_rc=0
  if (( _pg_has_input == 1 )); then
    if _pg_out="$("${_pg_cmd[@]}" <<< "${_pg_input}")"; then _pg_rc=0; else _pg_rc=$?; fi
  else
    if _pg_out="$("${_pg_cmd[@]}" < /dev/null)"; then _pg_rc=0; else _pg_rc=$?; fi
  fi

  if [[ -n "${_pg_out_var}" ]]; then
    local -n __pg_out="${_pg_out_var}"
    __pg_out="${_pg_out}"
  fi
  if [[ -n "${_pg_lines_var}" ]]; then
    local -n __pg_lines="${_pg_lines_var}"
    __pg_lines=()
    if [[ -n "${_pg_out}" ]]; then
      mapfile -t __pg_lines <<< "${_pg_out}"
    fi
  fi
  if [[ -n "${_pg_map_var}" ]]; then
    local -n __pg_map="${_pg_map_var}"
    __pg_map=()
    local _pg_line
    while IFS= read -r _pg_line; do
      [[ "${_pg_line}" == *=* ]] || continue
      __pg_map["${_pg_line%%=*}"]="${_pg_line#*=}"
    done <<< "${_pg_out}"
  fi
  if [[ -z "${_pg_out_var}${_pg_lines_var}${_pg_map_var}" && -n "${_pg_out}" ]]; then
    printf '%s\n' "${_pg_out}"
  fi

  if [[ -n "${_pg_rc_var}" ]]; then
    local -n __pg_rc="${_pg_rc_var}"
    __pg_rc="${_pg_rc}"
    return 0
  fi
  if [[ -n "${_pg_timeout_s}" && "${_pg_rc}" -eq 124 ]]; then
    return "${LIB_ERROR_TIMEOUT}"
  fi
  return "${_pg_rc}"
}
