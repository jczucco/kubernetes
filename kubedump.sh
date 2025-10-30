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

# log function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] - ${1}: ${2}"
}

CONTEXT="${1:-}"
readonly BACKUP_DIR="/KUBERNETES_BACKUP/DUMP"
readonly RETENTION_DAYS=30
# A list of resource types that should generally be excluded from backups.
readonly EXCLUDED_RESOURCES="events|bindings|componentstatuses|localsubjectaccessreviews.authorization.k8s.io"

if [ ! -d "${BACKUP_DIR}" ]; then
  echo "Directory '$DIRECTORY' does not exist."
  exit 2
fi

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

readonly TIMESTAMP=$(date +%Y%m%d-%H%M%S)
tar cfz ${BACKUP_DIR}/kubernetes_dump_${TIMESTAMP}.tar.gz ${BACKUP_DIR}/${CONTEXT}
find ${BACKUP_DIR} -type d -exec chmod 0700 {} \;
find ${BACKUP_DIR} -type f -exec chmod 0600 {} \;
log "INFO" "$(ls -l ${BACKUP_DIR}/kubernetes_dump_${TIMESTAMP}.tar.gz)"

# ROTATING
log "INFO" "Removing backups older than ${RETENTION_DAYS} days..."
find ${BACKUP_DIR} -name kubernetes_dump_*.tar.gz -type f -mtime +"${RETENTION_DAYS}" -print -delete
echo
