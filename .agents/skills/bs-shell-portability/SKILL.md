---
name: bs-shell-portability
description: Keep BS usable from most shells (bash, zsh, ash/dash, ksh, fish, nushell) — the host/user shell model, the @shell tier annotation with a description, the POSIX layer (bootstrap/shell.sh, bootstrap/trampoline.sh), the shell registry (rc file, PATH line, reload command), the tier scanner and the shell probe
type: prompt
whenToUse: When writing or changing anything that touches the shell — an installer step, a PATH/rc edit, a hint such as "source ~/.bashrc", shell detection, an entry point, bootstrap/ code, completion — or a new lib/ module and you must decide (and declare) which shells can run it; also before claiming "this works in zsh/dash/nu"
---

# Переносимость между оболочками / Shell portability

Ядро BS делится на **два яруса**: `@shell posix` (14 файлов `core/` и слой `bootstrap/` —
работают в bash, zsh, dash, busybox ash, ksh93, mksh) и `@shell bash4` (остальное,
требует bash 4.2+). Яруса bash4 не надо «лечить»: на ассоциативных массивах,
namerefs и `[[ =~ ]]` стоят сотни функций; для ядра эти конструкции заменяются слоем `core/data.sh` и переводятся по плану (см. `bs-shell-abstraction`), а `lib/` остаётся bash.
BS доступен из большинства оболочек разделением ролей, а не переписыванием всего.
Полное описание и таблица оболочек —
`documentation/{en,ru}/08-development/shell-portability.md`.

## 1. Модель: три разных «оболочки» / Three different shells

| Роль | Что это | Кто решает |
| --- | --- | --- |
| **Хозяин / host** | интерпретатор, ИСПОЛНЯЮЩИЙ код BS | зависит от яруса файла: `posix` — любая оболочка из таблицы; `bash4` — bash 4.2+ (`bs_shell_host_ok`, `bs_shell_host_find`) |
| **Оболочка пользователя / user shell** | та, где человек набирает команды; чьи rc-файлы правим | `bs_shell_user` (BS_USER_SHELL → родительский процесс → `$SHELL`) |
| **Оболочка скрипта / script shell** | интерпретатор шебанга `#!/usr/bin/env bs` | `bs` (bash) |

Четыре способа доступа: **exec** — команда `bs` из ЛЮБОЙ оболочки (универсально,
включая nushell и fish); **source** — `source bootstrap/init.sh`, только bash 4.2+;
**trampoline** — `sh install.sh`, `dash ./bs`, `zsh ./bs` перезапускаются в bash;
**call** — `bs call [--load МОДУЛЬ] ФУНКЦИЯ` вызывает функцию ядра из fish, nushell и
любой другой оболочки (она исполняется в bash, вывод и код возвращаются). Файлы
`@shell posix` дополнительно подключаются напрямую (`. файл`) из bash, zsh, dash, ash,
ksh, mksh.

`$SHELL` — логин-оболочка, а не интерпретатор и не обязательно оболочка, где
набрана команда. Никогда не выводите по `$SHELL`, что исполняет ваш код.

## 2. Tier-ы и аннотация / Tiers and the annotation

Две независимые оси в заголовке файла:

```bash
# @tier core — pure Bash 4+, no GNU tools: works everywhere      # userland (как раньше)
# @shell bash4 — assoc arrays + namerefs; zsh 5.9 has no namerefs # оболочка (новое)
```

* `@shell posix` — файл валиден как POSIX sh: его подключат dash, ash/busybox,
  bash, zsh, ksh, mksh. Сейчас: `bootstrap/shell.sh`, `trampoline.sh`, `shebang.sh`;
  `core/prereq`, `guard`, `const`, `version`, `quiet`, `fmt`, `logger`, `calc`. **bash в этом ярусе не
  участвует** — это проверяет `.agents/skills/bs-shell-abstraction/scripts/check_posix_tier.sh`
  (разбор в не-bash оболочках, запрет bash-конструкций, запуск в dash без bash в PATH).
  Стиль кода яруса — `documentation/*/code-style-guide.md`, раздел 12.
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
причины (так пока остаётся `args`; ядро переводится по плану на слое `core/data.sh`). Для пользователя другой оболочки такой
модуль доступен через `bs` (hosted) и `bs call`. В POSIX переводят то, что (а) должно
работать ДО bash — пролог, трамплин, реестр, шебанг; или (б) нужно скриптам на других
оболочках и не держится на bash-конструкциях — `quiet`, `version`, `const`, `guard`,
`prereq`; очередь: `args` (все остальные файлы `core/` готовы). Перевод — отдельный
коммит: код, тест в шести оболочках, `check_posix_tier.sh`, строка в документации.

## 5. Порядок работы / Workflow

```bash
bash .agents/skills/bs-shell-portability/scripts/probe_shells.sh        # что умеют установленные оболочки (busybox как `busybox ash`)
bash .agents/skills/bs-shell-portability/scripts/tier_scan.sh --check   # аннотации vs конструкции; 1 при нарушении
bash .agents/skills/bs-shell-abstraction/scripts/check_posix_tier.sh    # bash в ярусе posix не участвует; 1 при нарушении
dash -n FILE && shellcheck -s sh FILE                                   # для posix-файлов; также busybox ash -n, ksh -n, mksh -n, zsh -n
bash tests/unit/testshellunit.sh                                        # реестр, определение, tier, init-shell
bash tests/unit/testtrampolineunit.sh                                   # dash/zsh/bash-as-sh, отказ без bash
bash tests/unit/testposixtierunit.sh                                    # ярус posix без bash (то же, что check_posix_tier.sh)
bash tests/unit/testquietportableunit.sh                                # образец теста posix-модуля в 6 оболочках
bash tests/unit/testcallbridgeunit.sh                                   # мост bs call из 7 оболочек
bash tests/integration/testinstallshells.sh                             # PATH и удаление по оболочкам
bash tests/validatesyntax.sh && bash tests/validateshellcheck.sh && bash tests/runalltests.sh
```

`tier_scan.sh` — эвристика: конструкция внутри строки даёт ложное срабатывание;
для `posix`-файлов решает разбор в dash и текст без строковых литералов.

## 6. Что проверить в конце / Final checklist

- [ ] заголовок файла: `@shell` + описание причины (двуязычно) для сильной зависимости;
- [ ] нет литералов `.bashrc`/`.zshrc`/`source ~/` вне реестра и тестов;
- [ ] POSIX-файл разбирается в dash, busybox ash, ksh, mksh, bash, zsh; `shellcheck -s sh` чист;
- [ ] `check_posix_tier.sh` — OK: bash в ярусе `posix` не участвует; непроверенные оболочки названы;
- [ ] стиль POSIX-яруса соблюдён (`code-style-guide.md`, раздел 12): настоящие имена `модуль_функция` + псевдонимы `::`, без `local`, префикс `__bs_<функция>_` для временных;
- [ ] пролог точек входа не разошёлся (тест трамплина);
- [ ] тест для оболочки, которой нет на машине, — на генерацию текста, и честная
      пометка «не запускалось на реальной оболочке» в документации;
- [ ] `documentation/{en,ru}` и `CHANGELOG.md` обновлены.

Справка по результатам проб: `references/shell-matrix.md`.

## Strict mode / Строгий режим

`bs --strict-shell[=SHELL]` (or `BS_SHELL_STRICT=1`) makes the `@shell` tier binding at `load`: a `lib/` module runs only if its tier fits the origin shell (`BS_ORIGIN_SHELL`) — or, with a name (`--strict-shell=dash`), the NAMED shell, wherever bs is started ("will this work in dash"). `install.sh --strict-shell=SHELL` is the shell the install is for (like `--shell`, refused for tier unsupported). Rules: `posix` — any, `bash4` — bash 4.2+, other word (`zsh`, `nu`, …) — the shell of that name, a list `a,b` — any. `core/` is always allowed. Write a new module's tier honestly: it is what strict mode enforces.
`bs --strict-shell` (или `BS_SHELL_STRICT=1`) делает tier `@shell` обязательным при `load`; правила выше. Tier нового модуля пишите честно — именно его проверяет строгий режим.
