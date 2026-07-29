#!/usr/bin/env bs
# tests/validatesyntax.sh — Bash syntax validation for BS framework
# tests/validatesyntax.sh — Проверка синтаксиса bash для фреймворка BS
#
# Этот скрипт проверяет синтаксис всех bash-файлов в проекте.
# This script validates bash syntax for all files in the project.
#
# Exit codes / Коды выхода:
#   0 — все файлы на месте и синтаксис корректен / all files present and valid
#   1 — есть ошибки синтаксиса или отсутствующие файлы / syntax errors or missing files

set -euo pipefail

# Корень проекта от расположения скрипта: проверка работает из любого каталога
# Project root from the script location: validation works from any directory
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${BS_PROJECT_ROOT}"

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Заголовок
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
}

# Функция проверки синтаксиса
# @description Check syntax of a bash file
# @param $1 File path / Путь к файлу
# @return 0 if syntax is valid, 1 if invalid, 2 if missing
validate_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo -e "${YELLOW}⚠ File not found / Файл не найден:${NC} $file"
        return 2
    fi

    echo -e "${YELLOW}▶ Checking syntax / Проверка синтаксиса:${NC} $file"

    if bash -n "$file" 2>/dev/null; then
        echo -e "  ${GREEN}✓ Syntax is valid / Синтаксис корректен${NC}"
        return 0
    else
        echo -e "  ${RED}✗ Syntax errors / Ошибки синтаксиса${NC}"
        echo -e "${RED}$(bash -n "$file" 2>&1)${NC}"
        return 1
    fi
}

# Основная функция
main() {
    print_header "BS Framework Syntax Validation"
    print_header "Проверка синтаксиса фреймворка BS"

    echo -e "${YELLOW}Validating bash syntax for all project files...${NC}"
    echo -e "${YELLOW}Проверка синтаксиса bash для всех файлов проекта...${NC}"
    echo

    # Счетчики
    local -i total_files=0
    local -i valid_files=0
    local -i invalid_files=0
    local -i missing_files=0

    # Обязательные файлы (относительно корня проекта): отсутствие — ошибка прогона
    # Required files (relative to project root): a missing file fails the run
    local required_files=(
        # Entry points / Точки входа
        "bs"
        "boot.sh"
        "install.sh"

        # Bootstrap / Инициализация
        "bootstrap/init.sh"
        "bootstrap/loader.sh"
    )

    # Все скрипты проекта: core, lib, install, tests
    # (examples/ проверяются отдельно — см. фазу 6 плана чистки)
    # All project scripts: core, lib, install, tests
    # (examples/ are checked separately — see phase 6 of the cleanup plan)
    local all_files=("${required_files[@]}")
    local found_file
    while IFS= read -r found_file; do
        all_files+=("${found_file#./}")
    done < <(find core lib install tests -type f -name "*.sh" 2>/dev/null | sort)

    # Проверка каждого файла
    local file rc
    for file in "${all_files[@]}"; do
        ((++total_files))

        rc=0
        validate_file "$file" || rc=$?
        case "${rc}" in
            0) ((++valid_files)) ;;
            2) ((++missing_files)) ;;
            *) ((++invalid_files)) ;;
        esac
    done

    # Финальная сводка
    echo
    print_header "FINAL SUMMARY / ФИНАЛЬНАЯ СВОДКА"

    echo -e "${BLUE}Total files checked / Всего файлов проверено:${NC} $total_files"
    echo -e "${GREEN}Valid files / Файлов с корректным синтаксисом:${NC} $valid_files"
    echo -e "${RED}Invalid files / Файлов с ошибками:${NC} $invalid_files"
    echo -e "${YELLOW}Missing files / Отсутствующих файлов:${NC} $missing_files"
    echo

    if [[ $invalid_files -eq 0 ]] && [[ $missing_files -eq 0 ]]; then
        echo -e "${GREEN}🎉 All files have valid syntax!${NC}"
        echo -e "${GREEN}🎉 Все файлы имеют корректный синтаксис!${NC}"
        echo -e "${GREEN}BS framework syntax validation passed!${NC}"
        echo -e "${GREEN}Проверка синтаксиса фреймворка BS пройдена!${NC}"
        exit 0
    else
        echo -e "${RED}❌ Some files have syntax errors or are missing!${NC}"
        echo -e "${RED}❌ Некоторые файлы содержат ошибки синтаксиса или отсутствуют!${NC}"
        echo -e "${YELLOW}Please review the output above and fix the errors.${NC}"
        echo -e "${YELLOW}Пожалуйста, просмотрите вывод выше и исправьте ошибки.${NC}"
        exit 1
    fi
}

# Запуск основной функции
main "$@"
