#!/usr/bin/env bs
# shellcheck shell=bash
# examples/vkmusic_tui.sh — full-screen VK Music client
# examples/vkmusic_tui.sh — полноэкранный клиент VK Music
#
#   ./bs run examples/vkmusic_tui.sh
#   VK_TOKEN=... VK_USER=123 ./bs run examples/vkmusic_tui.sh
#
# Клавиши / Keys: ↑↓/jk выбор, ENTER скачать, / поиск, r рекомендации,
# p популярное, u моя музыка, i информация, q выход.
# Tracks are vkmusic_track objects (core/object.sh); lists are cached (core/cache.sh).

load "lib/integration/vkmusic_tui"

if [[ -n "${VK_TOKEN:-}" && -n "${VK_USER:-}" ]]; then
    vkmusic::auth "${VK_TOKEN}" "${VK_USER}" || true
fi

vkmusic_tui::main
