---
name: bs-cli-noop-output
description: Design "nothing to do / no changes" output for BS CLI commands (bs update, uninstall, doctor, sync, any new command) as a framed bilingual notice «... НЕТ / NO ...» with per-item reasons and next-step hints — never a raw WARN/ERROR + "see messages above"; detect no-op states by content comparison before redoing work; pad frames by characters, not bytes (printf %-*s measures bytes and breaks Cyrillic borders); exit 0 for no-ops, exit 1 only for real failures
type: prompt
whenToUse: When implementing or fixing the output of a BS CLI command whose run can legitimately end in "nothing was done" (all targets skipped, nothing to update, nothing to delete, no changes to apply) — or when a user reports that a command's empty-result output is confusing (raw ERROR line, "see messages above", frame borders misaligned with Cyrillic)
---

# Стиль вывода «ничего не сделано» / BS CLI "nothing to do" output style

Эталон / Reference: `bs update` в CLI `bs` — коммиты `5741a01` (первая рамка) и `412789c`
(детект «уже актуально» + причины). Смотрите / see `update_box()` в `bs`.

## Правило / The rule

Запуск команды, которая ничего не изменила, НЕ заканчивается сырой строкой ошибки.
Он заканчивается рамкой: заголовок «…НЕТ / NO …» (RU первым), по строке причины на
каждый пропущенный пункт, затем точные команды, которые пользователь может выполнить.

```
╭──────────────────────────────────────────────────────────╮
│               ОБНОВЛЕНИЙ НЕТ / NO UPDATES                │
├──────────────────────────────────────────────────────────┤
│• /usr/local/lib/bs — уже актуально / already up to date  │
╰──────────────────────────────────────────────────────────╯
```

## Чек-лист / Checklist

1. **Собирайте причины, а не WARN на каждый пункт.** `log::warn` в цикле даёт
   стену строк; собирайте причины в массивы (`same_paths`, `miss_paths`,
   `ro_paths`, `uptodate_paths`) и печатайте один раз в финальной рамке. WARN
   оставляйте только когда он несёт немедленную подсказку («нет прав — попробуйте
   sudo bs update --system»).
2. **Подсказки, а не только факты.** Рамка заканчивается точными командами:
   `cd <repo> && ./bs update`, `bs update --from <repo-path>` и т.п.
3. **Exit-коды: no-op — не ошибка.** `exit 0`, когда все пропуски безобидны
   (источник==цель, уже актуально); `exit 1` только при реальном сбое (цель не
   найдена / нет прав / копирование упало).
4. **Детектируйте «нечего делать» — не повторяйте работу вслепую.** Перед
   копированием/синхронизацией сравните содержимое: `cmp -s` для файлов,
   `diff -rq` для каталогов. Идентичная цель → пропуск, в рамке «уже актуально /
   already up to date».
5. **Паддинг рамки по символам, а не байтам.** `printf '%-*s' W text` считает
   ширину в БАЙТАХ: с кириллицей правый бордюр плывёт (заголовок короче, строки
   длиннее). Паддите вручную через `${#text}` — символы == клетки для кириллицы и
   глифов рамки:
   ```bash
   (( n = inner - ${#line} )); (( n > 0 )) && printf -v line '%s%*s' "${line}" "${n}" ''
   ```
6. **Рамку не рисуйте через log::\***. `log::info`/`log::warn` добавляют префикс
   `[timestamp] LEVEL ` — при включённых таймстампах выравнивание ломается
   (проверено на `log::header`). Рамку печатайте обычным `printf` в stdout; цвет
   включайте теми же условиями, что `log::__is_color_enabled` (NO_COLOR /
   BS_LOG_COLOR / `-t`).
7. **Двуязычность RU первым**: «ОБНОВЛЕНИЙ НЕТ / NO UPDATES», строки причин
   `RU / EN`.
8. **Длинные строки переносите по символам** (не `fold` — он режет байты):
   режьте `${text:0:inner}`, остаток — следующей строкой.

## Заготовка / Ready-to-copy skeleton

`update_box()` из `bs` (заголовок центрируется, причины переносятся по 58 символам,
паддинг посимвольный, цвет — как у логгера):

```bash
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
```

Использование / Usage:

```bash
local -a reasons=()
for p in "${same_paths[@]}"; do
  reasons+=("• ${p} — вы запустили bs из установленной копии: источник совпадает с целью / running from an installed copy: source equals target")
done
update_box "ОБНОВЛЕНИЙ НЕТ / NO UPDATES" "${reasons[@]}"
```

## Проверка / Verify

- Три сценария на временной цели: идентично → рамка, `exit 0`; устарело → синк;
  снова идентично → рамка. Пример: `./bs update --lib /tmp/target --from <repo>`.
- same-as-source / not found / not writable: коды 0 / 1 / 1.
- `bash tests/validatesyntax.sh && bash tests/validateshellcheck.sh && bash tests/runalltests.sh`
- Вывод через `cat -A`: каждая строка обязана заканчиваться `│` на одной колонке —
  сдвинутый бордюр = байтовый паддинг.