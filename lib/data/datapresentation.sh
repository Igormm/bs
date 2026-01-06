#!/usr/bin/env bs
# datapresentation.sh — Main data presentation module for BS
# This module provides beautiful data presentation with CSV, JSON, and XML support

# @description Load the data presentation module
# @example
#   load "lib/datapresentation"
datapresentation::init() {
    # Load the main data presentation functionality
    load "lib/datapresentation/main"
    load "lib/datapresentation/filesystem_info"
    load "lib/datapresentation/command_search"
}

# Initialize the data presentation module by default
datapresentation::init