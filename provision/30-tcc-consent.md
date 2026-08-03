# provision/30 — TCC bake-by-consent (human-zero via VNC)

Direct `sqlite3` pre-seed of the system TCC.db needs SIP off (the base
image ships SIP **on**, and Tart can't script SIP-off —
`cirruslabs/tart#1072`); an MDM/PPPC profile needs a supervised enrolled
device and still can't silently allow Screen Recording. So grants are
baked by **consenting once inside the VM** — and that consent click is
**fully scriptable** (proven by the 2026-08-03 gate run, see
[../docs/design.md](../docs/design.md)): boot with `tart run
--no-graphics --vnc-experimental`, then drive the consent UI with
`vncdotool` (pip) — capture → click → `--delay 80` typing. Zero host
windows, zero human touches. All in-VM consent is pre-authorized (the
host is the opposite — always ask).

**The core grants are automated**: `bake.sh` runs
[`30-consent-core.sh`](30-consent-core.sh) (ssh-context AX + Screen
Recording via `sshd-keygen-wrapper`, state-verified after every click).
The steps below document the mechanism and the per-app variant.

## Do this once, on the base VM, BEFORE snapshotting

1. Boot the base headless with VNC: `tart run <base> --no-graphics
   --vnc-experimental` (prints `vnc://:PASSWORD@127.0.0.1:PORT`).
2. **ssh-context grants (covers peekaboo + click and any ssh-run tool)**:
   run one failing AX call over SSH (e.g. `peekaboo see`) — macOS
   auto-registers `/usr/libexec/sshd-keygen-wrapper` in the
   Accessibility list; toggle it ON over VNC (password sheet → type
   `admin`). For **Screen Recording** add the same binary by hand:
   `+` → ⌘⇧G → type `/usr/libexec/sshd-keygen-wrapper` → Enter ×2 — it
   lands pre-enabled with no password prompt.
3. Launch a `package.sh`-signed `Wand.app` once (`open ~/Wand.app` over
   SSH); macOS opens the Accessibility pane with **Wand** listed —
   toggle ON over VNC. TCC keys this to the signing cert, so it survives
   rebuilds *and* runs from other paths (the gate launched it from the
   RO virtiofs share). **The core bake no longer does this**: a
   host-signed app launched as a child of the SSH session inherits the
   `sshd-keygen-wrapper` grant, so there is no per-app TCC step — see
   docs/design.md §Verify loop.
4. Verify with `peekaboo permissions status --all-sources` (everything
   Granted), then `tart stop` → this becomes the reusable base.

## What survives, what doesn't

- **Accessibility** grants survive the bake, the clone, and app
  rebuilds (csreq-keyed, on-disk, no periodic re-prompt). Human-zero
  **forever**.
- **Screen Recording** re-confirms on a macOS Sequoia/Tahoe ~monthly
  cadence that only MDM suppresses → re-bake monthly, OR run the
  **AX-only** verification tier (peekaboo `see` + wand's own tap), which
  needs no Screen Recording at all. Default acceptance to the AX tier.
