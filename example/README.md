# Example Scripts / Примеры скриптов

This directory contains example scripts built using the BS framework.

Данный каталог содержит примеры скриптов, созданных с использованием фреймворка BS.

## Scripts / Скрипты

### caldate_script.sh
A script that displays calendar and date information using the BS framework. It shows:
- Current date and time
- Current month calendar
- Next month calendar
- Date in different formats (ISO, US, EU)

Скрипт, который отображает информацию о календаре и дате с использованием фреймворка BS. Он показывает:
- Текущую дату и время
- Календарь текущего месяца
- Календарь следующего месяца
- Дату в разных форматах (ISO, US, EU)

## Tests / Тесты

### test_caldate_script.sh
A test script to verify the functionality of caldate_script.sh.

Тестовый скрипт для проверки функциональности caldate_script.sh.

## Installation / Установка

To use the BS framework, you need to install it first. There are two ways to install:

Для использования фреймворка BS его необходимо сначала установить. Есть два способа установки:

### System-wide installation (requires root): / Системная установка (требуется root):
```bash
sudo ./bootstrap/install.sh
```

### Local installation (recommended, no root required): / Локальная установка (рекомендуется, root не требуется):
```bash
./bootstrap/install.sh --local
```

After local installation, you may need to add `~/.local/bin` to your PATH:
После локальной установки, возможно, потребуется добавить `~/.local/bin` в PATH:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Or run: / Или выполните:
```bash
./bootstrap/install.sh --local --update-path
```
This will automatically add the PATH export to your `~/.bashrc`.
Это автоматически добавит экспорт PATH в ваш `~/.bashrc`.

## How to run / Как запустить

To run the calendar and date script:
Для запуска скрипта календаря и даты:

```bash
./example/caldate_script.sh
```

To run the tests:
Для запуска тестов:

```bash
./example/test_caldate_script.sh
```

## Framework Notes / Заметки о фреймворке

The script includes a fallback mechanism in case the BS framework is not installed in the system. If the framework is not available, it will still provide the essential functionality using standard bash commands.

Скрипт включает в себя механизм отказа на случай, если фреймворк BS не установлен в системе. Если фреймворк недоступен, он все равно обеспечит основную функциональность с помощью стандартных команд bash.

# Примеры использования BS Framework

## bs_test.sh - Тестирование основных компонентов фреймворка

Этот скрипт демонстрирует базовое использование фреймворка BS и проверяет работоспособность основных компонентов.

### Что делает скрипт

Скрипт [bs_test.sh](file:///home/igor/bs/example/bs_test.sh) выполняет следующие проверки:

1. **Версия фреймворка** - загружает модуль `core/version` и выводит версию фреймворка
2. **Модуль логирования** - загружает модуль `core/logger` и тестирует разные типы сообщений
3. **Модуль констант** - загружает модуль `core/const` и проверяет его доступность
4. **Обработчик ошибок** - загружает модуль `core/errorhandler` и проверяет его доступность
5. **Системная информация** - загружает модуль `lib/system/info` и выводит информацию о системе
6. **Работа с процессами** - загружает модуль `lib/system/processes` и выводит список активных процессов
7. **Определение дистрибутива** - загружает модуль `lib/system/distro` и определяет тип дистрибутива
8. **Работа с пакетами** - загружает модуль `lib/system/packages` и определяет менеджер пакетов

### Как использовать

Чтобы запустить тест, просто выполните:

```bash
bs ./example/bs_test.sh
```

или если фреймворк установлен в систему:

```bash
./example/bs_test.sh
```

### Особенности

Скрипт использует `load` для загрузки модулей, что является правильным подходом в фреймворке BS. Это позволяет корректно обрабатывать зависимости между модулями и обеспечивает правильную инициализацию компонентов фреймворка.

### Результаты теста

После выполнения всех проверок, скрипт выводит сообщение "Все тесты выполнены успешно!" если все компоненты работают корректно.
