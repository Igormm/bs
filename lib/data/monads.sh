#!/usr/bin/env bs
# monads.sh — Main monads module for BS
# This module provides functional programming capabilities with monads

# @description Load the monads module
# @example
#   source "${BS_ROOT}/lib/data/monads.sh"
#   monads::init

# @description Initialize the monads module
monads::init() {
    # Prevent multiple initializations
    if [[ -n "${MONADS_INITIALIZED:-}" ]]; then
        return 0
    fi

    MONADS_INITIALIZED=1

    # Load the main monad functionality
    source "${BS_ROOT}/lib/monads/monad_types.sh"
    source "${BS_ROOT}/lib/monads/utils.sh"
}

# Initialize the monads module by default
monads::init