{ config, pkgs, lib, ... }:

let cfg = config.services.runme.home-assistant; in
{
  options.services.runme.home-assistant = {
    enable = lib.mkEnableOption "Home Assistant container";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/homeassistant";
      description = "Directory for Home Assistant configuration data";
    };

    extraOptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra docker options for the Home Assistant container";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = lib.mkDefault true;

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];

    virtualisation.oci-containers = {
      backend = "docker";
      containers.homeassistant = {
        image = "ghcr.io/home-assistant/home-assistant:stable";
        volumes = [ "${cfg.dataDir}:/config" ];
        environment = {
          TZ = config.time.timeZone;
        };
        extraOptions = [ "--network=host" "--privileged" ] ++ cfg.extraOptions;
        autoStart = true;
      };
    };

    systemd.services.docker-homeassistant = {
      after = [ "network-online.target" ];
      requires = [ "network-online.target" ];
    };

    # Seed HACS and Node-RED Companion into Home Assistant before container starts
    systemd.services.homeassistant-seed-hacs = {
      description = "Install HACS and Node-RED Companion into Home Assistant";
      wantedBy = [ "docker-homeassistant.service" ];
      before = [ "docker-homeassistant.service" ];
      after = [ "network-online.target" ];
      requires = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.curl pkgs.unzip pkgs.coreutils ];
      script = ''
        HA_CONFIG="${cfg.dataDir}"
        CUSTOM="$HA_CONFIG/custom_components"
        mkdir -p "$CUSTOM"

        # Install HACS
        if [ ! -d "$CUSTOM/hacs" ]; then
          echo "Installing HACS..."
          TMPDIR=$(mktemp -d)
          curl -fsSL -o "$TMPDIR/hacs.zip" "https://github.com/hacs/integration/releases/latest/download/hacs.zip"
          unzip -o "$TMPDIR/hacs.zip" -d "$CUSTOM/hacs"
          rm -rf "$TMPDIR"
          echo "HACS installed"
        fi

        # Install Node-RED Companion
        if [ ! -d "$CUSTOM/nodered" ]; then
          echo "Installing Node-RED Companion..."
          TMPDIR=$(mktemp -d)
          curl -fsSL -o "$TMPDIR/nodered.zip" "https://github.com/zachowj/hass-node-red/releases/latest/download/nodered.zip"
          unzip -o "$TMPDIR/nodered.zip" -d "$CUSTOM/nodered"
          rm -rf "$TMPDIR"
          echo "Node-RED Companion installed"
        fi
      '';
    };

    networking.firewall.allowedTCPPorts = [
      1400  # Sonos event subscriptions
      8123  # Home Assistant UI/API
      21064 # Home Assistant HomeKit Bridge (legacy/default)
      21066 # Home Assistant HomeKit Bridge alternate port for stale Apple Home hub caches
    ];
  };
}
