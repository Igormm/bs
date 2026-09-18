#!/usr/bin/env bs
# shellcheck shell=bash
# lib/math/math.sh — C-backed expression evaluator (real math for BS)
# lib/math/math.sh — вычисление выражений через C (настоящая математика для BS)

# @depends core/lang, core/const, core/utils
# @tier gnu-linux

# Source Guard
bs::guard "LIB_MATH" || return 0

# Dependencies
bs::source_relative "../../core/lang.sh" "../../core/const.sh" "../../core/utils.sh"

# ==========================================
# Math evaluator / Математический вычислитель
#
# Bash arithmetic is integers only — useless for real math. This module
# compiles the expression into a tiny C program (double precision,
# math.h: sin/cos/pow/sqrt/log/...) and runs it. The first evaluation
# compiles (~100 ms), the binary is cached by content hash, subsequent
# calls run in ~1 ms. Input via heredoc (triple quotes):
#   math::eval <<'EOF'
#   pow(2, 10) + sqrt(144) * sin(PI / 6)
#   EOF
# SECURITY: the expression is compiled and executed as C — only feed
# expressions you trust. Requires cc (gcc/clang).
# Арифметика bash — только целые числа, для настоящей математики она
# бесполезна. Модуль компилирует выражение в крошечную C-программу
# (double, math.h: sin/cos/pow/sqrt/log/...) и запускает её. Первое
# вычисление компилирует (~100 мс), бинарник кэшируется по хешу,
# последующие вызовы — ~1 мс. Ввод — через heredoc (тройные кавычки):
#   math::eval <<'EOF'
#   pow(2, 10) + sqrt(144) * sin(PI / 6)
#   EOF
# БЕЗОПАСНОСТЬ: выражение компилируется и выполняется как C — подавайте
# только доверенные выражения. Требуется cc (gcc/clang).
# ==========================================

# Cache dir / Каталог кэша
: "${MATH_CACHE_DIR:=${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/bs/math}"

# Helpers available in every expression (math.h + small extras).
# Хелперы, доступные в каждом выражении (math.h + небольшие дополнения).
readonly MATH_TEMPLATE_HEAD='#include <math.h>
#include <stdio.h>
#define PI 3.14159265358979323846
#define TAU 6.28318530717958647692
#define E 2.71828182845904523536
#define deg(x) ((x) * (180.0 / PI))
#define rad(x) ((x) * (PI / 180.0))
#define sign(x) ((x) > 0 ? 1 : ((x) < 0 ? -1 : 0))
#define clamp(x, a, b) fmin(fmax((x), (a)), (b))
#define lerp(a, b, t) ((a) + (t) * ((b) - (a)))
#define roundn(x, n) (round((x) * pow(10, (n))) / pow(10, (n)))
int main(void) {'

readonly MATH_TEMPLATE_EXPR_OPEN='  double __result = ('

readonly MATH_TEMPLATE_TAIL=');
  printf(FMT "\n", __result);
  return 0;
}
'

# @private
# @description Robust content hash (coreutils, macOS, busybox).
# @description Надёжный хеш содержимого.
# @stdin data / данные
# @stdout hash / хеш
__math::sha256() {
  if utils::has sha256sum; then
    sha256sum | awk '{print $1}'
  elif utils::has shasum; then
    shasum -a 256 | awk '{print $1}'
  else
    cksum | awk '{print $1}'
  fi
}

# @private
# @description Find a C compiler / Найти C-компилятор.
# @stdout compiler path or empty / путь или пусто
__math::compiler() {
  if utils::has cc; then
    printf 'cc\n'
  elif utils::has gcc; then
    printf 'gcc\n'
  elif utils::has clang; then
    printf 'clang\n'
  fi
}

# @private
# @description Compile (or fetch from cache) the evaluator binary.
# @description Скомпилировать (или взять из кэша) бинарник вычислителя.
# @param $1 Variable declarations (may be empty) / Объявления переменных
# @param $2 Expression / Выражение
# @param $3 Output format string / Строка формата вывода
# @stdout path to the binary / путь к бинарнику
# @return 0 ok, 1 no compiler, 2 compile failed
__math::build() {
  local -r var_decls="$1" expr="$2" fmt="$3"
  local compiler
  compiler="$(__math::compiler)"
  if is::empty "${compiler}"; then
    log::error "math: no C compiler found (install gcc or clang)"
    return 1
  fi

  # Формат подставляется как строковый литерал / Format as string literal
  local fmt_escaped="${fmt//\\/\\\\}"
  fmt_escaped="${fmt_escaped//\"/\\\"}"
  local csrc
  csrc="${MATH_TEMPLATE_HEAD}
${var_decls}${MATH_TEMPLATE_EXPR_OPEN}
${expr}${MATH_TEMPLATE_TAIL//FMT/\"${fmt_escaped}\"}"

  local hash out
  hash="$(printf '%s' "${csrc}" | __math::sha256)"
  out="${MATH_CACHE_DIR}/${hash}"

  if [[ -x "${out}" ]]; then
    printf '%s\n' "${out}"
    return 0
  fi

  mkdir -p "${MATH_CACHE_DIR}" || return 2
  local err
  err="$(printf '%s' "${csrc}" | "${compiler}" -O2 -lm -x c - -o "${out}" 2>&1)"
  if [[ ! -x "${out}" ]]; then
    log::error "math: compilation failed"
    local err_line
    while IFS= read -r err_line; do
      log::error "  ${err_line}"
    done <<< "${err}"
    return 2
  fi
  printf '%s\n' "${out}"
  return 0
}

# @private
# @description Evaluate an expression (shared by math::eval / math::calc).
# @description Вычислить выражение (общий код math::eval / math::calc).
# @param $1 Expression / Выражение
# @param $2 Output format, default "%.15g" / Формат вывода
# @param $@ Variable definitions "name=value" / Определения переменных
# @stdout the result / результат
# @return 0 ok, nonzero on failure
__math::run() {
  local -r expr="${1:?expression required}"
  local -r fmt="${2:-%.15g}"
  shift 2

  # Переменные → объявления double / Variables → double declarations
  local var_decls="" pair name value
  for pair in "$@"; do
    name="${pair%%=*}"
    value="${pair#*=}"
    [[ "${name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
      log::error "math: invalid variable name: ${name}"
      return 1
    }
    var_decls+="double ${name} = ${value};
"
  done

  local binary
  binary="$(__math::build "${var_decls}" "${expr}" "${fmt}")" || return $?
  "${binary}"
  return $?
}

# @description Evaluate an expression from stdin (heredoc = triple quotes).
# @description Вычислить выражение из stdin (heredoc = тройные кавычки).
# @param $1 [optional] --format FMT, default "%.15g" / формат вывода
# @param $@ [optional] Variable definitions "name=value"
#        Определения переменных "name=value"
# @stdin the expression / выражение
# @stdout the result / результат
# @return 0 ok, nonzero on failure
# @example
#   math::eval <<'EOF'
#   pow(2, 10) + sqrt(144) * sin(PI / 6)
#   EOF
#   math::eval x=3 y=4 <<'EOF'
#   hypot(x, y)
#   EOF
math::eval() {
  local fmt="%.15g"
  local -a vars=()
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      --format)
        shift
        fmt="${1:?--format requires a value}"
        shift ;;
      *)
        vars+=("${1}")
        shift ;;
    esac
  done

  local expr=""
  IFS= read -r -d '' expr || :
  expr="${expr%$'\n'}"
  if is::empty "${expr}"; then
    log::warn "math::eval: empty expression"
    return 1
  fi

  __math::run "${expr}" "${fmt}" "${vars[@]}"
}

# @description Evaluate a one-shot expression from an argument.
# @description Вычислить разовое выражение из аргумента.
# @param $1 Expression / Выражение
# @param $2 [optional] --format FMT / формат вывода
# @param $@ [optional] Variable definitions / Определения переменных
# @stdout the result / результат
# @return 0 ok, nonzero on failure
# @example
#   math::calc "2 + 3 * 4"         # 14
#   math::calc "sin(x)" x=1.57
math::calc() {
  local -r expr="${1-}"
  if is::empty "${expr}"; then
    log::warn "math::calc: expression required"
    return 1
  fi
  shift

  local fmt="%.15g"
  local -a vars=()
  while [[ $# -gt 0 ]]; do
    case "${1:-}" in
      --format)
        shift
        fmt="${1:?--format requires a value}"
        shift ;;
      *)
        vars+=("${1}")
        shift ;;
    esac
  done

  __math::run "${expr}" "${fmt}" "${vars[@]}"
}