#!/usr/bin/env bash
# provision/20 — deterministic single display. A fixed 1024×768 makes
# every window/click coordinate reproducible session-to-session and
# removes the multi-display non-determinism that broke host verification
# (a window opened at x=3376 on a second display; peekaboo couldn't find
# it; osascript activate flew the Space).
#
# STATUS: WIP skeleton — not yet run inside a bake.
set -euo pipefail

# Tart sets the guest resolution at run time (`tart run
# --display=1024x768` / the default), so this is mostly a guard/record.
# All three hand-made VMs already standardized on 1024×768.
echo "capsule: expecting a single 1024x768 display for deterministic coords"
peekaboo list screens --json 2>/dev/null || true
