---
name: bs-shell-portability
description: Keep BS usable from most shells (bash, zsh, ash/dash, ksh, fish, nushell) — the host/user shell model, the @shell tier annotation with a description, the POSIX layer (bootstrap/shell.sh, bootstrap/trampoline.sh), the shell registry (rc file, PATH line, reload command), the tier scanner and the shell probe
type: prompt
whenToUse: When writing or changing anything that touches the shell — an installer step, a PATH/rc edit, a hint such as "source ~/.bashrc", shell detection, an entry point, bootstrap/ code, completion — or a new lib/ module and you must decide (and declare) which shells can run it; also before claiming "this works in zsh/dash/nu"
---

# Переносимость между оболочками / Shell portability

Ядро BS — код для **bash 4.2+**. Это не недостаток, который надо «вылечить»: на
ассоциативных массивах, namerefs и `[[ =~ ]]` стоят сотни функций. Поэтому BS
сделан доступным из большинства оболочек не переписыванием ядра, а разделением
ролей. Полное описание — `documentation/{en,ru}/08-development/shell-portability.md`.

## 1. Модель: три разных «оболочки» / Three different shells

| Роль | Что это | Кто решает |
| --- | --- | --- |
| **Хозяин / host** | интерпретатор, ИСПОЛНЯЮЩИЙ код BS | всегда bash 4.2+ (`bs_shell_host_ok`, `bs_shell_host_find`) |
| **Оболочка пользователя / user shell** | та, где человек набирает команды; чьи rc-файлы правим | `bs_shell_user` (BS_USER_SHELL → родительский процесс → `$SHELL`) |
| **Оболочка скрипта / script shell** | интерпретатор шебанга `#!/usr/bin/env bs` | `bs` (bash) |

Три способа доступа: **exec** — команда `bs` из ЛЮБОЙ оболочки (универсально,
включая nushell и fish); **source** — `source bootstrap/init.sh`, только bash 4.2+;
**trampoline** — `sh install.sh`, `dash ./bs`, `zsh ./bs` перезапускаются в bash.

`$SHELL` — логин-оболочка, а не интерпретатор и не обязательно оболочка, где
набрана команда. Никогда не выводите по `$SHELL`, что исполняет ваш код.

## 2. Tier-ы и аннотация / Tiers and the annotation

Две независимые оси в заголовке файла:

```bash
# @tier core — pure Bash 4+, no GNU tools: works everywhere      # userland (как раньше)
# @shell bash4 — assoc arrays + namerefs; zsh 5.9 has no namerefs # оболочка (новое)
```

* `@shell posix` — файл валиден как POSIX sh: его подключат dash, ash/busybox,
  bash, zsh, ksh. Только `bootstrap/shell.sh`, `bootstrap/trampoline.sh` и
  подобное.
* `@shell bash4` — нужен bash 4.2+ как хозяин. **Значение по умолчанию** для
  файла без аннотации (всё ядро и `lib/`).
* После тире — **описание причины** (обязательно, на двух языках, если зависимость
  сильная или нерешаемая): какая конструкция держит файл и почему её нельзя
  заменить. Не пишите `posix`, если файл не разбирается в `dash -n`.

Tier пользователя (что получит человек): **native** (его оболочка — bash 4.2+),
**hosted** (другая оболочка: BS работает командой `bs`, её исполняет найденный
bash; PATH/rc/подсказки — под его оболочку), **unsupported** (bash 4.2+ на
машине нет). Описание — `bs_shell_tier_desc`; видно в `bs doctor`, `bs where`,
`bs init-shell`.

## 3. Правила автора / Author rules

1. **Не вписывайте имена оболочек и rc-файлов.** Ни `~/.bashrc`, ни `~/.zshrc`,
   ни «source ~/.zshrc» в коде и сообщениях — только реестр:
   `bs_shell_rc_file`, `bs_shell_path_line`, `bs_shell_reload_hint`,
   `bs_shell_rc_scan`, `bs_shell_all_rc_files`, `bs_shell_fresh_flags`.
2. **POSIX-файл** (`@shell posix`): имена функций — валидные идентификаторы
   (`bs_shell_x`, а НЕ `bs::shell::x`: dash отвергает `::` на этапе разбора);
   без `[[ ]]`, массивов, `local -r`, `source`, `${a[0]}`, `$'..'`; `local` не
   используйте (в ksh нет) — временные переменные с префиксом `__bs_`. Имена с
   `::` для bash/zsh — только циклом `eval "bs::shell::${n}() { bs_shell_${n} \"\$@\"; }"`.
3. **Точка входа** (`bs`, `install.sh`, `boot.sh`) начинается с одного и того же
   POSIX-пролога (его проверяет `tests/unit/testtrampolineunit.sh`): до первой
   bash-конструкции. Путь точки входа запоминается в прологе (`__bs_s`): zsh меняет
   `$0` внутри подключаемого файла.
4. **Не создавайте чужие конфигурации с нуля.** Для nushell `env.nu` не создаётся
   (пустой файл помешал бы nu создать свою конфигурацию) — печатается точная
   строка. Для fish — отдельный файл `conf.d/bs.fish`, его же удаляет uninstall.
5. **Сообщение — для оболочки пользователя.** Подсказка «как применить в этом
   терминале» — `bs_shell_reload_hint "$(bs_shell_user)"`.
6. **Не утверждайте, что работает, не запустив.** Таблицы из интернета — про
   интерактивное удобство. Запустите `scripts/probe_shells.sh`; оболочка, которой
   нет на машине, помечается «не проверено», а не «поддерживается».
7. **Новая оболочка** = запись в `bs_shell_of_name`, `bs_shell_rc_file`,
   `bs_shell_rc_scan`, `bs_shell_path_line`, `bs_shell_reload_hint`,
   `bs_shell_known`, строки в `bs init-shell --list` и тесты.

## 4. Когда зависимость нельзя убрать / When it cannot be removed

Не «портируйте» ради галочки. Если модуль держится на ассоциативных массивах,
namerefs, `mapfile`, `${!x}`, `BASH_REMATCH` — это `@shell bash4` с описанием
причины. Для пользователя другой оболочки модуль доступен через `bs` (hosted).
Переписывать под POSIX стоит только то, что должно работать ДО bash:
пролог, трамплин, реестр, определение оболочки.

## 5. Порядок работы / Workflow

```bash
bash .agents/skills/bs-shell-portability/scripts/probe_shells.sh        # что умеют установленные оболочки
bash .agents/skills/bs-shell-portability/scripts/tier_scan.sh --check   # аннотации vs конструкции; 1 при нарушении
dash -n FILE && shellcheck -s sh FILE                                   # для posix-файлов
bash tests/unit/testshellunit.sh                                        # реестр, определение, tier, init-shell
bash tests/unit/testtrampolineunit.sh                                   # dash/zsh/bash-as-sh, отказ без bash
bash tests/integration/testinstallshells.sh                             # PATH и удаление по оболочкам
bash tests/validatesyntax.sh && bash tests/validateshellcheck.sh && bash tests/runalltests.sh
```

`tier_scan.sh` — эвристика: конструкция внутри строки даёт ложное срабатывание;
для `posix`-файлов решает разбор в dash и текст без строковых литералов.

## 6. Что проверить в конце / Final checklist

- [ ] заголовок файла: `@shell` + описание причины (двуязычно) для сильной зависимости;
- [ ] нет литералов `.bashrc`/`.zshrc`/`source ~/` вне реестра и тестов;
- [ ] POSIX-файл разбирается в dash, bash, zsh; `shellcheck -s sh` чист;
- [ ] пролог точек входа не разошёлся (тест трамплина);
- [ ] тест для оболочки, которой нет на машине, — на генерацию текста, и честная
      пометка «не запускалось на реальной оболочке» в документации;
- [ ] `documentation/{en,ru}` и `CHANGELOG.md` обновлены.

Справка по результатам проб: `references/shell-matrix.md`.
