{
  description = "runmeHaNix — public-safe NixOS Home Assistant bootstrap ISO";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;

      publicModules = [
        self.nixosModules.home-assistant
        self.nixosModules.node-red
        self.nixosModules.homebridge
        self.nixosModules.avahi
        self.nixosModules.shell-environment
        self.nixosModules.home-stack
      ];
    in
    {
      nixosConfigurations.iso-minimal = lib.nixosSystem {
        inherit system;
        specialArgs = { inherit self; };
        modules = [
          { nixpkgs.config.allowUnfree = true; }
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ./iso.nix
          {
            image.fileName = "runmeHaNix-${self.shortRev or "dev"}.iso";
            isoImage.volumeID = "HANIX_ISO";
          }
        ];
      };

      nixosConfigurations.demo-hanix = lib.nixosSystem {
        inherit system;
        modules = publicModules ++ [
          ({ pkgs, ... }: {
            networking.hostName = "demo-hanix";
            time.timeZone = "UTC";

            boot.loader.grub.enable = true;
            boot.loader.grub.device = "nodev";
            fileSystems."/" = {
              device = "/dev/disk/by-label/nixos";
              fsType = "ext4";
            };

            networking.networkmanager.enable = true;
            services.runme.home-stack.enable = true;

            users.users."hanix-user" = {
              isNormalUser = true;
              extraGroups = [ "wheel" "networkmanager" ];
              shell = pkgs.zsh;
            };
            security.sudo.wheelNeedsPassword = false;

            nix.settings.experimental-features = [ "nix-command" "flakes" ];
            system.stateVersion = "26.05";
          })
        ];
      };

      nixosModules = {
        home-assistant = import ./modules/roles/home-assistant.nix;
        node-red = import ./modules/roles/node-red.nix;
        homebridge = import ./modules/roles/homebridge.nix;
        avahi = import ./modules/roles/avahi.nix;
        shell-environment = import ./modules/roles/shell-environment.nix;
        home-stack = import ./modules/roles/home-stack.nix;
      };
    };
}
