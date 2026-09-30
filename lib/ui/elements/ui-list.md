# UI components catalog / Каталог UI-компонентов

Что существует в сети (TUI-фреймворки и их виджеты) и как это соотносится
с элементами BS в `lib/ui/elements/`.
What exists in the network (TUI frameworks and their widgets) and how it maps
to the BS elements in `lib/ui/elements/`.

## 1. Элементы BS (этот каталог) / BS elements (this catalog)

| Элемент / Element | Файл / File | Что делает / What it does |
|---|---|---|
| box | `box.sh` | центрированная рамка с заголовком / centered framed box |
| table | `table.sh` | таблица с выровненными колонками / aligned table |
| list | `list.sh` | список с выбором и прокруткой / selectable list |
| input | `input.sh` | поле ввода с курсором / input field |
| menu | `menu.sh` | вертикальное меню / vertical menu |
| confirm | `confirm.sh` | диалог да/нет / yes-no dialog |
| progress | `progress.sh` | прогресс-бар / progress bar |
| spinner | `spinner.sh` | спиннер (брайль) / braille spinner |
| statusbar | `statusbar.sh` | строка статуса снизу / bottom status bar |
| titlebar | `titlebar.sh` | заголовок сверху / top title bar |
| separator | `separator.sh` | горизонтальный разделитель / horizontal rule |
| message | `message.sh` | баннер info/success/warning/error |

Каждый элемент: `load "lib/ui/elements/<name>"` → `ui::elements::<name>::draw …`,
рисует в буфер TUI (`tui::buf::clear` + `tui::render` вокруг); при прямом
запуске `bs run lib/ui/elements/<name>.sh` — показывает себя.

## 2. Фреймворки в сети / Frameworks in the network

Источник: awesome-tuis (Libraries). Классификация по языку.

### Rust
| Фреймворк | Виджеты |
|---|---|
| **Ratatui** (tui-rs revival) | блоки, параграфы, таблицы, списки, gauge, sparkline, canvas, chart, scrollbar, tabs |
| iocraft | declarative, React-like |

### Go
| Фреймворк | Виджеты |
|---|---|
| **Bubble Tea** (charmbracelet) | Elm-модель; компоненты — в lipgloss (стили) и hub |
| **tview** | Form, Table, List, TreeView, InputField, Modal, Pages, Flex, Grid |
| gocui | менеджер панелей, ввод |
| pterm | прогресс-бары, таблицы, деревья, чарты (вывод, не интерактив) |

### Python
| Фреймворк | Виджеты |
|---|---|
| **Textual** | DataTable, ListView, Input, Tabs, Header/Footer, LoadingIndicator, Masonry, Markdown, Static |
| **Rich** | таблицы, деревья, прогресс, спиннеры, панели (вывод) |
| urwid | ListBox, Edit, Button, CheckBox, ProgressBar, Frame, Pile |
| prompt_toolkit | автодополнение, layout, меню, form |
| py_cui | меню, текстовые поля, формы, попапы, файл-эксплорер |

### C / C++
| Фреймворк | Виджеты |
|---|---|
| **ncurses** | классика: окна, панели, меню, формы |
| **notcurses** | графические примитивы, plane'ы, сканлайны |
| **FTXUI** | Component: Menu, Slider, Input, Checkbox, Radiobox, Toggle, Table, Canvas, Graph |
| FINAL CUT | виджеты в стиле Qt |
| Terminal.Gui (.NET) | полноценный widget-тулкит |

### Node / JS / TS
| Фреймворк | Виджеты |
|---|---|
| **blessed** | box, list, form, textarea, table, progressbar, question, message |
| **ink** | React-компоненты: Text, Box, useInput, Spacer, Static |
| OpenTUI (sst) | TypeScript TUI |

### Прочее
| Фреймворк | Заметки |
|---|---|
| termbox2 | низкоуровневый рендер (как наш `lib/tui`) |
| gum (charmbracelet) | «glamorous shell»: input/choose/confirm/prompt для **bash-скриптов** |
| moulti | CLI-driven TUI блоки для shell |

## 3. Маппинг: что у BS есть, чего нет / Mapping: what BS has vs the network

| Виджет из сети | В BS |
|---|---|
| box / panel / frame | ✅ `box` |
| table / DataTable | ✅ `table` (без сортировки/скролла колонок) |
| list / ListBox | ✅ `list` |
| input / InputField | ✅ `input` (однострочный) |
| menu / Radiobox | ✅ `menu` |
| confirm / Modal | ✅ `confirm` |
| progress / gauge | ✅ `progress` |
| spinner / LoadingIndicator | ✅ `spinner` |
| statusbar / Header-Footer | ✅ `statusbar`, `titlebar` |
| separator | ✅ `separator` |
| message / toast | ✅ `message` |
| textarea / многострочный ввод | ❌ — кандидат |
| checkbox (мультивыбор) | ❌ — кандидат (в визардах реализован вручную) |
| tree / TreeView | ❌ — кандидат |
| tabs / панели-вкладки | ❌ — кандидат |
| grid / flex layout | ⚠️ частично (tui::center, координаты вручную) |
| canvas / chart / gauge-спарклайн | ❌ — дальний план |
| mouse-поддержка | ✅ базовая в lib/tui (TUI_MOUSE_*) |

## 4. Принципы отбора для BS

1. **Один элемент — один модуль** — просто подключать и ревьюить.
2. **Рисование в буфер, а не в stdout** — композиция без мерцания.
3. **Центрирование и резина по умолчанию** — как в этом каталоге.
4. **Демо при прямом запуске** — элемент можно посмотреть без интеграции.
5. Брать только то, что нужно реальным скриптам BS (визарды, тулзы, дашборды) —
   не гнаться за полной паритетностью с Ratatui/Textual.