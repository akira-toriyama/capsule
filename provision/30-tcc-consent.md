# provision/30 — TCC bake-by-consent (the ONE human touch)

This step is **not scriptable** and that is by design — see
[../docs/design.md](../docs/design.md). Direct `sqlite3` pre-seed of the
system TCC.db needs SIP off (the base image ships SIP **on**, and Tart
can't script SIP-off — `cirruslabs/tart#1072`); an MDM/PPPC profile needs
a supervised enrolled device and still can't silently allow Screen
Recording. So grants are baked by **consenting once inside the VM**. All
in-VM consent is pre-authorized (the host is the opposite — always ask).

## Do this once, on the base VM, BEFORE snapshotting

1. Boot the base VM with a graphical session (login as `admin`).
2. Launch peekaboo once and let it prompt; grant it:
   - **Accessibility** (drives clicks / reads the AX tree)
   - **Screen Recording** (screenshots)
3. Install wand's persistent signing cert (`provision/40-signing-cert.sh`)
   and launch a `package.sh`-signed `Wand.app` once; grant **wand**
   **Accessibility** (its event tap). TCC keys this to the cert, so it
   survives rebuilds signed with the same identity.
4. Verify no prompt remains, then snapshot / `tart stop` → this becomes
   the reusable base.

## What survives, what doesn't

- **Accessibility** grants survive the bake, the clone, and app
  rebuilds (csreq-keyed, on-disk, no periodic re-prompt). Human-zero
  **forever**.
- **Screen Recording** re-confirms on a macOS Sequoia/Tahoe ~monthly
  cadence that only MDM suppresses → re-bake monthly, OR run the
  **AX-only** verification tier (peekaboo `see` + wand's own tap), which
  needs no Screen Recording at all. Default acceptance to the AX tier.
