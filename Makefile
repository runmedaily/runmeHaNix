.PHONY: help build-minimal test-minimal clean write-usb build-and-write-usb public-check lock

help:
	@echo "runmeHaNix public ISO toolkit"
	@echo ""
	@echo "Targets:"
	@echo "  make public-check        - run public safety/eval checks"
	@echo "  make lock                - generate/update flake.lock"
	@echo "  make build-minimal       - build the bootstrap ISO"
	@echo "  make test-minimal        - boot ISO in QEMU"
	@echo "  make write-usb           - write built ISO to USB (Linux/macOS)"
	@echo "  make build-and-write-usb - build ISO, then write USB"
	@echo "  make clean               - remove build/test artifacts"

build-minimal:
	@echo "Building runmeHaNix minimal ISO..."
	nix build .#nixosConfigurations.iso-minimal.config.system.build.isoImage
	@echo "ISO output: result/iso/"

lock:
	nix flake lock

UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	QEMU_ACCEL =
	QEMU_CPU = -cpu max
	QEMU_DISPLAY = -display cocoa
else
	QEMU_ACCEL = -enable-kvm
	QEMU_CPU = -cpu host
	QEMU_DISPLAY =
endif

test-minimal: test-disk.qcow2
	@if [ ! -d result/iso ]; then echo "No ISO found. Run make build-minimal first."; exit 1; fi
	@if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then echo "qemu-system-x86_64 not found"; exit 1; fi
	qemu-system-x86_64 \
		$(QEMU_ACCEL) \
		-m 8G \
		-smp 2 \
		$(QEMU_CPU) \
		-boot once=d \
		-cdrom result/iso/*.iso \
		-drive file=test-disk.qcow2,if=virtio,format=qcow2 \
		-net nic -net user \
		$(QEMU_DISPLAY)

test-disk.qcow2:
	qemu-img create -f qcow2 test-disk.qcow2 20G

write-usb:
	@./scripts/write-usb.sh

build-and-write-usb: build-minimal write-usb

public-check:
	@echo "==> Checking for private strings"
	@! grep -RInE 'PRIVATE KEY|BEGIN OPENSSH|tskey-auth-[A-Za-z0-9]|tskey-api-[A-Za-z0-9]|op://|bash-nash-forgejo|tupai-w23|nixos_custom_iso|/home/spellcaster|forgejo|Employee|Home programming|runmeDrop|git\+ssh|path:/' . \
		--exclude-dir=.git --exclude=flake.lock --exclude=Makefile --exclude='*.org' || \
		{ echo "Public check failed: private-looking string found"; exit 1; }
	@echo "==> Checking suspicious tracked files"
	@if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
		! git ls-files | grep -E 'deploy-key|authkey|token|secret|hosts.toml|tailnet|hardware-configuration|\.env' || \
		{ echo "Public check failed: suspicious tracked file"; exit 1; }; \
	fi
	@echo "==> Bash syntax"
	@bash -n installer/install.sh
	@bash -n scripts/write-usb.sh
	@echo "==> Nix flake show"
	@nix flake show --allow-import-from-derivation >/dev/null
	@echo "==> ISO filename eval"
	@nix eval .#nixosConfigurations.iso-minimal.config.image.fileName --raw >/dev/null
	@echo "==> Demo HA stack eval"
	@test "$$(nix eval .#nixosConfigurations.demo-hanix.config.services.runme.home-assistant.enable --json)" = true
	@test "$$(nix eval .#nixosConfigurations.demo-hanix.config.services.runme.node-red.enable --json)" = true
	@test "$$(nix eval .#nixosConfigurations.demo-hanix.config.services.runme.homebridge.enable --json)" = true
	@echo "public-check passed"

clean:
	rm -rf result result-* test-disk.qcow2
