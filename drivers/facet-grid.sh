#!/usr/bin/env bash
# capsule driver: facet — grid overlay env-proof.
#
# Sourced by verify.sh, which has already cloned a consented VM, shared
# the host-signed Facet.app read-only, and installed fixtures/facet-tree.toml
# as the guest's ~/.config/facet/config.toml. Everything below runs on the
# HOST through verify.sh's helpers.
#
# Same two-mode binary as the tree driver: the server is launched as an
# SSH child, and `facet --view grid` is a client-mode post over the DNC —
# fire-and-forget, idempotent, so the poll re-sends it each round. The
# grid names its cells `index (label)` ("1 (Alpha)"), unlike the tree's
# `WORKSPACE · ALPHA` headings, and its cells sit under an
# `AXOpaqueProviderGrid` container (measured 2026-09-05) — so the assert
# proves the GRID rendered the fixture, not that the tree happened to be
# up.

drive() {
  launch_and_wait "/Contents/MacOS/facet" "facet server" || return 1
  sleep 3
  app_log >"$ART/app.log"

  local ok=""
  for _ in $(seq 1 10); do
    vm "$GUEST_APP/Contents/MacOS/facet" --view grid
    ax_wait facet grid-ax 1 '(Alpha)' && { ok=1; break; }
  done
  if [ -z "$ok" ]; then
    app_log >"$ART/app.log"
    fail "grid never showed the fixture workspaces (see $ART/grid-ax.txt, $ART/app.log)"
    return 1
  fi

  assert_labels "$ART/grid-ax.txt" "grid is missing fixture workspaces" \
    AXOpaqueProviderGrid '(Alpha)' '(Beta)' || return 1
  say "grid open — AXOpaqueProviderGrid lists cells (Alpha) / (Beta)"

  snap_bonus facet-grid

  vm pkill -f "/Contents/MacOS/facet" >/dev/null 2>&1 || true
  return 0
}
