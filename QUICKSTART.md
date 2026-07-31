# Quickstart

```bash
git clone https://github.com/runmedaily/runmeHaNix
cd runmeHaNix
make public-check
```

Build options:

- Linux/NixOS: run `make build-minimal`.
- macOS: use GitHub Actions → "Build ISO" → Run workflow, unless you have a
  configured Linux builder.

After you have an ISO, run:

```bash
make write-usb
```

Boot the USB and follow the prompts.

Recommended SSH key setup before install:

1. Add your SSH public key to GitHub.
2. In the installer, choose GitHub username lookup.
3. Enter your GitHub username.

Tailscale is optional. If you paste an auth key, input is hidden.
