#!/usr/bin/env bash
# capsule/verify.sh — the DAILY loop: clone a fresh ephemeral VM from the
# baked base, share the host-built product read-only, drive the GUI
# headlessly, capture the result, and destroy the clone.
#
#   usage: ./verify.sh <base-image> <profile.toml>
#
# STATUS: WIP skeleton. The end-to-end loop has NOT been proven in a
# clone yet — the headless-WindowServer observability leg (does a
# non-activating NSPanel screenshot cleanly under --no-graphics?) is the
# open risk the bring-up gate exists to settle. See docs/design.md.
set -euo pipefail

BASE="${1:?usage: verify.sh <base-image> <profile.toml>}"
PROFILE="${2:?usage: verify.sh <base-image> <profile.toml>}"

# A clone/pull must never auto-prune the OCI cache and evict other VMs.
export TART_NO_AUTO_PRUNE=1

EPHEMERAL="capsule-run-$$"

cleanup() { tart delete "$EPHEMERAL" 2>/dev/null || true; }
trap cleanup EXIT

echo "capsule: cloning $BASE -> $EPHEMERAL (APFS copy-on-write)"
tart clone "$BASE" "$EPHEMERAL"

# TODO(gate): parse $PROFILE for the worktree, build/fixture, driver.
#   1. build the product on the HOST (native arm64, signed with the
#      persistent cert so the baked AX grant matches — NEVER ship a raw
#      `swift build` binary: ad-hoc re-signing drops the grant).
#   2. tart run --no-graphics \
#        --dir=product:<worktree>/.build:ro \
#        --dir=app:<worktree>/<App>.app:ro "$EPHEMERAL" &
#   3. wait for boot (see condition-wait skill / `tart ip`).
#   4. drive: helpers/click (middle-click) + peekaboo see/image.
#   5. assert: no consent prompt, no tapCreate failure, panel visible in
#      the AX tree; screenshot is a within-window bonus, AX is the
#      human-zero-forever signal (Screen Recording re-confirms ~monthly).
echo "capsule: WIP — driver not wired yet (bring-up gate, projects/t-8ffm)" >&2
exit 3
