{ config, lib, ... }:

let
  cfg = config.services.runme.home-stack;
in
{
  options.services.runme.home-stack = {
    enable = lib.mkEnableOption "Home Assistant + Node-RED + Homebridge public stack";

    enableNativeTailscale = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable native NixOS Tailscale for remote access.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.runme.home-assistant.enable = true;
    services.runme.node-red.enable = true;
    services.runme.homebridge.enable = true;
    services.runme.avahi.enable = true;
    services.runme.shell.enable = true;

    services.tailscale.enable = cfg.enableNativeTailscale;
    networking.firewall.trustedInterfaces = lib.mkIf cfg.enableNativeTailscale [ "tailscale0" ];
  };
}
