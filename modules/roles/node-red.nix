{ config, pkgs, lib, ... }:

let cfg = config.services.runme.node-red; in
{
  options.services.runme.node-red = {
    enable = lib.mkEnableOption "Node-RED container";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/nodered";
      description = "Directory for Node-RED persistent data";
    };

    extraOptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra docker options for the Node-RED container";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = lib.mkDefault true;
    environment.systemPackages = [ pkgs.docker ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 1000 1000 -"
    ];

    virtualisation.oci-containers = {
      backend = "docker";
      containers.nodered = {
        image = "nodered/node-red:latest";
        volumes = [ "${cfg.dataDir}:/data" ];
        environment = {
          TZ = config.time.timeZone;
        };
        extraOptions = [ "--network=host" ] ++ cfg.extraOptions;
        autoStart = true;
        dependsOn = lib.optional config.services.runme.home-assistant.enable "homeassistant";
      };
    };

    systemd.services.docker-nodered = {
      after = [ "network-online.target" ];
      requires = [ "network-online.target" ];
    };

    systemd.services.nodered-install-ha = {
      description = "Install Home Assistant nodes in Node-RED";
      wantedBy = [ "docker-nodered.service" ];
      after = [ "docker-nodered.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.docker ];
      script = ''
        # Wait for Node-RED container to be ready
        for i in $(seq 1 30); do
          if docker exec nodered true 2>/dev/null; then break; fi
          sleep 2
        done

        # Install if not already present
        if [ ! -d "${cfg.dataDir}/node_modules/node-red-contrib-home-assistant-websocket" ]; then
          echo "Installing node-red-contrib-home-assistant-websocket..."
          docker exec -w /data nodered npm install node-red-contrib-home-assistant-websocket 2>&1
          echo "Restarting Node-RED to load new nodes..."
          docker restart nodered
          echo "Done"
        else
          echo "Home Assistant nodes already installed"
        fi
      '';
    };

    networking.firewall.allowedTCPPorts = [ 1880 ];
  };
}
