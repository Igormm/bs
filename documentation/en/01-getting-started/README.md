[↑ Documentation index](../README.md)

# Getting Started

## What is BS

**BS** is a modular framework and standard library written in **Bash 4.2+**. It provides
a module loader, logging, error handling, declarative script arguments, an
I/O streams abstraction, and a set of system modules — all in one consistent
code style and with zero external dependencies.

## Requirements

- **bash 4.2+ is a hard requirement.** All of the `lib/` library (87 modules) and
  1 of the 19 `core/` files are written in bash, so BS does not run without it.
  Versions 4.2 and 4.3 are accepted by the code, but CI checks from **4.4**
  (nearly every platform ships 4.4 or newer).
- The exception is the 18 kernel files labelled `@shell posix`: they do not depend
  on bash and can be sourced from dash, ash, ksh, mksh, zsh and bash (see "How the
  kernel works"). That is a small set of helpers (constants, the version,
  `bs_utils_has`, `bs_log_info`, `calc`, …), not the whole of BS.
- You can start `bs` and `install.sh` **from any shell** (dash, ash, zsh, ksh,
  fish, nushell): the prologue finds bash and re-runs itself in it, so for `bs`
  bash must be on the system but need not be your shell.
- **`install.sh` does not need bash at all**: with no bash 4.2+ on the machine it
  runs in dash, ash, ksh, mksh or zsh and installs BS (see
  [install](../install.md#installing-without-bash)); only the installed `bs`
  command and `lib/` then need bash.
- Linux (primary platform; macOS is partially supported: the system bash there
  is 3.2, install bash 4.2+ from Homebrew)

Nothing else is required: BS relies on bash built-ins and standard system
tools only.

**Heading for shell independence.** The goal is a kernel (`bootstrap/`, `core/`,
`install/`, `boot.sh`, `bs`, `install.sh`) in one namespace `bs_*` that does not
depend on the shell (dash, ash, ksh, mksh, zsh, bash). Already done: 18 of the 19
`core/` files (including the array and map layer `core/data.sh`) and the shell
layer in `bootstrap/`; the rest moves by plan (see
[shell-portability](../08-development/shell-portability.md#heading-for-shell-independence)).
All of the `lib/` library is for now written for bash 4.2+ (zsh parses 85 of the
87 files, but `lib/` was not run in zsh).

## Installation

BS runs straight from the repository — installation is optional and only
puts the `bs` command into your `PATH`.

### Run from the repository

```bash
git clone <repo-url> bs
cd bs
./bs doctor
```

### Local install (`~/.local`, no sudo)

```bash
./install.sh --local
```

Copies the framework to `~/.local/lib/bs`, creates a wrapper at
`~/.local/bin/bs`, and adds `~/.local/bin` to `PATH` in `~/.bashrc` /
`~/.zshrc` (idempotently). PATH helpers:

```bash
./install.sh --local --path          # print the export snippet
./install.sh --local --update-path   # add to ~/.bashrc / ~/.zshrc
```

### System install (`/usr/local`, requires root)

```bash
sudo ./install.sh
```

Files go to `/usr/local/lib/bs`, the wrapper to `/usr/local/bin/bs`.

Install locations can be overridden with the `PREFIX`, `BIN_DIR`, and
`LIB_DIR` environment variables.

### Uninstall

```bash
sudo ./install.sh uninstall      # system
./install.sh --local uninstall   # local
```

> **Note on the source directory.**  
> The installer **copies** BS files to the target directory
> (`~/.local/lib/bs` for `--local`, `/usr/local/lib/bs` for system
> install; paths can be overridden via `PREFIX`/`LIB_DIR`/`BIN_DIR`)
> and creates a `bs` wrapper in the matching `bin/`. After a successful
> install, the source repository can be removed — the framework will
> run from the target directory.

## Verify the installation

```bash
./bs doctor    # framework integrity check
./bs list      # list modules
./bs version   # framework version
./bs version --full   # + where this copy is from
```

- `bs doctor` checks that `bootstrap/init.sh`, the core modules, and the
  `core/` and `lib/` directories are present under `BS_ROOT`, and exits
  non-zero if anything is missing.
- `bs list` prints the modules located directly in `core/` and `lib/`
  (for example `core/args.sh`, `lib/automation.sh`). Nested modules such as
  `lib/io/streams.sh` live in subdirectories and are loaded by path.

## Your first script

Runnable copy: [examples/hello.sh](../../../examples/hello.sh).

```bash
#!/usr/bin/env bs
# shellcheck shell=bash

load "lib/io/streams"

io::streams::print "hello from BS $(bs::version::get)"
```

- `#!/usr/bin/env bs` — runs the script through the `bs` interpreter; the
  framework core is loaded before your code, so no bootstrap boilerplate is
  needed.
- `# shellcheck shell=bash` — required on line 2 when the shebang is `bs`.
- Strict mode is already enabled by the interpreter (`set -euo pipefail`
  before your script is sourced) — no strict line needed here. Only plain
  `#!/usr/bin/env bash` entry points set it themselves, via `utils::strict`
  (post-kernel) or the pre-kernel `bs::strict` from `bootstrap/bs.sh`.
- `load "lib/io/streams"` — path relative to `BS_ROOT`, no `.sh`. Never
  `source` framework modules directly in a new script.
- `io::streams::print` — safe output: a `printf '%s\n'` wrapper that does
  not break on values like `-n` or `-e`. The version comes from the core
  function `bs::version::get`.

## Running scripts

```bash
./bs run examples/hello.sh
./examples/hello.sh          # when bs is in PATH
```

Landing examples:

```bash
./bs run examples/hello.sh     # short script
./bs run examples/todo.sh      # TUI todo list (lib/tui)
./bs run examples/pulse.sh     # host capability pulse
```

CLI with `core/args` (auto-help, validation) is in the
[first-script tutorial](../05-tutorials/first-script.md).

## How the kernel works: UML diagrams

The diagrams below use [Mermaid](https://mermaid.js.org/) (GitHub draws them itself). Colour carries meaning: **teal** — the `@shell posix` tier (runs in any shell), **purple** — the `@shell bash4` tier (needs bash 4.2+), grey — entry points. First the overall picture, then six scenarios.

### Components

```mermaid
flowchart TB
  classDef entry fill:#F1EFE8,stroke:#5F5E5A,color:#2C2C2A
  classDef posix fill:#E1F5EE,stroke:#0F6E56,color:#04342C
  classDef bash4 fill:#EEEDFE,stroke:#534AB7,color:#26215C
  subgraph E["entry points"]
    bs["bs"]:::entry
    boot["boot.sh"]:::entry
    inst["install.sh"]:::entry
  end
  subgraph P["bootstrap/ · POSIX"]
    shell["shell.sh<br/>shell registry"]:::posix
    tramp["trampoline.sh<br/>re-run in bash"]:::posix
    sheb["shebang.sh<br/>#! management"]:::posix
  end
  subgraph B["bootstrap/ · bash4"]
    bssh["bs.sh<br/>pre-kernel, bs::cli"]:::bash4
    init["init.sh"]:::bash4
    loader["loader.sh<br/>load, @depends"]:::bash4
  end
  subgraph C["core/"]
    direction TB
    subgraph CP["@shell posix"]
      prereq:::posix
      guard:::posix
      const:::posix
      version:::posix
      quiet:::posix
    end
    subgraph CB["@shell bash4"]
      lang:::bash4
      args:::bash4
      errorhandler:::bash4
      config:::bash4
      logger:::bash4
      utils:::bash4
      deps:::bash4
      calc:::bash4
      repl:::bash4
    end
  end
  bs -.-> shell
  boot -.-> shell
  inst -.-> shell
  shell -.-> tramp
  bs -.-> bssh
  bssh -.-> init
  init -.-> loader
  loader -.-> CP
  loader -.-> CB
  CB -.-> CP
  inst -.-> sheb
```

Arrows are dependencies (who sources whom). `init.sh` loads the `core/` files of the package top to bottom.

### Scenarios

#### 1. `bs script.sh` or `#!/usr/bin/env bs` from bash 4.2+

![Scenario 1: bs script.sh from bash 4.2+](../../assets/uml/scenario-1-en.svg)

<details>
<summary>Diagram source (Mermaid)</summary>

```mermaid
sequenceDiagram
  autonumber
  actor U as User
  participant bs as bs
  participant sh as shell.sh
  participant bsh as bs.sh
  participant init as init.sh
  participant core as core/*
  participant S as script.sh
  U->>bs: ./script.sh (the shebang starts bs)
  bs->>sh: bs_shell_host_ok (prologue: is this shell fit?)
  sh-->>bs: yes: bash ≥ 4.2, not POSIX mode
  bs->>bsh: source (bs::strict, bs::cli::*)
  bs->>init: source
  init->>core: load prereq, lang, const, logger, errorhandler, version, quiet, utils, config, deps
  init-->>bs: BS_INITIALIZED=1
  bs->>bs: BS_SHEBANG=1: the first argument is a file
  bs->>S: a new bash: init.sh, then source the script
  S->>core: load "lib/..." on demand
  S-->>U: exit: EXIT trap, cleanup stack (LIFO)
```

</details>

#### 2. Start from dash, ash or another shell: re-run in bash

![Scenario 2: start from dash — re-run in bash](../../assets/uml/scenario-2-en.svg)

<details>
<summary>Diagram source (Mermaid)</summary>

```mermaid
sequenceDiagram
  autonumber
  actor U as User
  participant d as dash ./bs
  participant sh as shell.sh
  participant tr as trampoline.sh
  participant b as bash 4.2+
  U->>d: dash ./bs version
  d->>sh: bs_shell_host_ok
  sh-->>d: no: this is dash
  d->>tr: source
  tr->>sh: bs_shell_host_find (looks for bash 4.2+: BS_HOST_BASH, PATH, usual paths)
  alt bash 4.2+
    tr->>b: found: exec bash, same file and arguments
    Note over tr,b: BS_ORIGIN_SHELL=dash (for --strict-shell)
    b-->>U: goes on as in scenario 1
  else
    tr-->>U: not found: a message about what to install (apk, apt, dnf, brew)
  end
```

</details>

#### 3. Calling a kernel function from fish or nushell: `bs call`

![Scenario 3: bs call from fish or nushell](../../assets/uml/scenario-3-en.svg)

<details>
<summary>Diagram source (Mermaid)</summary>

```mermaid
sequenceDiagram
  autonumber
  participant F as fish / nushell
  participant bs as bs call
  participant core as kernel loaded (as in scenario 1)
  participant fn as FUNCTION
  F->>bs: bs call --load lib/system/info system::info::os
  bs->>core: kernel loaded (as in scenario 1)
  bs->>bs: check: function name and module path against a pattern
  alt ✗
    bs-->>F: invalid: code 2
  else
    bs->>core: --load: load the module
    alt ✗ declare -F
      bs-->>F: no such function: code 127
    else
      bs->>fn: run
      fn-->>F: stdout, stderr and the function's code
    end
  end
```

</details>

#### 4. The POSIX tier directly, without bash

![Scenario 4: the POSIX tier without bash](../../assets/uml/scenario-4-en.svg)

<details>
<summary>Diagram source (Mermaid)</summary>

```mermaid
sequenceDiagram
  autonumber
  participant D as a dash script sources the layer
  participant sh as shell.sh
  participant pre as prereq.sh
  participant q as quiet.sh
  D->>sh: . bootstrap/shell.sh
  D->>pre: . core/prereq.sh
  D->>q: . core/quiet.sh
  D->>q: bs_utils_has ls
  q-->>D: code 0 or 1; bash was not started
```

</details>

#### 5. Install: `./install.sh --local`

![Scenario 5: install](../../assets/uml/scenario-5-en.svg)

<details>
<summary>Diagram source (Mermaid)</summary>

```mermaid
sequenceDiagram
  autonumber
  actor U as User
  participant i as install.sh
  participant k as kernel
  participant a as install/actions.sh
  participant sb as shebang.sh
  participant fs as ~/.local/lib/bs
  U->>i: ./install.sh --local
  i->>k: prologue and kernel: as in scenario 1 or 2
  i->>a: copy bootstrap, core, bs, lib into staging
  a->>sb: adapts the #! to the machine (Termux)
  a->>a: the .install manifest and the wrapper
  a->>fs: atomic rename of staging to ~/.local/lib/bs
  i-->>U: PATH for the user's shell
```

</details>

#### 6. Update: `bs update`

![Scenario 6: update](../../assets/uml/scenario-6-en.svg)

<details>
<summary>Diagram source (Mermaid)</summary>

```mermaid
sequenceDiagram
  autonumber
  actor U as User
  participant bs as bs update
  participant sb as shebang.sh
  participant t as copy the source into…
  participant inst as installed bs
  U->>bs: bs update
  bs->>t: copy the source into a temporary directory
  bs->>sb: shebang of bs and the wrapper for the machine
  bs->>inst: swap the parts, old ones to .update-old
  bs->>inst: smoke test: bs version as a program
  alt ok
    bs-->>U: ok: manifest, cleanup
  else
    bs-->>U: failure: rollback
  end
```

</details>


## Where to go next

- [Architecture](../02-core-concepts/architecture.md) — boot stages,
  `BS_ROOT`, the module loader
- [core/args module](../03-modules/args.md) — parameter trees, flags,
  bash completion
- [lib/io/streams module](../03-modules/io-streams.md) — safe printing,
  redirection, pipes
- [Tutorial: your first script](../05-tutorials/first-script.md) — a
  step-by-step walkthrough

See also the [repository README](../../../README.md) and the runnable
examples in [examples/](../../../examples/).
