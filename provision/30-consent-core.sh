#!/usr/bin/env bash
# provision/30-consent-core.sh — bake the ssh-context TCC grants into a
# freshly packer-built image, human-zero, zero host windows.
#
#   usage: 30-consent-core.sh <image-name> <ssh-private-key>
#
# What it grants (and why this is the core, gate-proven 2026-08-03):
#   /usr/libexec/sshd-keygen-wrapper is macOS's TCC responsible process
#   for everything run over SSH. Granting it Accessibility + Screen
#   Recording arms EVERY ssh-driven tool (peekaboo, capsule-click) in
#   one move. Per-app grants (e.g. Wand's own event tap) are a
#   per-profile step, not core.
#
# Mechanism: the VM runs with Virtualization.framework's VNC server
# (`tart run --vnc-experimental`, no host window) and vncdotool drives
# the consent UI. Every click is STATE-VERIFIED over SSH via
# `peekaboo permissions status` — no blind click sequences. On failure
# a screenshot lands in artifacts/ for diagnosis.
#
# Coordinates are in the 1024x768 POINT space of the deterministic tart
# display, in the FRESH-IMAGE state (consent lists empty except what
# this script registers). The VNC framebuffer may be served at 1x
# (1024x768) or 2x (2048x1536) depending on how the VM last configured
# its display — both were observed on the same base — so the actual
# scale is measured from a capture at startup and every click is
# multiplied by it. Re-measure the point coords if macOS moves the
# Privacy & Security layout.
set -euo pipefail
cd "$(dirname "$0")/.."

IMG="${1:?usage: 30-consent-core.sh <image-name> <ssh-private-key>}"
KEY="${2:?usage: 30-consent-core.sh <image-name> <ssh-private-key>}"

export TART_NO_AUTO_PRUNE=1

VNCDO="${CAPSULE_VNCDO:-$(command -v vncdo || true)}"
[ -n "$VNCDO" ] || {
  echo "consent: vncdotool not found — python3 -m venv ~/.tart/capsule-venv &&" >&2
  echo "         ~/.tart/capsule-venv/bin/pip install vncdotool, then" >&2
  echo "         export CAPSULE_VNCDO=~/.tart/capsule-venv/bin/vncdo" >&2
  exit 3
}

mkdir -p artifacts

# Every capsule coordinate assumes the deterministic 1024x768 display.
# `--display` ALONE IS NOT ENOUGH: display-refit lets the guest resize
# itself to the viewer (observed 2026-08-03 — `tart get` reported
# 1024x768 while the VNC framebuffer served 1280px wide). Pin both.
tart set "$IMG" --display 1024x768 --no-display-refit

RUNLOG="$(mktemp -t capsule-consent)"
tart run "$IMG" --no-graphics --vnc-experimental >"$RUNLOG" 2>&1 &
TART_PID=$!
cleanup() { kill "$TART_PID" 2>/dev/null || true; }
trap cleanup EXIT

# --- wait for VNC + SSH --------------------------------------------
VNC_URL=""
for _ in $(seq 1 30); do
  VNC_URL="$(grep -oE 'vnc://:[^@]+@127\.0\.0\.1:[0-9]+' "$RUNLOG" | head -1 || true)"
  [ -n "$VNC_URL" ] && break
  sleep 2
done
[ -n "$VNC_URL" ] || { echo "consent: no VNC URL from tart run" >&2; exit 1; }
VNC_PASS="${VNC_URL#vnc://:}"; VNC_PASS="${VNC_PASS%%@*}"
VNC_PORT="${VNC_URL##*:}"

IP=""
for _ in $(seq 1 60); do
  IP="$(tart ip "$IMG" 2>/dev/null || true)"
  [ -n "$IP" ] && nc -z -w 2 "$IP" 22 2>/dev/null && break
  sleep 3
done
[ -n "$IP" ] || { echo "consent: VM never became SSH-reachable" >&2; exit 1; }

vncc() { "$VNCDO" -s "127.0.0.1::${VNC_PORT}" -p "$VNC_PASS" "$@" 2>/dev/null; }
# --delay (global option) must precede -s/-p in some vncdotool versions.
vncslow() { "$VNCDO" --delay 120 -s "127.0.0.1::${VNC_PORT}" -p "$VNC_PASS" "$@" 2>/dev/null; }

# Measure the framebuffer scale (1x or 2x of the 1024x768 point space) —
# clicking with the wrong scale lands on the wallpaper and hides every
# window (Tahoe's click-wallpaper-to-show-desktop trap).
SCALE_PROBE="$(mktemp -t capsule-scale).png"
vncc capture "$SCALE_PROBE"
FB_W="$(sips -g pixelWidth "$SCALE_PROBE" 2>/dev/null | awk '/pixelWidth/{print $2}')"
rm -f "$SCALE_PROBE"
[ -n "$FB_W" ] || { echo "consent: could not measure VNC framebuffer" >&2; exit 1; }
if [ $(( FB_W % 1024 )) -ne 0 ]; then
  echo "consent: framebuffer ${FB_W}px is not a 1024x768 multiple — display drifted; aborting" >&2
  exit 1
fi
SCALE=$(( FB_W / 1024 ))
echo "consent: VNC framebuffer ${FB_W}px wide -> ${SCALE}x scale"
click_at() { vncc move $(( $1 * SCALE )) $(( $2 * SCALE )) click 1; }

# Two observed failure modes make fixed sleeps unusable, so every click
# is gated on pixel probes of the 1024x768 point space:
#   - the privacy panes render their rows SECONDS after the window opens
#     (an early click hits empty pane, then the blind password typing
#     goes nowhere);
#   - the base image restores a Terminal window at login, which can sit
#     ON TOP of System Settings — a click then lands in the shell and
#     "admin" is typed at the prompt (`zsh: command not found: admin`).
# Probes: ANCHOR is pane-white only when System Settings is frontmost;
# ROW_ICON is the first row's dark app icon, white while the list is
# still empty. The toggle itself is near-white in BOTH states, so it
# cannot be used as its own readiness probe.
PYBIN="$(dirname "$VNCDO")/python3"
[ -x "$PYBIN" ] || PYBIN="python3"
pixel_at() { # pixel_at <png> <x-pt> <y-pt> -> "R,G,B"
  "$PYBIN" - "$1" "$(( $2 * SCALE ))" "$(( $3 * SCALE ))" <<'PY' 2>/dev/null
import sys
from PIL import Image
p, x, y = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
print(",".join(str(v) for v in Image.open(p).convert("RGB").getpixel((x, y))))
PY
}
ANCHOR_X=600; ANCHOR_Y=100   # pane background — white iff Settings is frontmost
ROW_X=414;    ROW_Y=167      # first row's app icon — dark once the list renders

is_light() { [ "$(( ${1%%,*} ))" -gt 200 ]; }
is_dark()  { [ "$(( ${1%%,*} ))" -lt 120 ]; }

wait_front() { # System Settings frontmost and its pane drawn
  local probe; probe="$(mktemp -t capsule-front).png"
  for _ in $(seq 1 15); do
    vncc capture "$probe"
    is_light "$(pixel_at "$probe" $ANCHOR_X $ANCHOR_Y)" && { rm -f "$probe"; return 0; }
    sleep 2
  done
  rm -f "$probe"; return 1
}

wait_row() { # frontmost AND the first list row has rendered
  local probe; probe="$(mktemp -t capsule-row).png"
  for _ in $(seq 1 15); do
    vncc capture "$probe"
    if is_light "$(pixel_at "$probe" $ANCHOR_X $ANCHOR_Y)" \
       && is_dark "$(pixel_at "$probe" $ROW_X $ROW_Y)"; then
      rm -f "$probe"; return 0
    fi
    sleep 2
  done
  rm -f "$probe"; return 1
}
sshvm() {
  ssh -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR "admin@$IP" "$@"
}
pb="/Users/admin/peekaboo/bin/peekaboo"
granted() { # granted <Accessibility|Screen Recording>
  sshvm "$pb permissions status --all-sources" 2>/dev/null \
    | awk '/local runtime/{f=1} f' | grep -q "$1 (Required): Granted"
}
snap() { vncc capture "artifacts/consent-$1.png" || true; }

# --- A. register sshd-keygen-wrapper in the AX list -----------------
sshvm "$pb see --app Finder --json >/dev/null 2>&1 || true"
sleep 2

# --- B. Accessibility toggle ---------------------------------------
if ! granted "Accessibility"; then
  # The restored Terminal window would otherwise cover the pane.
  sshvm 'pkill -x Terminal 2>/dev/null || true'
  sshvm 'open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"'
  for attempt in 1 2 3; do
    wait_row || { sleep 3; continue; }
    click_at 823 168             # row 1 toggle (sshd-keygen-wrapper is the only row)
    sleep 2
    vncslow type admin         # password sheet — field is pre-focused
    sleep 1
    vncc key enter
    sleep 4
    granted "Accessibility" && break
    snap "ax-attempt$attempt"
  done
  granted "Accessibility" || { snap ax-fail; echo "consent: AX toggle failed (artifacts/consent-ax-fail.png)" >&2; exit 1; }
fi
echo "consent: Accessibility granted (ssh context)"

# --- C. Screen Recording via + -> Go-to sheet ----------------------
if ! granted "Screen Recording"; then
  sshvm 'pkill -x Terminal 2>/dev/null || true'
  sshvm 'open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"'
  sleep 4
  for attempt in 1 2 3; do
    # The SR list starts EMPTY (no row to wait for) — front check only.
    wait_front || sleep 3
    click_at 404 204           # "+" under the Screen Recording list
    sleep 3
    vncc key super-shift-g
    sleep 1
    vncslow type "/usr/libexec/sshd-keygen-wrapper"
    sleep 1
    vncc key enter             # accept Go-to suggestion
    sleep 2
    vncc key enter             # Open (adds pre-enabled, no password sheet)
    sleep 3
    granted "Screen Recording" && break
    # typing may have mangled (autocomplete) — close any dialog and retry
    snap "sr-attempt$attempt"
    vncc key esc; sleep 1; vncc key esc; sleep 1
  done
  granted "Screen Recording" || { snap sr-fail; echo "consent: SR add failed (artifacts/consent-sr-fail.png)" >&2; exit 1; }
fi
echo "consent: Screen Recording granted (ssh context)"

# --- D. verify, tidy, snapshot -------------------------------------
sshvm 'osascript -e "quit app \"System Settings\"" 2>/dev/null || true'
sshvm "$pb image --mode screen --path /tmp/consent-proof.png >/dev/null 2>&1" \
  || { echo "consent: post-grant screenshot failed" >&2; exit 1; }
sshvm 'rm -f /tmp/consent-proof.png; sudo shutdown -h now' 2>/dev/null || true

for _ in $(seq 1 30); do
  state="$(tart list 2>/dev/null | awk -v img="$IMG" '$2 == img {print $NF}')"
  [ "$state" = "stopped" ] && break
  sleep 3
done
[ "$state" = "stopped" ] || { echo "consent: VM did not stop cleanly" >&2; exit 1; }

echo "consent: DONE — $IMG carries AX + Screen Recording for the ssh context"
