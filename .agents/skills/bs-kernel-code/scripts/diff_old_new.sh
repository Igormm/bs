#!/usr/bin/env bash
#
# diff_old_new.sh — differential run: the converted kernel file against its old implementation (read-only)
# diff_old_new.sh — дифференциальный прогон: переведённый файл ядра против прежней реализации (только чтение)
#
# Copies the tree, puts the OLD version of one file (git show REF:FILE) into the copy, then runs every
# case (one bash snippet per line) in both trees under `env -i` for every combination of the --env matrix
# and compares stdout, stderr and the exit status BYTE FOR BYTE. The kernel is loaded through
# bootstrap/init.sh, so the snippets use the names callers use (log::info, utils::has …): that is what
# must not change. The tree path is masked as @TREE@.
# Копирует дерево, кладёт в копию СТАРУЮ версию одного файла (git show REF:FILE) и гоняет каждый кейс
# (по сниппету bash в строке) в обоих деревьях под `env -i` на каждой комбинации матрицы --env;
# сравнивает stdout, stderr и код возврата ПОБАЙТНО. Ядро грузится через bootstrap/init.sh, поэтому
# сниппеты зовут привычные вызывающим имена (log::info, utils::has …): они и не должны меняться.
#
# Usage / Использование:
#   bash diff_old_new.sh --file core/logger.sh [--ref HEAD] [--also FILE]... [--cases FILE] [--env NAME=v1,v2]... [--show N]
#   --file  path of the converted file, relative to the repo root (required)
#   --also  one more file taken from --ref into the old tree, repeatable. Needed when the conversion
#           changed a caller that the old file cannot work without, e.g. bootstrap/init.sh, which
#           now calls bs_config_load: the old core/config.sh does not define it
#           / ещё один файл из --ref в старое дерево, повторяемый: нужен, когда перевод изменил
#           вызывающего (bootstrap/init.sh зовёт bs_config_load, в старом config.sh её нет)
#   --ref   where the old version lives (default HEAD: the committed file against the working copy;
#           use e.g. 3a20a84^ for an already committed conversion)
#   --cases file with one snippet per line (# lines and blank lines are skipped); default: stdin
#   --env   a matrix axis, repeatable: BS_LOG_FORMAT=text,json,structured (use NAME= for "unset")
#   --show  how many differences to print in full (default 3)
# Exit: 0 — all equal, 1 — differences, 2 — bad usage. The shell is bash: init.sh is bash 4 (the
# six-shell comparison of the NEW code is the job of tests/unit/test<module>portableunit.sh).

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)" # shell-gate: a bash tool of its own
file=""; ref="HEAD"; cases="-"; show=3
declare -a env_names=() env_vals=() also=()
while (( $# > 0 )); do
  case "$1" in
    --file) file="${2:?--file needs a path}"; shift 2 ;;
    --ref) ref="${2:?--ref needs a revision}"; shift 2 ;;
    --also) also+=("${2:?--also needs a path}"); shift 2 ;;
    --cases) cases="${2:?--cases needs a file}"; shift 2 ;;
    --env)
      [[ "${2:-}" == *=* ]] || { echo "bad --env: ${2:-}" >&2; exit 2; }
      env_names+=("${2%%=*}"); env_vals+=("${2#*=}"); shift 2 ;;
    --show) show="${2:?--show needs a number}"; shift 2 ;;
    -h|--help) sed -n '2,/^set -uo/p' "$0" | sed '$d'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
[[ -n "${file}" ]] || { echo "--file is required" >&2; exit 2; }
cd "${root}" || exit 2
git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null || { echo "no such revision: ${ref}" >&2; exit 2; }
git cat-file -e "${ref}:${file}" 2>/dev/null || { echo "${file} does not exist in ${ref}" >&2; exit 2; }
[[ -f "${file}" ]] || { echo "no such file in the working tree: ${file}" >&2; exit 2; }

tmp="$(mktemp -d)"; trap 'rm -rf "${tmp:?}"' EXIT
mkdir -p "${tmp}/old" "${tmp}/home"
tar --exclude=.git --exclude=.claude -cf - . | tar -xf - -C "${tmp}/old"
git show "${ref}:${file}" > "${tmp}/old/${file}"
for extra in ${also[@]+"${also[@]}"}; do
  git cat-file -e "${ref}:${extra}" 2>/dev/null || { echo "${extra} does not exist in ${ref}" >&2; exit 2; }
  git show "${ref}:${extra}" > "${tmp}/old/${extra}"
done

declare -a snippets=()
while IFS= read -r line || [[ -n "${line}" ]]; do
  [[ -z "${line}" || "${line}" == \#* ]] || snippets+=("${line}")
done < <(if [[ "${cases}" == "-" ]]; then cat; else cat -- "${cases}"; fi)
(( ${#snippets[@]} > 0 )) || { echo "no cases" >&2; exit 2; }

# run_one TREE SNIPPET [NAME=value ...] → the answer in one string (out, err, rc)
run_one() {
  local tree="$1" snippet="$2" out err rc
  shift 2
  out="${tmp}/out.$$"; err="${tmp}/err.$$"
  env -i HOME="${tmp}/home" PATH="${PATH}" BS_SILENT=1 TZ=UTC LC_ALL=C "$@" \
    bash -c ". '${tree}/bootstrap/init.sh' >/dev/null 2>&1 || exit 99; ${snippet}" >"${out}" 2>"${err}"
  rc=$?
  printf '%s\n--stderr--\n%s\n--rc--\n%s\n' \
    "$(sed "s#${tree}#@TREE@#g" "${out}")" "$(sed "s#${tree}#@TREE@#g" "${err}")" "${rc}"
}

total=0; diffs=0; shown=0

# nth_field "a,b,,c" 2 → the 2nd comma-separated field (0-based; empty fields are kept)
nth_field() {
  local rest="$1," n="$2"
  while (( n > 0 )); do rest="${rest#*,}"; n=$((n - 1)); done
  printf '%s' "${rest%%,*}"
}
# count_fields "a,b,,c" → 4
count_fields() {
  local rest="$1," n=0
  while [[ -n "${rest}" ]]; do rest="${rest#*,}"; n=$((n + 1)); done
  printf '%s' "${n}"
}

# odometer over the --env axes / счётчик-одометр по осям --env
declare -a idx=() lens=()
for i in "${!env_names[@]}"; do
  lens[i]="$(count_fields "${env_vals[i]}")"; idx[i]=0
done
while :; do
  assign=()
  for i in "${!env_names[@]}"; do
    v="$(nth_field "${env_vals[i]}" "${idx[i]}")"
    [[ -z "${v}" ]] || assign+=("${env_names[i]}=${v}")
  done
  for snippet in "${snippets[@]}"; do
    total=$((total + 1))
    a="$(run_one "${tmp}/old" "${snippet}" ${assign[@]+"${assign[@]}"})"
    b="$(run_one "${root}" "${snippet}" ${assign[@]+"${assign[@]}"})"
    if [[ "${a}" != "${b}" ]]; then
      diffs=$((diffs + 1))
      if (( shown < show )); then
        shown=$((shown + 1))
        printf 'DIFF  env=[%s] case=[%s]\n' "${assign[*]:-}" "${snippet}"
        diff <(printf '%s\n' "${a}") <(printf '%s\n' "${b}") | sed 's/^/      /' | head -n 12
      fi
    fi
  done
  # next combination / следующая комбинация
  pos=$(( ${#env_names[@]} - 1 )); carry=1
  while (( carry == 1 && pos >= 0 )); do
    idx[pos]=$(( idx[pos] + 1 ))
    if (( idx[pos] >= lens[pos] )); then idx[pos]=0; pos=$((pos - 1)); else carry=0; fi
  done
  (( carry == 0 )) || break
done

echo
echo "compared ${total} run(s): ${diffs} difference(s) / сравнено ${total} прогонов: ${diffs} различий"
(( diffs == 0 )) && { echo "OK: byte-for-byte equal / побайтно совпало"; exit 0; }
exit 1
