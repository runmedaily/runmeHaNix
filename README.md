# runmeHaNix

![Build ISO](https://github.com/runmedaily/runmeHaNix/actions/workflows/build-iso.yml/badge.svg)

A public-safe NixOS bootstrap ISO for a Home Assistant stack:

- Home Assistant
- Node-RED
- Homebridge
- Avahi / mDNS
- native NixOS Tailscale

Built for livestream testing and public feedback.

Special thanks to **[Tonarchy](https://github.com/Tonarchy) / tony_btw on YouTube** for inspiration.

## Safety promise

The ISO contains **no baked secrets**:

- no SSH private keys
- no deploy keys
- no Tailscale auth keys
- no private host configs
- no Forgejo or 1Password wiring

During install, you add your own SSH public key and optionally your own Tailscale auth key.

## Fastest path: download the ISO

Open:

https://github.com/runmedaily/runmeHaNix/actions/workflows/build-iso.yml

Then:

1. Open the latest successful **Build ISO** run.
2. Download the artifact named `runmeHaNix-iso`.
3. Unzip it.
4. Write the `.iso` to USB.

The current artifact is large, about 1.4 GB.

## Build it yourself

On Linux/NixOS:

```bash
git clone https://github.com/runmedaily/runmeHaNix
cd runmeHaNix
make public-check
make build-minimal
```

On macOS:

```bash
git clone https://github.com/runmedaily/runmeHaNix
cd runmeHaNix
make public-check
```

Then use GitHub Actions to build the ISO, unless your Mac has a configured Linux builder.

## Write USB

Linux or macOS:

```bash
make write-usb
```

Build and then write on Linux/NixOS:

```bash
make build-and-write-usb
```

The writer lists disks and requires explicit confirmation before erasing anything.

## Installer flow

The installer asks for:

- target disk
- hostname
- username, default `hanix-user`
- SSH public key source
- optional Tailscale auth key
- optional modules to install from the public repo

Optional modules are not baked as service deployments into the ISO. During
install, the target machine writes a flake pointing at `github:runmedaily/runmeHaNix`
and builds only what you selected.

Available module choices:

- Home Assistant
- Node-RED
- Homebridge
- Avahi / mDNS
- shell environment

Recommended SSH key path:

1. Add your SSH public key to GitHub.
2. In the installer, choose GitHub username lookup.
3. Type your GitHub username.

The installer fetches public keys from:

```text
https://github.com/<username>.keys
```

No GitHub login, password, token, or private key is needed.

Tailscale auth-key input is hidden so it is safe for livestreams and recordings.

## Test in QEMU

On a Linux/NixOS machine with QEMU:

```bash
make test-minimal
```

## Repo layout

```text
flake.nix                  public flake: ISO, modules, demo config
iso.nix                    live ISO config
installer/install.sh       bootstrap installer
scripts/write-usb.sh       Linux/macOS USB writer
modules/roles/             Home Assistant stack roles
templates/host/            example public host template
.github/workflows/         GitHub Actions ISO build
```

## Public check

Before pushing changes:

```bash
make public-check
```

This checks for private-looking strings, suspicious tracked files, Bash syntax, and Nix eval.

## Status

First public iteration. Expect rough edges; feedback is welcome.
