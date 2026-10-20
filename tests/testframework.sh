#!/usr/bin/env bs
# shellcheck shell=bash
# tests/testframework.sh — Basic test framework for BS
# tests/testframework.sh — Базовый тестовый фреймворк для BS
#
# Этот файл предоставляет базовые функции для написания тестов.
# This file provides basic functions for writing tests.

set -euo pipefail

# Цветовой гейт: NO_COLOR, TERM=dumb или не-tty отключают ANSI-коды.
# Цветные переменные остаются доступны под старыми именами (RED, GREEN и т.д.)
# и превращаются в пустые строки при отключённом цвете.
# Color gate: NO_COLOR, TERM=dumb or a non-tty disable ANSI codes.
# The color variables keep their old names (RED, GREEN, etc.) and become
# empty strings when color is disabled.
if [[ -n "${NO_COLOR:-}" ]] || [[ "${TERM:-}" == "dumb" ]] || [[ ! -t 1 ]]; then
  readonly TF_COLOR=0
else
  readonly TF_COLOR=1
fi

# Локаль: тесты проверяют ширину рамок и символы (┌ ▸ █, кириллица), а ${#s} и
# ${s:0:1} в bash считают символы только в UTF-8-локали. В POSIX/C (ssh без LANG,
# контейнеры, CI) переключаем LC_CTYPE на UTF-8-локаль, если она есть, и пишем об
# этом одну строку; остальные категории (сортировка, сообщения) не трогаем. Нет
# UTF-8-локали — предупреждение, и такие тесты падают честно.
# Locale: tests check frame widths and glyphs (┌ ▸ █, Cyrillic), and bash's ${#s}
# and ${s:0:1} count characters only under a UTF-8 locale. Under POSIX/C (ssh
# without LANG, containers, CI) LC_CTYPE is switched to a UTF-8 locale when one
# exists, with a one-line note; the other categories (collation, messages) stay
# as they are. No UTF-8 locale means a warning, and such tests fail honestly.
testframework::__is_utf8() {
  local s='ж'
  (( ${#s} == 1 ))
}

if ! testframework::__is_utf8; then
  __tf_was="${LC_ALL:-${LC_CTYPE:-${LANG:-POSIX}}}"
  __tf_utf8=""
  for __tf_loc in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
    if ( unset LC_ALL; export LC_CTYPE="${__tf_loc}"; testframework::__is_utf8 ) 2>/dev/null; then
      __tf_utf8="${__tf_loc}"
      break
    fi
  done
  if [[ -n "${__tf_utf8}" ]]; then
    # LC_ALL перекрывает LC_CTYPE: его значение уходит в LANG / LC_ALL overrides LC_CTYPE: its value moves to LANG
    if [[ -n "${LC_ALL:-}" ]]; then
      export LANG="${LC_ALL}"
      unset LC_ALL
    fi
    export LC_CTYPE="${__tf_utf8}"
    printf 'note: LC_CTYPE=%s for the tests (was %s) / примечание: LC_CTYPE=%s для тестов (было %s)\n' \
      "${__tf_utf8}" "${__tf_was}" "${__tf_utf8}" "${__tf_was}" >&2
  else
    printf 'warning: no UTF-8 locale (was %s); glyph and frame-width tests will fail / предупреждение: нет UTF-8-локали (было %s); тесты символов и ширины рамок упадут\n' \
      "${__tf_was}" "${__tf_was}" >&2
  fi
  unset __tf_was __tf_utf8 __tf_loc
fi

# git: тесты коммитят во временные репозитории; подпись коммитов из личного
# ~/.gitconfig (gpg/ssh-ключ, внешний подписчик) там не нужна и роняет коммит.
# Отключаем только её, через переменные окружения git (git ≥ 2.31), прочие
# настройки (safe.directory и т.д.) остаются.
# git: tests commit into temporary repositories; commit signing from a personal
# ~/.gitconfig (a gpg/ssh key, an external signer) is not needed there and breaks
# the commit. Only signing is turned off, through git's environment config
# (git >= 2.31); every other setting (safe.directory and so on) stays. Pairs
# already in GIT_CONFIG_* are kept: ours are appended once.
# Уже заданные пары GIT_CONFIG_* сохраняются: наши дописываются один раз.
if [[ -z "${BS_TEST_GIT_NOSIGN:-}" ]]; then
  __tf_n="${GIT_CONFIG_COUNT:-0}"
  export "GIT_CONFIG_KEY_${__tf_n}=commit.gpgsign" "GIT_CONFIG_VALUE_${__tf_n}=false"
  export "GIT_CONFIG_KEY_$((__tf_n + 1))=tag.gpgsign" "GIT_CONFIG_VALUE_$((__tf_n + 1))=false"
  export GIT_CONFIG_COUNT=$((__tf_n + 2)) BS_TEST_GIT_NOSIGN=1
  unset __tf_n
fi

# Интерпретатор для запуска CLI в тестах: тот же bash, что исполняет BS (не первый в PATH)
# The interpreter that runs the CLI in tests: the same bash that runs BS (not the first in PATH)
if declare -F bs::shell::host >/dev/null 2>&1; then
  TEST_BASH="${TEST_BASH:-$(bs::shell::host)}"
else
  TEST_BASH="${TEST_BASH:-bash}"  # раннер вне bs / a runner outside bs
fi
export TEST_BASH

# Цвета для вывода / Output colors
if [[ "${TF_COLOR}" -eq 1 ]]; then
  readonly RED='\033[0;31m'
  readonly GREEN='\033[0;32m'
  readonly YELLOW='\033[1;33m'
  readonly BLUE='\033[0;34m'
  readonly NC='\033[0m' # No Color
else
  readonly RED=''
  readonly GREEN=''
  readonly YELLOW=''
  readonly BLUE=''
  readonly NC=''
fi

# Счетчики тестов
declare -g tests_run=0
declare -g tests_passed=0
declare -g tests_failed=0
declare -g tests_skipped=0

# Заголовок
# @description Print a bilingual box-drawing header banner / Рамка-заголовок на двух языках
# @param $1 Header text / Текст заголовка
print_header() {
  local text="$1"
  local inner=" ${text} "
  local line
  printf -v line '%*s' "${#inner}" ''
  line="${line// /─}"
  echo -e "${BLUE}╭${line}╮${NC}"
  echo -e "${BLUE}│${inner}│${NC}"
  echo -e "${BLUE}╰${line}╯${NC}"
  echo
}

# Функция инициализации тестов
# @description Initialize test framework
# @example testframework::init
testframework::init() {
  echo -e "${BLUE}Initializing test framework / Инициализация тестового фреймворка${NC}"
  tests_run=0
  tests_passed=0
  tests_failed=0
  tests_skipped=0
}

# Функция проверки условия
# @description Assert that condition is true
# @param $1 Condition to check: "true"/"false" or a [[ ... ]] expression / Условие для проверки
# @param $2 Test name / Название теста
# @example testframework::assert_true "$result" "Test result"
testframework::assert_true() {
  local condition="$1"
  local test_name="${2:-Unknown test}"

  ((++tests_run))

  # "true"/"false" обрабатываем явно, остальное — как выражение [[ ... ]]
  # Handle "true"/"false" explicitly, anything else as a [[ ... ]] expression
  local result=1
  if [[ "$condition" == "true" ]]; then
    result=0
  elif [[ "$condition" == "false" ]]; then
    result=1
  elif eval "[[ ${condition} ]]" 2>/dev/null; then
    result=0
  fi

  if [[ $result -eq 0 ]]; then
    echo -e "  ${GREEN}✓ $test_name: PASSED${NC}"
    ((++tests_passed))
    return 0
  else
    # Выводим вычисленное значение и само выражение
    # Print the evaluated result and the expression
    local evaluated="false"
    [[ $result -eq 0 ]] && evaluated="true"
    echo -e "  ${RED}✗ $test_name: FAILED${NC}"
    echo -e "    ${RED}Expected true, got: ${evaluated} — ${condition}${NC}"
    ((++tests_failed))
    return 1
  fi
}

# Функция проверки, что команда завершается с ошибкой
# @description Assert that command/condition fails
# @param $1 Command to run (or "false"/"true") / Команда для выполнения
# @param $2 Test name / Название теста
# @example testframework::assert_false "platformcheck::is_macos" "Not macOS"
testframework::assert_false() {
  local condition="$1"
  local test_name="${2:-Unknown test}"

  ((++tests_run))

  local result=1
  if [[ "$condition" == "false" ]]; then
    result=0
  elif [[ "$condition" == "true" ]]; then
    result=1
  elif ! eval "${condition}" >/dev/null 2>&1; then
    result=0
  fi

  if [[ $result -eq 0 ]]; then
    echo -e "  ${GREEN}✓ $test_name: PASSED${NC}"
    ((++tests_passed))
    return 0
  else
    echo -e "  ${RED}✗ $test_name: FAILED${NC}"
    echo -e "    ${RED}Expected failure, but succeeded: $condition${NC}"
    ((++tests_failed))
    return 1
  fi
}

# Функция пропуска проверки
# @description Skip a check that cannot run in this environment (root, a missing tool).
#   Not a pass: the line is printed, counted in the summary and, when the runner sets
#   BS_TEST_SKIP_LOG, listed in its final report. Never use it to silence a failure.
# @description Пропустить проверку, которую нельзя выполнить в этом окружении (root,
#   нет утилиты). Это не «пройдено»: строка печатается, учитывается в сводке и, если
#   раннер задал BS_TEST_SKIP_LOG, попадает в его итоговый отчёт. Не для заглушки падений.
# @param $1 Test name / Название теста
# @param $2 Reason / Причина
# @example testframework::skip "uninstall refuses a read-only lib" "root ignores file modes"
testframework::skip() {
  local test_name="${1:-Unknown test}"
  local reason="${2:-no reason given}"

  ((++tests_skipped))
  echo -e "  ${YELLOW}⊘ $test_name: SKIPPED — $reason${NC}"
  if [[ -n "${BS_TEST_SKIP_LOG:-}" ]]; then
    printf '%s — %s\n' "${test_name}" "${reason}" >> "${BS_TEST_SKIP_LOG}" || true
  fi
  return 0
}

# @description True when the tests run as root (root ignores file modes) / Тесты идут под root
testframework::is_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]]
}

# Функция проверки равенства
# @description Assert that two values are equal
# @param $1 Expected value / Ожидаемое значение
# @param $2 Actual value / Фактическое значение
# @param $3 Test name / Название теста
# @example testframework::assert_equal "expected" "$result" "Test equality"
testframework::assert_equal() {
  local expected="$1"
  local actual="$2"
  local test_name="${3:-Unknown test}"

  ((++tests_run))

  if [[ "$expected" == "$actual" ]]; then
    echo -e "  ${GREEN}✓ $test_name: PASSED${NC}"
    ((++tests_passed))
    return 0
  else
    echo -e "  ${RED}✗ $test_name: FAILED${NC}"
    echo -e "    ${RED}Expected: '$expected'${NC}"
    echo -e "    ${RED}Got:      '$actual'${NC}"
    ((++tests_failed))
    return 1
  fi
}

# Функция проверки существования файла
# @description Assert that file exists
# @param $1 File path / Путь к файлу
# @param $2 Test name / Название теста
# @example testframework::assert_file_exists "/path/to/file" "File exists"
testframework::assert_file_exists() {
  local file="$1"
  local test_name="${2:-File exists / Файл существует}"

  if [[ -f "$file" ]]; then
    testframework::assert_true "true" "$test_name"
  else
    # Не делегируем в assert_true: нужен путь отсутствующего файла
    # Do not delegate to assert_true: the missing file path is required
    ((++tests_run))
    echo -e "  ${RED}✗ $test_name: FAILED${NC}"
    echo -e "    ${RED}Expected true, got: false — file not found: $file${NC}"
    ((++tests_failed))
    return 1
  fi
}

# Функция проверки команды
# @description Assert that command succeeds
# @param $1 Command to run / Команда для выполнения
# @param $2 Test name / Название теста
# @example testframework::assert_command "ls /tmp" "List tmp directory"
testframework::assert_command() {
  local command="$1"
  local test_name="${2:-Command test}"

  if eval "$command" >/dev/null 2>&1; then
    testframework::assert_true "true" "$test_name"
  else
    testframework::assert_true "false" "$test_name"
  fi
}

# Функция вывода заголовка раздела
# @description Print test section header in the box-drawing banner style
# @param $1 Section name / Название раздела
# @example testframework::section "Testing Logger"
testframework::section() {
  local section_name="$1"
  echo
  print_header "${section_name}"
}

# Функция вывода сводки тестов
# @description Print test summary
# @example testframework::summary
# Оболочки для тестов ярусов: bash zsh dash ash ksh mksh — по одному пути в строке.
# Нет оболочки — строка «skip» в stderr (в отчёт «не проверено»), не молчаливый пропуск.
# ash берётся настоящая; иначе апплет busybox через крошечный лаунчер `ash` (один путь, как у остальных).
# Shells for tier tests: bash zsh dash ash ksh mksh — one path per line. A missing shell prints a
# "skip" line to stderr (it goes to the report as "not verified"), never a silent skip. A real ash is
# preferred; otherwise the busybox applet runs through a tiny launcher named `ash` (one path like the rest).
testframework::posix_shells() {
  local name path dir="${TMPDIR:-/tmp}/bs-test-shells.$$"
  for name in bash zsh dash ash ksh mksh; do
    path="$(command -v "${name}" 2>/dev/null || true)"
    if [[ -z "${path}" && "${name}" == ash ]]; then
      path="$(command -v busybox 2>/dev/null || true)"
      if [[ -n "${path}" ]]; then
        mkdir -p "${dir}"
        printf '#!/bin/sh\nexec %s ash "$@"\n' "${path}" > "${dir}/ash"
        chmod +x "${dir}/ash"
        path="${dir}/ash"
      fi
    fi
    if [[ -n "${path}" ]]; then
      printf '%s\n' "${path}"
    else
      printf 'skip: %s is not installed / не установлен\n' "${name}" >&2
    fi
  done
}

testframework::summary() {
  rm -rf "${TMPDIR:-/tmp}/bs-test-shells.$$" 2>/dev/null || true
  echo
  print_header "TEST SUMMARY / СВОДКА ТЕСТОВ"
  echo -e "${BLUE}Tests run / Тестов запущено:${NC} $tests_run"
  echo -e "${GREEN}Passed / Пройдено:${NC} $tests_passed"
  echo -e "${RED}Failed / Провалено:${NC} $tests_failed"
  if [[ $tests_skipped -gt 0 ]]; then
    echo -e "${YELLOW}Skipped / Пропущено:${NC} $tests_skipped"
  fi
  echo

  if [[ $tests_failed -eq 0 ]]; then
    echo -e "${GREEN}🎉 All tests passed!${NC}"
    echo -e "${GREEN}🎉 Все тесты пройдены!${NC}"
    return 0
  else
    echo -e "${RED}❌ Some tests failed!${NC}"
    echo -e "${RED}❌ Некоторые тесты провалены!${NC}"
    return 1
  fi
}

# Пример использования
if declare -F bs::is_main >/dev/null 2>&1 && bs::is_main; then
  # Этот файл запущен напрямую, демонстрируем использование
  # This file is run directly, demonstrate usage

  # Пути от расположения скрипта, чтобы демо работало из любого каталога
  # Paths relative to the script location so the demo works from any directory
  TESTFRAMEWORK_DIR="$(bs::script_dir)"
  BS_ROOT_DIR="$(cd "${TESTFRAMEWORK_DIR}/.." && pwd)"

  print_header "Test Framework Demo / Демонстрация тестового фреймворка"

  testframework::init

  # Тесты файловой системы
  testframework::section "Filesystem Tests / Тесты файловой системы"
  testframework::assert_file_exists "${BS_ROOT_DIR}/boot.sh" "Boot file exists"
  testframework::assert_file_exists "${BS_ROOT_DIR}/bs" "Main entrypoint exists"
  testframework::assert_file_exists "nonexistent" "Non-existent file test"

  # Тесты команд
  testframework::section "Command Tests / Тесты команд"
  testframework::assert_command "ls -la '${BS_ROOT_DIR}/boot.sh'" "List boot file"
  testframework::assert_command "pwd" "Print working directory"
  testframework::assert_command "false" "Failing command test"

  # Тесты равенства
  testframework::section "Equality Tests / Тесты равенства"
  testframework::assert_equal "test" "test" "String equality"
  testframework::assert_equal "1" "1" "Number equality"
  testframework::assert_equal "expected" "actual" "Failing equality test"

  # Вывод сводки
  testframework::summary
fi