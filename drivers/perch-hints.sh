#!/usr/bin/env bash
# capsule driver: perch — hint-proof through perch's own AX reader.
#
# Sourced by verify.sh, which has already cloned a consented VM, shared
# the host-signed Perch.app read-only, and installed
# fixtures/perch-hints.toml at ~/.config/perch/config.toml. Everything
# below runs on the HOST through verify.sh's helpers.
#
# perch's pills are pixels (no AX text of their own), but its core is
# an AX READER, and `perch ax --dump` runs that reader standalone,
# loading the config fresh per invocation. Four gates:
#   1. daemon-proof — the server starts and logs "controller: started".
#   2. reader-proof — `ax --dump` with Calculator frontmost lists its
#      buttons through perch's own AXSource (labels "1"…"9"): the
#      wrapper AX grant armed perch's walker.
#   3. config-proof — sed [behavior].roles to ["Slider"] in the guest,
#      re-dump: "found 0 labelable" can only come from perch re-reading
#      OUR file at OUR path (Calculator has no sliders).
#   4. overlay-proof — `overlay --activate` round-trips the DNC control
#      channel: the log records the receipt and N hint(s), and must NOT
#      record a keytap-install failure (the tap is the TCC-gated part).

PERCH="" # set in drive() — $GUEST_APP is not bound at source time

drive() {
  PERCH="$GUEST_APP/Contents/MacOS/perch"

  # Frontmost target first: the dump and the overlay both read
  # whatever is frontmost, and a bare desktop labels nothing.
  vmsh 'open -a Calculator' || { fail "could not open Calculator"; return 1; }
  wait_proc "Calculator" || { fail "Calculator never started"; return 1; }
  sleep 2

  launch_app >/dev/null
  wait_proc "/Contents/MacOS/perch" || {
    app_log >"$ART/app.log"
    fail "perch daemon did not start (see $ART/app.log)"
    return 1
  }
  sleep 3
  app_log >"$ART/app.log"
  grep -q "controller: started" "$ART/app.log" || {
    fail "daemon never logged 'controller: started' (see $ART/app.log)"
    return 1
  }

  # Reader-proof. Structure, not titles: Calculator's SwiftUI buttons
  # expose NO title through perch's label extraction (measured
  # 2026-08-04 — 21 Buttons, every one "<no title>"), and perch's own
  # pill letters come from [labels].alphabet anyway. The proof is the
  # dump addressing com.apple.calculator and enumerating a
  # keypad-sized set of Buttons; the roles flip below is what makes
  # the count attributable to OUR config. First dump after boot can
  # lag while Calculator finishes rendering, so poll.
  local n=0
  for _ in $(seq 1 10); do
    sleep 2
    vm "$PERCH" ax --dump >"$ART/ax-dump.txt" 2>"$ART/ax-dump.err" || continue
    n="$(sed -n 's/^found \([0-9]*\) labelable.*/\1/p' "$ART/ax-dump.txt")"
    [ -n "$n" ] && [ "$n" -ge 10 ] && break
    n=0
  done
  if [ "$n" -lt 10 ]; then
    fail "perch's AX reader never enumerated Calculator's keypad (found ${n:-0}; see $ART/ax-dump.txt, $ART/ax-dump.err)"
    return 1
  fi
  grep -q "dump-ax → com.apple.calculator" "$ART/ax-dump.txt" || {
    fail "ax --dump read some other frontmost app (see $ART/ax-dump.txt)"
    return 1
  }
  say "reader-proof — perch's AXSource enumerates Calculator ($n Buttons)"

  # Overlay-proof BEFORE the config flip: the daemon read the fixture
  # at startup, and the flip below must not race the activation.
  vm "$PERCH" overlay --activate || {
    fail "overlay --activate refused (no daemon detected?)"
    return 1
  }
  ok=""
  for _ in $(seq 1 8); do
    sleep 2
    app_log >"$ART/app.log"
    grep -q "hint(s)" "$ART/app.log" && { ok=1; break; }
  done
  if grep -q "keytap install failed" "$ART/app.log"; then
    fail "overlay keytap refused — the wrapper grant did not arm perch's tap (see $ART/app.log)"
    return 1
  fi
  if [ -z "$ok" ]; then
    fail "overlay never reported hints (see $ART/app.log)"
    return 1
  fi
  local hints
  hints="$(grep -o '[0-9]* hint(s)' "$ART/app.log" | tail -1)"
  say "overlay-proof — DNC round trip, $hints over Calculator"

  # Pixel tier while the pills are up: a bonus, never the gate.
  snap perch-hints && say "captured $ART/perch-hints.png" \
                   || say "screenshot unavailable (bonus tier — not a failure)"
  vm "$PERCH" overlay --cancel >/dev/null 2>&1 || true

  # Config-proof: Calculator has no sliders, so a zero-count dump after
  # the flip can only mean perch re-read the edited fixture.
  vmsh 'sed -i "" "s/^roles = \[\"Button\"\]/roles = [\"Slider\"]/" ~/.config/perch/config.toml'
  vm "$PERCH" ax --dump >"$ART/ax-dump-slider.txt" 2>&1 || {
    fail "ax --dump failed after the roles flip (see $ART/ax-dump-slider.txt)"
    return 1
  }
  grep -q "found 0 labelable" "$ART/ax-dump-slider.txt" || {
    fail "roles flip did not change the dump — perch is not reading the fixture path (see $ART/ax-dump-slider.txt)"
    return 1
  }
  say "config-proof — roles flip zeroed the dump (perch re-reads the fixture)"

  vm pkill -f "/Contents/MacOS/perch" >/dev/null 2>&1 || true
  vm pkill -x Calculator >/dev/null 2>&1 || true
  return 0
}
