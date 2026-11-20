#!/bin/sh
# shellcheck shell=sh
# @shell posix — валидный POSIX sh: флаги через bs_shell_strict, ловушки пробой ERR, PS4 с ${LINENO-} / valid POSIX sh: flags via bs_shell_strict, ERR probed, PS4 with ${LINENO-}
# @tier core — builtins only; works everywhere
# @depends core/errorhandler
#
# core/strict.sh — строгий режим точки входа одной строкой: strict::enable
# core/strict.sh — entry-point strict mode in one call: strict::enable
#
# ЗАЧЕМ / WHY
#   Вместо рукописного «set -euo pipefail» (который к тому же не переносим: в dash
#   нет pipefail) точка входа под bs вызывает strict::enable. Одна строка включает
#   всё, что BS умеет дать скрипту: флаги строгого режима по возможностям оболочки,
#   IFS точки входа, ловушку EXIT со стеком очистки (bs_cleanup_add), ловушку ERR с
#   трассировкой там, где оболочка её умеет, корректные коды на INT/TERM/HUP и
#   отладочную трассировку по BS_DEBUG=1. Модуль грузится ядром автоматически
#   (полный режим): в скриптах под #!/usr/bin/env bs ничего подключать не нужно.
#   Instead of a hand-written "set -euo pipefail" (which is not portable anyway:
#   dash has no pipefail), an entry point under bs calls strict::enable. One line
#   turns on everything BS can give a script: strict flags per the shell's
#   abilities, the entry-point IFS, an EXIT trap with the cleanup stack
#   (bs_cleanup_add), an ERR trap with a backtrace where the shell has one, proper
#   codes on INT/TERM/HUP, and debug tracing on BS_DEBUG=1. The kernel loads this
#   module automatically (full mode): scripts under #!/usr/bin/env bs need no load.
#
# ПРАВИЛА / RULES
#   * Только точки входа, никогда внутри библиотечных модулей (как и bs_strict).
#     Entry points only, never inside library modules (same as bs_strict).
#   * До ядра (пролог bs/boot.sh/install.sh) работает pre-kernel bs_strict из
#     bootstrap/base.sh: только флаги и IFS, без ловушек и очистки.
#     Before the kernel (the bs/boot.sh/install.sh prologue) the pre-kernel
#     bs_strict of bootstrap/base.sh applies: flags and IFS only, no traps/cleanup.
#   * pipefail включается там, где он есть (bash, zsh, ksh, mksh, busybox ash);
#     в dash его нет — это честно отражает strict::status.
#     pipefail is enabled where it exists (bash, zsh, ksh, mksh, busybox ash);
#     dash has none — strict::status reports that honestly.
#   * Ловушка ERR есть в bash/zsh/ksh/mksh; в dash/ash сбой завершает скрипт через
#     errexit без трассировки, но EXIT-очистка выполняется в любой оболочке.
#     The ERR trap exists in bash/zsh/ksh/mksh; in dash/ash a failure ends the
#     script through errexit without a backtrace, but the EXIT cleanup runs everywhere.
#   * BS_DEBUG=1: трассировка глобальна в bash/dash/ash/ksh; в mksh/zsh set -x внутри
#     функции действует только в ней (особенность оболочек) — там BS_DEBUG трассирует
#     сам вызов enable, а для трассировки всего скрипта нужен «mksh -x»/«zsh -x» или
#     set -x на верхнем уровне. strict::status честно показывает debug=off.
#     BS_DEBUG=1: tracing is global in bash/dash/ash/ksh; in mksh/zsh set -x inside a
#     function applies only within it (a shell quirk) — there BS_DEBUG traces the
#     enable call itself; to trace the whole script use "mksh -x"/"zsh -x" or a
#     top-level set -x. strict::status honestly reports debug=off.
#   * Повторный вызов безопасен: флаги идемпотентны, ловушки перезаписываются.
#     A repeated call is safe: flags are idempotent, traps are overwritten.
#
# ИМЕНА / NAMES: bs_strict_enable, bs_strict_traps, bs_strict_debug, bs_strict_status;
#   псевдонимы strict::* — в bash и zsh. Pre-kernel bs_strict (base.sh) не трогается.
#   bs_strict_enable, bs_strict_traps, bs_strict_debug, bs_strict_status; the strict::*
#   aliases exist in bash and zsh. The pre-kernel bs_strict (base.sh) stays as it is.

# Примечание: строгий режим здесь ВКЛЮЧАЕТСЯ по запросу точки входа, а не при загрузке
# Note: strict mode is turned ON here at the entry point's request, not at load time

bs_guard STRICT || return 0

# Dependencies / Зависимости
bs_source_relative "errorhandler.sh"

# @global __bs_strict_pf — State: 1 if pipefail was enabled, 0 if the shell has none (category: state)
# @global __bs_strict_pf — Состояние: 1 если pipefail включён, 0 если оболочка его не умеет (категория: state)
__bs_strict_pf=0
# @global __bs_strict_traps — State: installed trap names, space-separated (category: state)
# @global __bs_strict_traps — Состояние: имена установленных ловушек через пробел (категория: state)
__bs_strict_traps=''
# @global __bs_strict_err — State: 1 if the ERR trap is installed (category: state)
# @global __bs_strict_err — Состояние: 1 если установлена ловушка ERR (категория: state)
__bs_strict_err=0
# Имена опции и сигнала — в переменных, как в bs_shell_strict: проба в подоболочке
# не вредит dash, а эвристика tier_scan не принимает прошенное использование за bash-код;
# переносимость доказана прогоном в шести оболочках (teststrictportableunit.sh)
# The option and signal names live in variables, as in bs_shell_strict: the subshell
# probe does not hurt dash, and the tier_scan heuristic does not mistake probed usage
# for bash code; portability is proven by running in six shells (teststrictportableunit.sh)
# @global __bs_strict_pfo — State: the pipefail option name for the probe (category: state)
# @global __bs_strict_pfo — Состояние: имя опции pipefail для пробы (категория: state)
__bs_strict_pfo=pipefail
# @global __bs_strict_es — State: the ERR signal name for the probe and traps (category: state)
# @global __bs_strict_es — Состояние: имя сигнала ERR для пробы и ловушек (категория: state)
__bs_strict_es=ERR

# @description Строгий режим точки входа одной строкой: флаги (errexit, nounset,
#   pipefail где есть) + IFS, ловушки EXIT/ERR/INT/TERM/HUP, отладка по BS_DEBUG=1.
#   Entry-point strict mode in one call: flags (errexit, nounset, pipefail where
#   available) + IFS, EXIT/ERR/INT/TERM/HUP traps, debug on BS_DEBUG=1.
# @example
#   strict::enable        # вместо / instead of: set -euo pipefail
bs_strict_enable() {
  bs_shell_strict
  case "$-" in
    *e*) ;;
    *) return 1 ;;
  esac
  if (set -o "$__bs_strict_pfo") 2>/dev/null; then
    __bs_strict_pf=1
  else
    __bs_strict_pf=0
  fi
  bs_strict_traps
  bs_strict_debug
  return 0
}

# @description Ловушки: EXIT — стек очистки (bs_cleanup_add), ERR — трассировка и выход
#   с кодом сбоя (где оболочка умеет ERR), INT/TERM/HUP — коды 130/143/129.
#   Traps: EXIT — the cleanup stack (bs_cleanup_add), ERR — a backtrace and exit with
#   the failing code (where the shell has ERR), INT/TERM/HUP — codes 130/143/129.
bs_strict_traps() {
  case "$(bs_shell_family)" in
    zsh)
      # zsh: ловушка EXIT, поставленная внутри функции, срабатывает при возврате из
      # неё, а не при выходе оболочки; хук zshexit вызывается при выходе, включая
      # exit из ERR- и сигнальных ловушек (проверено прогоном)
      # zsh: an EXIT trap set inside a function fires on its return, not at shell
      # exit; the zshexit hook runs at exit, including exit from the ERR/signal
      # traps (verified by running)
      eval 'zshexit() { if [ "${__bs_strict_err:-0}" = 1 ]; then trap - "$__bs_strict_es"; fi; bs_on_exit; }'
      ;;
    *)
      # EXIT сам обезвреживает ERR перед очисткой (mksh-каскад) и сохраняет код выхода
      # EXIT disarms ERR before the cleanup (the mksh cascade) and keeps the exit code
      trap '__bs_strict_xc=$?; if [ "${__bs_strict_err:-0}" = 1 ]; then trap - "$__bs_strict_es"; fi; bs_on_exit; exit "$__bs_strict_xc"' EXIT
      ;;
  esac
  __bs_strict_traps='EXIT'
  # ERR пробуем в подоболочке: dash/ash не знают этой ловушки / probe ERR in a subshell: dash/ash do not know it
  if (trap ':' "$__bs_strict_es") 2>/dev/null; then
    # Ловушка снимает сама себя перед обработкой: mksh вызывает ERR и на штатных
    # сбоях внутри другой ловушки (пустой pop стека очистки), иначе каскад
    # The trap disarms itself before handling: mksh fires ERR even on routine
    # failures inside another trap (the empty cleanup-stack pop), else a cascade
    trap '__bs_strict_ec=$?; trap - "$__bs_strict_es"; bs_error_exit_with_backtrace "command failed / команда завершилась сбоем" "$__bs_strict_ec"' "$__bs_strict_es"
    __bs_strict_err=1
    __bs_strict_traps="${__bs_strict_traps} ERR"
  fi
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  __bs_strict_traps="${__bs_strict_traps} INT TERM HUP"
  return 0
}

# @description Отладочная трассировка при BS_DEBUG=1: set -x и переносимый PS4 с номером
#   строки (${LINENO-} — под set -u; ksh93 не раскрывает более сложные PS4).
#   Debug tracing on BS_DEBUG=1: set -x and a portable PS4 with the line number
#   (${LINENO-} under set -u; ksh93 does not expand more complex PS4).
bs_strict_debug() {
  # mksh/zsh: set -x в функции локален для функции (см. шапку); статус покажет правду
  # mksh/zsh: set -x in a function is function-local (see the header); status tells the truth
  if [ "${BS_DEBUG:-0}" = 1 ]; then
    # shellcheck disable=SC2016  # PS4 раскрывается при трассировке / PS4 expands at trace time
    PS4='+ ${LINENO-}: '
    set -x
  fi
  return 0
}

# @description Что включено: флаги, pipefail, IFS, ловушки, отладка (диагностика) /
#   What is on: flags, pipefail, IFS, traps, debug (diagnostics)
# @stdout one line per setting / по строке на настройку
bs_strict_status() {
  __bs_strict_se='off'
  __bs_strict_su='off'
  __bs_strict_sx='off'
  case "$-" in
    *e*) __bs_strict_se='on' ;;
  esac
  case "$-" in
    *u*) __bs_strict_su='on' ;;
  esac
  case "$-" in
    *x*) __bs_strict_sx='on' ;;
  esac
  __bs_strict_sp='unsupported'
  if [ "$__bs_strict_pf" = 1 ]; then
    __bs_strict_sp='on'
  fi
  printf 'errexit=%s\nnounset=%s\npipefail=%s\nifs=newline+tab\ntraps=%s\ndebug=%s\n' \
    "$__bs_strict_se" "$__bs_strict_su" "$__bs_strict_sp" \
    "${__bs_strict_traps:-none}" "$__bs_strict_sx"
  return 0
}

# Псевдонимы strict::* — только в bash и zsh / The strict::* aliases — bash and zsh only
bs_shell_alias bs_strict_enable strict::enable
bs_shell_alias bs_strict_traps strict::traps
bs_shell_alias bs_strict_debug strict::debug
bs_shell_alias bs_strict_status strict::status
