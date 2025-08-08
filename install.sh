#!/usr/bin/env bash
set -euo pipefail

# Константы
NVME="/dev/nvme0n1"
EFI_PART="${NVME}p1"
LUKS_PART="${NVME}p2"
HOST="svetos"
USER="statix"

DATA_A="/dev/sda"
DATA_B="/dev/sdb"
DATA_A_PART="/dev/disk/by-partlabel/data-a"
DATA_B_PART="/dev/disk/by-partlabel/data-b"

ask() {
  read -r -p "$1 [y/N]: " ans
  [[ "${ans:-}" == "y" || "${ans:-}" == "Y" ]]
}

echo "ВНИМАНИЕ: будут УДАЛЕНЫ ВСЕ ДАННЫЕ на: ${NVME}, ${DATA_A}, ${DATA_B}"
ask "Продолжить?" || exit 1

echo "Устанавливаем нужные инструменты..."
if ! command -v nixos-generate-config >/dev/null 2>&1; then
  echo "Скрипт должен выполняться из Live-ISO NixOS. Прерывание."
  exit 1
fi

# 1) Разметка nvme0n1: EFI + LUKS
echo "Разметка ${NVME}..."
sgdisk --zap-all "${NVME}"
parted -s "${NVME}" mklabel gpt
parted -s "${NVME}" mkpart EFI fat32 1MiB 513MiB
parted -s "${NVME}" set 1 esp on
parted -s "${NVME}" name 1 EFI
parted -s "${NVME}" mkpart nixos-root 513MiB 100%
parted -s "${NVME}" name 2 nixos-root

echo "Шифрование LUKS и файловая система..."
cryptsetup luksFormat --type luks2 -q "${LUKS_PART}"
cryptsetup open "${LUKS_PART}" cryptroot
mkfs.vfat -n EFI "${EFI_PART}"
mkfs.btrfs -L nixos /dev/mapper/cryptroot

# 2) Субтомы на корне
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

mkdir -p /mnt/boot
mount "${EFI_PART}" /mnt/boot

# 3) Разметка дисков под /home: Btrfs RAID0 (без шифрования)
echo "Разметка ${DATA_A} и ${DATA_B} под Btrfs RAID0..."
sgdisk --zap-all "${DATA_A}" || true
sgdisk --zap-all "${DATA_B}" || true

parted -s "${DATA_A}" mklabel gpt
parted -s "${DATA_A}" mkpart data 1MiB 100%
parted -s "${DATA_A}" name 1 data-a

parted -s "${DATA_B}" mklabel gpt
parted -s "${DATA_B}" mkpart data 1MiB 100%
parted -s "${DATA_B}" name 1 data-b

# Ждём появления by-partlabel
udevadm settle

mkfs.btrfs -L data -d raid0 -m raid0 "${DATA_A_PART}" "${DATA_B_PART}"

mkdir -p /mnt/hdtemp
mount /dev/disk/by-label/data /mnt/hdtemp
btrfs subvolume create /mnt/hdtemp/@home
umount /mnt/hdtemp
rmdir /mnt/hdtemp

mkdir -p /mnt/home
mount -o subvol=@home,compress=zstd,noatime,ssd,space_cache=v2 /dev/disk/by-label/data /mnt/home

# 4) Конфиги
mkdir -p /mnt/etc/nixos/hosts/svetos
mkdir -p /mnt/etc/nixos/home/statix

# flake.nix
cat > /mnt/etc/nixos/flake.nix <<"EOF"
<ВСТАВЬ ИЗ СООБЩЕНИЯ flake.nix БЕЗ ИЗМЕНЕНИЙ>
EOF

# configuration.nix
cat > /mnt/etc/nixos/hosts/svetos/configuration.nix <<"EOF"
<ВСТАВЬ ИЗ СООБЩЕНИЯ configuration.nix БЕЗ ИЗМЕНЕНИЙ>
EOF

# home.nix
cat > /mnt/etc/nixos/home/statix/home.nix <<"EOF"
<ВСТАВЬ ИЗ СООБЩЕНИЯ home.nix БЕЗ ИЗМЕНЕНИЙ>
EOF

# hardware-configuration.nix
echo "Генерация hardware-configuration.nix..."
nixos-generate-config --root /mnt
mv /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/hosts/svetos/hardware-configuration.nix

# 5) Установка
echo "Установка системы..."
nixos-install --root /mnt --flake /mnt/etc/nixos#svetos --no-root-passwd

# 6) Пароли и финиш
echo "Задай пароли для root и ${USER} (для входа/SSH)."
echo "Сначала root:"
chroot /mnt /bin/sh -c "passwd root"
echo "Теперь ${USER}:"
chroot /mnt /bin/sh -c "passwd ${USER}"

echo "Готово. Отмонтируем и перезагружаем."
umount -R /mnt
swapoff -a || true
reboot
