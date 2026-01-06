#!/usr/bin/env bs
# interactiveui.sh — Main interactive UI module for BS
# This module provides text-based interactive UI components

# @description Load the interactive UI module
# @example
#   load "lib/interactiveui"
interactiveui::init() {
    # Load the main interactive UI functionality
    load "lib/interactiveui/main"
    load "lib/interactiveui/doc_search"
}

# Initialize the interactive UI module by default
interactiveui::init