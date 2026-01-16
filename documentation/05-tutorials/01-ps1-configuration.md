#!/usr/bin/env bs
# examples/ps1_configuration_example.sh — PS1 configuration example
# examples/ps1_configuration_example.sh — Пример конфигурации PS1
#
# Этот скрипт демонстрирует различные способы настройки PS1
# с использованием модуля ps1config.
# This script demonstrates various ways to configure PS1
# using the ps1config module.

# Можно использовать как standalone скрипт или source для .bashrc
# Can be used as standalone script or sourced for .bashrc

set -euo pipefail

# Проверяем, запущен ли скрипт напрямую
# Check if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Запущен напрямую, подключаем BS
    # Run directly, load BS
    if [[ -f "boot.sh" ]]; then
        source "boot.sh"
        bs::init
    else
        echo "Error: boot.sh not found. Please run from BS directory."
        echo "Ошибка: boot.sh не найден. Пожалуйста, запустите из директории BS."
        exit 1
    fi
fi

# Подключаем модуль PS1
# Load PS1 module
load "lib/ui/ps1config"

# ==========================================
# БАЗОВЫЕ НАСТРОЙКИ / BASIC CONFIGURATIONS
# ==========================================

# 1. Быстрая настройка / Quick setup
# -----------------------------------
setup_ps1_basic() {
    log::header "Basic PS1 Setup / Базовая настройка PS1"
    
    # Просто включаем расширенные функции
    # Just enable advanced features
    ps1config::enable_advanced
    
    log::success "PS1 configured with advanced features"
    log::success "PS1 настроен с расширенными функциями"
    echo
}

# 2. Выбор темы / Theme selection
# --------------------------------
setup_ps1_theme() {
    log::header "Theme Selection / Выбор темы"
    
    # Показываем доступные темы
    # Show available themes
    ps1config::list_themes
    
    echo
    echo -e "${YELLOW}Applying different themes...${NC}"
    echo -e "${YELLOW}Применение различных тем...${NC}"
    
    local themes=("default" "powerline" "minimal" "time" "rainbow")
    for theme in "${themes[@]}"; do
        echo -e "\n${BLUE}Applying theme: $theme${NC}"
        echo -e "${BLUE}Применение темы: $theme${NC}"
        ps1config::set_theme "$theme"
        echo -e "Your PS1 now looks like:"
        echo -e "Ваш PS1 теперь выглядит так:"
        echo "PS1: $PS1"
        sleep 2
    done
    
    # Возвращаем powerline тему как рекомендуемую
    # Return powerline theme as recommended
    ps1config::set_theme "powerline"
    log::success "Applied recommended theme: powerline"
    log::success "Применена рекомендуемая тема: powerline"
    echo
}

# 3. Настройка под свои нужды / Custom configuration
# ---------------------------------------------------
setup_ps1_custom() {
    log::header "Custom Configuration / Настройка под свои нужды"
    
    # Настраиваем время
    # Configure time
    log::info "Setting custom time format..."
    log::info "Настройка пользовательского формата времени..."
    ps1config::set_time_format "%Y-%m-%d %H:%M"
    
    # Включаем/выключаем git info
    # Enable/disable git info
    log::info "Enabling git information..."
    log::info "Включение информации о git..."
    ps1config::set_git_info true
    
    # Настраиваем динамическое обновление
    # Configure dynamic updates
    log::info "Setting up dynamic updates..."
    log::info "Настройка динамического обновления..."
    ps1config::setup_prompt_command
    
    log::success "Custom configuration applied"
    log::success "Пользовательская конфигурация применена"
    echo
}

# 4. Интерактивная настройка / Interactive setup
# -----------------------------------------------
setup_ps1_interactive() {
    log::header "Interactive Setup / Интерактивная настройка"
    
    load "lib/ui/interactiveui"
    
    # Выбор темы
    # Theme selection
    echo
    echo -e "${BLUE}Choose your preferred theme:${NC}"
    echo -e "${BLUE}Выберите предпочитаемую тему:${NC}"
    
    local theme
    theme=$(interactiveui::menu "Select PS1 theme" \
        "default" "powerline" "minimal" "time" "rainbow")
    
    ps1config::set_theme "$theme"
    log::success "Theme set to: $theme"
    log::success "Тема установлена: $theme"
    
    # Вопросы о дополнительных функциях
    # Questions about additional features
    echo
    if interactiveui::confirm "Enable git information? / Включить информацию о git?"; then
        ps1config::set_git_info true
        log::info "Git information enabled"
        log::info "Информация о git включена"
    else
        ps1config::set_git_info false
        log::info "Git information disabled"
        log::info "Информация о git отключена"
    fi
    
    echo
    if interactiveui::confirm "Enable dynamic updates? / Включить динамическое обновление?"; then
        ps1config::setup_prompt_command
        log::info "Dynamic updates enabled"
        log::info "Динамическое обновление включено"
    else
        log::info "Dynamic updates disabled"
        log::info "Динамическое обновление отключено"
    fi
    
    log::success "Interactive setup completed"
    log::success "Интерактивная настройка завершена"
    echo
}

# 5. Профессиональная настройка / Professional setup
# ---------------------------------------------------
setup_ps1_professional() {
    log::header "Professional Setup / Профессиональная настройка"
    
    # Настраиваем для системного администратора
    # Configure for system administrator
    log::info "Configuring for system administrator..."
    log::info "Настройка для системного администратора..."
    
    # Включаем все функции
    # Enable all features
    ps1config::enable_advanced()
    
    # Добавляем SSH индикатор
    # Add SSH indicator
    ps1config::detect_ssh
    
    # Настраиваем время с секундами
    # Configure time with seconds
    ps1config::set_time_format "%H:%M:%S"
    
    log::success "Professional PS1 configuration applied"
    log::success "Профессиональная конфигурация PS1 применена"
    echo
}

# 6. Минималистичная настройка / Minimal setup
# ---------------------------------------------
setup_ps1_minimal() {
    log::header "Minimal Setup / Минималистичная настройка"
    
    # Только самое необходимое
    # Only the essentials
    ps1config::set_theme "minimal"
    ps1config::set_git_info true
    
    log::success "Minimal PS1 configuration applied"
    log::success "Минималистичная конфигурация PS1 применена"
    echo
}

# ==========================================
# ГЛАВНАЯ ФУНКЦИЯ / MAIN FUNCTION
# ==========================================

main() {
    print_header "PS1 Configuration Example"
    print_header "Пример конфигурации PS1"
    
    echo -e "${BLUE}This script demonstrates PS1 configuration options${NC}"
    echo -e "${BLUE}Этот скрипт демонстрирует варианты настройки PS1${NC}"
    echo
    
    # Меню выбора настройки
    # Setup selection menu
    echo -e "${GREEN}Choose configuration option:${NC}"
    echo -e "${GREEN}Выберите вариант настройки:${NC}"
    echo -e "  1. Basic setup / Базовая настройка"
    echo -e "  2. Theme selection / Выбор темы"
    echo -e "  3. Custom configuration / Пользовательская настройка"
    echo -e "  4. Interactive setup / Интерактивная настройка"
    echo -e "  5. Professional setup / Профессиональная настройка"
    echo -e "  6. Minimal setup / Минималистичная настройка"
    echo -e "  7. Demo / Демо"
    echo -e "  0. Exit / Выход"
    echo
    
    read -p "Select option (1-7, 0 to exit): " choice
    
    case "$choice" in
        1)
            setup_ps1_basic
            ;;
        2)
            setup_ps1_theme
            ;;
        3)
            setup_ps1_custom
            ;;
        4)
            setup_ps1_interactive
            ;;
        5)
            setup_ps1_professional
            ;;
        6)
            setup_ps1_minimal
            ;;
        7)
            ps1config::demo
            ;;
        0)
            log::info "Exiting PS1 configuration example"
            log::info "Выход из примера конфигурации PS1"
            exit 0
            ;;
        *)
            log::error "Invalid option: $choice"
            log::error "Недопустимый вариант: $choice"
            ;;
    esac
    
    echo
    echo -e "${GREEN}✓ PS1 configuration completed!${NC}"
    echo -e "${GREEN}✓ Конфигурация PS1 завершена!${NC}"
    echo
    echo -e "${YELLOW}Your PS1 now looks like:${NC}"
    echo -e "${YELLOW}Ваш PS1 теперь выглядит так:${NC}"
    echo "$PS1"
    
    echo
    echo -e "${BLUE}To make changes permanent, add to your .bashrc:${NC}"
    echo -e "${BLUE}Чтобы сделать изменения постоянными, добавьте в .bashrc:${NC}"
    echo -e "  source /path/to/BS/boot.sh"
    echo -e "  load lib/ui/ps1config"
    echo -e "  ps1config::set_theme \"powerline\""
}

# Если скрипт запущен напрямую, запускаем main
# If script is run directly, call main
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
