#!/usr/bin/env bash
# @tier core — bash 4+ only (gated by bootstrap/bs.sh), works everywhere
# @tier core — только bash 4+ (гейт в bootstrap/bs.sh), работает везде

# Environment checking functions for the installer

# Check if already installed
is_already_installed() {
  is::dir "${TARGET_LIB}" && is::file "${TARGET_BIN}"
}

# get running shell environment name

# Чистая функция. Не пишет в stderr, не вызывает exit.
# Возвращает: bash | zsh | ksh | dash | sh | fish | или пустую строку
get_current_shell_name() {
    local shell_path=""
    local shell_name=""

    # Linux: реальный бинарник текущего процесса
    if [[ -e "/proc/$$/exe" ]]; then
        shell_path=$(readlink -f "/proc/$$/exe" 2>/dev/null) || \
        shell_path=$(readlink "/proc/$$/exe" 2>/dev/null) || \
        shell_path=$(realpath "/proc/$$/exe" 2>/dev/null)
    fi

    # Fallback: ps (macOS, BSD, WSL1, контейнеры без /proc)
    if [[ -z "$shell_path" ]]; then
        shell_path=$(ps -p $$ -o comm= 2>/dev/null)
        # Убираем "-" у логин-шеллов (-bash → bash)
        shell_path="${shell_path#-}"
    fi

    # Извлекаем имя бинарника
    shell_name="${shell_path##*/}"

    # Нормализация: обрезаем версии (bash4.2 → bash не нужно, но на всякий случай)
    # Оставляем только известные имена
    case "$shell_name" in
        bash|zsh|ksh|mksh|oksh|dash|sh|ash|fish)
            printf "%s" "$shell_name"
            ;;
        *)
            # Если не распознали — возвращаем как есть или пустоту
            printf "%s" "$shell_name"
            ;;
    esac
}

# check_shell_environment

# Проверяет окружение и выводит ошибки ===
# Использует get_current_shell_name. Может вызвать exit.
check_shell_environment() {
    local shell_name
    shell_name=$(get_current_shell_name)

    # Не смогли определить
    if [[ -z "$shell_name" ]]; then
        printf "ERROR: Unable to detect current shell interpreter.\n" >&2
        exit 1
    fi

    # Проверяем поддерживаемость и версии
    # Версия bash 4+ уже проверена гейтом bootstrap/bs.sh::bs::shell::ensure_version
    # (install.sh source'ит bootstrap/init.sh до check_shell_environment), поэтому
    # здесь только диспетчер интерпретаторов и целостность детекта.
    # Bash 4+ is already gated by bootstrap/bs.sh::bs::shell::ensure_version
    # (install.sh sources bootstrap/init.sh before check_shell_environment),
    # so only the interpreter dispatch and detection integrity remain.
    case "$shell_name" in
        bash)
            if [[ -z "${BASH_VERSION:-}" ]]; then
                printf "ERROR: Shell mismatch. Detected '%s', but \$BASH_VERSION is empty.\n" "$shell_name" >&2
                exit 1
            fi
            ;;

        zsh)
            if [[ -z "${ZSH_VERSION:-}" ]]; then
                printf "ERROR: Shell mismatch. Detected '%s', but \$ZSH_VERSION is empty.\n" "$shell_name" >&2
                exit 1
            fi
            ;;

        ksh|mksh|oksh)
            if [[ -z "${KSH_VERSION:-}" ]]; then
                printf "ERROR: Shell mismatch. Detected '%s', but \$KSH_VERSION is empty.\n" "$shell_name" >&2
                exit 1
            fi
            ;;

        dash|sh|ash)
            printf "ERROR: This script requires bash 4+, zsh, or ksh.\n" >&2
            printf "Current shell: %s\n" "$shell_name" >&2
            printf "Please run: bash %s\n" "$0" >&2
            exit 1
            ;;

        fish)
            printf "ERROR: fish is not supported.\n" >&2
            printf "Please run: bash %s\n" "$0" >&2
            exit 1
            ;;

        *)
            printf "ERROR: Unsupported shell: %s\n" "$shell_name" >&2
            printf "This script requires bash 4+, zsh, or ksh.\n" >&2
            exit 1
            ;;
    esac

    # Сохраняем для других функций
    readonly CURRENT_SHELL="$shell_name"
}
