# capsule — design & decision record

Durable home for *why* capsule is shaped the way it is. Tracked as
`projects/t-8ffm`. Every claim below was verified against a primary
source (GitHub/cirruslabs docs, Tart CLI `--help`, Apple docs, or the
local machine) during the 2026-07-18 investigation.

## Goal

An environment **Claude Code can drive end-to-end from the terminal**
to GUI-verify the family's macOS apps, with **zero host disruption** and
**deterministic** results. Host-machine GUI automation aborted a real
session (focus steal, window ops, Space switches) and is non-repeatable
(multi-display coords, toolchain drift, TCC flakiness, cross-session
repo collisions). A fixed, disposable VM removes every one of those
variables.

## The two decisions

### 1. A dedicated repo — YES, `capsule`

There are already **three hand-made** Tart VMs (`facet-test-26`,
`sill-focusprobe`, `facet-test-rec` — identical 4CPU/8GB/50GB/1024×768
shells) built by hand, three times, with the pattern captured nowhere.
The right move is to encode the *recipe*, not hand-build a fourth. The
per-app needs (patched-dependency build override, unpushed-branch rsync,
per-app fixture, per-app cert, middle-click helper, per-app driver) are
recurring and shared across ≥2 first-users plus the family — clearing
the "redundant across 2+ apps ⇒ shared infra" bar. A Packer recipe's
natural home is a git repo; a scratch dir is neither reviewable nor
reproducible.

**Name:** `capsule` over `kiln`. The *daily* operation is the ephemeral
copy-on-write clone→run→destroy loop; baking is *rare* and
CI-impossible on hosted runners. Name the thing you do every day (throw
a capsule, a lab appears; fold it, gone), not the rare oven. Both fit
the single-word craft-noun register (sill/wand/prism/facet/glyph/
furrow/…). Low-stakes and trivially reversible this early.

### 2. Image vs recipe — a FALSE dichotomy: ship both, recipe is source

The vendor-canonical `cirruslabs/macos-image-templates` pipeline is
exactly "recipe **and** image from one repo": `tart pull vanilla →
packer build (bakes) → tart push (distributes) → tart delete`. The HCL
is the reviewable input; the image is the cached output.

capsule keeps the **recipe in git** and treats the **~27 GB image as a
disposable local cache** (`tart export` → `.tvm`), not a git artifact
and not a default registry push, because:

- `tart push` has **no layer reuse** (`cirruslabs/tart#771`,
  closed-not-planned) → every re-bake re-uploads ~27 GB.
- Copy-on-write `tart clone` makes local re-clone ~free → the daily loop
  never needs a pulled image.
- GitHub-hosted CI **cannot bake** (below), so an auto-published image
  would just be a stale hand-baked blob.
- The load-bearing per-app inputs **can't be baked** anyway: wand's work
  is 17 **unpushed** commits on `feat/t-k4hf`, built against an
  **unreleased** sill patch (`t-cp90`). Those arrive at run time over a
  read-only virtiofs share.

This is the family north star ("source over a stale brew snapshot")
applied to VM infra: the pushed image is the stale snapshot; the recipe
is the source. `tart export`/`import` (a registry-free `.tvm`) is the
right way to move an image for a single-dev reality — the prior analysis
missed it.

## Verified facts that shaped the design

### CI / baking
- GitHub-**hosted** macOS runners can never run Tart: they are
  themselves Apple-VF VMs, and Apple's Virtualization Framework nests
  **Linux** guests only (M3/M4 + macOS 15+). Confirmed by GitHub's
  larger-runners doc + the Tart FAQ.
- **Self-hosted** Apple-silicon runners (the user's own Mac) or paid
  Cirrus Runners *can* bake — that's how cirruslabs bakes its own base
  images (monthly + per release, `runs-on: [self-hosted, macOS,
  ARM64]`). So auto-rebake is achievable *later*; it is not a reason
  against the repo. → *Corrects the prior "CI can't bake, so repo =
  recipe-not-auto-build", which was overstated.*
- `packer` is **not installed** here (`brew install packer` needed).
  Baking has never run; the Packer HCL in `packer/` is an unverified
  DRAFT until the gate proves it.

### TCC grants + signing (the "human-zero" premise)
- TCC's access check is the **csreq** code-signing-requirement blob =
  **signing identity** (bundle id + team/leaf cert), with **zero**
  hardware binding. → *Corrects the prior premise that a clone's "new
  random MAC/UUID" could invalidate grants — doubly wrong: `tart clone`
  **preserves** identity by default (randomization is an explicit `tart
  set --random-mac --random-serial` opt-in), AND TCC isn't
  hardware-keyed.*
- TCC state is on-disk SQLite (system db `/Library/Application
  Support/com.apple.TCC/TCC.db` for both Accessibility and Screen
  Recording), so it **rides along in a baked disk image** and survives
  clone.
- **Accessibility** bakes cleanly and **forever** — on-disk,
  csreq-keyed, no periodic re-prompt. wand needs only AX (event tap +
  `AXTarget`).
- **Screen Recording is the one fragile leg:** macOS Sequoia 15
  introduced a ~monthly re-confirmation dialog, still present in Tahoe
  26, suppressible only via MDM on a supervised device (unavailable to a
  throwaway VM). → *The prior plan listed "bake AX + Screen Recording"
  as a clean win but missed this. "Human-zero forever" is true for AX,
  false for SR.* Hence **two-tier verify** (default AX-only; screenshot
  is a within-window bonus), and re-bake refreshes the SR grant
  naturally.
- Pre-seeding TCC.db directly is impractical: the system db is
  SIP-protected, cirruslabs base images ship **SIP on**, and Tart can't
  script SIP-off (recovery mode has no SSH — `cirruslabs/tart#1072`).
  MDM/PPPC needs a supervised enrolled device and still can't silently
  allow Screen Recording. → the only viable mechanism is
  **bake-by-in-VM-consent** (pre-authorized).
- wand's persistent self-signed cert lives in the login keychain
  (password-bound software key, not hardware/Secure-Enclave) → survives
  clone. peekaboo is Developer-ID signed (team `Y5PE65HELJ`) → its grant
  survives upgrades too.
- **The signed-bundle invariant:** a fresh `swift build` inside the VM
  ad-hoc re-signs wand and **drops** the baked AX grant
  (`event-tap: tapCreate failed`) — the same trap wand documents for the
  host. The harness must drive the `package.sh`-signed bundle, never
  `.build/debug/wand`.

### peekaboo (the GUI-verification CLI)
- No middle-click / arbitrary button through peekaboo HEAD 3.9.4 →
  `helpers/click.swift` is genuinely still needed (wand's tome opens on
  middle-click). Upstream a `--middle` PR (non-blocking); see
  `helpers/UPSTREAM.md`.
- `winlist.swift` is **obsolete**: `peekaboo list windows --pid <pid>
  --include-details bounds,ids --json` already reports per-window bounds
  by pid, and multi-display coords were fixed in peekaboo 3.0.0. Dropped
  (not carried here).

### dotfiles / tooling
- Do **not** piggyback the verify env on `dotfiles/packages.nix`: it's a
  home-manager module (needs the flake), its CLI wrappers **hardcode**
  `/Volumes/workspace/...` host paths and need mise's go, `glyph` isn't
  in it at all, and it drags host-only tooling (1Password, docker/colima
  = a Linux VM *inside* the macOS VM, `tart` itself). → *Corrects the
  prior "bring packages.nix and furrow/pare/cifail/glyph come wholesale"
  — false for glyph and not VM-portable.* Cherry-pick a small verify
  subset instead.

### Operations
- `tart clone` is APFS copy-on-write (instant, ~0 disk until writes);
  boot-to-SSH ≈ 10 s; `tart delete` reclaims only the delta. The daily
  loop costs seconds.
- Get the working tree in via `tart run --dir=<path>:ro` (virtiofs;
  auto-mounts to `/Volumes/My Shared Files`). **Build on the host**
  (native arm64, signed with the persistent cert), share the product
  read-only — keeps the baked image toolchain-free. Don't run
  write-heavy builds over the virtiofs mount.
- **Footgun:** `tart clone`/`pull` auto-prune the OCI cache (100 GB LRU
  default). `~/.tart` is already ~147 G with ~277 G free — a naive clone
  could silently evict the three hand-made VMs. Always set
  `TART_NO_AUTO_PRUNE=1` in the loop.
- The tahoe base is ~27 GB / 96 layers (local manifest) — heavier than
  the prior "22.9 GB". Both `macos-tahoe-base` (26) and
  `macos-sequoia-base` (15) are already cached locally.

## Bring-up sequence (risk-gated)

The biggest unknown is **not** TCC or the 27 GB pull (both de-risked
above); it is that the **integrated headless chain has never run once**
— can a `--no-graphics` VM render a non-activating NSPanel well enough
for peekaboo to screenshot/AX-read it, honoring a baked AX grant for a
host-built, cert-signed binary, with zero fresh consent?

0. **Done / unconditional:** rescue `helpers/click.swift` (this repo);
   drop `winlist.swift`; open the peekaboo `--middle` issue (async).
1. **The gate (cheapest experiment — an afternoon, no packer/no bake):**
   in an *existing* hand-made VM (`sill-focusprobe` / `facet-test-26`),
   install wand's persistent cert, host-build+sign a tome-enabled
   `Wand.app` (fixture: `fixtures/wand-tome.toml`), grant AX once,
   `tart clone` the consented VM (`TART_NO_AUTO_PRUNE=1`), and in the
   **clone** run fully headless: launch the signed bundle from a
   `--dir:ro` share, `helpers/click` middle-click, `peekaboo see` (AX) +
   `image` (screenshot).
   **PASS** = zero consent prompts in the clone, no `tapCreate failed`,
   the tome panel opens, the AX tree enumerates the rows (screenshot
   non-empty is a bonus). **FAIL** = any re-prompt, tapCreate failure,
   black/empty screenshot (headless WindowServer gap), or `see` not
   enumerating the panel. Do **not** install packer or bake until green.
2. **If green:** turn the manual steps into `packer/base.pkr.hcl` +
   `provision/*.sh`, `brew install packer`, prove `make bake` against
   the cached tahoe base.
3. **Use it:** unblock wand `t-k4hf` (5 items) and sill/prism `t-cp90`.
   Note wand `t-k4hf` is *also* blocked on the unreleased sill `t-cp90`
   patch — capsule solves *verification*, not *shipping*.
