# Public-safe live ISO environment for the Hanix bootstrap installer.
{ pkgs, lib, ... }:

{
  system.stateVersion = "25.11";

  # Avoid unsupported/broken filesystems in the live installer image.
  boot.supportedFilesystems = lib.mkForce [ "btrfs" "reiserfs" "vfat" "f2fs" "xfs" "ntfs" "cifs" "ext4" ];

  isoImage = {
    makeEfiBootable = true;
    makeUsbBootable = true;
    squashfsCompression = "zstd -Xcompression-level 19";
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking = {
    hostName = "hanix-installer";
    networkmanager.enable = true;
    wireless.enable = lib.mkForce false;
  };

  services.getty.autologinUser = "nixos";
  services.xserver.enable = false;

  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    htop
    openssh
    parted
    dosfstools
    e2fsprogs
    fzf
    pciutils
    usbutils
  ];

  environment.etc."hanix/install.sh" = {
    source = ./installer/install.sh;
    mode = "0755";
  };

  environment.shellAliases = {
    install = "sudo /etc/hanix/install.sh";
  };

  programs.bash.loginShellInit = ''
    if [ "$(tty)" = "/dev/tty1" ] && [ -z "$INSTALLER_LAUNCHED" ]; then
      export INSTALLER_LAUNCHED=1
      sudo /etc/hanix/install.sh
    fi
  '';

  # Livestream/public-safe default: do not expose the live ISO over SSH with a
  # known password. The installed system enables SSH with user-provided keys.
  services.openssh.enable = lib.mkForce false;

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    password = "nixos";
    initialHashedPassword = lib.mkForce null;
  };

  security.sudo.wheelNeedsPassword = false;

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  console = {
    earlySetup = true;
    font = "ter-132n";
    packages = [ pkgs.terminus_font ];
    keyMap = "us";
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  hardware = {
    enableAllFirmware = true;
    enableRedistributableFirmware = true;
  };
}
