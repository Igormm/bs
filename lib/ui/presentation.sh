#!/usr/bin/env bs
# shellcheck shell=bash
# presentation.sh — Main presentation module for BS
# This module provides beautiful terminal output styling capabilities
# @depends core/const, core/logger, core/utils

# Source Guard / Защита от повторной загрузки
bs::guard "UI_PRESENTATION" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh"

# Define common color codes
export PRESENTATION_COLOR_RESET=$'\033[0m'
export PRESENTATION_COLOR_BLACK=$'\033[30m'
export PRESENTATION_COLOR_RED=$'\033[31m'
export PRESENTATION_COLOR_GREEN=$'\033[32m'
export PRESENTATION_COLOR_YELLOW=$'\033[33m'
export PRESENTATION_COLOR_BLUE=$'\033[34m'
export PRESENTATION_COLOR_MAGENTA=$'\033[35m'
export PRESENTATION_COLOR_CYAN=$'\033[36m'
export PRESENTATION_COLOR_WHITE=$'\033[37m'
export PRESENTATION_COLOR_BRIGHT_BLACK=$'\033[90m'
export PRESENTATION_COLOR_BRIGHT_RED=$'\033[91m'
export PRESENTATION_COLOR_BRIGHT_GREEN=$'\033[92m'
export PRESENTATION_COLOR_BRIGHT_YELLOW=$'\033[93m'
export PRESENTATION_COLOR_BRIGHT_BLUE=$'\033[94m'
export PRESENTATION_COLOR_BRIGHT_MAGENTA=$'\033[95m'
export PRESENTATION_COLOR_BRIGHT_CYAN=$'\033[96m'
export PRESENTATION_COLOR_BRIGHT_WHITE=$'\033[97m'

# Define styles
export PRESENTATION_STYLE_BOLD=$'\033[1m'
export PRESENTATION_STYLE_DIM=$'\033[2m'
export PRESENTATION_STYLE_ITALIC=$'\033[3m'
export PRESENTATION_STYLE_UNDERLINE=$'\033[4m'
export PRESENTATION_STYLE_BLINK=$'\033[5m'
export PRESENTATION_STYLE_REVERSE=$'\033[7m'
export PRESENTATION_STYLE_HIDDEN=$'\033[8m'
export PRESENTATION_STYLE_STRIKETHROUGH=$'\033[9m'

# Define background colors
export PRESENTATION_BG_BLACK=$'\033[40m'
export PRESENTATION_BG_RED=$'\033[41m'
export PRESENTATION_BG_GREEN=$'\033[42m'
export PRESENTATION_BG_YELLOW=$'\033[43m'
export PRESENTATION_BG_BLUE=$'\033[44m'
export PRESENTATION_BG_MAGENTA=$'\033[45m'
export PRESENTATION_BG_CYAN=$'\033[46m'
export PRESENTATION_BG_WHITE=$'\033[47m'
export PRESENTATION_BG_BRIGHT_BLACK=$'\033[100m'
export PRESENTATION_BG_BRIGHT_RED=$'\033[101m'
export PRESENTATION_BG_BRIGHT_GREEN=$'\033[102m'
export PRESENTATION_BG_BRIGHT_YELLOW=$'\033[103m'
export PRESENTATION_BG_BRIGHT_BLUE=$'\033[104m'
export PRESENTATION_BG_BRIGHT_MAGENTA=$'\033[105m'
export PRESENTATION_BG_BRIGHT_CYAN=$'\033[106m'
export PRESENTATION_BG_BRIGHT_WHITE=$'\033[107m'

# Define common symbols
export PRESENTATION_SYMBOL_CHECK="✓"
export PRESENTATION_SYMBOL_CROSS="✗"
export PRESENTATION_SYMBOL_ARROW="→"
export PRESENTATION_SYMBOL_POINTER=">"
export PRESENTATION_SYMBOL_STAR="★"
export PRESENTATION_SYMBOL_DIAMOND="◆"
export PRESENTATION_SYMBOL_BULLET="•"

# Define common emojis as fallback text
export PRESENTATION_EMOJI_CHECK="✅"
export PRESENTATION_EMOJI_CROSS="❌"
export PRESENTATION_EMOJI_WARN="⚠️"
export PRESENTATION_EMOJI_INFO="ℹ️"
export PRESENTATION_EMOJI_HEART="❤️"

# @description Colorize text with specified color
# @param $1 Color to use
# @param $2 Text to colorize
# @example
#   colored_text=$(presentation::colorize "$PRESENTATION_COLOR_RED" "Error message")
presentation::colorize() {
    local color="$1"
    local text="$2"
    echo "${color}${text}${PRESENTATION_COLOR_RESET}"
}

# @description Style text with specified style
# @param $1 Style to use
# @param $2 Text to style
# @example
#   styled_text=$(presentation::style "$PRESENTATION_STYLE_BOLD" "Bold text")
presentation::style() {
    local style="$1"
    local text="$2"
    echo "${style}${text}${PRESENTATION_COLOR_RESET}"
}

# @description Create a colored and styled text
# @param $1 Color to use
# @param $2 Style to use
# @param $3 Text to format
# @example
# formatted=$(presentation::format "$PRESENTATION_COLOR_RED" "$PRESENTATION_STYLE_BOLD"
# "Important")
presentation::format() {
    local color="$1"
    local style="$2"
    local text="$3"
    echo "${color}${style}${text}${PRESENTATION_COLOR_RESET}"
}

# @description Print a header with separator lines
# @param $1 Header text
# @param $2 Optional separator character (default: =)
# @example
#   presentation::header "My Application" "="
presentation::header() {
    local text="$1"
    local separator="${2:-=}"
    local width
    width=$(utils::quiet_err tput cols || echo 80)
    local padding=$(( (width - ${#text}) / 2 - 1 ))
    local left_pad=$(printf '%*s' "$padding" | tr ' ' "$separator")
    local right_pad
    
    if (( (padding * 2 + ${#text} + 2) <= width )); then
        right_pad=$(printf '%*s' $((width - padding - ${#text} - 2)) | tr ' ' "$separator")
    else
        right_pad=""
    fi
    
    echo "${left_pad} ${text} ${right_pad}"
}

# @description Print a section header
# @param $1 Section text
# @example
#   presentation::section "Configuration"
presentation::section() {
    local text="$1"
    echo
    echo "$(presentation::colorize "$PRESENTATION_COLOR_BRIGHT_BLUE" "$(presentation::style "$PRESENTATION_STYLE_BOLD" "$text")")"
    echo "$(presentation::colorize "$PRESENTATION_COLOR_BRIGHT_BLUE" "$(printf '%*s' "${#text}" | tr ' ' '-')")"
}

# @description Print a subsection header
# @param $1 Subsection text
# @example
#   presentation::subsection "Database Settings"
presentation::subsection() {
    local text="$1"
    echo
    echo "$(presentation::colorize "$PRESENTATION_COLOR_CYAN" "$text")"
    echo "$(presentation::colorize "$PRESENTATION_COLOR_CYAN" "$(printf '%*s' "${#text}" | tr ' ' '-')")"
}

# @description Print success message
# @param $1 Message to print
# @example
#   presentation::success "Operation completed successfully"
presentation::success() {
    local message="$1"
    echo "$(presentation::colorize "$PRESENTATION_COLOR_BRIGHT_GREEN" "${PRESENTATION_SYMBOL_CHECK} ${message}")"
}

# @description Print error message
# @param $1 Message to print
# @example
#   presentation::error "An error occurred"
presentation::error() {
    local message="$1"
    echo "$(presentation::colorize "$PRESENTATION_COLOR_BRIGHT_RED" "${PRESENTATION_SYMBOL_CROSS} ${message}")"
}

# @description Print warning message
# @param $1 Message to print
# @example
#   presentation::warning "This is a warning"
presentation::warning() {
    local message="$1"
    echo "$(presentation::colorize "$PRESENTATION_COLOR_BRIGHT_YELLOW" "${PRESENTATION_SYMBOL_POINTER} ${message}")"
}

# @description Print info message
# @param $1 Message to print
# @example
#   presentation::info "This is an info message"
presentation::info() {
    local message="$1"
    echo "$(presentation::colorize "$PRESENTATION_COLOR_BRIGHT_BLUE" "${PRESENTATION_SYMBOL_ARROW} ${message}")"
}

# @description Print a progress bar
# @param $1 Current value
# @param $2 Max value
# @param $3 Optional bar width (default: 40)
# @example
#   presentation::progress 50 100 30
presentation::progress() {
    local current="$1"
    local max="$2"
    local width="${3:-40}"
    local percentage
    percentage=$(( current * 100 / max ))
    local filled
    filled=$(( current * width / max ))
    local remaining=$(( width - filled ))
    local bar=""
    
    for ((i=0; i<filled; i++)); do
        bar="${bar}█"
    done
    
    for ((i=0; i<remaining; i++)); do
        bar="${bar}░"
    done
    
    printf "%3d%% [${bar}] (%d/%d)\r" "$percentage" "$current" "$max"
}

# @description Print a styled table
# @param $@ Array of rows (each row is a colon-separated string of cells)
# @example
#   presentation::table "Name:Age:City" "John:25:NYC" "Jane:30:SFO"
presentation::table() {
    local rows=("$@")
    local -a parsed_rows
    local -a col_widths
    local i j
    
    # Parse rows and calculate column widths
    for row in "${rows[@]}"; do
        IFS=':' read -ra cells <<< "$row"
        parsed_rows+=("$(printf '%s|' "${cells[@]}")")
        
        for j in "${!cells[@]}"; do
            local cell_len=${#cells[$j]}
            if [[ $j -ge ${#col_widths[@]} ]] || [[ $cell_len -gt ${col_widths[$j]} ]]; then
                col_widths[$j]=$cell_len
            fi
        done
    done
    
    # Print table
    local separator=""
    for width in "${col_widths[@]}"; do
        separator="${separator}$(printf '%*s' "$((width + 2))" | tr ' ' '-')-"
    done
    separator="+${separator%?}+"
    
    for i in "${!parsed_rows[@]}"; do
        IFS='|' read -ra cells <<< "${parsed_rows[$i]}"
        printf "|"
        for j in "${!cells[@]}"; do
            printf " %-${col_widths[$j]}s |" "${cells[$j]}"
        done
        printf "\n"
        
        if [[ $i -eq 0 ]]; then  # Header separator
            echo "$separator"
        fi
    done
}

# @private
# @description Display width of a string (wide chars/emoji count as 2 cells).
# @description Ширина строки на экране (широкие символы/эмодзи = 2 клетки).
presentation::__disp_width() {
    local s="$1" w=0 c blen i
    for ((i = 0; i < ${#s}; i++)); do
        c="${s:i:1}"
        blen=$(LC_ALL=C printf '%s' "$c" | wc -c)
        if (( blen >= 4 )); then (( w += 2 )); else (( w += 1 )); fi
    done
    printf '%s' "$w"
}

# @description Display width of a string in terminal cells (public wrapper).
# @description Ширина строки в экранных клетках (публичная обёртка).
#   Emoji and other wide chars count as 2 cells / Эмодзи считаются за 2 клетки.
# @param $1 Text / Текст
# @stdout width in cells / ширина в клетках
# @example
#   w="$(presentation::text_width "🚀 Deploy")"
presentation::text_width() {
    presentation::__disp_width "${1-}"
}

# @description Print a box around text
# @param $1 Text to box (multiple lines separated by \n or real newlines)
# @param $2 [optional] "round" for rounded corners / скруглённые углы
# @example
#   presentation::boxed "Line 1\nLine 2\nLine 3"
#   presentation::boxed "Text" round
presentation::boxed() {
    local text="$1"
    local -r style="${2:-square}"

    # Литеральные \n тоже считаем переносами / literal \n counts as newline
    text="${text//\\n/$'\n'}"

    local -a lines
    mapfile -t lines <<< "${text}"

    # Ширина в экранных клетках (printf %-*s считает байты и ломает Unicode)
    # Width in display cells (printf %-*s counts bytes and breaks Unicode)
    local max_w=0 w line
    for line in "${lines[@]}"; do
        w="$(presentation::__disp_width "$line")"
        (( w > max_w )) && max_w=${w}
    done

    local border
    printf -v border '%*s' "$((max_w + 2))" ''
    border="${border// /─}"

    local tl='┌' tr='┐' bl='└' br='┘'
    if [[ "${style}" == "round" ]]; then
        tl='╭' tr='╮' bl='╰' br='╯'
    fi

    echo "${tl}${border}${tr}"
    for line in "${lines[@]}"; do
        w="$(presentation::__disp_width "$line")"
        printf '│ %s%*s │\n' "${line}" "$((max_w - w))" ''
    done
    echo "${bl}${border}${br}"
}

# @description Print a colorful title
# @param $1 Title text
# @example
#   presentation::title "My Application"
presentation::title() {
    local text="$1"
    local styled_chars=""
    local colors=(
        "$PRESENTATION_COLOR_BRIGHT_RED"
        "$PRESENTATION_COLOR_BRIGHT_GREEN" 
        "$PRESENTATION_COLOR_BRIGHT_YELLOW"
        "$PRESENTATION_COLOR_BRIGHT_BLUE"
        "$PRESENTATION_COLOR_BRIGHT_MAGENTA"
        "$PRESENTATION_COLOR_BRIGHT_CYAN"
        "$PRESENTATION_COLOR_BRIGHT_WHITE"
    )
    
    local i
    for ((i=0; i<${#text}; i++)); do
        local char="${text:$i:1}"
        local color_idx=$((i % ${#colors[@]}))
        styled_chars="${styled_chars}${colors[$color_idx]}${char}${PRESENTATION_COLOR_RESET}"
    done
    
    echo
    echo "$(presentation::style "$PRESENTATION_STYLE_BOLD" "$styled_chars")"
    echo
}

# @description Initialize the presentation module
# @example
#   presentation::init
presentation::init() {
    # Module initialization can be extended here if needed
    true
}

# Initialize the presentation module by default
presentation::init