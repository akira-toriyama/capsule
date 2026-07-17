#!/usr/bin/env bash
# capsule/bake.sh — RARE, LOCAL bake: turn the recipe into a baked base
# image cached in ~/.tart. Runs on the host Mac (baking is not
# host-disruptive: packer provisions inside an isolated VM over SSH and
# never touches host apps).
#
#   usage: ./bake.sh <vanilla-base> <output-image-name>
#
# STATUS: WIP skeleton. `packer` is not installed yet
# (`brew install packer`), so this has never run. The persistent signing
# cert and the AX + Screen-Recording TCC grants are baked by the ONE
# human touch documented in provision/30-tcc-consent.md (all in-VM
# consent is pre-authorized). See docs/design.md.
set -euo pipefail

BASE="${1:?usage: bake.sh <vanilla-base> <output-image-name>}"
OUT="${2:?usage: bake.sh <vanilla-base> <output-image-name>}"

export TART_NO_AUTO_PRUNE=1

command -v packer >/dev/null 2>&1 || {
  echo "bake: packer not installed — run 'brew install packer' first" >&2
  echo "      (packer is third-party HashiCorp; brew is fine here — the" >&2
  echo "       source-over-brew rule binds only akira-toriyama's own CLIs)" >&2
  exit 3
}

echo "capsule: baking $OUT from $BASE"
# Canonical cirruslabs pipeline: pull vanilla -> packer build (bakes) ->
# result is a local VM in ~/.tart. Distribution (if ever needed) is a
# separate `make export` -> .tvm, never a default `tart push`.
tart pull "$BASE"
packer init  packer/base.pkr.hcl
packer build -var "vm_base_name=${BASE}" -var "vm_name=${OUT}" packer/base.pkr.hcl

# The interactive TCC consent (AX + Screen Recording) is a manual boot
# step BEFORE the snapshot — see provision/30-tcc-consent.md. sqlite3
# pre-seed needs SIP off (base image is SIP-on) and MDM/PPPC needs a
# supervised device, so bake-by-in-VM-consent is the only viable path.
echo "capsule: baked $OUT — remember the one-time TCC consent (provision/30-tcc-consent.md)"
