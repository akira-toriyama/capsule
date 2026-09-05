#!/usr/bin/env bash
# capsule driver: halo — hug-proof by frame math + hot-reload.
#
# Sourced by verify.sh, which has already cloned a consented VM, shared
# the host-signed Halo.app read-only, and installed fixtures/halo-hug.toml
# at ~/.config/halo/config.toml. Everything below runs on the HOST
# through verify.sh's helpers.
#
# halo draws its ring with Core Graphics — no AX text exists anywhere
# in the app — but the overlay is a real NSWindow whose FRAME is
# deterministic: the hugged window's rect expanded by glowPad = 24 pt
# per side (a compile-time constant — `RingGeometry.glowPad`, applied by
# `RingGeometry.overlayFrame(hugging:screenHeight:)` in
# HaloCore/RingGeometry.swift). Two gates:
#   1. hug-proof     — overlay frame == Calculator frame + 48 in both
#      dimensions. Calculator is the hug target: fixed-size,
#      dialog-free, present on every macOS.
#   2. config-proof  — flip the fixture's [exclude].apps to Calculator
#      inside the guest; halo's 0.4 s mtime poll must drop the overlay
#      (AXWindow gone from the dump). Only a daemon reading OUR file
#      at OUR path reacts to that edit.

# win_wh <dumpfile> — echo "W H" of the first AXWindow line, or fail.
win_wh() {
  awk '/^ *AXWindow/ {
    if (match($0, /[0-9]+x[0-9]+$/)) {
      split(substr($0, RSTART, RLENGTH), d, "x"); print d[1], d[2]; exit 0
    }
  }' "$1" | grep . || return 1
}

drive() {
  # The hug target must exist BEFORE halo looks for a frontmost window.
  # `open` re-parents Calculator to launchd, which is fine — Calculator
  # holds no grants; only halo must stay an SSH child.
  vmsh 'open -a Calculator' || { fail "could not open Calculator"; return 1; }
  wait_proc "Calculator" || { fail "Calculator never started"; return 1; }
  sleep 2

  launch_and_wait "/Contents/MacOS/halo" "halo" || return 1

  # SkyLight subscription + first update tick; poll for the overlay
  # window rather than trusting one fixed sleep.
  local cw ch hw hh
  if ! ax_wait halo halo-ax 10 '^ *AXWindow'; then
    app_log >"$ART/app.log"
    fail "halo never showed its overlay window (see $ART/halo-ax.txt, $ART/app.log)"
    return 1
  fi
  app_log >"$ART/app.log"

  ax_dump Calculator calc-ax || {
    fail "capsule-ax-dump Calculator failed (see $ART/calc-ax.err)"
    return 1
  }
  read -r cw ch < <(win_wh "$ART/calc-ax.txt") || {
    fail "no Calculator AXWindow frame to measure against (see $ART/calc-ax.txt)"
    return 1
  }
  read -r hw hh < <(win_wh "$ART/halo-ax.txt")
  # glowPad = 24 per side -> +48 exactly; ±2 absorbs AX rounding.
  local dw=$((hw - cw - 48)) dh=$((hh - ch - 48))
  if [ "${dw#-}" -gt 2 ] || [ "${dh#-}" -gt 2 ]; then
    fail "overlay is not hugging Calculator: halo ${hw}x${hh} vs calc ${cw}x${ch} (want +48/+48)"
    return 1
  fi
  say "overlay hugs Calculator — ${cw}x${ch} ringed at ${hw}x${hh} (+48/+48)"

  # Pixel tier first, while the ring is still up.
  snap_bonus halo-hug

  # Hot-reload config-proof: exclude Calculator in the guest copy; the
  # 0.4 s mtime poll must order the overlay out.
  vmsh 'sed -i "" "s/^apps = \[\]/apps = [\"com.apple.calculator\"]/" ~/.config/halo/config.toml'
  ax_wait halo halo-ax-excluded 5 ! '^ *AXWindow' || {
    fail "overlay survived the exclude edit — halo is not reading the fixture path (see $ART/halo-ax-excluded.txt)"
    return 1
  }
  say "exclude edit dropped the overlay — halo live-reads the fixture"

  vm pkill -f "/Contents/MacOS/halo" >/dev/null 2>&1 || true
  vm pkill -x Calculator >/dev/null 2>&1 || true
  return 0
}
