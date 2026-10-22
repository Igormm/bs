#!/bin/sh
# shellcheck shell=sh
# shellcheck disable=SC2154  # __bs_args_cf_kind/__bs_args_cp_kind присваивает bs_args_mget через eval / assigned by bs_args_mget through eval
# @shell posix — валидный POSIX sh: case, printf, cat, sort, tr; генераторы только печатают текст / valid POSIX sh: case, printf, cat, sort, tr; the generators only print text
# @tier core — builtins, sort and tr; works everywhere
#
# core/args-completion.sh — генераторы автодополнения для core/args.sh
# core/args-completion.sh — completion generators for core/args.sh
#
# Подключается в конце core/args.sh, поэтому `load "core/args"` по-прежнему даёт
# bs_args_completion и args::completion. Отдельно подключать не нужно.
# Sourced at the end of core/args.sh, so `load "core/args"` still provides
# bs_args_completion and args::completion. Do not source it on its own.
#
# @depends core/args

# Без args нет ни дерева, ни bs_args_mget / Without args there is no tree and no bs_args_mget
if ! command -v bs_args_mget >/dev/null 2>&1; then
  printf 'BS: core/args-completion.sh: load core/args first / сначала подключите core/args\n' >&2
  return 1
fi

bs_guard "ARGS_COMPLETION" || return 0

# @private
# @description Список флагов для генераторов: имя<TAB>вид<TAB>значения, по строке на флаг
# @description Flags for the generators: name<TAB>kind<TAB>values, one flag per line
bs_args_completion_flags() {
  if [ "$(bs_map_count bs_args_flags)" -eq 0 ]; then return 0; fi
  bs_map_keys bs_args_flags | sort | while IFS= read -r __bs_args_cf_n; do
    bs_args_mget bs_args_flags "$__bs_args_cf_n" __bs_args_cf_kind
    bs_args_mget bs_args_flag_val "$__bs_args_cf_n" __bs_args_cf_v
    if [ "$__bs_args_cf_kind" = "value" ]; then
      case "$__bs_args_cf_v" in
        enum:*) printf '%s\tenum\t%s\n' "$__bs_args_cf_n" "${__bs_args_cf_v#enum:}" ;;
        *)      printf '%s\tvalue\t\n' "$__bs_args_cf_n" ;;
      esac
    else
      printf '%s\tbool\t\n' "$__bs_args_cf_n"
    fi
  done
}

# @description Сгенерировать скрипт автодополнения для bash (по умолчанию), zsh, fish или nu
# @description Generate a completion script for bash (default), zsh, fish or nu
#   Вывод можно сохранить в файл и подключить через source или ~/.bashrc
#   The output can be saved to a file and loaded via source or ~/.bashrc
# @param $1 program name / имя программы
# @param $2 [optional] shell: bash (default), zsh, fish, nu; also BS_COMPLETION_SHELL
# @example
#   args::completion "deploy.sh" > /etc/bash_completion.d/deploy.sh
#   args::completion "deploy.sh" zsh > ~/.zfunc/_deploy.sh
bs_args_completion() {
  __bs_args_cp_prog=${1:-${0##*/}}
  __bs_args_cp_target=$(bs_shell_of_name "${2:-${BS_COMPLETION_SHELL:-bash}}")

  if [ "$(bs_map_count bs_args_tree)" -eq 0 ] && [ "$(bs_map_count bs_args_flags)" -eq 0 ]; then
    bs_log_warn "args::completion: nothing declared, call args::define, args::level or args::flag first"
    return "${E_ERROR:-1}"
  fi

  case "$__bs_args_cp_target" in
    bash) bs_args_completion_bash "$__bs_args_cp_prog" ;;
    zsh)  bs_args_completion_zsh "$__bs_args_cp_prog" ;;
    fish) bs_args_completion_fish "$__bs_args_cp_prog" ;;
    nu)   bs_args_completion_nu "$__bs_args_cp_prog" ;;
    *)
      bs_log_error "args::completion: no generator for '${2:-${BS_COMPLETION_SHELL:-}}' (supported: bash zsh fish nu)"
      return "${E_ERROR:-1}"
      ;;
  esac
}

# @private
# @description Генератор bash-completion; печатает текст, не выполняет его / Bash-completion generator; prints text, does not run it
# @param $1 program name / имя программы
# shell-gate: в теле — текст bash-completion (compgen, complete -F), который функция печатает, а не выполняет
# shell-gate: the body holds bash-completion text (compgen, complete -F) that the function prints, not runs
bs_args_completion_bash() {
  __bs_args_cp_prog=$1
  # Имя функции: только [a-zA-Z0-9_] / Function name: [a-zA-Z0-9_] only
  __bs_args_cp_fn="_$(printf '%s' "$__bs_args_cp_prog" | tr -c 'a-zA-Z0-9_' '_')_completion"

  # Список всех флагов для дополнения / All flags for completion
  __bs_args_cp_words="--help"
  __bs_args_cp_vflags=""
  if [ "$(bs_map_count bs_args_flags)" -gt 0 ]; then
    # Список value-флагов (после них значение не дополняется);
    # enum-флаги исключаются — для них дополняются значения
    # Value flags list (their values are not completed);
    # enum flags are excluded — their values ARE completed
    __bs_args_cp_sorted=$(bs_map_keys bs_args_flags | sort)
    bs_arr_from_lines bs_args_cp_names "$__bs_args_cp_sorted"
    eval "$(bs_arr_to_args bs_args_cp_names)"
    for __bs_args_cp_n in "$@"; do
      __bs_args_cp_words="${__bs_args_cp_words} --${__bs_args_cp_n}"
      bs_args_mget bs_args_flags "$__bs_args_cp_n" __bs_args_cp_kind
      bs_args_mget bs_args_flag_val "$__bs_args_cp_n" __bs_args_cp_v
      if [ "$__bs_args_cp_kind" = "value" ]; then
        case "$__bs_args_cp_v" in
          enum:*) ;;
          *) __bs_args_cp_vflags="${__bs_args_cp_vflags} --${__bs_args_cp_n}" ;;
        esac
      fi
    done
  fi

  __bs_args_cp_max=$(bs_args_max_level)

  cat <<EOF
# Bash completion for ${__bs_args_cp_prog} — generated by core/args.sh (args::completion)
# Автодополнение Bash для ${__bs_args_cp_prog} — сгенерировано core/args.sh (args::completion)
${__bs_args_cp_fn}() {
    local cur prev word positional i
    COMPREPLY=()
    cur="\${COMP_WORDS[COMP_CWORD]}"
    prev="\${COMP_WORDS[COMP_CWORD-1]}"
EOF

  # После value-флага значение не дополняем / Do not complete after a value flag
  __bs_args_cp_pat=""
  if [ -n "$__bs_args_cp_vflags" ]; then
    bs_utils_split bs_args_wa "$__bs_args_cp_vflags" ' '
    __bs_args_cp_pat=$(bs_arr_join bs_args_wa '|')
    cat <<EOF

    # value-флаги: значение не дополняется / value flags: value is not completed
    case "\${prev}" in
        ${__bs_args_cp_pat}) return 0 ;;
    esac
EOF
  fi

  # enum-значения для value-флагов / enum values for value flags
  if [ "$(bs_map_count bs_args_flags)" -gt 0 ]; then
    eval "$(bs_arr_to_args bs_args_cp_names)"
    for __bs_args_cp_n in "$@"; do
      bs_args_mget bs_args_flags "$__bs_args_cp_n" __bs_args_cp_kind
      bs_args_mget bs_args_flag_val "$__bs_args_cp_n" __bs_args_cp_v
      if [ "$__bs_args_cp_kind" = "value" ]; then
        case "$__bs_args_cp_v" in
          enum:*)
            __bs_args_cp_enum=$(printf '%s' "${__bs_args_cp_v#enum:}" | tr ',' ' ')
            __bs_args_cp_enum_bar=$(printf '%s' "$__bs_args_cp_enum" | tr ' ' '|')
            cat <<EOF

    # enum-значения: --${__bs_args_cp_n} <${__bs_args_cp_enum_bar}>
    case "\${prev}" in
        --${__bs_args_cp_n}) COMPREPLY=( \$(compgen -W "${__bs_args_cp_enum}" -- "\${cur}") ); return 0 ;;
    esac
EOF
            ;;
        esac
      fi
    done
  fi

  cat <<EOF

    # Дополнение флагов / Flag completion
    if [[ "\${cur}" == --* ]]; then
        COMPREPLY=( \$(compgen -W "${__bs_args_cp_words}" -- "\${cur}") )
        return 0
    fi

    # Считаем уже введённые позиционные параметры (флаги уровней не занимают)
    # Count positionals already entered (flags do not occupy levels)
    positional=0
    for ((i = 1; i < COMP_CWORD; i++)); do
        word="\${COMP_WORDS[i]}"
        case "\${word}" in
EOF

  if [ -n "$__bs_args_cp_vflags" ]; then
    cat <<EOF
            ${__bs_args_cp_pat}) ((++i)) ;;   # пропускаем значение value-флага / skip value flag value
EOF
  fi

  cat <<EOF
            --*) ;;                      # bool-флаг / bool flag
            *) ((++positional)) ;;
        esac
    done

    # Выбираем варианты по уровню / Choices by level
    local choices=""
    case \$((positional + 1)) in
EOF

  __bs_args_cp_level=1
  while [ "$__bs_args_cp_level" -le "$__bs_args_cp_max" ]; do
    bs_args_mget bs_args_tree "$__bs_args_cp_level" __bs_args_cp_list
    if [ -n "$__bs_args_cp_list" ]; then
      printf '        %d) choices="%s" ;;\n' "$__bs_args_cp_level" "$__bs_args_cp_list"
    fi
    __bs_args_cp_level=$((__bs_args_cp_level + 1))
  done

  cat <<EOF
    esac

    COMPREPLY=( \$(compgen -W "\${choices} ${__bs_args_cp_words}" -- "\${cur}") )
    return 0
}
complete -F ${__bs_args_cp_fn} "${__bs_args_cp_prog}"
EOF
}

# ==========================================
# Автодополнение zsh, fish, nushell / Completion for zsh, fish, nushell
# Не проверено на реальных fish и nu: проверяется только текст.
# Not verified on real fish and nu: only the text is tested.
# ==========================================

# @private
bs_args_completion_zsh() {
  __bs_args_zs_prog=$1
  __bs_args_zs_fn="_$(printf '%s' "$__bs_args_zs_prog" | tr -c 'a-zA-Z0-9_' '_')_completion"
  bs_arr_clear bs_args_specs
  bs_arr_push bs_args_specs "'--help[show help]'"
  __bs_args_zs_flags=$(bs_args_completion_flags)
  while IFS="$(printf '\t')" read -r __bs_args_zs_name __bs_args_zs_kind __bs_args_zs_values; do
    [ -n "$__bs_args_zs_name" ] || continue
    case "$__bs_args_zs_kind" in
      enum)
        __bs_args_zs_vals=$(printf '%s' "$__bs_args_zs_values" | tr ',' ' ')
        bs_arr_push bs_args_specs "$(bs_quote "--${__bs_args_zs_name}=:value:(${__bs_args_zs_vals})")" ;;
      value) bs_arr_push bs_args_specs "$(bs_quote "--${__bs_args_zs_name}=:value: ")" ;;
      *)     bs_arr_push bs_args_specs "$(bs_quote "--${__bs_args_zs_name}")" ;;
    esac
  done <<EOF
${__bs_args_zs_flags}
EOF
  __bs_args_zs_max=$(bs_args_max_level)
  __bs_args_zs_level=1
  while [ "$__bs_args_zs_level" -le "$__bs_args_zs_max" ]; do
    bs_args_mget bs_args_tree "$__bs_args_zs_level" __bs_args_zs_list
    if [ -n "$__bs_args_zs_list" ]; then
      bs_arr_push bs_args_specs "$(bs_quote "${__bs_args_zs_level}:argument ${__bs_args_zs_level}:(${__bs_args_zs_list})")"
    fi
    __bs_args_zs_level=$((__bs_args_zs_level + 1))
  done
  printf '#compdef %s\n' "$__bs_args_zs_prog"
  printf '# zsh completion for %s — generated by core/args.sh (args::completion)\n' "$__bs_args_zs_prog"
  printf '# Автодополнение zsh для %s — сгенерировано core/args.sh (args::completion)\n' "$__bs_args_zs_prog"
  printf '%s() {\n  _arguments -S \\\n' "$__bs_args_zs_fn"
  __bs_args_zs_n=$(bs_arr_len bs_args_specs)
  __bs_args_zs_i=0
  while [ "$__bs_args_zs_i" -lt "$__bs_args_zs_n" ]; do
    __bs_args_zs_spec=$(bs_arr_get bs_args_specs "$__bs_args_zs_i")
    if [ "$__bs_args_zs_i" -lt $((__bs_args_zs_n - 1)) ]; then
      printf '    %s \\\n' "$__bs_args_zs_spec"
    else
      printf '    %s\n' "$__bs_args_zs_spec"
    fi
    __bs_args_zs_i=$((__bs_args_zs_i + 1))
  done
  printf '}\n'
  printf 'compdef %s %s\n' "$__bs_args_zs_fn" "$__bs_args_zs_prog"
}

# @private
bs_args_completion_fish() {
  __bs_args_fi_prog=$1
  __bs_args_fi_q=$(bs_quote "$__bs_args_fi_prog")
  printf '# fish completion for %s — generated by core/args.sh (args::completion)\n' "$__bs_args_fi_prog"
  printf '# Автодополнение fish для %s — сгенерировано core/args.sh (args::completion)\n' "$__bs_args_fi_prog"
  printf 'complete -c %s -f\n' "$__bs_args_fi_q"
  printf 'complete -c %s -l help -d %s\n' "$__bs_args_fi_q" "$(bs_quote "show help")"
  __bs_args_fi_flags=$(bs_args_completion_flags)
  while IFS="$(printf '\t')" read -r __bs_args_fi_name __bs_args_fi_kind __bs_args_fi_values; do
    [ -n "$__bs_args_fi_name" ] || continue
    case "$__bs_args_fi_kind" in
      enum)  printf 'complete -c %s -l %s -x -a %s\n' "$__bs_args_fi_q" "$__bs_args_fi_name" "$(bs_quote "$(printf '%s' "$__bs_args_fi_values" | tr ',' ' ')")" ;;
      value) printf 'complete -c %s -l %s -r\n' "$__bs_args_fi_q" "$__bs_args_fi_name" ;;
      *)     printf 'complete -c %s -l %s\n' "$__bs_args_fi_q" "$__bs_args_fi_name" ;;
    esac
  done <<EOF
${__bs_args_fi_flags}
EOF
  __bs_args_fi_max=$(bs_args_max_level)
  __bs_args_fi_level=1
  while [ "$__bs_args_fi_level" -le "$__bs_args_fi_max" ]; do
    bs_args_mget bs_args_tree "$__bs_args_fi_level" __bs_args_fi_list
    if [ -n "$__bs_args_fi_list" ]; then
      printf 'complete -c %s -n %s -a %s\n' "$__bs_args_fi_q" \
        "$(bs_quote "__fish_is_nth_token ${__bs_args_fi_level}")" "$(bs_quote "$__bs_args_fi_list")"
    fi
    __bs_args_fi_level=$((__bs_args_fi_level + 1))
  done
}

# @private
bs_args_completion_nu() {
  __bs_args_nu_prog=$1
  printf '# nushell completion for %s — generated by core/args.sh (args::completion)\n' "$__bs_args_nu_prog"
  printf '# Автодополнение nushell для %s — сгенерировано core/args.sh (args::completion)\n' "$__bs_args_nu_prog"
  bs_arr_clear bs_args_decl
  bs_arr_push bs_args_decl "  --help"
  __bs_args_nu_flags=$(bs_args_completion_flags)
  while IFS="$(printf '\t')" read -r __bs_args_nu_name __bs_args_nu_kind __bs_args_nu_values; do
    [ -n "$__bs_args_nu_name" ] || continue
    case "$__bs_args_nu_kind" in
      enum)
        printf 'def "nu-complete %s --%s" [] { [' "$__bs_args_nu_prog" "$__bs_args_nu_name"
        bs_utils_split bs_args_wa "$__bs_args_nu_values" ','
        eval "$(bs_arr_to_args bs_args_wa)"
        for __bs_args_nu_item in "$@"; do printf ' "%s"' "$__bs_args_nu_item"; done
        printf ' ] }\n'
        bs_arr_push bs_args_decl "  --${__bs_args_nu_name}: string@\"nu-complete ${__bs_args_nu_prog} --${__bs_args_nu_name}\"" ;;
      value) bs_arr_push bs_args_decl "  --${__bs_args_nu_name}: string" ;;
      *)     bs_arr_push bs_args_decl "  --${__bs_args_nu_name}" ;;
    esac
  done <<EOF
${__bs_args_nu_flags}
EOF
  __bs_args_nu_max=$(bs_args_max_level)
  __bs_args_nu_level=1
  while [ "$__bs_args_nu_level" -le "$__bs_args_nu_max" ]; do
    bs_args_mget bs_args_tree "$__bs_args_nu_level" __bs_args_nu_list
    if [ -n "$__bs_args_nu_list" ]; then
      printf 'def "nu-complete %s arg %d" [] { [' "$__bs_args_nu_prog" "$__bs_args_nu_level"
      bs_utils_split bs_args_wa "$__bs_args_nu_list" ' '
      eval "$(bs_arr_to_args bs_args_wa)"
      for __bs_args_nu_item in "$@"; do printf ' "%s"' "$__bs_args_nu_item"; done
      printf ' ] }\n'
      bs_arr_push bs_args_decl "  arg${__bs_args_nu_level}?: string@\"nu-complete ${__bs_args_nu_prog} arg ${__bs_args_nu_level}\""
    fi
    __bs_args_nu_level=$((__bs_args_nu_level + 1))
  done
  printf 'extern "%s" [\n' "$__bs_args_nu_prog"
  eval "$(bs_arr_to_args bs_args_decl)"
  printf '%s\n' "$@"
  printf ']\n'
}

# Псевдоним переезжает вместе с функцией / The alias moves with the function
bs_shell_alias bs_args_completion args::completion
