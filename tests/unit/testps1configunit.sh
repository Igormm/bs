#!/usr/bin/env bs
# tests/unit/test_ps1_config_unit.sh — Unit tests for PS1 configuration module
# tests/unit/test_ps1_config_unit.sh — Модульные тесты для модуля конфигурации PS1
#
# Этот файл содержит unit тесты для модуля ps1config.
# This file contains unit tests for the ps1config module.

set -euo pipefail

# Подключаем тестовый фреймворк
source "../testframework.sh"

# Подключаем тестируемый модуль
source "../../../boot.sh"
bs::init

# Главная функция тестов
main() {
    print_header "PS1 Configuration Unit Tests"
    print_header "Модульные тесты конфигурации PS1"
    
    testframework::init
    
    # Тест 1: Инициализация модуля
    testframework::section "Module Initialization / Инициализация модуля"
    load "lib/ui/ps1config"
    testframework::assert_true "${PS1_CONFIG_INITIALIZED:-}" "Module initialized"
    testframework::assert_equal "1.0.0" "$PS1_CONFIG_VERSION" "Version correct"
    
    # Тест 2: Темы
    testframework::section "Themes / Темы"
    
    # Проверяем все темы
    local themes=("default" "powerline" "minimal" "time" "rainbow")
    for theme in "${themes[@]}"; do
        ps1config::set_theme "$theme"
        testframework::assert_equal "$theme" "$(ps1config::get_current_theme)" "Theme $theme set correctly"
    done
    
    # Тест 3: Git информация
    testframework::section "Git Information / Информация о Git"
    
    # Создаем временный git репозиторий
    local temp_dir
    temp_dir=$(mktemp -d)
    pushd "$temp_dir" >/dev/null 2>&1
    
    git init >/dev/null 2>&1 || {
        log::warn "Git not available, skipping git tests" 2>/dev/null || true
        popd >/dev/null 2>&1
        rm -rf "$temp_dir"
    }
    
    if [[ -d .git ]]; then
        # Проверяем git info
        local git_info
        git_info=$(ps1config::git_info)
        testframework::assert_true "${#git_info} -gt 0" "Git info returned"
        
        # Создаем файл и коммитим
        echo "test" > test.txt
        git add test.txt >/dev/null 2>&1
        git commit -m "Test commit" >/dev/null 2>&1
        
        git_info=$(ps1config::git_info)
        testframework::assert_true "${#git_info} -gt 0" "Git info with commit"
    fi
    
    popd >/dev/null 2>&1
    rm -rf "$temp_dir"
    
    # Тест 4: SSH обнаружение
    testframework::section "SSH Detection / Обнаружение SSH"
    
    # Сохраняем исходное значение
    local original_ssh_client="${SSH_CLIENT:-}"
    
    # Тестируем без SSH
    unset SSH_CLIENT 2>/dev/null || true
    ps1config::detect_ssh
    testframework::assert_equal "" "$PS1_CONFIG_SSH_INFO" "No SSH detected"
    
    # Тестируем с SSH
    export SSH_CLIENT="192.168.1.100 12345 22"
    ps1config::detect_ssh
    testframework::assert_true "${#PS1_CONFIG_SSH_INFO} -gt 0" "SSH detected"
    
    # Восстанавливаем исходное значение
    if [[ -n "$original_ssh_client" ]]; then
        export SSH_CLIENT="$original_ssh_client"
    else
        unset SSH_CLIENT
    fi
    
    # Тест 5: Виртуальное окружение
    testframework::section "Virtual Environment / Виртуальное окружение"
    
    # Сохраняем исходные значения
    local original_venv="${VIRTUAL_ENV:-}"
    local original_conda="${CONDA_DEFAULT_ENV:-}"
    
    # Без виртуального окружения
    unset VIRTUAL_ENV 2>/dev/null || true
    unset CONDA_DEFAULT_ENV 2>/dev/null || true
    ps1config::detect_virtualenv
    testframework::assert_equal "" "$PS1_CONFIG_VIRTUALENV_INFO" "No venv detected"
    
    # С VIRTUAL_ENV
    export VIRTUAL_ENV="/home/user/venv"
    ps1config::detect_virtualenv
    testframework::assert_true "${#PS1_CONFIG_VIRTUALENV_INFO} -gt 0" "Venv detected"
    testframework::assert_true "\$PS1_CONFIG_VIRTUALENV_INFO =~ venv" "Correct venv name"
    
    # С CONDA
    unset VIRTUAL_ENV
    export CONDA_DEFAULT_ENV="base"
    ps1config::detect_virtualenv
    testframework::assert_true "${#PS1_CONFIG_VIRTUALENV_INFO} -gt 0" "Conda detected"
    
    # Восстанавливаем исходные значения
    if [[ -n "$original_venv" ]]; then
        export VIRTUAL_ENV="$original_venv"
    else
        unset VIRTUAL_ENV
    fi
    
    if [[ -n "$original_conda" ]]; then
        export CONDA_DEFAULT_ENV="$original_conda"
    else
        unset CONDA_DEFAULT_ENV
    fi
    
    # Тест 6: Настройка времени
    testframework::section "Time Configuration / Настройка времени"
    
    ps1config::set_time_format "%Y-%m-%d"
    testframework::assert_equal "%Y-%m-%d" "$PS1_CONFIG_TIME_FORMAT" "Time format set"
    
    ps1config::set_time_format "%H:%M"
    testframework::assert_equal "%H:%M" "$PS1_CONFIG_TIME_FORMAT" "Time format changed"
    
    # Тест 7: Сброс
    testframework::section "Reset / Сброс"
    
    ps1config::reset
    testframework::assert_equal "default" "$(ps1config::get_current_theme)" "Reset to default"
    
    # Вывод сводки
    testframework::summary
}

# Запуск тестов
main "$@"
