[↑ Table of Contents](../README.md)

# Module `io::files`

File System Helper (FSH) — high-level file operations with unified dry-run,
logging, and error handling.

Source: [lib/io/files.sh](../../../lib/io/files.sh)

## Loading

```bash
#!/usr/bin/env bs

load "lib/io/files"
```

Or manually:

```bash
source bootstrap/init.sh
load "lib/io/files"
```

## Inspection

```bash
io::files::exists  "/etc/passwd"
io::files::is_file "/etc/passwd"
io::files::is_dir  "/etc"
```

## Directory creation

```bash
io::files::ensure_dir "/tmp/myapp"      # mkdir -p
io::files::ensure_dir "/tmp/myapp" "755" # + chmod 755
```

## Copy

```bash
# Single file
io::files::copy_file "src.txt" "dst.txt"

# Recursive directory copy
io::files::copy_dir "project" "project_backup"

# Synchronization: with delete=true the destination becomes a mirror of the
# source. Uses rsync if available; otherwise falls back to cp + manual cleanup.
io::files::sync_dir "project" "project_backup" false  # additive sync
io::files::sync_dir "project" "project_backup" true   # mirror

# Copy matching basename patterns (include/exclude are space-separated globs)
io::files::copy_matching "project" "release" "*.sh *.md" "*.tmp *.log"

# Atomic copy with backup
# The file is first written to a temp file next to dst, then atomically renamed.
# Existing dst is preserved as dst<suffix>.
io::files::copy_file "src.txt" "dst.txt" true ".bak"
io::files::copy_dir "project" "project_backup" true ".bak"
```

## Move and remove

```bash
io::files::move "old.txt" "new.txt"   # mv --
io::files::cut  "old.txt" "new.txt"   # UI semantics for cut = move

# Move with copy+remove fallback for cross-device cases (enabled by default)
io::files::move "old.txt" "new.txt" true ".bak"

io::files::remove "file.txt"
io::files::remove "dir" true          # recursive
```

## Atomicity, backup and environment variables

The module supports safe target updates:

- **Atomic copy** — `copy_file`/`copy_dir` with `atomic=true` write to a
  temporary object next to the destination, then `mv` it into place. Observers
  always see either the old or the fully written new version.
- **Backup** — if `backup_suffix` is set (or `BS_FILES_BACKUP_SUFFIX`), the
  existing destination is renamed to `dst<suffix>` before the operation.
- **Move fallback** — when `mv` fails (e.g. cross-device), `move` with
  `atomic_fallback=true` falls back to `cp -a` + `rm -rf`.

Environment defaults:

| Variable | Purpose |
|---|---|
| `BS_FILES_ATOMIC=true\|false` | Default for atomic copy |
| `BS_FILES_ATOMIC_FALLBACK=true\|false` | Default for move fallback |
| `BS_FILES_BACKUP_SUFFIX=.suffix` | Default backup suffix |

Example with env defaults:

```bash
export BS_FILES_ATOMIC=true
export BS_FILES_BACKUP_SUFFIX=.bak
io::files::copy_file "src.txt" "dst.txt"   # atomic=true, backup=.bak
```

## Dry-run mode

When `FRAMEWORK_DRY_RUN=true` is set, all operations are only logged via
`log::warn` with a `[DRY-RUN]` prefix, no filesystem changes are made, and
functions return `0`.

```bash
export FRAMEWORK_DRY_RUN=true
io::files::copy_dir "project" "project_backup"  # only prints the command
```

## Error codes

The module uses constants from `core/const`:

- `E_INVALID` — a required argument is missing or `src == dst`.
- `LIB_ERROR_FILE_NOT_FOUND` — the source does not exist.
- `LIB_ERROR_FILE_OPERATION` — failure of `cp`/`mv`/`rm`/`find`, or source is
  not a file/directory.
- `LIB_ERROR_CONFLICT` — reserved for future overwrite options.

## Dependencies

- `core/const`, `core/logger`, `core/utils` — basic idioms and error codes.
- `lib/system/permissions` — mode handling for `ensure_dir`.
- Optional `rsync` for `sync_dir` (falls back to `cp` if unavailable).

## Examples

```bash
bs run examples/filesops_example.sh
bs run examples/filesops_atomic_example.sh
```

Sources:
- [examples/filesops_example.sh](../../../examples/filesops_example.sh) — basic operations.
- [examples/filesops_atomic_example.sh](../../../examples/filesops_atomic_example.sh) — atomic copy, backup, move fallback, env defaults and dry-run.
