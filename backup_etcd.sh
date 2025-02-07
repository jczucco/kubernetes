#!/bin/bash
# backup kubernetes etcd database
#
# by jczucco@gmail.com

set -euo pipefail

export BACKUP_DIR="/KUBERNETES_BACKUP"
export ETCDCTL="${BACKUP_DIR}/etcdctl"
export ETCDUTL="${BACKUP_DIR}/etcdutl"
export ETCD_ENDPOINT="https://127.0.0.1:2379"

# Check for required commands
for cmd in ${ETCDCTL} ${ETCDUTL} gzip; do
  if ! command -v $cmd &> /dev/null; then
    echo "Error: $cmd is not installed." >&2
    exit 1
  fi
done

# Trap to handle script interruptions
trap 'echo "Script interrupted."; exit 1' INT TERM

# List etcd members
echo
echo "LISTING ETCD MEMBERS:"
ETCDCTL_API=3 ${ETCDCTL} --endpoints=${ETCD_ENDPOINT} --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key member list

mkdir -p "${BACKUP_DIR}/ETCD"

# BACKUP ETCD:  
echo
echo "ETCD BACKUP in ${BACKUP_DIR}/ETCD/snapshot_$(date +%Y%m%d).db" 
ETCDCTL_API=3 ${ETCDCTL} --endpoints=${ETCD_ENDPOINT} --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key snapshot save ${BACKUP_DIR}/ETCD/snapshot_$(date +%Y%m%d).db 

echo
echo "CHECKING ETCD BACKUP:"
ls -l ${BACKUP_DIR}/ETCD/snapshot_$(date +%Y%m%d).db
echo
ETCDCTL_API=3 ${ETCDUTL} --write-out=table snapshot status ${BACKUP_DIR}/ETCD/snapshot_$(date +%Y%m%d).db

echo
echo "COMPACTING ETCD BACKUP:"
gzip -v ${BACKUP_DIR}/ETCD/snapshot_$(date +%Y%m%d).db
