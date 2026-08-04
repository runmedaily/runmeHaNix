# runmeHaNix Public-Safety and Security Audit

Date: 2026-08-03
Status: Initial audit; remediation not yet applied
Tracking: GitHub issue #5

## Scope and method

Reviewed:

- all exported NixOS modules under `modules/roles/`;
- generated target configuration in `installer/install.sh`;
- the example host, ISO configuration, download/write scripts, CI workflow, and public checks;
- evaluated the combined demo system and each exported module independently;
- inspected the effective firewall configuration;
- scanned the full Git history with Gitleaks 8.30.1 and targeted key/token/path patterns;
- compared the evaluated configuration with the physical test host.

## Bottom line

No private keys, credentials, Tailscale keys, API tokens, or high-confidence secrets were found in the current tree or Git history.

The repository is not yet a neutral public installer, however. It contains household/integration-specific behavior, overly broad network exposure, mutable unverified downloads, and defaults inherited from a particular deployment. These are privacy metadata and security-design problems rather than leaked credentials.

## Findings

### A1 — Node-RED is globally exposed without authentication (critical)

Evidence:

- `modules/roles/node-red.nix` opens TCP 1880 globally.
- The default Node-RED editor/admin API has no configured authentication.
- The container uses host networking, so Docker provides no network isolation.

Agreed remediation:

- after Node-RED is selected, ask for one allowed IPv4 address or CIDR;
- do not globally open 1880;
- permit loopback/host-internal traffic for local integrations;
- permit external traffic only from the configured source;
- add Node-RED authentication as a second layer.

### A2 — The Homebridge module contains household-specific behavior (high)

Evidence:

- RainBird-specific options and an RFC1918 address example;
- runtime patching of the RainBird plugin's JavaScript;
- RainBird endpoint wait logic;
- Ring-specific camera-port commentary;
- unexplained TCP port 31190;
- broad TCP and UDP ranges 35000–58000 opened globally.

Impact:

- reveals deployment-specific brands/topology assumptions;
- modifies third-party code at runtime;
- exposes far more network surface than a generic Homebridge install requires.

Remediation:

- remove all RainBird behavior from the generic module;
- remove unexplained and broad default firewall openings;
- make plugin-specific ports explicit opt-in options.

### A3 — Home Assistant opens integration-specific ports globally (high)

Evidence:

- TCP 1400 for Sonos;
- TCP 21064 and 21066 for HomeKit bridge behavior;
- these ports are opened even when those integrations are unused.

Remediation:

- open only the Home Assistant UI/API port by default;
- expose Sonos and HomeKit bridge ports through explicit opt-in options.

### A4 — Tailscale bypasses service-level firewall restrictions (high)

Evidence:

- generated configuration and `home-stack.nix` trust `tailscale0` wholesale.

Impact:

- every listening service is reachable from the tailnet regardless of per-port firewall policy;
- a Node-RED source allowlist would be bypassed for traffic arriving on `tailscale0`.

Remediation:

- stop treating `tailscale0` as a trusted interface;
- explicitly allow required ports/sources on Tailscale.

### A5 — Home Assistant receives excessive container privileges (high)

Evidence:

- Home Assistant runs with both host networking and `--privileged`.

Impact:

- compromise of Home Assistant has a much larger host impact than necessary.

Remediation:

- retain host networking where discovery requires it;
- replace `--privileged` with explicit device mappings and capabilities selected by the user.

### A6 — External software is mutable and unverified (high)

Evidence:

- Homebridge and Node-RED use `latest` image tags;
- Home Assistant uses a floating `stable` tag;
- HACS and the Node-RED companion are downloaded from latest release URLs without checksums;
- Node-RED installs an unpinned npm package at runtime;
- the ISO release downloader does not verify a checksum.

Impact:

- installations are not reproducible;
- upstream changes can enter an install without repository review;
- downloaded archives are trusted solely through HTTPS and the upstream account.

Remediation:

- pin container digests or explicit versions;
- pin archive versions and hashes;
- pin npm package versions;
- publish and verify ISO checksums.

### A7 — Installer input is interpolated into Nix without complete escaping (high)

Evidence:

- hostname and SSH public-key lines are embedded directly into generated Nix strings;
- hostname and swap size are not fully validated;
- SSH key comments may contain characters meaningful to Nix strings.

Impact:

- accidental characters can break installation;
- malicious externally fetched key text could alter generated configuration.

Remediation:

- strictly validate hostnames and numeric swap sizes;
- escape all generated Nix string values;
- strip or safely encode SSH key comments.

### A8 — The public-check denylist exposes private metadata (medium)

Evidence:

- `Makefile` contains literal internal host, project, vault, and user-path names as denylist patterns;
- the check excludes its own file, so those names are committed publicly by the mechanism intended to prevent disclosure.

Remediation:

- remove identity-specific denylist terms from public history going forward;
- replace them with generic secret scanning and a local, untracked denylist when needed.

### A9 — Exported modules do not all work independently (medium)

Evidence:

- `nixosModules.node-red` references the Home Assistant option without importing or safely probing it;
- `nixosModules.home-stack` references role options without importing those role modules;
- combined demo evaluation hides both failures.

Remediation:

- make every exported module independently evaluable;
- add one evaluation test per exported module and combination tests.

### A10 — Persistent service directories are broadly accessible (medium)

Evidence:

- service data directories are initially created with mode 0755.

Impact:

- configuration, flow, and credential-bearing directories may be traversable/readable by unrelated local users depending on child-file modes.

Remediation:

- use dedicated service users and restrictive directory modes;
- verify ownership expected by each container/native service.

### A11 — Privileged local access is broader than necessary (medium)

Evidence:

- the same SSH keys are installed for root and the normal user;
- the normal user has passwordless sudo;
- the normal user is always added to the Docker group;
- Docker is installed even when no container role is selected.

Impact:

- each of these grants effective root access;
- direct root SSH is unnecessary when sudo is available.

Remediation:

- make root SSH opt-in or disable it;
- add Docker and Docker-group membership only when required;
- make passwordless sudo an explicit installer choice.

### A12 — Avahi publishes more interfaces than intended (medium)

Evidence:

- address/workstation publication is enabled without interface restrictions;
- the physical host advertised both its LAN and Docker bridge addresses.

Remediation:

- publish only on selected LAN interfaces or explicitly deny container bridges.

### A13 — Personal/default policy remains in generated systems (low)

Evidence:

- timezone is hard-coded to `America/Los_Angeles`;
- default hostname/user naming and automatic Tailscale enablement reflect project policy rather than neutral defaults;
- Zsh's rebuild alias always updates the flake before rebuilding.

Remediation:

- prompt for timezone or default to UTC;
- distinguish update and rebuild operations;
- document each opinionated default.

### A14 — ISO workflow no longer matches the chosen iteration model (medium)

Evidence:

- CI still builds and publishes a custom ISO;
- documentation/download scripts still point to that custom ISO;
- current testing uses the official NixOS 26.05 ISO plus a downloaded installer;
- GitHub Actions are tag-pinned rather than commit-pinned and the workflow has job-wide write permission.

Remediation:

- decide and document one supported distribution model;
- if using the vanilla ISO, remove/deprecate the custom ISO release path;
- reduce CI token permissions and pin third-party Actions.

## Effective combined firewall exposure

The evaluated demo currently allows:

- TCP: 1400, 1880, 8123, 8581, 21064, 21066, 31190;
- TCP range: 35000–58000;
- UDP: 5353;
- UDP range: 35000–58000;
- all traffic arriving on `tailscale0`.

SSH port 22 is additionally opened by installer-generated host configuration.

## Recommended remediation order

1. Implement the already-agreed Node-RED source allowlist; remove global 1880 exposure.
2. Remove RainBird and household-specific Homebridge behavior.
3. Replace broad integration ports and Tailscale trust with explicit policy.
4. Validate/escape installer input and reduce privilege defaults.
5. Pin external artifacts and verify downloads.
6. Fix module independence and make per-module evaluations mandatory.
7. Align documentation and CI with the vanilla-ISO installation model.
