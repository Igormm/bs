#!/bin/bash

# Function to get the current shell name without path
get_shell_name() {
    basename "$SHELL"
}

# Function to check if current shell is at least the required version
ensure_shell_version() {
    local required_version=${1:-4}  # Default to version 4 if not specified
    local shell_name=$(get_shell_name)
    
    case "$shell_name" in
        "bash")
            if [[ -z "$BASH_VERSION" ]] || [[ "${BASH_VERSION%%.*}" -lt "$required_version" ]]; then
                echo "Error: Bash version $required_version or higher is required but you have version $BASH_VERSION" >&2
                return 1
            fi
            ;;
        "zsh")
            if [[ -z "$ZSH_VERSION" ]] || [[ "${ZSH_VERSION%%.*}" -lt "$required_version" ]]; then
                echo "Error: Zsh version $required_version or higher is required but you have version $ZSH_VERSION" >&2
                return 1
            fi
            ;;
        *)
            echo "Warning: Unknown shell $shell_name, cannot verify version requirements" >&2
            return 1
            ;;
    esac
    
    echo "Shell $shell_name meets version requirement (>= $required_version)"
    return 0
}

# Backward compatibility function - ensures bash 4 or higher
ensure_bash4() {
    ensure_shell_version 4
}