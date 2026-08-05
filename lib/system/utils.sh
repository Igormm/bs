#!/usr/bin/env bs
# utils.sh — Comprehensive system utilities library for BS / Комплексная библиотека
# системных утилит для BS
#
# This module provides a wide range of system utility functions based on the user's
# extensive list.
# / Этот модуль предоставляет широкий спектр функций системных утилит на основе обширного
# списка пользователя.
# @depends core/const, core/logger, core/utils, lib/system/distro

# Source Guard / Защита от повторной загрузки
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/guard.sh"
bs::guard "SYSTEM_UTILS" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "distro.sh"

# @description Get OS type / Получить тип ОС
# @return OS type string / Строка типа ОС
# @example
#   os_type=$(system::utils::get_os_type)
system::utils::get_os_type() {
    local os_type
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        os_type="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        os_type="macos"
    elif [[ "$OSTYPE" == "cygwin" ]]; then
        os_type="windows-cygwin"
    elif [[ "$OSTYPE" == "msys" ]]; then
        os_type="windows-msys"
    elif [[ "$OSTYPE" == "win32" ]]; then
        os_type="windows-native"
    else
        os_type="unknown"
    fi
    
    echo "${os_type}"
}

# @description Get kernel version / Получить версию ядра
# @return Kernel version string / Строка версии ядра
# @example
#   kernel_version=$(system::utils::get_kernel_version)
system::utils::get_kernel_version() {
    uname -r
}

# @description Get system uptime / Получить время работы системы
# @return Uptime string / Строка времени работы
# @example
#   uptime=$(system::utils::get_uptime)
system::utils::get_uptime() {
    uptime
}

# @description Get system load average / Получить среднюю нагрузку системы
# @return Load average string / Строка средней нагрузки
# @example
#   load_avg=$(system::utils::get_load_average)
system::utils::get_load_average() {
    cat /proc/loadavg | awk '{print $1, $2, $3}'
}

# @description Get memory information / Получить информацию о памяти
# @return Memory information string / Строка информации о памяти
# @example
#   memory_info=$(system::utils::get_memory_info)
system::utils::get_memory_info() {
    if utils::has free; then
        free -h
    else
        cat /proc/meminfo
    fi
}

# @description Get disk usage for all filesystems / Получить использование диска для всех
# файловых систем
# @return Disk usage information / Информация об использовании диска
# @example
#   disk_usage=$(system::utils::get_disk_usage)
system::utils::get_disk_usage() {
    df -h
}

# @description Get CPU information / Получить информацию о CPU
# @return CPU information string / Строка информации о CPU
# @example
#   cpu_info=$(system::utils::get_cpu_info)
system::utils::get_cpu_info() {
    if [[ -f /proc/cpuinfo ]]; then
        grep -m 1 "model name" /proc/cpuinfo | cut -d ":" -f 2 | xargs
    elif utils::has lscpu; then
        lscpu | grep "Model name" | cut -d ":" -f 2 | xargs
    else
        echo "CPU info not available"
    fi
}

# @description Get hostname / Получить имя хоста
# @return Hostname string / Строка имени хоста
# @example
#   hostname=$(system::utils::get_hostname)
system::utils::get_hostname() {
    hostname
}

# @description Get IP address / Получить IP адрес
# @return IP address string / Строка IP адреса
# @example
#   ip_addr=$(system::utils::get_ip_address)
system::utils::get_ip_address() {
    hostname -I | awk '{print $1}'
}

# @description Get public IP address / Получить публичный IP
# @return Public IP address string / Строка публичного IP
# @example
#   public_ip=$(system::utils::get_public_ip)
system::utils::get_public_ip() {
    curl -s ifconfig.co
}

# @description Check if running as root / Проверить права root
# @return 0 if root, 1 otherwise / 0 если root, 1 в противном случае
# @example
#   if system::utils::check_root; then
#       echo "Running as root"
#   fi
system::utils::check_root() {
    [[ "$EUID" -eq 0 ]]
}

# @description Check if command exists / Проверить наличие команды
# @param $1 Command name / Имя команды
# @return 0 if exists, 1 otherwise / 0 если существует, 1 в противном случае
# @example
#   if system::utils::check_command_exists "curl"; then
#       echo "curl is available"
#   fi
system::utils::check_command_exists() {
    local cmd="${1}"
    utils::has "${cmd}"
}

# @description Check if file exists / Проверить файл
# @param $1 File path / Путь к файлу
# @return 0 if exists, 1 otherwise / 0 если существует, 1 в противном случае
# @example
#   if system::utils::check_file_exists "/etc/passwd"; then
#       echo "File exists"
#   fi
system::utils::check_file_exists() {
    local file_path="${1}"
    [[ -f "${file_path}" ]]
}

# @description Check if directory exists / Проверить директорию
# @param $1 Directory path / Путь к директории
# @return 0 if exists, 1 otherwise / 0 если существует, 1 в противном случае
# @example
#   if system::utils::check_directory_exists "/tmp"; then
#       echo "Directory exists"
#   fi
system::utils::check_directory_exists() {
    local dir_path="${1}"
    [[ -d "${dir_path}" ]]
}

# @description Get system architecture / Получить архитектуру системы
# @return Architecture string / Строка архитектуры
# @example
#   arch=$(system::utils::get_system_architecture)
system::utils::get_system_architecture() {
    uname -m
}

# @description Start a process / Запустить процесс
# @param $1 Process command / Команда процесса
# @example
#   system::utils::process_start "sleep 100"
system::utils::process_start() {
    local cmd="${1}"
    # Split command into arguments (no eval) / Разбиваем команду на аргументы (без eval)
    local -a cmd_args
    read -ra cmd_args <<< "${cmd}"
    "${cmd_args[@]}" &
}

# @description Stop a process by PID / Остановить процесс по PID
# @param $1 Process PID / PID процесса
# @example
#   system::utils::process_stop 1234
system::utils::process_stop() {
    local pid="${1}"
    kill "${pid}"
}

# @description Kill a process by name / Убить процесс по имени
# @param $1 Process name / Имя процесса
# @example
#   system::utils::process_kill_by_name "sleep"
system::utils::process_kill_by_name() {
    local proc_name="${1}"
    pkill -f "${proc_name}"
}

# @description Find processes by name / Найти процессы по имени
# @param $1 Process name / Имя процесса
# @return List of matching PIDs / Список соответствующих PID
# @example
#   pids=$(system::utils::process_find "bash")
system::utils::process_find() {
    local proc_name="${1}"
    pgrep -f "${proc_name}"
}

# @description Count running processes / Подсчет процессов
# @return Number of running processes / Количество запущенных процессов
# @example
#   count=$(system::utils::process_count)
system::utils::process_count() {
    ps -e --no-headers | wc -l
}

# @description Read file content / Чтение файла
# @param $1 File path / Путь к файлу
# @return File content / Содержимое файла
# @example
#   content=$(system::utils::file_read "/etc/hostname")
system::utils::file_read() {
    local file_path="${1}"
    cat "${file_path}"
}

# @description Write content to file / Запись в файл
# @param $1 File path / Путь к файлу
# @param $2 Content / Содержимое
# @example
#   system::utils::file_write "/tmp/test.txt" "Hello, World!"
system::utils::file_write() {
    local file_path="${1}"
    local content="${2}"
    echo "${content}" > "${file_path}"
}

# @description Append content to file / Добавление в файл
# @param $1 File path / Путь к файлу
# @param $2 Content / Содержимое
# @example
#   system::utils::file_append "/tmp/log.txt" "Log entry"
system::utils::file_append() {
    local file_path="${1}"
    local content="${2}"
    echo "${content}" >> "${file_path}"
}

# @description Copy file / Копирование файла
# @param $1 Source file / Исходный файл
# @param $2 Destination file / Файл назначения
# @example
#   system::utils::file_copy "/etc/passwd" "/tmp/passwd.bak"
system::utils::file_copy() {
    local src_file="${1}"
    local dest_file="${2}"
    cp "${src_file}" "${dest_file}"
}

# @description Move file / Перемещение файла
# @param $1 Source file / Исходный файл
# @param $2 Destination file / Файл назначения
# @example
#   system::utils::file_move "/tmp/old.txt" "/tmp/new.txt"
system::utils::file_move() {
    local src_file="${1}"
    local dest_file="${2}"
    mv "${src_file}" "${dest_file}"
}

# @description Delete file / Удаление файла
# @param $1 File path / Путь к файлу
# @example
#   system::utils::file_delete "/tmp/unwanted.txt"
system::utils::file_delete() {
    local file_path="${1}"
    rm "${file_path}"
}

# @description Get file size / Получение размера файла
# @param $1 File path / Путь к файлу
# @return File size in bytes / Размер файла в байтах
# @example
#   size=$(system::utils::file_get_size "/etc/passwd")
system::utils::file_get_size() {
    local file_path="${1}"
    stat -c %s "${file_path}"
}

# @description Get MD5 hash of file / MD5 хэш файла
# @param $1 File path / Путь к файлу
# @return MD5 hash / MD5 хэш
# @example
#   md5=$(system::utils::file_get_md5 "/etc/passwd")
system::utils::file_get_md5() {
    local file_path="${1}"
    md5sum "${file_path}" | cut -d ' ' -f 1
}

# @description Create directory / Создание директории
# @param $1 Directory path / Путь к директории
# @example
#   system::utils::directory_create "/tmp/mydir"
system::utils::directory_create() {
    local dir_path="${1}"
    mkdir -p "${dir_path}"
}

# @description Delete directory / Удаление директории
# @param $1 Directory path / Путь к директории
# @example
#   system::utils::directory_delete "/tmp/mydir"
system::utils::directory_delete() {
    local dir_path="${1}"
    rmdir "${dir_path}"
}

# @description List directory contents / Список содержимого директории
# @param $1 Directory path / Путь к директории
# @return Directory contents / Содержимое директории
# @example
#   contents=$(system::utils::directory_list "/tmp")
system::utils::directory_list() {
    local dir_path="${1}"
    ls -la "${dir_path}"
}

# @description Get directory size / Размер директории
# @param $1 Directory path / Путь к директории
# @return Directory size in bytes / Размер директории в байтах
# @example
#   size=$(system::utils::directory_size "/home")
system::utils::directory_size() {
    local dir_path="${1}"
    du -sb "${dir_path}" | cut -f1
}

# @description Log information message / Информационное сообщение
# @param $@ Message / Сообщение
# @example
#   system::utils::log_info "Operation completed"
system::utils::log_info() {
    log::info "$@"
}

# @description Log warning message / Предупреждение
# @param $@ Message / Сообщение
# @example
#   system::utils::log_warning "Low disk space"
system::utils::log_warning() {
    log::warn "$@"
}

# @description Log error message / Ошибка
# @param $@ Message / Сообщение
# @example
#   system::utils::log_error "Operation failed"
system::utils::log_error() {
    log::error "$@"
}

# @description Log debug message / Отладочное сообщение
# @param $@ Message / Сообщение
# @example
#   system::utils::log_debug "Debug information"
system::utils::log_debug() {
    log::debug "$@"
}

# @description Check system connectivity / Проверка соединения
# @param $1 Host to ping (default: 8.8.8.8) / Хост для пинга (по умолчанию: 8.8.8.8)
# @return 0 if connected, 1 otherwise / 0 если подключен, 1 в противном случае
# @example
#   if system::utils::network_check_connectivity; then
#       echo "Connected"
#   fi
system::utils::network_check_connectivity() {
    local host="${1:-8.8.8.8}"
    utils::quiet ping -c 1 -W 5 "${host}"
}

# @description Download file from URL / Загрузка файла
# @param $1 URL / URL
# @param $2 Output path (optional) / Путь вывода (опционально)
# @example
#   system::utils::network_download "https://example.com/file.txt"
system::utils::network_download() {
    local url="${1}"
    local output_path="${2:-}"
    
    if utils::has wget; then
        if [[ -n "${output_path}" ]]; then
            wget "${url}" -O "${output_path}"
        else
            wget "${url}"
        fi
    elif utils::has curl; then
        if [[ -n "${output_path}" ]]; then
            curl -L "${url}" -o "${output_path}"
        else
            curl -L "${url}" -O
        fi
    else
        log::error "Neither wget nor curl available"
        return 1
    fi
}

# @description Generate random password / Генерация пароля
# @param $1 Length (default: 16) / Длина (по умолчанию: 16)
# @return Generated password / Сгенерированный пароль
# @example
#   password=$(system::utils::security_generate_password 20)
system::utils::security_generate_password() {
    local length="${1:-16}"
    cat /dev/urandom | tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' | fold -w "${length}" | head -n 1
}

# @description Hash password with bcrypt / Хэширование пароля
# @param $1 Password / Пароль
# @return Hashed password / Хэшированный пароль
# @example
#   hash=$(system::utils::security_hash_password "mypassword")
system::utils::security_hash_password() {
    local password="${1}"
    
    if utils::has htpasswd; then
        echo "${password}" | htpasswd -i -B -n testuser | cut -d: -f2
    else
        # Never return the plain password / Никогда не возвращаем пароль открытым текстом
        log::error "htpasswd not available, cannot hash password"
        return 1
    fi
}

# @description Send email notification / Уведомление по email
# @param $1 Recipient email / Email получателя
# @param $2 Subject / Тема
# @param $3 Message body / Тело сообщения
# @example
#   system::utils::notify_email "user@example.com" "Alert" "System is down"
system::utils::notify_email() {
    local recipient="${1}"
    local subject="${2}"
    local body="${3}"
    
    if utils::has mail; then
        echo "${body}" | mail -s "${subject}" "${recipient}"
    else
        log::warn "mail command not available"
        return 1
    fi
}

# @description Monitor CPU usage / Мониторинг CPU
# @return CPU usage percentage / Процент использования CPU
# @example
#   cpu_usage=$(system::utils::monitor_cpu)
system::utils::monitor_cpu() {
    # Get CPU usage from top for 1 sample
    top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}'
}

# @description Monitor memory usage / Мониторинг памяти
# @return Memory usage percentage / Процент использования памяти
# @example
#   mem_usage=$(system::utils::monitor_memory)
system::utils::monitor_memory() {
    free | grep Mem | awk '{printf("%.2f", ($3/$2) * 100.0)}'
}

# @description Install package using appropriate package manager / Установка пакета
# @param $@ Package names / Имена пакетов
# @example
#   system::utils::package_install curl vim
system::utils::package_install() {
    # Using the existing distro module for cross-platform package installation
    system::distro::install_package "$@"
}

# @description Check if package is installed / Проверка установленного пакета
# @param $1 Package name / Имя пакета
# @return 0 if installed, 1 otherwise / 0 если установлен, 1 в противном случае
# @example
#   if system::utils::package_is_installed "curl"; then
#       echo "curl is installed"
#   fi
system::utils::package_is_installed() {
    local package="${1}"
    system::distro::is_package_installed "${package}"
}

# @description Create user / Создание пользователя
# @param $1 Username / Имя пользователя
# @param $2 User ID (optional) / ID пользователя (опционально)
# @example
#   system::utils::user_create "newuser"
system::utils::user_create() {
    local username="${1}"
    local user_id="${2:-}"
    
    if [[ -n "${user_id}" ]]; then
        useradd -m -u "${user_id}" "${username}"
    else
        useradd -m "${username}"
    fi
}

# @description Delete user / Удаление пользователя
# @param $1 Username / Имя пользователя
# @example
#   system::utils::user_delete "olduser"
system::utils::user_delete() {
    local username="${1}"
    userdel -r "${username}"
}

# @description Get current date and time / Текущая дата и время
# @param $1 Format (optional, default: %Y-%m-%d %H:%M:%S) / Формат (опционально, по
# умолчанию: %Y-%m-%d %H:%M:%S)
# @return Formatted date/time / Форматированная дата/время
# @example
#   now=$(system::utils::datetime_now)
system::utils::datetime_now() {
    local format="${1:-%Y-%m-%d %H:%M:%S}"
    date +"${format}"
}

# @description Add time to current date / Добавление времени
# @param $1 Amount of time / Количество времени
# @param $2 Unit (seconds, minutes, hours, days) / Единица (секунды, минуты, часы, дни)
# @return New date/time / Новая дата/время
# @example
#   future=$(system::utils::datetime_add 1 days)
system::utils::datetime_add() {
    local amount="${1}"
    local unit="${2}"
    date -d "now + ${amount} ${unit}" '+%Y-%m-%d %H:%M:%S'
}

# @description Length of string / Длина строки
# @param $1 String / Строка
# @return Length / Длина
# @example
#   len=$(system::utils::string_length "hello")
system::utils::string_length() {
    local str="${1}"
    echo "${#str}"
}

# @description Trim whitespace from string / Обрезка пробелов
# @param $1 String / Строка
# @return Trimmed string / Обрезанная строка
# @example
#   trimmed=$(system::utils::string_trim "  hello  ")
system::utils::string_trim() {
    local str="${1}"
    # Remove leading and trailing whitespace
    str="${str#"${str%%[![:space:]]*}"}"
    str="${str%"${str##*[![:space:]]}"}"
    echo "${str}"
}

# @description Convert string to lowercase / Нижний регистр
# @param $1 String / Строка
# @return Lowercase string / Строка в нижнем регистре
# @example
#   lower=$(system::utils::string_lower "HELLO")
system::utils::string_lower() {
    local str="${1}"
    echo "${str,,}"
}

# @description Convert string to uppercase / Верхний регистр
# @param $1 String / Строка
# @return Uppercase string / Строка в верхнем регистре
# @example
#   upper=$(system::utils::string_upper "hello")
system::utils::string_upper() {
    local str="${1}"
    echo "${str^^}"
}

# @description Replace substring in string / Замена подстроки
# @param $1 String / Строка
# @param $2 Pattern to replace / Шаблон для замены
# @param $3 Replacement / Замена
# @return Modified string / Измененная строка
# @example
#   result=$(system::utils::string_replace "hello world" "world" "universe")
system::utils::string_replace() {
    local str="${1}"
    local pattern="${2}"
    local replacement="${3}"
    echo "${str/$pattern/$replacement}"
}

# @description Split string into array / Разделение строки
# @param $1 String / Строка
# @param $2 Delimiter / Разделитель
# @return Array of parts / Массив частей
# @example
#   parts=($(system::utils::string_split "a,b,c" ","))
system::utils::string_split() {
    local str="${1}"
    local delimiter="${2}"
    local IFS="${delimiter}"
    local -a parts=(${str})
    printf '%s\n' "${parts[@]}"
}

# @description Check if string contains substring / Проверка содержания
# @param $1 String / Строка
# @param $2 Substring / Подстрока
# @return 0 if contains, 1 otherwise / 0 если содержит, 1 в противном случае
# @example
#   if system::utils::string_contains "hello world" "world"; then
#       echo "Contains"
#   fi
system::utils::string_contains() {
    local str="${1}"
    local substr="${2}"
    [[ "${str}" == *"${substr}"* ]]
}

# @description Array length / Длина массива
# @param $@ Array elements / Элементы массива
# @return Array length / Длина массива
# @example
#   arr=(a b c)
#   len=$(system::utils::array_length "${arr[@]}")
system::utils::array_length() {
    local -a arr=("$@")
    echo "${#arr[@]}"
}

# @description Add element to array / Добавление в массив
# @param $1 Array name / Имя массива
# @param $2 Element to add / Элемент для добавления
# @example
#   declare -a myarr=(a b)
#   system::utils::array_add myarr "c"
system::utils::array_add() {
    local arr_name="${1}"
    local element="${2}"
    # Use nameref instead of eval / Nameref вместо eval
    local -n arr_ref="${arr_name}"
    arr_ref+=("${element}")
}

# @description Parse JSON using jq if available / Парсинг JSON
# @param $1 JSON string / Строка JSON
# @return Parsed JSON / Разобранный JSON
# @example
#   json_data=$(system::utils::json_parse '{"name": "John"}')
system::utils::json_parse() {
    local json_str="${1}"
    
    if utils::has jq; then
        echo "${json_str}" | jq .
    else
        log::warn "jq command not available"
        echo "${json_str}"
    fi
}

# @description Validate JSON / Валидация JSON
# @param $1 JSON string / Строка JSON
# @return 0 if valid, 1 otherwise / 0 если действительна, 1 в противном случае
# @example
#   if system::utils::json_validate '{"name": "John"}'; then
#       echo "Valid JSON"
#   fi
system::utils::json_validate() {
    local json_str="${1}"
    
    if utils::has jq; then
        echo "${json_str}" | utils::quiet_err jq empty
    else
        log::warn "jq command not available, cannot validate JSON"
        return 1
    fi
}

# @description Read input from user / Чтение ввода
# @param $1 Prompt message / Сообщение-подсказка
# @return User input / Ввод пользователя
# @example
#   name=$(system::utils::input_read "Enter your name: ")
system::utils::input_read() {
    local prompt="${1}"
    read -p "${prompt}" input
    echo "${input}"
}

# @description Confirm with user / Подтверждение
# @param $1 Confirmation message / Сообщение подтверждения
# @return 0 if confirmed, 1 otherwise / 0 если подтверждено, 1 в противном случае
# @example
#   if system::utils::input_confirm "Continue?"; then
#       echo "Confirmed"
#   fi
system::utils::input_confirm() {
    local prompt="${1}"
    local response
    read -p "${prompt} (y/N): " response
    [[ "${response}" =~ ^[Yy]$ ]]
}

# @description Parse command line arguments / Парсинг аргументов
# @return Parsed arguments / Разобранные аргументы
# @example
#   system::utils::cli_parse_args "$@"
system::utils::cli_parse_args() {
    # This is a basic implementation - more complex parsing would require more code
    local args=("$@")
    for arg in "${args[@]}"; do
        echo "Argument: ${arg}"
    done
}

# @description Show help message / Показ справки
# @example
#   system::utils::cli_show_help
system::utils::cli_show_help() {
    echo "BS System Utilities Help"
    echo "This module provides various system utility functions"
    echo ""
    echo "Examples of available functions:"
    echo "  system::utils::get_hostname"
    echo "  system::utils::get_ip_address"
    echo "  system::utils::check_root"
    echo "  system::utils::file_read <path>"
    echo "  system::utils::directory_create <path>"
    echo "  system::utils::package_install <package_name>"
}

# @description Dependency check / Проверка зависимостей
# @param $@ Commands to check / Команды для проверки
# @return 0 if all found, 1 otherwise / 0 если все найдены, 1 в противном случае
# @example
#   system::utils::dependency_check curl jq git
system::utils::dependency_check() {
    local missing_deps=()
    
    for cmd in "$@"; do
        if ! utils::has "${cmd}"; then
            missing_deps+=("${cmd}")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log::warn "Missing dependencies: ${missing_deps[*]}"
        return 1
    else
        log::info "All dependencies found"
        return 0
    fi
}

# @description API call using curl or wget / Вызов API
# @param $1 Method (GET, POST, etc.) / Метод (GET, POST и т.д.)
# @param $2 URL / URL
# @param $3 Data (optional) / Данные (опционально)
# @example
#   system::utils::api_call GET "https://api.example.com/data"
system::utils::api_call() {
    local method="${1}"
    local url="${2}"
    local data="${3:-}"
    
    if utils::has curl; then
        if [[ -n "${data}" ]]; then
            curl -X "${method}" -H "Content-Type: application/json" -d "${data}" "${url}"
        else
            curl -X "${method}" "${url}"
        fi
    elif utils::has wget; then
        if [[ "${method}" == "GET" ]]; then
            wget -qO- "${url}"
        else
            log::warn "wget does not support ${method} method well, recommend using curl"
            return 1
        fi
    else
        log::error "Neither curl nor wget available"
        return 1
    fi
}