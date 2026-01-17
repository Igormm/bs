#!/usr/bin/env bash

# Utility functions for the installer

# Ask user to confirm
# @param question string вопрос
confirm() {
  local question="$1"
  local answer
  read -r -p "${question} [y/N]: " answer
  [[ "${answer}" == "y" || "${answer}" == "Y" ]]
}