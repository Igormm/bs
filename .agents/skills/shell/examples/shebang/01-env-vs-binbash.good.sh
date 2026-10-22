#!/usr/bin/env bash
#
# GOOD: `env` resolves bash on PATH, so this finds a modern bash (5.x) instead of
# macOS's frozen /bin/bash 3.2, and works on systems with no /bin/bash (NixOS).
set -euo pipefail

printf 'running under bash %s\n' "${BASH_VERSION}"
