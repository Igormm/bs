#!/usr/bin/env bs
# interactiveui.sh — Main interactive UI module for BS
# This module provides text-based interactive UI components

# @description Load the interactive UI module
# @example
#   source "${BS_ROOT}/lib/ui/interactiveui.sh"
#   interactiveui::init

# @description Initialize the interactive UI module
interactiveui::init() {
    # Prevent multiple initializations
    if [[ -n "${INTERACTIVEUI_INITIALIZED:-}" ]]; then
        return 0
    fi

    INTERACTIVEUI_INITIALIZED=1

    # Load the main interactive UI functionality
    source "${BS_ROOT}/lib/interactiveui/main.sh"
    source "${BS_ROOT}/lib/interactiveui/doc_search.sh"
}

# Initialize the interactive UI module by default
interactiveui::init