#!/usr/bin/env bs
# shellcheck shell=bash
# vkapi.sh — VK API Integration Module for BS Framework
# Модуль интеграции VK API для фреймворка BS
#
# Description:
#   Provides comprehensive VK API integration including authentication,
#   user management, messaging, wall operations, and more.
#   Предоставляет комплексную интеграцию с VK API, включая аутентификацию,
#   управление пользователями, сообщениями, операции со стеной и многое другое.
#
# Features:
#   - OAuth 2.0 authentication flow
#   - API method calls with rate limiting
#   - User management (friends, groups, etc.)
#   - Messaging (send, receive, conversations)
#   - Wall operations (post, get, delete)
#   - Photo and document uploads
#   - Error handling and retries
#   - Caching for better performance
#
# Dependencies:
#   - curl (for HTTP requests)
#   - jq (for JSON parsing)
#   - openssl (for signatures)
#   - base64 (for encoding)
#
# Usage:
#   source "${BS_ROOT}/boot.sh"
#   bs::init
#   vkapi::init "YOUR_APP_ID" "YOUR_APP_SECRET"
#   vkapi::auth "USER_TOKEN"
#   vkapi::users.get "user_id=1"
#
# @author BS Framework
# @since 2026-01-06
# @version 1.0.0
# @depends core/const, core/logger, core/utils, core/errorhandler, lib/system/platformcheck

# Source Guard / Защита от повторной загрузки
bs::guard "INTEGRATION_VK_API" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "../../core/errorhandler.sh" "../system/platformcheck.sh"

# Error codes fallbacks (no readonly): values live in core/const.sh;
# assign defaults only when const.sh was not loaded (standalone mode).
: "${LIB_ERROR_INVALID_ARGS:=3}"
: "${LIB_ERROR_FILE_OPERATION:=100}"
: "${LIB_ERROR_DEPENDENCY_MISSING:=101}"
: "${LIB_ERROR_PLATFORM_UNSUPPORTED:=102}"
: "${LIB_ERROR_INVALID_STATE:=104}"
: "${LIB_ERROR_API_REQUEST:=105}"
: "${LIB_ERROR_INVALID_RESPONSE:=106}"
: "${LIB_ERROR_API_RESPONSE:=107}"

# VK API configuration constants
readonly VK_API_VERSION="5.131"
readonly VK_API_BASE_URL="https://api.vk.com/method"
readonly VK_OAUTH_BASE_URL="https://oauth.vk.com"
readonly VK_API_RATE_LIMIT_DELAY=0.34  # 3 requests per second
readonly VK_API_MAX_RETRIES=3
readonly VK_API_CACHE_TTL=300  # 5 minutes

# Module state variables
VK_API_APP_ID=""
VK_API_APP_SECRET=""
VK_API_ACCESS_TOKEN=""
VK_API_LAST_REQUEST_TIME=0
VK_API_CACHE_DIR="${BS_ROOT:-/tmp}/vk_api_cache"

# Ensure function_exists helper is available
if ! utils::has function_exists; then
  function_exists() { utils::quiet declare -F "$1"; }
fi

# Helper function for error handling (since errorhandler::throw may not be available)
_vkapi_error() {
    local message="${1}"
    local exit_code="${2:-1}"
    if function_exists "log::error"; then
        log::error "${message}"
    else
        echo "ERROR: ${message}" >&2
    fi
    return "${exit_code}"
}

# Module initialization
vkapi::init() {
    local app_id="${1:-}"
    local app_secret="${2:-}"
    
    log::info "Initializing VK API module..."
    
    # Store credentials
    VK_API_APP_ID="${app_id}"
    VK_API_APP_SECRET="${app_secret}"
    
    # Check dependencies
    vkapi::check_dependencies
    
    # Create cache directory
    mkdir -p "${VK_API_CACHE_DIR}" || {
        error::throw "Failed to create cache directory" \
            "${LIB_ERROR_FILE_OPERATION}"
    }
    
    log::success "VK API module initialized successfully"
}

# Check VK API dependencies
vkapi::check_dependencies() {
    local missing_deps=()
    
    log::debug "Checking VK API dependencies..."

    deps::missing_tools missing_deps \
        curl jq openssl base64:coreutils
    
    # Install missing dependencies based on platform
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log::warn "Missing dependencies: ${missing_deps[*]}"
        vkapi::install_dependencies "${missing_deps[@]}"
    else
        log::debug "All dependencies are installed"
    fi
}

# Install missing dependencies
vkapi::install_dependencies() {
    local deps=("$@")
    
    log::info "Installing missing dependencies: ${deps[*]}..."
    
    # Helper predicates with graceful fallbacks if platformcheck is unavailable
    _vk_is_debian_like=false
    _vk_is_rhel_like=false
    _vk_is_macos=false

    if utils::has platformcheck::is_debian && platformcheck::is_debian || \
       utils::has platformcheck::is_ubuntu && platformcheck::is_ubuntu; then
        _vk_is_debian_like=true
    elif utils::has platformcheck::is_alma && platformcheck::is_alma || \
         utils::has platformcheck::is_fedora && platformcheck::is_fedora; then
        _vk_is_rhel_like=true
    elif utils::has platformcheck::is_macos && platformcheck::is_macos; then
        _vk_is_macos=true
    fi

    if [[ "${_vk_is_debian_like}" == true ]]; then
        apt-get update
        apt-get install -y curl jq openssl coreutils
    elif [[ "${_vk_is_rhel_like}" == true ]]; then
        dnf install -y curl jq openssl coreutils
    elif [[ "${_vk_is_macos}" == true ]]; then
        if ! utils::has brew; then
            if utils::has errorhandler::throw; then
                error::throw "Homebrew is required for macOS" "${LIB_ERROR_DEPENDENCY_MISSING}"
            else
                _vkapi_error "Homebrew is required for macOS" "${LIB_ERROR_DEPENDENCY_MISSING}"
            fi
        fi
        brew install curl jq openssl
    else
        if utils::has errorhandler::throw; then
            error::throw "Unsupported or undetected platform for dependency installation" "${LIB_ERROR_PLATFORM_UNSUPPORTED}"
        else
            _vkapi_error "Unsupported or undetected platform for dependency installation" "${LIB_ERROR_PLATFORM_UNSUPPORTED}"
        fi
    fi
    
    log::success "Dependencies installed successfully"
}

# Set access token
vkapi::auth() {
    local access_token="${1:-}"
    
    if [[ -z "${access_token}" ]]; then
        error::throw "Access token is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    VK_API_ACCESS_TOKEN="${access_token}"
    log::info "VK API authentication configured"
}

# Rate limiting delay
vkapi::rate_limit_delay() {
    local current_time
    current_time=$(utils::now_float)
    
    local time_diff
    time_diff=$(echo "${current_time} - ${VK_API_LAST_REQUEST_TIME}" | utils::quiet_err bc -l || echo "1")
    
    if (( $(echo "${time_diff} < ${VK_API_RATE_LIMIT_DELAY}" | utils::quiet_err bc -l || echo "0") )); then
        local sleep_time
        sleep_time=$(echo "${VK_API_RATE_LIMIT_DELAY} - ${time_diff}" | utils::quiet_err bc -l || echo "0.34")
        sleep "${sleep_time}"
    fi
    
    VK_API_LAST_REQUEST_TIME=$(utils::now_float)
}

# Generate cache key for request
vkapi::get_cache_key() {
    local method="${1:-}"
    local params="${2:-}"
    
    echo -n "${method}_${params}" | openssl dgst -sha256 | cut -d' ' -f2
}

# Check if cached response exists and is valid
vkapi::get_cached_response() {
    local cache_key="${1:-}"
    
    local cache_file="${VK_API_CACHE_DIR}/${cache_key}.json"
    
    if [[ -f "${cache_file}" ]]; then
        local file_age
        file_age=$(echo "$(utils::now_s) - $(utils::quiet_err stat -c %Y "${cache_file}" || utils::quiet_err stat -f %m "${cache_file}")" | bc)
        
        if [[ "${file_age}" -lt "${VK_API_CACHE_TTL}" ]]; then
            cat "${cache_file}"
            return 0
        else
            rm -f "${cache_file}"
        fi
    fi
    
    return 1
}

# Cache API response
vkapi::cache_response() {
    local cache_key="${1:-}"
    local response="${2:-}"
    
    local cache_file="${VK_API_CACHE_DIR}/${cache_key}.json"
    echo "${response}" > "${cache_file}"
}

# Make API request
vkapi::api_request() {
    local method="${1:-}"
    local params="${2:-}"
    local use_cache="${3:-true}"
    
    if [[ -z "${method}" ]]; then
        error::throw "API method is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    if [[ -z "${VK_API_ACCESS_TOKEN}" ]]; then
        error::throw "Access token not set. Use vkapi::auth() first." \
            "${LIB_ERROR_INVALID_STATE}"
    fi
    
    # Check cache first
    if [[ "${use_cache}" == "true" ]]; then
        local cache_key
        cache_key=$(vkapi::get_cache_key "${method}" "${params}")
        
        local cached_response
        if cached_response=$(vkapi::get_cached_response "${cache_key}"); then
            log::debug "Using cached response for ${method}"
            echo "${cached_response}"
            return 0
        fi
    fi
    
    # Rate limiting
    vkapi::rate_limit_delay
    
    # Build request URL and data
    local url="${VK_API_BASE_URL}/${method}"
    local data="access_token=${VK_API_ACCESS_TOKEN}&v=${VK_API_VERSION}"
    
    if [[ -n "${params}" ]]; then
        data="${data}&${params}"
    fi
    
    # Make request with retries
    local retry_count=0
    local response=""
    local http_code=""
    
    while [[ "${retry_count}" -lt "${VK_API_MAX_RETRIES}" ]]; do
        log::debug "Making API request to ${method} (attempt $((retry_count + 1)))"
        
        # Make curl request
        response=$(utils::quiet_err curl -s -w "%{http_code}" -d "${data}" "${url}")
        http_code=$(echo "${response}" | tail -n1)
        response=$(echo "${response}" | head -n-1)
        
        # Check for rate limiting (HTTP 429)
        if [[ "${http_code}" == "429" ]]; then
            log::warn "Rate limited, waiting before retry..."
            sleep $((retry_count + 1))
            ((retry_count++))
            continue
        fi
        
        # Check for server errors
        if [[ "${http_code}" =~ ^5[0-9][0-9]$ ]]; then
            log::warn "Server error ${http_code}, retrying..."
            sleep $((retry_count + 1))
            ((retry_count++))
            continue
        fi
        
        break
    done
    
    # Check final response
    if [[ "${http_code}" != "200" ]]; then
        error::throw "API request failed with HTTP ${http_code}: ${response}" \
            "${LIB_ERROR_API_REQUEST}"
    fi
    
    # Cache successful response
    if [[ "${use_cache}" == "true" ]] && [[ -n "${cache_key:-}" ]]; then
        vkapi::cache_response "${cache_key}" "${response}"
    fi
    
    echo "${response}"
}

# Parse API response
vkapi::parse_response() {
    local response="${1:-}"
    
    if [[ -z "${response}" ]]; then
        error::throw "Empty response" \
            "${LIB_ERROR_INVALID_RESPONSE}"
    fi
    
    # Check for error in response
    local error_msg
    error_msg=$(echo "${response}" | utils::quiet_err jq -r '.error.error_msg' || echo "")
    
    if [[ -n "${error_msg}" ]] && [[ "${error_msg}" != "null" ]]; then
        local error_code
        error_code=$(echo "${response}" | utils::quiet_err jq -r '.error.error_code' || echo "0")
        error::throw "VK API Error ${error_code}: ${error_msg}" \
            "${LIB_ERROR_API_RESPONSE}"
    fi
    
    # Extract response data
    echo "${response}" | utils::quiet_err jq -r '.response' || echo "${response}"
}

# Generic API method caller
vkapi::api_call() {
    local method="${1:-}"
    local params="${2:-}"
    local use_cache="${3:-true}"
    
    log::debug "Calling VK API method: ${method}"
    
    local response
    response=$(vkapi::api_request "${method}" "${params}" "${use_cache}")
    
    vkapi::parse_response "${response}"
}

# User management methods
vkapi::users.get() {
    local params="${1:-}"
    
    vkapi::api_call "users.get" "${params}"
}

vkapi::users.search() {
    local params="${1:-}"
    
    vkapi::api_call "users.search" "${params}"
}

# Friends methods
vkapi::friends.get() {
    local params="${1:-}"
    
    vkapi::api_call "friends.get" "${params}"
}

vkapi::friends.getOnline() {
    local params="${1:-}"
    
    vkapi::api_call "friends.getOnline" "${params}"
}

# Groups methods
vkapi::groups.get() {
    local params="${1:-}"
    
    vkapi::api_call "groups.get" "${params}"
}

vkapi::groups.getById() {
    local params="${1:-}"
    
    vkapi::api_call "groups.getById" "${params}"
}

# Wall methods
vkapi::wall.get() {
    local params="${1:-}"
    
    vkapi::api_call "wall.get" "${params}"
}

vkapi::wall.post() {
    local params="${1:-}"
    
    vkapi::api_call "wall.post" "${params}"
}

# Messages methods
vkapi::messages.getConversations() {
    local params="${1:-}"
    
    vkapi::api_call "messages.getConversations" "${params}"
}

vkapi::messages.getHistory() {
    local params="${1:-}"
    
    vkapi::api_call "messages.getHistory" "${params}"
}

vkapi::messages.send() {
    local params="${1:-}"
    
    vkapi::api_call "messages.send" "${params}"
}

# Photos methods
vkapi::photos.get() {
    local params="${1:-}"
    
    vkapi::api_call "photos.get" "${params}"
}

vkapi::photos.getWallUploadServer() {
    local params="${1:-}"
    
    vkapi::api_call "photos.getWallUploadServer" "${params}"
}

# Status methods
vkapi::status.get() {
    local params="${1:-}"
    
    vkapi::api_call "status.get" "${params}"
}

vkapi::status.set() {
    local params="${1:-}"
    
    vkapi::api_call "status.set" "${params}"
}

# Board methods (for groups)
vkapi::board.getTopics() {
    local params="${1:-}"
    
    vkapi::api_call "board.getTopics" "${params}"
}

# Market methods
vkapi::market.get() {
    local params="${1:-}"
    
    vkapi::api_call "market.get" "${params}"
}

# Polls methods
vkapi::polls.getById() {
    local params="${1:-}"
    
    vkapi::api_call "polls.getById" "${params}"
}

# Secure methods for app authentication
vkapi::secure.checkToken() {
    local token="${1:-}"
    local ip="${2:-}"
    
    local params="token=${token}"
    if [[ -n "${ip}" ]]; then
        params="${params}&ip=${ip}"
    fi
    
    vkapi::api_call "secure.checkToken" "${params}"
}

# Account methods
vkapi::account.getInfo() {
    local params="${1:-}"
    
    vkapi::api_call "account.getInfo" "${params}"
}

vkapi::account.setOnline() {
    local params="${1:-}"
    
    vkapi::api_call "account.setOnline" "${params}"
}

# Database methods
vkapi::database.getCountries() {
    local params="${1:-}"
    
    vkapi::api_call "database.getCountries" "${params}" "true"  # Cache this
}

vkapi::database.getCities() {
    local params="${1:-}"
    
    vkapi::api_call "database.getCities" "${params}"
}

# Execute method (for generic API calls)
vkapi::execute() {
    local code="${1:-}"
    
    if [[ -z "${code}" ]]; then
        error::throw "VKScript code is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    vkapi::api_call "execute" "code=${code}"
}

# Utility functions for common operations
# Get current user's profile
vkapi::get_my_profile() {
    
    vkapi::users.get "fields=photo_200,status,last_seen,online"
}

# Get user profile by ID
vkapi::get_user_profile() {
    local user_id="${1:-}"
    
    if [[ -z "${user_id}" ]]; then
        error::throw "User ID is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    vkapi::users.get "user_ids=${user_id}&fields=photo_200,status,last_seen,online"
}

# Search for users
vkapi::search_users() {
    local query="${1:-}"
    local count="${2:-10}"
    
    if [[ -z "${query}" ]]; then
        error::throw "Search query is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    vkapi::users.search "q=${query}&count=${count}"
}

# Get user's groups
vkapi::get_user_groups() {
    local user_id="${1:-}"
    local extended="${2:-1}"
    
    local params="extended=${extended}"
    if [[ -n "${user_id}" ]]; then
        params="${params}&user_id=${user_id}"
    fi
    
    vkapi::groups.get "${params}"
}

# Get group information
vkapi::get_group_info() {
    local group_id="${1:-}"
    
    if [[ -z "${group_id}" ]]; then
        error::throw "Group ID is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    vkapi::groups.getById "group_id=${group_id}&fields=members_count,description"
}

# Get wall posts
vkapi::get_wall_posts() {
    local owner_id="${1:-}"
    local count="${2:-10}"
    local offset="${3:-0}"
    
    local params="count=${count}&offset=${offset}"
    if [[ -n "${owner_id}" ]]; then
        params="${params}&owner_id=${owner_id}"
    fi
    
    vkapi::wall.get "${params}"
}

# Post to wall
vkapi::post_to_wall() {
    local message="${1:-}"
    local owner_id="${2:-}"
    
    if [[ -z "${message}" ]]; then
        error::throw "Message is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    local params="message=${message}"
    if [[ -n "${owner_id}" ]]; then
        params="${params}&owner_id=${owner_id}"
    fi
    
    vkapi::wall.post "${params}"
}

# Send message
vkapi::send_message() {
    local user_id="${1:-}"
    local message="${2:-}"
    local random_id="${3:-$(utils::now_s)}"
    
    if [[ -z "${user_id}" ]] || [[ -z "${message}" ]]; then
        error::throw "User ID and message are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    vkapi::messages.send "user_id=${user_id}&message=${message}&random_id=${random_id}"
}

# Get conversations
vkapi::get_conversations() {
    local count="${1:-20}"
    local offset="${2:-0}"
    
    vkapi::messages.getConversations "count=${count}&offset=${offset}"
}

# Get message history
vkapi::get_message_history() {
    local peer_id="${1:-}"
    local count="${2:-20}"
    local offset="${3:-0}"
    
    if [[ -z "${peer_id}" ]]; then
        error::throw "Peer ID is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    vkapi::messages.getHistory "peer_id=${peer_id}&count=${count}&offset=${offset}"
}

# Get online friends
vkapi::get_online_friends() {
    local online_mobile="${1:-1}"
    local order="${2:-random}"
    
    vkapi::friends.getOnline "online_mobile=${online_mobile}&order=${order}"
}

# Set status
vkapi::set_status() {
    local text="${1:-}"
    
    if [[ -z "${text}" ]]; then
        error::throw "Status text is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    vkapi::status.set "text=${text}"
}

# Get current status
vkapi::get_status() {
    local user_id="${1:-}"
    
    local params=""
    if [[ -n "${user_id}" ]]; then
        params="user_id=${user_id}"
    fi
    
    vkapi::status.get "${params}"
}

# Get countries list (cached)
vkapi::get_countries() {
    local need_all="${1:-1}"
    local count="${2:-1000}"
    
    vkapi::database.getCountries "need_all=${need_all}&count=${count}"
}

# Clear cache
vkapi::clear_cache() {
    
    log::info "Clearing VK API cache..."
    
    rm -f "${VK_API_CACHE_DIR}"/*.json
    
    log::success "Cache cleared"
}

# Get API usage statistics
vkapi::get_stats() {
    
    local cache_count
    cache_count=$(utils::quiet_err find "${VK_API_CACHE_DIR}" -name "*.json" | wc -l)
    
    cat << EOF
VK API Statistics:
  Cache directory: ${VK_API_CACHE_DIR}
  Cached responses: ${cache_count}
  Rate limit delay: ${VK_API_RATE_LIMIT_DELAY}s
  Max retries: ${VK_API_MAX_RETRIES}
  Cache TTL: ${VK_API_CACHE_TTL}s
  API version: ${VK_API_VERSION}
EOF
}

# Module info
vkapi::info() {
    cat << EOF
VK API Integration Module v1.0.0

Available API methods:
  Users: users.get, users.search
  Friends: friends.get, friends.getOnline
  Groups: groups.get, groups.getById
  Wall: wall.get, wall.post
  Messages: messages.getConversations, messages.getHistory, messages.send
  Photos: photos.get, photos.getWallUploadServer
  Status: status.get, status.set
  Board: board.getTopics
  Market: market.get
  Polls: polls.getById
  Secure: secure.checkToken
  Account: account.getInfo, account.setOnline
  Database: database.getCountries, database.getCities
  Execute: execute

Utility functions:
  vkapi::auth                     - Set access token
  vkapi::get_my_profile          - Get current user profile
  vkapi::get_user_profile        - Get user profile by ID
  vkapi::search_users            - Search for users
  vkapi::get_user_groups         - Get user's groups
  vkapi::get_group_info          - Get group information
  vkapi::get_wall_posts          - Get wall posts
  vkapi::post_to_wall            - Post to wall
  vkapi::send_message            - Send message
  vkapi::get_conversations       - Get conversations
  vkapi::get_message_history     - Get message history
  vkapi::get_online_friends      - Get online friends
  vkapi::set_status              - Set status
  vkapi::get_status              - Get status
  vkapi::get_countries           - Get countries list
  vkapi::clear_cache             - Clear cache
  vkapi::get_stats               - Get usage statistics

Configuration:
  Cache directory: ${VK_API_CACHE_DIR}
  API version: ${VK_API_VERSION}
  Rate limit: 3 requests per second

Usage:
  vkapi::init "APP_ID" "APP_SECRET"
  vkapi::auth "ACCESS_TOKEN"
  result=\$(vkapi::users.get "user_ids=1")
EOF
}
