#!/usr/bin/env bs
# bashitintegration.sh — Main bashitintegration module for BS
# This module provides Bash-it style integration for BS framework

# @description Load the bashitintegration module
# @example
#   load "lib/bashitintegration"
bashitintegration::init() {
    # Load the main bashitintegration functionality
    load "lib/bashitintegration/main"
}

# Initialize the bashitintegration module by default
bashitintegration::init