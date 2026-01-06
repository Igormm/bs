#!/usr/bin/env bs
# algorithms.sh — Main algorithms module for BS
# This module provides access to various algorithm implementations

# @description Load all algorithm modules
# @example
#   load "lib/algorithms"
algorithms::init() {
    # Load all algorithm modules
    load "lib/algorithms/binary_search"
    load "lib/algorithms/sorting"
    load "lib/algorithms/graphs"
    load "lib/algorithms/dynamic_programming"
    load "lib/algorithms/hashing"
}

# Initialize the algorithms module by default
algorithms::init