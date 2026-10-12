# Changelog

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
- platform: shell as a capability — facts shell/shell_ok/bash_version in tier system (bash 4+ full, zsh init-level, others unsupported); init.sh source-guard works in zsh via ZSH_EVAL_CONTEXT, BS_ROOT detection via funcsourcetrace
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
- platform: shell as a capability — facts shell/shell_ok/bash_version in tier system (bash 4+ full, zsh init-level, others unsupported); init.sh source-guard works in zsh via ZSH_EVAL_CONTEXT, BS_ROOT detection via funcsourcetrace
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

