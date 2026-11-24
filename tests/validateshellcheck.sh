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
# shell-gate: исполняемый раннер вне bs; $0 — единственный источник пути / a runner executed outside bs; $0 is the only source of its path
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

# Общий фреймворк: print_header, цвета и гейт NO_COLOR / TERM=dumb / не-tty
# Shared framework: print_header, colors and the NO_COLOR / TERM=dumb / non-tty gate
source "${SCRIPT_DIR}/testframework.sh"

# ShellCheck обязателен для CI, локально прогон честно пропускается
# ShellCheck is required for CI; local runs are skipped honestly
if ! command -v shellcheck >/dev/null 2>&1; then
    echo -e "${YELLOW}▶ shellcheck not installed, skipping (CI installs it)${NC}"
    echo -e "${YELLOW}▶ shellcheck не установлен, пропуск (в CI устанавливается)${NC}"
    exit 0
fi

# Список файлов: все *.sh + скрипт bs (тоже bash). *.bad.sh — намеренно
# неправильные примеры импортированных навыков; их проверяет свой CI upstream.
# .claude/worktrees — локальные рабочие копии агентов, не часть дерева проекта.
# File list: all *.sh + the bs script (bash as well). *.bad.sh are intentional
# counterexamples of imported skills; their own upstream CI checks them.
# .claude/worktrees are local agent checkouts, not part of the project tree.
mapfile -t files < <(find . -name "*.sh" -not -path "./.git/*" -not -path "./.claude/*" -not -name "*.bad.sh" | sort)
files+=("./bs")

print_header "ShellCheck Validation / Проверка ShellCheck"
echo -e "${BLUE}Checking ${#files[@]} files / Проверка ${#files[@]} файлов${NC}"
echo

# -s bash: shebang '#!/usr/bin/env bs' неизвестен ShellCheck,
# но все файлы фреймворка — bash
# -s bash: the '#!/usr/bin/env bs' shebang is unknown to ShellCheck,
# but all framework files are bash
# ShellCheck — CPU-bound и однопоточный. Гоняем ЧАНКАМИ с -P (число ядер):
# xargs -n <батч> группирует файлы, поэтому кэш source-зависимостей работает
# внутри батча и параллельность не теряется; xargs возвращает 123, если хоть
# один батч дал ошибку уровня error. ВНИМАНИЕ: строка комментария не может
# начинаться с «# shellcheck» строчными — это директива ShellCheck.
# ShellCheck is CPU-bound and single-threaded. Run in CHUNKS with -P (cores):
# xargs -n <batch> groups files, so the source-following cache works inside a
# batch and parallelism is retained; xargs returns 123 if any batch has an
# error. NOTE: a comment must not start with lowercase "# shellcheck" — that
# is a ShellCheck directive.
declare -r SHC_JOBS="${SHELLCHECK_JOBS:-$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || printf 4)}"
declare -r SHC_BATCH="$(( (${#files[@]} + SHC_JOBS - 1) / SHC_JOBS ))"
echo -e "${BLUE}ShellCheck on ${SHC_JOBS} jobs, batch ${SHC_BATCH} files (SHELLCHECK_JOBS=N → override) / ${SHC_JOBS} потоков, батч ${SHC_BATCH} файлов (SHELLCHECK_JOBS=N → переопределить)${NC}"

if printf '%s\0' "${files[@]}" | xargs -0 -n "${SHC_BATCH}" -P "${SHC_JOBS}" shellcheck -s bash --severity=error; then
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
    printf '%s\0' "${files[@]}" | xargs -0 -n "${SHC_BATCH}" -P "${SHC_JOBS}" shellcheck -s bash --severity=warning || true
fi
