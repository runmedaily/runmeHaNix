{ config, pkgs, lib, ... }:

let cfg = config.services.runme.avahi; in
{
  options.services.runme.avahi = {
    enable = lib.mkEnableOption "Avahi mDNS/Bonjour for HomeKit discovery";
  };

  config = lib.mkIf cfg.enable {
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };
    networking.firewall.allowedUDPPorts = [ 5353 ];
  };
}
