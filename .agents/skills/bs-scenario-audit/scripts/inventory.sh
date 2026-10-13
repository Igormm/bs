#!/usr/bin/env bash
# shellcheck shell=bash
#
# inventory.sh — read-only inventory of the public functions of a BS tree for
# bs-scenario-audit: parameters, risky constructs, test coverage.
# inventory.sh — опись публичных функций дерева BS для bs-scenario-audit:
# параметры, рискованные конструкции, покрытие тестами. Только чтение.
#
# Usage / Использование:
#   inventory.sh [options] [scope...]        scope = files or directories
#                                            (default: core lib bootstrap bs install install.sh)
#   --untested        only functions never mentioned in the tests / только без тестов
#   --min-risk N      only functions with a risk score >= N / только риск >= N
#   --csv             comma-separated output instead of a markdown table
#   --tests-dir DIR   where the tests live (default: <repo>/tests)
#   -h, --help
#
# Risk score = 3*destructive + 2*privileged + 1*network + 3*eval + 1*masking
#              + 2*strict-mode trap (each category counts once per function).
# Tests column: how often the name occurs in the tests; for names without "::" it is a word match
# and can be overstated (a function called "help"). Unterminated functions are reported on stderr.
# Heuristic: functions are recognised by "name() {" at column 0 and the closing
# "}" at column 0; arguments are the highest $1..$9 seen in the body (an awk
# program inside a function can add false positives). Treat it as a map to
# decide where to look first, not as a verdict.
# Эвристика: функция — "name() {" в нулевой колонке до "}" в нулевой колонке;
# это карта «куда смотреть в первую очередь», а не приговор.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd -P)"
readonly ROOT

usage() {
  sed -n '/^# Usage/,/^# -h, --help/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

tests_dir="${ROOT}/tests"
format="md"
only_untested=0
min_risk=0
scope=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --untested)  only_untested=1; shift ;;
    --csv)       format="csv"; shift ;;
    --min-risk)
      [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || { printf 'inventory: --min-risk needs a number\n' >&2; exit 2; }
      min_risk="$2"; shift 2 ;;
    --tests-dir)
      [[ $# -ge 2 ]] || { printf 'inventory: --tests-dir needs a directory\n' >&2; exit 2; }
      tests_dir="$2"; shift 2 ;;
    -h|--help)   usage; exit 0 ;;
    -*)          printf 'inventory: unknown option: %s\n' "$1" >&2; exit 2 ;;
    *)           scope+=("$1"); shift ;;
  esac
done
(( ${#scope[@]} > 0 )) || scope=(core lib bootstrap bs install install.sh)

# Файлы области: каталог -> все *.sh и bs; относительные пути ищем от корня репо
# Scope files: a directory -> every *.sh and bs; relative paths resolve from the repo root
files=()
for item in "${scope[@]}"; do
  path="${item}"
  if [[ "${path}" != /* ]]; then
    if [[ -e "${ROOT}/${path}" ]]; then path="${ROOT}/${path}"; fi
  fi
  if [[ -d "${path}" ]]; then
    while IFS= read -r f; do files+=("${f}"); done \
      < <(find "${path}" -type f \( -name '*.sh' -o -name bs \) | LC_ALL=C sort)
  elif [[ -f "${path}" ]]; then
    files+=("${path}")
  else
    printf 'inventory: not found: %s\n' "${item}" >&2
    exit 2
  fi
done
(( ${#files[@]} > 0 )) || { printf 'inventory: no shell files in the scope\n' >&2; exit 2; }

# Сколько раз имя функции встречается в тестах (одним проходом по tests/)
# How often a function name occurs in the tests (one pass over tests/)
counts="$(mktemp)"
trap 'rm -f -- "${counts}"' EXIT
if [[ -d "${tests_dir}" ]]; then
  grep -rhoE '[A-Za-z_][A-Za-z0-9_]*(::[A-Za-z0-9_]+)*' -- "${tests_dir}" 2>/dev/null \
    | sort | uniq -c > "${counts}" || true
fi

# shellcheck disable=SC2016  # the awk program is single-quoted on purpose
awk_scan='
function scan(l) {
  if (l ~ /^[ \t]*#/) return
  if (l ~ /(^|[^A-Za-z_])(rm[ \t]+-|rmdir[ \t]|mv[ \t]|truncate[ \t]|shred[ \t]|mkfs|dd[ \t]+if=)/ || l ~ /sed[ \t]+(-[a-zA-Z]*i|--in-place)/) D = 1
  if (l ~ /(systemctl|useradd|userdel|usermod|chpasswd|visudo|chown|chmod|iptables|ufw|firewall-cmd|crontab|modprobe|sysctl|(^|[ \t])mount[ \t]|sudo[ \t]|apt(-get)?[ \t]|dnf[ \t]|yum[ \t]|pacman[ \t]|zypper[ \t])/) P = 1
  if (l ~ /(curl|wget|scp|rsync|ssh)[ \t]/) N = 1
  if (l ~ /(^|[ \t;({])eval[ \t]/) E = 1
  if (l ~ /utils::ignore/ || l ~ /\|\|[ \t]*(true|:)([ \t;)]|$)/) M = 1
  if (l ~ /\(\([ \t]*[A-Za-z_][A-Za-z0-9_]*\+\+/ || l ~ /\(\([ \t]*\+\+/) T = 1
  if (l ~ /local[ \t]+(-[a-zA-Z]+[ \t]+)?[A-Za-z_][A-Za-z0-9_]*="\$\{[1-9]\}"/) T = 1
  rest = l
  while (match(rest, /\$\{?[1-9]/)) {
    d = substr(rest, RSTART + RLENGTH - 1, 1) + 0
    if (d > maxarg) maxarg = d
    rest = substr(rest, RSTART + RLENGTH)
  }
  if (l ~ /\$@/) varargs = 1
  if (match(l, /^[ \t]*-[-A-Za-z0-9|]+\)/)) {
    tok = substr(l, RSTART, RLENGTH); gsub(/[ \t)]/, "", tok)
    if (index("," flags ",", "," tok ",") == 0) flags = (flags == "" ? tok : flags "," tok)
  }
}
function finish(   score, m, t, a) {
  if (name ~ /::__/ || name ~ /^_/) return
  score = 3 * D + 2 * P + N + 3 * E + M + 2 * T
  m = ""
  if (D) m = m "destructive+"; if (P) m = m "privileged+"; if (N) m = m "network+"
  if (E) m = m "eval+"; if (M) m = m "masking+"; if (T) m = m "strict-trap+"
  sub(/\+$/, "", m); if (m == "") m = "-"
  t = (name in cnt) ? cnt[name] : 0
  a = maxarg ""; if (varargs) a = a "+@"
  print score "\t" name "\t" fname ":" start "\t" (FNR - start + 1) "\t" a "\t" (flags == "" ? "-" : flags) "\t" m "\t" t
}
function begin_fn(line) {
  name = substr(line, 1, index(line, "(") - 1)
  infn = 1; start = FNR; fname = FILENAME
  if (root != "" && index(fname, root "/") == 1) fname = substr(fname, length(root) + 2)
  D = P = N = E = M = T = 0; maxarg = 0; varargs = 0; flags = ""
}
function flush_unterminated() {
  if (infn) print "inventory: unterminated function " name " at " fname ":" start " (no closing brace in column 0)" > "/dev/stderr"
  infn = 0
}
FILENAME == counts { cnt[$2] = $1; next }
FNR == 1 { flush_unterminated() }
{
  if (!infn) {
    if (match($0, /^[A-Za-z_][A-Za-z0-9_:]*\(\)[ \t]*\{/)) {
      begin_fn($0); scan($0)
      if ($0 ~ /\}[ \t]*$/) { finish(); infn = 0 }
    }
    next
  }
  scan($0)
  if ($0 ~ /^\}/) { finish(); infn = 0 }
}
END { flush_unterminated() }
'

report="$(mktemp)"
trap 'rm -f -- "${counts}" "${report}"' EXIT
(cd "${ROOT}" && awk -v counts="${counts}" -v root="${ROOT}" "${awk_scan}" "${counts}" "${files[@]}") \
  | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 > "${report}"

awk -F'\t' -v fmt="${format}" -v untested="${only_untested}" -v minrisk="${min_risk}" '
  BEGIN {
    if (fmt == "md") {
      print "| риск | функция | где | строк | арг | флаги | маркеры | тестов |"
      print "| ---: | --- | --- | ---: | --- | --- | --- | ---: |"
    } else print "risk,function,where,lines,args,flags,markers,tests"
  }
  {
    total++
    if ($8 == 0) un++
    if ($1 > 0) risky++
    if ($1 < minrisk) next
    if (untested && $8 != 0) next
    shown++
    if (fmt == "md") printf "| %s | `%s` | %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6, $7, $8
    else { gsub(/,/, ";", $6); print $1 "," $2 "," $3 "," $4 "," $5 "," $6 "," $7 "," $8 }
  }
  END {
    if (fmt == "md") printf "\nФункций в описи: %d, показано: %d, без тестов: %d, с риском > 0: %d\n", total + 0, shown + 0, un + 0, risky + 0
  }
' "${report}"
