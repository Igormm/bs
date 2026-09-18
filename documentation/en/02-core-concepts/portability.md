# Portability and capability vector — recommendations

> Recommendations for supporting different platforms (GNU/Linux, macOS,
> FreeBSD, busybox/Alpine) and versioning the project by capability
> vectors. Mandatory rules live in code-style-guide §11; this document
> is the full description and rationale.

## 1. Why

BS runs on Bash 4+ and claims "ubiquity". But "everywhere" is several
worlds:

- **GNU/Linux** — `grep -P`, `sed -z`, `sha256sum`, `stat -c`, `/proc`, `/sys`;
- **macOS and FreeBSD (BSD userland)** — `shasum`, `stat -f`, no `grep -P`
  or `sed -z`, no `/proc`/`/sys`;
- **Alpine (busybox)** — a minimal toolset, `apk` instead of `apt`;
- **musl vs glibc** — matters mostly for binaries; for Bash scripts the
  differences are minor.

The OS name says nothing about capabilities: GNU/Linux may be glibc or
musl, with or without `/sys`, with or without `grep -P`. Therefore we
**version by the capability vector, not by platform names**.

## 2. Capability vector

A set of facts about the current environment:

```
kernel      — linux | darwin | freebsd
arch        — x86_64 | aarch64 | ...
distro      — ubuntu | fedora | ... (ID from /etc/os-release)
family      — debian | rhel | suse | arch | alpine (ID_LIKE chain)
repo        — apt | dnf | apk | pacman | zypper | brew | pkg (derived from family)
userland    — gnu | bsd | busybox
libc        — glibc | musl
bash        — version
tools       — presence of sha256sum/shasum/cksum, grep -P, sed -z, stat -c, ...
fs          — /proc, /sys, /sys/class/dmi, ...
root        — privileges available
```

The package repository is always derived from `family` (ID_LIKE), not
from the distro name: Ubuntu and Mint both inherit `debian` → `apt`.

## 3. Detection algorithm (cascade)

1. `uname -s` → kernel;
2. `/etc/os-release` → `ID`, `VERSION_ID`;
3. `ID_LIKE` → family;
4. tool probes → userland and capabilities;
5. environment checks (`[[ -d /proc ]]`, `id -u`) → final bits.

Each step is independent of the previous ones: tool probes always run,
they determine the userland by themselves.

## 4. Feature detection and probe chains

Probe a capability, not a name. The reference is `bs_build::sha256`:

```bash
sha_cmd="$(platform::probe "sha256sum" "shasum -a 256" "cksum")"
```

GNU-only tools and their fallbacks:

| Tool | GNU (Linux) | BSD (macOS/FreeBSD) | Fallback chain |
|---|---|---|---|
| Hash | `sha256sum` | `shasum -a 256` | `sha256sum → shasum → cksum` |
| PCRE | `grep -P` | — | `grep -P` → ERE (`grep -E`) |
| Multiline sed | `sed -z` | — | `sed -z` → `perl -0` |
| File size | `stat -c %s` | `stat -f %z` | behavior probe |
| Nanoseconds | `date +%N` | — | `date +%N` → `date +%s` + 000 |
| readlink | `readlink -f` | not on macOS | `readlink -f` → `realpath` → loop |

## 5. Versioning strategies

**Recommended**: a single repository + capability gates + compatibility
layers (`lib/platform/compat/*`). Separate per-platform repositories are
justified only for globally different runtimes.

Compatibility tiers (for the version and `bs doctor`):

- `core` — pure Bash 4+, no GNU tools: works everywhere;
- `gnu-linux` — GNU userland (`grep -P`, `sed -z`, `sha256sum`);
- `posix` — POSIX-only tools (fallback mode);
- `bsd` — macOS/FreeBSD compatibility layers.

A script checks the required tier at startup and fails with a clear
message if the capability is missing (instead of a cryptic crash from
`sed -z`).

## 6. Distributions and package repositories

| ID | Family | Repository |
|---|---|---|
| ubuntu / debian / mint | debian | apt |
| fedora / almalinux / rhel | fedora | dnf/yum |
| alpine | alpine | apk |
| arch | arch | pacman |
| opensuse | suse | zypper |
| macOS | — | brew |
| FreeBSD | — | pkg |

**Plan (future)**: publishing BS as apt/dnf/brew packages is a separate
infrastructure (signing, repositories, formulae); for now `install.sh`
and `bs build` are enough. The structure of `lib/platform/repo.sh`
(family → install command map) is being laid out now.

## 7. Minimum supported platform (contract)

Fix the support matrix explicitly (checked by `bs doctor`):

| Tier | Requirements |
|---|---|
| `core` | Bash 4.0+, POSIX tools, Linux-like FS |
| `gnu-linux` | tier core + GNU userland (grep -P, sed -z, sha256sum) |
| `bsd` | tier core + Bash 4+ from packages (system Bash on macOS is 3.2!) |

Note: the system Bash on macOS is 3.2 (GPLv2 license), so macOS support
implies Bash from Homebrew. macOS is currently out of priority.

## 8. Test hooks for platform-dependent paths

Platform data cannot be read directly in tests, so every module with
`/sys` dependencies gets **path-override hooks** (environment variables
with defaults):

```bash
: "${HW_DMI_PATH:=/sys/class/dmi/id}"     # lib/system/hw
: "${SSH_MOCK:=}"                          # lib/network/ssh — mock binary
: "${LLM_MOCK_RESPONSE:=}"                 # lib/integration/llm — mock response
: "${MATH_CACHE_DIR:=...}"                 # lib/math — isolated cache
```

Pattern: `: "${VAR:=real_path}"` at module load + the test overrides the
variable and calls `module::reset` (if any) or reloads the module. This
tests logic without real hardware and without root privileges.

## 9. Facts cache

Collecting the capability vector is fast (milliseconds), but noticeable
across hundreds of scripts in CI. Facts are cached in
`${XDG_CACHE_HOME:-$HOME/.cache}/bs/facts` and rebuilt when the
environment changes (hash of key files: uname, os-release).

## 10. Summary

1. Detection: cascade `uname → os-release → ID_LIKE → probes`.
2. Implementation choice: probe chains, never `uname` branching.
3. Versioning: single repo, capability gates, tiers core/gnu-linux/bsd.
4. Tests: path-override hooks, isolated caches.
5. Contract: the support matrix is verified by `bs doctor`.