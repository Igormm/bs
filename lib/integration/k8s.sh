#!/usr/bin/env bash
#
# lib/integration/k8s.sh — Kubernetes client for BS
# lib/integration/k8s.sh — Kubernetes-клиент для BS
#
# Thin wrapper around kubectl with dry-run support, namespace defaults,
# and structured JSON results for Go backends and CI.
#
# Usage / Использование:
#   load "lib/integration/k8s"
#
#   k8s::is_available
#   k8s::pod::list
#   k8s::deployment::restart my-app
#   k8s::apply ./manifests
#   k8s::result get pods
#
# @depends core/const, core/logger, core/utils, lib/integration/result
# @optdeps kubectl

# Source Guard / Защита от повторной загрузки
source "$(dirname -- "${BASH_SOURCE[0]}")/../../core/prereq.sh"
bs::guard "IO_INTEGRATION_K8S" || return 0

# Зависимости / Dependencies
bs::source_relative "../../core/const.sh" "../../core/logger.sh" "../../core/utils.sh" "result.sh"

# Module version / Версия модуля
declare -g IO_INTEGRATION_K8S_VERSION="1.0.0"

# Default namespace / Пространство имён по умолчанию
: "${K8S_NAMESPACE:=default}"

# ==========================================
# Private helpers / Приватные вспомогательные функции
# ==========================================

# @private
# @description Build kubectl arguments with namespace and dry-run.
# @description Собрать аргументы kubectl с namespace и dry-run.
# @param $@ original kubectl arguments
# @stdout final kubectl arguments
__k8s::kubectl_args() {
  local -a args=("$@")

  if ! __k8s::arg_present "--namespace" "${args[@]}" && ! __k8s::arg_present "-n" "${args[@]}"; then
    args+=("--namespace" "${K8S_NAMESPACE}")
  fi

  printf '%s\n' "${args[@]}"
}

# @private
# @description Check if an argument flag is already present.
# @description Проверить, присутствует ли уже флаг.
# @param $1 flag name to look for
# @param $@ arguments to search
__k8s::arg_present() {
  local target="${1:-}"
  shift

  local arg
  for arg in "$@"; do
    if [[ "${arg}" == "${target}" ]]; then
      return 0
    fi
  done
  return 1
}

# @private
# @description Execute kubectl command with logging and dry-run support.
# @description Выполнить команду kubectl с логом и dry-run.
# @param $@ kubectl arguments
# @return exit code from kubectl
__k8s::kubectl() {
  local -a args=()
  while IFS= read -r line; do
    args+=("${line}")
  done < <(__k8s::kubectl_args "$@")

  if [[ "${FRAMEWORK_DRY_RUN:-false}" == "true" ]]; then
    log::warn "[DRY-RUN] kubectl ${args[*]}"
    return 0
  fi

  if ! utils::has kubectl; then
    log::error "kubectl is not installed"
    return "${INTEGRATION_ERROR_MISSING_DEPS}"
  fi

  log::debug "kubectl ${args[*]}"
  kubectl "${args[@]}"
}

# ==========================================
# Public API / Публичный API
# ==========================================

# @description Check if kubectl is available.
# @description Проверить, доступен ли kubectl.
# @return 0 if available, 1 otherwise
k8s::is_available() {
  utils::has kubectl
}

# @description Run an arbitrary kubectl command.
# @description Выполнить произвольную команду kubectl.
# @param $@ kubectl arguments
# @return exit code from kubectl
k8s::run() {
  __k8s::kubectl "$@"
}

# Context management / Управление контекстами

# @description Get current kubectl context.
# @description Получить текущий контекст kubectl.
# @stdout context name
k8s::context::current() {
  k8s::run config current-context
}

# @description List all kubectl contexts.
# @description Список всех контекстов kubectl.
# @stdout context names
k8s::context::list() {
  k8s::run config get-contexts -o name
}

# @description Switch kubectl context.
# @description Переключить контекст kubectl.
# @param $1 context name
k8s::context::use() {
  local context="${1:-}"

  if [[ -z "${context}" ]]; then
    log::warn "k8s::context::use: context name required"
    return "${E_INVALID}"
  fi

  k8s::run config use-context "${context}"
}

# Namespace helpers / Работа с namespace

# @description Get current namespace.
# @description Получить текущее пространство имён.
# @stdout namespace name
k8s::namespace::current() {
  k8s::run config view --minify --output 'jsonpath={..namespace}' 2>/dev/null || printf '%s' "${K8S_NAMESPACE}"
}

# Pod helpers / Работа с подами

# @description List pods in a namespace.
# @description Список подов в пространстве имён.
# @param [$1=K8S_NAMESPACE] namespace
k8s::pod::list() {
  local namespace="${1:-${K8S_NAMESPACE}}"
  k8s::run get pods --namespace "${namespace}"
}

# @description Get logs from a pod.
# @description Получить логи пода.
# @param $1 pod name
# @param [$2=K8S_NAMESPACE] namespace
k8s::pod::logs() {
  local pod="${1:-}"
  local namespace="${2:-${K8S_NAMESPACE}}"

  if [[ -z "${pod}" ]]; then
    log::warn "k8s::pod::logs: pod name required"
    return "${E_INVALID}"
  fi

  k8s::run logs "${pod}" --namespace "${namespace}"
}

# @description Execute a command in a pod.
# @description Выполнить команду внутри пода.
# @param $1 pod name
# @param $2 command
# @param [$3=K8S_NAMESPACE] namespace
k8s::pod::exec() {
  local pod="${1:-}"
  local cmd="${2:-}"
  local namespace="${3:-${K8S_NAMESPACE}}"

  if [[ -z "${pod}" || -z "${cmd}" ]]; then
    log::warn "k8s::pod::exec: pod and command required"
    return "${E_INVALID}"
  fi

  k8s::run exec "${pod}" --namespace "${namespace}" -- /bin/sh -c "${cmd}"
}

# Deployment helpers / Работа с deployment

# @description Restart a deployment.
# @description Перезапустить deployment.
# @param $1 deployment name
# @param [$2=K8S_NAMESPACE] namespace
k8s::deployment::restart() {
  local deployment="${1:-}"
  local namespace="${2:-${K8S_NAMESPACE}}"

  if [[ -z "${deployment}" ]]; then
    log::warn "k8s::deployment::restart: deployment name required"
    return "${E_INVALID}"
  fi

  k8s::run rollout restart deployment "${deployment}" --namespace "${namespace}"
}

# @description Scale a deployment.
# @description Масштабировать deployment.
# @param $1 deployment name
# @param $2 number of replicas
# @param [$3=K8S_NAMESPACE] namespace
k8s::deployment::scale() {
  local deployment="${1:-}"
  local replicas="${2:-}"
  local namespace="${3:-${K8S_NAMESPACE}}"

  if [[ -z "${deployment}" || -z "${replicas}" ]]; then
    log::warn "k8s::deployment::scale: deployment and replicas required"
    return "${E_INVALID}"
  fi

  k8s::run scale deployment "${deployment}" --replicas "${replicas}" --namespace "${namespace}"
}

# Apply and get / Применение и получение ресурсов

# @description Apply Kubernetes manifests.
# @description Применить манифесты Kubernetes.
# @param $1 file or directory
# @param [$2=K8S_NAMESPACE] namespace
k8s::apply() {
  local target="${1:-}"
  local namespace="${2:-${K8S_NAMESPACE}}"

  if [[ -z "${target}" ]]; then
    log::warn "k8s::apply: file or directory required"
    return "${E_INVALID}"
  fi

  if [[ ! -e "${target}" ]]; then
    log::error "Manifest not found: ${target}"
    return "${LIB_ERROR_FILE_NOT_FOUND}"
  fi

  k8s::run apply -f "${target}" --namespace "${namespace}"
}

# @description Get Kubernetes resources.
# @description Получить ресурсы Kubernetes.
# @param $1 resource type
# @param [$2=K8S_NAMESPACE] namespace
# @param [$3...] extra kubectl args
k8s::get() {
  local resource="${1:-}"

  if [[ -z "${resource}" ]]; then
    log::warn "k8s::get: resource type required"
    return "${E_INVALID}"
  fi

  shift
  k8s::run get "${resource}" "$@"
}

# Result wrapper / Обёртка результата

# @description Run a kubectl command and emit a structured JSON result.
# @description Выполнить kubectl и вернуть JSON-результат.
# @param $@ kubectl arguments
# @stdout JSON result object
# @return exit code
k8s::result() {
  if ! load "lib/integration/result" 2>/dev/null; then
    log::error "k8s::result requires lib/integration/result"
    return "${INTEGRATION_ERROR_MISSING_DEPS}"
  fi

  result::run -- kubectl "$@"
}
