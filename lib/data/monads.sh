#!/usr/bin/env bs
# monads.sh — Main monads module for BS
# This module provides functional programming capabilities with monads

# @description Load the monads module
# @example
#   load "lib/monads"
monads::init() {
    # Load the main monad functionality
    load "lib/monads/monad_types"
    load "lib/monads/utils"
}

# Initialize the monads module by default
monads::init