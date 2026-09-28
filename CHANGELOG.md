# Changelog

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

