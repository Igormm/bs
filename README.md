# Установщик BS Framework
# Bs or BOSA or Bourn shell again open source arhitecture framework

## Getting Started
Основная цель - обеспечить гибкую, надежную и легко поддерживаемую систему установки и удаления фреймворка.

## Структура каталога

- [main.sh](../install/main.sh) - Главный скрипт установки, координирующий выполнение всех этапов
- [utils.sh](../install/utils.sh) - Вспомогательные функции (подтверждение пользователя, вывод информации о PATH и т.д.)
- [checks.sh](../install/checks.sh) - Функции проверки среды выполнения (тип оболочки, проверка на уже установленную версию)
- [actions.sh](../install/actions.sh) - Реализация действий установки и удаления
- [path_manager.sh](../install/path_manager.sh) - Управление переменной PATH для различных оболочек (bash, zsh)

## Возможности

### Режимы установки
- **Системная установка**: Установка в `/usr/local` (требует прав root)
- **Локальная установка**: Установка в `~/.local` (не требует прав root)

### Поддерживаемые оболочки
- bash
- zsh

### Действия
- Установка (`install`)
- Удаление (`uninstall` или `remove`)
- Вывод сниппета PATH (`--path`)
- Автоматическое обновление конфигурационных файлов оболочки (`--update-path`)

## Использование

### Стандартная установка

#### Системная установка (требует root):
```bash
sudo ./install.sh
sudo ./install.sh install
```

#### Локальная установка (без root):
```bash
./install.sh --local
./install.sh --local install
```

### Удаление

#### Системное удаление:
```bash
sudo ./install.sh uninstall
```

#### Локальное удаление:
```bash
./install.sh --local uninstall
```

### Управление PATH

#### Вывести сниппет для ручного добавления в PATH:
```bash
./install.sh --local --path
```

#### Автоматически добавить в ~/.bashrc и/или ~/.zshrc:
```bash
./install.sh --local --update-path
```

### Переопределение переменных окружения
Вы можете переопределить значения по умолчанию для следующих переменных:
- `PREFIX` - базовый каталог установки
- `BIN_DIR` - каталог для исполняемых файлов
- `LIB_DIR` - каталог для библиотек

Пример:
```bash
PREFIX=/opt ./install.sh --local
```

## Особенности реализации

### Проверка оболочки
Скрипт проверяет, что используется поддерживаемая оболочка (bash, zsh, ksh, sh) и завершается с ошибкой, если оболочка не поддерживается.

### Защита от дублирования
Перед установкой проверяется, не установлена ли уже BS Framework в указанный каталог, чтобы избежать конфликта версий.

### Безопасность
Скрипт использует безопасные опции оболочки:
- `-e`: выход при ошибке
- `-u`: ошибка при неопределенных переменных
- `-o pipefail`: ошибка в пайплайне при ошибке любой команды

### Управление PATH
При локальной установке скрипт автоматически обновляет `~/.bashrc` и `~/.zshrc`, добавляя путь к `~/.local/bin`, чтобы можно было использовать `#!/usr/bin/env bs` в шебангах.

## Вклад в проект

Если вы хотите внести улучшения, коммите что пожелаете!# Установщик BS Framework

Основная цель - обеспечить гибкую, надежную и легко поддерживаемую систему установки и удаления фреймворка.

## Структура каталога

- [main.sh](../install/main.sh) - Главный скрипт установки, координирующий выполнение всех этапов
- [utils.sh](../install/utils.sh) - Вспомогательные функции (подтверждение пользователя, вывод информации о PATH и т.д.)
- [checks.sh](../install/checks.sh) - Функции проверки среды выполнения (тип оболочки, проверка на уже установленную версию)
- [actions.sh](../install/actions.sh) - Реализация действий установки и удаления
- [path_manager.sh](../install/path_manager.sh) - Управление переменной PATH для различных оболочек (bash, zsh)

## Возможности

### Режимы установки
- **Системная установка**: Установка в `/usr/local` (требует прав root)
- **Локальная установка**: Установка в `~/.local` (не требует прав root)

### Поддерживаемые оболочки
- bash
- zsh

### Действия
- Установка (`install`)
- Удаление (`uninstall` или `remove`)
- Вывод сниппета PATH (`--path`)
- Автоматическое обновление конфигурационных файлов оболочки (`--update-path`)

## Использование

### Стандартная установка

#### Системная установка (требует root):
```bash
sudo ./install.sh
sudo ./install.sh install
```

#### Локальная установка (без root):
```bash
./install.sh --local
./install.sh --local install
```

### Удаление

#### Системное удаление:
```bash
sudo ./install.sh uninstall
```

#### Локальное удаление:
```bash
./install.sh --local uninstall
```

### Управление PATH

#### Вывести сниппет для ручного добавления в PATH:
```bash
./install.sh --local --path
```

#### Автоматически добавить в ~/.bashrc и/или ~/.zshrc:
```bash
./install.sh --local --update-path
```

### Переопределение переменных окружения
Вы можете переопределить значения по умолчанию для следующих переменных:
- `PREFIX` - базовый каталог установки
- `BIN_DIR` - каталог для исполняемых файлов
- `LIB_DIR` - каталог для библиотек

Пример:
```bash
PREFIX=/opt ./install.sh --local
```

## Особенности реализации

### Проверка оболочки
Скрипт проверяет, что используется поддерживаемая оболочка (bash, zsh, ksh, sh) и завершается с ошибкой, если оболочка не поддерживается.

### Защита от дублирования
Перед установкой проверяется, не установлена ли уже BS Framework в указанный каталог, чтобы избежать конфликта версий.

### Безопасность
Скрипт использует безопасные опции оболочки:
- `-e`: выход при ошибке
- `-u`: ошибка при неопределенных переменных
- `-o pipefail`: ошибка в пайплайне при ошибке любой команды

### Управление PATH
При локальной установке скрипт автоматически обновляет `~/.bashrc` и `~/.zshrc`, добавляя путь к `~/.local/bin`, чтобы можно было использовать `#!/usr/bin/env bs` в шебангах.

## Quick Start Guide

### 1. Project Structure

```
bs/
├── bs                          # Main entrypoint
├── boot.sh                       # Library mode bootstrap
├── bootstrap/
│   ├── init.sh                  # Framework initialization
│   └── loader.sh                # Module loader
├── core/
│   ├── const.sh                 # Constants (enhanced)
│   ├── logger.sh                # Logging system (enhanced)
│   ├── errorhandler.sh         # Error handling
│   └── version.sh               # Version management
├── lib/
│   └── system/
│       ├── utils.sh             # Base utilities
│       ├── distro.sh            # Distribution detection
│       ├── ...
│   └── module/ 
│       ├── ...
└── docs/
    ├── ...
```

### 2. Running the Framework

#### Create Your First Script

```bash
# Create a simple script
cat > my_first_bs_script.sh << 'EOF'
#!/usr/bin/env bash
# My first BOSA script

# Source the framework
source "./boot.sh"

# Initialize
bs::init

# Log a message
logger::info "Hello from BOSA!"
logger::success "Framework is working correctly"

# Get system info
load "lib/system/info"
hostname=$(system::info::get_hostname)
logger::info "Current hostname: $hostname"

# Exit cleanly
bs::exit 0
EOF

# Make it executable
chmod +x my_first_bs_script.sh

# Run it
./my_first_bs_script.sh
```

#### Use Shebang Mode

```bash
# Create a shebang script
cat > shebang_script.sh << 'EOF'
#!/usr/bin/env bs
# Shebang mode script

bs::init

logger::header "Shebang Mode Test"
logger::info "This script uses shebang mode!"
logger::list "Feature 1" "Feature 2" "Feature 3"

bs::exit 0
EOF

# Make it executable
chmod +x shebang_script.sh

# Run it (requires bs in PATH or use bin/bs)
./shebang_script.sh
```

### 3. Using System Modules

#### Package Management

```bash
#!/usr/bin/env bash
source "./boot.sh"
bs::init

load "lib/system/distrologic"

# Install packages cross-platform
logger::header "Installing Packages"
system::distrologic::pkg_install_cross "curl" "wget" "git"

logger::success "Packages installed successfully"
```

#### Service Management

```bash
#!/usr/bin/env bash
source "./boot.sh"
bs::init

load "lib/system/services"

# Manage services
logger::header "Service Management"
system::services::start_service "nginx"
system::services::enable_service "nginx"

if system::services::is_active "nginx"; then
    logger::success "Nginx is running"
else
    logger::error "Nginx failed to start"
fi
```

#### User Management

```bash
#!/usr/bin/env bash
source "./boot.sh"
bs::init

load "lib/system/users"

# Create a user
logger::header "User Management"
system::users::create_user "deploy" "/home/deploy"
system::users::add_to_group "deploy" "sudo"

logger::success "User 'deploy' created successfully"
```

### 4. Advanced Features

#### Custom Logging

```bash
#!/usr/bin/env bash
source "./boot.sh"
bs::init

# Set custom log level
export BS_LOG_LEVEL=DEBUG
export BS_LOG_COLOR=always

logger::debug "This debug message will be shown"
logger::trace "This trace message will be shown"

# Use different formats
export BS_LOG_FORMAT=json
logger::info "This is a JSON formatted message"

export BS_LOG_FORMAT=structured
logger::warn "This is a structured message"
```

#### Error Handling

```bash
#!/usr/bin/env bash
source "./boot.sh"
bs::init

# Register cleanup
cleanup::add "echo 'Cleanup called'"

# Try-catch pattern
if error::try "risky_command"; then
    logger::success "Command succeeded"
else
    logger::error "Command failed, but we handled it"
fi

# Retry pattern
if error::retry 3 "unreliable_command"; then
    logger::success "Command succeeded after retries"
else
    logger::error "Command failed after 3 attempts"
    error::exit "Cannot continue" 1
fi
```

#### Custom Modules

```bash
# Create a custom module: lib/custom/my_module.sh
cat > lib/custom/my_module.sh << 'EOF'
#!/usr/bin/env bash
# Custom module example

declare -g MY_MODULE_VERSION="1.0.0"

# @description Do something useful
# @param $1 First parameter
# @param $2 Second parameter
# @example
#   my_module::do_something "arg1" "arg2"
my_module::do_something() {
    local param1="${1:?Missing first parameter}"
    local param2="${2:-default}"
    
    logger::info "Doing something with $param1 and $param2"
    
    # Your logic here
    echo "Result: $param1 + $param2"
    
    return ${E_SUCCESS}
}
EOF

# Use the custom module
#!/usr/bin/env bash
source "./boot.sh"
bs::init

load "lib/custom/my_module"

result=$(my_module::do_something "value1" "value2")
logger::info "Got result: $result"
```

### 5. Testing Your Scripts

#### Unit Testing

```bash
# Create a test script
cat > test_my_module.sh << 'EOF'
#!/usr/bin/env bash
source "./boot.sh"
bs::init

# Load module to test
load "lib/custom/my_module"

# Test function
test_my_module() {
    local result
    result=$(my_module::do_something "test1" "test2")
    
    if [[ "$result" == *"test1 + test2"* ]]; then
        logger::success "Test passed"
        return 0
    else
        logger::error "Test failed"
        return 1
    fi
}

# Run test
test_my_module
EOF

chmod +x test_my_module.sh
./test_my_module.sh
```

#### Integration Testing

```bash
# Create integration test
cat > integration_test.sh << 'EOF'
#!/usr/bin/env bash
source "./boot.sh"
bs::init

load "lib/system/distrologic"
load "lib/system/packages"

# Test package installation flow
test_package_flow() {
    logger::header "Testing Package Installation Flow"
    
    # Check if package is installed
    if system::distrologic::pkg_is_installed "curl"; then
        logger::info "curl is already installed"
    else
        logger::info "Installing curl..."
        if system::distrologic::pkg_install_cross "curl"; then
            logger::success "curl installed successfully"
        else
            logger::error "Failed to install curl"
            return 1
        fi
    fi
    
    return 0
}

test_package_flow
EOF

chmod +x integration_test.sh
./integration_test.sh
```

### 6. Production Deployment

#### Creating a Deployment Script

```bash
cat > deploy.sh << 'EOF'
#!/usr/bin/env bash
source "./boot.sh"
bs::init

# Production deployment script
load "lib/system/distrologic"
load "lib/system/packages"
load "lib/system/services"

# Configuration
APP_NAME="myapp"
APP_USER="app"
APP_DIR="/opt/$APP_NAME"

# Deploy function
deploy_application() {
    logger::header "Deploying $APP_NAME"
    
    # Create user if doesn't exist
    if ! system::users::user_exists "$APP_USER"; then
        logger::info "Creating user $APP_USER"
        system::users::create_user "$APP_USER" "/home/$APP_USER"
    fi
    
    # Install dependencies
    logger::info "Installing dependencies"
    system::distrologic::pkg_install_cross "nginx" "nodejs" "npm"
    
    # Setup application
    logger::info "Setting up application"
    mkdir -p "$APP_DIR"
    chown "$APP_USER:$APP_USER" "$APP_DIR"
    
    # Configure nginx
    logger::info "Configuring nginx"
    # ... nginx configuration logic ...
    
    # Start services
    logger::info "Starting services"
    system::services::enable_service "nginx"
    system::services::start_service "nginx"
    
    logger::success "Deployment completed successfully"
}

# Error handling
cleanup::add "logger::info 'Deployment cleanup completed'"

# Run deployment
deploy_application
EOF

chmod +x deploy.sh
```

#### Using in CI/CD

```yaml
# .github/workflows/deploy.yml
name: Deploy with BOSA

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v2
    
    - name: Setup BOSA
      run: |
        sudo ./install.sh install
    
    - name: Run deployment
      run: |
        ./deploy.sh
```

### 7. Best Practices

#### Code Organization

```bash
# Good organization
my_project/
├── bs/                      # BOSA framework (git submodule)
├── lib/
│   ├── project/              # Project-specific modules
│   │   ├── config.sh
│   │   ├── database.sh
│   │   └── api.sh
│   └── vendor/               # Third-party modules
├── scripts/
│   ├── deploy.sh
│   ├── backup.sh
│   └── monitor.sh
├── tests/
│   ├── unit/
│   └── integration/
└── docs/
```

#### Configuration Management

```bash
# config.sh
#!/usr/bin/env bash
source "./boot.sh"
bs::init

# Load configuration
config::load "/etc/myapp.conf"
config::load "./.myapp.conf"

# Use configuration
logger::info "Using database: ${DB_HOST}:${DB_PORT}"
```

#### Error Handling Patterns

```bash
# Pattern 1: Early returns
function process_data() {
    local data="${1:?Missing data}"
    
    [[ -z "$data" ]] && return ${E_INVALID}
    [[ ! -f "$data" ]] && return ${E_ERROR}
    
    # Process data
    return ${E_SUCCESS}
}

# Pattern 2: Result objects
function get_user_info() {
    local username="${1:?Missing username}"
    local result_status=0
    local result_data=""
    
    if user::exists "$username"; then
        result_data=$(user::info "$username")
        result_status=${E_SUCCESS}
    else
        result_status=${E_ERROR}
    fi
    
    echo "$result_status"
    echo "$result_data"
}

# Pattern 3: Try-catch with fallback
try_with_fallback() {
    local primary_cmd="$1"
    local fallback_cmd="$2"
    
    if error::try "$primary_cmd"; then
        return ${E_SUCCESS}
    elif error::try "$fallback_cmd"; then
        logger::warn "Using fallback for $primary_cmd"
        return ${E_SUCCESS}
    else
        return ${E_ERROR}
    fi
}
```

### 8. Troubleshooting

#### Common Issues

**Problem:** `bs: command not found`
```bash
# Solution 1: Use full path
./bs/bs --help

# Solution 2: Add to PATH
export PATH="$PWD/bs:$PATH"

# Solution 3: Install system-wide
sudo ./install.sh install
```

**Problem:** `Module not found: lib/some_module`
```bash
# Solution 1: Check path is relative to BOSA_ROOT
load "lib/system/some_module"  # Correct
load "./lib/system/some_module"  # Wrong

# Solution 2: Check file exists
ls -la "${BOSA_ROOT}/lib/system/some_module.sh"
```

**Problem:** `Permission denied`
```bash
# Solution
chmod +x your_script.sh
# or
bash your_script.sh
```

#### Debugging

```bash
# Enable debug mode
export BS_LOG_LEVEL=DEBUG

# Run with trace
bash -x your_script.sh

# Check framework variables
bs doctor
```

#### Community Support

- Создайте issue в репозитории
- Присоединяйтесь к обсуждению
- Делитесь вашими модулями
