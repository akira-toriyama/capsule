#!/usr/bin/env bash
# capsule driver: sill/prism — gallery AX-proof (the t-c4pv measurement).
#
# Sourced by verify.sh, which has already cloned a consented VM, shared
# the host-built Prism.app read-only, and installed
# fixtures/prism-gallery.toml at the guest path $PRISM_CONFIG points to.
# Everything below runs on the HOST through verify.sh's helpers.
#
# prism is a plain single-window gallery: launch it, wait for the
# window, and assert the AX dump. Two independent facts:
#   1. config-proof — the top bar shows the fixture's theme name
#      ("synthwave"; the default would be "dracula"), so prism parsed
#      OUR config.
#   2. SwiftUI-content-proof — the WidgetPage segmented control
#      (Overview | Specimens | API) is readable. This is t-c4pv's
#      headline: peekaboo saw ui_elements 0, so ANY readable SwiftUI
#      text here proves the raw walker closed the gap.

drive() {
  launch_app >/dev/null
  # Not "/Contents/Resources/…": the shim execs via "MacOS/../Resources",
  # and the un-normalized path IS the process's command line.
  wait_proc "Resources/bin/prism" || {
    app_log >"$ART/app.log"
    fail "prism did not start (see $ART/app.log)"
    return 1
  }
  app_log >"$ART/app.log"

  # First AX answer after launch can lag while the gallery builds its
  # cards, so poll for the config-proof label instead of one sleep.
  local ok=""
  for _ in $(seq 1 10); do
    sleep 2
    ax_dump prism gallery-ax || continue
    grep -q '"synthwave"' "$ART/gallery-ax.txt" && { ok=1; break; }
  done
  if [ -z "$ok" ]; then
    app_log >"$ART/app.log"
    fail "gallery never showed the fixture theme (see $ART/gallery-ax.txt, $ART/app.log)"
    return 1
  fi

  # All three segment labels, not just one: a partial page would mean
  # the window rendered but the WidgetPage did not.
  local missing=()
  for label in Overview Specimens API; do
    grep -q "\"$label\"" "$ART/gallery-ax.txt" || missing+=("$label")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    fail "widget page chrome missing: ${missing[*]} (see $ART/gallery-ax.txt)"
    return 1
  fi
  say "gallery open — AX reads theme 'synthwave' + WidgetPage chrome ($(wc -l <"$ART/gallery-ax.txt" | tr -d ' ') elements)"

  # Pixel tier: a bonus. Screen Recording re-confirms ~monthly, so a
  # missing screenshot must never fail a run that AX already proved.
  snap prism-gallery && say "captured $ART/prism-gallery.png" \
                     || say "screenshot unavailable (bonus tier — not a failure)"

  vm pkill -f "Resources/bin/prism" >/dev/null 2>&1 || true
  return 0
}
