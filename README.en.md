# 🐚 BS Framework

> 🇬🇧 English version · 🇷🇺 [Русская версия](README.md)

[![CI](https://github.com/Igormm/bs/actions/workflows/ci.yml/badge.svg)](https://github.com/Igormm/bs/actions/workflows/ci.yml)
![bash 4.2+](https://img.shields.io/badge/bash-4.2%2B-4EAA25?logo=gnubash&logoColor=white)
![kernel POSIX sh](https://img.shields.io/badge/kernel-POSIX%20sh-blue)
[![MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**BS is a modular framework and standard library for shell scripts.**
Write your script, `load` the modules you need, and the framework does
the rest.

<p align="center">
  <img src="documentation/assets/tui-demo.gif" alt="A BS TUI: rounded frames, tasks, an input modal and progress" width="760">
</p>

## ✨ Why BS

- 📦 **Module loader** with dependency resolution: `load "lib/io/streams"` pulls in everything it needs
- 📝 **Logging** and 🛡️ **error handling** out of the box
- ⚙️ **Script parameters in one declaration**: validation, `--help` and completion for free
- 🖥️ **Pure bash TUI**: windows, menus, modals, mouse
- 🧰 **100+ modules**: files, processes, network, hardware, services, HTTP, LLM, Kubernetes
- 📦 **`bs build`**: your script and the framework in one file that runs without installing anything
- 🐚 **POSIX sh kernel**, standard library in Bash 4.2+
- 🎯 **Zero external dependencies** and one code style

## 🚀 Quick start

```bash
git clone https://github.com/Igormm/bs.git && cd bs   # download the repo and enter it

./bs run examples/hello.sh     # run your first script
./bs repl                      # open the interactive console
./bs doctor                    # check that all framework files are in place
```

Like it? Put the `bs` command in your `PATH`:

```bash
./install.sh --local           # install into ~/.local, no root needed
```

## 👋 Examples

### Hello, world

```bash
#!/usr/bin/env bs
# ↑ shebang: the bs interpreter runs the script, not bare bash

load "lib/io/streams"          # load the output module (its dependencies come along)

io::streams::print "hello from BS $(bs::version::get)"   # print a line with the BS version
```

```console
$ bs run examples/hello.sh
hello from BS 0.20.0
```

### 📝 Logging without boilerplate

The logger and checks like `is::file` are available right away, no `load` needed:

```bash
#!/usr/bin/env bs
# ↑ shebang: the logger and is::* are already loaded, no load needed

log::info "Starting the backup"                      # a plain message with a timestamp
if is::file "/etc/hostname"; then                     # is there such a regular file?
    log::success "The file is there, ready to copy"   # yes: a green success message
else                                                  # otherwise
    log::warn "No such file, skipping"                # no: a yellow warning
fi                                                    # end of the condition
```

```console
[2026-11-11 08:06:35] INFO  Starting the backup
[2026-11-11 08:06:35] SUCCESS The file is there, ready to copy
```

### ⚙️ A script with parameters

Declare the parameters once; BS does the validation, error messages and
`--help`. Read values by meaning: `args::param 1` (the first command word)
and `args::flag_get name` (the value of `--name`).

```bash
#!/usr/bin/env bs
# ↑ shebang: run through the bs interpreter

load "core/args"                       # the command-line parsing module
load "lib/io/streams"                  # the output module

main() {                               # the script's main function
    args::level 1 hello goodbye        # the first command word: hello or goodbye
    args::flag name value world        # a --name flag with a value, default world
    args::flag loud                    # a --loud switch with no value
    args::required 1                   # the first word is required
    args::require "$@"                 # parse the arguments; on error show the help and exit

    local -r command="$(args::param 1)"      # the first word after the script name
    local -r name="$(args::flag_get name)"   # the --name value or the default world
    local msg                                # a variable for the final text
    case "${command}" in                     # pick the text by command
        hello)   msg="Hello, ${name}!" ;;    # a greeting
        goodbye) msg="Goodbye, ${name}!" ;;  # a farewell
    esac                                     # end of the choice
    args::flag_is_set loud && msg="${msg^^}" # with --loud, turn the text UPPERCASE
    io::streams::print "${msg}"              # print the result
}

main "$@"                              # call main with all the script's arguments
```

```console
$ bs run examples/greet.sh hello --name World
Hello, World!
$ bs run examples/greet.sh goodbye --loud
GOODBYE, WORLD!
```

The full version with `--help` descriptions: [examples/greet.sh](examples/greet.sh).

### 🎛️ A terminal menu

<img src="documentation/assets/tui-menu.png" alt="A TUI menu in a rounded frame" width="320" align="right">

`↑↓` to select, `Enter` to run, `q` to quit. The full example with the
key loop: [examples/menu.sh](examples/menu.sh).

```bash
load "lib/tui/tui"                                       # load the TUI library

main() {                                                 # the main function
    local -a items=("Run checks" "Show status" "Quit")   # the menu items
    local -i sel=0                                       # the selected item number

    tui::init                                # switch to full-screen mode
    tui::menu 2 2 items "${sel}" "Menu"      # a menu at row 2, column 2, in a rounded frame
    tui::render                              # draw the frame on screen
    tui::key_read                            # wait for a key: it lands in $TUI_KEY
    # ...                                    # next: handle the key and redraw
}
```

<br clear="right">

## 🖼️ What you can build with BS

All of this lives in [examples/](examples/) and runs with one command.

| | |
|---|---|
| ✅ **Todo list** `examples/todo.sh`<br>Windows, modals, a task file. | <img src="documentation/assets/todo.gif" alt="TUI todo: adding, ticking and deleting tasks" width="420"> |
| 🔐 **sshd setup wizard** `examples/sshd_wizard.sh --dry-run`<br>Profiles, a tip for every option, safe apply. | <img src="documentation/assets/tui-sshd.gif" alt="sshd wizard: sections, options and tips" width="420"> |
| 🌍 **Locale wizard** `examples/locale_wizard.sh`<br>Steps for language, encoding and keyboard. | <img src="documentation/assets/tui-locale.gif" alt="Locale wizard step by step" width="420"> |
| 🌐 **Network** `examples/netconn.sh`<br>Interfaces, addresses, live traffic. | <img src="documentation/assets/tui-netconn.png" alt="Network TUI" width="420"> |
| 🧩 **TUI demo** `examples/tui_demo.sh`<br>Sections, a task list, an input modal, progress. | <img src="documentation/assets/tui-demo.png" alt="TUI demo" width="420"> |

More examples:

- 🛡️ `fail2ban_wizard.sh`, `ntp_wizard.sh`, `locale_wizard.sh`: system setup wizards
- 🔑 `openbao_wizard.sh`: OpenBao installer, [details](documentation/en/03-modules/system-openbao.md)
- 🛰️ `vpn.sh`: a sing-box and Xray VPN client with a TUI, [details](documentation/en/03-modules/network-vpn.md)
- 💓 `pulse.sh`, `sysdiag.sh`: a quick look at the host
- 🌍 `http_example.sh`, `llm_example.sh`, `k8s_example.sh`: integrations

## 🧰 The `bs` tool

<p align="center">
  <img src="documentation/assets/bs-cli.gif" alt="bs version, bs version --full and bs help in a terminal" width="640">
</p>

| Command | What it does |
|---|---|
| `bs run script.sh` | run a script (or put `#!/usr/bin/env bs` at the top) |
| `bs repl` | console with the kernel loaded, `:list`, `:doc`, `:info` |
| `bs calc '2 3 4 * +'` | RPN calculator |
| `bs list` | list modules |
| `bs build script.sh` | one self-contained file that runs without BS installed |
| `bs doctor` | integrity check |
| `bs update` | update installed copies |
| `bs where` | find every BS install on the machine |
| `bs version [--full]` | the version; `--full` adds the path, install kind and commit |
| `bs help [command]` | the command list, or detailed help for one command |

<details>
<summary>📸 Screenshots of <code>bs version</code> and <code>bs help</code></summary>

![bs version and bs version --full](documentation/assets/bs-version.png)

![bs help: every command by group](documentation/assets/bs-help.png)

</details>

## 📦 Installation

```bash
./install.sh --local      # just for you: ~/.local/bin/bs, no sudo
sudo ./install.sh         # for every user: /usr/local/bin/bs
```

The installer copies the framework, so you can delete the clone afterwards.
Install kinds, updating and removal are in
[documentation/en/install.md](documentation/en/install.md).

**Requirements:** Linux and Bash 4.2+ (CI checks 4.4–5.x on ubuntu, debian
and almalinux 8–9). You can start `bs` from any shell: it finds bash itself.

## 🗂️ Layout

```
bs              CLI and interpreter
bootstrap/      module loader
core/           kernel: args, logger, errorhandler, utils, lang …
lib/            standard library: io, tui, system, network, integration …
examples/       examples
tests/          tests
documentation/  docs in Russian and English
```

## 🧪 Tests

```bash
bash tests/runalltests.sh          # run the whole test suite
bash tests/validateshellcheck.sh   # lint the code with ShellCheck
```

## 📚 Documentation

- 🏁 [Getting started](documentation/en/01-getting-started/README.md)
- ✍️ [Your first script, step by step](documentation/en/05-tutorials/first-script.md)
- 🏗️ [Architecture](documentation/en/02-core-concepts/architecture.md)
- 🧩 [Modules overview](documentation/en/03-modules/lib-modules-overview.md)
- 📖 [Core API reference](documentation/en/04-api-reference/core-api.md)
- 🎨 [Code style](documentation/en/code-style-guide.md)
- 🇷🇺 [Документация на русском](documentation/ru/README.md)

## 💡 Principles

- **Bash is everywhere:** nothing to install.
- **It's bash, not a new language:** the whole bash ecosystem stays open, `bash -x` works.
- **No magic:** every line reads as plain bash.
- **Ops first:** cron, CI, Docker, one file via `bs build`.
- **Honest boundaries:** heavy data work goes to jq or Go over JSON.

## 📄 License

MIT, see [LICENSE](LICENSE).
