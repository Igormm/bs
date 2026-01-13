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