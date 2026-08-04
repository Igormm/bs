[↑ Table of Contents](../README.md)

# Module `k8s`

`lib/integration/k8s.sh` — a thin wrapper around `kubectl` with dry-run support, automatic namespace injection, and structured JSON results for Go backends and CI.

Source: [lib/integration/k8s.sh](../../../lib/integration/k8s.sh)

## Loading

```bash
#!/usr/bin/env bs

load "lib/integration/k8s"
```

## API

### `k8s::is_available`

Check if `kubectl` is installed.

```bash
if k8s::is_available; then
  echo "kubectl ready"
fi
```

### `k8s::run <kubectl args...>`

Run an arbitrary `kubectl` command, automatically adding `--namespace`.

```bash
k8s::run get nodes
```

### `k8s::context::current`

Current context.

### `k8s::context::list`

List contexts.

### `k8s::context::use <context>`

Switch context.

### `k8s::namespace::current`

Current namespace.

### `k8s::pod::list [namespace]`

List pods.

```bash
k8s::pod::list
k8s::pod::list kube-system
```

### `k8s::pod::logs <pod> [namespace]`

Get pod logs.

### `k8s::pod::exec <pod> <command> [namespace]`

Run a command inside a pod.

```bash
k8s::pod::exec my-pod "ps aux"
```

### `k8s::deployment::restart <deployment> [namespace]`

Restart a deployment.

```bash
k8s::deployment::restart my-app
```

### `k8s::deployment::scale <deployment> <replicas> [namespace]`

Scale a deployment.

```bash
k8s::deployment::scale my-app 3
```

### `k8s::apply <file_or_dir> [namespace]`

Apply manifests.

```bash
k8s::apply ./k8s/manifests.yaml
```

### `k8s::get <resource> [namespace] [extra args...]`

Get resources.

```bash
k8s::get pods
k8s::get services -o wide
```

### `k8s::result <kubectl args...>`

Return the standard BS JSON result contract. Requires `lib/integration/result`.

```bash
k8s::result get pods
```

## Environment variables

| Variable | Purpose | Default |
|---|---|---|
| `K8S_NAMESPACE` | Default namespace | `default` |
| `FRAMEWORK_DRY_RUN=true` | Do not execute commands, only log | — |

## Example

```bash
bs run examples/k8s_example.sh
```

Source: [examples/k8s_example.sh](../../../examples/k8s_example.sh).

## Dependencies

- `core/const`, `core/logger`, `core/utils` — BS core modules.
- `kubectl` — external Kubernetes CLI.
- `lib/integration/result` — optional, for `k8s::result`.
