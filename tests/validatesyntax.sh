#!/usr/bin/env bs
# tests/validatesyntax.sh — Bash syntax validation for BS framework
# tests/validatesyntax.sh — Проверка синтаксиса bash для фреймворка BS
#
# Этот скрипт проверяет синтаксис всех bash-файлов в проекте.
# This script validates bash syntax for all files in the project.

set -euo pipefail

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
# @return 0 if syntax is valid, 1 if invalid
validate_file() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        echo -e "${YELLOW}⚠ File not found / Файл не найден:${NC} $file"
        return 1
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
    
    # Список файлов для проверки (относительно корня проекта)
    local files=(
        # Core entry points / Основные точки входа
        "BS"
        "boot.sh"
        "main.sh"
        "api.sh"
        
        # Bootstrap / Инициализация
        "bootstrap/init.sh"
        "bootstrap/loader.sh"
        "bootstrap/install.sh"
        
        # Core modules / Ядро
        "core/const.sh"
        "core/logger.sh"
        "core/errorhandler.sh"
        "core/version.sh"
        
        # System modules / Системные модули
        "lib/system/utils.sh"
        "lib/system/distro.sh"
        "lib/system/distrologic.sh"
        "lib/system/packages.sh"
        "lib/system/services.sh"
        "lib/system/network.sh"
        "lib/system/users.sh"
        "lib/system/permissions.sh"
        "lib/system/processes.sh"
        "lib/system/info.sh"
        "lib/system/logging.sh"
        "lib/system/security.sh"
        "lib/system/safety.sh"
        "lib/system/time.sh"
        "lib/system/locale.sh"
        "lib/system/keyboard.sh"
        "lib/system/devices.sh"
        "lib/system/display.sh"
        "lib/system/routing.sh"
        
        # Integration modules / Модули интеграции
        "lib/integration/telegramintegration.sh"
        "lib/integration/bashitintegration.sh"
        "lib/integration/desktopintegration.sh"
        
        # UI modules / Модули интерфейса
        "lib/ui/presentation.sh"
        "lib/ui/displaysettings.sh"
        "lib/ui/interactiveui.sh"
        "lib/ui/bosa_theme.sh"
        
        # Data modules / Модули данных
        "lib/data/algorithms.sh"
        "lib/data/datapresentation.sh"
        "lib/data/monads.sh"
        
        # Extra modules / Дополнительные модули
        "extras/docker.sh"
        "extras/git.sh"
        
        # Test files / Тестовые файлы
        "tests/runalltests.sh"
        "tests/validatesyntax.sh"
        "tests/testframework.sh"
        "tests/run_comprehensive_test.sh"
    )
    
    # Проверка каждого файла
    for file in "${files[@]}"; do
        ((total_files++))
        
        if validate_file "$file"; then
            ((valid_files++))
        else
            if [[ -f "$file" ]]; then
                ((invalid_files++))
            else
                ((missing_files++))
            fi
        fi
        
        echo
    done
    
    # Сводка
    print_header "VALIDATION SUMMARY / СВОДКА ПРОВЕРКИ"
    
    echo -e "${BLUE}Total files checked / Всего файлов проверено:${NC} $total_files"
    echo -e "${GREEN}Valid files / Файлов с корректным синтаксисом:${NC} $valid_files"
    echo -e "${RED}Invalid files / Файлов с ошибками:${NC} $invalid_files"
    echo -e "${YELLOW}Missing files / Отсутствующих файлов:${NC} $missing_files"
    echo
    
    # Проверка всех bash файлов в lib/system/
    echo -e "${BLUE}Checking additional system modules...${NC}"
    echo -e "${BLUE}Проверка дополнительных системных модулей...${NC}"
    
    if [[ -d "lib/system" ]]; then
        while IFS= read -r -d '' file; do
            if [[ "$file" != *.md ]]; then  # Skip markdown files
                relative_path="${file#./}"
                if [[ ! " ${files[@]} " =~ " ${relative_path} " ]]; then
                    ((total_files++))
                    if validate_file "$relative_path"; then
                        ((valid_files++))
                    else
                        ((invalid_files++))
                    fi
                    echo
                fi
            fi
        done < <(find lib/system -name "*.sh" -print0 2>/dev/null)
    fi
    
    # Финальная сводка
    echo
    print_header "FINAL SUMMARY / ФИНАЛЬНАЯ СВОДКА"
    
    if [[ $invalid_files -eq 0 ]]; then
        echo -e "${GREEN}🎉 All files have valid syntax!${NC}"
        echo -e "${GREEN}🎉 Все файлы имеют корректный синтаксис!${NC}"
        echo -e "${GREEN}BS framework syntax validation passed!${NC}"
        echo -e "${GREEN}Проверка синтаксиса фреймворка BS пройдена!${NC}"
        exit 0
    else
        echo -e "${RED}❌ Some files have syntax errors!${NC}"
        echo -e "${RED}❌ Некоторые файлы содержат ошибки синтаксиса!${NC}"
        echo -e "${YELLOW}Please review the output above and fix the errors.${NC}"
        echo -e "${YELLOW}Пожалуйста, просмотрите вывод выше и исправьте ошибки.${NC}"
        exit 1
    fi
}

# Запуск основной функции
main "$@"
