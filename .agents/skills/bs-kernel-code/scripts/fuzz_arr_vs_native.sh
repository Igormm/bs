#!/usr/bin/env bash
#
# fuzz_arr_vs_native.sh — random operations on bs_arr_* in a shell against a NATIVE bash array (read-only)
# fuzz_arr_vs_native.sh — случайные операции над bs_arr_* в оболочке против НАСТОЯЩЕГО массива bash (только чтение)
#
# For several seeds it builds a random list of operations (push, pop, shift, set, remove_at, get,
# index_of, contains, clear — negative and out-of-range indexes, "hard" values: empty, spaces, quote,
# *, $HOME, backslash, newline, Cyrillic, -n, --), runs the SAME driver once over a native bash array
# and once over core/data.sh in the chosen shell, and compares the logs (result, status, length and
# the whole content after every operation) byte for byte. It is the model for any "data structure
# replaced by the data layer" conversion: the reference is the real bash array the code used before.
# Для нескольких зёрен строит случайный список операций, гоняет ОДИН драйвер по настоящему массиву
# bash и по core/data.sh в выбранной оболочке и сравнивает логи побайтно (результат, статус, длина и
# всё содержимое после каждой операции). Образец для любой замены структуры данных слоем данных.
#
# Usage / Использование:
#   bash fuzz_arr_vs_native.sh [--shell dash] [--ops 2500] [--seeds 6]
# Exit: 0 — no differences, 1 — differences, 2 — bad usage / shell not installed.
# A shell that is not installed is an error here (exit 2), never "passed".

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)" # shell-gate: a bash tool of its own
sh_name="dash"; ops=2500; seeds=6
while (( $# > 0 )); do
  case "$1" in
    --shell) sh_name="${2:?--shell needs a name}"; shift 2 ;;
    --ops) ops="${2:?--ops needs a number}"; shift 2 ;;
    --seeds) seeds="${2:?--seeds needs a number}"; shift 2 ;;
    -h|--help) sed -n '2,/^set -uo/p' "$0" | sed '$d'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
if [[ "${sh_name}" == "busybox ash" ]]; then sh_cmd=(busybox ash); else sh_cmd=("${sh_name}"); fi
command -v "${sh_cmd[0]}" >/dev/null 2>&1 || { echo "shell not installed: ${sh_name} — NOT verified / не установлен" >&2; exit 2; }

tmp="$(mktemp -d)"; trap 'rm -rf "${tmp:?}"' EXIT

# the hard values, shared by both runs / трудные значения, общие для обоих прогонов
cat > "${tmp}/vals.sh" <<'VALS'
V0=''
V1='a b'
V2="it's"
V3='*'
V4='$HOME'
V5='back\slash'
V6='new
line'
V7='Привет'
V8='-n'
V9='--'
VALS

# the driver: identical for both backends / драйвер: один и тот же для обоих
cat > "${tmp}/driver.sh" <<'DRIVER'
n=0
while read -r op a b; do
  case "$op" in
    push)      eval "v=\$V$a"; be_push "$v" ;;
    pop)       be_pop ;;
    shift)     be_shift ;;
    set)       eval "v=\$V$b"; be_set "$a" "$v" ;;
    remove_at) be_remove_at "$a" ;;
    get)       be_get "$a" ;;
    index_of)  eval "v=\$V$a"; be_index_of "$v" ;;
    contains)  eval "v=\$V$a"; be_index_of "$v" >/dev/null ;;
    clear)     be_clear ;;
  esac
  rc=$?
  printf '#%s %s %s %s rc=%s len=%s join=[%s]\n' "$n" "$op" "$a" "$b" "$rc" "$(be_len)" "$(be_join)"
  n=$((n + 1))
done < "$OPS"
DRIVER

# backend 1: a real bash array / настоящий массив bash
cat > "${tmp}/native.sh" <<'NATIVE'
A=()
be_len() { printf '%s\n' "${#A[@]}"; }
be_push() { A+=("$1"); }
be_norm() { local n=${#A[@]}; idx=$1; if (( idx < 0 )); then idx=$((n + idx)); fi; (( idx >= 0 && idx <= n )); }
be_get() { be_norm "$1" && (( idx < ${#A[@]} )) || return 1; printf '%s\n' "${A[idx]}"; }
be_set() { be_norm "$1" || return 1; A[idx]=$2; }
be_pop() { local n=${#A[@]}; (( n > 0 )) || return 1; printf '%s\n' "${A[n-1]}"; unset "A[n-1]"; }
be_shift() { (( ${#A[@]} > 0 )) || return 1; printf '%s\n' "${A[0]}"; A=("${A[@]:1}"); }
be_remove_at() { be_norm "$1" && (( idx < ${#A[@]} )) || return 1; A=("${A[@]:0:idx}" "${A[@]:idx+1}"); }
be_index_of() { local j; for (( j = 0; j < ${#A[@]}; j++ )); do if [[ "${A[j]}" == "$1" ]]; then printf '%s\n' "$j"; return 0; fi; done; return 1; }
be_join() { local IFS=,; printf '%s' "${A[*]}"; }
be_clear() { A=(); }
NATIVE

# backend 2: core/data.sh in the shell under test / core/data.sh в проверяемой оболочке
cat > "${tmp}/layer.sh" <<LAYER
for f in bootstrap/shell.sh core/prereq.sh core/data.sh; do
  BS_CURRENT_FILE="${root}/\$f"
  . "${root}/\$f"
done
be_len() { bs_arr_len fz; }
be_push() { bs_arr_push fz "\$1"; }
be_get() { bs_arr_get fz "\$1"; }
be_set() { bs_arr_set fz "\$1" "\$2"; }
be_pop() { bs_arr_pop fz __fz_v || return 1; printf '%s\n' "\$__fz_v"; }
be_shift() { bs_arr_shift fz __fz_v || return 1; printf '%s\n' "\$__fz_v"; }
be_remove_at() { bs_arr_remove_at fz "\$1"; }
be_index_of() { bs_arr_index_of fz "\$1"; }
be_join() { __fz_j=\$(bs_arr_join fz ,); printf '%s' "\$__fz_j"; }
be_clear() { bs_arr_clear fz; }
LAYER

status=0
for (( seed = 1; seed <= seeds; seed++ )); do
  RANDOM=${seed}
  : > "${tmp}/ops"
  for (( i = 0; i < ops; i++ )); do
    r=$(( RANDOM % 100 )); v=$(( RANDOM % 10 )); x=$(( RANDOM % 14 - 5 ))   # index −5 … 8
    if   (( r < 24 )); then echo "push ${v}"
    elif (( r < 34 )); then echo "pop"
    elif (( r < 44 )); then echo "shift"
    elif (( r < 58 )); then echo "set ${x} ${v}"
    elif (( r < 68 )); then echo "remove_at ${x}"
    elif (( r < 82 )); then echo "get ${x}"
    elif (( r < 92 )); then echo "index_of ${v}"
    elif (( r < 98 )); then echo "contains ${v}"
    else echo "clear"
    fi
  done >> "${tmp}/ops"
  { cat "${tmp}/vals.sh" "${tmp}/native.sh" "${tmp}/driver.sh"; } > "${tmp}/run_native.sh"
  { cat "${tmp}/vals.sh" "${tmp}/layer.sh" "${tmp}/driver.sh"; } > "${tmp}/run_layer.sh"
  OPS="${tmp}/ops" env -i PATH="${PATH}" HOME="${tmp}" OPS="${tmp}/ops" bash "${tmp}/run_native.sh" > "${tmp}/native.out" 2>&1
  (cd "${root}" && OPS="${tmp}/ops" env -i PATH="${PATH}" HOME="${tmp}" OPS="${tmp}/ops" "${sh_cmd[@]}" "${tmp}/run_layer.sh") > "${tmp}/layer.out" 2>&1
  if cmp -s "${tmp}/native.out" "${tmp}/layer.out"; then
    printf 'seed %-3s %s ops: equal (%s lines)\n' "${seed}" "${ops}" "$(wc -l < "${tmp}/native.out")"
  else
    status=1
    printf 'seed %-3s DIFFERENT; first difference:\n' "${seed}"
    diff "${tmp}/native.out" "${tmp}/layer.out" | head -n 8 | sed 's/^/      /'
  fi
done
echo
if (( status == 0 )); then
  echo "OK: ${seeds} seed(s) x ${ops} ops, ${sh_name} == native bash array / ${sh_name} совпал с массивом bash"
else
  echo "FAIL: bs_arr_* in ${sh_name} differs from the native array / bs_arr_* в ${sh_name} расходится с массивом bash"
fi
exit "${status}"
