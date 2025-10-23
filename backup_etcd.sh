#!/bin/bash
# ==============================================================================
# Script para backup do banco de dados etcd do Kubernetes
#
# Features:
# - Timestamp completo para evitar sobrescrita.
# - Rotação automática de backups antigos.
# - Permissões de arquivo seguras.
# - Código centralizado e fácil de configurar.
# - Verificações de robustez.
# - Clear boundary between etcdctl and etcdutl https://etcd.io/blog/2025/announcing-etcd-3.6/#clear-boundary-between-etcdctl-and-etcdutl
# - ETCDCTL_API=3 is not necessary anymore since etcdctl > 3.4
# - Tested with etcdctl and etcdutl 3.6.4 API 3.6
#
# by jczucco@gmail.com (versão aprimorada)
# ==============================================================================

set -euo pipefail

# --- CONFIG ---
# Main directory for all backups
readonly BACKUP_BASE_DIR="/root/BACKUP"
# Subdirectory for etcd backups
readonly ETCD_BACKUP_DIR="${BACKUP_BASE_DIR}/ETCD"
# etcdctl path
readonly ETCDCTL_BIN="${BACKUP_BASE_DIR}/etcdctl"
# etcdutl path
readonly ETCDUTL_BIN="${BACKUP_BASE_DIR}/etcdutl"
# etcd endpoint url
readonly ETCD_ENDPOINT="https://127.0.0.1:2379"
# backup retention in days
readonly RETENTION_DAYS=30

# --- CERTIFICATE PATHS ---
readonly ETCD_CACERT="/etc/kubernetes/pki/etcd/ca.crt"
readonly ETCD_CERT="/etc/kubernetes/pki/etcd/server.crt"
readonly ETCD_KEY="/etc/kubernetes/pki/etcd/server.key"

# --- END CONFIG ---

# log function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] - ${1}: ${2}"
}

# Trap to handle interrupts and exit cleanly
trap 'log "ERROR" "Script interrupted improperly."; exit 1' INT TERM

# 1. INITIAL CHECKS
log "INFO" "Starting the etcd backup process."

for cmd in ${ETCDCTL_BIN} $(type -p gzip) $(type -p find) ; do
  if ! command -v $cmd &> /dev/null; then
    log "ERROR" "Mandatory command '$cmd' not found. Aborting." >&2
    exit 1
  fi
done

if [[ ! -d "${ETCD_BACKUP_DIR}" ]]; then
  log "INFO" "Backup directory ${ETCD_BACKUP_DIR} not found. Creating..."
  mkdir -p "${ETCD_BACKUP_DIR}"
fi

# 2. VARIABLES AND OPTIONS
readonly TIMESTAMP=$(date +%Y%m%d-%H%M%S)
readonly SNAPSHOT_FILE="${ETCD_BACKUP_DIR}/snapshot_${TIMESTAMP}.db"

readonly ETCDCTL_OPTS=(
  "--endpoints=${ETCD_ENDPOINT}"
  "--cacert=${ETCD_CACERT}"
  "--cert=${ETCD_CERT}"
  "--key=${ETCD_KEY}"
)

# 3. BACKUP EXECUTION
log "INFO" "Listing etcd cluster members..."
${ETCDCTL_BIN} "${ETCDCTL_OPTS[@]}" member list
echo

log "INFO" "Creating etcd snapshot in ${SNAPSHOT_FILE}"
${ETCDCTL_BIN} "${ETCDCTL_OPTS[@]}" snapshot save "${SNAPSHOT_FILE}"

# 4. CHECKS
log "INFO" "Check snapshot integrity..."
${ETCDUTL_BIN} snapshot status "${SNAPSHOT_FILE}" --write-out=table
echo

log "INFO" "Setting secure permissions for the backup file (600)."
chmod 600 "${SNAPSHOT_FILE}"
ls -lh "${SNAPSHOT_FILE}"
echo

# 5. Compressing
log "INFO" "Compressing the snapshot file..."
gzip -v9 "${SNAPSHOT_FILE}"
echo

# 6. ROTATING
log "INFO" "Removing backups older than ${RETENTION_DAYS} days..."
find "${ETCD_BACKUP_DIR}" -name "snapshot_*.db.gz" -type f -mtime +"${RETENTION_DAYS}" -print -delete
echo

log "SUCCESS" "etcd backup and cleanup completed successfully!"
