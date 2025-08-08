#!/usr/bin/env bash
set -euo pipefail

# ПУТИ/ИМЕНА
NVME="/dev/nvme0n1"
EFI_PART="${NVME}p1"
LUKS_PART="${NVME}p2"
HOST="svetos"
USER="statix"

DATA_A="/dev/sda"
DATA_B="/dev/sdb"
DATA_A_PART="/dev/disk/by-partlabel/data-a"
DATA_B_PART="/dev/disk/by-partlabel/data-b"

REPO_DIR="$(dirname "$(readlink -f "$0")")"

ask() {
  read -r -p "$1 [y/N]: " ans || true
  [[ "${ans:-}" == "y" || "${ans:-}" == "Y" ]]
}

echo "ВНИМАНИЕ: будут УДАЛЕНЫ ВСЕ ДАННЫЕ на: ${NVME}, ${DATA_A}, ${DATA_B}"
ask "Продолжить?" || exit 1

echo "Проверка окружения..."
if ! command -v nixos-generate-config >/dev/null 2>&1; then
  echo "Этот скрипт нужно запускать из Live-ISO NixOS."
  exit 1
fi

# Универсальная зачистка
nuke_device() {
  local dev="$1"
  echo ">>> Затираем: $dev"

  # Снимаем монтирования
  while read -r mp; do
    [[ -n "$mp" ]] || continue
    echo "  - umount $mp"
    umount -R "$mp" 2>/dev/null || true
  done < <(lsblk -lnpo MOUNTPOINT "$dev" 2>/dev/null | awk 'NF>0')

  # Снимаем монтирования с разделов
  mapfile -t parts < <(lsblk -lnpo NAME "$dev" 2>/dev/null | tail -n +2 || true)
  for p in "${parts[@]:-}"; do
    while read -r mp; do
      [[ -n "$mp" ]] || continue
      echo "  - umount $mp"
      umount -R "$mp" 2>/dev/null || true
    done < <(lsblk -lnpo MOUNTPOINT "$p" 2>/dev/null | awk 'NF>0')
  done

  # swapoff
  while read -r swdev _; do
    [[ -n "${swdev:-}" ]] || continue
    if [[ "$swdev" == "$dev"* ]]; then
      echo "  - swapoff $swdev"
      swapoff "$swdev" 2>/dev/null || true
    fi
  done < <(grep -E "^(/dev/|/dev/mapper/)" /proc/swaps || true)

  # Закрываем любые mapper-устройства (LUKS)
  if command -v cryptsetup >/dev/null 2>&1; then
    for m in /dev/mapper/*; do
      [[ -e "$m" ]] || continue
      cryptsetup status "$m" >/dev/null 2>&1 && cryptsetup close "$m" 2>/dev/null || true
    done
  fi

  # mdadm
  if command -v mdadm >/dev/null 2>&1; then
    mdadm --stop --scan 2>/dev/null || true
    mdadm --remove --scan 2>/dev/null || true
    mdadm --zero-superblock --force "$dev" 2>/dev/null || true
    for p in "${parts[@]:-}"; do
      mdadm --zero-superblock --force "$p" 2>/dev/null || true
    done
  fi

  # LVM
  if command -v vgchange >/dev/null 2>&1; then vgchange -an 2>/dev/null || true; fi
  if command -v pvremove >/dev/null 2>&1; then
    pvremove -ff -y "$dev" 2>/dev/null || true
    for p in "${parts[@]:-}"; do
      pvremove -ff -y "$p" 2>/dev/null || true
    done
  fi

  # wipefs
  wipefs -af "$dev" 2>/dev/null || true
  for p in "${parts[@]:-}"; do
    wipefs -af "$p" 2>/dev/null || true
  done

  # ZAP GPT/MBR
  if command -v sgdisk >/dev/null 2>&1; then
    sgdisk --zap-all "$dev" 2>/dev/null || true
  fi

  # TRIM/нуление краёв
  if command -v blkdiscard >/dev/null 2>&1; then
    blkdiscard -f "$dev" 2>/dev/null || true
  fi

  local size_mb
  size_mb=$(($(blockdev --getsize64 "$dev" 2>/dev/null || echo 0)/1024/1024))
  if (( size_mb > 32 )); then
    dd if=/dev/zero of="$dev" bs=1M count=16 oflag=direct,dsync status=none 2>/dev/null || true
    dd if=/dev/zero of="$dev" bs=1M count=16 seek=$((size_mb-16)) oflag=direct,dsync status=none 2>/dev/null || true
  else
    dd if=/dev/zero of="$dev" bs=1M count=16 oflag=direct,dsync status=none 2>/dev/null || true
  fi

  udevadm settle
  echo "<<< Готово: $dev"
}

# Общая зачистка перед началом
swapoff -a || true
umount -R /mnt 2>/dev/null || true
if command -v mdadm >/dev/null 2>&1; then mdadm --stop --scan 2>/dev/null || true; fi
if command -v cryptsetup >/dev/null 2>&1; then
  for m in /dev/mapper/*; do
    [[ -e "$m" ]] || continue
    cryptsetup status "$m" >/dev/null 2>&1 && cryptsetup close "$m" 2>/dev/null || true
  done
fi
if command -v vgchange >/dev/null 2>&1; then vgchange -an 2>/dev/null || true; fi

# Полная зачистка целевых дисков
nuke_device "$NVME"
nuke_device "$DATA_A"
nuke_device "$DATA_B"

# 1) Разметка NVMe: EFI + LUKS(Btrfs)
echo "Разметка ${NVME}..."
parted -s "${NVME}" mklabel gpt
parted -s "${NVME}" mkpart EFI fat32 1MiB 513MiB
parted -s "${NVME}" set 1 esp on
parted -s "${NVME}" name 1 EFI
parted -s "${NVME}" mkpart nixos-root 513MiB 100%
parted -s "${NVME}" name 2 nixos-root
udevadm settle

echo "Шифрование LUKS и Btrfs..."
cryptsetup luksFormat --type luks2 -q "${LUKS_PART}"
cryptsetup open "${LUKS_PART}" cryptroot
mkfs.vfat -n EFI "${EFI_PART}"
mkfs.btrfs -L nixos /dev/mapper/cryptroot

mount /dev/mapper/cryptroot /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@cache
btrfs subvolume create /mnt/@swap
btrfs subvolume create /mnt/@snapshots
umount /mnt

mount -o subvol=@,compress=zstd,noatime,ssd,space_cache=v2 /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{boot,nix,var/log,var/cache,swap,.snapshots}
mount -o subvol=@nix,compress=zstd,noatime,ssd,space_cache=v2 /dev/mapper/cryptroot /mnt/nix
mount -o subvol=@log,compress=zstd,noatime,ssd,space_cache=v2 /dev/mapper/cryptroot /mnt/var/log
mount -o subvol=@cache,compress=zstd,noatime,ssd,space_cache=v2 /dev/mapper/cryptroot /mnt/var/cache
mount -o subvol=@swap,noatime,ssd,space_cache=v2 /dev/mapper/cryptroot /mnt/swap
mount -o subvol=@snapshots,compress=zstd,noatime,ssd,space_cache=v2 /dev/mapper/cryptroot /mnt/.snapshots
mount "${EFI_PART}" /mnt/boot

# 2) /home: Btrfs RAID0 на sda+sdb
echo "Разметка ${DATA_A} и ${DATA_B} под Btrfs RAID0..."
parted -s "${DATA_A}" mklabel gpt
parted -s "${DATA_A}" mkpart data 1MiB 100%
parted -s "${DATA_A}" name 1 data-a
parted -s "${DATA_B}" mklabel gpt
parted -s "${DATA_B}" mkpart data 1MiB 100%
parted -s "${DATA_B}" name 1 data-b
udevadm settle

echo "Создаём Btrfs (RAID0) c меткой data..."
mkfs.btrfs -L data -d raid0 -m raid0 "${DATA_A_PART}" "${DATA_B_PART}"

# Убедимся, что ядро «видит» многодисковый Btrfs и появились /dev/disk/by-*
modprobe btrfs || true
btrfs device scan --all-devices || true
udevadm trigger --subsystem-match=block --action=add || true
udevadm settle

# Ждём /dev/disk/by-label/data до 5с, иначе fallback на один из членов массива
DATA_FS_DEV=""
for i in {1..50}; do
  if [[ -e /dev/disk/by-label/data ]]; then
    DATA_FS_DEV="/dev/disk/by-label/data"
    break
  fi
  sleep 0.1
done
if [[ -z "${DATA_FS_DEV}" ]]; then
  echo "Предупреждение: /dev/disk/by-label/data не появился, используем ${DATA_A_PART}"
  DATA_FS_DEV="${DATA_A_PART}"
fi

# Создаём субтом @home и монтируем его
mkdir -p /mnt/hdtemp
mount -t btrfs "${DATA_FS_DEV}" /mnt/hdtemp
btrfs subvolume create /mnt/hdtemp/@home
umount /mnt/hdtemp
rmdir /mnt/hdtemp

mkdir -p /mnt/home
mount -t btrfs -o subvol=@home,compress=zstd,noatime,ssd,space_cache=v2 "${DATA_FS_DEV}" /mnt/home

# 3) Копируем конфиги из репозитория
mkdir -p /mnt/etc/nixos
cp -v "$REPO_DIR/flake.nix" /mnt/etc/nixos/
mkdir -p /mnt/etc/nixos/hosts/svetos
cp -v "$REPO_DIR/hosts/svetos/configuration.nix" /mnt/etc/nixos/hosts/svetos/
mkdir -p /mnt/etc/nixos/home/statix
cp -v "$REPO_DIR/home/statix/home.nix" /mnt/etc/nixos/home/statix/

# 4) Генерируем hardware-configuration.nix
echo "Генерируем hardware-configuration.nix..."
nixos-generate-config --root /mnt
mv -v /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/hosts/svetos/hardware-configuration.nix

# 5) Установка
echo "Устанавливаем систему..."
nixos-install --root /mnt --flake /mnt/etc/nixos#svetos --no-root-passwd

# 6) Пароли
echo "Задай пароли для root и ${USER} (для входа/SSH)."
echo "Сначала root:"
chroot /mnt /bin/sh -c "passwd root"
echo "Теперь ${USER}:"
chroot /mnt /bin/sh -c "passwd ${USER}"

echo "Готово. Отмонтируем и перезагружаем."
umount -R /mnt || true
swapoff -a || true
reboot
