#!/usr/bin/env bs
# shellcheck shell=bash
# lib/integration/vkmusic_tui.sh — full-screen VK Music client on lib/tui/app
# lib/integration/vkmusic_tui.sh — полноэкранный клиент VK Music на lib/tui/app
#
# Треки — объекты vkmusic_track (core/object.sh), списки кешируются core/cache.sh.
# Клавиши / Keys: ↑↓/jk выбор, ENTER скачать, / поиск, r рекомендации, p популярное,
# u моя музыка, i информация, q выход.
# Tracks are vkmusic_track objects (core/object.sh); the list endpoints are cached
# via core/cache.sh. Keys: ↑↓/jk select, ENTER download, / search, r recommendations,
# p popular, u my music, i info, q quit.
# @depends core/logger, core/utils, lib/tui/app, lib/integration/vkmusic

bs::guard "INTEGRATION_VK_MUSIC_TUI" || return 0

bs::source_relative "../../core/logger.sh" "../../core/utils.sh" "../tui/app.sh" "vkmusic.sh"

# @global VKM_SEL — VkMusicTUI: selected track index (0-based) (category: state)
# @global VKM_SEL — VkMusicTUI: индекс выбранного трека (с нуля) (категория: state)
declare -gi VKM_SEL=0
# @global VKM_BASE — VkMusicTUI: first visible index (category: state)
# @global VKM_BASE — VkMusicTUI: индекс первого видимого элемента (категория: state)
declare -gi VKM_BASE=0
# @global VKM_MODE — VkMusicTUI: list mode: search|reco|popular|user (category: state)
# @global VKM_MODE — VkMusicTUI: режим списка: search|reco|popular|user (категория: state)
VKM_MODE=""
# @global VKM_QUERY — VkMusicTUI: last search query (category: state)
# @global VKM_QUERY — VkMusicTUI: последний поисковый запрос (категория: state)
VKM_QUERY=""

# @private Число треков / The number of tracks
vkm_tui::__total() {
    local n
    n="$(vkmusic::track_count 2>/dev/null || echo 0)"
    [[ "${n}" =~ ^[0-9]+$ ]] && printf '%s\n' "${n}" || printf '0\n'
}

# @private Обновить выбор в границах видимого списка / Clamp the selection into the viewport
vkm_tui::__clamp() {
    local -i total page
    total="$(vkm_tui::__total)"
    if (( total == 0 )); then
        VKM_SEL=0; VKM_BASE=0
        return 0
    fi
    (( VKM_SEL >= total )) && VKM_SEL=$(( total - 1 ))
    (( VKM_SEL < 0 )) && VKM_SEL=0
    page=$(( TUI_LINES - 9 ))
    (( page < 1 )) && page=1
    if (( VKM_SEL < VKM_BASE )); then VKM_BASE=$(( VKM_SEL )); fi
    if (( VKM_SEL >= VKM_BASE + page )); then VKM_BASE=$(( VKM_SEL - page + 1 )); fi
    (( VKM_BASE < 0 )) && VKM_BASE=0
    return 0
}

# @private Переместить выбор / Move the selection
# @param $1 delta / сдвиг
vkm_tui::__move() {
    VKM_SEL=$(( VKM_SEL + ${1:?delta required} ))
    vkm_tui::__clamp
}

# @private Страница вниз/вверх / A page down/up
# @param $1 down|up / направление
vkm_tui::__page() {
    local -i page=$(( TUI_LINES - 9 ))
    (( page < 1 )) && page=1
    if [[ "${1:-}" == down ]]; then VKM_SEL=$(( VKM_SEL + page )); else VKM_SEL=$(( VKM_SEL - page )); fi
    vkm_tui::__clamp
}

# @private Загрузить список по режиму / Load the list for the mode
vkm_tui::__load() {
    case "${VKM_MODE}" in
        search)  vkmusic::search "${VKM_QUERY:-pop}" 50 >/dev/null 2>&1 || : ;;
        reco)    vkmusic::get_recommendations "" 50 >/dev/null 2>&1 || : ;;
        popular) vkmusic::get_popular "" 50 >/dev/null 2>&1 || : ;;
        user)    vkmusic::get_user_audio "${VK_MUSIC_USER_ID:-}" 50 >/dev/null 2>&1 || : ;;
    esac
    VKM_SEL=0; VKM_BASE=0
    vkm_tui::__clamp
    return 0
}

# @private Переключить режим / Switch the mode
vkm_tui::__mode() {
    VKM_MODE="${1:?mode required}"
    VKM_BASE=0; VKM_SEL=0
    vkm_tui::__load
    return 0
}

# @private Запустить поиск (Enter/Esc модалки) / Run a search (modal Enter/Esc)
vkm_tui::__search() {
    local -r text="${1:-}"
    if is::empty "${text}"; then return 0; fi
    VKM_QUERY="${text}"
    VKM_MODE=search
    vkm_tui::__load
    return 0
}

# @private Скачать выбранный трек / Download the selected track
vkm_tui::__download() {
    local -i total
    total="$(vkm_tui::__total)"
    if (( total == 0 )); then
        tui::app::message_modal "VK Music" "Список пуст / the list is empty"
        return 0
    fi
    local out
    if out="$(vkmusic::download_track "${VKM_SEL}" 2>/dev/null)"; then
        tui::app::message_modal "Скачано / Downloaded" "$(basename "${out}")"
    else
        tui::app::message_modal "Не удалось / Failed" "$(vkmusic::track_field "${VKM_SEL}" title)"
    fi
    return 0
}

# @private Информация о выбранном треке / Info about the selected track
vkm_tui::__info() {
    local -i total
    total="$(vkm_tui::__total)"
    (( total == 0 )) && return 0
    local artist title id owner duration album url
    artist="$(vkmusic::track_field "${VKM_SEL}" artist)"
    title="$(vkmusic::track_field "${VKM_SEL}" title)"
    id="$(vkmusic::track_field "${VKM_SEL}" id)"
    owner="$(vkmusic::track_field "${VKM_SEL}" owner_id)"
    duration="$(vkmusic::track_field "${VKM_SEL}" duration)"
    album="$(vkmusic::track_field "${VKM_SEL}" album)"
    url="$(vkmusic::track_field "${VKM_SEL}" url)"
    tui::app::message_modal \
        "${artist} — ${title}" \
        "$(printf '%s\n%s\n%s\n%s\n%s' \
            "owner: ${owner}" "id: ${id}" "duration: ${duration}s" \
            "album: ${album:-—}" "url: ${url:-—}")"
    return 0
}

# @private Рисование списка / Draw the list
vkm_tui::__draw() {
    vkm_tui::__clamp
    local -i total page
    total="$(vkm_tui::__total)"
    page=$(( TUI_LINES - 9 ))
    (( page < 1 )) && page=1

    local label
    case "${VKM_MODE}" in
        search)  label="Поиск: ${VKM_QUERY:-—} / search" ;;
        reco)    label="Рекомендации / recommendations" ;;
        popular) label="Популярное / popular" ;;
        user)    label="Моя музыка / my music" ;;
        *)       label="VK Music" ;;
    esac
    tui::app::statusbar \
        "VK Music · ${label}   ⏱ ${total}   ↑↓ выбор · ENTER скачать · / поиск · r reco · p popular · i info · q выход"

    if (( total == 0 )); then
        tui::put 3 3 "список пуст / the list is empty — нажмите / (поиск) или r (рекомендации)" "$(tui::style dim)"
        return 0
    fi

    local -i r=2 c=3 i=0
    while (( i < page && VKM_BASE + i < total )); do
        local idx=$(( VKM_BASE + i ))
        local line="$(vkmusic::track_line "${idx}")"
        if (( idx == VKM_SEL )); then
            tui::put "$(( r + i ))" "${c}" "▸ ${line}" "$(tui::style bold reverse cyan)"
        else
            tui::put "$(( r + i ))" "${c}" "  ${line}" ""
        fi
        i=$(( i + 1 ))
    done

    local -i dr=$(( r + page ))
    local artist title duration album
    artist="$(vkmusic::track_field "${VKM_SEL}" artist)"
    title="$(vkmusic::track_field "${VKM_SEL}" title)"
    duration="$(vkmusic::track_field "${VKM_SEL}" duration)"
    album="$(vkmusic::track_field "${VKM_SEL}" album)"
    tui::put "${dr}" "${c}" \
        "$(printf '%s — %s  [%ss]  альбом: %s' "${artist}" "${title}" "${duration}" "${album:-—}")" \
        "$(tui::style dim bold)"
    return 0
}

# @description Запустить полноэкранный TUI VK Music / Run the full-screen VK Music TUI
vkm_tui::run() {
    tui::size
    tui::app::window list "VK Music" 1 1 $(( TUI_COLS - 1 )) $(( TUI_LINES - 1 ))
    tui::app::draw_hook vkm_tui::__draw
    tui::app::statusbar "VK Music — загрузка… / loading…"

    tui::app::bind "UP|k|K|ц|Ц"   vkm_tui::__move -1
    tui::app::bind "DOWN|j|J|о|О" vkm_tui::__move 1
    tui::app::bind "PGUP"         vkm_tui::__page up
    tui::app::bind "PGDN"         vkm_tui::__page down
    tui::app::bind "ENTER"        vkm_tui::__download
    tui::app::bind "i|I|ш|Ш"     vkm_tui::__info
    tui::app::bind "r|R|к|К"     vkm_tui::__mode reco
    tui::app::bind "p|P|з|З"     vkm_tui::__mode popular
    tui::app::bind "u|U|г|Г"     vkm_tui::__mode user
    tui::app::bind "/"            vkm_tui::__prompt
    tui::app::bind "q|Q|й|Й"     tui::app::quit

    VKM_MODE=reco
    vkm_tui::__load

    tui::app::run
    return "${E_SUCCESS}"
}

# @private Открыть модалку поиска / Open the search modal
vkm_tui::__prompt() {
    tui::app::input_modal "Поиск VK Music / search" vkm_tui::__search "" "${VKM_QUERY:-}"
    return 0
}

# Точка входа / Entry point
vkmusic_tui::main() {
    vkm_tui::run "$@"
}
