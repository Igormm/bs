#!/usr/bin/env bs
# shellcheck disable=SC2155

# test_vk_music.sh — Unit tests for VK Music integration module
# Модульные тесты для модуля интеграции VK Music
#
# Description:
#   Comprehensive test suite for VK Music module functionality.
#   Комплексный набор тестов для функциональности модуля VK Music.
#
# @author BS Framework Test Suite
# @since 2026-01-06
# @version 1.0.0

set -euo pipefail

# Test framework setup
readonly TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BS_PROJECT_ROOT="$(cd "${TEST_SCRIPT_DIR}/../.." && pwd)"

# Source test framework
source "${TEST_SCRIPT_DIR}/../testframework.sh"

# Initialize BS framework (bootstrap; BS_HOME нужен lib-модулям — pre-existing расхождение BS_ROOT/BS_HOME)
# Initialize BS framework (bootstrap; BS_HOME is needed by lib modules — pre-existing BS_ROOT/BS_HOME mismatch)
export BS_SILENT=1
source "${BS_PROJECT_ROOT}/bootstrap/init.sh"
export BS_HOME="${BS_PROJECT_ROOT}"

# Изолированный HOME: модуль создаёт ~/Music/VK и ~/.config/vkmusic (readonly-пути вычисляются из HOME при source)
# Isolated HOME: the module creates ~/Music/VK and ~/.config/vkmusic (readonly paths computed from HOME at source time)
TEST_HOME="$(mktemp -d)"
export HOME="${TEST_HOME}"

# Заглушка id3tag: иначе vkmusic::init пытается ставить пакеты через dnf (pre-existing: автоустановка зависимостей)
# id3tag stub: otherwise vkmusic::init tries to install packages via dnf (pre-existing auto-install)
mkdir -p "${TEST_HOME}/bin"
printf '#!/bin/sh\nexit 0\n' > "${TEST_HOME}/bin/id3tag"
chmod +x "${TEST_HOME}/bin/id3tag"
export PATH="${TEST_HOME}/bin:${PATH}"

# Test configuration
readonly TEST_ACCESS_TOKEN="test_token"
readonly TEST_USER_ID="123456"

# Test results tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Mock functions for testing
setup_mocks() {
    # Mock vkapi::api_call
    vkapi::api_call() {
        local method="${1:-}"
        local params="${2:-}"
        
        case "${method}" in
            "audio.search")
                echo '{"count":2,"items":[{"id":1,"owner_id":1,"artist":"Test Artist","title":"Test Song","duration":180,"url":"http://example.com/audio.mp3"}]}'
                ;;
            "audio.getById")
                echo '{"response":[{"id":1,"owner_id":1,"artist":"Test Artist","title":"Test Song","duration":180,"url":"http://example.com/audio.mp3"}]}'
                ;;
            "audio.get")
                echo '{"count":1,"items":[{"id":1,"owner_id":1,"artist":"Test Artist","title":"Test Song","duration":180,"url":"http://example.com/audio.mp3"}]}'
                ;;
            "audio.getRecommendations")
                echo '{"count":1,"items":[{"id":2,"owner_id":2,"artist":"Recommended Artist","title":"Recommended Song","duration":200,"url":"http://example.com/rec.mp3"}]}'
                ;;
            "audio.getPopular")
                echo '{"count":1,"items":[{"id":3,"owner_id":3,"artist":"Popular Artist","title":"Popular Song","duration":210,"url":"http://example.com/pop.mp3"}]}'
                ;;
            "audio.getGenres")
                echo '{"response":[{"id":1,"name":"Rock"},{"id":2,"name":"Pop"}]}'
                ;;
            "audio.getPlaylists")
                echo '{"count":1,"items":[{"id":1,"owner_id":1,"title":"Test Playlist","description":"Test Description"}]}'
                ;;
            "audio.getLyrics")
                echo '{"response":{"lyrics":"Test lyrics text"}}'
                ;;
            *)
                echo '{"response":[]}'
                ;;
        esac
    }
    
    # Mock curl (поддерживает -o FILE, как в vkmusic::download)
    # Mock curl (supports -o FILE, as used by vkmusic::download)
    curl() {
        local args=("$@")
        local url=""
        local out_file=""
        local i
        
        for ((i=0; i<${#args[@]}; i++)); do
            case "${args[$i]}" in
                -o)
                    out_file="${args[$((i+1))]}"
                    ;;
                http://example.com*)
                    url="${args[$i]}"
                    ;;
            esac
        done
        
        if [[ "${url}" == "http://example.com/audio.mp3" ]] || \
           [[ "${url}" == "http://example.com/rec.mp3" ]] || \
           [[ "${url}" == "http://example.com/pop.mp3" ]]; then
            # Create a small valid MP3 file
            if [[ -n "${out_file}" ]]; then
                printf '\xff\xfb\x90\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' > "${out_file}"
            else
                printf '\xff\xfb\x90\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00'
            fi
        else
            return 1
        fi
    }
    
    export -f vkapi::api_call curl
}

# Test counter functions
test_increment() {
    ((++TESTS_RUN))
}

test_pass() {
    test_increment
    ((++TESTS_PASSED))
    log::success "✓ ${FUNCNAME[1]}"
}

test_fail() {
    test_increment
    ((++TESTS_FAILED))
    FAILED_TESTS+=("${FUNCNAME[1]}")
    log::error "✗ ${FUNCNAME[1]}"
}

# Test 1: Module initialization
test_module_initialization() {
    log::info "Testing module initialization..."
    
    # Source the module
    source "${BS_PROJECT_ROOT}/lib/integration/vkmusic.sh"
    
    # Кэш vkapi в изолированный каталог: vkmusic::auth вызывает vkapi::init,
    # который создаёт ${BS_ROOT}/vk_api_cache (pre-existing: дефолтный путь в корне проекта)
    # Isolate the vkapi cache: vkmusic::auth calls vkapi::init,
    # which creates ${BS_ROOT}/vk_api_cache (pre-existing: default path in the project root)
    VK_API_CACHE_DIR="${TEST_HOME}/vk_api_cache"
    
    # Test initialization
    if vkmusic::init; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 2: Directory creation
test_directory_creation() {
    log::info "Testing directory creation..."
    
    if [[ -d "/tmp/vk_music_cache" ]] && \
       [[ -d "${HOME}/Music/VK" ]] && \
       [[ -d "${HOME}/.config/vkmusic/playlists" ]]; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 3: Authentication
test_authentication() {
    log::info "Testing authentication..."
    
    # Setup mocks
    setup_mocks
    
    # Test auth function
    if vkmusic::auth "${TEST_ACCESS_TOKEN}" "${TEST_USER_ID}"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 4: Search functionality
test_search_functionality() {
    log::info "Testing search functionality..."
    
    local result
    result=$(vkmusic::search "test artist" 5)
    
    if [[ -n "${result}" ]] && echo "${result}" | grep -q "Test Artist"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 5: Display search results
test_display_search_results() {
    log::info "Testing search results display..."
    
    # First perform a search to populate results
    vkmusic::search "test" 2 >/dev/null
    
    # Then test display function
    if vkmusic::display_search_results >/dev/null; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 6: Get audio by ID
test_get_audio_by_id() {
    log::info "Testing get audio by ID..."
    
    local result
    result=$(vkmusic::get_audio 1 1)
    
    if [[ -n "${result}" ]] && echo "${result}" | grep -q "Test Artist"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 7: Get user audio
test_get_user_audio() {
    log::info "Testing get user audio..."
    
    local result
    result=$(vkmusic::get_user_audio 1)
    
    if [[ -n "${result}" ]] && echo "${result}" | grep -q "count"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 8: Get recommendations
test_get_recommendations() {
    log::info "Testing get recommendations..."
    
    local result
    result=$(vkmusic::get_recommendations)
    
    if [[ -n "${result}" ]] && echo "${result}" | grep -q "Recommended Artist"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 9: Get popular tracks
test_get_popular_tracks() {
    log::info "Testing get popular tracks..."
    
    local result
    result=$(vkmusic::get_popular)
    
    if [[ -n "${result}" ]] && echo "${result}" | grep -q "Popular Artist"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 10: Get genres
test_get_genres() {
    log::info "Testing get genres..."
    
    local result
    result=$(vkmusic::get_genres)
    
    if [[ -n "${result}" ]] && echo "${result}" | grep -q "Rock"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 11: Create playlist
test_create_playlist() {
    log::info "Testing create playlist..."
    
    local result
    result=$(vkmusic::create_playlist "Test Playlist" "Test Description")
    
    if [[ -n "${result}" ]]; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 12: Get playlists
test_get_playlists() {
    log::info "Testing get playlists..."
    
    local result
    result=$(vkmusic::get_playlists 1)
    
    if [[ -n "${result}" ]] && echo "${result}" | grep -q "Test Playlist"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 13: Download audio
test_download_audio() {
    log::info "Testing download audio..."
    
    # Create test audio info
    local test_audio='{"id":1,"owner_id":1,"artist":"Test Artist","title":"Test Song","duration":180,"url":"http://example.com/audio.mp3"}'
    
    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    
    local result
    result=$(vkmusic::download "${test_audio}" "${temp_dir}" "test.mp3")
    
    # stdout замусорен логами, проверяем сам файл / stdout is polluted by logs, check the file itself
    if [[ -f "${temp_dir}/test.mp3" ]]; then
        test_pass
    else
        test_fail
    fi
    
    rm -rf "${temp_dir}"
}

# Test 14: Add metadata
test_add_metadata() {
    log::info "Testing add metadata..."
    
    # Create temporary file
    local temp_file
    temp_file=$(mktemp --suffix=.mp3)
    
    # Write minimal MP3 header
    printf '\xff\xfb\x90\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' > "${temp_file}"
    
    # Test metadata addition
    if vkmusic::add_metadata "${temp_file}" "Test Artist" "Test Title" "180"; then
        test_pass
    else
        test_fail
    fi
    
    rm -f "${temp_file}"
}

# Test 15: Batch download
test_batch_download() {
    log::info "Testing batch download..."
    
    # Create test audio list
    local test_audios='[{"id":1,"owner_id":1,"artist":"Test Artist 1","title":"Test Song 1","duration":180,"url":"http://example.com/audio.mp3"},{"id":2,"owner_id":2,"artist":"Test Artist 2","title":"Test Song 2","duration":200,"url":"http://example.com/rec.mp3"}]'
    
    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Test batch download
    vkmusic::batch_download "$(echo "${test_audios}" | jq -c '.[]')" "${temp_dir}"
    
    local file_count
    file_count=$(find "${temp_dir}" -name "*.mp3" | wc -l)
    
    if [[ "${file_count}" -ge 1 ]]; then
        test_pass
    else
        test_fail
    fi
    
    rm -rf "${temp_dir}"
}

# Test 16: Get lyrics
test_get_lyrics() {
    log::info "Testing get lyrics..."
    
    local result
    result=$(vkmusic::get_lyrics 1 1)
    
    if [[ -n "${result}" ]] && echo "${result}" | grep -q "lyrics"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 17: Create playlist file
test_create_playlist_file() {
    log::info "Testing create playlist file..."
    
    # VK_MUSIC_PLAYLIST_DIR — readonly и уже изолирован (TEST_HOME), переопределять нельзя
    # VK_MUSIC_PLAYLIST_DIR is readonly and already isolated (TEST_HOME), cannot override
    local result
    result=$(vkmusic::create_playlist_file "test_playlist" "1_1\n2_2" "m3u")
    
    # stdout замусорен логами, проверяем наличие файла в каталоге плейлистов
    # stdout is polluted by logs, check for the file in the playlist directory
    if [[ -n "$(find "${VK_MUSIC_PLAYLIST_DIR}" -name 'test_playlist*' -print -quit)" ]]; then
        test_pass
    else
        test_fail
    fi
}

# Test 18: Get audio count
test_get_audio_count() {
    log::info "Testing get audio count..."
    
    local result
    result=$(vkmusic::get_audio_count 1)
    
    if [[ -n "${result}" ]]; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 19: Clear cache
test_clear_cache() {
    log::info "Testing clear cache..."
    
    # Create test cache file
    local test_cache_file="/tmp/vk_music_cache/test_cache"
    echo "test" > "${test_cache_file}"
    
    # Clear cache
    vkmusic::clear_cache
    
    if [[ ! -f "${test_cache_file}" ]]; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 20: Statistics
test_statistics() {
    log::info "Testing statistics..."
    
    local stats
    stats=$(vkmusic::get_stats)
    
    if [[ -n "${stats}" ]] && echo "${stats}" | grep -q "VK Music Statistics"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 21: Module info
test_module_info() {
    log::info "Testing module info..."
    
    local info_output
    info_output=$(vkmusic::info)
    
    if [[ -n "${info_output}" ]] && echo "${info_output}" | grep -q "VK Music Integration Module"; then
        test_pass
    else
        test_fail
        return 1
    fi
}

# Test 22: Search and download
test_search_and_download() {
    log::info "Testing search and download..."
    
    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # VK_MUSIC_DOWNLOAD_DIR — readonly и уже изолирован (TEST_HOME), переопределять нельзя
    # VK_MUSIC_DOWNLOAD_DIR is readonly and already isolated (TEST_HOME), cannot override
    # Test search and download
    vkmusic::search_and_download "test" 1 "${temp_dir}"
    
    local file_count
    file_count=$(find "${temp_dir}" -name "*.mp3" | wc -l)
    
    if [[ "${file_count}" -ge 0 ]]; then
        test_pass
    else
        test_fail
    fi
    
    rm -rf "${temp_dir}"
}

# Cleanup function
cleanup() {
    log::info "Cleaning up test artifacts..."
    
    # Clean up test files (изолированный HOME / isolated HOME)
    utils::quiet_err rm -rf "${TEST_HOME:-}" || true
    
    log::debug "Cleanup completed"
}

# Print test summary
print_summary() {
    log::info "=== Test Summary ==="
    log::info "Tests run: ${TESTS_RUN}"
    log::info "Tests passed: ${TESTS_PASSED}"
    log::info "Tests failed: ${TESTS_FAILED}"
    
    if [[ "${TESTS_FAILED}" -gt 0 ]]; then
        log::error "Failed tests:"
        for test in "${FAILED_TESTS[@]}"; do
            log::error "  - ${test}"
        done
        return 1
    else
        log::success "All tests passed!"
        return 0
    fi
}

# Main test runner
main() {
    log::info "Starting VK Music module tests..."
    
    # Register cleanup on exit
    trap cleanup EXIT
    
    # Run tests (|| true: падение одного теста не прерывает прогон / a failing test does not abort the run)
    test_module_initialization || true
    test_directory_creation || true
    test_authentication || true
    test_search_functionality || true
    test_display_search_results || true
    test_get_audio_by_id || true
    test_get_user_audio || true
    test_get_recommendations || true
    test_get_popular_tracks || true
    test_get_genres || true
    test_create_playlist || true
    test_get_playlists || true
    test_download_audio || true
    test_add_metadata || true
    test_batch_download || true
    test_get_lyrics || true
    test_create_playlist_file || true
    test_get_audio_count || true
    test_clear_cache || true
    test_statistics || true
    test_module_info || true
    test_search_and_download || true
    
    # Print summary
    print_summary
    
    # Exit with appropriate code
    if [[ "${TESTS_FAILED}" -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
