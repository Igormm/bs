# 🐚 BS — a framework for shell scripts

🇷🇺 [Русская версия](README.md)

[![CI](https://github.com/Igormm/bs/actions/workflows/ci.yml/badge.svg)](https://github.com/Igormm/bs/actions/workflows/ci.yml)
![bash 4.2+](https://img.shields.io/badge/bash-4.2%2B-4EAA25?logo=gnubash&logoColor=white)
![kernel POSIX sh](https://img.shields.io/badge/kernel-POSIX%20sh-blue)
[![MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**BS** is a modular framework and standard library for shell scripts.
You write an ordinary script, pull in the modules you need with one `load`
line, and the framework handles argument parsing, help, logging, error
handling and even a text user interface.

![greet.sh: a greeting, the loud mode and the generated help](documentation/assets/greet.png)

## ✨ What's inside

- 📦 **Modules on demand**: `load "lib/io/streams"`; dependencies come
  along by themselves, double loading and cycles are ruled out.
- 🎛️ **Painless arguments**: describe commands and flags once, get
  validation, clear errors, `--help` and shell completion.
- 📝 **Logging and errors out of the box**: levels, colours, JSON format,
  a cleanup stack on exit.
- 🖥️ **TUI in pure bash**: windows, buttons, menus, modal dialogs, mouse.
- 🧰 **Standard library**: files, processes, network, hardware, HTTP, LLM,
  Kubernetes, UUID, CSV and more than 80 modules in total.
- 🐚 **Runs everywhere**: the kernel is POSIX sh, the library is Bash 4.2+,
  no external dependencies.

## 🚀 Quick start

```bash
git clone https://github.com/Igormm/bs.git && cd bs

./bs doctor                  # 🩺 is everything in place
./bs run examples/hello.sh   # 👋 your first script
./bs repl                    # 💬 interactive console
```

Want the `bs` command in your `PATH`? See [Installation](#-installation).

## 👋 Your first script

`examples/hello.sh`: the `load` line pulls in the output module, the rest is
plain bash.

```bash
#!/usr/bin/env bs
# shellcheck shell=bash

load "lib/io/streams"

io::streams::print "hello from BS $(bs::version::get)"
```

```bash
./bs run examples/hello.sh
```

## 🎛️ A script with arguments

`examples/greet.sh` says hello or goodbye. We describe which words and flags
the script understands; the framework does the validation and the help.

```bash
#!/usr/bin/env bs
# shellcheck shell=bash

load "core/args"
load "lib/io/streams"

main() {
    args::level 1 hello goodbye
    args::describe hello "Greet a name"
    args::describe goodbye "Say goodbye to a name"
    args::flag name value world
    args::flag loud
    args::flag_describe name "Who to greet"
    args::flag_describe loud "Uppercase the greeting"
    args::required 1
    args::require "$@"

    local -r command="$(args::param 1)"
    local -r name="$(args::flag_get name)"
    local msg
    case "${command}" in
        hello)   msg="Hello, ${name}!" ;;
        goodbye) msg="Goodbye, ${name}!" ;;
    esac
    args::flag_is_set loud && msg="${msg^^}"
    io::streams::print "${msg}"
}

main "$@"
```

What happens here:

| Line | Meaning |
|---|---|
| `args::level 1 hello goodbye` | the first word after the script name: `hello` or `goodbye` |
| `args::flag name value world` | a `--name` flag with a value, `world` by default |
| `args::flag loud` | an on/off flag `--loud` without a value |
| `args::require "$@"` | check the arguments; on error show the reason and the help |
| `args::param 1` | the first word given (counted from 1, like `$1`) |
| `args::flag_get name` | the value of `--name`, or the default `world` |
| `args::flag_is_set loud` | was `--loud` given |

```bash
./bs run examples/greet.sh hello --name Ann      # Hello, Ann!
./bs run examples/greet.sh goodbye --loud        # GOODBYE, WORLD!
./bs run examples/greet.sh --help                # help from the same description
```

🔎 More: [the args module](documentation/en/03-modules/args.md).

## 🖥️ Text user interface

`examples/todo.sh` is a to-do list on `lib/tui/app`: the framework handles
windows, keys and modal dialogs; tasks are kept in `~/.todo.tsv`.

![todo.sh: adding three tasks and ticking two of them off](documentation/assets/todo.gif)

```bash
./bs run examples/todo.sh
```

⌨️ `↑↓` select · `Enter` tick · `a` add · `e` edit · `d` delete · `q` quit

A window with a button fits in a few lines (`examples/app_demo.sh`):

```bash
load "lib/tui/app"

main() {
    tui::app::window main "Hello BS" 2 2 30 9
    tui::app::button main greet "Say hello" 3 4
    tui::app::on greet app::say_hello
    tui::app::statusbar "Tab / arrows — next button, Enter — press, q — quit"
    tui::app::run
}
```

## 🧪 More to try

| Example | What it shows |
|---|---|
| `./bs run examples/pulse.sh` | 💓 a host passport: distro, bash, CPU, memory |
| `./bs run examples/menu.sh` | 📋 a simple arrow-key menu |
| `./bs calc '2 3 4 * +'` | 🧮 a reverse Polish notation calculator |
| `./bs run examples/sysdiag.sh quick` | 🔍 a quick system check |
| `./bs list` | 📚 every module of the framework |

For administrators there are full-screen setup wizards:
[sshd](examples/sshd_wizard.sh) (`--dry-run` changes nothing),
[fail2ban](examples/fail2ban_wizard.sh), [OpenBao](documentation/en/03-modules/system-openbao.md)
and a [VPN client](documentation/en/03-modules/network-vpn.md) on sing-box and Xray.
All examples with descriptions: [examples/](examples/README.md).

## 🛠️ `bs` commands

| Command | What for |
|---|---|
| `bs run script.sh` | run a script; or put `#!/usr/bin/env bs` on its first line |
| `bs repl` | a console with the kernel loaded: `load`, history, `:doc`, `:list` |
| `bs calc` | an RPN calculator, one-line or interactive |
| `bs build script.sh` | 📦 build a script into one file that runs without BS installed |
| `bs doctor` | check the framework's integrity |
| `bs update` | update installed copies from the repository or from GitHub |
| `bs where` | find every trace of BS on the machine and suggest fixes |

## 📥 Installation

BS runs straight from the repository folder. For everyday use, put the `bs`
command in your `PATH`:

```bash
./install.sh --local     # into ~/.local, no sudo
sudo ./install.sh        # into /usr/local for all users
```

The installer copies the framework, so the repository folder can be removed
afterwards.

| Mode | Where | `bs` command |
|---|---|---|
| `--local` | `~/.local/lib/bs` | `~/.local/bin/bs` |
| system | `/usr/local/lib/bs` | `/usr/local/bin/bs` |
| custom | `$LIB_DIR/bs` | `$BIN_DIR/bs` |

A single file without installation:

```bash
./bs build examples/sysdiag.sh            # → examples/sysdiag.standalone.sh
./examples/sysdiag.standalone.sh quick    # runs wherever bash 4.2+ is
```

Updating, removal and details: [documentation/en/install.md](documentation/en/install.md).

## 📋 Requirements

- 🐧 Linux (macOS is partly supported)
- 🐚 Bash 4.2+ for the standard library; CI checks bash 4.4–5.x on ubuntu,
  debian and almalinux 8–9
- `bs` and `install.sh` can be started from any shell: they find bash
  themselves

## 🗂️ Project layout

```
bs              # CLI and script interpreter
bootstrap/      # module loader
core/           # POSIX sh kernel: arguments, logging, errors, utilities
lib/            # standard library: io, tui, system, network, data, ...
examples/       # ready-to-run examples
tests/          # test framework and suites
documentation/  # docs: ru/ and en/
```

## ✅ Tests

```bash
bash tests/runalltests.sh          # all tests
bash tests/validatesyntax.sh       # syntax
bash tests/validateshellcheck.sh   # ShellCheck
```

## 📚 Documentation

- 🏁 [Getting started](documentation/en/01-getting-started/README.md)
- ✍️ [Your first script: a step-by-step tutorial](documentation/en/05-tutorials/first-script.md)
- 🏗️ [Architecture](documentation/en/02-core-concepts/architecture.md)
- 🎛️ [Arguments with `core/args`](documentation/en/03-modules/args.md)
- 🤫 [Silence idioms `utils::quiet*`](documentation/en/03-modules/core-utils.md)
- 🌐 [HTTP, LLM, Kubernetes](documentation/en/03-modules/integration-http.md)
- 🎨 [Code style](documentation/en/code-style-guide.md)
- 🤖 [Rules for AI agents](AGENTS.md)
- 📖 [All documentation](documentation/en/README.md)

## 💡 Principles

- 🌍 **Runs everywhere.** Bash is on almost every machine: nothing to
  install, no external dependencies.
- 🤝 **Still bash.** BS adds conventions, not a new language: any bash code
  and any tool stays at hand.
- 🔍 **No magic.** Every line can be read and debugged with `bash -x`.
- ⚙️ **Built for real work.** cron, CI, Docker, a distro matrix, single-file
  builds.
- 🧭 **Honest boundaries.** Heavy data work goes to programs (jq, Go) through
  a JSON contract.

## 📄 License

MIT, see [LICENSE](LICENSE).
