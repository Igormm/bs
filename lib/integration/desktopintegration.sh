#!/usr/bin/env bs
# desktopintegration.sh — Main desktop integration module for BS
# This module provides desktop environment integration for BS framework

# @description Load the desktop integration module
# @example
#   load "lib/desktopintegration"
desktopintegration::init() {
    # Load the main desktop integration functionality
    load "lib/desktopintegration/desktop_env"
}

# Initialize the desktop integration module by default
desktopintegration::init