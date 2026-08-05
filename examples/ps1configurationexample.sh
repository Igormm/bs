#!/usr/bin/env bs
# shellcheck shell=bash
# examples/ps1configurationexample.sh — PS1 configuration example
# examples/ps1configurationexample.sh — Пример конфигурации PS1
#
# Этот скрипт демонстрирует различные способы настройки PS1
# с использованием модуля ps1config.
# This script demonstrates various ways to configure PS1
# using the ps1config module.

# Запуск / Run:
#   ./bs run examples/ps1configurationexample.sh
#   ./examples/ps1configurationexample.sh   (с bs в PATH / with bs in PATH)

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
    echo -e "${COLOR_YELLOW}Applying different themes...${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}Применение различных тем...${COLOR_RESET}"

    local themes=("default" "powerline" "minimal" "time" "rainbow")
    local theme
    for theme in "${themes[@]}"; do
        echo -e "\n${COLOR_BLUE}Applying theme: ${theme}${COLOR_RESET}"
        echo -e "${COLOR_BLUE}Применение темы: ${theme}${COLOR_RESET}"
        ps1config::set_theme "${theme}"
        echo -e "Your PS1 now looks like:"
        echo -e "Ваш PS1 теперь выглядит так:"
        echo "PS1: ${PS1}"
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

    # Выбор темы
    # Theme selection
    echo
    echo -e "${COLOR_BLUE}Choose your preferred theme:${COLOR_RESET}"
    echo -e "${COLOR_BLUE}Выберите предпочитаемую тему:${COLOR_RESET}"

    local themes=("default" "powerline" "minimal" "time" "rainbow")
    local i theme theme_num
    for i in "${!themes[@]}"; do
        echo "  $((i + 1)). ${themes[$i]}"
    done
    read -rp "Select theme (1-${#themes[@]}): " theme_num
    if [[ "${theme_num}" =~ ^[0-9]+$ ]] && (( theme_num >= 1 && theme_num <= ${#themes[@]} )); then
        theme="${themes[$((theme_num - 1))]}"
    else
        theme="default"
    fi

    ps1config::set_theme "${theme}"
    log::success "Theme set to: ${theme}"
    log::success "Тема установлена: ${theme}"

    # Вопросы о дополнительных функциях
    # Questions about additional features
    local answer
    echo
    read -rp "Enable git information? / Включить информацию о git? [y/N] " answer
    if [[ "${answer}" =~ ^[yYдД]$ ]]; then
        ps1config::set_git_info true
        log::info "Git information enabled"
        log::info "Информация о git включена"
    else
        ps1config::set_git_info false
        log::info "Git information disabled"
        log::info "Информация о git отключена"
    fi

    echo
    read -rp "Enable dynamic updates? / Включить динамическое обновление? [y/N] " answer
    if [[ "${answer}" =~ ^[yYдД]$ ]]; then
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
    ps1config::enable_advanced

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
    log::header "PS1 Configuration Example"
    log::header "Пример конфигурации PS1"

    echo -e "${COLOR_BLUE}This script demonstrates PS1 configuration options${COLOR_RESET}"
    echo -e "${COLOR_BLUE}Этот скрипт демонстрирует варианты настройки PS1${COLOR_RESET}"
    echo

    # Меню выбора настройки
    # Setup selection menu
    echo -e "${COLOR_GREEN}Choose configuration option:${COLOR_RESET}"
    echo -e "${COLOR_GREEN}Выберите вариант настройки:${COLOR_RESET}"
    echo -e "  1. Basic setup / Базовая настройка"
    echo -e "  2. Theme selection / Выбор темы"
    echo -e "  3. Custom configuration / Пользовательская настройка"
    echo -e "  4. Interactive setup / Интерактивная настройка"
    echo -e "  5. Professional setup / Профессиональная настройка"
    echo -e "  6. Minimal setup / Минималистичная настройка"
    echo -e "  7. Demo / Демо"
    echo -e "  0. Exit / Выход"
    echo

    local choice
    read -rp "Select option (1-7, 0 to exit): " choice

    case "${choice}" in
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
            log::error "Invalid option: ${choice}"
            log::error "Недопустимый вариант: ${choice}"
            ;;
    esac

    echo
    echo -e "${COLOR_GREEN}✓ PS1 configuration completed!${COLOR_RESET}"
    echo -e "${COLOR_GREEN}✓ Конфигурация PS1 завершена!${COLOR_RESET}"
    echo
    echo -e "${COLOR_YELLOW}Your PS1 now looks like:${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}Ваш PS1 теперь выглядит так:${COLOR_RESET}"
    echo "${PS1}"

    echo
    echo -e "${COLOR_BLUE}To make changes permanent, add to your .bashrc:${COLOR_RESET}"
    echo -e "${COLOR_BLUE}Чтобы сделать изменения постоянными, добавьте в .bashrc:${COLOR_RESET}"
    echo -e "  source /path/to/bs/bootstrap/init.sh"
    echo -e "  load \"lib/ui/ps1config\""
    echo -e "  ps1config::set_theme \"powerline\""
}

# Запускаем main (bs исполняет скрипты через source — как и остальные примеры)
# Call main (bs runs scripts via source — same as the other examples)
main "$@"
