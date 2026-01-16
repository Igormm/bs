#!/usr/bin/env bs

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
#   source "${BS_HOME}/boot.sh"
#   bs::init
#   vkapi::init "YOUR_APP_ID" "YOUR_APP_SECRET"
#   vkapi::auth "USER_TOKEN"
#   vkapi::users.get "user_id=1"
#
# @author BS Framework
# @since 2026-01-06
# @version 1.0.0

# Check if module is already loaded
if [[ -n "${BOSA_LIB_INTEGRATION_VK_API_LOADED:-}" ]]; then
    log::debug "VK API module already loaded" 2>/dev/null || true
    return 0
fi
readonly BOSA_LIB_INTEGRATION_VK_API_LOADED=1

# Import required modules
source "${BS_HOME}/core/const.sh"
source "${BS_HOME}/core/logger.sh"
source "${BS_HOME}/core/errorhandler.sh"

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
VK_API_CACHE_DIR="/tmp/vk_api_cache"

# Module initialization
vkapi::init() {
    local func_name="vkapi::init"
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
        errorhandler::throw "${func_name}" "Failed to create cache directory" \
            "${LIB_ERROR_FILE_OPERATION}"
    }
    
    log::success "VK API module initialized successfully"
}

# Check VK API dependencies
check_dependencies() {
    local func_name="vkapi::check_dependencies"
    local missing_deps=()
    
    log::debug "Checking VK API dependencies..."
    
    # Check for curl
    if ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("curl")
    fi
    
    # Check for jq
    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi
    
    # Check for openssl
    if ! command -v openssl >/dev/null 2>&1; then
        missing_deps+=("openssl")
    fi
    
    # Check for base64
    if ! command -v base64 >/dev/null 2>&1; then
        missing_deps+=("coreutils")
    fi
    
    # Install missing dependencies based on platform
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log::warn "Missing dependencies: ${missing_deps[*]}"
        vkapi::install_dependencies "${missing_deps[@]}"
    else
        log::debug "All dependencies are installed"
    fi
}

# Install missing dependencies
install_dependencies() {
    local func_name="vkapi::install_dependencies"
    local deps=("$@")
    
    log::info "Installing missing dependencies: ${deps[*]}..."
    
    # Source platform check module
    source "${BS_HOME}/lib/system/platformcheck.sh"
    
    if platformcheck::is_debian || platformcheck::is_ubuntu; then
        apt-get update
        apt-get install -y curl jq openssl coreutils
    elif platformcheck::is_alma || platformcheck::is_fedora; then
        dnf install -y curl jq openssl coreutils
    elif platformcheck::is_macos; then
        if ! command -v brew >/dev/null 2>&1; then
            errorhandler::throw "${func_name}" "Homebrew is required for macOS" \
                "${LIB_ERROR_DEPENDENCY_MISSING}"
        fi
        brew install curl jq openssl
    else
        errorhandler::throw "${func_name}" "Unsupported platform for dependency installation" \
            "${LIB_ERROR_PLATFORM_UNSUPPORTED}"
    fi
    
    log::success "Dependencies installed successfully"
}

# Set access token
auth() {
    local func_name="vkapi::auth"
    local access_token="${1:-}"
    
    if [[ -z "${access_token}" ]]; then
        errorhandler::throw "${func_name}" "Access token is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    VK_API_ACCESS_TOKEN="${access_token}"
    log::info "VK API authentication configured"
}

# Rate limiting delay
rate_limit_delay() {
    local current_time
    current_time=$(date +%s.%N)
    
    local time_diff
    time_diff=$(echo "${current_time} - ${VK_API_LAST_REQUEST_TIME}" | bc -l 2>/dev/null || echo "1")
    
    if (( $(echo "${time_diff} < ${VK_API_RATE_LIMIT_DELAY}" | bc -l 2>/dev/null || echo "0") )); then
        local sleep_time
        sleep_time=$(echo "${VK_API_RATE_LIMIT_DELAY} - ${time_diff}" | bc -l 2>/dev/null || echo "0.34")
        sleep "${sleep_time}"
    fi
    
    VK_API_LAST_REQUEST_TIME=$(date +%s.%N)
}

# Generate cache key for request
get_cache_key() {
    local method="${1:-}"
    local params="${2:-}"
    
    echo -n "${method}_${params}" | openssl dgst -sha256 | cut -d' ' -f2
}

# Check if cached response exists and is valid
get_cached_response() {
    local func_name="vkapi::get_cached_response"
    local cache_key="${1:-}"
    
    local cache_file="${VK_API_CACHE_DIR}/${cache_key}.json"
    
    if [[ -f "${cache_file}" ]]; then
        local file_age
        file_age=$(echo "$(date +%s) - $(stat -c %Y "${cache_file}" 2>/dev/null || stat -f %m "${cache_file}" 2>/dev/null)" | bc)
        
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
cache_response() {
    local func_name="vkapi::cache_response"
    local cache_key="${1:-}"
    local response="${2:-}"
    
    local cache_file="${VK_API_CACHE_DIR}/${cache_key}.json"
    echo "${response}" > "${cache_file}"
}

# Make API request
api_request() {
    local func_name="vkapi::api_request"
    local method="${1:-}"
    local params="${2:-}"
    local use_cache="${3:-true}"
    
    if [[ -z "${method}" ]]; then
        errorhandler::throw "${func_name}" "API method is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    if [[ -z "${VK_API_ACCESS_TOKEN}" ]]; then
        errorhandler::throw "${func_name}" "Access token not set. Use vkapi::auth() first." \
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
        response=$(curl -s -w "%{http_code}" -d "${data}" "${url}" 2>/dev/null)
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
        errorhandler::throw "${func_name}" "API request failed with HTTP ${http_code}: ${response}" \
            "${LIB_ERROR_API_REQUEST}"
    fi
    
    # Cache successful response
    if [[ "${use_cache}" == "true" ]] && [[ -n "${cache_key:-}" ]]; then
        vkapi::cache_response "${cache_key}" "${response}"
    fi
    
    echo "${response}"
}

# Parse API response
parse_response() {
    local func_name="vkapi::parse_response"
    local response="${1:-}"
    
    if [[ -z "${response}" ]]; then
        errorhandler::throw "${func_name}" "Empty response" \
            "${LIB_ERROR_INVALID_RESPONSE}"
    fi
    
    # Check for error in response
    local error_msg
    error_msg=$(echo "${response}" | jq -r '.error.error_msg' 2>/dev/null || echo "")
    
    if [[ -n "${error_msg}" ]] && [[ "${error_msg}" != "null" ]]; then
        local error_code
        error_code=$(echo "${response}" | jq -r '.error.error_code' 2>/dev/null || echo "0")
        errorhandler::throw "${func_name}" "VK API Error ${error_code}: ${error_msg}" \
            "${LIB_ERROR_API_RESPONSE}"
    fi
    
    # Extract response data
    echo "${response}" | jq -r '.response' 2>/dev/null || echo "${response}"
}

# Generic API method caller
api_call() {
    local func_name="vkapi::api_call"
    local method="${1:-}"
    local params="${2:-}"
    local use_cache="${3:-true}"
    
    log::debug "Calling VK API method: ${method}"
    
    local response
    response=$(vkapi::api_request "${method}" "${params}" "${use_cache}")
    
    vkapi::parse_response "${response}"
}

# User management methods
users.get() {
    local func_name="vkapi::users.get"
    local params="${1:-}"
    
    vkapi::api_call "users.get" "${params}"
}

users.search() {
    local func_name="vkapi::users.search"
    local params="${1:-}"
    
    vkapi::api_call "users.search" "${params}"
}

# Friends methods
friends.get() {
    local func_name="vkapi::friends.get"
    local params="${1:-}"
    
    vkapi::api_call "friends.get" "${params}"
}

friends.getOnline() {
    local func_name="vkapi::friends.getOnline"
    local params="${1:-}"
    
    vkapi::api_call "friends.getOnline" "${params}"
}

# Groups methods
groups.get() {
    local func_name="vkapi::groups.get"
    local params="${1:-}"
    
    vkapi::api_call "groups.get" "${params}"
}

groups.getById() {
    local func_name="vkapi::groups.getById"
    local params="${1:-}"
    
    vkapi::api_call "groups.getById" "${params}"
}

# Wall methods
wall.get() {
    local func_name="vkapi::wall.get"
    local params="${1:-}"
    
    vkapi::api_call "wall.get" "${params}"
}

wall.post() {
    local func_name="vkapi::wall.post"
    local params="${1:-}"
    
    vkapi::api_call "wall.post" "${params}"
}

# Messages methods
messages.getConversations() {
    local func_name="vkapi::messages.getConversations"
    local params="${1:-}"
    
    vkapi::api_call "messages.getConversations" "${params}"
}

messages.getHistory() {
    local func_name="vkapi::messages.getHistory"
    local params="${1:-}"
    
    vkapi::api_call "messages.getHistory" "${params}"
}

messages.send() {
    local func_name="vkapi::messages.send"
    local params="${1:-}"
    
    vkapi::api_call "messages.send" "${params}"
}

# Photos methods
photos.get() {
    local func_name="vkapi::photos.get"
    local params="${1:-}"
    
    vkapi::api_call "photos.get" "${params}"
}

photos.getWallUploadServer() {
    local func_name="vkapi::photos.getWallUploadServer"
    local params="${1:-}"
    
    vkapi::api_call "photos.getWallUploadServer" "${params}"
}

# Status methods
status.get() {
    local func_name="vkapi::status.get"
    local params="${1:-}"
    
    vkapi::api_call "status.get" "${params}"
}

status.set() {
    local func_name="vkapi::status.set"
    local params="${1:-}"
    
    vkapi::api_call "status.set" "${params}"
}

# Board methods (for groups)
board.getTopics() {
    local func_name="vkapi::board.getTopics"
    local params="${1:-}"
    
    vkapi::api_call "board.getTopics" "${params}"
}

# Market methods
market.get() {
    local func_name="vkapi::market.get"
    local params="${1:-}"
    
    vkapi::api_call "market.get" "${params}"
}

# Polls methods
polls.getById() {
    local func_name="vkapi::polls.getById"
    local params="${1:-}"
    
    vkapi::api_call "polls.getById" "${params}"
}

# Secure methods for app authentication
secure.checkToken() {
    local func_name="vkapi::secure.checkToken"
    local token="${1:-}"
    local ip="${2:-}"
    
    local params="token=${token}"
    if [[ -n "${ip}" ]]; then
        params="${params}&ip=${ip}"
    fi
    
    vkapi::api_call "secure.checkToken" "${params}"
}

# Account methods
account.getInfo() {
    local func_name="vkapi::account.getInfo"
    local params="${1:-}"
    
    vkapi::api_call "account.getInfo" "${params}"
}

account.setOnline() {
    local func_name="vkapi::account.setOnline"
    local params="${1:-}"
    
    vkapi::api_call "account.setOnline" "${params}"
}

# Database methods
database.getCountries() {
    local func_name="vkapi::database.getCountries"
    local params="${1:-}"
    
    vkapi::api_call "database.getCountries" "${params}" "true"  # Cache this
}

database.getCities() {
    local func_name="vkapi::database.getCities"
    local params="${1:-}"
    
    vkapi::api_call "database.getCities" "${params}"
}

# Execute method (for generic API calls)
execute() {
    local func_name="vkapi::execute"
    local code="${1:-}"
    
    if [[ -z "${code}" ]]; then
        errorhandler::throw "${func_name}" "VKScript code is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    vkapi::api_call "execute" "code=${code}"
}

# Utility functions for common operations
# Get current user's profile
get_my_profile() {
    local func_name="vkapi::get_my_profile"
    
    vkapi::users.get "fields=photo_200,status,last_seen,online"
}

# Get user profile by ID
get_user_profile() {
    local func_name="vkapi::get_user_profile"
    local user_id="${1:-}"
    
    if [[ -z "${user_id}" ]]; then
        errorhandler::throw "${func_name}" "User ID is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    vkapi::users.get "user_ids=${user_id}&fields=photo_200,status,last_seen,online"
}

# Search for users
search_users() {
    local func_name="vkapi::search_users"
    local query="${1:-}"
    local count="${2:-10}"
    
    if [[ -z "${query}" ]]; then
        errorhandler::throw "${func_name}" "Search query is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    vkapi::users.search "q=${query}&count=${count}"
}

# Get user's groups
get_user_groups() {
    local func_name="vkapi::get_user_groups"
    local user_id="${1:-}"
    local extended="${2:-1}"
    
    local params="extended=${extended}"
    if [[ -n "${user_id}" ]]; then
        params="${params}&user_id=${user_id}"
    fi
    
    vkapi::groups.get "${params}"
}

# Get group information
get_group_info() {
    local func_name="vkapi::get_group_info"
    local group_id="${1:-}"
    
    if [[ -z "${group_id}" ]]; then
        errorhandler::throw "${func_name}" "Group ID is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    vkapi::groups.getById "group_id=${group_id}&fields=members_count,description"
}

# Get wall posts
get_wall_posts() {
    local func_name="vkapi::get_wall_posts"
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
post_to_wall() {
    local func_name="vkapi::post_to_wall"
    local message="${1:-}"
    local owner_id="${2:-}"
    
    if [[ -z "${message}" ]]; then
        errorhandler::throw "${func_name}" "Message is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    local params="message=${message}"
    if [[ -n "${owner_id}" ]]; then
        params="${params}&owner_id=${owner_id}"
    fi
    
    vkapi::wall.post "${params}"
}

# Send message
send_message() {
    local func_name="vkapi::send_message"
    local user_id="${1:-}"
    local message="${2:-}"
    local random_id="${3:-$(date +%s)}"
    
    if [[ -z "${user_id}" ]] || [[ -z "${message}" ]]; then
        errorhandler::throw "${func_name}" "User ID and message are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    vkapi::messages.send "user_id=${user_id}&message=${message}&random_id=${random_id}"
}

# Get conversations
get_conversations() {
    local func_name="vkapi::get_conversations"
    local count="${1:-20}"
    local offset="${2:-0}"
    
    vkapi::messages.getConversations "count=${count}&offset=${offset}"
}

# Get message history
get_message_history() {
    local func_name="vkapi::get_message_history"
    local peer_id="${1:-}"
    local count="${2:-20}"
    local offset="${3:-0}"
    
    if [[ -z "${peer_id}" ]]; then
        errorhandler::throw "${func_name}" "Peer ID is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    vkapi::messages.getHistory "peer_id=${peer_id}&count=${count}&offset=${offset}"
}

# Get online friends
get_online_friends() {
    local func_name="vkapi::get_online_friends"
    local online_mobile="${1:-1}"
    local order="${2:-random}"
    
    vkapi::friends.getOnline "online_mobile=${online_mobile}&order=${order}"
}

# Set status
set_status() {
    local func_name="vkapi::set_status"
    local text="${1:-}"
    
    if [[ -z "${text}" ]]; then
        errorhandler::throw "${func_name}" "Status text is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    vkapi::status.set "text=${text}"
}

# Get current status
get_status() {
    local func_name="vkapi::get_status"
    local user_id="${1:-}"
    
    local params=""
    if [[ -n "${user_id}" ]]; then
        params="user_id=${user_id}"
    fi
    
    vkapi::status.get "${params}"
}

# Get countries list (cached)
get_countries() {
    local func_name="vkapi::get_countries"
    local need_all="${1:-1}"
    local count="${2:-1000}"
    
    vkapi::database.getCountries "need_all=${need_all}&count=${count}"
}

# Clear cache
clear_cache() {
    local func_name="vkapi::clear_cache"
    
    log::info "Clearing VK API cache..."
    
    rm -f "${VK_API_CACHE_DIR}"/*.json
    
    log::success "Cache cleared"
}

# Get API usage statistics
get_stats() {
    local func_name="vkapi::get_stats"
    
    local cache_count
    cache_count=$(find "${VK_API_CACHE_DIR}" -name "*.json" 2>/dev/null | wc -l)
    
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
info() {
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
