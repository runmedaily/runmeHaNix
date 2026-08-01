# Example public host template for runmeHaNix.
# Copy into your host flake and replace disk/SSH-key details for your machine.
{ pkgs, ... }:
{
  networking.hostName = "hanix";
  networking.networkmanager.enable = true;

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda"; # adjust for your machine

  services.runme.home-stack.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  users.users."hanix-user" = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      # Add your SSH public key here, or rely on the bootstrap installer.
    ];
  };

  # Optional Home Manager placeholder:
  # Add Home Manager to your own flake if you want user-level packages for
  # hanix-user, such as nvim, emacs, nmap, etc.

  security.sudo.wheelNeedsPassword = false;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "26.05";
}
