#!/usr/bin/env bash
# provision/20 — deterministic single display. A fixed 1024×768 makes
# every window/click coordinate reproducible session-to-session and
# removes the multi-display non-determinism that broke host verification
# (a window opened at x=3376 on a second display; peekaboo couldn't find
# it; osascript activate flew the Space).
#
# Tart sets the guest resolution at run time (1024×768 is the default),
# so this is a guard/record only. The consent script and the verify
# drivers assume the 2048×1536 VNC framebuffer (1024×768 @2x) — if this
# ever prints something else, their coordinates are invalid.
set -euo pipefail

echo "capsule: expecting a single 1024x768 display for deterministic coords"
system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Resolution|Main Display" || true
