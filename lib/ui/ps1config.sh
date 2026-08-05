#!/usr/bin/env bs
# shellcheck shell=bash
# lib/ui/ps1config.sh — Advanced PS1 configuration module for BS
# lib/ui/ps1config.sh — Модуль расширенной конфигурации PS1 для BS
#
# Этот модуль предоставляет продвинутую настройку командной строки,
# превосходящую функциональность oh-my-zsh.
# This module provides advanced command line configuration,
# surpassing oh-my-zsh functionality.
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/guard.sh"
bs::guard "UI_PS1CONFIG" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

set -euo pipefail

# Глобальные переменные модуля
declare -g PS1_CONFIG_VERSION="1.0.0"
declare -g -A PS1_CONFIG_THEMES
declare -g PS1_CONFIG_CURRENT_THEME="default"
declare -g PS1_CONFIG_GIT_INFO=""
declare -g PS1_CONFIG_SSH_INFO=""
declare -g PS1_CONFIG_VIRTUALENV_INFO=""
declare -g PS1_CONFIG_TIME_FORMAT="%H:%M:%S"

# ==========================================
# Встроенные темы / Built-in themes
# ==========================================

# Тема по умолчанию / Default theme
PS1_CONFIG_THEME_DEFAULT="\[\033[01;32m\]\u\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$(ps1config::git_info) \[\033[01;31m\]\$\[\033[00m\] "

# Тема powerline / Powerline theme
PS1_CONFIG_THEME_POWERLINE="\[\033[38;5;250m\]\[\033[48;5;240m\] \u \[\033[48;5;238m\]\[\033[38;5;250m\]\[\033[48;5;31m\]\[\033[38;5;238m\] \w \[\033[48;5;28m\]\[\033[38;5;31m\]\$(ps1config::git_info) \[\033[0m\]\[\033[38;5;28m\] \$ \[\033[0m\]"

# Тема minimal / Minimal theme
PS1_CONFIG_THEME_MINIMAL="\[\033[01;36m\]\u\[\033[00m\]@\[\033[01;32m\]\h\[\033[00m\]:\[\033[01;34m\]\W\[\033[00m\]\$(ps1config::git_info) \$ "

# Тема с временем / Time theme
PS1_CONFIG_THEME_WITH_TIME="\[\033[90m\]\$(date '+\$(ps1config::time_format)')\[\033[00m\] \[\033[01;32m\]\u\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$(ps1config::git_info) \[\033[01;31m\]\$\[\033[00m\] "

# Тема rainbow / Rainbow theme
PS1_CONFIG_THEME_RAINBOW="\[\033[38;5;196m\]\u\[\033[38;5;214m\]@\[\033[38;5;226m\]\h\[\033[38;5;082m\]:\[\033[38;5;051m\]\w\[\033[38;5;201m\]\$(ps1config::git_info) \[\033[38;5;196m\]\$\[\033[00m\] "

# ==========================================
# Инициализация модуля / Module initialization
# ==========================================

# @description Initialize PS1 configuration module
# @description Инициализировать модуль конфигурации PS1
# @example
#   ps1config::init
ps1config::init() {
    utils::quiet_err log::debug "Initializing PS1 config module" || true
    
    # Устанавливаем тему по умолчанию
    # Set default theme
    ps1config::set_theme "default"
    
    # Инициализируем информацию о SSH
    # Initialize SSH info
    ps1config::detect_ssh
    
    # Инициализируем информацию о виртуальном окружении
    # Initialize virtual environment info
    ps1config::detect_virtualenv
    
    # Настраиваем обновление при каждой команде
    # Set up update on each command
    ps1config::setup_prompt_command
    
    utils::quiet_err log::info "PS1 config module initialized" || true
}

# ==========================================
# Темы / Themes
# ==========================================

# @description Set PS1 theme
# @description Установить тему PS1
# @param $1 Theme name / Название темы
# @example
#   ps1config::set_theme "powerline"
ps1config::set_theme() {
    local theme="${1:-default}"
    
    case "$theme" in
        default)
            PS1="$PS1_CONFIG_THEME_DEFAULT"
            ;;
        powerline)
            PS1="$PS1_CONFIG_THEME_POWERLINE"
            ;;
        minimal)
            PS1="$PS1_CONFIG_THEME_MINIMAL"
            ;;
        time)
            PS1="$PS1_CONFIG_THEME_WITH_TIME"
            ;;
        rainbow)
            PS1="$PS1_CONFIG_THEME_RAINBOW"
            ;;
        *)
            utils::quiet_err log::warn "Unknown theme: $theme, using default" || true
            PS1="$PS1_CONFIG_THEME_DEFAULT"
            ;;
    esac
    
    PS1_CONFIG_CURRENT_THEME="$theme"
    utils::quiet_err log::info "PS1 theme set to: $theme" || true
}

# @description List available themes
# @description Список доступных тем
# @example
#   ps1config::list_themes
ps1config::list_themes() {
    local themes=("default" "powerline" "minimal" "time" "rainbow")
    
    utils::quiet_err log::info "Available PS1 themes:" || true
    for theme in "${themes[@]}"; do
        if [[ "$theme" == "$PS1_CONFIG_CURRENT_THEME" ]]; then
            echo -e "  ${COLOR_GREEN}● $theme (current)${COLOR_RESET}"
        else
            echo -e "  ○ $theme"
        fi
    done
}

# ==========================================
# Git информация / Git information
# ==========================================

# @description Get git repository information for PS1
# @description Получить информацию о git репозитории для PS1
# @return Git info string or empty / Строка с информацией или пусто
# @example
#   ps1config::git_info
ps1config::git_info() {
    if [[ -d .git ]] || utils::quiet git rev-parse --git-dir; then
        local branch
        branch=$(utils::quiet_err git symbolic-ref --short HEAD || utils::quiet_err git describe --tags --exact-match)
        
        if [[ -n "$branch" ]]; then
            local git_status=""
            
            # Проверяем состояние репозитория
            # Check repository status
            if [[ -n $(utils::quiet_err git status --porcelain) ]]; then
                git_status="*"  # Есть изменения / Has changes
            fi
            
            echo -n " \[\033[38;5;239m\]($branch$git_status)\[\033[00m\]"
        fi
    fi
}

# @description Enable/disable git info in PS1
# @description Включить/выключить git info в PS1
# @param $1 true/false / true/false
# @example
#   ps1config::set_git_info true
ps1config::set_git_info() {
    local enabled="${1:-true}"
    
    if [[ "$enabled" == "true" ]]; then
        PS1_CONFIG_GIT_INFO="\$(ps1config::git_info)"
        utils::quiet_err log::info "Git info enabled in PS1" || true
    else
        PS1_CONFIG_GIT_INFO=""
        utils::quiet_err log::info "Git info disabled in PS1" || true
    fi
}

# ==========================================
# SSH информация / SSH information
# ==========================================

# @description Detect if connected via SSH
# @description Определить подключение через SSH
# @example
#   ps1config::detect_ssh
ps1config::detect_ssh() {
    if [[ -n "${SSH_CLIENT:-}" ]] || [[ -n "${SSH_TTY:-}" ]]; then
        PS1_CONFIG_SSH_INFO="\[\033[38;5;208m\][SSH]\[\033[00m\] "
    else
        PS1_CONFIG_SSH_INFO=""
    fi
}

# ==========================================
# Виртуальное окружение / Virtual environment
# ==========================================

# @description Detect Python virtual environment
# @description Определить виртуальное окружение Python
# @example
#   ps1config::detect_virtualenv
ps1config::detect_virtualenv() {
    if [[ -n "${VIRTUAL_ENV:-}" ]]; then
        local venv_name
        venv_name=$(basename "$VIRTUAL_ENV")
        PS1_CONFIG_VIRTUALENV_INFO="\[\033[38;5;106m\]($venv_name)\[\033[00m\] "
    elif [[ -n "${CONDA_DEFAULT_ENV:-}" ]]; then
        PS1_CONFIG_VIRTUALENV_INFO="\[\033[38;5;106m\]($CONDA_DEFAULT_ENV)\[\033[00m\] "
    else
        PS1_CONFIG_VIRTUALENV_INFO=""
    fi
}

# ==========================================
# Настройка времени / Time configuration
# ==========================================

# @description Set time format for PS1
# @description Установить формат времени для PS1
# @param $1 Time format / Формат времени
# @example
#   ps1config::set_time_format "%Y-%m-%d %H:%M:%S"
ps1config::set_time_format() {
    local format="${1:-%H:%M:%S}"
    PS1_CONFIG_TIME_FORMAT="$format"
    utils::quiet_err log::info "Time format set to: $format" || true
}

# ==========================================
# Динамическое обновление / Dynamic updates
# ==========================================

# @description Setup prompt command for dynamic updates
# @description Настроить команду промпта для динамического обновления
# @example
#   ps1config::setup_prompt_command
ps1config::setup_prompt_command() {
    # Функция для обновления PS1 перед каждой командой
    # Function to update PS1 before each command
    ps1config::update_prompt() {
        # Обновляем git информацию
        # Update git information
        local git_info
        git_info=$(ps1config::git_info)
        
        # Обновляем виртуальное окружение
        # Update virtual environment
        ps1config::detect_virtualenv
        
        # Формируем динамический PS1
        # Build dynamic PS1
        case "$PS1_CONFIG_CURRENT_THEME" in
            default)
                PS1="\[\033[01;32m\]\u\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$git_info \[\033[01;31m\]\$\[\033[00m\] "
                ;;
            time)
                PS1="\[\033[90m\]\$(date '+$PS1_CONFIG_TIME_FORMAT')\[\033[00m\] \[\033[01;32m\]\u\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]$git_info \[\033[01;31m\]\$\[\033[00m\] "
                ;;
            *)
                # Используем текущую тему
                # Use current theme
                ;;
        esac
    }
    
    # Добавляем к существующей PROMPT_COMMAND
    # Add to existing PROMPT_COMMAND
    if [[ -z "${PROMPT_COMMAND:-}" ]]; then
        PROMPT_COMMAND="ps1config::update_prompt"
    elif [[ "${PROMPT_COMMAND}" != *"ps1config::update_prompt"* ]]; then
        PROMPT_COMMAND="$PROMPT_COMMAND; ps1config::update_prompt"
    fi
}

# ==========================================
# Служебные функции / Utility functions
# ==========================================

# @description Get current PS1 theme
# @description Получить текущую тему PS1
# @return Current theme name / Название текущей темы
# @example
#   current_theme=$(ps1config::get_current_theme)
ps1config::get_current_theme() {
    echo "$PS1_CONFIG_CURRENT_THEME"
}

# @description Reset PS1 to default
# @description Сбросить PS1 к значению по умолчанию
# @example
#   ps1config::reset
ps1config::reset() {
    PS1="\[\033[01;32m\]\u\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "
    PS1_CONFIG_CURRENT_THEME="default"
    utils::quiet_err log::info "PS1 reset to default" || true
}

# @description Show PS1 configuration demo
# @description Показать демо конфигурации PS1
# @example
#   ps1config::demo
ps1config::demo() {
    utils::quiet_err log::header "PS1 Configuration Demo" || true
    utils::quiet_err log::header "Демо конфигурации PS1" || true
    
    echo
    echo -e "${COLOR_BLUE}Available themes / Доступные темы:${COLOR_RESET}"
    ps1config::list_themes
    
    echo
    echo -e "${COLOR_BLUE}Current theme / Текущая тема:${COLOR_RESET}"
    echo "Current: $(ps1config::get_current_theme)"
    
    echo
    echo -e "${COLOR_BLUE}Testing themes / Тестирование тем:${COLOR_RESET}"
    
    local themes=("default" "powerline" "minimal" "time" "rainbow")
    for theme in "${themes[@]}"; do
        echo -e "\n${COLOR_YELLOW}Theme: $theme${COLOR_RESET}"
        ps1config::set_theme "$theme"
        echo "PS1: $PS1"
    done
    
    # Возвращаем default тему
    # Return to default theme
    ps1config::set_theme "default"
}

# ==========================================
# Функции настройки / Configuration functions
# ==========================================

# @description Enable advanced PS1 features
# @description Включить расширенные функции PS1
# @example
#   ps1config::enable_advanced
ps1config::enable_advanced() {
    # Включаем git info
    # Enable git info
    ps1config::set_git_info true
    
    # Включаем динамическое обновление
    # Enable dynamic updates
    ps1config::setup_prompt_command
    
    # Устанавливаем тему powerline
    # Set powerline theme
    ps1config::set_theme "powerline"
    
    utils::quiet_err log::info "Advanced PS1 features enabled" || true
    utils::quiet_err log::info "Расширенные функции PS1 включены" || true
}

# @description Disable all PS1 enhancements
# @description Выключить все улучшения PS1
# @example
#   ps1config::disable_enhancements
ps1config::disable_enhancements() {
    ps1config::reset
    ps1config::set_git_info false
    
    # Очищаем PROMPT_COMMAND
    # Clear PROMPT_COMMAND
    PROMPT_COMMAND=""
    
    utils::quiet_err log::info "PS1 enhancements disabled" || true
    utils::quiet_err log::info "Улучшения PS1 отключены" || true
}

# ==========================================
# Инициализация при загрузке модуля / Module initialization
# ==========================================

# Инициализируем модуль при загрузке
# Initialize module on load
if [[ -z "${PS1_CONFIG_INITIALIZED:-}" ]]; then
    PS1_CONFIG_INITIALIZED="1"
    ps1config::init
fi
