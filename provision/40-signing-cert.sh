#!/usr/bin/env bash
# provision/40 — wand's persistent signing cert. TCC keys an app's
# Accessibility grant to its code-signing identity, so a stable
# self-signed cert (not ad-hoc) is what lets the baked AX grant survive
# every rebuild. wand already ships the generator; capsule just runs it
# inside the VM and never commits the key material (see .gitignore).
#
# STATUS: WIP skeleton — not yet run inside a bake.
set -euo pipefail

WAND="${WAND_SRC:-/Volumes/workspace/github.com/akira-toriyama/wand}"

if [ -x "$WAND/setup-signing-cert.sh" ]; then
  # Creates the "wand Local Signing" cert in the login keychain (a
  # password-bound software key — survives clone). package.sh then signs
  # Wand.app with it; the harness drives THAT bundle, never a raw
  # `swift build` binary (ad-hoc re-signing would drop the grant).
  "$WAND/setup-signing-cert.sh"
else
  echo "capsule: wand setup-signing-cert.sh not found at $WAND" >&2
  echo "         (rsync/clone wand into the VM first, or set WAND_SRC)" >&2
  exit 3
fi
