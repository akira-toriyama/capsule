#!/usr/bin/env bash
# capsule driver: facet — tree sidebar env-proof.
#
# Sourced by verify.sh, which has already cloned a consented VM, shared
# the host-signed Facet.app read-only, and installed
# fixtures/facet-tree.toml as the guest's ~/.config/facet/config.toml.
# Everything below runs on the HOST and reaches the guest through
# verify.sh's helpers (vm, vmsh, pb, ax_dump, snap, launch_app,
# wait_proc, app_log, fail, say).
#
# facet is a two-mode binary: no args = SERVER (agent-only, no panel),
# any recognised flag = CLIENT (posts a DistributedNotificationCenter
# control to the server, exits 0). launch_app starts the server as a
# direct child of the SSH session (inheriting the baked AX grant);
# summoning the tree is a second, client-mode invocation of the same
# shared binary.

drive() {
  launch_app >/dev/null
  wait_proc "/Contents/MacOS/facet" || {
    app_log >"$ART/app.log"
    fail "facet server did not start (see $ART/app.log)"
    return 1
  }
  # Let the server finish its first catalog build (config parse, AX
  # window adoption) before summoning a view.
  sleep 3
  app_log >"$ART/app.log"

  # Client mode posts over the DNC and exits 0 even with no listener,
  # so the summon itself proves nothing — the AX assert below does.
  vm "$GUEST_APP/Contents/MacOS/facet" --view tree

  # AX tier (the human-zero-forever signal). ax_dump walks the raw AX
  # tree via capsule-ax-dump — peekaboo's inspect-ui shows the SwiftUI
  # tree as ONE opaque childless element (the reason the helper exists;
  # see helpers/ax-dump.swift). The workspace rows surface as AXHeading
  # desc="WORKSPACE · ALPHA" — the label is small-caps-styled, so the
  # asserts match case-insensitively rather than encoding the styling.
  # First summon after boot can lag a beat, so poll for the label
  # instead of trusting one fixed sleep.
  local ok=""
  for _ in $(seq 1 10); do
    sleep 2
    ax_dump facet tree-ax || continue
    grep -qi "Alpha" "$ART/tree-ax.txt" && { ok=1; break; }
  done
  if [ -z "$ok" ]; then
    app_log >"$ART/app.log"
    fail "tree never showed the fixture workspaces (see $ART/tree-ax.txt, $ART/app.log)"
    return 1
  fi

  # Both fixture labels, not just the poll sentinel: one label present
  # + one missing would mean facet loaded SOME config but not ours.
  local missing=()
  for label in Alpha Beta; do
    grep -qi "$label" "$ART/tree-ax.txt" || missing+=("$label")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    fail "tree is missing fixture workspaces: ${missing[*]} (see $ART/tree-ax.txt)"
    return 1
  fi
  say "tree open — AX lists workspaces Alpha / Beta"

  # Pixel tier: a bonus. Screen Recording re-confirms ~monthly, so a
  # missing screenshot must never fail a run that AX already proved.
  snap facet-tree && say "captured $ART/facet-tree.png" \
                  || say "screenshot unavailable (bonus tier — not a failure)"

  vm pkill -f "/Contents/MacOS/facet" >/dev/null 2>&1 || true
  return 0
}
