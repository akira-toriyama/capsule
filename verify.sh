#!/usr/bin/env bash
# capsule/verify.sh — the DAILY loop: build the product on the HOST,
# clone a fresh ephemeral VM from the baked base, share the signed
# bundle read-only, drive the GUI headlessly, capture the result, and
# destroy the clone.
#
#   usage: ./verify.sh <base-image> <profile.toml>
#   env:   CAPSULE_KEEP=1   keep the clone (and leave it running) for
#                           post-mortem SSH instead of deleting it
#          CAPSULE_NO_BUILD=1  reuse the last host build (fast iteration
#                           on a driver; skips signing + build)
#
# Shape (each stage's WHY is in docs/design.md):
#   1. profile   — per-app variable surface, parsed on the host
#   2. host build — a DETACHED git worktree of the app repo under
#      ~/.tart/capsule-work/<name>, so the loop never checks out a
#      branch in the tree a human/other session is using (the
#      cross-session collision capsule exists to remove), signed with
#      the persistent cert (ad-hoc re-signing drops the TCC grant)
#   3. stage      — the ONLY thing the guest sees: a small directory
#      holding the signed bundle + fixture, shared :ro over virtiofs
#   4. clone/run  — APFS copy-on-write clone, --no-graphics, pinned
#      1024x768 (display-refit would silently move every coordinate)
#   5. drive      — profiles/<x>.toml names a drivers/<x>.sh that gets
#      sourced and must define `drive`; it runs on the HOST and talks
#      to the guest through the helpers below (guest stays
#      toolchain-free — JSON is parsed here, not there)
#   6. verdict    — artifacts/<name>/ holds every capture; the clone is
#      destroyed either way
#
# Exit: 0 pass · 1 assertion failed · 2 usage · 3 missing prerequisite.
set -euo pipefail
cd "$(dirname "$0")"

BASE="${1:-}"
PROFILE="${2:-}"
[ -n "$BASE" ] && [ -n "$PROFILE" ] || {
  echo "usage: verify.sh <base-image> <profile.toml>" >&2; exit 2; }
[ -f "$PROFILE" ] || { echo "verify: no such profile: $PROFILE" >&2; exit 2; }

# A clone/pull must never auto-prune the OCI cache and evict other VMs.
export TART_NO_AUTO_PRUNE=1

need() { command -v "$1" >/dev/null 2>&1 || {
  echo "verify: $1 not installed — ${2:-install it and retry}" >&2; exit 3; }; }
need tart
need yq "profiles are TOML and are parsed on the host"
need jq "peekaboo's JSON is parsed on the host — the guest is toolchain-free"

say()  { echo "capsule: $*"; }
fail() { echo "capsule: FAIL — $*" >&2; VERDICT=1; return 1; }

# --- 1. profile -----------------------------------------------------
pf()  { yq -p toml -o=json -r "(${1}) // \"\"" "$PROFILE"; }
pfa() { yq -p toml -o=json -r "((${1}) // []) | .[]" "$PROFILE"; }

NAME="$(pf .name)"
WORKTREE="$(pf .worktree)"
BRANCH="$(pf .branch)"
APP="$(pf .app)"
SIGNING="$(pf .signing)"
BUILD="$(pf .build)"
FIXTURE="$(pf .fixture)"
FIXTURE_DEST="$(pf '.["fixture-dest"]')"
TIER="$(pf '.["verify-tier"]')"
DRIVER="$(pf .driver)"

[ -n "$NAME" ]   || { echo "verify: profile has no name" >&2; exit 2; }
[ -n "$DRIVER" ] || { echo "verify: profile $NAME declares no driver" >&2; exit 2; }
[ -f "$DRIVER" ] || { echo "verify: driver not found: $DRIVER" >&2; exit 2; }
[ -d "$WORKTREE" ] || { echo "verify: worktree not found: $WORKTREE" >&2; exit 3; }

ART="artifacts/$NAME"
rm -rf "$ART"; mkdir -p "$ART"
VERDICT=0

# --- 2. host build --------------------------------------------------
# Detached worktree: resolves any local ref (including an unpushed
# branch — worktrees share the object store) without touching the
# checkout a human or another session has open. Kept across runs so
# SwiftPM rebuilds are incremental.
WORK="$HOME/.tart/capsule-work/$NAME"
if [ "${CAPSULE_NO_BUILD:-}" != "1" ]; then
  git -C "$WORKTREE" rev-parse --verify --quiet "$BRANCH^{commit}" >/dev/null || {
    echo "verify: $WORKTREE has no ref '$BRANCH'" >&2; exit 3; }
  git -C "$WORKTREE" worktree prune
  if [ -d "$WORK/.git" ] || [ -f "$WORK/.git" ]; then
    git -C "$WORK" checkout --detach --quiet "$BRANCH"
  else
    rm -rf "$WORK"
    git -C "$WORKTREE" worktree add --detach --quiet "$WORK" "$BRANCH"
  fi
  REV="$(git -C "$WORK" rev-parse --short HEAD)"
  say "building $NAME @ $BRANCH ($REV) in $WORK"
  # Uncommitted work in $WORKTREE is deliberately NOT verified: the run
  # must be reproducible from a commit. Commit, then verify.

  # SwiftPM local-path overrides for unreleased dependencies. `edit`
  # state is STICKY — it lives in the build worktree, so a dependency
  # would keep being overridden after the profile stopped asking for it,
  # and the run would silently verify something the profile never
  # declared. Clear every edited dependency first, then apply the list.
  WS="$WORK/.build/workspace-state.json"
  if [ -f "$WS" ]; then
    while IFS= read -r stale; do
      [ -n "$stale" ] || continue
      say "clearing stale patched dep: $stale"
      (cd "$WORK" && swift package unedit --force "$stale" >/dev/null 2>&1 || true)
    done < <(jq -r '.object.dependencies[]? | select(.state.name == "edited")
                    | .packageRef.name' "$WS" 2>/dev/null)
  fi
  while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    dep_path="${dep#*=}"
    dep_path="${dep_path/#\~/$HOME}"   # profiles may write ~ for the home dir
    [ -d "$dep_path" ] || {
      echo "verify: patched-dep path does not exist: $dep_path" >&2; exit 3; }
    say "patched dep: ${dep%%=*} -> $dep_path"
    (cd "$WORK" && swift package edit "${dep%%=*}" --path "$dep_path")
  done < <(pfa '.["patched-deps"]')

  # The persistent self-signed cert: TCC keys the grant to the signing
  # identity, so an ad-hoc re-sign would drop it. Idempotent.
  if [ -n "$SIGNING" ]; then
    (cd "$WORK" && bash -c "$SIGNING") >"$ART/signing.log" 2>&1 \
      || { echo "verify: signing step failed (see $ART/signing.log)" >&2; exit 1; }
  fi
  (cd "$WORK" && bash -c "$BUILD") >"$ART/build.log" 2>&1 \
    || { echo "verify: build failed (see $ART/build.log)" >&2; exit 1; }
else
  say "CAPSULE_NO_BUILD=1 — reusing the last build in $WORK"
fi

[ -d "$WORK/$APP" ] || { echo "verify: build produced no $APP in $WORK" >&2; exit 1; }

# --- 3. stage (the only thing the guest sees) -----------------------
STAGE="$HOME/.tart/capsule-stage/$NAME"
rm -rf "$STAGE"; mkdir -p "$STAGE"
ditto "$WORK/$APP" "$STAGE/$APP"          # ditto preserves the signature
codesign --verify --strict "$STAGE/$APP" 2>>"$ART/build.log" || {
  echo "verify: staged $APP failed codesign --verify — the baked AX" >&2
  echo "        grant would not apply; see $ART/build.log" >&2; exit 1; }
# No early `exit` in the awk: closing the pipe early would SIGPIPE
# codesign, and `set -o pipefail` turns that into a failed run.
SIGN_ID="$(codesign -dv --verbose=2 "$STAGE/$APP" 2>&1 |
             awk -F= '/^Authority=/ && !a {a=$2} END{print a}')"
say "staged $APP (signed: ${SIGN_ID:-ad-hoc?})"
[ -n "$FIXTURE" ] && cp "$FIXTURE" "$STAGE/fixture.toml"

EXE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
        "$STAGE/$APP/Contents/Info.plist" 2>/dev/null || echo "")"
[ -n "$EXE" ] || { echo "verify: $APP has no CFBundleExecutable" >&2; exit 1; }

SHARE="/Volumes/My Shared Files/capsule"
GUEST_APP="$SHARE/$APP"

# --- 4. clone + run -------------------------------------------------
VM="capsule-run-$NAME"
RUNLOG="$ART/tart-run.log"

cleanup() {
  local rc=$?
  if [ "${CAPSULE_KEEP:-}" = "1" ]; then
    say "CAPSULE_KEEP=1 — leaving $VM running (ssh -i ${KEY:-?} admin@${IP:-?})"
  else
    # Guard, don't default: the trap is armed before TART_PID is
    # assigned, and `kill 0` would SIGTERM the caller's whole process
    # group — make and the interactive shell included (t-gsen).
    [ -n "${TART_PID:-}" ] && kill "$TART_PID" 2>/dev/null || true
    for _ in $(seq 1 20); do
      [ "$(vm_state)" = "running" ] || break
      sleep 1
    done
    tart delete "$VM" 2>/dev/null || true
  fi
  exit $rc
}
vm_state() { tart list 2>/dev/null | awk -v n="$VM" '$2 == n {print $NF}'; }

tart delete "$VM" 2>/dev/null || true     # a stale clone from a crashed run
say "cloning $BASE -> $VM (APFS copy-on-write)"
tart clone "$BASE" "$VM"
trap cleanup EXIT
# --display ALONE is not enough: display-refit lets the guest resize
# itself and every click coordinate silently shifts (2026-08-03).
tart set "$VM" --display 1024x768 --no-display-refit

tart run "$VM" --no-graphics --dir="capsule:$STAGE:ro" >"$RUNLOG" 2>&1 &
TART_PID=$!

KEY="$HOME/.tart/capsule-ssh/id_ed25519"
[ -f "$KEY" ] || { echo "verify: no capsule SSH key at $KEY — run 'make bake' first" >&2; exit 3; }
SSH_OPTS=(-i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o LogLevel=ERROR -o ConnectTimeout=5)

# The loop exits on IP + port 22 both up; the post-loop guard must
# check the same fact — an IP with a closed port used to slip through
# and fail later in the first ssh with a worse message (t-gsen).
IP="" SSH_UP=""
for _ in $(seq 1 60); do
  kill -0 "$TART_PID" 2>/dev/null || { echo "verify: tart run died — $RUNLOG" >&2; exit 1; }
  IP="$(tart ip "$VM" 2>/dev/null || true)"
  [ -n "$IP" ] && nc -z -w 2 "$IP" 22 2>/dev/null && { SSH_UP=1; break; }
  sleep 3
done
[ -n "$SSH_UP" ] || { echo "verify: $VM never became SSH-reachable — $RUNLOG" >&2; exit 1; }
say "clone up at $IP"

# --- guest helpers (the driver's whole vocabulary) ------------------
PB="/Users/admin/peekaboo/bin/peekaboo"
CLICK="/Users/admin/capsule-helpers/capsule-click"
AXDUMP="/Users/admin/capsule-helpers/capsule-ax-dump"

q() { local a out=""; for a in "$@"; do out+="$(printf '%q' "$a") "; done; printf '%s' "$out"; }
# vm  — run an argv in the guest with host-side quoting preserved.
# vmsh — run a raw shell snippet in the guest (pipelines, redirection).
vm()   { ssh "${SSH_OPTS[@]}" "admin@$IP" "$(q "$@")"; }
vmsh() { ssh "${SSH_OPTS[@]}" "admin@$IP" "$1"; }
vmput() { scp -q "${SSH_OPTS[@]}" "$1" "admin@$IP:$2"; }
vmget() { scp -q "${SSH_OPTS[@]}" "admin@$IP:$1" "$2"; }

pb()    { vm "$PB" "$@"; }
click() { vm "$CLICK" "$1" "$2" "${3:-middle}"; }

# Launch the SIGNED bundle as a direct child of the SSH session — never
# via `open`. Launch Services would re-parent it to launchd and it
# would lose the sshd-keygen-wrapper TCC responsibility that carries
# the baked Accessibility grant.
launch_app() {
  local env_kv=() e envq=""
  while IFS= read -r e; do [ -n "$e" ] && env_kv+=("$e"); done < <(pfa '.["launch-env"]')
  # No `env` prefix at all when the profile declares no launch-env: an
  # empty array would otherwise quote to `env ''` and die rc=127 trying
  # to exec an empty command name (t-gsen).
  [ "${#env_kv[@]}" -gt 0 ] && envq="env $(q "${env_kv[@]}")"
  vmsh "cd '$SHARE' && nohup $envq '$GUEST_APP/Contents/MacOS/$EXE' \
        >/tmp/capsule-app.log 2>&1 </dev/null & echo started"
}

# Poll instead of sleeping: boot/render timing is the one thing that is
# NOT deterministic in a fresh clone.
wait_proc() { # wait_proc <pattern> [tries]
  for _ in $(seq 1 "${2:-20}"); do
    vm pgrep -f "$1" >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

app_log() { vm cat /tmp/capsule-app.log 2>/dev/null || true; }

# AX tier — capsule's own walker, not peekaboo: `see --app` filters out
# layer != 0 (non-activating NSPanels), and `inspect-ui` cannot descend
# SwiftUI's accessibility containers — an NSHostingView subtree surfaces
# as ONE opaque childless element (measured 2026-08-04 against facet's
# SwiftUI tree; same failure class as prism, t-c4pv). capsule-ax-dump
# (helpers/ax-dump.swift, baked into the image) walks the raw
# AXUIElement tree and sees both AppKit and SwiftUI content. Drivers
# assert on the .txt; text attributes are printed quoted, so
# `grep '"Alpha"'` matches exactly the fixture's label.
ax_dump() { # ax_dump <app> <artifact-name> -> $ART/<name>.txt
  vm "$AXDUMP" "$1" >"$ART/$2.txt" 2>"$ART/$2.err" || return 1
  [ -s "$ART/$2.txt" ]
}

# Screenshot tier — a BONUS, never the gate: Screen Recording
# re-confirms ~monthly on Tahoe, Accessibility is forever.
#
# A fresh clone answers AX ~25 s before it composites a desktop, and an
# idle framebuffer keeps serving the BOOT SPLASH to a capture that
# otherwise looks successful (measured 2026-08-03: 22 KB splash vs
# >150 KB composited, at the pinned 1024x768). Retry until the frame is
# a composited one; a still-uncomposited frame costs a bonus artifact,
# never a false PASS.
SNAP_MIN_BYTES=100000
snap() { # snap <artifact-name>
  [ "$TIER" = "screenshot" ] || { say "snap $1 skipped (verify-tier=$TIER)"; return 0; }
  local size=0
  for _ in $(seq 1 12); do
    pb image --mode screen --path "/tmp/snap-$1.png" >/dev/null 2>&1 \
      && vmget "/tmp/snap-$1.png" "$ART/$1.png" || return 1
    size="$(stat -f%z "$ART/$1.png" 2>/dev/null || echo 0)"
    [ "$size" -ge "$SNAP_MIN_BYTES" ] && return 0
    sleep 3
  done
  say "snap $1: framebuffer still uncomposited (${size}B) — keeping it anyway"
  [ "$size" -gt 0 ]
}

# --- 5. reset the lab, then assert the clone is human-zero -----------
# Assert user activity for the whole run: a just-booted guest keeps the
# BOOT SPLASH on its framebuffer until something wakes the display, even
# though the session behind it already answers AX. `caffeinate -u` is
# what moved it (measured 2026-08-03); the recipe's pmset keeps it there.
vmsh 'nohup caffeinate -u -t 1800 >/dev/null 2>&1 </dev/null & echo awake' >/dev/null

# Every clone logs in with System Settings reopened by launchd — the
# bake had to open it to grant TCC, and killing it before shutdown does
# NOT stop the relaunch (measured: ppid 1 in a fresh clone, with no
# TALAppsToRelaunchAtLogin and no Saved Application State to clear). It
# stays dead once killed WITH its agent, so the loop resets the lab
# rather than trusting the image: a verify run must start against a bare
# desktop, or the frontmost app is a variable no profile declared.
vmsh 'pkill -f "System Settings.app/Contents" 2>/dev/null; true'
sleep 2


perms="$(pb permissions status --all-sources 2>&1 | awk '/local runtime/{f=1} f' || true)"
printf '%s\n' "$perms" >"$ART/permissions.txt"
grep -q "Accessibility (Required): Granted" <<<"$perms" \
  || fail "fresh clone lacks the baked Accessibility grant (see $ART/permissions.txt)"
if [ "$TIER" = "screenshot" ]; then
  grep -q "Screen Recording (Required): Granted" <<<"$perms" \
    || fail "fresh clone lacks Screen Recording (re-bake: the grant expires ~monthly)"
fi
[ "$VERDICT" = "0" ] || exit 1
say "clone is consented (no prompts) — driving profile '$NAME'"

# Per-app fixture: config lives in the guest HOME, not on the :ro share.
if [ -n "$FIXTURE" ] && [ -n "$FIXTURE_DEST" ]; then
  vm mkdir -p "$(dirname "$FIXTURE_DEST")"
  vmput "$FIXTURE" "$FIXTURE_DEST"
  say "fixture -> ~/$FIXTURE_DEST"
fi

# --- 6. drive + verdict ---------------------------------------------
# shellcheck source=/dev/null
source "$DRIVER"
command -v drive >/dev/null || { echo "verify: $DRIVER defines no drive()" >&2; exit 2; }

drive || VERDICT=1

if [ "$VERDICT" = "0" ]; then
  say "PASS — $NAME verified in a fresh clone (artifacts: $ART/)"
else
  say "FAIL — $NAME (artifacts: $ART/)" >&2
fi
exit "$VERDICT"
