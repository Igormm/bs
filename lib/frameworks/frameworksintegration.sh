#!/usr/bin/env bs
# shellcheck shell=bash
# shellcheck disable=SC2155

# frameworksintegration.sh — Frameworks Integration Module for BS
# Модуль интеграции фреймворков для BS
#
# Description:
#   Integrates features and patterns from popular Bash frameworks:
#   Bash-it, Bashinator, Bashly, ShellSpec, and mbfl.
#   Интегрирует функции и паттерны из популярных Bash фреймворков:
#   Bash-it, Bashinator, Bashly, ShellSpec и mbfl.
#
# Features:
#   - Bash-it: Community-driven aliases, plugins, and themes
#   - Bashinator: Message handling, logging, and modular structure
#   - Bashly: CLI generation from YAML with argument validation
#   - ShellSpec: BDD testing framework for Bash scripts
#   - mbfl: Marco's Bash Functions Library with naming conventions
#
# Dependencies:
#   - bash 4.0+ (for associative arrays)
#   - Various framework-specific dependencies
#
# Usage:
#   source "${BS_HOME}/boot.sh"
#   bs::init
#   frameworks::init
#   frameworks::bashit::load_plugin "git"
#   frameworks::bashinator::log_message "INFO" "Test message"
#
# @author BS Framework
# @since 2026-01-06
# @version 1.0.0
# @depends core/const, core/logger, core/utils, core/errorhandler

# Source Guard / Защита от повторной загрузки
bs::guard "FRAMEWORKS_INTEGRATION" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "../../core/errorhandler.sh"

# Frameworks Integration configuration
readonly FRAMEWORKS_CONFIG_DIR="${HOME}/.config/bs_frameworks"
readonly FRAMEWORKS_PLUGIN_DIR="${FRAMEWORKS_CONFIG_DIR}/plugins"
readonly FRAMEWORKS_CACHE_DIR="/tmp/bs_frameworks"

# Module state variables
FRAMEWORKS_ACTIVE_PLUGINS=()
FRAMEWORKS_BASHIT_THEME="default"
FRAMEWORKS_BASHINATOR_LEVEL="INFO"

# Initialize frameworks integration
frameworks::init() {
    
    log::info "Initializing Frameworks Integration module..."
    
    # Create necessary directories
    mkdir -p "${FRAMEWORKS_CONFIG_DIR}" || {
        error::throw "Failed to create config directory" \
            "${LIB_ERROR_FILE_OPERATION}"
    }
    
    mkdir -p "${FRAMEWORKS_PLUGIN_DIR}" || {
        error::throw "Failed to create plugin directory" \
            "${LIB_ERROR_FILE_OPERATION}"
    }
    
    mkdir -p "${FRAMEWORKS_CACHE_DIR}" || {
        error::throw "Failed to create cache directory" \
            "${LIB_ERROR_FILE_OPERATION}"
    }
    
    # Initialize sub-modules
    frameworks::bashit::init
    frameworks::bashinator::init
    frameworks::bashly::init
    frameworks::shellspec::init
    frameworks::mbfl::init
    
    log::success "Frameworks Integration module initialized successfully"
}

# ============================================================================
# BASH-IT INTEGRATION (Community-driven aliases, plugins, and themes)
# ============================================================================

frameworks::bashit::init() {
    
    log::debug "Initializing Bash-it integration..."
    
    # Initialize Bash-it components
    FRAMEWORKS_BASHIT_PLUGINS=()
    FRAMEWORKS_BASHIT_ALIASES=()
    FRAMEWORKS_BASHIT_COMPLETIONS=()
    
    log::debug "Bash-it integration initialized"
}

# Load Bash-it style plugin
frameworks::bashit::load_plugin() {
    local plugin_name="${1:-}"
    
    if [[ -z "${plugin_name}" ]]; then
        error::throw "Plugin name is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Loading Bash-it plugin: ${plugin_name}"
    
    # Check if plugin is already loaded
    if [[ " ${FRAMEWORKS_BASHIT_PLUGINS[*]} " =~ " ${plugin_name} " ]]; then
        log::warn "Plugin ${plugin_name} is already loaded"
        return 0
    fi
    
    # Plugin implementations
    case "${plugin_name}" in
        base)
            frameworks::bashit::plugins::base::load
            ;;
        alias)
            frameworks::bashit::plugins::alias::load
            ;;
        battery)
            frameworks::bashit::plugins::battery::load
            ;;
        docker)
            frameworks::bashit::plugins::docker::load
            ;;
        editor)
            frameworks::bashit::plugins::editor::load
            ;;
        git)
            frameworks::bashit::plugins::git::load
            ;;
        history)
            frameworks::bashit::plugins::history::load
            ;;
        osx)
            frameworks::bashit::plugins::osx::load
            ;;
        projects)
            frameworks::bashit::plugins::projects::load
            ;;
        ssh)
            frameworks::bashit::plugins::ssh::load
            ;;
        tmux)
            frameworks::bashit::plugins::tmux::load
            ;;
        *)
            log::warn "Unknown Bash-it plugin: ${plugin_name}"
            return "${E_ERROR}"
            ;;
    esac
    
    FRAMEWORKS_BASHIT_PLUGINS+=("${plugin_name}")
    log::success "Plugin ${plugin_name} loaded successfully"
}

# Base plugin (core functionality)
frameworks::bashit::plugins::base::load() {
    # Directory navigation shortcuts
    alias ..='cd ..'
    alias ...='cd ../..'
    alias ....='cd ../../..'
    alias .....='cd ../../../..'
    
    # List shortcuts
    alias ll='ls -al'
    alias la='ls -A'
    alias l='ls -CF'
    
    # Safe operations
    alias rm='rm -i'
    alias cp='cp -i'
    alias mv='mv -i'
    
    # History shortcuts
    alias h='history'
    alias j='jobs -l'
    
    # Process management
    alias psg='ps aux | grep -v grep | grep'
    alias killall='killall'
    
    # System information
    alias myip='curl -s https://ipinfo.io/ip'
    alias ports='netstat -tulanp'
    
    # Quick edit
    alias qedit='${EDITOR:-nano} ~/.bashrc && source ~/.bashrc'
    
    # BOSA-specific
    alias bosa-init='source "${BOSA_HOME}/boot.sh" && bs::init'
    alias bosa-info='bs::info'
}

# Alias plugin
frameworks::bashit::plugins::alias::load() {
    # Common aliases
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
    
    # File size shortcuts
    alias df='df -h'
    alias du='du -h'
    
    # Tree command
    if utils::has tree; then
        alias tree='tree -C'
    else
        alias tree='find . -print | sed -e "s;[^/]*/;|____;g;s;____|; |;g"'
    fi
    
    # Date/time
    alias now='date +"%T"'
    alias nowdate='date +"%d-%m-%Y"'
    
    # Extract archives
    alias extract='frameworks::bashit::plugins::alias::extract'
}

# Extract function for multiple archive types
frameworks::bashit::plugins::alias::extract() {
    if [[ -f "$1" ]]; then
        case "$1" in
            *.tar.bz2)   tar xjf "$1"     ;;
            *.tar.gz)    tar xzf "$1"     ;;
            *.bz2)       bunzip2 "$1"     ;;
            *.rar)       unrar e "$1"     ;;
            *.gz)        gunzip "$1"      ;;
            *.tar)       tar xf "$1"      ;;
            *.tbz2)      tar xjf "$1"     ;;
            *.tgz)       tar xzf "$1"     ;;
            *.zip)       unzip "$1"       ;;
            *.Z)         uncompress "$1"  ;;
            *.7z)        7z x "$1"        ;;
            *)           echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

# Battery plugin
frameworks::bashit::plugins::battery::load() {
    alias battery='frameworks::bashit::plugins::battery::info'
}

frameworks::bashit::plugins::battery::info() {
    if [[ -f /sys/class/power_supply/BAT0/capacity ]]; then
        local capacity
        capacity=$(cat /sys/class/power_supply/BAT0/capacity)
        local status
        status=$(cat /sys/class/power_supply/BAT0/status)
        echo "Battery: ${capacity}% (${status})"
    elif utils::has pmset; then
        pmset -g batt
    else
        echo "Battery information not available"
    fi
}

# Docker plugin
frameworks::bashit::plugins::docker::load() {
    alias d='docker'
    alias dc='docker-compose'
    alias dps='docker ps'
    alias dpsa='docker ps -a'
    alias dim='docker images'
    alias drm='docker rm'
    alias drmi='docker rmi'
    alias dcl='docker system prune -f'
    
    # Docker bash completion
    if utils::has docker && utils::has docker-compose; then
        utils::ignore source <(docker completion bash)
        utils::ignore source <(docker-compose completion bash)
    fi
}

# Editor plugin
frameworks::bashit::plugins::editor::load() {
    export EDITOR="${EDITOR:-nano}"
    alias edit="${EDITOR}"
    alias e="${EDITOR}"
}

# Git plugin
frameworks::bashit::plugins::git::load() {
    alias g='git'
    alias gs='git status'
    alias ga='git add'
    alias gc='git commit'
    alias gp='git push'
    alias gl='git log'
    alias gd='git diff'
    alias gb='git branch'
    alias gco='git checkout'
    alias gm='git merge'
    alias gr='git rebase'
    alias grv='git revert'
    alias grm='git rm'
    alias gmv='git mv'
    alias gcl='git clone'
    alias gpl='git pull'
    alias gpp='git pull && git push'
    
    # Git functions
    git_current_branch() {
        utils::quiet_err git rev-parse --abbrev-ref HEAD || echo "unknown"
    }
    
    git_current_sha() {
        utils::quiet_err git rev-parse HEAD | cut -c1-7 || echo "unknown"
    }
    
    # Git prompt
    git_prompt() {
        local branch
        branch=$(git_current_branch)
        if [[ -n "${branch}" ]] && [[ "${branch}" != "unknown" ]]; then
            echo " (git:${branch})"
        fi
    }
}

# History plugin
frameworks::bashit::plugins::history::load() {
    # History settings
    shopt -s histappend
    export HISTCONTROL=ignoredups
    export HISTSIZE=10000
    export HISTFILESIZE=10000
    
    # History aliases
    alias h='history'
    alias hg='history | grep'
    alias hclear='history -c'
    
    # Search history with grep
    alias histg='history | grep'
}

# macOS plugin
frameworks::bashit::plugins::osx::load() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        alias finder='open -a Finder .'
        alias show='defaults write com.apple.finder AppleShowAllFiles TRUE; killall Finder'
        alias hide='defaults write com.apple.finder AppleShowAllFiles FALSE; killall Finder'
        alias flushdns='sudo dscacheutil -flushcache'
        alias lsusb='system_profiler SPUSBDataType'
        alias lsbt='system_profiler SPBluetoothDataType'
    fi
}

# Projects plugin
frameworks::bashit::plugins::projects::load() {
    export PROJECTS_HOME="${PROJECTS_HOME:-${HOME}/Projects}"
    
    proj() {
        utils::quiet_err cd "${PROJECTS_HOME}/${1}" || echo "Project not found: ${1}"
    }
    
    proj_list() {
        ls -1 "${PROJECTS_HOME}"
    }
}

# SSH plugin
frameworks::bashit::plugins::ssh::load() {
    alias ss='ssh'
    alias ssconfig='${EDITOR:-nano} ~/.ssh/config'
    
    # SSH with common options
    ssh_copy_id() {
        if utils::has ssh-copy-id; then
            command ssh-copy-id "$@"
        else
            echo "ssh-copy-id not available"
        fi
    }
}

# Tmux plugin
frameworks::bashit::plugins::tmux::load() {
    alias tm='tmux'
    alias tml='tmux list-sessions'
    alias tma='tmux attach-session -t'
    alias tmn='tmux new-session -s'
    alias tmk='tmux kill-session -t'
    
    # Auto-attach to tmux session
    if utils::has tmux && [[ -z "${TMUX}" ]]; then
        if utils::quiet_err tmux has-session; then
            tmux attach-session
        fi
    fi
}

# ============================================================================
# BASHINATOR INTEGRATION (Message handling, logging, and modular structure)
# ============================================================================

frameworks::bashinator::init() {
    
    log::debug "Initializing Bashinator integration..."
    
    # Initialize Bashinator message levels
    FRAMEWORKS_BASHINATOR_LEVELS=(
        "DEBUG"
        "INFO"
        "NOTICE"
        "WARNING"
        "ERROR"
        "CRITICAL"
        "ALERT"
        "EMERGENCY"
    )
    
    log::debug "Bashinator integration initialized"
}

# Bashinator-style message handling
frameworks::bashinator::log_message() {
    local level="${1:-INFO}"
    local message="${2:-}"
    local component="${3:-Bashinator}"
    
    if [[ -z "${message}" ]]; then
        error::throw "Message is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    # Map Bashinator levels to BS logger levels
    case "${level}" in
        DEBUG)
            log::debug "[${component}] ${message}"
            ;;
        INFO|NOTICE)
            log::info "[${component}] ${message}"
            ;;
        WARNING)
            log::warn "[${component}] ${message}"
            ;;
        ERROR|CRITICAL)
            log::error "[${component}] ${message}"
            ;;
        ALERT|EMERGENCY)
            log::fatal "[${component}] ${message}"
            return "${?}"
            ;;
        *)
            log::info "[${component}] ${message}"
            ;;
    esac
}

# Bashinator-style function structure
frameworks::bashinator::function_template() {
    local func_name="frameworks::bashinator::function_template"
    local param1="${1:-}"
    local param2="${2:-}"
    
    # Input validation
    if [[ -z "${param1}" ]]; then
        error::throw "param1 is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    # Function body
    frameworks::bashinator::log_message "DEBUG" "Entering function: ${func_name}"
    
    # Your code here
    local result="${param1}_${param2}"
    
    frameworks::bashinator::log_message "DEBUG" "Exiting function: ${func_name}"
    echo "${result}"
}

# ============================================================================
# BASHLY INTEGRATION (CLI generation from YAML with argument validation)
# ============================================================================

frameworks::bashly::init() {
    
    log::debug "Initializing Bashly integration..."
    
    # Initialize Bashly components
    FRAMEWORKS_BASHLY_COMMANDS=()
    FRAMEWORKS_BASHLY_OPTIONS=()
    FRAMEWORKS_BASHLY_ARGS=()
    
    log::debug "Bashly integration initialized"
}

# Parse command line arguments Bashly-style
frameworks::bashly::parse_args() {
    
    # Initialize variables
    local args=()
    local flags=()
    local options=()
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --*=*)
                # Long option with value
                local option="${1%%=*}"
                local value="${1#*=}"
                options+=("${option}=${value}")
                shift
                ;;
            --*)
                # Long option without value (flag)
                flags+=("$1")
                shift
                ;;
            -*)
                # Short options
                flags+=("$1")
                shift
                ;;
            *)
                # Positional arguments
                args+=("$1")
                shift
                ;;
        esac
    done
    
    # Store parsed arguments in global arrays
    FRAMEWORKS_BASHLY_ARGS=("${args[@]}")
    FRAMEWORKS_BASHLY_FLAGS=("${flags[@]}")
    FRAMEWORKS_BASHLY_OPTIONS=("${options[@]}")
    
    # Return parsed data
    echo "args: ${args[*]}"
    echo "flags: ${flags[*]}"
    echo "options: ${options[*]}"
}

# Validate arguments against schema
frameworks::bashly::validate_args() {
    local schema_file="${1:-}"
    
    if [[ -z "${schema_file}" ]]; then
        error::throw "Schema file is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    # Simple validation (in real Bashly, this would be more complex)
    log::info "Validating arguments against schema: ${schema_file}"
    
    # For now, just check if required arguments are present
    if [[ ${#FRAMEWORKS_BASHLY_ARGS[@]} -eq 0 ]]; then
        log::warn "No positional arguments provided"
    fi
    
    return 0
}

# Generate help text
frameworks::bashly::generate_help() {
    local command_name="${1:-command}"
    local description="${2:-Description not provided}"
    
    cat << EOF
Usage: ${command_name} [OPTIONS] [ARGS]

${description}

Options:
  -h, --help      Show this help message
  -v, --version   Show version information
  --debug         Enable debug mode
  --verbose       Enable verbose output

Arguments:
  [args...]       Positional arguments

Examples:
  ${command_name} --debug arg1 arg2
  ${command_name} --help
EOF
}

# ============================================================================
# SHELLSPEC INTEGRATION (BDD testing framework for Bash scripts)
# ============================================================================

frameworks::shellspec::init() {
    
    log::debug "Initializing ShellSpec integration..."
    
    # Initialize ShellSpec components
    FRAMEWORKS_SHELLSPEC_TESTS=()
    FRAMEWORKS_SHELLSPEC_RESULTS=()
    
    log::debug "ShellSpec integration initialized"
}

# ShellSpec-style test definition
frameworks::shellspec::describe() {
    local description="${1:-}"
    local test_block="${2:-}"
    
    if [[ -z "${description}" ]]; then
        error::throw "Description is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Test Suite: ${description}"
    
    # Execute test block
    if [[ -n "${test_block}" ]]; then
        eval "${test_block}"
    fi
}

# ShellSpec-style test case
frameworks::shellspec::it() {
    local description="${1:-}"
    local test_command="${2:-}"
    
    if [[ -z "${description}" ]]; then
        error::throw "Description is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "  Test: ${description}"
    
    # Execute test
    if [[ -n "${test_command}" ]]; then
        if eval "${test_command}"; then
            log::success "    ✓ PASSED"
            FRAMEWORKS_SHELLSPEC_RESULTS+=("PASS: ${description}")
        else
            log::error "    ✗ FAILED"
            FRAMEWORKS_SHELLSPEC_RESULTS+=("FAIL: ${description}")
        fi
    fi
}

# ShellSpec-style assertions
frameworks::shellspec::assert() {
    local condition="${1:-}"
    
    if [[ -z "${condition}" ]]; then
        error::throw "Condition is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    eval "${condition}"
}

# ShellSpec-style matchers
frameworks::shellspec::matchers::equal() {
    local actual="${1:-}"
    local expected="${2:-}"
    
    [[ "${actual}" == "${expected}" ]]
}

frameworks::shellspec::matchers::contain() {
    local string="${1:-}"
    local substring="${2:-}"
    
    [[ "${string}" == *"${substring}"* ]]
}

frameworks::shellspec::matchers::be_empty() {
    local value="${1:-}"
    
    [[ -z "${value}" ]]
}

frameworks::shellspec::matchers::exist() {
    local path="${1:-}"
    
    [[ -e "${path}" ]]
}

# Run ShellSpec tests
frameworks::shellspec::run() {
    
    log::info "Running ShellSpec tests..."
    
    local passed=0
    local failed=0
    
    for result in "${FRAMEWORKS_SHELLSPEC_RESULTS[@]}"; do
        if [[ "${result}" =~ ^PASS: ]]; then
            ((passed++))
        elif [[ "${result}" =~ ^FAIL: ]]; then
            ((failed++))
        fi
    done
    
    log::info "Test Results: ${passed} passed, ${failed} failed"
    
    if [[ "${failed}" -gt 0 ]]; then
        return "${E_ERROR}"
    else
        return 0
    fi
}

# ============================================================================
# MBFL INTEGRATION (Marco's Bash Functions Library)
# ============================================================================

frameworks::mbfl::init() {
    
    log::debug "Initializing mbfl integration..."
    
    # Initialize mbfl naming conventions
    FRAMEWORKS_MBFL_PREFIX="mbfl_"
    
    log::debug "mbfl integration initialized"
}

# MBFL-style function naming
frameworks::mbfl::define_function() {
    local func_name="${FRAMEWORKS_MBFL_PREFIX}${1:-}"
    local body="${2:-}"
    
    if [[ -z "${1:-}" ]]; then
        errorhandler::throw "frameworks::mbfl::define_function" "Function name is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    eval "${func_name}() { ${body}; }"
}

# MBFL-style variable naming
frameworks::mbfl::set_var() {
    local var_name="${FRAMEWORKS_MBFL_PREFIX}${1:-}"
    local value="${2:-}"
    
    if [[ -z "${1:-}" ]]; then
        errorhandler::throw "frameworks::mbfl::set_var" "Variable name is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    printf -v "${var_name}" '%s' "${value}"
}

# MBFL-style error handling
frameworks::mbfl::die() {
    local message="${1:-Unknown error}"
    local exit_code="${2:-1}"
    
    log::fatal "${message}"
    return "${exit_code}"
}

# MBFL-style argument parsing
frameworks::mbfl::parse_args() {
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  -h, --help     Show this help"
                echo "  -v, --version  Show version"
                exit 0
                ;;
            --version|-v)
                echo "Version: 1.0.0"
                exit 0
                ;;
            --*)
                local option="${1#--}"
                local value="${2:-}"
                printf -v "mbfl_option_${option}" '%s' "${value}"
                shift 2
                ;;
            -*)
                local option="${1#-}"
                local value="${2:-}"
                printf -v "mbfl_flag_${option}" '%s' "${value}"
                shift 2
                ;;
            *)
                mbfl_args+=("$1")
                shift
                ;;
        esac
    done
}

# MBFL-style string functions
frameworks::mbfl::string::is_empty() {
    local string="${1:-}"
    [[ -z "${string}" ]]
}

frameworks::mbfl::string::is_not_empty() {
    local string="${1:-}"
    [[ -n "${string}" ]]
}

frameworks::mbfl::string::length() {
    local string="${1:-}"
    echo "${#string}"
}

frameworks::mbfl::string::substring() {
    local string="${1:-}"
    local start="${2:-0}"
    local length="${3:-}"
    
    if [[ -n "${length}" ]]; then
        echo "${string:${start}:${length}}"
    else
        echo "${string:${start}}"
    fi
}

# MBFL-style array functions
frameworks::mbfl::array::length() {
    local array=("$@")
    echo "${#array[@]}"
}

frameworks::mbfl::array::contains() {
    local element="${1:-}"
    shift
    local array=("$@")
    
    for item in "${array[@]}"; do
        if [[ "${item}" == "${element}" ]]; then
            return 0
        fi
    done
    
    return 1
}

# MBFL-style file functions
frameworks::mbfl::file::exists() {
    local file="${1:-}"
    [[ -f "${file}" ]]
}

frameworks::mbfl::file::is_readable() {
    local file="${1:-}"
    [[ -r "${file}" ]]
}

frameworks::mbfl::file::is_writable() {
    local file="${1:-}"
    [[ -w "${file}" ]]
}

frameworks::mbfl::file::is_executable() {
    local file="${1:-}"
    [[ -x "${file}" ]]
}

# MBFL-style directory functions
frameworks::mbfl::dir::exists() {
    local dir="${1:-}"
    [[ -d "${dir}" ]]
}

frameworks::mbfl::dir::create() {
    local dir="${1:-}"
    mkdir -p "${dir}"
}

frameworks::mbfl::dir::remove() {
    local dir="${1:-}"
    rm -rf "${dir}"
}

# ============================================================================
# FRAMEWORKS INTEGRATION UTILITIES
# ============================================================================

# Get loaded frameworks status
frameworks::status() {
    
    cat << EOF
Frameworks Integration Status:

Bash-it Plugins Loaded: ${#FRAMEWORKS_BASHIT_PLUGINS[@]}
  Plugins: ${FRAMEWORKS_BASHIT_PLUGINS[*]:-none}

Bashinator Level: ${FRAMEWORKS_BASHINATOR_LEVEL}

Bashly Commands: ${#FRAMEWORKS_BASHLY_COMMANDS[@]}
  Commands: ${FRAMEWORKS_BASHLY_COMMANDS[*]:-none}

ShellSpec Tests: ${#FRAMEWORKS_SHELLSPEC_RESULTS[@]}
  Results: ${#FRAMEWORKS_SHELLSPEC_RESULTS[@]} total

MBFL Prefix: ${FRAMEWORKS_MBFL_PREFIX}
EOF
}

# Clear all framework integrations
frameworks::clear() {
    
    log::info "Clearing all framework integrations..."
    
    # Clear Bash-it
    FRAMEWORKS_BASHIT_PLUGINS=()
    FRAMEWORKS_BASHIT_ALIASES=()
    FRAMEWORKS_BASHIT_COMPLETIONS=()
    
    # Clear Bashinator
    FRAMEWORKS_BASHINATOR_LEVEL="INFO"
    
    # Clear Bashly
    FRAMEWORKS_BASHLY_COMMANDS=()
    FRAMEWORKS_BASHLY_OPTIONS=()
    FRAMEWORKS_BASHLY_ARGS=()
    
    # Clear ShellSpec
    FRAMEWORKS_SHELLSPEC_TESTS=()
    FRAMEWORKS_SHELLSPEC_RESULTS=()
    
    log::success "All framework integrations cleared"
}

# Module info
frameworks::info() {
    cat << EOF
Frameworks Integration Module v1.0.0

Integrated Frameworks:
  - Bash-it: Community-driven aliases, plugins, and themes
  - Bashinator: Message handling, logging, and modular structure
  - Bashly: CLI generation from YAML with argument validation
  - ShellSpec: BDD testing framework for Bash scripts
  - mbfl: Marco's Bash Functions Library with naming conventions

Available Functions:
  Bash-it Integration:
    frameworks::bashit::load_plugin <plugin>    - Load Bash-it style plugin
    frameworks::bashit::plugins::<name>::load   - Load specific plugin

  Bashinator Integration:
    frameworks::bashinator::log_message <level> <message> [component]
    frameworks::bashinator::function_template   - Template for functions

  Bashly Integration:
    frameworks::bashly::parse_args [args...]    - Parse command line arguments
    frameworks::bashly::validate_args <schema>  - Validate against schema
    frameworks::bashly::generate_help           - Generate help text

  ShellSpec Integration:
    frameworks::shellspec::describe <desc> <block> - Define test suite
    frameworks::shellspec::it <desc> <command>     - Define test case
    frameworks::shellspec::assert <condition>      - Assert condition
    frameworks::shellspec::run                     - Run tests

  mbfl Integration:
    frameworks::mbfl::define_function <name> <body> - Define function
    frameworks::mbfl::set_var <name> <value>        - Set variable
    frameworks::mbfl::die <message> [exit_code]     - Die with message
    frameworks::mbfl::string::*                     - String functions
    frameworks::mbfl::array::*                      - Array functions
    frameworks::mbfl::file::*                       - File functions
    frameworks::mbfl::dir::*                        - Directory functions

Utilities:
  frameworks::status                            - Show integration status
  frameworks::clear                             - Clear all integrations
  frameworks::info                              - Show this information

Configuration:
  Config directory: ${FRAMEWORKS_CONFIG_DIR}
  Plugin directory: ${FRAMEWORKS_PLUGIN_DIR}
  Cache directory: ${FRAMEWORKS_CACHE_DIR}
EOF
}
