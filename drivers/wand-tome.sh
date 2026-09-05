#!/usr/bin/env bash
# capsule driver: wand — tome panel env-proof.
#
# Sourced by verify.sh, which has already cloned a consented VM, shared
# the host-signed Wand.app read-only, and installed fixtures/wand-tome.toml
# as the guest's ~/.config/wand/config.toml. Everything below runs on the
# HOST and reaches the guest through verify.sh's helpers (vm, pb, click,
# launch_and_wait, ax_dump, assert_labels, snap_bonus, app_log, fail, say).
#
# This is the ENV-PROOF: it re-runs the 2026-08-03 bring-up gate through
# the automated loop — middle-click opens the tome, the AX tree lists the
# fixture rows.

# The tome anchors on the cursor, and the fixture uses apps = ["*"], so
# the middle of the deterministic 1024x768 display is a valid anchor.
TOME_X=512
TOME_Y=384

drive() {
  launch_and_wait "/Contents/MacOS/wand" "wand" || return 1
  # The daemon installs its event tap during startup; the tap verdict is
  # a log line, so the log is read only after startup has had a beat.
  sleep 3
  app_log >"$ART/app.log"

  # The signed-bundle invariant, asserted rather than assumed: an ad-hoc
  # re-signed binary loses the baked AX grant and the tap refuses to open.
  if grep -q "tapCreate failed" "$ART/app.log"; then
    fail "event tap refused — the baked AX grant did not apply to this bundle"
    return 1
  fi

  click "$TOME_X" "$TOME_Y" middle
  sleep 2

  # AX tier (the human-zero-forever signal). ax_dump raw-walks the AX
  # tree via capsule-ax-dump: peekaboo's `see --app` cannot target the
  # tome (non-activating NSPanel, layer != 0, filtered out of its
  # window pipeline), and its inspect-ui is blind to SwiftUI subtrees
  # elsewhere in the family — one walker covers both.
  ax_dump Wand tome-ax || { fail "capsule-ax-dump Wand failed (see $ART/tome-ax.err)"; return 1; }

  # Match the fixture's labels in the rendered element listing, not the
  # JSON shape: peekaboo's schema is not a contract, the fixture is.
  assert_labels "$ART/tome-ax.txt" "tome panel is missing fixture rows" \
    '"Alpha"' '"Beta"' '"Sort"' || return 1
  say "tome panel open — AX lists Alpha / Beta / Sort"

  snap_bonus tome-panel

  vm pkill -f "/Contents/MacOS/wand" >/dev/null 2>&1 || true
  return 0
}
