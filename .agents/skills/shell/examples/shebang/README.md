# Shebang examples

Runnable good/bad pairs for [`reference/shebang.md`](../../reference/shebang.md).
Each `*.good.sh` runs to exit 0 (the behavioural suite invokes it as
`bash <file>`, which ignores the shebang — so these examples teach the shebang
*line*, verified by the linter, not by execution). Each `*.bad.sh` is safe and
declares the ShellCheck code it triggers, or `none` for a portability pitfall the
linter cannot catch.

| Pair | Good shows | Bad shows | Code |
|------|-----------|-----------|------|
| `01-env-vs-binbash` | `#!/usr/bin/env bash` finds modern bash | `#!/bin/bash` (3.2 on macOS, absent on NixOS) | none |
| `02-env-flags` | `#!/usr/bin/env -S bash -euo pipefail` | flags without `-S` (kernel one-arg rule) | `SC2096` |
| `03-absolute-interpreter` | absolute path via `env` | `#!bin/bash` relative path | `SC2239` |
