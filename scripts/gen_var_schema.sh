#!/bin/sh
# shellcheck shell=sh
# @shell posix — grep/find/sed over text; no bash constructs / grep/find/sed по тексту, без конструкций bash
# @tier dev — a developer generator, not part of the runtime / генератор разработчика, не часть рантайма
#
# scripts/gen_var_schema.sh — прочитать аннотации `# @var`/`# @type`/`# @ops`/… из
# core/, lib/, bootstrap/ (или заданных путей) и собрать POSIX-манифест
# core/var-schema.sh: по строке `bs_var_declare ИМЯ 'спецификация'` на переменную.
# Это единственный источник истины, генерируемый из комментариев; runtime не парсит
# комментарии. Манифест подключается после core/var.sh (там определён bs_var_declare).
# scripts/gen_var_schema.sh — read the `# @var`/`# @type`/`# @ops`/… annotations from
# core/, lib/, bootstrap/ (or the given paths) and assemble the POSIX manifest
# core/var-schema.sh: one `bs_var_declare NAME 'spec'` line per variable. It is the
# single source of truth generated from the comments; the runtime never parses comments.
# The manifest is sourced after core/var.sh (where bs_var_declare lives).
#
# Использование / Usage:
#   sh scripts/gen_var_schema.sh                    # пишет core/var-schema.sh / writes core/var-schema.sh
#   sh scripts/gen_var_schema.sh --list             # имя<TAB>спецификация в stdout / name<TAB>spec to stdout
#   sh scripts/gen_var_schema.sh --check            # сравнить с core/var-schema.sh, exit 1 при дрейфе / compare, exit 1 on drift
#   sh scripts/gen_var_schema.sh --out FILE PATH... # свой выход и пути / custom output and paths
#
# Аннотации пишутся так / The annotations look like:
#   # @var CACHE_TTL
#   # @type int
#   # @ops read,write
#   # @default 60
#   CACHE_TTL=60

set -eu

out=core/var-schema.sh
check=0
list=0
paths="core lib bootstrap"

usage() {
  printf '%s\n' \
    'Usage: scripts/gen_var_schema.sh [--list] [--check] [--out FILE] [PATH...]' \
    '' \
    '  --list   print name<TAB>spec to stdout instead of writing the manifest' \
    '  --check  compare the generated manifest with --out (default core/var-schema.sh)' \
    '  --out F  write the manifest to F (default core/var-schema.sh)' \
    '' \
    'Default paths: core/ lib/ bootstrap/. A directory is scanned for *.sh recursively.'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --list) list=1 ;;
    --check) check=1 ;;
    --out) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; out=$2; shift ;;
    --out=*) out=${1#--out=} ;;
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
entries=$tmp/entries
files=$tmp/files
: > "$entries"

# Собрать файлы / Collect the files
for p in $paths; do
  if [ -d "$p" ]; then
    find "$p" -type f -name '*.sh' 2>/dev/null
  elif [ -f "$p" ]; then
    printf '%s\n' "$p"
  fi
done | sort -u > "$files"

# Проверка имени / A name check: [A-Za-z_][A-Za-z0-9_]*
name_ok() {
  case "${1-}" in
    ''|[0-9]*|*[!A-Za-z0-9_]*) return 1 ;;
  esac
  return 0
}

# Экранировать одинарную кавычку для '…' / Escape a single quote for '…'
qspec() {
  printf '%s' "${1-}" | sed "s/'/'\\\\''/g"
}

# Разобрать один файл / Parse one file
scan_file() {
  __gs_f=$1
  __gs_inblock=0
  __gs_name=
  __gs_spec=
  __gs_ln=0
  while IFS= read -r __gs_line; do
    __gs_ln=$((__gs_ln + 1))
    case $__gs_line in
      '# @var '*)
        if [ "$__gs_inblock" = 1 ]; then
          printf '%s\t%s\n' "$__gs_name" "$__gs_spec" >> "$entries"
        fi
        __gs_name=${__gs_line#'# @var '}
        __gs_name=${__gs_name%% *}
        __gs_spec=
        __gs_inblock=1
        ;;
      '# @'*)
        if [ "$__gs_inblock" = 1 ]; then
          __gs_body=${__gs_line#'# @'}
          __gs_key=${__gs_body%% *}
          __gs_val=${__gs_body#* }
          [ "$__gs_val" = "$__gs_body" ] && __gs_val=
          case $__gs_key in
            type|ops|scope|visibility|default|range|unit|on_invalid|on_change|secret|since|deprecated|owner|description) ;;
            *)
              printf 'gen_var_schema: %s:%s: unknown key @%s\n' "$__gs_f" "$__gs_ln" "$__gs_key" >&2
              exit 2 ;;
          esac
          case $__gs_val in
            *';'*)
              printf 'gen_var_schema: %s:%s: @%s value must not contain ";"\n' "$__gs_f" "$__gs_ln" "$__gs_key" >&2
              exit 2 ;;
          esac
          __gs_spec="${__gs_spec}${__gs_spec:+;}${__gs_key}=${__gs_val}"
        fi
        ;;
      *)
        if [ "$__gs_inblock" = 1 ]; then
          if ! name_ok "$__gs_name"; then
            printf 'gen_var_schema: %s: bad variable name: %s\n' "$__gs_f" "$__gs_name" >&2
            exit 2
          fi
          printf '%s\t%s\n' "$__gs_name" "$__gs_spec" >> "$entries"
          __gs_inblock=0
          __gs_name=
          __gs_spec=
        fi
        ;;
    esac
  done < "$__gs_f"
  if [ "$__gs_inblock" = 1 ]; then
    name_ok "$__gs_name" || { printf 'gen_var_schema: %s: bad variable name: %s\n' "$__gs_f" "$__gs_name" >&2; exit 2; }
    printf '%s\t%s\n' "$__gs_name" "$__gs_spec" >> "$entries"
  fi
}

while IFS= read -r __gs_f; do
  scan_file "$__gs_f"
done < "$files"

# Дубликат имени / A duplicate name
__gs_dup=$(cut -f1 "$entries" | sort | uniq -d)
if [ -n "$__gs_dup" ]; then
  printf 'gen_var_schema: duplicate @var name(s): %s\n' "$__gs_dup" >&2
  exit 2
fi

emit() {
  printf '%s\n' '#!/bin/sh'
  printf '%s\n' '# shellcheck shell=sh'
  printf '%s\n' '# @shell posix — only bs_var_declare calls, no code / только вызовы bs_var_declare, без кода'
  printf '%s\n' '# @tier core — sourced after core/var.sh; builtins and the loaded function / подключается после core/var.sh'
  printf '%s\n' '# Generated by scripts/gen_var_schema.sh — do not edit. / Сгенерировано scripts/gen_var_schema.sh — не редактируйте.'
  printf '%s\n' '# Declares the module-level variables of the metadata layer. / Объявляет переменные модульного уровня слоя метаданных.'
  printf '%s\n' '# Source it after core/var.sh. / Подключайте после core/var.sh.'
  printf '%s\n' ''
  while IFS="$(printf '\t')" read -r __gs_n __gs_s; do
    [ -n "$__gs_n" ] || continue
    printf 'bs_var_declare %s '\''%s'\''\n' "$__gs_n" "$(qspec "$__gs_s")"
  done < "$entries"
}

if [ "$list" = 1 ]; then
  while IFS="$(printf '\t')" read -r __gs_n __gs_s; do
    [ -n "$__gs_n" ] || continue
    printf '%s\t%s\n' "$__gs_n" "$__gs_s"
  done < "$entries"
  exit 0
fi

emit > "$tmp/manifest.sh"

if [ "$check" = 1 ]; then
  if cmp -s "$tmp/manifest.sh" "$out"; then
    printf 'gen_var_schema: manifest is up to date / манифест актуален: %s\n' "$out"
    exit 0
  fi
  printf 'gen_var_schema: manifest drifted / манифест разошёлся: %s\n' "$out" >&2
  diff -u "$out" "$tmp/manifest.sh" >&2 || true
  printf 'Run: sh scripts/gen_var_schema.sh\n' >&2
  exit 1
fi

cp "$tmp/manifest.sh" "$out"
printf 'gen_var_schema: wrote %s (%s declaration(s)) / записан %s (%s объявлений)\n' "$out" "$(wc -l < "$entries")" "$out" "$(wc -l < "$entries")"
