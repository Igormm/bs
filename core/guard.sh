#!/usr/bin/env bash
#
# core/guard.sh — compatibility alias for core/prereq.sh
# core/guard.sh — обратносовместимая обёртка над core/prereq.sh
#
# Historically this file defined bs::guard, bs::guard_loaded and
# bs::source_relative. They have been moved to core/prereq.sh so that
# core prerequisites are loaded from a file whose only job is to be
# the a-priori core machinery.
#
# @depends (none)

# Self-guard: prevent double-source even though we just re-export prereq.
[[ -n "${__GUARD_SOURCED:-}" ]] && return 0
readonly __GUARD_SOURCED=1

# shellcheck disable=SC1090
source "$(dirname -- "${BASH_SOURCE[0]}")/prereq.sh"
