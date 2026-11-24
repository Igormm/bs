#!/usr/bin/env bs
# shellcheck shell=bash
# tests/runalltests.sh — Comprehensive test runner for BS framework
# tests/runalltests.sh — Комплексный запуск всех тестов фреймворка BS
#
# Этот скрипт запускает все тесты фреймворка и выводит подробный отчет.
# This script runs all framework tests and outputs a detailed report.
#
# Usage / Использование:
#   bash tests/runalltests.sh                    # последовательно / serial
#   bash tests/runalltests.sh --jobs 8           # параллельно / parallel
#   BS_TEST_JOBS=8 bash tests/runalltests.sh      # через окружение / via env
#   bash tests/runalltests.sh --with-root        # + деструктивные тесты (только под root)

set -euo pipefail

# Каталог скрипта: прогон работает из любого текущего каталога
# Script directory: the run works from any current directory
# shell-gate: исполняемый раннер вне bs; $0 — единственный источник пути / a runner executed outside bs; $0 is the only source of its path
readonly RUNNER_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${RUNNER_DIR}"
export RUNNER_DIR

# Общий фреймворк: print_header, цвета и гейт NO_COLOR / TERM=dumb / не-tty
# Shared framework: print_header, colors and the NO_COLOR / TERM=dumb / non-tty gate
source "${RUNNER_DIR}/testframework.sh"

# Счетчики тестов
declare -i total_tests=0
declare -i passed_tests=0
declare -i failed_tests=0
# Имена упавших тестов — для сводки / Names of failed tests, for the summary
declare -a failed_names=()
declare -i skipped_tests=0

# Пропущенные проверки внутри файлов (testframework::skip) собираются сюда для итога
# Checks skipped inside the files (testframework::skip) are collected here for the summary
BS_TEST_SKIP_LOG="$(mktemp)"
export BS_TEST_SKIP_LOG
RESULT_DIR=""
QUEUE_FILE=""
cleanup() {
    rm -f "${BS_TEST_SKIP_LOG}"
    [[ -z "${QUEUE_FILE}" ]] || rm -f "${QUEUE_FILE}"
    [[ -z "${RESULT_DIR}" ]] || rm -rf "${RESULT_DIR}"
}
trap cleanup EXIT

# Разбор аргументов
with_root=0
TEST_JOBS="${BS_TEST_JOBS:-1}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-root) with_root=1; shift ;;
    --jobs)
      [[ $# -ge 2 ]] || { echo "--jobs requires a number / --jobs требует число" >&2; exit 2; }
      TEST_JOBS="$2"; shift 2 ;;
    --jobs=*) TEST_JOBS="${1#--jobs=}"; shift ;;
    -h|--help)
      echo "Usage: bash tests/runalltests.sh [--with-root] [--jobs N]"
      echo "  --with-root  Также запустить root-требующие/деструктивные тесты (нужен root)"
      echo "               Also run root-requiring/destructive tests (requires root)"
      echo "  --jobs N     Параллельных тестов (default 1; env BS_TEST_JOBS)"
      echo "               Parallel tests (default 1; env BS_TEST_JOBS)"
      exit 0 ;;
    *)
      echo "Unknown option: ${1}" >&2
      exit 2 ;;
  esac
done
if [[ ! "${TEST_JOBS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid --jobs value: ${TEST_JOBS} (expected positive integer / ожидается положительное целое)" >&2
  exit 2
fi

# Деструктивные/root-требующие тесты (только с --with-root и EUID=0):
# Destructive/root-requiring tests (only with --with-root and EUID=0):
#  - integration/testwireguard.sh — пишет в /etc/wireguard, /var/backups, поднимает wg-интерфейсы (root)
#  - audit/testsystemaudit.sh — подменяет /etc/ssh/sshd_config и /etc/security/pwquality.conf (root)
declare -a ROOT_TESTS=(
  "integration/testwireguard.sh"
  "audit/testsystemaudit.sh"
)

is_root_test() {
  local file="$1"
  local root_test
  for root_test in "${ROOT_TESTS[@]}"; do
    [[ "${file}" == "${root_test}" ]] && return 0
  done
  return 1
}

# Очередь тестов: метка, скрипт, причина пропуска (пусто = запускать).
# Test queue: label, script, skip reason (empty = run).
declare -a TEST_LABELS=()
declare -a TEST_SCRIPTS=()
declare -a TEST_SKIPS=()

queue_skip() {
  TEST_LABELS+=("$1")
  TEST_SCRIPTS+=("$2")
  TEST_SKIPS+=("$3")
}

queue_run() {
  TEST_LABELS+=("$1")
  TEST_SCRIPTS+=("$2")
  TEST_SKIPS+=("")
}

# Запуск тестов каталога
# @description Run all tests from a directory (skips root tests unless allowed)
# @param $1 Directory / Каталог
# @param $2 Label / Метка
run_test_dir() {
  local dir="$1"
  local label="$2"

  [[ -d "${dir}" ]] || return 0

  local test_file test_name
  for test_file in "${dir}"/*.sh; do
    [[ -f "${test_file}" ]] || continue
    test_name=$(basename "${test_file}" .sh)
    if is_root_test "${test_file}"; then
      if [[ "${with_root}" -eq 1 ]] && [[ "${EUID}" -eq 0 ]]; then
        queue_run "${label}: ${test_name}" "${test_file}"
      elif [[ "${with_root}" -eq 1 ]]; then
        queue_skip "${label}: ${test_name}" "${test_file}" "requires root / требуется root (EUID != 0)"
      else
        queue_skip "${label}: ${test_name}" "${test_file}" "destructive/root test, use --with-root / деструктивный тест, нужен --with-root"
      fi
    else
      queue_run "${label}: ${test_name}" "${test_file}"
    fi
  done
}

print_skip() {
  local test_name="$1" reason="$2"
  ((++skipped_tests))
  echo -e "${YELLOW}▶ Skipping test:${NC} $test_name"
  echo -e "  ${YELLOW}Reason / Причина:${NC} $reason"
  echo
}

# Последовательный запуск с живым выводом.
# Serial run with live output.
run_serial() {
  local i test_name test_script reason
  for (( i=0; i<${#TEST_LABELS[@]}; i++ )); do
    test_name="${TEST_LABELS[$i]}"
    test_script="${TEST_SCRIPTS[$i]}"
    reason="${TEST_SKIPS[$i]}"
    ((++total_tests))
    if [[ -n "${reason}" ]]; then
      print_skip "${test_name}" "${reason}"
      continue
    fi
    echo -e "${YELLOW}▶ Running test:${NC} $test_name"
    echo -e "${BLUE}────────────────────────${NC}"
    if env -u BS_ROOT -u BS_INITIALIZED bash "${RUNNER_DIR}/../bs" run "${test_script}"; then
      echo -e "${GREEN}✓ $test_name: PASSED${NC}"
      ((++passed_tests))
    else
      echo -e "${RED}✗ $test_name: FAILED${NC}"
      ((++failed_tests))
      failed_names+=("${test_name}")
    fi
    echo
  done
}

# Параллельный запуск: каждый воркер пишет вывод/rc/skip-log в свой файл,
# родитель собирает итог в исходном порядке. Это исключает гонки счётчиков
# и общего BS_TEST_SKIP_LOG.
# Parallel run: each worker writes output/rc/skip-log to its own files; the
# parent aggregates in the original order. This avoids counter and shared
# BS_TEST_SKIP_LOG races.
run_parallel() {
  RESULT_DIR="$(mktemp -d)"
  QUEUE_FILE="$(mktemp)"
  export RESULT_DIR

  local i test_name test_script reason runnable=0
  for (( i=0; i<${#TEST_LABELS[@]}; i++ )); do
    reason="${TEST_SKIPS[$i]}"
    [[ -n "${reason}" ]] && continue
    printf '%s\0' "$i" "${TEST_LABELS[$i]}" "${TEST_SCRIPTS[$i]}" >> "${QUEUE_FILE}"
    runnable=$(( runnable + 1 ))
  done

  echo -e "${BLUE}Running ${runnable} tests on ${TEST_JOBS} parallel jobs / Запуск ${runnable} тестов в ${TEST_JOBS} потоков${NC}"
  echo

  if (( runnable > 0 )); then
    xargs -0 -n3 -P "${TEST_JOBS}" bash -c '
      idx="$1"; label="$2"; script="$3"
      skip="$(mktemp "${RESULT_DIR}/skip.XXXXXX")"
      if BS_TEST_SKIP_LOG="${skip}" env -u BS_ROOT -u BS_INITIALIZED \
          bash "${RUNNER_DIR}/../bs" run "${script}" \
          > "${RESULT_DIR}/${idx}.out" 2>&1; then
        rc=0
      else
        rc=$?
      fi
      printf "%s\n" "${rc}" > "${RESULT_DIR}/${idx}.rc"
      cat "${skip}" > "${RESULT_DIR}/${idx}.skip"
      rm -f "${skip}"
    ' _ < "${QUEUE_FILE}"
  fi
  rm -f "${QUEUE_FILE}"; QUEUE_FILE=""

  local rc line
  for (( i=0; i<${#TEST_LABELS[@]}; i++ )); do
    test_name="${TEST_LABELS[$i]}"
    test_script="${TEST_SCRIPTS[$i]}"
    reason="${TEST_SKIPS[$i]}"
    ((++total_tests))
    if [[ -n "${reason}" ]]; then
      print_skip "${test_name}" "${reason}"
      continue
    fi
    echo -e "${YELLOW}▶ Running test:${NC} $test_name"
    echo -e "${BLUE}────────────────────────${NC}"
    cat "${RESULT_DIR}/${i}.out"
    rc="$(cat "${RESULT_DIR}/${i}.rc")"
    if [[ "${rc}" -eq 0 ]]; then
      echo -e "${GREEN}✓ $test_name: PASSED${NC}"
      ((++passed_tests))
    else
      echo -e "${RED}✗ $test_name: FAILED${NC}"
      ((++failed_tests))
      failed_names+=("${test_name}")
    fi
    if [[ -s "${RESULT_DIR}/${i}.skip" ]]; then
      while IFS= read -r line; do
        printf '%s\n' "${line}" >> "${BS_TEST_SKIP_LOG}"
      done < "${RESULT_DIR}/${i}.skip"
    fi
    echo
  done
  rm -rf "${RESULT_DIR}"; RESULT_DIR=""
}

# Основная функция тестирования
main() {
  print_header "BS Framework Comprehensive Test Suite / Комплексный набор тестов фреймворка BS"

  echo -e "${YELLOW}Starting test execution...${NC}"
  echo -e "${YELLOW}Запуск выполнения тестов...${NC}"
  echo

  run_test_dir "unit" "Unit Tests / Модульные тесты"
  run_test_dir "integration" "Integration Tests / Интеграционные тесты"
  run_test_dir "data" "Data Tests / Тесты данных"
  run_test_dir "frameworks" "Frameworks Tests / Тесты фреймворков"
  run_test_dir "network" "Network Tests / Сетевые тесты"
  run_test_dir "status" "Status Tests / Тесты статуса"
  run_test_dir "audit" "Audit Tests / Тесты аудита"
  run_test_dir "demos" "Demo Tests / Демонстрационные тесты"

  if (( TEST_JOBS > 1 )); then
    run_parallel
  else
    run_serial
  fi

  # Сводка результатов
  print_header "TEST SUMMARY / СВОДКА ТЕСТОВ"

  echo -e "${BLUE}Tests run / Тестов запущено:${NC} $total_tests"
  echo -e "${GREEN}Passed / Пройдено:${NC} $passed_tests"
  echo -e "${RED}Failed / Провалено:${NC} $failed_tests"
  echo -e "${YELLOW}Skipped / Пропущено:${NC} $skipped_tests"
  local -i skipped_checks
  skipped_checks="$(wc -l < "${BS_TEST_SKIP_LOG}")"
  if [[ $skipped_checks -gt 0 ]]; then
    echo -e "${YELLOW}Skipped checks inside tests / Пропущено проверок внутри тестов:${NC} $skipped_checks"
    local line
    while IFS= read -r line; do
      echo -e "  ${YELLOW}⊘${NC} ${line}"
    done < "${BS_TEST_SKIP_LOG}"
  fi
  echo
  if (( ${#failed_names[@]} > 0 )); then
    # Длинный лог CI обрезается: список упавших — рядом с итогом
    # A long CI log gets cut: the list of failures sits next to the verdict
    echo -e "${RED}Failed tests / Упавшие тесты:${NC}"
    printf '  ✗ %s\n' "${failed_names[@]}"
    echo
  fi

  if [[ $failed_tests -eq 0 ]]; then
    echo -e "${GREEN}🎉 All tests passed!${NC}"
    echo -e "${GREEN}🎉 Все тесты пройдены!${NC}"
    if [[ $skipped_tests -gt 0 ]]; then
      echo -e "${YELLOW}Note: ${skipped_tests} test(s) skipped (see above) / пропущено тестов: ${skipped_tests}${NC}"
    fi
    echo -e "${GREEN}BS framework is working correctly!${NC}"
    echo -e "${GREEN}Фреймворк BS работает корректно!${NC}"
    exit 0
  else
    echo -e "${RED}❌ Some tests failed!${NC}"
    echo -e "${RED}❌ Некоторые тесты провалились!${NC}"
    echo -e "${YELLOW}Please check the output above for details.${NC}"
    echo -e "${YELLOW}Пожалуйста, проверьте вывод выше для деталей.${NC}"
    exit 1
  fi
}

# Запуск основной функции
main "$@"
