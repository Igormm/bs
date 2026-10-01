#!/usr/bin/env bs
# shellcheck shell=bash
# examples/output_contract/noop_box.sh — output contract demo: no-op box
# examples/output_contract/noop_box.sh — демо контракта вывода: рамка «ничего не сделано»
#
# Рамка «ОБНОВЛЕНИЙ НЕТ / NO UPDATES» из CLI bs (update_box): причины по
# каждой пропущенной цели + подсказки, паддинг по символам (printf %-*s
# считает байты и ломает кириллицу). No-op — exit 0, реальный сбой — exit 1.
# The "NO UPDATES" box from the bs CLI (update_box): per-target reasons +
# hints, character-based padding (printf %-*s measures bytes and breaks
# Cyrillic). No-op — exit 0, real failure — exit 1.
#
# Run / Запуск:
#   bs run examples/output_contract/noop_box.sh

load "core/logger"

update_box() {
  local -r title="$1"
  shift
  local -r inner=58
  local -a body=()
  local text
  for text in "$@"; do
    while (( ${#text} > inner )); do
      body+=("${text:0:inner}")
      text="${text:inner}"
    done
    body+=("${text}")
  done

  local color_b='' color_reset=''
  if log::__is_color_enabled 1; then
    color_b=$'\033[34m'
    color_reset=$'\033[0m'
  fi
  local rule
  printf -v rule '%*s' "${inner}" ''
  rule="${rule// /─}"
  local title_row
  printf -v title_row '%*s' "$(( (inner - ${#title}) / 2 ))" ''
  title_row+="${title}"

  local n
  (( n = inner - ${#title_row} )) && (( n > 0 )) && printf -v title_row '%s%*s' "${title_row}" "${n}" ''
  printf '%s╭%s╮%s\n' "${color_b}" "${rule}" "${color_reset}"
  printf '%s│%s│%s\n' "${color_b}" "${title_row}" "${color_reset}"
  printf '%s├%s┤%s\n' "${color_b}" "${rule}" "${color_reset}"
  local line
  for line in "${body[@]}"; do
    (( n = inner - ${#line} )) && (( n > 0 )) && printf -v line '%s%*s' "${line}" "${n}" ''
    printf '%s│%s│%s\n' "${color_b}" "${line}" "${color_reset}"
  done
  printf '%s╰%s╯%s\n' "${color_b}" "${rule}" "${color_reset}"
}

main() {
    local -a reasons=()
    printf 'Сценарий 1 / Scenario 1: цель уже актуальна / target up to date\n'
    printf '(no-op → exit 0)\n\n'
    reasons=("• /usr/local/lib/bs — уже актуально / already up to date")
    update_box "ОБНОВЛЕНИЙ НЕТ / NO UPDATES" "${reasons[@]}"
    printf '\nexit 0\n\n'

    printf 'Сценарий 2 / Scenario 2: запуск из установленной копии / installed copy\n'
    printf '(no-op → exit 0, с подсказкой / with a hint)\n\n'
    reasons=(
        "• /usr/local/lib/bs — вы запустили bs из установленной копии: источник совпадает с целью / running from an installed copy: source equals target"
        ""
        "Запустите из каталога репозитория / Run from the repo directory:"
        "  cd <repo> && ./bs update"
        "или укажите источник / or pass the source:"
        "  bs update --from <repo-path>"
    )
    update_box "ОБНОВЛЕНИЙ НЕТ / NO UPDATES" "${reasons[@]}"
    printf '\nexit 0\n\n'

    printf 'Сценарий 3 / Scenario 3: цель не найдена / target not found\n'
    printf '(реальная ошибка → exit 1)\n\n'
    reasons=("• /nonexistent — каталог не найден / directory not found")
    update_box "ОБНОВЛЕНИЙ НЕТ / NO UPDATES" "${reasons[@]}"
    printf '\nexit 1\n'
}

main "$@"