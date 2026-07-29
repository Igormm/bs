# BOSA Framework Examples

This directory contains example scripts demonstrating various features and use cases of the BOSA framework.

## Examples Included

### PS1 Configuration Example
**File:** `ps1_configuration_example.sh`

Demonstrates the advanced PS1 configuration module with features surpassing oh-my-zsh:
- Multiple built-in themes (default, powerline, minimal, time, rainbow)
- Git repository information with branch and status
- SSH connection detection
- Python virtual environment detection
- Dynamic time display
- Interactive theme selection
- Professional and minimal configurations

**Usage:**
```bash
# Run interactively
./examples/ps1_configuration_example.sh

# Or source for use in .bashrc
source examples/ps1_configuration_example.sh
# Then run: setup_ps1_professional
```

### IO Streams Examples
**Files:** `iostreams_output_example.sh`, `iostreams_input_example.sh`,
`iostreams_redirection_example.sh`, `iostreams_fd_example.sh`,
`iostreams_pipe_buffering_example.sh`, `iostreams_state_example.sh`,
`iostreams_dev_example.sh`

Demonstrate the `io::streams` module (`lib/io/streams.sh`) — an abstraction
over I/O streams, file descriptors and redirections:

- **Output / Вывод** — `print`, `printn`, `printf`, `eprint`, `tty_print`:
  safe output that never breaks on `-n`/`-e` or format-string injection
- **Input / Ввод** — `read_line`, `read_all`, `feed`:
  reading lines, whole streams and here-string feeding
- **Redirections / Перенаправления** — `redirect_stdout`, `redirect_stderr`,
  `redirect_all`, `silence`: `exec`-based redirection with the correct
  `>file 2>&1` order, all demos run in subshells
- **FD management / Управление FD** — `save`, `restore`, `close`:
  `dup`/`dup2` equivalents with temporary-FD cleanup (no EMFILE leaks)
- **Pipe and buffering / Pipe и буферизация** — `pipe`, `run_line_buffered`,
  `run_unbuffered`: `cmd1 | cmd2` and `stdbuf` buffering control
- **Stream state / Состояние потоков** — `is_tty`, `can_read`,
  `wait_readable`: terminal detection and `poll`/`select` equivalents
- **/dev special files / Специальные файлы /dev** — `null_sink`,
  `random_bytes`, `fd_path`, `list_fds`:
  `/dev/null`, `/dev/urandom`, `/dev/fd/N`, `/proc/self/fd`

**Usage:**
```bash
# Each example runs standalone and non-interactively
bs run examples/iostreams_output_example.sh
```

### Args Parse Example
**File:** `argsparseexample.sh`

Demonstrates the `args` module (`core/args.sh`) — declarative script
parameter trees with automatic validation and help generation:

- `args::define first middle last` — linear parameter chains
- `args::level 1 start stop` — tree branching (alternatives per level)
- `args::describe` — descriptions that land in the generated help
- `args::flag verbose` / `args::flag output value` — `--flag` and
  `--flag value` / `--flag=value` support; flags never occupy positional levels
- `args::parse "$@"` — validation: unknown parameters/flags and wrong-level
  parameters are rejected with a printed reason and auto-generated help
  (`E_INVALID`); `-h`/`--help` prints help and exits cleanly
- `args::completion` — generates a working bash completion function
  from the same tree (levels, alternatives and flags included)

**Usage:**
```bash
bs run examples/argsparseexample.sh deploy now --env production --dry-run
bs run examples/argsparseexample.sh now      # level error + help
bs run examples/argsparseexample.sh --help
source <(bs run examples/argsparseexample.sh --emit-completion)  # bash completion
```

### Combo Examples (args + io::streams)
**Files:** `deploytoolexample.sh`, `passwordgenexample.sh`,
`logmonitorexample.sh`, `quizgameexample.sh`

Small complete tools showing both modules working together:

- **deploytoolexample.sh** — mini deploy tool: parameter tree, `--env`/
  `--dry-run` flags, FD save/restore that sends the whole deploy section
  to a log file while the terminal sees only the summary
- **passwordgenexample.sh** — password generator from `/dev/urandom`
  with `--length`, `--count`, `--hex` flags and a strength estimate
- **logmonitorexample.sh** — live log monitor: a background service writes
  to a pipe, the monitor reads it non-blockingly via `can_read`, shows
  waiting "ticks" and counts ERROR statistics
- **quizgameexample.sh** — timed quiz: the answer is awaited with
  `wait_readable` (poll/select) instead of a blocking `read`;
  non-interactive environments get an auto mode

**Usage:**
```bash
bs run examples/deploytoolexample.sh deploy --env production --dry-run
bs run examples/passwordgenexample.sh --length 24 --count 5
bs run examples/logmonitorexample.sh
bs run examples/quizgameexample.sh          # best in a real terminal
```

## How to Use Examples

### Running Examples
```bash
# Make example executable
chmod +x examples/ps1_configuration_example.sh

# Run example
./examples/ps1_configuration_example.sh

# Or source for use in current shell
source examples/ps1_configuration_example.sh
```

### Integrating into .bashrc
```bash
# Add to ~/.bashrc
cd /path/to/bosa_project
source examples/ps1_configuration_example.sh
setup_ps1_professional
```

### Using in Scripts
```bash
#!/usr/bin/env bash
source "/path/to/bosa/boot.sh"
bosa::init

# Load example functions
source "/path/to/bosa/examples/ps1_configuration_example.sh"

# Use example functions
setup_ps1_basic
```

## Creating New Examples

When adding new examples:
1. Use bilingual comments (Russian/English)
2. Include comprehensive usage examples
3. Add clear explanations of features
4. Provide both interactive and non-interactive modes
5. Document requirements and dependencies
6. Test on multiple distributions

## Best Practices

1. **Always check if BOSA is loaded**
2. **Use proper error handling**
3. **Include usage examples**
4. **Document functions with docstrings**
5. **Test on different terminals**
6. **Consider performance impact**

## Integration with Other Modules

Examples can use any BOSA modules:
```bash
# Load multiple modules
load "lib/ui/ps1config"
load "lib/system/utils"
load "lib/integration/telegramintegration"

# Use together
setup_ps1_professional
system::utils::get_hostname | telegramintegration::send_message "$CHAT_ID"
```

## Testing Examples

All examples should be tested:
```bash
# Test example
./examples/ps1_configuration_example.sh

# Or run through test framework
source tests/testframework.sh
testframework::assert_command "./examples/ps1_configuration_example.sh"
```

## Contributing Examples

When contributing new examples:
1. Follow existing patterns
2. Add bilingual documentation
3. Include usage instructions
4. Test thoroughly
5. Update this README
6. Consider different use cases

## License

Examples are part of the BOSA framework and follow the same licensing terms.
