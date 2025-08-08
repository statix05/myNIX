#!/usr/bin/env bash
set -euo pipefail

# КОНСТАНТЫ
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

# Универсальная функция «полного» затирания метаданных и разделов
nuke_device() {
  local dev="$1"
  echo ">>> Подготовка к затиранию: $dev"

  # Собираем список самого диска и его разделов
  mapfile -t nodes < <(lsblk -lnpo NAME "$dev" 2>/dev/null || true)
  if ((${#nodes[@]} == 0)); then
    nodes=("$dev")
  fi

  # Снимаем монтирования
  for n in "${nodes[@]}"; do
    while read -r mp; do
      [[ -n "$mp" ]] || continue
      echo "  - umount $mp"
      umount -R "$mp" 2>/dev/null || true
    done < <(lsblk -lnpo MOUNTPOINT "$n" 2>/dev/null | awk 'NF>0')
  done

  # Отключаем свап на этих устройствах
  while read -r swdev _; do
    [[ -n "${swdev:-}" ]] || continue
    if [[ "$swdev" == "$dev"* ]]; then
      echo "  - swapoff $swdev"
      swapoff "$swdev" 2>/dev/null || true
    fi
  done < <(grep -E "^(/dev/|/dev/mapper/)" /proc/swaps || true)

  # Закрываем любые открытые dm-crypt (LUKS)
  if command -v cryptsetup >/dev/null 2>&1; then
    for m in /dev/mapper/*; do
      [[ -e "$m" ]] || continue
      if cryptsetup status "$m" >/dev/null 2>&1; then
        echo "  - cryptsetup close $m"
        cryptsetup close "$m" 2>/dev/null || true
      fi
    done
  fi

  # Останавливаем mdadm-массивы и затираем superblock
  if command -v mdadm >/dev/null 2>&1; then
    mdadm --stop --scan 2>/dev/null || true
    for n in "${nodes[@]}" "$dev"; do
      echo "  - mdadm --zero-superblock $n"
      mdadm --zero-superblock --force "$n" 2>/dev/null || true
    done
  fi

  # Деактивируем LVM и убираем PV-сигнатуры
  if command -v vgchange >/dev/null 2>&1; then
    vgchange -an 2>/dev/null || true
  fi
  if command -v pvremove >/dev/null 2>&1; then
    for n in "${nodes[@]}" "$dev"; do
      pvremove -ff -y "$n" 2>/dev/null || true
    done
  fi

  # Wipe FS сигнатуры на разделах и самом диске
  for n in "${nodes[@]}" "$dev"; do
    wipefs -af "$n" 2>/dev/null || true
  done

  # ZAP GPT/MBR
  if command -v sgdisk >/dev/null 2>&1; then
    sgdisk --zap-all "$dev" 2>/dev/null || true
  fi

  # Быстрый TRIM (если поддерживается)
  if command -v blkdiscard >/dev/null 2>&1; then
    blkdiscard -f "$dev" 2>/dev/null || true
  fi

  # Нулим первые и последние 16MiB диска (для верности)
  local size_mb
  size_mb=$(($(blockdev --getsize64 "$dev" 2>/dev/null || echo 0)/1024/1024))
  if (( size_mb > 32 )); then
    echo "  - zero first/last 16MiB on $dev"
    dd if=/dev/zero of="$dev" bs=1M count=16 oflag=direct,dsync status=none 2>/dev/null || true
    dd if=/dev/zero of="$dev" bs=1M count=16 seek=$((size_mb-16)) oflag=direct,dsync status=none 2>/dev/null || true
  else
    dd if=/dev/zero of="$dev" bs=1M count=16 oflag=direct,dsync status=none 2>/dev/null || true
  fi

  udevadm settle
  echo "<<< Готово: $dev"
}

# Предварительная общая зачистка (если скрипт запускают повторно)
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

# ПОЛНОЕ ЗАТИРАНИЕ ТРЁХ НОСИТЕЛЕЙ
nuke_device "$NVME"
nuke_device "$DATA_A"
nuke_device "$DATA_B"

# 1) Разметка nvme0n1: EFI + LUKS
echo "Разметка ${NVME}..."
parted -s "${NVME}" mklabel gpt
parted -s "${NVME}" mkpart EFI fat32 1MiB 513MiB
parted -s "${NVME}" set 1 esp on
parted -s "${NVME}" name 1 EFI
parted -s "${NVME}" mkpart nixos-root 513MiB 100%
parted -s "${NVME}" name 2 nixos-root
udevadm settle

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
parted -s "${DATA_A}" mklabel gpt
parted -s "${DATA_A}" mkpart data 1MiB 100%
parted -s "${DATA_A}" name 1 data-a

parted -s "${DATA_B}" mklabel gpt
parted -s "${DATA_B}" mkpart data 1MiB 100%
parted -s "${DATA_B}" name 1 data-b
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
umount -R /mnt || true
swapoff -a || true
reboot
