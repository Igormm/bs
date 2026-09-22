[↑ Table of Contents](../README.md)

# Module `io::tree`

Create a project file tree from a **yaml / yml / txt / ini / csv** spec.
One canonical model: directories and files with optional content. Paths are
relative, `..` and absolute paths are rejected.

Source: [lib/io/tree.sh](../../../lib/io/tree.sh)

## Loading

```bash
#!/usr/bin/env bs

load "lib/io/tree"
```

## One-liner

```bash
io::tree::create spec.yaml ./my-app
io::tree::create --force --format txt paths.txt /tmp/app
io::tree::create --dry-run tree.ini ./preview
```

Flags: `--force` (overwrite files), `--dry-run` (plan only),
`--format yaml|yml|txt|ini|csv` (override extension / sniff).

## Formats

### YAML / YML (restricted mapping tree)

Pure bash. No `yq` required. Nested maps are directories, scalars are files,
`|` is a block scalar. Keys ending with `/` are empty directories.

```yaml
src:
  hello.sh: "#!/usr/bin/env bs"
  lib/:
README.md: |
  # title
  body
```

Not supported: anchors, tags, merge keys, flow sequences as trees.

### TXT

Path list (one path per line, trailing `/` = directory) or an indent tree
(2 spaces / `tree(1)` box drawing). `#` comments.

```
src/
  lib/
    util.sh
README.md
```

### INI

Section = directory. `key = content` = file. Empty section still creates
the directory. `[.]` or `[root]` is the destination root.

```ini
[src]
hello.sh = #!/usr/bin/env bs

[docs]
```

### CSV

Columns: `path`, `kind` (`file`/`dir`/`f`/`d`), optional `content`.
Header row is optional. Quoted fields via [lib/rfc/csv.sh](../../../lib/rfc/csv.sh).

```csv
path,kind,content
src,dir,
src/app.sh,file,"hello"
```

## API

| Function | Role |
| --- | --- |
| `io::tree::detect path` | stdout: `yaml`/`yml`/`txt`/`ini`/`csv` |
| `io::tree::parse path [format]` | fill `IO_TREE_*` arrays |
| `io::tree::parse_text text format` | same from a string |
| `io::tree::dump` | stdout `kind<TAB>path` |
| `io::tree::plan dest` | stdout `MKDIR`/`WRITE`/`SKIP`/`KEEP` |
| `io::tree::apply dest [force]` | create on disk |
| `io::tree::create [flags] spec dest` | parse + apply |
| `io::tree::reset` | clear arrays |

Existing files are skipped unless `force=1` / `--force`.
`FRAMEWORK_DRY_RUN=true` or `IO_TREE_DRY_RUN=1` skips writes.
Directories use `io::files::ensure_dir`.

## Safety

- Relative paths only.
- `.` and `..` path components are errors (`E_INVALID`).
- File vs directory conflicts return `LIB_ERROR_CONFLICT`.

Example: [examples/tree_example.sh](../../../examples/tree_example.sh).
