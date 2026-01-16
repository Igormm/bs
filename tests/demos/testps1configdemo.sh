#!/usr/bin/env bs
# tests/demos/test_ps1_config_demo.sh — Demo of PS1 configuration module
# tests/demos/test_ps1_config_demo.sh — Демонстрация модуля конфигурации PS1
#
# Этот скрипт демонстрирует возможности модуля ps1config.
# This script demonstrates the capabilities of the ps1config module.

set -euo pipefail

# Подключаем фреймворк
source "${TEST_SCRIPT_DIR}/../testframework.sh"
source "${BS_PROJECT_ROOT}/boot.sh"

# Initialize BS framework
bs::init

# Test results tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Подключаем модуль
load "lib/ui/ps1config"

# Главная функция демо
main() {
    print_header "PS1 Configuration Module Demo"
    print_header "Демо модуля конфигурации PS1"
    
    echo
    echo -e "${BLUE}1. Базовая информация / Basic information:${NC}"
    echo -e "   Текущая тема: $(ps1config::get_current_theme)"
    echo -e "   Версия модуля: $PS1_CONFIG_VERSION"
    
    echo
    echo -e "${BLUE}2. Доступные темы / Available themes:${NC}"
    ps1config::list_themes
    
    echo
    echo -e "${BLUE}3. Демо тем / Theme demo:${NC}"
    ps1config::demo
    
    echo
    echo -e "${BLUE}4. Пользовательская настройка / Custom configuration:${NC}"
    echo -e "${YELLOW}   Setting minimal theme...${NC}"
    ps1config::set_theme "minimal"
    echo -e "   New PS1: $PS1"
    
    echo
    echo -e "${BLUE}5. Расширенные функции / Advanced features:${NC}"
    echo -e "${YELLOW}   Enabling advanced mode...${NC}"
    ps1config::enable_advanced
    echo -e "   ${GREEN}✓ Advanced features enabled${NC}"
    
    echo
    echo -e "${BLUE}6. Git информация / Git info:${NC}"
    if [[ -d .git ]] || git rev-parse --git-dir >/dev/null 2>&1; then
        echo -e "   Git branch: $(git symbolic-ref --short HEAD 2>/dev/null || echo 'unknown')"
        echo -e "   Git info in PS1: $(ps1config::git_info)"
    else
        echo -e "   Not in git repository"
    fi
    
    echo
    echo -e "${BLUE}7. SSH detection / Обнаружение SSH:${NC}"
    ps1config::detect_ssh
    if [[ -n "$PS1_CONFIG_SSH_INFO" ]]; then
        echo -e "   SSH connection detected: $PS1_CONFIG_SSH_INFO"
    else
        echo -e "   Local connection"
    fi
    
    echo
    echo -e "${BLUE}8. Виртуальное окружение / Virtual environment:${NC}"
    ps1config::detect_virtualenv
    if [[ -n "$PS1_CONFIG_VIRTUALENV_INFO" ]]; then
        echo -e "   Virtual environment: $PS1_CONFIG_VIRTUALENV_INFO"
    else
        echo -e "   No virtual environment detected"
    fi
    
    echo
    echo -e "${GREEN}✓ PS1 configuration demo completed${NC}"
    echo -e "${GREEN}✓ Демо конфигурации PS1 завершено${NC}"
    
    echo
    echo -e "${YELLOW}To apply changes to your current shell:${NC}"
    echo -e "${YELLOW}Чтобы применить изменения к текущей оболочке:${NC}"
    echo -e "  source lib/ui/ps1config.sh"
    echo -e "  ps1config::set_theme powerline"
}

# Запуск демо
main "$@"
