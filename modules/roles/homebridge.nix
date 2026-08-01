{ config, pkgs, lib, ... }:

let
  cfg = config.services.runme.homebridge;
  rainbirdHttpsHostsJson = builtins.toJSON cfg.rainbird.httpsHosts;
in
{
  options.services.runme.homebridge = {
    enable = lib.mkEnableOption "Homebridge container";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/homebridge";
      description = "Directory for Homebridge configuration data";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "homebridge/homebridge:latest";
      description = "Homebridge container image. Set this to a version tag or digest in host configs for reproducible deployments.";
    };

    extraOptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra docker options for the Homebridge container";
    };

    rainbird = {
      httpsHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = [ "10.11.10.94" ];
        description = ''
          RainBird controller IPs/hosts known to use the newer HTTPS /stick API.
          Homebridge startup waits for these controllers' HTTPS endpoints, and the
          bundled rainbird library is patched to recover if it ever caches HTTP/80
          for one of these hosts after a transient probe failure.
        '';
      };

      httpsWaitTimeout = lib.mkOption {
        type = lib.types.ints.positive;
        default = 120;
        description = "Seconds to wait for configured RainBird HTTPS controllers before starting Homebridge.";
      };

      patchHttpsReprobe = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Patch the bundled rainbird library so configured HTTPS controllers recover from an accidental HTTP/80 fallback.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = lib.mkDefault true;
    environment.systemPackages = [ pkgs.docker ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];

    virtualisation.oci-containers = {
      backend = "docker";
      containers.homebridge = {
        image = cfg.image;
        volumes = [ "${cfg.dataDir}:/homebridge" ];
        environment = {
          TZ = config.time.timeZone;
          HOMEBRIDGE_CONFIG_UI_PORT = "8581";
        };
        extraOptions = [ "--network=host" ] ++ cfg.extraOptions;
        autoStart = true;
      };
    };

    systemd.services.docker-homebridge = {
      after = [ "network-online.target" ];
      requires = [ "network-online.target" ];
    };

    # Patch Homebridge config to use ciao mDNS advertiser before container starts
    systemd.services.homebridge-fix-advertiser = {
      description = "Fix Homebridge mDNS advertiser to use ciao";
      wantedBy = [ "docker-homebridge.service" ];
      before = [ "docker-homebridge.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.gnused pkgs.curl pkgs.python3 pkgs.coreutils ];
      script = ''
        CFG="${cfg.dataDir}/config.json"
        if [ -f "$CFG" ]; then
          sed -i -e 's/"advertiser": "bonjour-hap"/"advertiser": "ciao"/' \
                 -e 's/"advertiser": "avahi"/"advertiser": "ciao"/' "$CFG"
        fi

        export RAINBIRD_HTTPS_HOSTS='${rainbirdHttpsHostsJson}'

        if [ "${lib.boolToString cfg.rainbird.patchHttpsReprobe}" = "true" ]; then
          CLIENT="${cfg.dataDir}/node_modules/@homebridge-plugins/homebridge-rainbird/node_modules/rainbird/dist/RainBird/RainBirdClient.js"
          if [ -f "$CLIENT" ]; then
            RAINBIRD_HTTPS_HOSTS="$RAINBIRD_HTTPS_HOSTS" python3 - "$CLIENT" <<'PY'
import json, os, sys
from pathlib import Path

path = Path(sys.argv[1])
hosts = json.loads(os.environ.get("RAINBIRD_HTTPS_HOSTS", "[]"))
text = path.read_text()
marker = "RUNME_RAINBIRD_HTTPS_REPROBE"
if marker not in text:
    old = """                this.emitLog('error', `RainBird controller request failed. [''${error}]`);\n"""
    new = """                // RUNME_RAINBIRD_HTTPS_REPROBE: Some newer RainBird controllers use HTTPS only.\n                // If a transient startup probe makes the library cache HTTP/80 for one of the\n                // configured HTTPS-only hosts, switch it back to HTTPS instead of retrying port 80 forever.\n                const runmeRainbirdHttpsHosts = new Set(RUNME_RAINBIRD_HTTPS_HOSTS);\n                const runmeRainbirdErrorCode = error && error.code;\n                const runmeRainbirdErrorMessage = error instanceof Error ? error.message : String(error);\n                if (this._url !== null && this._url.startsWith('http:')\n                    && runmeRainbirdHttpsHosts.has(this.address)\n                    && (runmeRainbirdErrorCode === 'ECONNREFUSED' || runmeRainbirdErrorMessage.includes(':80'))) {\n                    this._url = `https://''${this.address}/stick`;\n                    this.emitLog('warn', `[''${this.address}] HTTP/80 failed for configured HTTPS RainBird controller; retrying HTTPS`);\n                    continue;\n                }\n                this.emitLog('error', `RainBird controller request failed. [''${error}]`);\n""".replace("RUNME_RAINBIRD_HTTPS_HOSTS", json.dumps(hosts))
    if old not in text:
        raise SystemExit(f"RainBirdClient.js patch anchor not found in {path}")
    path.write_text(text.replace(old, new, 1))
PY
          fi
        fi

        if [ "$RAINBIRD_HTTPS_HOSTS" != "[]" ]; then
          python3 - <<'PY'
import json, os, subprocess, sys, time
hosts = json.loads(os.environ["RAINBIRD_HTTPS_HOSTS"])
timeout = int(os.environ.get("RAINBIRD_HTTPS_WAIT_TIMEOUT", "${toString cfg.rainbird.httpsWaitTimeout}"))
deadline = time.time() + timeout
for host in hosts:
    url = f"https://{host}/stick"
    while True:
        result = subprocess.run([
            "curl", "-k", "-sS", "-o", "/dev/null", "-w", "%{http_code}",
            "--connect-timeout", "5", "--max-time", "8", url,
        ], text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        # GET normally returns 405; any HTTP response proves HTTPS/TLS/connectivity is ready.
        if result.stdout.strip() and result.stdout.strip() != "000":
            print(f"RainBird HTTPS endpoint ready: {url} -> HTTP {result.stdout.strip()}")
            break
        if time.time() >= deadline:
            raise SystemExit(f"Timed out waiting for RainBird HTTPS endpoint: {url}")
        print(f"Waiting for RainBird HTTPS endpoint: {url}")
        time.sleep(5)
PY
        fi
      '';
    };

    networking.firewall = {
      allowedTCPPorts = [ 8581 21064 31190 ];
      allowedTCPPortRanges = [{ from = 35000; to = 58000; }];
      # HomeKit camera streams (e.g. Ring via Homebridge) use dynamic UDP/RTP ports.
      allowedUDPPortRanges = [{ from = 35000; to = 58000; }];
    };
  };
}
