# Lib modules overview

[↑ Documentation index](../README.md)

The `lib/` directory contains optional feature modules built on top of `core/`. Unlike `core/`, nothing here is loaded automatically — a script loads only the modules it needs.

Modules are loaded with `load`, which resolves paths relative to `BS_ROOT` (the `.sh` extension is omitted):

```bash
#!/usr/bin/env bs

load "core/args"
load "lib/io/streams"
load "lib/system/info"
```

Or, from a plain bash script:

```bash
source bootstrap/init.sh
load "lib/data/dataprocessor"
```

Most lib modules follow the same conventions: a `<module>::init` function, a `<module>::check_dependencies` / `<module>::install_dependencies` pair where external tools are required, and a `<module>::info` help function. Internally the modules rely on the core idioms described in [core-utils.md](core-utils.md) — e.g. `utils::has cmd` instead of `command -v cmd >/dev/null 2>&1`, and `utils::quiet cmd` instead of `cmd >/dev/null 2>&1`.

## io — `lib/io/`

- [streams.sh](../../../lib/io/streams.sh) — low-level I/O stream management: printing, reading, fd redirection, pipes and TTY detection.
- [files.sh](../../../lib/io/files.sh) — high-level file operations: copying, moving, syncing, and removing files/directories with dry-run and unified error handling.
- [process.sh](../../../lib/io/process.sh) — process guard wrapper: timeout, hang detection via stdout/stderr, diagnostic snapshot of `/proc/<pid>` and `strace`.

Key functions: `io::streams::print`, `io::streams::read_line`, `io::streams::redirect_stdout`, `io::streams::pipe`, `io::files::copy_dir`, `io::files::sync_dir`, `io::files::copy_matching`, `io::files::move`, `io::files::remove`, `io::process::guard`.

Details: [io-streams.md](io-streams.md), [io-files.md](io-files.md), [io-process.md](io-process.md)

## system — `lib/system/`

The largest group: wrappers around day-to-day Linux system administration. Modules: [devices.sh](../../../lib/system/devices.sh), [display.sh](../../../lib/system/display.sh), [distro.sh](../../../lib/system/distro.sh) (distro detection), [distrologic.sh](../../../lib/system/distrologic.sh) (per-distro package/service logic), [info.sh](../../../lib/system/info.sh), [keyboard.sh](../../../lib/system/keyboard.sh), [locale.sh](../../../lib/system/locale.sh), [logging.sh](../../../lib/system/logging.sh), [network.sh](../../../lib/system/network.sh), [packages.sh](../../../lib/system/packages.sh), [permissions.sh](../../../lib/system/permissions.sh), [platformcheck.sh](../../../lib/system/platformcheck.sh), [processes.sh](../../../lib/system/processes.sh), [routing.sh](../../../lib/system/routing.sh), [safety.sh](../../../lib/system/safety.sh) (dry-run / confirmation gate), [security.sh](../../../lib/system/security.sh), [services.sh](../../../lib/system/services.sh), [system.sh](../../../lib/system/system.sh), [time.sh](../../../lib/system/time.sh), [users.sh](../../../lib/system/users.sh), [utils.sh](../../../lib/system/utils.sh).

Key functions: `system::distro::detect`, `system::info::all`, `system::packages::install`, `safety::execute`.

## ui — `lib/ui/`

Terminal presentation: colored output helpers ([presentation.sh](../../../lib/ui/presentation.sh)), configurable PS1 prompts ([ps1config.sh](../../../lib/ui/ps1config.sh)), and the BS prompt theme ([bosatheme.sh](../../../lib/ui/bosatheme.sh)).

Key functions: `presentation::header`, `presentation::table`, `ps1config::set_theme`, `bosatheme::apply`.

## network — `lib/network/`

- [sshnetwork.sh](../../../lib/network/sshnetwork.sh) — SSH-based operations across the local network: device discovery, remote command execution, file transfer and tunnels.

Key functions: `sshnetwork::discover_devices`, `sshnetwork::execute_remote`, `sshnetwork::transfer_file`, `sshnetwork::create_tunnel`.

## data — `lib/data/`

- [dataprocessor.sh](../../../lib/data/dataprocessor.sh) — processing and conversion of JSON, XML, CSV, YAML and TSV, with jq / XPath / JSONPath-style querying. Requires external tools (`jq`, `xmllint`, `python3`) installed via `dataprocessor::install_dependencies`.

Key functions: `dataprocessor::json::query`, `dataprocessor::xml::to_json`, `dataprocessor::csv::filter`, `dataprocessor::convert`.

## integration — `lib/integration/`

Clients for external services, VPN tooling, LLMs, Kubernetes and connectors to other systems:
- [http.sh](../../../lib/integration/http.sh) — HTTP client based on `curl`/`wget` with dry-run, timeouts and retries.
- [llm.sh](../../../lib/integration/llm.sh) — unified client for OpenAI and Ollama.
- [k8s.sh](../../../lib/integration/k8s.sh) — `kubectl` wrapper with default namespace and dry-run.
- [vkapi.sh](../../../lib/integration/vkapi.sh) — VK API wrapper with caching and rate limiting.
- [vkmusic.sh](../../../lib/integration/vkmusic.sh) — VK music search/download.
- [wireguard.sh](../../../lib/integration/wireguard.sh) — WireGuard interface and peer management.
- [result.sh](../../../lib/integration/result.sh) — JSON result contract for integrations with Go backends, HTTP APIs and CI systems.

Key functions: `http::get`, `http::post`, `http::retry`, `llm::chat`, `llm::chat_file`, `k8s::pod::list`, `k8s::deployment::restart`, `k8s::apply`, `vkapi::api_call`, `vkmusic::search_and_download`, `wireguard::create_interface`, `wireguard::add_peer`, `result::run`, `result::wrap`, `result::ok`, `result::error`.

Details: [integration-http.md](integration-http.md), [integration-llm.md](integration-llm.md), [integration-k8s.md](integration-k8s.md), [integration-result.md](integration-result.md)

## frameworks — `lib/frameworks/`

- [frameworksintegration.sh](../../../lib/frameworks/frameworksintegration.sh) — compatibility shims that expose ideas from other bash frameworks (bash-it, bashinator, bashly, ShellSpec, MBFL) through a uniform `frameworks::*` API.

Key functions: `frameworks::bashit::load_plugin`, `frameworks::bashly::parse_args`, `frameworks::shellspec::describe`, `frameworks::shellspec::run`.

## status — `lib/status/`

- [ps1status.sh](../../../lib/status/ps1status.sh) — live status indicators embedded into the PS1 prompt: WireGuard, network latency, download speed, audio volume, CPU/memory. Components are toggled individually and refreshed by a background monitor loop.

Key functions: `ps1status::enable_component`, `ps1status::enable`, `ps1status::disable`, `ps1status::audio::toggle_mute`.

## audit — `lib/audit/`

- [systemaudit.sh](../../../lib/audit/systemaudit.sh) — security and compliance auditing of a Linux host: SSH config, firewall, users/sudo, open ports, filesystem permissions, services. Reports are produced in text, JSON, CSV or XML.

Key functions: `systemaudit::run`, `systemaudit::run_full`, `systemaudit::security::check_ssh_config`, `systemaudit::network::check_open_ports`.

## automation — `lib/automation.sh`

A single high-level module that composes the `lib/system/` building blocks into check/act/verify workflows: locale and timezone setup, input devices, display server / desktop environment installation, network interfaces and routes, services and packages.

Key functions: `automation::locale::set_locale`, `automation::system::manage_packages`, `automation::display::detect_desktop_environment`, `automation::network::manage_interface`.

## See also

- [args.md](args.md) — the `core/args` argument-parsing module used by many scripts
- [io-streams.md](io-streams.md) — detailed `lib/io/streams` reference
- [core-utils.md](core-utils.md) — core utility idioms (`utils::has`, `utils::quiet`, `utils::ignore`)
