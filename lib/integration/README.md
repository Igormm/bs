# Integration Modules

This directory contains integration modules for BOSA framework.

## Modules

### telegramintegration.sh
Telegram bot integration for sending messages, photos, and documents.

**Usage:**
```bash
load "lib/integration/telegramintegration"
telegramintegration::set_token "YOUR_BOT_TOKEN"
telegramintegration::send_message "CHAT_ID" "Hello from BOSA!"
```

### bashitintegration.sh
Integration with Bash-it framework for enhanced shell experience.

**Usage:**
```bash
load "lib/integration/bashitintegration"
bashitintegration::enable
```

### desktopintegration.sh
Desktop environment integration for GUI applications.

**Usage:**
```bash
load "lib/integration/desktopintegration"
desktopintegration::create_shortcut "My App" "/path/to/app"
```

## Features

- Cross-platform integration
- Easy to use API
- Error handling
- Comprehensive logging
- Bilingual documentation

## Requirements

- BOSA framework initialized
- External dependencies as specified in each module
- Proper configuration for integrations

## Examples

See individual module files for detailed examples and API documentation.
