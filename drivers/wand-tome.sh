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
# fixture rows — then the wand#128 gate: right-click a row, the themed
# context menu lists Delete, clicking it drops that row (and only that
# row) from the live panel.

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

  # wand#128 — row context menu. Coordinates come from the AX listing
  # itself (`… value="Alpha" at (x,y) wxh`), never from the fixture: the
  # panel anchors on the cursor and its rows lay out from the font size,
  # so a hard-coded offset would silently drift with either.
  local alpha
  alpha=$(ax_frame "$ART/tome-ax.txt" '"Alpha"') || { fail "Alpha row has no AX frame (see $ART/tome-ax.txt)"; return 1; }
  click $(ax_centre "$alpha") right
  sleep 2
  ax_dump Wand tome-ax-menu || { fail "capsule-ax-dump Wand failed after right-click (see $ART/tome-ax-menu.err)"; return 1; }
  assert_labels "$ART/tome-ax-menu.txt" "row context menu did not open (wand#128)" \
    '"Delete"' || return 1
  say "row context menu open — AX lists Delete"
  snap_bonus tome-context-menu

  local delete
  delete=$(ax_frame "$ART/tome-ax-menu.txt" '"Delete"') || { fail "Delete entry has no AX frame (see $ART/tome-ax-menu.txt)"; return 1; }
  click $(ax_centre "$delete") left
  sleep 2
  ax_dump Wand tome-ax-after || { fail "capsule-ax-dump Wand failed after Delete (see $ART/tome-ax-after.err)"; return 1; }
  if grep -q '"Alpha"' "$ART/tome-ax-after.txt"; then
    fail "Alpha is still listed after Delete (see $ART/tome-ax-after.txt)"
    return 1
  fi
  assert_labels "$ART/tome-ax-after.txt" "Delete took rows other than Alpha with it" \
    '"Beta"' '"Sort"' || return 1
  say "Delete hid Alpha — AX lists Beta / Sort only"
  snap_bonus tome-after-delete

  vm pkill -f "/Contents/MacOS/wand" >/dev/null 2>&1 || true
  return 0
}

# ax_frame <ax-listing> <label> -> "x y w h" of the first element whose line
# carries <label> and a frame; exit 1 when none does.
ax_frame() {
  grep -m1 -- "$2" "$1" | sed -nE 's/.* at \(([0-9]+),([0-9]+)\) ([0-9]+)x([0-9]+).*/\1 \2 \3 \4/p' | grep .
}

# ax_centre "x y w h" -> "cx cy" (integer centre of the frame).
ax_centre() {
  local x y w h
  read -r x y w h <<<"$1"
  echo "$((x + w / 2)) $((y + h / 2))"
}
