# QEMU smoke test

Use this before writing USB or asking someone else to test.

## macOS setup

Install QEMU:

```bash
brew install qemu
```

Download the latest GitHub-built ISO:

```bash
make download-iso
```

Boot it in QEMU:

```bash
make test-minimal
```

Notes:

- On macOS this is for smoke testing only.
- It boots the ISO and gives the installer a virtual disk.
- It does not make macOS able to build the Linux ISO locally.
- Linux ISO builds happen in GitHub Actions unless you have a Linux builder.

## What to verify

- ISO boots.
- Installer starts.
- Disk selection shows the QEMU virtual disk.
- SSH key prompt appears.
- Optional module selection appears.

You can quit QEMU after confirming the flow appears.
