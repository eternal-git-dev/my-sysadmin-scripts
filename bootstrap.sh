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
"${SUDO[@]}" apt-get install -y docker.io docker-compose-v2 docker-buildx nginx openssl mdadm lvm2 curl
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
"${SUDO[@]}" systemctl stop my-app 2>/dev/null || true
"${SUDO[@]}" docker rm -f my-app >/dev/null 2>&1 || true
"${SUDO[@]}" docker compose build
"${SUDO[@]}" docker compose up -d --force-recreate

if ! "${SUDO[@]}" test -f /etc/ssl/private/my-app.key \
    || ! "${SUDO[@]}" test -f /etc/ssl/certs/my-app.crt; then
    "${SUDO[@]}" openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/my-app.key \
        -out /etc/ssl/certs/my-app.crt \
        -subj "/CN=my-app.local"
fi

"${SUDO[@]}" install -m 0644 deploy/nginx-my-app.conf /etc/nginx/sites-available/my-app
"${SUDO[@]}" ln -sfn /etc/nginx/sites-available/my-app /etc/nginx/sites-enabled/my-app
"${SUDO[@]}" rm -f /etc/nginx/sites-enabled/default
"${SUDO[@]}" nginx -t
"${SUDO[@]}" systemctl enable --now nginx
"${SUDO[@]}" systemctl reload nginx

"${SUDO[@]}" install -m 0644 deploy/my-app.service /etc/systemd/system/my-app.service
"${SUDO[@]}" systemctl daemon-reload
"${SUDO[@]}" systemctl enable my-app
"${SUDO[@]}" docker stop my-app >/dev/null
"${SUDO[@]}" systemctl restart my-app
sleep 6

curl --fail --silent --show-error http://127.0.0.1:8080/monitor.log >/dev/null
curl --fail --insecure --silent --show-error https://127.0.0.1/monitor.log >/dev/null

printf '\nГотово. Проверка хранилища:\n'
cat /proc/mdstat
"${SUDO[@]}" pvs
"${SUDO[@]}" vgs
"${SUDO[@]}" lvs
df -h /mnt/raid /mnt/logs

printf '\nПроверка сервиса:\n'
"${SUDO[@]}" nginx -t
curl -kI https://127.0.0.1/monitor.log
"${SUDO[@]}" systemctl --no-pager --full status my-app
