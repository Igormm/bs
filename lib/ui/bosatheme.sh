#!/usr/bin/env bs
# bosatheme.sh — BS theme for BS bash-it integration
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/guard.sh"
bs::guard "UI_BOSATHEME" || return 0

# Зависимости / Dependencies
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/const.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/logger.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/utils.sh"

# BS theme - A clean, informative prompt
_bosa_prompt() {
    local reset_color='\[\033[0m\]'
    local blue='\[\033[0;34m\]'
    local bright_blue='\[\033[1;34m\]'
    local green='\[\033[0;32m\]'
    local bright_green='\[\033[1;32m\]'
    local yellow='\[\033[1;33m\]'
    local red='\[\033[0;31m\]'
    local purple='\[\033[0;35m\]'
    
    # Get git branch if in a git repository
    local git_branch=""
    if utils::has git && utils::quiet git rev-parse --git-dir; then
        git_branch=" $(utils::quiet_err git branch | grep '^*' | cut -c3-)"
        if [[ -n "$git_branch" ]]; then
            git_branch="${purple}[${git_branch}]${reset_color}"
        fi
    fi
    
    # Get current directory
    local current_dir="$bright_green\W$reset_color"
    
    # Get username and host
    local user_host="$blue\u@\h$reset_color"
    
    # Set the prompt
    PS1="$user_host:$current_dir$git_branch \$ $reset_color"
}

# Apply the prompt to the current shell
bosatheme::apply() {
    _bosa_prompt
}
