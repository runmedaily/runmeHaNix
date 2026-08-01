#!/usr/bin/env bash
# Download the latest published runmeHaNix ISO release.

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'
info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok() { echo -e "${GREEN}[OK]${NC} $*"; }
err() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT/downloads"
ISO="$OUT_DIR/runmeHaNix-latest.iso"
URL="https://github.com/runmedaily/runmeHaNix/releases/download/latest/runmeHaNix-latest.iso"

mkdir -p "$OUT_DIR"

info "Downloading latest runmeHaNix ISO..."
info "$URL"

if command -v curl >/dev/null 2>&1; then
  curl -L --fail --continue-at - --progress-bar -o "$ISO.tmp" "$URL"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$ISO.tmp" "$URL"
else
  err "Need curl or wget to download the ISO"
  exit 1
fi

mv "$ISO.tmp" "$ISO"
ok "Downloaded: $ISO"
ls -lh "$ISO"
