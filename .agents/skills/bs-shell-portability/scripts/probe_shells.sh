#!/usr/bin/env bash
#
# probe_shells.sh — what does each installed shell really support? (read-only)
# probe_shells.sh — что на самом деле умеет каждая установленная оболочка?
#
# Runs ~30 one-line probes of the features the BS kernel uses in every shell
# found on this machine (bash zsh dash ash busybox ksh mksh oksh osh) and
# prints a table. Use it BEFORE you claim "this works in zsh" in code or docs:
# a feature table from the internet is about interactive comfort, BS needs the
# scripting language. fish and nushell are not POSIX-syntax shells: they are
# listed as "n/a" and reach BS through the `bs` command only.
# Запускает ~30 однострочных проб возможностей, на которых стоит ядро BS, в
# каждой найденной на машине оболочке и печатает таблицу. Запускайте ПЕРЕД
# тем, как писать в коде или документации «в zsh это работает»: таблицы из
# интернета — про интерактивное удобство, а BS нужен скриптовый язык. fish и
# nushell — не POSIX-синтаксис: они помечены «n/a» и доступны BS только через
# команду `bs`.
#
# Usage / Использование:
#   bash probe_shells.sh [--tsv] [SHELL ...]     (default: every shell found)

set -euo pipefail

tsv=0
declare -a wanted=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tsv) tsv=1; shift ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d'; exit 0 ;;
    *) wanted+=("$1"); shift ;;
  esac
done
if (( ${#wanted[@]} == 0 )); then
  wanted=(bash zsh dash ash busybox ksh mksh oksh osh)
fi

# name|code|expected stdout (empty = only the exit code must be 0)
readonly -a PROBES=(
  'local|f(){ local x=1; echo $x; }; f|1'
  'local -r|f(){ local -r x=1; echo $x; }; f|1'
  '[[ ]]|[[ a == a ]] && echo y|y'
  '(( )) command|i=1; (( i++ )); echo $i|2'
  'indexed array|a=(x y z); echo ${#a[@]}|3'
  'array index from 0|a=(x y z); echo ${a[0]}|x'
  'array slice|a=(x y z); echo ${a[@]:1}|y z'
  'assoc array (declare -A)|declare -A m; m[k]=v; echo ${m[k]}|v'
  'nameref (local -n)|f(){ local -n r=$1; r=ok; }; v=; f v; echo $v|ok'
  'regex =~ + BASH_REMATCH|[[ abc =~ ^a(b)c$ ]] && echo ${BASH_REMATCH[1]}|b'
  '${v,,} lowercase|v=ABC; echo ${v,,}|abc'
  '${v^^} uppercase|v=abc; echo ${v^^}|ABC'
  'printf -v|printf -v x "%s-%s" a b; echo $x|a-b'
  'mapfile / readarray|printf "a\nb\n" \| { mapfile -t m; echo ${#m[@]}; }|2'
  'process substitution|cat <(echo hi)|hi'
  'declare -g|f(){ declare -g G=1; }; f; echo $G|1'
  'indirect ${!name}|n=v; v=ok; echo ${!n}|ok'
  'FUNCNAME|f(){ echo ${FUNCNAME[0]}; }; f|f'
  'BASH_SOURCE|echo ${BASH_SOURCE[0]:-none}|'
  "ANSI-C quoting \$'..'|x=\$'a\\tb'; echo \${#x}|3"
  'set -o pipefail|set -o pipefail; false \| true; echo $?|1'
  'trap ... ERR (fires)|trap "echo e" ERR; false; true|e'
  'read -a|echo "a b" \| { read -ra x; echo ${#x[@]}; }|2'
  'function keyword|function f { echo y; }; f|y'
  '$EPOCHREALTIME|echo ${EPOCHREALTIME:+y}|y'
  'coproc|coproc C { cat; }; echo ok|ok'
  'substring ${v:o:l}|v=hello; echo ${v:1:3}|ell'
  'name with :: (a::b)|a::b() { echo ok; }; a::b|ok'
  'shopt|shopt -s nocasematch; [[ A == a ]] && echo y|y'
)

run_probe() {
  local -r bin="$1" code="${2//\\|/|}" want="$3"
  local out rc=0
  out="$("${bin}" -c "${code}" 2>/dev/null)" || rc=$?
  if [[ -n "${want}" ]]; then
    [[ ${rc} -eq 0 && "${out}" == "${want}" ]] && printf 'ok' || printf 'no'
  else
    [[ ${rc} -eq 0 ]] && printf 'ok' || printf 'no'
  fi
}

declare -a bins=() names=()
for s in "${wanted[@]}"; do
  b="$(command -v "${s}" 2>/dev/null || true)"
  [[ -n "${b}" ]] || { (( tsv == 1 )) || printf 'skip: %s is not installed / не установлен\n' "${s}" >&2; continue; }
  names+=("${s}"); bins+=("${b}")
done
if (( ${#names[@]} == 0 )); then echo "no shells found" >&2; exit 1; fi

if (( tsv == 1 )); then
  printf 'feature'; printf '\t%s' "${names[@]}"; printf '\n'
else
  printf '%-30s' "feature"; printf ' %-8s' "${names[@]}"; printf '\n'
fi
for entry in "${PROBES[@]}"; do
  name="${entry%%|*}"; rest="${entry#*|}"
  want="${rest##*|}"; code="${rest%|*}"
  if (( tsv == 1 )); then printf '%s' "${name}"; else printf '%-30s' "${name}"; fi
  for b in "${bins[@]}"; do
    r="$(run_probe "${b}" "${code}" "${want}")"
    if (( tsv == 1 )); then printf '\t%s' "${r}"; else printf ' %-8s' "${r}"; fi
  done
  printf '\n'
done
if (( tsv == 0 )); then
  printf '\nversions / версии:\n'
  for i in "${!names[@]}"; do
    v="$("${bins[i]}" --version 2>&1 | head -n 1 || true)"
    [[ "${v}" != *[Ii]llegal* && "${v}" != *"invalid option"* ]] || v="(no --version)"
    printf '  %-8s %s\n' "${names[i]}" "${v}"
  done
fi
