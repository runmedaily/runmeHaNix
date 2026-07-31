#!/usr/bin/env bash
# Safely write result/iso/*.iso to a USB disk on Linux or macOS.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'
info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok() { echo -e "${GREEN}[OK]${NC} $*"; }
err() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ISO="$(find "$ROOT/result/iso" -maxdepth 1 -name '*.iso' 2>/dev/null | head -1 || true)"
if [[ -z "$ISO" ]]; then
  err "No ISO found. Run: make build-minimal"
  exit 1
fi

info "ISO: $ISO"
echo "     Size: $(du -h "$ISO" | awk '{print $1}')"
echo ""

confirm_write() {
  local device="$1"
  echo ""
  echo -e "${RED}${BOLD}WARNING: this will erase all data on $device${NC}"
  echo -en "${CYAN}Type the device path to confirm ($device): ${NC}"
  read -r confirm
  [[ "$confirm" == "$device" ]]
}

write_linux() {
  echo -e "${BOLD}Removable / USB disks:${NC}"
  local found=0
  while IFS= read -r name; do
    local removable transport size model tran
    removable=$(cat "/sys/block/$name/removable" 2>/dev/null || echo 0)
    transport=$(readlink -f "/sys/block/$name/device" 2>/dev/null || echo "")
    if [[ "$removable" == 1 || "$transport" == *usb* ]]; then
      size=$(lsblk -dno SIZE "/dev/$name" 2>/dev/null || echo '?')
      model=$(lsblk -dno MODEL "/dev/$name" 2>/dev/null || echo unknown)
      tran=$(lsblk -dno TRAN "/dev/$name" 2>/dev/null || echo '?')
      echo -e "  ${GREEN}/dev/$name${NC}  $size  $model  ($tran)"
      found=$((found + 1))
    fi
  done < <(lsblk -dno NAME | grep -E '^(sd[a-z]|nvme[0-9]+n[0-9]+)$' || true)

  if [[ "$found" -eq 0 ]]; then
    err "No removable/USB disks found"
    exit 1
  fi

  echo -en "${CYAN}Device path (e.g. /dev/sdb): ${NC}"
  read -r device
  [[ "$device" == /dev/* ]] || device="/dev/$device"

  local base removable transport
  base=$(basename "$device")
  removable=$(cat "/sys/block/$base/removable" 2>/dev/null || echo 0)
  transport=$(readlink -f "/sys/block/$base/device" 2>/dev/null || echo "")
  if [[ "$removable" != 1 && "$transport" != *usb* ]]; then
    err "$device does not look removable/USB; refusing"
    exit 1
  fi

  lsblk -o NAME,SIZE,TYPE,MOUNTPOINT "$device" || true
  confirm_write "$device" || { err "Cancelled"; exit 1; }

  for part in $(lsblk -nrpo NAME "$device" | tail -n +2); do
    sudo umount "$part" 2>/dev/null || true
  done
  sudo dd if="$ISO" of="$device" bs=4M status=progress oflag=sync conv=fsync
  ok "ISO written to $device"
}

write_macos() {
  echo -e "${BOLD}Disks:${NC}"
  diskutil list external physical || diskutil list
  echo ""
  echo -en "${CYAN}Disk identifier (e.g. disk4): ${NC}"
  read -r disk
  [[ "$disk" == disk* ]] || { err "Expected disk identifier like disk4"; exit 1; }
  local device="/dev/$disk"
  local raw="/dev/r$disk"

  diskutil info "$device" | sed -n '1,25p'
  confirm_write "$device" || { err "Cancelled"; exit 1; }

  diskutil unmountDisk "$device"
  sudo dd if="$ISO" of="$raw" bs=4m status=progress
  sync
  diskutil eject "$device" || true
  ok "ISO written to $device"
}

case "$(uname -s)" in
  Linux) write_linux ;;
  Darwin) write_macos ;;
  *) err "Unsupported OS: $(uname -s)"; exit 1 ;;
esac
