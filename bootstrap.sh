#!/usr/bin/env bash

set -Eeuo pipefail

readonly PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LAB_DIR="/mnt/raid-lab"

if (( EUID == 0 )); then
    SUDO=()
else
    SUDO=(sudo)
fi

loop_for_file() {
    local image_path="$1"
    local loop_device

    loop_device=$(losetup -j "$image_path" -n -O NAME | head -n 1)
    if [[ -z "$loop_device" ]]; then
        loop_device=$("${SUDO[@]}" losetup -fP --show "$image_path")
    fi
    printf '%s\n' "$loop_device"
}

export DEBIAN_FRONTEND=noninteractive
"${SUDO[@]}" apt-get update
"${SUDO[@]}" apt-get install -y docker.io docker-compose-v2 docker-buildx mdadm lvm2
"${SUDO[@]}" systemctl enable --now docker

"${SUDO[@]}" mkdir -p "$LAB_DIR" /mnt/raid /mnt/logs
for disk in disk1.img disk2.img disk3.img; do
    if [[ ! -f "$LAB_DIR/$disk" ]]; then
        "${SUDO[@]}" dd if=/dev/zero of="$LAB_DIR/$disk" bs=1M count=512 status=progress
    fi
done

LOOP1=$(loop_for_file "$LAB_DIR/disk1.img")
LOOP2=$(loop_for_file "$LAB_DIR/disk2.img")
LOOP3=$(loop_for_file "$LAB_DIR/disk3.img")

if ! "${SUDO[@]}" mdadm --detail /dev/md0 >/dev/null 2>&1; then
    if "${SUDO[@]}" mdadm --examine "$LOOP1" >/dev/null 2>&1 \
        && "${SUDO[@]}" mdadm --examine "$LOOP2" >/dev/null 2>&1; then
        "${SUDO[@]}" mdadm --assemble /dev/md0 "$LOOP1" "$LOOP2"
    else
        printf 'y\n' | "${SUDO[@]}" mdadm --create /dev/md0 --level=1 --raid-devices=2 "$LOOP1" "$LOOP2"
    fi
fi
if ! "${SUDO[@]}" blkid /dev/md0 | grep -q 'TYPE="ext4"'; then
    "${SUDO[@]}" mkfs.ext4 -F /dev/md0
fi
if ! mountpoint -q /mnt/raid; then
    "${SUDO[@]}" mount /dev/md0 /mnt/raid
fi

"${SUDO[@]}" pvscan --cache "$LOOP3" >/dev/null
if ! "${SUDO[@]}" pvs --noheadings -o pv_name 2>/dev/null | grep -qx " *$LOOP3"; then
    printf 'y\n' | "${SUDO[@]}" pvcreate "$LOOP3"
fi
if ! "${SUDO[@]}" vgs vg_data >/dev/null 2>&1; then
    "${SUDO[@]}" vgcreate vg_data "$LOOP3"
else
    "${SUDO[@]}" vgchange -ay vg_data >/dev/null
fi
if ! "${SUDO[@]}" lvs /dev/vg_data/lv_logs >/dev/null 2>&1; then
    printf 'y\n' | "${SUDO[@]}" lvcreate -L 200M -n lv_logs vg_data
fi
if ! "${SUDO[@]}" blkid /dev/vg_data/lv_logs | grep -q 'TYPE="ext4"'; then
    "${SUDO[@]}" mkfs.ext4 -F /dev/vg_data/lv_logs
fi
if ! mountpoint -q /mnt/logs; then
    "${SUDO[@]}" mount /dev/vg_data/lv_logs /mnt/logs
fi

cd "$PROJECT_DIR"
"${SUDO[@]}" docker compose up -d --build

printf '\nПроверка хранилища:\n'
cat /proc/mdstat
"${SUDO[@]}" pvs
"${SUDO[@]}" vgs
"${SUDO[@]}" lvs
df -h /mnt/raid /mnt/logs