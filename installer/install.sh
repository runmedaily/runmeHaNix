#!/usr/bin/env bash
#
# Hanix public bootstrap installer
# Installs a minimal NixOS system with SSH key auth and optional native Tailscale.
# No SSH keys, deploy keys, or Tailscale auth keys are baked into the ISO.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

MOUNT_POINT="/mnt"
CONFIG_DIR="/etc/nixos"

DISK=""
TARGET_HOSTNAME="hanix"
USERNAME="hanix-user"
SWAP_SIZE="4"
SSH_KEYS=()
TS_AUTHKEY=""

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

confirm() {
  local prompt="${1:-Continue?}"
  echo -en "${CYAN}${prompt} [y/N]: ${NC}"
  read -r response
  [[ "$response" =~ ^[Yy]$ ]]
}

section_header() {
  clear
  echo -e "${CYAN}─── ${BOLD}$1${NC}${CYAN} ───${NC}"
  echo ""
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
  fi
}

setup_console() {
  if command -v setfont >/dev/null 2>&1; then
    setfont ter-132n 2>/dev/null || setfont ter-v32b 2>/dev/null || true
  fi
}

check_uefi() {
  [[ -d /sys/firmware/efi/efivars ]]
}

wait_for_internet() {
  local attempt=0
  while ! curl -sf --max-time 5 https://cache.nixos.org >/dev/null 2>&1; do
    printf "\r${YELLOW}...${NC} Waiting for internet"
    sleep 2
    attempt=$((attempt + 1))
    if (( attempt % 15 == 0 )); then
      echo ""
      log_warn "Still no connection after $((attempt * 2))s. Check NetworkManager/nmtui."
    fi
  done
  printf "\r"
  log_success "Internet connection available"
}

part_prefix() {
  if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
    echo "${DISK}p"
  else
    echo "$DISK"
  fi
}

show_banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  cat <<'EOF'
  _   _             _       
 | | | | __ _ _ __ (_)_  __ 
 | |_| |/ _` | '_ \| \ \/ / 
 |  _  | (_| | | | | |>  <  
 |_| |_|\__,_|_| |_|_/_/\_\ 

 Public NixOS Bootstrap Installer
EOF
  echo -e "${NC}"
}

valid_ssh_key() {
  [[ "$1" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+)[[:space:]]+[^[:space:]]+([[:space:]].*)?$ ]]
}

add_ssh_key() {
  local key="$1"
  if [[ -z "$key" ]]; then
    return 1
  fi
  if [[ "$key" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+)[[:space:]]+[^[:space:]]+([[:space:]].*)?$ ]]; then
    SSH_KEYS+=("$key")
    return 0
  fi
  return 1
}

show_key_fingerprints() {
  if ((${#SSH_KEYS[@]} == 0)); then
    return 0
  fi
  echo -e "${BOLD}Current SSH keys:${NC}"
  local tmp
  tmp=$(mktemp)
  for key in "${SSH_KEYS[@]}"; do
    printf '%s\n' "$key" > "$tmp"
    if command -v ssh-keygen >/dev/null 2>&1; then
      echo -n "  "
      ssh-keygen -lf "$tmp" 2>/dev/null || echo "fingerprint unavailable"
    else
      echo "  $(awk '{print $1, $3}' "$tmp")"
    fi
  done
  rm -f "$tmp"
}

select_disk() {
  section_header "Disk Selection"
  local disks
  # Include common physical, virtual, and Xen block devices:
  #   sd*      SATA/SCSI/USB/VirtIO-scsi
  #   nvme*    NVMe
  #   vd*      VirtIO block
  #   xvd*     Xen paravirtual disks, common in Xen Orchestra/XCP-ng
  #   mmcblk*  eMMC/SD media
  disks=$(lsblk -dpno NAME,SIZE,MODEL | grep -E "^/dev/(sd|nvme|vd|xvd|mmcblk)" || true)
  if [[ -z "$disks" ]]; then
    log_error "No suitable disks found"
    exit 1
  fi

  echo -e "${BOLD}Available disks:${NC}"
  echo "$disks"
  echo ""

  if command -v fzf >/dev/null 2>&1; then
    DISK=$(echo "$disks" | fzf --prompt="Select disk: " --height=8 --reverse --no-mouse | awk '{print $1}') || true
  else
    echo -en "${CYAN}Enter disk path (e.g. /dev/sda): ${NC}"
    read -r DISK
  fi

  if [[ -z "$DISK" ]]; then
    log_error "No disk selected"
    exit 1
  fi

  section_header "Confirm Disk"
  echo -e "${RED}${BOLD}WARNING:${NC} This will ${RED}ERASE ALL DATA${NC} on ${BOLD}$DISK${NC}"
  echo ""
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINT "$DISK" | head -n 20
  echo ""
  if ! confirm "Are you ABSOLUTELY sure?"; then
    log_info "Installation cancelled"
    exit 0
  fi
}

get_host_info() {
  section_header "Host Info"
  echo -en "${CYAN}Hostname [hanix]: ${NC}"
  read -r TARGET_HOSTNAME
  TARGET_HOSTNAME="${TARGET_HOSTNAME:-hanix}"

  echo -en "${CYAN}Username [hanix-user]: ${NC}"
  read -r USERNAME
  USERNAME="${USERNAME:-hanix-user}"

  if ! [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    log_error "Invalid Linux username: $USERNAME"
    exit 1
  fi

  echo -en "${CYAN}Swap size in GB [4]: ${NC}"
  read -r SWAP_SIZE
  SWAP_SIZE="${SWAP_SIZE:-4}"

  log_success "Hostname: $TARGET_HOSTNAME, User: $USERNAME, Swap: ${SWAP_SIZE}GB"
}

collect_ssh_keys_github() {
  echo -en "${CYAN}GitHub username: ${NC}"
  read -r gh_user
  if [[ -z "$gh_user" ]]; then
    return 0
  fi
  if ! [[ "$gh_user" =~ ^[A-Za-z0-9-]+$ ]]; then
    log_warn "Invalid GitHub username format"
    return 0
  fi

  local tmp before added
  tmp=$(mktemp)
  before=${#SSH_KEYS[@]}
  if curl -fsSL "https://github.com/${gh_user}.keys" -o "$tmp"; then
    while IFS= read -r key; do
      add_ssh_key "$key" || true
    done < "$tmp"
  else
    log_warn "Could not fetch GitHub keys for $gh_user"
  fi
  rm -f "$tmp"
  added=$((${#SSH_KEYS[@]} - before))
  if (( added > 0 )); then
    log_success "Added $added key(s) from GitHub user $gh_user"
  else
    log_warn "No SSH keys found for GitHub user $gh_user"
  fi
}

collect_ssh_keys_manual() {
  echo -e "Paste one public key per line. Press Enter on an empty line when done."
  while true; do
    echo -en "${CYAN}SSH public key: ${NC}"
    read -r key
    [[ -z "$key" ]] && break
    if add_ssh_key "$key"; then
      log_success "Added SSH key"
    else
      log_warn "That did not look like an SSH public key"
    fi
  done
}

collect_ssh_keys_file() {
  echo -en "${CYAN}Path to authorized_keys or .pub file: ${NC}"
  read -r key_file
  if [[ -z "$key_file" ]]; then
    return 0
  fi
  if [[ ! -r "$key_file" ]]; then
    log_warn "Cannot read $key_file"
    return 0
  fi
  local before added
  before=${#SSH_KEYS[@]}
  while IFS= read -r key; do
    add_ssh_key "$key" || true
  done < "$key_file"
  added=$((${#SSH_KEYS[@]} - before))
  log_success "Added $added key(s) from $key_file"
}

collect_ssh_keys() {
  section_header "SSH Keys"
  echo "No SSH keys are baked into this ISO. Add at least one public key."
  echo "Recommended: enter a GitHub username and fetch public keys from github.com/<user>.keys."
  echo ""

  while ((${#SSH_KEYS[@]} == 0)); do
    echo -e "${BOLD}Choose SSH key source:${NC}"
    echo "  1) GitHub username (recommended)"
    echo "  2) Manual paste"
    echo "  3) File path"
    echo "  4) Cancel install"
    echo -en "${CYAN}Choice [1]: ${NC}"
    read -r choice
    choice="${choice:-1}"
    case "$choice" in
      1) collect_ssh_keys_github ;;
      2) collect_ssh_keys_manual ;;
      3) collect_ssh_keys_file ;;
      4) log_error "Cancelled"; exit 1 ;;
      *) log_warn "Unknown choice" ;;
    esac
    echo ""
    show_key_fingerprints
    if ((${#SSH_KEYS[@]} == 0)); then
      log_warn "At least one SSH public key is required for remote access."
      echo ""
    fi
  done
}

collect_tailscale_auth() {
  section_header "Tailscale"
  echo "Optional: paste a Tailscale ephemeral/pre-auth key to auto-join on first boot."
  echo "Press Enter to skip. Input is hidden for livestream safety."
  echo ""
  echo -en "${CYAN}Tailscale auth key (optional, hidden): ${NC}"
  read -r -s TS_AUTHKEY
  echo ""
  TS_AUTHKEY="$(printf '%s' "$TS_AUTHKEY" | tr -d '\r\n')"
  if [[ -z "$TS_AUTHKEY" ]]; then
    log_info "Tailscale auto-auth skipped"
  elif [[ "$TS_AUTHKEY" == tskey-auth-* ]]; then
    log_success "Tailscale auth key provided"
  else
    log_warn "Provided value does not look like tskey-auth-*; it will still be installed as entered"
  fi
}

release_disk() {
  log_info "Releasing existing partitions on $DISK..."
  swapoff "${DISK}"* 2>/dev/null || true
  for part in $(lsblk -nrpo NAME "$DISK" | tail -n +2); do
    umount -f "$part" 2>/dev/null || true
  done
  for part in $(lsblk -nrpo NAME "$DISK" | tail -n +2); do
    dmsetup remove "$part" 2>/dev/null || true
  done
  sleep 1
}

partition_disk_uefi() {
  log_info "Partitioning (UEFI)..."
  release_disk
  wipefs -af "$DISK"
  parted -s "$DISK" mklabel gpt
  parted -s "$DISK" mkpart ESP fat32 1MiB 1025MiB
  parted -s "$DISK" set 1 esp on
  local swap_end=$((1025 + SWAP_SIZE * 1024))
  parted -s "$DISK" mkpart primary linux-swap 1025MiB "${swap_end}MiB"
  parted -s "$DISK" mkpart primary ext4 "${swap_end}MiB" 100%
  sleep 2
  partprobe "$DISK"
  sleep 1
  local pp
  pp=$(part_prefix)
  mkfs.fat -F32 "${pp}1"
  mkswap "${pp}2"
  mkfs.ext4 -F "${pp}3"
}

partition_disk_bios() {
  log_info "Partitioning (BIOS)..."
  release_disk
  wipefs -af "$DISK"
  parted -s "$DISK" mklabel gpt
  parted -s "$DISK" mkpart primary 1MiB 2MiB
  parted -s "$DISK" set 1 bios_grub on
  local swap_end=$((2 + SWAP_SIZE * 1024))
  parted -s "$DISK" mkpart primary linux-swap 2MiB "${swap_end}MiB"
  parted -s "$DISK" mkpart primary ext4 "${swap_end}MiB" 100%
  sleep 2
  partprobe "$DISK"
  sleep 1
  local pp
  pp=$(part_prefix)
  mkswap "${pp}2"
  mkfs.ext4 -F "${pp}3"
}

mount_partitions() {
  log_info "Mounting..."
  local pp
  pp=$(part_prefix)
  mount "${pp}3" "$MOUNT_POINT"
  if check_uefi; then
    mkdir -p "$MOUNT_POINT/boot"
    mount "${pp}1" "$MOUNT_POINT/boot"
  fi
  swapon "${pp}2"
}

generate_config() {
  log_info "Generating NixOS configuration..."
  nixos-generate-config --root "$MOUNT_POINT"

  local ssh_keys_nix=""
  for key in "${SSH_KEYS[@]}"; do
    ssh_keys_nix+="      \"$key\"\n"
  done

  local tailscale_auth_block=""
  if [[ -n "$TS_AUTHKEY" ]]; then
    tailscale_auth_block=$(cat <<TAILSCALEEOF
  systemd.services.tailscale-autoauth = {
    description = "Tailscale auto-authentication";
    after = [ "tailscaled.service" "network-online.target" ];
    wants = [ "tailscaled.service" "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      if [ -s /etc/tailscale/authkey ]; then
        /run/current-system/sw/bin/tailscale up --auth-key="\$(cat /etc/tailscale/authkey)" --hostname="$TARGET_HOSTNAME" || true
        rm -f /etc/tailscale/authkey
      fi
    '';
  };
TAILSCALEEOF
)
  fi

  local boot_config=""
  if check_uefi; then
    boot_config='  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;'
  else
    boot_config="  boot.loader.grub.enable = true;
  boot.loader.grub.device = \"$DISK\";"
  fi

  cat > "$MOUNT_POINT$CONFIG_DIR/configuration.nix" <<NIXEOF
# Hanix bootstrap config — enough to get on the network and accept SSH.
{ config, pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];

$boot_config

  networking.hostName = "$TARGET_HOSTNAME";
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.trusted-users = [ "root" "$USERNAME" ];

  environment.systemPackages = with pkgs; [ git curl htop vim ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  services.tailscale.enable = true;
$tailscale_auth_block
  users.users.root.openssh.authorizedKeys.keys = [
$(printf '%b' "$ssh_keys_nix")  ];

  users.users."$USERNAME" = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
$(printf '%b' "$ssh_keys_nix")    ];
  };

  security.sudo.wheelNeedsPassword = false;

  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  system.stateVersion = "25.11";
}
NIXEOF
  log_success "Configuration generated"
}

run_installation() {
  wait_for_internet
  log_info "Installing NixOS. This can take a while..."
  export TMPDIR="$MOUNT_POINT/tmp"
  mkdir -p "$TMPDIR"
  nixos-install --root "$MOUNT_POINT" --no-root-passwd
  rm -rf "$MOUNT_POINT/tmp"
  unset TMPDIR
  log_success "Installation complete"
}

inject_tailscale_key() {
  if [[ -n "$TS_AUTHKEY" ]]; then
    log_info "Installing Tailscale auth key for first boot..."
    mkdir -p "$MOUNT_POINT/etc/tailscale"
    printf '%s\n' "$TS_AUTHKEY" > "$MOUNT_POINT/etc/tailscale/authkey"
    chmod 600 "$MOUNT_POINT/etc/tailscale/authkey"
    log_success "Tailscale auth key installed"
  fi
}

set_user_password() {
  log_info "Setting password for '$USERNAME'..."
  echo ""
  while ! nixos-enter --root "$MOUNT_POINT" -c "passwd '$USERNAME'"; do
    log_warn "Try again..."
    echo ""
  done
  log_success "Password set"
}

main() {
  check_root
  setup_console
  show_banner
  echo -e "  ${BOLD}Public-safe bootstrap installer${NC} — no baked keys or secrets.\n"

  if check_uefi; then log_info "Boot mode: UEFI"; else log_info "Boot mode: BIOS/Legacy"; fi
  echo ""

  select_disk
  get_host_info
  collect_ssh_keys
  collect_tailscale_auth

  show_banner
  echo -e "${BOLD}Installation Summary:${NC}"
  echo "─────────────────────────────────────"
  echo -e "  Disk:      ${YELLOW}$DISK${NC}"
  echo -e "  Hostname:  $TARGET_HOSTNAME"
  echo -e "  Username:  $USERNAME"
  echo -e "  Swap:      ${SWAP_SIZE}GB"
  echo -e "  SSH keys:  ${#SSH_KEYS[@]} key(s)"
  if [[ -n "$TS_AUTHKEY" ]]; then
    echo -e "  Tailscale: ${GREEN}auto-auth on boot${NC}"
  else
    echo -e "  Tailscale: skipped/manual later"
  fi
  if check_uefi; then echo "  Boot:      UEFI"; else echo "  Boot:      BIOS/Legacy"; fi
  echo "─────────────────────────────────────"
  echo ""

  if ! confirm "Proceed with installation?"; then
    log_info "Cancelled"
    exit 0
  fi

  section_header "Installing"
  if check_uefi; then partition_disk_uefi; else partition_disk_bios; fi
  mount_partitions
  generate_config
  run_installation
  inject_tailscale_key

  section_header "User Password"
  set_user_password

  show_banner
  echo -e "${GREEN}${BOLD}Installation complete.${NC}"
  echo ""
  echo "After reboot, SSH using your provided key:"
  echo -e "  ${CYAN}ssh $USERNAME@$TARGET_HOSTNAME${NC}"
  if [[ -z "$TS_AUTHKEY" ]]; then
    echo -e "Run ${CYAN}sudo tailscale up${NC} after boot if you skipped Tailscale auth."
  fi
  echo ""

  if confirm "Reboot now?"; then
    umount -R "$MOUNT_POINT" 2>/dev/null || true
    swapoff -a 2>/dev/null || true
    reboot
  fi
}

main "$@"
