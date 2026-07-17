#!/usr/bin/env bash
# provision/10 — toolchain. First-users need only `swift build` (CLT);
# tests are CI-covered, so Xcode is a per-app OPTIONAL, not core.
#
# STATUS: WIP skeleton — not yet run inside a bake.
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
# The existing sill-focusprobe VM ran GUI checks fine with "Xcode無".
