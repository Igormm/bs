# Changelog

## [Unreleased]

### Added
- shells: BS entry points (`bs`, `install.sh`, `boot.sh`) start with a POSIX prologue and re-run themselves in a capable bash via `bootstrap/trampoline.sh` (`sh install.sh`, `dash ./bs`, `zsh ./bs`, bash as `sh`); `BS_HOST_BASH` overrides the search; without bash 4.2+ a bilingual message with install hints
- shells: `bootstrap/shell.sh` — POSIX registry of shells (bash zsh dash ash sh ksh mksh oksh osh fish nu): rc file, PATH line, reload command, host search, tier; `bs::shell::*` aliases in bash/zsh
- shells: `@shell posix|bash4` annotation, `platform::get user_shell|shell_tier` (native / hosted / unsupported)
- install: PATH is set up for the user's shell (`--shell NAME`, `BS_USER_SHELL`), uninstall cleans every family; `bs init-shell [SHELL|--list]`; `bs where` shows the shell section
- shells: tier synonyms (`sh`, `shell` = posix; `bash` = bash4; `fs` = fish; `nushell` = nu) in `@shell` and for the origin shell (`bs_shell_tier_word`)
- cli: `bs --strict-shell` / `BS_SHELL_STRICT=1` — a `lib/` module loads only if its `@shell` tier fits the shell bs was started from (`BS_ORIGIN_SHELL`, set by the trampoline); `core/` is always allowed; `bs_shell_file_tier`, `bs_shell_tier_allows`
- refactor: the 63 commands and helpers of the `bs` file moved to `bootstrap/bs.sh` as `bs::cli::*` (`bs` is now a thin entry point: prologue, kernel load, flags, dispatcher); `bs::is_main` replaces 20 copies of the BASH_SOURCE/BASH_EXECUTION_STRING guard; `utils::ensure_shell_version` and `bs::shell::ensure_version` check the bash version only
- refactor: no shell-specific checks outside the abstraction layer — `bs::script_path`, `bs::stack_depth/file/line/func`, `bs::shell::version_string`, `bs::trace_prefix`, `bs_shell_login_path` replace `BASH_SOURCE`/`BASH_LINENO`/`FUNCNAME`/`BASH_VERSION`/`$SHELL` in core, lib, examples, install and 128 tests; entry points use `$0`; tests run through `bs run`; `bs::is_main` is true only for the running script (`BS_RUN_SCRIPT`), not for every file sourced under `bs run`
- fix: code that assumed the default IFS broke under the strict IFS of `bs` scripts: `sshnetwork::close_tunnel` found no tunnel, `io::files::copy_matching` read `*.sh *.md` as one pattern (fixed with `IFS=' ' read`); found because the tests now run through `bs run`
- refactor: the entry points ask the shell registry (`bs_shell_host_ok`; shell.sh is now idempotent) instead of repeating the BASH_VERSION test; `loader.sh` and `bs.sh` take the bootstrap directory from `BS_BOOTSTRAP_DIR` set once by `init.sh`; `find_leaks.sh` exempts only the layer files and lines tagged `shell-gate`
- refactor: `FUNCNAME` uses go through `bs::func_name`/`bs::stack_func`; the entry points read their directory once (`BS_ENTRY_DIR`); the leak finder also looks for `FUNCNAME`, `BASH_LINENO`, `$BASH`, `/proc/$$`, `$0` as a path; unavoidable places carry a `shell-gate` tag
- refactor: child shells start in the running bash (`bs::shell::host`) — `bs run`, osagent, ts stack, sshnetwork, Homebrew install; `bs run` passes the script path as `$0`; registry questions `bs_shell_can_source`, `bs_shell_rc_create_ok`, `bs_shell_default_login_path` replace family comparisons; the installed wrapper is POSIX `#!/bin/sh`; `shopt nullglob` removed from sshd and fail2ban
- feat: `args::completion PROG [bash|zsh|fish|nu]` (`BS_COMPLETION_SHELL`), examples accept `--emit-completion[=SHELL]`; zsh tested in a real zsh, fish and nushell as text only
- refactor: `BASH_SUBSHELL` and `BASH_XTRACEFD` go through `bs::shell::in_subshell` / `bs::trace_to_fd`; `bash -n` and the update smoke test run in the host bash; the leak finder covers every `BASH_*` (except the `BASH_REMATCH` capture) and explicit `bash`/`zsh` calls
- skill: bs-shell-abstraction (`scripts/find_leaks.sh`), bs-shell-portability (tier_scan.sh, probe_shells.sh, shell matrix); docs: 08-development/shell-portability.md
- tests: unit/testshellunit.sh, testtrampolineunit.sh, testshelltierunit.sh, integration/testinstallshells.sh, unit/testshellstrictunit.sh

### Not verified
- ash/busybox, ksh, mksh, oksh, osh, fish, nu were not run on real interpreters; only generated texts are tested

## [0.7.4] - 2026-10-12

### Added
- cli: bs update --pull — `git pull --ff-only` in the local repository before anything else (history is never rewritten, nothing is merged); the interactive question about a repository that is behind GitHub gets `[p]ull` (the default when the pull is possible): pull, then install from the repository; without a terminal the warning names `--pull`; a refusal (uncommitted changes, diverged history, no upstream, no network, no repository around) is explained, exits 1 and changes nothing
- cli: bs update — after the install it prints "State after the update" (installed version, the repository with its version, commit and relation to GitHub, a verdict); `--github` next to a repository that is behind says that the repository was NOT updated (bs update copies only bs, bootstrap, core, lib — examples/ and tests/ stay as they are), which is why a flag added on GitHub was "missing" after an update
- agents: skill bs-scenario-audit — a scenario-driven sweep for logic errors in library functions and CLI commands: a six-part scenario card per function (user scenario, main scenario, alternative scenarios, scenario parameters, half-scenario = interrupted midway, parameter groups), actual-vs-expected runs in a sandbox with the safety rules learned from this project, a two-lane scheme for business-logic findings, 12 classes of logic errors (references/logic-traps.md) and scripts/inventory.sh, a read-only inventory of public functions with parameters, risk markers and test coverage (core, lib and bootstrap: 1193 functions, 579 without tests, 332 with risk markers)
- tests: unit/testscenarioinventoryunit.sh (the inventory on a fixture tree)
- tests: unit/testupdatepullunit.sh — the install/repository/GitHub scenario table (42 checks on local file:// repositories)

### Fixed
- security: a project-local `./.bsrc` (it can come from a foreign repository) could export any key, including `LD_PRELOAD` and `BS_UPDATE_REPO`; now it accepts only the keys of `BS_CONFIG_LOCAL_KEYS` and ignores the rest with a warning (core/config.sh, documented in core-api.md)
- security: the temp-file registry of `utils::tempfile` was a predictable file in `$TMPDIR` that was cleaned with `rm -rf` on exit whoever had written it; now ownership and symlinks are checked, paths must lie inside the registry directory, the file is created exclusively
- security: API keys and tokens were visible in `ps` (curl argv) in `llm`, `vkapi` — they now go through stdin; `http --header` still puts a header into argv (open: needs a change of the `__http::curl_args` format)
- security: `sshnetwork::test_connection` ran the host as bash code (command injection); `monitor_network` took the host as the interval and looped without a pause; `close_tunnel` matched any process containing the port as a substring; `system::security::apparmor` removed `/etc/apparmor.d/force-enabled/<profile>` for a profile like `../../passwd`; `users::set_password` accepted a password with a newline (changing the root password); `utils::process_stop`/`kill_by_name` with an empty or `0` argument killed the caller's process group or every process; `devices::display brightness` evaluated an arbitrary string in arithmetic
- data loss: `wireguard::remove_peer` dropped the `[Peer]` header of every peer and reported success (and with an unknown key rewrote the file and the backup); `api::spec::drop` used the name as a regular expression and could wipe the registry; `vkmusic::download` wrote outside the output directory and overwrote a track with the same sanitised name; `system::permissions::recursive` accepted `/` and `/etc`; `system::distrologic::fs_format_*` ignored dry-run and formatted without checking the device; `automation::configure_log_rotation` overwrote the distribution's logrotate files
- installer/CLI: `bs uninstall` and `install.sh uninstall` removed the wrapper before the library (a failed `rm` left a half-deleted install with the command gone), a symlinked library left a dangling link and a stale wrapper; in a terminal the installer's `exec $SHELL` swallowed the "another install exists" notice; `args::parse` treated `-h` after `--` or as a flag value as a request for help; `error::retry 0` returned success without running; `utils::detect_root` returned `core/`
- failures reported as success: package, service, interface, route, firewall, time, locale and display functions in `lib/system` and `lib/automation.sh` wrote "done" and returned 0 after a failed command (`dnf check-update` exit 100 also broke `pkg_update_all` and killed callers under `set -e`); `automation::detect_package_manager` could never match (its log line went into the command substitution); `vkmusic::upload_audio` always failed on the same stdout mix and with a garbage server answer called `audio.save` with empty fields; `osagent::ask` printed nothing and returned 0 for a plain-text model answer; `io::process::guard` under `set -e` lost the output of a failed command
- `system::security::disable_root` (no other admin, no `sshd -t`, no rollback), `password_policy` (replaced the `pam_unix` line), `firewall disable` (flushed rules under `-P INPUT DROP`), `display::manager`/`multi` (stopped the session before checking), `systemaudit` (a one-category audit scored 100/100, a failed report write logged as "generated", false HIGH for `Protocol 2`), `platformcheck::show_report` (installed packages itself) and about ten more functions in `lib/system` were fixed; details and the reproduction for each finding are in the tests `tests/unit/testauditsystem*unit.sh`, `testauditlib*unit.sh`, `testauditcore*unit.sh`
- tests: `testhttpunit.sh` no longer calls api.github.com; placeholder `assert_true "true"` assertions in `testpresentationunit.sh`, `testrfcunit.sh`, `teststackunit.sh` now compare real output; 12 new audit test files (every fix has a test that fails on the old code)

## [0.7.3] - 2026-10-12

### Added
- examples: send_video.sh — `--prefill TEXT` presets the start of the model's answer (an assistant message with vLLM `continue_final_message`), the most reliable way to keep the language of the answer when a vision model drifts to English; the report shows the prefix plus the continuation; the prefill is part of the run's identity; tests for the `--prompt-file` / `--system` / `--prefill` request body (unit/testsendvideoprefillunit.sh)
- cli: bs where [--deep] — read-only report of every trace of BS on the machine: the running copy, every `bs` in PATH (wrapper → install, launcher, broken, foreign), installs with kind/version/manifest/owner/leftovers, source checkouts, lines in shell rc files, data and cache directories, environment variables, and a summary of what looks wrong with the commands to fix it; `--deep` also searches ~, /opt, /usr/local, /srv; no found copy of bs is run
- examples: send_audio.sh — while a long request is processed (a Whisper chunk on a CPU takes minutes) it prints "waiting for the server: N s, chunk i/n" every `SEND_AUDIO_HEARTBEAT_S` seconds (default 20), and after each chunk the progress, the speed relative to real time and the estimated remaining time; Ctrl-C/SIGTERM now also stops the background `curl`
- install: the "ALREADY INSTALLED" notice compares the versions (update available / the same / the installed one is newer), offers the repository command first (`./bs update --local` works without `PATH`; before, the only advice was `bs update --local`, useless when `bs` is not in the shell's `PATH`), and warns when `bs` is missing from the `PATH` of the shell or another copy runs first
- tests: unit/testsendaudioprogressunit.sh

## [0.7.2] - 2026-10-12

### Changed
- cli: bs update / bs uninstall — the running copy is described by exactly the rows of `bs version --full` (root, install, source, updated; for a checkout its commit and uncommitted changes): the "Запущен / Running: bs VERSION" block opens every run and every notice box, ERROR/WARN end with the same data in one line (before, a shorter summary built by separate code covered only part of the fields)

## [0.7.1] - 2026-10-12

### Added
- install: negative scenarios are explained by bilingual notices instead of raw errors — "ALREADY INSTALLED" (versions, `bs update`, uninstall + install, another `PREFIX`), "PARTIAL INSTALL — REPAIRING", "ANOTHER INSTALL EXISTS" (which copy `bs` will run, by `PATH` order), "NOTHING TO REMOVE", "PART LEFT IN PLACE"; install/notice.sh is the new home of the notices and checks
- install: the installer never deletes or overwrites what is not BS — a foreign `TARGET_LIB` (directory, file, symlink, source checkout) and a foreign `TARGET_BIN` (no `export BS_ROOT=`) are refused for install and left alone by uninstall (the old `rm -rf TARGET_LIB` without a check is gone); installation is transactional (staging next to the target + rename, the previous copy is put back on failure, the ERROR names the real cause)
- install: write access to `BIN_DIR`/`LIB_DIR` is checked instead of `EUID`, so `PREFIX=/opt/x ./install.sh` works without root; `sudo ./install.sh --local` into the home of `SUDO_USER` is refused (root-owned files in a user's home), with `HOME=/root` it only warns; unset or unwritable `HOME`, a relative `PREFIX`, forbidden characters in paths, `BIN_DIR` equal to `LIB_DIR` and an incomplete source are bilingual errors; `BIN_DIR` outside `PATH` gets the exact `export` line; an unwritable rc file no longer aborts the install; uninstall edits rc files in place (keeps a symlinked dotfile and its owner)
- install: `BS_SYSTEM_PREFIX` (default `/usr/local`) defines the system install for `install.sh`, `bs update` and `bs uninstall`, so the system case can be reproduced without root; manifest `mode` is `local`/`system`/`custom`
- cli: bs update — every run starts with "Запущен / Running: bs VERSION | ROOT | KIND | …" and the same line opens every notice box and ends every ERROR/WARN, so output always shows which copy of `bs` produced it (also for `bs uninstall`)
- cli: bs update — `--local` with only a system install (and the reverse) says so and gives the command ("UPDATE NOT DONE", exit 1); "BS NOT INSTALLED"; explanations for root/sudo (the install of `SUDO_USER`), a broken wrapper in `PATH`, a lib without a wrapper, several installs of different versions (`path: OLD → NEW`, `PATH` order, DOWNGRADE for every kind of target), a damaged manifest (kept as `.install.bad`), a symlink target, `--github` failures (no network, missing branch/tag, no git/curl); the full table is in documentation/{en,ru}/install.md
- cli: bs update — the target must be a BS install and the source must be complete (`bs`, `bootstrap/{init,loader}.sh`, `core/`, `lib/`, `core/version.sh` with a version) before anything is written; the old parts are kept in `.update-old.PID` and restored if the smoke test (`bs version` from the target) fails or the run is interrupted; leftovers of crashed runs are cleaned; `.update-lock` stops two simultaneous updates; a copy failure is an ERROR with exit 1 (it used to end as "NO UPDATES", exit 0); a mixed run with a failed target ends with exit 1 after the summary
- cli: bs uninstall — framed notices instead of "see messages above", a check of write access, a wrapper of another install stays, the removal of the running copy is announced; `bs version --full` and `bs env` cope with a damaged manifest and a checkout without git
- docs: install.md (en/ru) — installation types (system/local/custom/source checkout), the install manifest, a full `bs update` section (targets vs sources, the four common commands for a local and for a system install, local repo vs GitHub, safety), uninstall autodetect, fresh shell after a local install
- version: BS_VERSION 0.7.1 — the number lives only in core/version.sh (core/const.sh pulls it in, its own copy is gone); bs::version::of <dir> reads the version of another BS directory without running its code; bs version --full shows where this copy is from (root, install mode, source commit, last update); bs update prints "version old → new" and warns about a DOWNGRADE
- examples: send_video.sh / send_audio.sh — a reliable checkpoint: *.state records the exact sizes of the report and the results, so a resume cuts off anything written after it (a crash between the append and the state write) and never duplicates a piece; Ctrl-C/SIGTERM/SIGHUP mark the run as stopped; a resume checks that the media is cut into the same number of chunks and that the files were not shortened; .video.lock/.audio.lock keep two copies out of one directory; a plain file given as --output now gets a clear message
- tests: unit/testsendcommonunit.sh — run directory naming and creation, key=value files, checkpoint size helpers, lock
- examples: send_audio.sh — transcribe the audio track of a video through /v1/audio/transcriptions (Whisper): mono 16 kHz WAV on the video timeline, phrases with start_ms/end_ms, understands start_ms/end_ms segments and OpenAI verbose_json
- examples: send_video.sh / send_audio.sh — run directory <output>/<media name>/ shared by both: *.params (settings of the run, incl. the chunk length found by probing), *.state (checkpoint), *.txt report, *.jsonl results with millisecond bounds, logs; a rerun resumes from the checkpoint, --restart starts over, a failed chunk stops the run (send_video: --keep-going keeps the old behaviour); examples/send_common.sh holds the shared helpers
- install: install manifest <lib>/.install (mode, prefix, lib, bin, version, source, source repo/commit, date, user) written by install.sh; bs update refreshes it (updated_at/updated_from/updated_commit) and creates one for installs made by an older installer; bs env prints it; bs uninstall takes the wrapper path from it
- cli: bs update — target autodetect also covers the installed copy bs runs from and the install behind the `bs` wrapper in PATH (custom --lib); a root-owned install is updated through sudo when run in a terminal; the up-to-date check now runs before the writability check
- cli: bs update --github [--repo URL] [--ref REF] — update installed copies straight from GitHub (shallow clone, tarball fallback); an installed copy with no repo around falls back to GitHub automatically; a local checkout is compared with the remote (ls-remote) — when it lacks new code bs warns and asks which source to use, and warns about unpushed/uncommitted local changes when installing from GitHub
- agents: import 14 engineering skills from alirezarezvani/claude-skills (MIT); apply — security audit of skills, CHANGELOG.md, PR review, persona review of lib/tui/app
- skills: bs-audit — полный аудит проекта (валидация, сниппеты, артефакты, en/ru синхронизация, ревизия модулей)
- lib/tui: высокоуровневый слой app.sh — окна, кнопки, биндинги, модалки, цикл; app_demo.sh для новичков; todo.sh переведён на tui::app (267→150 строк)
- tests: validatedocscode.sh — проверка сниппетов кода в документации (конвенции, load-пути, API, соответствие examples/); skill bs-check-docs-code
- pre-kernel: bs::strict in bootstrap/bs.sh — pre-load strict-mode helper for plain-bash entry points; applied in bs, boot.sh and bs run (child bash); docs updated
- cli: bs uninstall — remove installed BS copies (wrapper + lib tree) with safety guards
- core: pre-kernel shell gate — bs::shell::ensure_version in bootstrap/bs.sh (runtime vars, not $SHELL) usable before the loader
- shell: abstract shell detection — bs::shell::{name,version,ok,is_sourced} in core/prereq.sh (runtime vars, not $SHELL); init.sh guard + facts.sh dedupe to helpers; shell facts renamed to shell_version
- platform: shell as a capability — facts shell/shell_ok/bash_version in tier system (bash 4.2+ full, zsh init-level, others unsupported); init.sh source-guard works in zsh via ZSH_EVAL_CONTEXT, BS_ROOT detection via funcsourcetrace
- utils: wrapper round — utils::tempfile (on-disk registry, subshell-safe cleanup via BASH_SUBSHELL guard), utils::human_size (promoted from hw), utils::head_bytes; applied in hw/osagent/process; errorhandler test checks membership not count
- integration: osagent — model-agnostic OS agent: tool schema + platform context in prompt, JSON tool protocol, deny-by-default permissions (exec gated), dry-run, api.call restricted to GET/HEAD
- cli: bs api — load/list/info/paths/call/drop; spec registry on disk (survives processes)
- api: OpenAPI 3.x client — spec load (file/URL, cached), introspect (info/paths), call operations with automatic param classification (path/query/header/body), required validation, Bearer auth, raw --json vs pretty output
- ts: lib/ts/toolchain - TS dev-toolchain detection and validation gates (runtime/lockfile probes, tsc/eslint/prettier validate with machine-readable output, doctor, port_free) with unit tests and docs (en+ru)
- agents: bs-commit-pro skill - commit engineering (atomic intent, staging discipline, bisect/revert safety, series ordering); cross-link from bs-commit-style
- examples: sensor TUI monitor and diagnostics CLI; test(sensor): unit tests with fake sysfs/evdev fixtures (record decoding, capabilities, diagnose, graceful degradation)
- examples: migrate todo.sh to lib/tui; add hello.sh, pulse.sh demos; add sensor.sh (input_event decoding)

### Changed
- agents: systematize AI workspace — ai/ → .agents/{skills,prompts,guides}; webserver-analysis → .art; fix all references (AGENTS.md, docs, skills); add .agents/README

### Fixed
- examples: send_video.sh — resuming a run with `--segment 0` deleted the user's original video file (the "chunk" is the file itself); files without an extension or with a dot in the directory name broke the probe/chunk paths
- audit: systemaudit counters `((x++))` no longer abort the report under `set -e` (also in regex, dataprocessor, frameworksintegration, vkmusic, vkapi, ps1status); the `netstat|ss` dependency is checked (it used to be an unquoted pipeline); `deps::missing_tools` splits packages by spaces under the strict IFS
- safety: `validate_path` normalises the path (`/etc/`, `//`, `/etc/.`, `/tmp/../etc`) and refuses an empty one — all of them used to pass
- sshd: `install_main` puts the common block at the start of sshd_config and Match sections at the end (sshd takes the FIRST value of a directive, so the hardening did not apply), and keeps the file mode; user: `write_sudoers` writes through a temporary file (the previous file is no longer lost when visudo fails) and turns commands into absolute paths (rules without one were always rejected)
- system: services/packages/network/routing/logging return and log command failures instead of "success" (service start/stop, apt/dnf install/remove/upgrade, interfaces, gateway, static IP, routes); `routing::default` is atomic (`ip route replace`); `list_interfaces` no longer hides `wlo1`; netmask for any prefix; `network::dns` in dry-run changes nothing; routes/tables cannot delete reserved tables; `${N}` → `${N:-}` for optional arguments in six system modules (no more "unbound variable" under `set -u`)
- fail2ban: enum values like `auto,pyinotify` are rejected, a backup no longer overwrites the copy made in the same second, revert keeps the caller's `nullglob`
- wireguard: `generate_keypair` no longer overwrites an existing private key; secrets are created with umask 077; `BS_WIREGUARD_CONFIG_DIR`/`BS_WIREGUARD_BACKUP_DIR` for tests
- version: `bs::version::compare` cuts suffixes (`1.2.3rc1`, `-beta`) instead of turning them into digits; `utils::human_size` accepts KiB/MiB/GiB
- tests: sshd tests no longer call the real `systemctl`; `testsystemaudit` — fixed the expected score and the endless recursion of the `command` mock (it ended in a segfault); new unit tests: safety, services, packages, systemlogging, systemauditreport, sendvideoresume, wireguardkeys, update/uninstall safety; known open: `tests/audit/testsystemaudit.sh` (root-only) still stops in the full-audit case
- examples: send_video.sh — the chunk-length search stopped on the vLLM error "Input length (N) exceeds model's maximum context length (M)" (size not recognised); the default prompt was sent empty when --prompt was not passed
- cli: bs uninstall refused to remove the install it was started from ("refusing to remove the BS source checkout") — the guard compared the target with BS_ROOT; a checkout is now recognised by .git or tests/
- lib/tui: app.sh — warn on unknown window/button ids, bind args via record separator, reset → private __reset; 3 new tests

<!-- recommended-semver-bump: minor -->

## [0.6.0] - 2026-09-28

### Added
- skills: bs-audit — полный аудит проекта (валидация, сниппеты, артефакты, en/ru синхронизация, ревизия модулей)
- lib/tui: высокоуровневый слой app.sh — окна, кнопки, биндинги, модалки, цикл; app_demo.sh для новичков; todo.sh переведён на tui::app (267→150 строк)
- tests: validatedocscode.sh — проверка сниппетов кода в документации (конвенции, load-пути, API, соответствие examples/); skill bs-check-docs-code
- pre-kernel: bs::strict in bootstrap/bs.sh — pre-load strict-mode helper for plain-bash entry points; applied in bs, boot.sh and bs run (child bash); docs updated
- cli: bs uninstall — remove installed BS copies (wrapper + lib tree) with safety guards
- core: pre-kernel shell gate — bs::shell::ensure_version in bootstrap/bs.sh (runtime vars, not $SHELL) usable before the loader
- shell: abstract shell detection — bs::shell::{name,version,ok,is_sourced} in core/prereq.sh (runtime vars, not $SHELL); init.sh guard + facts.sh dedupe to helpers; shell facts renamed to shell_version
- platform: shell as a capability — facts shell/shell_ok/bash_version in tier system (bash 4.2+ full, zsh init-level, others unsupported); init.sh source-guard works in zsh via ZSH_EVAL_CONTEXT, BS_ROOT detection via funcsourcetrace
- utils: wrapper round — utils::tempfile (on-disk registry, subshell-safe cleanup via BASH_SUBSHELL guard), utils::human_size (promoted from hw), utils::head_bytes; applied in hw/osagent/process; errorhandler test checks membership not count
- integration: osagent — model-agnostic OS agent: tool schema + platform context in prompt, JSON tool protocol, deny-by-default permissions (exec gated), dry-run, api.call restricted to GET/HEAD
- cli: bs api — load/list/info/paths/call/drop; spec registry on disk (survives processes)
- api: OpenAPI 3.x client — spec load (file/URL, cached), introspect (info/paths), call operations with automatic param classification (path/query/header/body), required validation, Bearer auth, raw --json vs pretty output
- ts: lib/ts/toolchain - TS dev-toolchain detection and validation gates (runtime/lockfile probes, tsc/eslint/prettier validate with machine-readable output, doctor, port_free) with unit tests and docs (en+ru)
- agents: bs-commit-pro skill - commit engineering (atomic intent, staging discipline, bisect/revert safety, series ordering); cross-link from bs-commit-style
- examples: sensor TUI monitor and diagnostics CLI; test(sensor): unit tests with fake sysfs/evdev fixtures (record decoding, capabilities, diagnose, graceful degradation)

### Changed
- agents: systematize AI workspace — ai/ → .agents/{skills,prompts,guides}; webserver-analysis → .art; fix all references (AGENTS.md, docs, skills); add .agents/README

<!-- recommended-semver-bump: minor -->

All notable changes to this project will be documented in this file.

