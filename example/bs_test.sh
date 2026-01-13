#!/usr/bin/env bs
bs::init

# Тестирование основных компонентов фреймворка BS

# Проверка версии фреймворка
if load "core/version"; then
    echo "Версия BS фреймворка: ${BOSA_VERSION:-unknown}"
else
    echo "Модуль версии не найден или не удалось загрузить"
fi

# Проверка логирования
if load "core/logger"; then
    logger::print "Тестовое сообщение от логгера"
    logger::info "Информационное сообщение"
    logger::warn "Предупреждающее сообщение"
    logger::error "Сообщение об ошибке"
else
    echo "Модуль логгера не найден или не удалось загрузить"
fi

# Проверка констант
if load "core/const"; then
    echo "Константы загружены"
else
    echo "Модуль констант не найден или не удалось загрузить"
fi

# Проверка обработчика ошибок
if load "core/errorhandler"; then
    echo "Обработчик ошибок загружен"
else
    echo "Модуль обработки ошибок не найден или не удалось загрузить"
fi

# Проверка системных компонентов
if load "lib/system/info"; then
    echo "Системная информация:"
    system::get_os_info
else
    echo "Модуль системной информации не найден или не удалось загрузить"
fi

# Проверка работы с процессами
if load "lib/system/processes"; then
    echo "Активные процессы (первые 5):"
    system::get_processes | head -n 5
else
    echo "Модуль процессов не найден или не удалось загрузить"
fi

# Проверка работы с дистрибутивом
if load "lib/system/distro"; then
    echo "Тип дистрибутива: $(system::get_distro_type)"
else
    echo "Модуль дистрибутива не найден или не удалось загрузить"
fi

# Проверка работы с пакетами
if load "lib/system/packages"; then
    echo "Менеджер пакетов: $(system::get_package_manager)"
else
    echo "Модуль управления пакетами не найден или не удалось загрузить"
fi

echo "Все тесты выполнены успешно!"