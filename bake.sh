#!/usr/bin/env bash
# capsule/bake.sh — RARE, LOCAL bake: turn the recipe into a baked,
# TCC-consented base image cached in ~/.tart. Runs on the host Mac and
# is not host-disruptive: packer provisions inside a headless VM over
# SSH, and the consent step drives the VM's screen over VNC — zero host
# windows end-to-end (gate-proven 2026-08-03, docs/design.md).
#
#   usage: ./bake.sh <vanilla-base> <output-image-name>
#
# Stages:
#   1. host prep — capsule SSH key, peekaboo location, compile click
#   2. packer build — ships binaries + pubkey into a fresh VM (headless)
#   3. provision/30-consent-core.sh — bakes the ssh-context TCC grants
#      (Accessibility + Screen Recording for sshd-keygen-wrapper) over
#      VNC, then shuts the VM down -> reusable consented base.
# Per-app grants (e.g. Wand's own AX) are a per-profile step, not core.
set -euo pipefail
cd "$(dirname "$0")"

BASE="${1:?usage: bake.sh <vanilla-base> <output-image-name>}"
OUT="${2:?usage: bake.sh <vanilla-base> <output-image-name>}"

export TART_NO_AUTO_PRUNE=1

command -v packer >/dev/null 2>&1 || {
  echo "bake: packer not installed — run 'brew install hashicorp/tap/packer'" >&2
  echo "      (packer is third-party HashiCorp; brew is fine here — the" >&2
  echo "       source-over-brew rule binds only akira-toriyama's own CLIs)" >&2
  exit 3
}

# --- 1. host prep ---------------------------------------------------

# Durable per-host keypair for driving capsule VMs (never in git).
KEYDIR="$HOME/.tart/capsule-ssh"
KEY="$KEYDIR/id_ed25519"
if [ ! -f "$KEY" ]; then
  mkdir -p "$KEYDIR"
  ssh-keygen -t ed25519 -N "" -C "capsule" -f "$KEY" -q
  echo "bake: generated capsule SSH key at $KEY"
fi
PUBKEY="$(cat "$KEY.pub")"

# peekaboo install dir on the host (whole dir → @rpath dylibs ride along).
PEEKABOO_BIN="$(command -v peekaboo)" || {
  echo "bake: peekaboo not found on host — brew install steipete/tap/peekaboo" >&2
  exit 3
}
PEEKABOO_DIR="$(dirname "$(dirname "$(readlink -f "$PEEKABOO_BIN")")")"

# Compile the middle-click helper on the HOST (guest has no toolchain).
mkdir -p .build
swiftc -O -o .build/capsule-click helpers/click.swift
echo "bake: compiled helpers/click.swift -> .build/capsule-click"

# --- 2. packer build ------------------------------------------------

echo "bake: baking $OUT from $BASE (headless — no host windows)"
tart pull "$BASE"
packer init packer/base.pkr.hcl
packer build \
  -var "vm_base_name=${BASE}" \
  -var "vm_name=${OUT}" \
  -var "ssh_pubkey=${PUBKEY}" \
  -var "peekaboo_dir=${PEEKABOO_DIR}" \
  -var "click_bin=.build/capsule-click" \
  packer/base.pkr.hcl

# --- 3. TCC consent (scripted, human-zero) --------------------------

./provision/30-consent-core.sh "$OUT" "$KEY"

echo "bake: DONE — $OUT is baked and consented. Daily loop: make verify"
