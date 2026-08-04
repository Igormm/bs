[↑ Оглавление](../README.md)

# Модуль `k8s`

`lib/integration/k8s.sh` — обёртка над `kubectl` с поддержкой dry-run, авто-добавлением namespace и структурированными JSON-результатами для Go-backend и CI.

Исходник: [lib/integration/k8s.sh](../../../lib/integration/k8s.sh)

## Загрузка

```bash
#!/usr/bin/env bs

load "lib/integration/k8s"
```

## API

### `k8s::is_available`

Проверить, установлен ли `kubectl`.

```bash
if k8s::is_available; then
  echo "kubectl ready"
fi
```

### `k8s::run <kubectl args...>`

Выполнить произвольную команду `kubectl` с автоматическим добавлением `--namespace`.

```bash
k8s::run get nodes
```

### `k8s::context::current`

Текущий контекст.

### `k8s::context::list`

Список контекстов.

### `k8s::context::use <context>`

Переключить контекст.

### `k8s::namespace::current`

Текущее пространство имён.

### `k8s::pod::list [namespace]`

Список подов.

```bash
k8s::pod::list
k8s::pod::list kube-system
```

### `k8s::pod::logs <pod> [namespace]`

Логи пода.

### `k8s::pod::exec <pod> <command> [namespace]`

Выполнить команду внутри пода.

```bash
k8s::pod::exec my-pod "ps aux"
```

### `k8s::deployment::restart <deployment> [namespace]`

Перезапустить deployment.

```bash
k8s::deployment::restart my-app
```

### `k8s::deployment::scale <deployment> <replicas> [namespace]`

Масштабировать deployment.

```bash
k8s::deployment::scale my-app 3
```

### `k8s::apply <file_or_dir> [namespace]`

Применить манифесты.

```bash
k8s::apply ./k8s/manifests.yaml
```

### `k8s::get <resource> [namespace] [extra args...]`

Получить ресурсы.

```bash
k8s::get pods
k8s::get services -o wide
```

### `k8s::result <kubectl args...>`

Вернуть стандартный JSON-контракт результата BS. Требует `lib/integration/result`.

```bash
k8s::result get pods
```

## Env-переменные

| Переменная | Назначение | Значение по умолчанию |
|---|---|---|
| `K8S_NAMESPACE` | Namespace по умолчанию | `default` |
| `FRAMEWORK_DRY_RUN=true` | Не выполнять команды, только логировать | — |

## Пример

```bash
bs run examples/k8s_example.sh
```

Исходник: [examples/k8s_example.sh](../../../examples/k8s_example.sh).

## Зависимости

- `core/const`, `core/logger`, `core/utils` — базовые модули BS.
- `kubectl` — внешний CLI Kubernetes.
- `lib/integration/result` — опционально, для `k8s::result`.
