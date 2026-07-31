# runmeHaNix

Public-safe NixOS bootstrap ISO for a Home Assistant + Node-RED + Homebridge stack.

No SSH keys, deploy keys, or Tailscale auth keys are baked into the ISO.

## Build

On Linux/NixOS:

```bash
make public-check
make build-minimal
```

The ISO appears under `result/iso/`.

On macOS, run checks locally but build the ISO with GitHub Actions unless you
have a configured Linux builder:

```bash
make public-check
```

Then open GitHub → Actions → "Build ISO" → Run workflow. Download the
`runmeHaNix-iso` artifact when the workflow completes.

## Test in QEMU

```bash
make test-minimal
```

## Install flow

The installer asks for:

- disk
- hostname
- username, default `hanix-user`
- SSH public key source
  - GitHub username lookup is recommended
  - manual paste is available
  - file import is available
- optional Tailscale auth key, entered silently

GitHub username lookup fetches public keys from:

```text
https://github.com/<username>.keys
```

No GitHub login or token is needed.

## Write USB

Linux or macOS:

```bash
make write-usb
```

Build then write:

```bash
make build-and-write-usb
```

The script shows disks and requires explicit confirmation before writing.
