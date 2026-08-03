#!/usr/bin/env bash
# capsule driver: wand — tome panel env-proof.
#
# Sourced by verify.sh, which has already cloned a consented VM, shared
# the host-signed Wand.app read-only, and installed fixtures/wand-tome.toml
# as the guest's ~/.config/wand/config.toml. Everything below runs on the
# HOST and reaches the guest through verify.sh's helpers (vm, pb, click,
# ax_dump, snap, launch_app, wait_proc, app_log, fail, say).
#
# This is the ENV-PROOF: it re-runs the 2026-08-03 bring-up gate through
# the automated loop — middle-click opens the tome, the AX tree lists the
# fixture rows. The t-k4hf delete acceptance (right-click a row → Delete →
# prune / dismiss / neon / line-pets) extends this driver; it is not here
# yet because it needs the unpushed wand branch.

# The tome anchors on the cursor, and the fixture uses apps = ["*"], so
# the middle of the deterministic 1024x768 display is a valid anchor.
TOME_X=512
TOME_Y=384

drive() {
  launch_app >/dev/null
  wait_proc "/Contents/MacOS/wand" || {
    app_log >"$ART/app.log"
    fail "wand did not start (see $ART/app.log)"
    return 1
  }
  # The daemon installs its event tap during startup; give it a beat and
  # then read the log rather than guessing from a fixed sleep.
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

  # AX tier (the human-zero-forever signal). `see --app` cannot target
  # the tome: it is a non-activating NSPanel at layer != 0, which
  # peekaboo's window pipeline filters out — inspect-ui reads it fine.
  ax_dump Wand tome-ax || { fail "inspect-ui --app Wand failed (see $ART/tome-ax.err)"; return 1; }

  # Match the fixture's labels in the rendered element listing, not the
  # JSON shape: peekaboo's schema is not a contract, the fixture is.
  local missing=()
  for row in Alpha Beta Sort; do
    grep -q "\"$row\"" "$ART/tome-ax.txt" || missing+=("$row")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    fail "tome panel is missing fixture rows: ${missing[*]} (see $ART/tome-ax.txt)"
    return 1
  fi
  say "tome panel open — AX lists Alpha / Beta / Sort"

  # Pixel tier: a bonus. Screen Recording re-confirms ~monthly, so a
  # missing screenshot must never fail a run that AX already proved.
  snap tome-panel && say "captured $ART/tome-panel.png" \
                  || say "screenshot unavailable (bonus tier — not a failure)"

  vm pkill -f "/Contents/MacOS/wand" >/dev/null 2>&1 || true
  return 0
}
