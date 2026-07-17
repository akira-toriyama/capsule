# capsule — see docs/design.md for the WHY behind every target.
#
# Baking is RARE and LOCAL: GitHub-hosted CI cannot bake (Apple's
# Virtualization Framework nests Linux guests only, so a Tart macOS VM
# can't run on a hosted macOS runner). `make verify` is the DAILY op and
# is nearly free (APFS copy-on-write clone).

BASE    ?= ghcr.io/cirruslabs/macos-tahoe-base:latest   # macOS 26 = sill/wand floor
IMAGE   ?= capsule-base
PROFILE ?= wand

# A bare clone/pull auto-prunes the OCI cache (100 GB LRU) and could
# evict the hand-made VMs. Never let the loop do that.
export TART_NO_AUTO_PRUNE = 1

.PHONY: help bake verify export import
help:
	@echo "capsule targets:"
	@echo "  make bake                 # RARE/LOCAL: build the baked image from the recipe"
	@echo "  make verify PROFILE=wand  # DAILY: clone -> run --dir:ro -> drive -> delete"
	@echo "  make export / make import # move the image registry-free via a .tvm file"
	@echo "  (no 'push' target by design — see docs/design.md, tart#771)"

bake:            ## rare, local: recipe -> baked image (needs packer + one-time TCC consent)
	./bake.sh "$(BASE)" "$(IMAGE)"

verify:          ## daily: run the acceptance loop for PROFILE against a fresh clone
	./verify.sh "$(IMAGE)" "profiles/$(PROFILE).toml"

export:          ## move the image as a registry-free .tvm (AirDrop / USB / shared drive)
	tart export "$(IMAGE)" "$(IMAGE).tvm"

import:
	tart import "$(IMAGE).tvm" "$(IMAGE)"

# Deliberately NO `push` target: `tart push` re-uploads all ~27 GB on
# every change (no layer reuse — cirruslabs/tart#771). Distribute via
# `make export` -> .tvm, and reserve ghcr for a real remote peer only.
