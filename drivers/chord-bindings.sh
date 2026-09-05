#!/usr/bin/env bash
# capsule driver: chord — daemon config-proof over the query socket.
#
# Sourced by verify.sh, which has already cloned a consented VM, shared
# the host-signed Chord.app read-only, and installed
# fixtures/chord-bindings.toml at ~/.config/chord/config.toml (the one
# path chord reads). Everything below runs on the HOST through
# verify.sh's helpers.
#
# chord is fully headless (LSUIElement, zero windows, zero AX surface),
# so neither ax_dump nor snap can gate — the daemon's own facts do.
# Three independent facts, weakest link first:
#   1. grant-proof  — `query --status` says ax_granted=true: the baked
#      sshd-keygen-wrapper responsibility armed chord's event tap, the
#      same mechanism wand's tap already proved.
#   2. count-proof  — `query --loaded-bindings` says bindings=2,
#      fallbacks=0: the daemon parsed OUR fixture (the shipped template
#      loads 0 — everything in it is commented out).
#   3. name-proof   — `config --show` prints capsule-alpha /
#      capsule-beta: the file at the daemon's config path is THIS
#      fixture, not some other two-binding config.

drive() {
  launch_and_wait "/Contents/MacOS/chord" "chord daemon" || return 1

  # The daemon exit(1)s without the AX grant, so surviving startup
  # already hints the grant applied — but poll the socket and let the
  # daemon SAY so instead of inferring from process liveness.
  local status=""
  for _ in $(seq 1 15); do
    sleep 2
    status="$(vm "$GUEST_APP/Contents/MacOS/chord" query --status 2>/dev/null)" && break
    status=""
  done
  app_log >"$ART/app.log"
  printf '%s\n' "$status" >"$ART/query-status.json"
  if [ -z "$status" ]; then
    fail "query socket never answered — daemon died or never listened (see $ART/app.log)"
    return 1
  fi
  jq -e '.ax_granted == true and .config_loaded_at != null' \
    >/dev/null <<<"$status" || {
    fail "daemon lacks the AX grant or never loaded config (see $ART/query-status.json)"
    return 1
  }

  local lb
  lb="$(vm "$GUEST_APP/Contents/MacOS/chord" query --loaded-bindings)"
  printf '%s\n' "$lb" >"$ART/query-loaded-bindings.json"
  jq -e '.bindings == 2 and .fallbacks == 0' >/dev/null <<<"$lb" || {
    fail "daemon did not load the fixture's 2 bindings (see $ART/query-loaded-bindings.json)"
    return 1
  }

  local show
  show="$(vm "$GUEST_APP/Contents/MacOS/chord" config --show)"
  printf '%s\n' "$show" >"$ART/config-show.txt"
  assert_labels "$ART/config-show.txt" "config --show is missing fixture bindings" \
    capsule-alpha capsule-beta || return 1

  # Belt and braces: the startup log line records dropped=0, so the
  # count of 2 is "2 parsed cleanly", not "2 survivors of 5".
  vm cat /tmp/chord.log >"$ART/chord.log" 2>/dev/null || true
  grep -q "dropped=0" "$ART/chord.log" || {
    fail "startup dropped bindings — the fixture did not parse cleanly (see $ART/chord.log)"
    return 1
  }

  say "daemon consented + fixture loaded — ax_granted, 2/0 bindings, names match"

  vm pkill -f "/Contents/MacOS/chord" >/dev/null 2>&1 || true
  return 0
}
