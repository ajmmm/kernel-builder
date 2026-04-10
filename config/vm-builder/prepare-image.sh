#!/usr/bin/env bash
set -euo pipefail

INPUT_QCOW2="${1:?input qcow2 path required}"
OUTPUT_HDS="${2:?output parallels payload path required}"
DISK_GB="${3:?disk size in GB required}"
BOOT_GB="${4:?boot size in GB required}"
BOOT_PART="${5:?boot partition device required}"
ROOT_PART="${6:?root partition device required}"

TMP_QCOW2="${OUTPUT_HDS}.qcow2.tmp"
TMP_HDS="${OUTPUT_HDS}.tmp"

export LIBGUESTFS_BACKEND=direct

dnf install -y qemu-img libguestfs-tools parted gdisk e2fsprogs xfsprogs

rm -f "${TMP_QCOW2}" "${TMP_HDS}" "${OUTPUT_HDS}"
qemu-img create -f qcow2 "${TMP_QCOW2}" "${DISK_GB}G"
virt-resize \
  --resize "${BOOT_PART}=${BOOT_GB}G" \
  --expand "${ROOT_PART}" \
  "${INPUT_QCOW2}" \
  "${TMP_QCOW2}"

qemu-img convert -f qcow2 -O parallels "${TMP_QCOW2}" "${TMP_HDS}"
mv "${TMP_HDS}" "${OUTPUT_HDS}"
rm -f "${TMP_QCOW2}"

dnf clean all
rm -rf /var/cache/dnf /var/tmp/* /tmp/*
