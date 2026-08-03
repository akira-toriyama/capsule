#!/usr/bin/env bash
# provision/10 — toolchain. NOT part of the core bake: the 2026-08-03
# gate proved the verify loop needs no guest toolchain (apps build on
# the host and arrive over a read-only share; JSON parsing happens on
# the host — invoking python3/swift in a toolchain-free guest pops the
# CLT install dialog). Run this only for a per-app profile that truly
# needs in-VM `swift build`/`swift test`.
set -euo pipefail

# CommandLineTools is enough for `swift build`. Pin it so a reboot can't
# drift `xcode-select` back to a different toolchain (the t-mjv7 trap).
if [ -d /Library/Developer/CommandLineTools ]; then
  sudo xcode-select -s /Library/Developer/CommandLineTools
fi
swift --version || { echo "no swift toolchain" >&2; exit 1; }

# peekaboo = the GUI-verification harness (screenshot + AX + click/type).
# brew is fine here: peekaboo is third-party. The source-over-brew rule
# binds only akira-toriyama's own CLIs.
command -v peekaboo >/dev/null 2>&1 || brew install peekaboo || true

# OPTIONAL (per-profile): `xcodes install <ver>` for in-VM `swift test`.
# GUI checks need no Xcode in the guest at all — the core bake ships no
# toolchain and apps are built on the host (docs/design.md §Bake result).
