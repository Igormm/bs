#!/usr/bin/env bs
# examples/bs_test.sh — Smoke test of BS framework core components
# examples/bs_test.sh — Дымовой тест основных компонентов фреймворка BS
#
# Проверяет загрузку ядра и базовых lib-модулей с актуальным API.
# Checks that core and basic lib modules load with the current API.
#
# Запуск / Run:
#   bs run examples/bs_test.sh
#   ./examples/bs_test.sh          # bs должен быть в PATH / bs must be in PATH

# Проверка версии фреймворка / Framework version check
if load "core/version"; then
    log::info "Версия BS фреймворка: ${BS_VERSION:-unknown}"
else
    echo "Модуль версии не найден или не удалось загрузить" >&2
fi

# Проверка логирования / Logging check
if load "core/logger"; then
    log::info "Информационное сообщение"
    log::warn "Предупреждающее сообщение"
    log::error "Сообщение об ошибке"
else
    echo "Модуль логгера не найден или не удалось загрузить" >&2
fi

# Проверка констант / Constants check
if load "core/const"; then
    log::info "Константы загружены (E_SUCCESS=${E_SUCCESS})"
else
    echo "Модуль констант не найден или не удалось загрузить" >&2
fi

# Проверка обработчика ошибок / Error handler check
if load "core/errorhandler"; then
    log::info "Обработчик ошибок загружен"
else
    echo "Модуль обработки ошибок не найден или не удалось загрузить" >&2
fi

# Проверка системных компонентов / System components check
if load "lib/system/info"; then
    log::info "Системная информация:"
    system::info::os
    system::info::kernel
else
    echo "Модуль системной информации не найден или не удалось загрузить" >&2
fi

# Проверка работы с процессами / Processes check
if load "lib/system/processes"; then
    log::info "Активные процессы (первые 5):"
    # sed читает поток до EOF — head закрыл бы pipe раньше времени (SIGPIPE)
    # sed reads the stream until EOF — head would close the pipe early (SIGPIPE)
    system::processes::list | sed -n '1,5p'
else
    echo "Модуль процессов не найден или не удалось загрузить" >&2
fi

# Проверка работы с дистрибутивом / Distro check
if load "lib/system/distro"; then
    log::info "Дистрибутив: $(system::distro::detect 2>/dev/null || echo unknown)"
else
    echo "Модуль дистрибутива не найден или не удалось загрузить" >&2
fi

log::success "Все проверки выполнены"
