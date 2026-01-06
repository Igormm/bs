#!/usr/bin/env bs
# telegramintegration.sh — Main telegram integration module for BS
# This module provides Telegram bot and API integration for BS framework

# @description Load the telegram integration module
# @example
#   load "lib/telegramintegration"
telegramintegration::init() {
    # Load the main telegram integration functionality
    load "lib/telegramintegration/main"
    load "lib/telegramintegration/api"
}

# Initialize the telegram integration module by default
telegramintegration::init