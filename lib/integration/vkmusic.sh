#!/usr/bin/env bs
# shellcheck disable=SC2155

# vkmusic.sh — VK Music Integration Module for BS Framework
# Модуль интеграции VK Music для фреймворка BS
#
# Description:
#   Provides comprehensive VK Music functionality including audio search,
#   playlist management, downloads, and recommendations.
#   Предоставляет комплексную функциональность VK Music, включая поиск аудио,
#   управление плейлистами, загрузки и рекомендации.
#
# Features:
#   - Audio search and discovery
#   - Playlist creation and management
#   - Audio file downloads
#   - Recommendations and popular tracks
#   - Lyrics retrieval
#   - Audio metadata extraction
#   - Batch operations
#   - Integration with VK API
#
# Dependencies:
#   - curl (for HTTP requests)
#   - jq (for JSON parsing)
#   - ffmpeg (for audio processing)
#   - id3tag (for metadata tagging)
#   - vkapi.sh module
#
# Usage:
#   source "${BS_HOME}/boot.sh"
#   BS::init
#   vkmusic::init
#   vkmusic::search "artist song"
#   vkmusic::download "audio_id" "/path/to/save"
#
# @author BS Framework
# @since 2026-01-06
# @version 1.0.0
# @depends core/const, core/logger, core/utils, core/errorhandler, lib/system/platformcheck, lib/integration/vkapi

# Source Guard / Защита от повторной загрузки
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/guard.sh"
bs::guard "INTEGRATION_VK_MUSIC" || return 0

# Зависимости / Dependencies
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/const.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/logger.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/utils.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/errorhandler.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/../system/platformcheck.sh"
source "$(dirname -- "${BASH_SOURCE[0]}")/vkapi.sh"

# VK Music configuration constants
readonly VK_MUSIC_CACHE_DIR="/tmp/vk_music_cache"
readonly VK_MUSIC_DOWNLOAD_DIR="${HOME}/Music/VK"
readonly VK_MUSIC_PLAYLIST_DIR="${HOME}/.config/vkmusic/playlists"
readonly VK_MUSIC_MAX_DOWNLOAD_SIZE="100M"
readonly VK_MUSIC_MAX_DURATION="3600"  # 1 hour in seconds
readonly VK_MUSIC_QUALITY="high"  # high, medium, low

# Module state variables
VK_MUSIC_USER_ID=""
VK_MUSIC_ACCESS_TOKEN=""
VK_MUSIC_LAST_SEARCH_RESULTS=()

# Module initialization
vkmusic::init() {
    local func_name="vkmusic::init"
    
    log::info "Initializing VK Music module..."
    
    # Check dependencies
    vkmusic::check_dependencies
    
    # Create necessary directories
    mkdir -p "${VK_MUSIC_CACHE_DIR}" || {
        errorhandler::throw "${func_name}" "Failed to create cache directory" \
            "${LIB_ERROR_FILE_OPERATION}"
    }
    
    mkdir -p "${VK_MUSIC_DOWNLOAD_DIR}" || {
        errorhandler::throw "${func_name}" "Failed to create download directory" \
            "${LIB_ERROR_FILE_OPERATION}"
    }
    
    mkdir -p "${VK_MUSIC_PLAYLIST_DIR}" || {
        errorhandler::throw "${func_name}" "Failed to create playlist directory" \
            "${LIB_ERROR_FILE_OPERATION}"
    }
    
    log::success "VK Music module initialized successfully"
}

# Check VK Music dependencies
vkmusic::check_dependencies() {
    local func_name="vkmusic::check_dependencies"
    local missing_deps=()
    
    log::debug "Checking VK Music dependencies..."
    
    # Check for curl
    if ! utils::has curl; then
        missing_deps+=("curl")
    fi
    
    # Check for jq
    if ! utils::has jq; then
        missing_deps+=("jq")
    fi
    
    # Check for ffmpeg
    if ! utils::has ffmpeg; then
        missing_deps+=("ffmpeg")
    fi
    
    # Check for id3tag
    if ! utils::has id3tag && ! utils::has eyeD3; then
        missing_deps+=("id3tag")
    fi
    
    # Install missing dependencies based on platform
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log::warn "Missing dependencies: ${missing_deps[*]}"
        vkmusic::install_dependencies "${missing_deps[@]}"
    else
        log::debug "All dependencies are installed"
    fi
}

# Install missing dependencies
vkmusic::install_dependencies() {
    local func_name="vkmusic::install_dependencies"
    local deps=("$@")
    
    log::info "Installing missing dependencies: ${deps[*]}..."
    
    if platformcheck::is_debian || platformcheck::is_ubuntu; then
        apt-get update
        apt-get install -y curl jq ffmpeg eyed3
    elif platformcheck::is_alma || platformcheck::is_fedora; then
        dnf install -y curl jq ffmpeg eyed3
    elif platformcheck::is_macos; then
        if ! utils::has brew; then
            errorhandler::throw "${func_name}" "Homebrew is required for macOS" \
                "${LIB_ERROR_DEPENDENCY_MISSING}"
        fi
        brew install curl jq ffmpeg eye-d3
    else
        errorhandler::throw "${func_name}" "Unsupported platform for dependency installation" \
            "${LIB_ERROR_PLATFORM_UNSUPPORTED}"
    fi
    
    log::success "Dependencies installed successfully"
}

# Authenticate with VK API
vkmusic::auth() {
    local func_name="vkmusic::auth"
    local access_token="${1:-}"
    local user_id="${2:-}"
    
    if [[ -z "${access_token}" ]]; then
        errorhandler::throw "${func_name}" "Access token is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    VK_MUSIC_ACCESS_TOKEN="${access_token}"
    VK_MUSIC_USER_ID="${user_id}"
    
    # Initialize VK API module
    vkapi::init "${VK_MUSIC_APP_ID:-}" "${VK_MUSIC_APP_SECRET:-}"
    vkapi::auth "${access_token}"
    
    log::info "VK Music authentication configured"
}

# Search for audio tracks
vkmusic::search() {
    local func_name="vkmusic::search"
    local query="${1:-}"
    local count="${2:-10}"
    local offset="${3:-0}"
    
    if [[ -z "${query}" ]]; then
        errorhandler::throw "${func_name}" "Search query is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Searching for: ${query}"
    
    # Make API request
    local params="q=${query}&count=${count}&offset=${offset}&search_own=0"
    local response
    response=$(vkapi::api_call "audio.search" "${params}")
    
    if [[ -z "${response}" ]]; then
        errorhandler::throw "${func_name}" "Empty response from API" \
            "${LIB_ERROR_INVALID_RESPONSE}"
    fi
    
    # Parse and store results
    local audio_count
    audio_count=$(echo "${response}" | utils::quiet_err jq -r '.count' || echo "0")
    
    if [[ "${audio_count}" == "0" ]] || [[ "${audio_count}" == "null" ]]; then
        log::warn "No audio found for query: ${query}"
        return 1
    fi
    
    # Store results in array
    VK_MUSIC_LAST_SEARCH_RESULTS=()
    while IFS= read -r audio_info; do
        VK_MUSIC_LAST_SEARCH_RESULTS+=("${audio_info}")
    done < <(echo "${response}" | utils::quiet_err jq -c '.items[]')
    
    log::success "Found ${audio_count} audio tracks"
    
    # Display results
    vkmusic::display_search_results
    
    echo "${response}"
}

# Display search results
vkmusic::display_search_results() {
    local func_name="vkmusic::display_search_results"
    
    if [[ ${#VK_MUSIC_LAST_SEARCH_RESULTS[@]} -eq 0 ]]; then
        log::warn "No search results to display"
        return 1
    fi
    
    log::info "Search Results:"
    
    local index=1
    for audio_info in "${VK_MUSIC_LAST_SEARCH_RESULTS[@]}"; do
        local artist
        artist=$(echo "${audio_info}" | utils::quiet_err jq -r '.artist' || echo "Unknown")
        
        local title
        title=$(echo "${audio_info}" | utils::quiet_err jq -r '.title' || echo "Unknown")
        
        local duration
        duration=$(echo "${audio_info}" | utils::quiet_err jq -r '.duration' || echo "0")
        
        local id
        id=$(echo "${audio_info}" | utils::quiet_err jq -r '.id' || echo "")
        
        local owner_id
        owner_id=$(echo "${audio_info}" | utils::quiet_err jq -r '.owner_id' || echo "")
        
        # Format duration
        local duration_formatted
        duration_formatted=$(printf "%02d:%02d" $((duration / 60)) $((duration % 60)))
        
        echo "  ${index}. ${artist} - ${title} [${duration_formatted}] (ID: ${owner_id}_${id})"
        ((index++))
    done
}

# Get audio by ID
vkmusic::get_audio() {
    local func_name="vkmusic::get_audio"
    local owner_id="${1:-}"
    local audio_id="${2:-}"
    
    if [[ -z "${owner_id}" ]] || [[ -z "${audio_id}" ]]; then
        errorhandler::throw "${func_name}" "Owner ID and audio ID are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Getting audio: ${owner_id}_${audio_id}"
    
    local params="audios=${owner_id}_${audio_id}"
    local response
    response=$(vkapi::api_call "audio.getById" "${params}")
    
    echo "${response}"
}

# Get user's audio
vkmusic::get_user_audio() {
    local func_name="vkmusic::get_user_audio"
    local user_id="${1:-}"
    local count="${2:-100}"
    local offset="${3:-0}"
    
    if [[ -z "${user_id}" ]]; then
        errorhandler::throw "${func_name}" "User ID is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Getting audio for user: ${user_id}"
    
    local params="owner_id=${user_id}&count=${count}&offset=${offset}"
    local response
    response=$(vkapi::api_call "audio.get" "${params}")
    
    echo "${response}"
}

# Get recommendations
vkmusic::get_recommendations() {
    local func_name="vkmusic::get_recommendations"
    local user_id="${1:-}"
    local count="${2:-20}"
    
    log::info "Getting music recommendations..."
    
    local params="count=${count}"
    if [[ -n "${user_id}" ]]; then
        params="${params}&user_id=${user_id}"
    fi
    
    local response
    response=$(vkapi::api_call "audio.getRecommendations" "${params}")
    
    echo "${response}"
}

# Get popular tracks
vkmusic::get_popular() {
    local func_name="vkmusic::get_popular"
    local genre_id="${1:-}"
    local count="${2:-20}"
    
    log::info "Getting popular tracks..."
    
    local params="count=${count}"
    if [[ -n "${genre_id}" ]]; then
        params="${params}&genre_id=${genre_id}"
    fi
    
    local response
    response=$(vkapi::api_call "audio.getPopular" "${params}")
    
    echo "${response}"
}

# Get audio genres
vkmusic::get_genres() {
    local func_name="vkmusic::get_genres"
    
    log::info "Getting audio genres..."
    
    local response
    response=$(vkapi::api_call "audio.getGenres")
    
    echo "${response}"
}

# Add audio to user page
vkmusic::add_audio() {
    local func_name="vkmusic::add_audio"
    local owner_id="${1:-}"
    local audio_id="${2:-}"
    
    if [[ -z "${owner_id}" ]] || [[ -z "${audio_id}" ]]; then
        errorhandler::throw "${func_name}" "Owner ID and audio ID are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Adding audio to user page: ${owner_id}_${audio_id}"
    
    local params="audio_id=${audio_id}&owner_id=${owner_id}"
    local response
    response=$(vkapi::api_call "audio.add" "${params}")
    
    log::success "Audio added successfully"
    echo "${response}"
}

# Delete audio
vkmusic::delete_audio() {
    local func_name="vkmusic::delete_audio"
    local owner_id="${1:-}"
    local audio_id="${2:-}"
    
    if [[ -z "${owner_id}" ]] || [[ -z "${audio_id}" ]]; then
        errorhandler::throw "${func_name}" "Owner ID and audio ID are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Deleting audio: ${owner_id}_${audio_id}"
    
    local params="audio_id=${audio_id}&owner_id=${owner_id}"
    local response
    response=$(vkapi::api_call "audio.delete" "${params}")
    
    log::success "Audio deleted successfully"
    echo "${response}"
}

# Create playlist
vkmusic::create_playlist() {
    local func_name="vkmusic::create_playlist"
    local title="${1:-}"
    local description="${2:-}"
    
    if [[ -z "${title}" ]]; then
        errorhandler::throw "${func_name}" "Playlist title is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Creating playlist: ${title}"
    
    local params="title=${title}"
    if [[ -n "${description}" ]]; then
        params="${params}&description=${description}"
    fi
    
    local response
    response=$(vkapi::api_call "audio.createPlaylist" "${params}")
    
    log::success "Playlist created successfully"
    echo "${response}"
}

# Get user's playlists
vkmusic::get_playlists() {
    local func_name="vkmusic::get_playlists"
    local user_id="${1:-}"
    local count="${2:-50}"
    local offset="${3:-0}"
    
    log::info "Getting playlists..."
    
    local params="count=${count}&offset=${offset}"
    if [[ -n "${user_id}" ]]; then
        params="${params}&owner_id=${user_id}"
    fi
    
    local response
    response=$(vkapi::api_call "audio.getPlaylists" "${params}")
    
    echo "${response}"
}

# Download audio file
vkmusic::download() {
    local audio_info="${1:-}"
    local output_dir="${2:-${VK_MUSIC_DOWNLOAD_DIR}}"
    local filename="${3:-}"
    
    if [[ -z "${audio_info}" ]]; then
        errorhandler::throw "${func_name}" "Audio information is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    # Get audio info if it's an ID
    if [[ "${audio_info}" =~ ^-?[0-9]+_[0-9]+$ ]]; then
        local owner_id
        owner_id=$(echo "${audio_info}" | cut -d'_' -f1)
        local audio_id
        audio_id=$(echo "${audio_info}" | cut -d'_' -f2)
        
        local audio_data
        audio_data=$(vkmusic::get_audio "${owner_id}" "${audio_id}")
        
        if [[ -z "${audio_data}" ]]; then
            errorhandler::throw "${func_name}" "Failed to get audio information" \
                "${LIB_ERROR_API_RESPONSE}"
        fi
        
        audio_info="${audio_data}"
    fi
    
    # Extract audio information
    local artist
    artist=$(echo "${audio_info}" | utils::quiet_err jq -r '.artist' || echo "Unknown")
    
    local title
    title=$(echo "${audio_info}" | utils::quiet_err jq -r '.title' || echo "Unknown")
    
    local url
    url=$(echo "${audio_info}" | utils::quiet_err jq -r '.url' || echo "")
    
    local duration
    duration=$(echo "${audio_info}" | utils::quiet_err jq -r '.duration' || echo "0")
    
    local owner_id
    owner_id=$(echo "${audio_info}" | utils::quiet_err jq -r '.owner_id' || echo "")
    
    local id
    id=$(echo "${audio_info}" | utils::quiet_err jq -r '.id' || echo "")
    
    if [[ -z "${url}" ]]; then
        errorhandler::throw "${func_name}" "Audio URL not found" \
            "${LIB_ERROR_INVALID_RESPONSE}"
    fi
    
    # Generate filename if not provided
    if [[ -z "${filename}" ]]; then
        filename="${artist} - ${title}.mp3"
        # Clean filename
        filename=$(echo "${filename}" | sed 's/[^a-zA-Z0-9._-]/_/g')
    fi
    
    local output_file="${output_dir}/${filename}"
    
    log::info "Downloading: ${artist} - ${title}"
    log::debug "URL: ${url}"
    log::debug "Output: ${output_file}"
    
    # Download audio file
    curl -L -s -o "${output_file}" --max-filesize "${VK_MUSIC_MAX_DOWNLOAD_SIZE}" \
        --connect-timeout 30 --max-time 300 "${url}" || {
        errorhandler::throw "${func_name}" "Failed to download audio file" \
            "${LIB_ERROR_DOWNLOAD_FAILED}"
    }
    
    # Add metadata if file was downloaded successfully
    if [[ -f "${output_file}" ]]; then
        vkmusic::add_metadata "${output_file}" "${artist}" "${title}" "${duration}"
        log::success "Downloaded: ${filename}"
    fi
    
    echo "${output_file}"
}

# Add metadata to audio file
vkmusic::add_metadata() {
    local func_name="vkmusic::add_metadata"
    local file="${1:-}"
    local artist="${2:-}"
    local title="${3:-}"
    local duration="${4:-}"
    
    if [[ ! -f "${file}" ]]; then
        errorhandler::throw "${func_name}" "File not found: ${file}" \
            "${LIB_ERROR_FILE_NOT_FOUND}"
    fi
    
    log::debug "Adding metadata to: ${file}"
    
    # Use eyeD3 if available, otherwise try id3tag
    if utils::has eyeD3; then
        utils::quiet eyeD3 --artist="${artist}" --title="${title}" "${file}"
    elif utils::has id3tag; then
        utils::quiet id3tag --artist="${artist}" --title="${title}" "${file}"
    else
        log::warn "No ID3 tagger found, skipping metadata"
    fi
}

# Batch download
vkmusic::batch_download() {
    local func_name="vkmusic::batch_download"
    local audio_list="${1:-}"
    local output_dir="${2:-${VK_MUSIC_DOWNLOAD_DIR}}"
    
    if [[ -z "${audio_list}" ]]; then
        errorhandler::throw "${func_name}" "Audio list is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Starting batch download..."
    
    local downloaded_count=0
    local failed_count=0
    
    # Process each audio
    while IFS= read -r audio_info; do
        if [[ -n "${audio_info}" ]]; then
            if vkmusic::download "${audio_info}" "${output_dir}"; then
                ((downloaded_count++))
            else
                ((failed_count++))
            fi
        fi
    done <<< "${audio_list}"
    
    log::info "Batch download completed: ${downloaded_count} succeeded, ${failed_count} failed"
}

# Search and download
vkmusic::search_and_download() {
    local func_name="vkmusic::search_and_download"
    local query="${1:-}"
    local count="${2:-5}"
    local output_dir="${3:-${VK_MUSIC_DOWNLOAD_DIR}}"
    
    if [[ -z "${query}" ]]; then
        errorhandler::throw "${func_name}" "Search query is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Searching and downloading: ${query}"
    
    # Search for audio
    local search_results
    search_results=$(vkmusic::search "${query}" "${count}")
    
    if [[ -z "${search_results}" ]]; then
        log::warn "No results found for: ${query}"
        return 1
    fi
    
    # Download found audio
    local audio_items
    audio_items=$(echo "${search_results}" | utils::quiet_err jq -c '.items[]')
    
    if [[ -n "${audio_items}" ]]; then
        vkmusic::batch_download "${audio_items}" "${output_dir}"
    fi
}

# Get lyrics
vkmusic::get_lyrics() {
    local func_name="vkmusic::get_lyrics"
    local owner_id="${1:-}"
    local audio_id="${2:-}"
    
    if [[ -z "${owner_id}" ]] || [[ -z "${audio_id}" ]]; then
        errorhandler::throw "${func_name}" "Owner ID and audio ID are required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Getting lyrics for: ${owner_id}_${audio_id}"
    
    local params="owner_id=${owner_id}&audio_id=${audio_id}"
    local response
    response=$(vkapi::api_call "audio.getLyrics" "${params}")
    
    echo "${response}"
}

# Create playlist file
vkmusic::create_playlist_file() {
    local func_name="vkmusic::create_playlist_file"
    local playlist_name="${1:-}"
    local audio_ids="${2:-}"
    local format="${3:-m3u}"  # m3u, pls, xspf
    
    if [[ -z "${playlist_name}" ]]; then
        errorhandler::throw "${func_name}" "Playlist name is required" \
            "${LIB_ERROR_INVALID_ARGS}"
    fi
    
    log::info "Creating playlist: ${playlist_name}"
    
    local playlist_file="${VK_MUSIC_PLAYLIST_DIR}/${playlist_name}.${format}"
    
    case "${format}" in
        m3u)
            echo "#EXTM3U" > "${playlist_file}"
            while IFS= read -r audio_id; do
                if [[ -n "${audio_id}" ]]; then
                    echo "#EXTINF:0,${audio_id}" >> "${playlist_file}"
                    echo "${audio_id}" >> "${playlist_file}"
                fi
            done <<< "${audio_ids}"
            ;;
        pls)
            echo "[playlist]" > "${playlist_file}"
            local count=0
            while IFS= read -r audio_id; do
                if [[ -n "${audio_id}" ]]; then
                    ((count++))
                    echo "File${count}=${audio_id}" >> "${playlist_file}"
                    echo "Title${count}=${audio_id}" >> "${playlist_file}"
                    echo "Length${count}=-1" >> "${playlist_file}"
                fi
            done <<< "${audio_ids}"
            echo "NumberOfEntries=${count}" >> "${playlist_file}"
            echo "Version=2" >> "${playlist_file}"
            ;;
        *)
            log::warn "Unsupported playlist format: ${format}"
            return 1
            ;;
    esac
    
    log::success "Playlist created: ${playlist_file}"
    echo "${playlist_file}"
}

# Get audio count
vkmusic::get_audio_count() {
    local func_name="vkmusic::get_audio_count"
    local user_id="${1:-}"
    
    log::info "Getting audio count..."
    
    local params="owner_id=${user_id}&count=1"
    local response
    response=$(vkapi::api_call "audio.get" "${params}")
    
    local count
    count=$(echo "${response}" | utils::quiet_err jq -r '.count' || echo "0")
    
    echo "${count}"
}

# Get audio upload server
vkmusic::get_upload_server() {
    local func_name="vkmusic::get_upload_server"
    
    log::info "Getting audio upload server..."
    
    local response
    response=$(vkapi::api_call "audio.getUploadServer")
    
    echo "${response}"
}

# Upload audio file
vkmusic::upload_audio() {
    local func_name="vkmusic::upload_audio"
    local file_path="${1:-}"
    local title="${2:-}"
    local artist="${3:-}"
    
    if [[ ! -f "${file_path}" ]]; then
        errorhandler::throw "${func_name}" "File not found: ${file_path}" \
            "${LIB_ERROR_FILE_NOT_FOUND}"
    fi
    
    log::info "Uploading audio: ${file_path}"
    
    # Get upload server
    local upload_server_response
    upload_server_response=$(vkmusic::get_upload_server)
    
    local upload_url
    upload_url=$(echo "${upload_server_response}" | utils::quiet_err jq -r '.upload_url')
    
    if [[ -z "${upload_url}" ]] || [[ "${upload_url}" == "null" ]]; then
        errorhandler::throw "${func_name}" "Failed to get upload server" \
            "${LIB_ERROR_API_RESPONSE}"
    fi
    
    # Upload file
    local upload_response
    upload_response=$(curl -s -F "file=@${file_path}" "${upload_url}")
    
    # Save audio
    local server
    server=$(echo "${upload_response}" | utils::quiet_err jq -r '.server')
    local audio_hash
    audio_hash=$(echo "${upload_response}" | utils::quiet_err jq -r '.audio')
    local hash
    hash=$(echo "${upload_response}" | utils::quiet_err jq -r '.hash')
    
    local params="server=${server}&audio=${audio_hash}&hash=${hash}"
    if [[ -n "${title}" ]]; then
        params="${params}&title=${title}"
    fi
    if [[ -n "${artist}" ]]; then
        params="${params}&artist=${artist}"
    fi
    
    local save_response
    save_response=$(vkapi::api_call "audio.save" "${params}")
    
    log::success "Audio uploaded successfully"
    echo "${save_response}"
}

# Clear cache
vkmusic::clear_cache() {
    local func_name="vkmusic::clear_cache"
    
    log::info "Clearing VK Music cache..."
    
    rm -f "${VK_MUSIC_CACHE_DIR}"/*
    
    log::success "Cache cleared"
}

# Get statistics
vkmusic::get_stats() {
    local func_name="vkmusic::get_stats"
    
    local download_count
    download_count=$(utils::quiet_err find "${VK_MUSIC_DOWNLOAD_DIR}" -name "*.mp3" | wc -l)
    
    local playlist_count
    playlist_count=$(utils::quiet_err find "${VK_MUSIC_PLAYLIST_DIR}" -name "*.m3u" -o -name "*.pls" | wc -l)
    
    local cache_size
    cache_size=$(utils::quiet_err du -sh "${VK_MUSIC_CACHE_DIR}" | cut -f1 || echo "0")
    
    cat << EOF
VK Music Statistics:
  Download directory: ${VK_MUSIC_DOWNLOAD_DIR}
  Downloaded tracks: ${download_count}
  Playlists created: ${playlist_count}
  Cache size: ${cache_size}
  Quality: ${VK_MUSIC_QUALITY}
  Max download size: ${VK_MUSIC_MAX_DOWNLOAD_SIZE}
EOF
}

# Module info
vkmusic::info() {
    cat << EOF
VK Music Integration Module v1.0.0

Available functions:
  vkmusic::init                    - Initialize module
  vkmusic::auth                    - Authenticate with VK API
  vkmusic::search                  - Search for audio tracks
  vkmusic::get_audio               - Get audio by ID
  vkmusic::get_user_audio          - Get user's audio
  vkmusic::get_recommendations     - Get music recommendations
  vkmusic::get_popular             - Get popular tracks
  vkmusic::get_genres              - Get audio genres
  vkmusic::add_audio               - Add audio to user page
  vkmusic::delete_audio            - Delete audio
  vkmusic::create_playlist         - Create playlist
  vkmusic::get_playlists           - Get user's playlists
  vkmusic::download                - Download audio file
  vkmusic::add_metadata            - Add metadata to audio file
  vkmusic::batch_download          - Batch download audio files
  vkmusic::search_and_download     - Search and download tracks
  vkmusic::get_lyrics              - Get audio lyrics
  vkmusic::create_playlist_file    - Create playlist file
  vkmusic::get_audio_count         - Get audio count
  vkmusic::upload_audio            - Upload audio file
  vkmusic::clear_cache             - Clear cache
  vkmusic::get_stats               - Get statistics

Configuration:
  Download directory: ${VK_MUSIC_DOWNLOAD_DIR}
  Playlist directory: ${VK_MUSIC_PLAYLIST_DIR}
  Cache directory: ${VK_MUSIC_CACHE_DIR}
  Quality: ${VK_MUSIC_QUALITY}
  Max download size: ${VK_MUSIC_MAX_DOWNLOAD_SIZE}

Dependencies:
  curl, jq, ffmpeg, eyeD3/id3tag
EOF
}
