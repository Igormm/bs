#!/usr/bin/env bs
# displaysettings.sh — Main display settings module for BS
# This module provides terminal display configuration for console environments

# @description Load the display settings module
# @example
#   load "lib/displaysettings"
displaysettings::init() {
    # Load the main display settings functionality
    load "lib/displaysettings/terminal_config"
}

# Initialize the display settings module by default
displaysettings::init