#!/usr/bin/env bash
# capsule driver: facet — isolate-desktop gate (tree only; grid / rail refused).
#
# Sourced by verify.sh, which has already cloned a consented VM, shared
# the host-signed Facet.app read-only, and installed
# fixtures/facet-isolate.toml as the guest's ~/.config/facet/config.toml.
# Everything below runs on the HOST through verify.sh's helpers.
#
# Three facts, in dependency order:
#   1. config-proof   — `--view tree` renders the isolate desktop's
#      synthesized section under the fixture's label (the AX dump reads
#      `MATCHED · ISOLATE`, measured 2026-09-05), so facet loaded THIS
#      config as an isolate desktop (a dropped isolate table would fall
#      back to five unnamed workspaces and never refuse anything).
#   2. refusal-proof  — `--view grid` and `--view rail` each log
#      `error: <view> view is not available on an isolate desktop (tree
#      only)` (FacetCore/IsolateDesktopGate.viewRefusal). The client
#      exits 0 either way, so the LOG is the witness, not the exit code.
#   3. no-render      — after both refusals the AX dump still carries no
#      `index (label)` cell: nothing was drawn behind the refusal.

drive() {
  launch_and_wait "/Contents/MacOS/facet" "facet server" || return 1
  sleep 3
  app_log >"$ART/app.log"

  local ok=""
  for _ in $(seq 1 10); do
    vm "$GUEST_APP/Contents/MacOS/facet" --view tree
    ax_wait facet tree-ax 1 -i "Isolate" && { ok=1; break; }
  done
  if [ -z "$ok" ]; then
    app_log >"$ART/app.log"
    fail "tree never showed the isolate section (see $ART/tree-ax.txt, $ART/app.log)"
    return 1
  fi
  say "config-proof — tree renders the isolate desktop's section"

  local view
  for view in grid rail; do
    vm "$GUEST_APP/Contents/MacOS/facet" --view "$view"
    sleep 2
  done
  app_log >"$ART/app.log"
  assert_labels "$ART/app.log" "isolate desktop did not refuse" \
    'error: grid view is not available on an isolate desktop (tree only)' \
    'error: rail view is not available on an isolate desktop (tree only)' || return 1
  say "refusal-proof — grid and rail both refused (tree only)"

  ax_dump facet after-ax || { fail "capsule-ax-dump facet failed (see $ART/after-ax.err)"; return 1; }
  if grep -q '(Isolate)' "$ART/after-ax.txt"; then
    fail "a grid/rail cell rendered despite the refusal (see $ART/after-ax.txt)"
    return 1
  fi
  say "no-render — no grid/rail cell behind the refusal"

  snap_bonus facet-isolate

  vm pkill -f "/Contents/MacOS/facet" >/dev/null 2>&1 || true
  return 0
}
