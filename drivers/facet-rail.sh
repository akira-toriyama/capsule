#!/usr/bin/env bash
# capsule driver: facet — rail overlay env-proof.
#
# Sourced by verify.sh, which has already cloned a consented VM, shared
# the host-signed Facet.app read-only, and installed fixtures/facet-tree.toml
# as the guest's ~/.config/facet/config.toml. Everything below runs on the
# HOST through verify.sh's helpers.
#
# Same two-mode binary as the tree driver: the server is launched as an
# SSH child, and `facet --view rail` is a client-mode post over the DNC —
# fire-and-forget, idempotent, so the poll re-sends it each round. The
# rail names its strip cells `index (label)` ("1 (Alpha)"), unlike the
# tree's `WORKSPACE · ALPHA` headings — so a `(Alpha)` match proves the
# RAIL rendered the fixture, not that the tree happened to be up.
#
# Presence, never count: with an EVEN workspace count and every cell
# shown, the rail draws the far-left cell again at the far right as a
# wrap ghost (FacetViewRail/RailMath.swift, "both-ends peek symmetry"),
# so this two-workspace fixture lists "2 (Beta)" twice by design.

drive() {
  launch_and_wait "/Contents/MacOS/facet" "facet server" || return 1
  sleep 3
  app_log >"$ART/app.log"

  local ok=""
  for _ in $(seq 1 10); do
    vm "$GUEST_APP/Contents/MacOS/facet" --view rail
    ax_wait facet rail-ax 1 '(Alpha)' && { ok=1; break; }
  done
  if [ -z "$ok" ]; then
    app_log >"$ART/app.log"
    fail "rail never showed the fixture workspaces (see $ART/rail-ax.txt, $ART/app.log)"
    return 1
  fi

  assert_labels "$ART/rail-ax.txt" "rail is missing fixture workspaces" \
    '(Alpha)' '(Beta)' || return 1
  say "rail open — AX lists strip cells (Alpha) / (Beta)"

  snap_bonus facet-rail

  vm pkill -f "/Contents/MacOS/facet" >/dev/null 2>&1 || true
  return 0
}
