#!/bin/sh
# shellcheck shell=sh
# @shell posix — grep/find/awk/sed over text; no bash constructs / grep/find/awk/sed по тексту, без конструкций bash
# @tier dev — an advisory inventory, not a CI gate unless you wire it / советующий инвентарь, не гейт CI, пока не подключите
#
# scripts/check_var_contracts.sh — найти прямые обращения к переменным, объявленным
# через слой метаданных (bs_var_declare). Прямое ЧТЕНИЕ `$ИМЯ`/`${ИМЯ` флагается
# только когда `@ops` не разрешает `read`; прямая ЗАПИСЬ (`ИМЯ=`, `unset ИМЯ`,
# `export ИМЯ`) флагается всегда (объявляющая строка сразу после `# @var` разрешена).
# Это эвристика, а не парсер shell: она не видит `eval` и nameref.
# scripts/check_var_contracts.sh — find direct accesses to variables declared through
# the metadata layer (bs_var_declare). A direct READ `$NAME`/`${NAME` is flagged only
# when `@ops` does not allow `read`; a direct WRITE (`NAME=`, `unset NAME`,
# `export NAME`) is always flagged (the declaring line right after `# @var` is allowed).
# It is a heuristic, not a shell parser: it cannot see `eval` or namerefs.
#
# Использование / Usage:
#   sh scripts/check_var_contracts.sh                       # имена+ops из core/var-schema.sh / names+ops from the manifest
#   sh scripts/check_var_contracts.sh --from-scan           # имена+ops из аннотаций / names+ops from the annotations
#   sh scripts/check_var_contracts.sh --vars A,B            # только имена, ops неизвестны / names only, ops unknown
#   sh scripts/check_var_contracts.sh PATH...               # свои пути / custom paths
#
# Exit 0 — нарушений нет; 1 — есть (для CI); 2 — ошибка использования.

set -eu

manifest=core/var-schema.sh
from_scan=0
vars=
paths="core lib bootstrap bs boot.sh install.sh"

usage() {
  printf '%s\n' \
    'Usage: scripts/check_var_contracts.sh [--from-scan] [--vars A,B] [PATH...]' \
    '' \
    '  --from-scan  take names and @ops from # @var annotations, not the manifest' \
    '  --vars A,B   check only these names (ops unknown: reads and writes are allowed)' \
    '' \
    'Default paths: core/ lib/ bootstrap/ and bs boot.sh install.sh. The manifest itself is skipped.'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --from-scan) from_scan=1 ;;
    --vars) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; vars=$2; shift ;;
    --vars=*) vars=${1#--vars=} ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    --*) usage >&2; exit 2 ;;
    *) break ;;
  esac
  shift
done
[ "$#" -gt 0 ] && paths=$*

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
files=$tmp/files
map=$tmp/map
findings=$tmp/findings
: > "$findings"

# Имена и ops объявленных переменных, в виде ИМЯ=ops / The names and ops, as NAME=ops
if [ -n "$vars" ]; then
  printf '%s' "$vars" | tr ',' '\n' | sed '/^$/d' | while IFS= read -r __n; do
    printf '%s=\n' "$__n"
  done | sort -u > "$map"
elif [ "$from_scan" = 1 ]; then
  for p in $paths; do
    if [ -d "$p" ]; then
      find "$p" -type f -name '*.sh' 2>/dev/null
    elif [ -f "$p" ]; then
      printf '%s\n' "$p"
    fi
  done | xargs awk '
    /^[[:space:]]*# @var / { v = $0; sub(/^[[:space:]]*# @var /, "", v); sub(/[[:space:]].*/, "", v); name = v; ops = "" }
    name != "" && /^[[:space:]]*# @ops / { o = $0; sub(/^[[:space:]]*# @ops /, "", o); sub(/[[:space:]].*/, "", o); ops = o }
    name != "" && $0 !~ /^[[:space:]]*#/ { printf "%s=%s\n", name, ops; name = "" }
    END { if (name != "") printf "%s=%s\n", name, ops }
  ' 2>/dev/null | sort -u > "$map"
else
  [ -s "$manifest" ] || { printf 'check_var_contracts: %s missing or empty; use --from-scan\n' "$manifest" >&2; exit 2; }
  awk -F"'" '/^bs_var_declare / {
    name = $1; sub(/^bs_var_declare /, "", name); sub(/[[:space:]]*$/, "", name);
    spec = $2; ops = "";
    n = split(spec, segs, ";");
    for (i = 1; i <= n; i++) { if (segs[i] ~ /^ops=/) { sub(/^ops=/, "", segs[i]); ops = segs[i]; } }
    printf "%s=%s\n", name, ops;
  }' "$manifest" | sort -u > "$map"
fi

# Проверяемые файлы / The files to check
for p in $paths; do
  if [ -d "$p" ]; then
    find "$p" -type f -name '*.sh' 2>/dev/null
  elif [ -f "$p" ]; then
    printf '%s\n' "$p"
  fi
done | sort -u > "$files"

__map=$(tr '\n' ' ' < "$map")
__map=${__map% }

# awk находит прямые чтения (только у write-only) и прямые записи; объявляющая строка
# ИМЯ= сразу после блока `# @var` разрешена. Комментарии и манифест пропускаются.
# Имена собраны в одну альтернацию, чтобы не гонять цикл по именам на каждую строку.
# awk finds direct reads (only for write-only vars) and direct writes; the declaring
# `NAME=` line right after its `# @var` block is allowed. Comments and the manifest are
# skipped. The names are joined into one alternation, not looped per line.
while IFS= read -r __f; do
  [ "$__f" = "$manifest" ] && continue
  awk -v map="$__map" '
    BEGIN {
      n = split(map, a, " ");
      names = ""; nrd = 0;
      for (i = 1; i <= n; i++) {
        if (a[i] == "") continue;
        name = a[i]; ops = "";
        if (index(a[i], "=") > 0) { name = substr(a[i], 1, index(a[i], "=") - 1); ops = substr(a[i], index(a[i], "=") + 1); }
        declared[name] = 1;
        names = names (names == "" ? "" : "|") name;
        if (ops != "") {
          m = split(ops, oplist, ","); has_read = 0;
          for (j = 1; j <= m; j++) if (oplist[j] == "read") has_read = 1;
          if (!has_read) { rd[++nrd] = name; }
        }
      }
      write_re = "^[[:space:]]*(" names ")=";
      unset_re = "^[[:space:]]*(unset|export)[[:space:]]+(" names ")([[:space:]]|$)";
    }
    /^[[:space:]]*# @var / {
      v = $0; sub(/^[[:space:]]*# @var /, "", v); sub(/[[:space:]].*/, "", v);
      if (v in declared) pending = v;
    }
    {
      if ($0 ~ /^[[:space:]]*#/) next;
      decl_ok = "";
      if (pending != "" && $0 ~ ("^[[:space:]]*" pending "=")) decl_ok = pending;
      pending = "";
      for (i = 1; i <= nrd; i++) {
        v = rd[i];
        if ($0 ~ ("\\$" v "([^A-Za-z0-9_]|$)") || $0 ~ ("\\${" v "([^A-Za-z0-9_]|$)")) {
          print FILENAME ":" NR ": direct read of $" v ": " $0;
        }
      }
      if ($0 ~ write_re) {
        t = $0; sub(/^[[:space:]]*/, "", t); nm = t; sub(/=.*/, "", nm);
        if (nm != decl_ok && (nm in declared)) {
          print FILENAME ":" NR ": direct write to " nm ": " $0;
        }
      }
      if ($0 ~ unset_re) {
        t = $0; sub(/^[[:space:]]*(unset|export)[[:space:]]+/, "", t); nm = t; sub(/[[:space:]].*/, "", nm);
        if (nm in declared) {
          print FILENAME ":" NR ": direct unset/export of " nm ": " $0;
        }
      }
    }
  ' "$__f" >> "$findings"
done < "$files"

if [ -s "$findings" ]; then
  printf 'check_var_contracts: direct accesses (advisory) / прямые обращения (совет):\n' >&2
  cat "$findings" >&2
  exit 1
fi

printf 'check_var_contracts: no direct accesses / прямых обращений нет\n'
exit 0
