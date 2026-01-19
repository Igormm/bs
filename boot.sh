#!/usr/bin/env bash
# ------------------------------------------------------------------
#  BS Framework – STAGE-1 BOOT-LOADER
#  Назначение / Purpose:
#    - проверить среду (bash≥4);
#    - максимально быстро найти BS_ROOT;
#    - передать управление скрипту bs (stage-2).
#  Exit-codes:
#    0 – успешный запуск bs;
#    1 – bash слишком старый;
#    2 – не найден BS_ROOT или отсутствует bs.
# ------------------------------------------------------------------
set -euo pipefail

# 2. Определяем каталог, где лежит boot.sh --
BOOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

# 3. BS_ROOT: приоритет поиска --------------
#  1) Уже экспортирован внешним скриптом
#  2) Рядом лежит файл «bs» и bootstrap/init.sh
#  3) Системные/пользовательские префиксы
if [[ -z "${BS_ROOT:-}" ]]; then
  if [[ -f "${BOOT_DIR}/bs" && -f "${BOOT_DIR}/bootstrap/init.sh" ]]; then
    BS_ROOT=$BOOT_DIR
  else
    for prefix in "${HOME}/.local/lib/bs" "/usr/local/lib/bs"; do
      if [[ -f "${prefix}/bs" && -f "${prefix}/bootstrap/init.sh" ]]; then
        BS_ROOT=$prefix
        break
      fi
    done
  fi
fi

# 4. Валидация -----------------------------
if [[ -z "${BS_ROOT:-}" ]]; then
  printf 'Error: BS framework not found (searched: repo, ~/.local/lib/bs, /usr/local/lib/bs)\n' >&2
  exit 2
fi

if [[ ! -x "${BS_ROOT}/bs" ]]; then
  printf 'Error: bs script not found or not executable in BS_ROOT=%s\n' "$BS_ROOT" >&2
  exit 2
fi

# 5. Передаём управление «настоящему» фреймворку
#    Все аргументы, STDIN/STDERR/STDOUT остаются без изменений.
exec "${BS_ROOT}/bs" "$@"