# Quickstart

## Mac or Linux: easiest path

```bash
git clone https://github.com/runmedaily/runmeHaNix
cd runmeHaNix
make download-and-write-usb
```

That downloads the latest GitHub-built ISO and launches the safe USB writer.

## If you only want the ISO

```bash
make download-iso
```

The ISO is saved to:

```text
downloads/runmeHaNix-latest.iso
```

## If you are on Linux/NixOS and want to build yourself

```bash
make public-check
make build-minimal
make write-usb
```

## Install

Boot the USB and follow prompts.

SSH key options:

- paste public key
- GitHub username lookup
- file import

Optional modules during install:

- Home Assistant
- Node-RED
- Homebridge
- Avahi/mDNS
- shell environment
