#!/usr/bin/env bash
# capsule driver: facet — by-workspace degrade tree, header-drag escape band.
#
# Measures whether a workspace-header drag released ABOVE the first header
# commits a real workspace-content swap (projects t-dc2w). The swap branch of
# `resolveTreeDrop` kills only its END gap; the window branch kills both ends.
# Whether a pointer drag can actually reach the above-the-top placement is the
# open question — sill's ±32 pt tolerance band is what would map it onto the
# first section.
#
# Two phases, gated by DEGRADE_PHASE (default probe):
#   probe — launch, seed windows, summon the tree, dump AX + snap. No input.
#           Read the artifacts to learn the real header geometry.
#   drag  — the probe, then a peekaboo drag from a lower workspace header to a
#           point DEGRADE_DY pt above the first header's top edge, then a
#           second AX dump. The assert compares window membership across the
#           two dumps.
#
# Never a silent pass: an unparseable geometry fails loudly rather than
# aiming a drag at a guess and reporting "no commit" (that reads identical to
# the bug being absent).

PHASE="${DEGRADE_PHASE:-probe}"
DY="${DEGRADE_DY:-16}"

# Seed real windows so a committed swap has something to move: performSwap
# early-returns when BOTH workspaces are empty, so an empty tree cannot tell
# an abort apart from a no-op commit.
seed_windows() {
  vm mkdir -p /Users/admin/capsule-seed
  vmsh "printf 'red-1\n'  > /Users/admin/capsule-seed/red-1.txt"
  vmsh "printf 'blue-1\n' > /Users/admin/capsule-seed/blue-1.txt"
  vm open -a TextEdit /Users/admin/capsule-seed/red-1.txt
  sleep 2
  vm open -a TextEdit /Users/admin/capsule-seed/blue-1.txt
  sleep 3
}

summon_tree() {
  local ok=""
  for _ in $(seq 1 10); do
    vm "$GUEST_APP/Contents/MacOS/facet" --view tree
    sleep 2
    ax_dump facet "$1" || continue
    grep -qi "workspace" "$ART/$1.txt" && { ok=1; break; }
  done
  [ -n "$ok" ]
}

drive() {
  launch_app >/dev/null
  wait_proc "/Contents/MacOS/facet" || {
    app_log >"$ART/app.log"
    fail "facet server did not start (see $ART/app.log)"
    return 1
  }
  sleep 3

  seed_windows

  # The degrade tree must actually be the thing under test: a config that
  # accidentally kept a section would render `.sections` and the swap branch
  # would never run, making any verdict here meaningless.
  vm cat /Users/admin/.config/facet/config.toml >"$ART/guest-config.toml" 2>/dev/null || true
  # Uncommented lines only — the fixture's own prose names the very table it
  # must not declare, and a naive grep matches that comment (measured).
  if grep -vE '^\s*#' "$ART/guest-config.toml" 2>/dev/null \
       | grep -q '^\s*\[\[desktop\.[0-9]*\.section\]\]'; then
    fail "fixture declares a section — that renders .sections, not .degrade"
    return 1
  fi

  summon_tree tree-ax-before || {
    app_log >"$ART/app.log"
    fail "tree never rendered workspaces (see $ART/tree-ax-before.txt, $ART/app.log)"
    return 1
  }
  app_log >"$ART/app.log"
  snap facet-degrade-before \
    && say "captured $ART/facet-degrade-before.png" \
    || say "screenshot unavailable (bonus tier — not a failure)"

  say "probe: tree rendered in degrade mode — geometry in $ART/tree-ax-before.txt"
  [ "$PHASE" = "probe" ] && return 0

  # --- drag phase -----------------------------------------------------
  # Header rects come from the AX dump the probe just wrote. capsule-ax-dump
  # prints `… at (x,y) WxH`; the workspace headers are the AXHeading rows
  # whose desc carries the degrade's "workspace · N" label.
  # perl, not awk: macOS ships BSD awk, whose `match()` takes no capture-array
  # third argument, so the gawk idiom is a syntax error here.
  local geom
  geom="$(perl -ne '
    next unless /AXHeading/ && /workspace/i;
    print "$1 $2 $3 $4\n" if /at \(([-0-9.]+),\s*([-0-9.]+)\)\s*([0-9.]+)x([0-9.]+)/;
  ' "$ART/tree-ax-before.txt")"

  local n; n="$(printf '%s\n' "$geom" | grep -c . || true)"
  if [ "${n:-0}" -lt 2 ]; then
    fail "could not read >=2 workspace header rects from the AX dump (got ${n:-0}) — see $ART/tree-ax-before.txt"
    return 1
  fi
  printf '%s\n' "$geom" >"$ART/header-rects.txt"

  local fx fy fw fh sx sy sw sh
  read -r fx fy fw fh < <(printf '%s\n' "$geom" | sed -n '1p')
  read -r sx sy sw sh < <(printf '%s\n' "$geom" | sed -n '2p')

  # Source = the SECOND header (dragging the first onto itself resolves to
  # t == g and is rejected before the escape band is reached).
  local from_x from_y to_x to_y
  from_x="$(printf '%.0f' "$(echo "$sx + $sw / 2" | bc -l)")"
  from_y="$(printf '%.0f' "$(echo "$sy + $sh / 2" | bc -l)")"
  to_x="$from_x"
  to_y="$(printf '%.0f' "$(echo "$fy - $DY" | bc -l)")"

  say "drag: header2 ($from_x,$from_y) -> ($to_x,$to_y) = ${DY}pt above header1 top ($fy)"
  echo "from=($from_x,$from_y) to=($to_x,$to_y) header1_top=$fy dy=$DY" >"$ART/drag-aim.txt"

  pb drag --from-coords "$from_x,$from_y" --to-coords "$to_x,$to_y" \
          --duration 900 --steps 30 >"$ART/drag.out" 2>&1 \
    || say "peekaboo drag returned non-zero (see $ART/drag.out)"
  sleep 3

  ax_dump facet tree-ax-after || {
    fail "AX dump after the drag failed"
    return 1
  }
  app_log >"$ART/app-after.log"
  snap facet-degrade-after \
    && say "captured $ART/facet-degrade-after.png" \
    || say "screenshot unavailable (bonus tier — not a failure)"

  # The verdict is membership, not pixels: a committed swap moves the seeded
  # TextEdit rows from one workspace heading to the other. Report BOTH dumps
  # either way — this driver measures, it does not police.
  if diff -q "$ART/tree-ax-before.txt" "$ART/tree-ax-after.txt" >/dev/null 2>&1; then
    say "RESULT: tree unchanged after the above-the-top release — no swap committed"
  else
    say "RESULT: tree CHANGED after the above-the-top release — diff in $ART/tree-ax.diff"
    diff "$ART/tree-ax-before.txt" "$ART/tree-ax-after.txt" >"$ART/tree-ax.diff" 2>&1 || true
  fi
  grep -c "moveWindow" "$ART/app-after.log" 2>/dev/null \
    | sed 's/^/moveWindow log lines: /' | while read -r l; do say "$l"; done

  vm pkill -f "/Contents/MacOS/facet" >/dev/null 2>&1 || true
  return 0
}
