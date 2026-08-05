#!/usr/bin/env bs
# shellcheck shell=bash
# tests/validateshellcheck.sh — ShellCheck validation for BS framework
# tests/validateshellcheck.sh — Проверка ShellCheck для фреймворка BS
#
# Прогоняет ShellCheck по всем .sh файлам и скрипту bs.
# Уровень error — обязателен (код возврата не ноль при ошибках),
# предупреждения выводятся информационно и не роняют прогон.
# Runs ShellCheck over all .sh files and the bs script.
# Error severity is mandatory (non-zero exit on errors),
# warnings are printed for information and do not fail the run.
#
# Usage / Использование:
#   bash tests/validateshellcheck.sh             # только ошибки / errors only
#   bash tests/validateshellcheck.sh --warnings  # + предупреждения / + warnings

set -euo pipefail

# Каталог скрипта: прогон работает из любого текущего каталога
# Script directory: the run works from any current directory
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

# Цвета для вывода / Output colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ShellCheck обязателен для CI, локально прогон честно пропускается
# ShellCheck is required for CI; local runs are skipped honestly
if ! command -v shellcheck >/dev/null 2>&1; then
    echo -e "${YELLOW}⊘ shellcheck not installed, skipping (CI installs it)${NC}"
    echo -e "${YELLOW}⊘ shellcheck не установлен, пропуск (в CI устанавливается)${NC}"
    exit 0
fi

# Список файлов: все *.sh + скрипт bs (тоже bash)
# File list: all *.sh + the bs script (bash as well)
mapfile -t files < <(find . -name "*.sh" -not -path "./.git/*" | sort)
files+=("./bs")

echo -e "${BLUE}ShellCheck validation (${#files[@]} files)${NC}"
echo -e "${BLUE}Проверка ShellCheck (${#files[@]} файлов)${NC}"
echo

# -s bash: shebang '#!/usr/bin/env bs' неизвестен ShellCheck,
# но все файлы фреймворка — bash
# -s bash: the '#!/usr/bin/env bs' shebang is unknown to ShellCheck,
# but all framework files are bash
if shellcheck -s bash --severity=error "${files[@]}"; then
    echo -e "${GREEN}✓ No ShellCheck errors / Ошибок ShellCheck нет${NC}"
else
    echo -e "${RED}✗ ShellCheck errors found / Найдены ошибки ShellCheck${NC}" >&2
    exit 1
fi

# Информационный прогон по предупреждениям (не роняет сборку)
# Informational warnings pass (does not fail the build)
if [[ "${1:-}" == "--warnings" ]]; then
    echo
    echo -e "${BLUE}Warnings (informational) / Предупреждения (информационно):${NC}"
    shellcheck -s bash --severity=warning "${files[@]}" || true
fi
