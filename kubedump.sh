#!/usr/bin/env bash
# Kubernetes backup dump in YAML format
# Based on https://gist.github.com/negz/c3ee465b48306593f16c523a22015bec
# improved by copilot
#
# by jczucco@gmail.com

set -euo pipefail

# Check for required commands
for cmd in kubectl jq ; do
  if ! command -v $cmd &> /dev/null; then
    echo "Error: $cmd is not installed." >&2
    exit 1
  fi
done

CONTEXT="${1:-}"
BACKUP_DIR="/KUBERNETES_BACKUP/DUMP"
# A list of resource types that should generally be excluded from backups.
readonly EXCLUDED_RESOURCES="events|bindings|componentstatuses|localsubjectaccessreviews.authorization.k8s.io"

# If context is not provided, use the current context
if [[ -z "$CONTEXT" ]]; then
  CONTEXT=$(kubectl config current-context)
fi

# Get all namespaces
NAMESPACES=$(kubectl get ns -o jsonpath="{.items[*].metadata.name}")

# Get all namespaced resources
RESOURCES=$(kubectl api-resources --namespaced --verbs=list -o name | egrep -v ^"${EXCLUDED_RESOURCES}"$ | tr "\n" " ")

# Trap to handle script interruptions
trap 'echo "Script interrupted."; exit 1' INT TERM

# Backup each resource in each namespace
for ns in $NAMESPACES; do
  for resource in $RESOURCES; do
    rsrcs=$(kubectl --context "$CONTEXT" -n "$ns" get -o json "$resource" | jq -r '.items[].metadata.name')
    for r in $rsrcs; do
      dir="${BACKUP_DIR}/${CONTEXT}/${ns}/${resource}"
      mkdir -p "$dir"
      kubectl --context "$CONTEXT" -n "$ns" get -o yaml "$resource" "$r" > "${dir}/${r}.yaml"
    done
  done
done

NON_NAMESPACED_RESOURCES=$(kubectl api-resources --namespaced=false --verbs=list -o name | egrep -v "${EXCLUDED_RESOURCES}" | tr "\n" " ")
mkdir -p "${BACKUP_DIR}/${CONTEXT}/NON_NAMESPACED_RESOURCES"
> "${BACKUP_DIR}/${CONTEXT}/NON_NAMESPACED_RESOURCES/NON_NAMESPACED_RESOURCES.yaml"
for resource in $RESOURCES; do
    kubectl --context "$CONTEXT" get -o yaml "$resource" >> "${BACKUP_DIR}/${CONTEXT}/NON_NAMESPACED_RESOURCES/NON_NAMESPACED_RESOURCES.yaml"
    echo >> "${BACKUP_DIR}/${CONTEXT}/NON_NAMESPACED_RESOURCES/NON_NAMESPACED_RESOURCES.yaml"
    echo "---" >> "${BACKUP_DIR}/${CONTEXT}/NON_NAMESPACED_RESOURCES/NON_NAMESPACED_RESOURCES.yaml"
done

