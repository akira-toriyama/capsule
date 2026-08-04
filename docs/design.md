# capsule — design & decision record

Durable home for *why* capsule is shaped the way it is, and the live
record of what has actually been measured. The bring-up task
(`projects/t-8ffm`) closed on 2026-08-03 once `make bake` and
`make verify` were both proven from the committed recipe; this file is
the canon from there on. Every claim below was verified against a
primary source (GitHub/cirruslabs docs, Tart CLI `--help`, Apple docs,
or the local machine).

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

*(The argument as it stood on 2026-07-18.)* There were then **three
hand-made** Tart VMs (`facet-test-26`, `sill-focusprobe`,
`facet-test-rec` — identical 4CPU/8GB/50GB/1024×768 shells) built by
hand, three times, with the pattern captured nowhere. The right move is
to encode the *recipe*, not hand-build a fourth. **All three have since
been deleted** — which is the argument's own vindication: the pattern
was the durable thing, the VMs were not. The
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
- Baking is **local-only, and proven**: `packer` (v1.15.4, re-measured
  2026-08-04) runs `make bake` on the host — ~1 min packer build plus
  the scripted consent, ~4 min end-to-end (§Bake result,
  §Reproducibility). GitHub-hosted CI still cannot bake — that
  judgment is unchanged; only the "never run / unverified DRAFT"
  status is history.

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
  default) — a naive clone could silently evict your other VMs,
  including `capsule-base` itself. Always set `TART_NO_AUTO_PRUNE=1` in
  the loop.
- The vanilla tahoe base is ~27 GB (local manifest). What is actually
  cached drifts: as of 2026-08-03 only
  `ghcr.io/cirruslabs/macos-tahoe-vanilla:latest` is, and `make bake`
  pulls it if absent — read `tart list` rather than trusting this line.

## Bring-up sequence (risk-gated)

*(The plan as written on 2026-07-18, kept because the sections below
report against it. Every step has since been executed — step 1 by hand
from a vanilla base because the hand-made VMs it names were gone by
then, steps 2 and 3 by `make bake` / `make verify`.)*

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

## Gate result — PASS (run 2026-08-03, all five criteria)

The hand-made VMs no longer existed, so the base was rebuilt from the
locally cached `ghcr.io/cirruslabs/macos-tahoe-vanilla:latest` (macOS
26.5, SIP on, 1024×768) as `capsule-gate-base`. Every claim below was
executed and observed this run, end-to-end from the terminal, zero host
windows, zero human touches:

1. **Zero consent prompts in the clone** — `peekaboo permissions status`
   reported AX + Screen Recording + Event Synthesizing all Granted at
   first SSH into the headless clone.
2. **No tapCreate failure across the path change** — `Wand.app` was
   granted AX at `~/Wand.app` in the base, then launched in the clone
   from the read-only virtiofs share (`/Volumes/My Shared Files/wandapp/`);
   the event tap still worked. Confirms the csreq grant is
   signature-keyed, not path-keyed.
3. **Tome panel opens headless** — `helpers/click` middle-click at
   (512,384) over SSH opened the 250×121 panel on the `--no-graphics`
   WindowServer (the design's biggest unknown — resolved YES).
4. **AX enumerates the rows** — `peekaboo inspect-ui --app Wand` returned
   10 elements: the panel, the frontmost-app header row, and the fixture
   rows Alpha / Beta / Sort (+ SF-symbol icons a.circle / b.circle).
5. **Bonus: non-empty screenshot** — `peekaboo image --mode screen`
   produced a real 2 MB capture showing the themed panel.

New verified facts (correcting / extending the notes above):

- **Consent bake IS scriptable, human-zero** — `tart run
  --vnc-experimental` + `vncdotool` (pip) drives the in-VM consent UI
  from the terminal with zero host windows: screenshot → click toggle →
  type the `admin` password. `provision/30-tcc-consent.md`'s "not
  scriptable" meant TCC.db seeding; the *click path* automates fine.
- **`sshd-keygen-wrapper` is the master key for ssh-driven tools**: after
  one failed AX attempt over SSH, macOS auto-registers
  `/usr/libexec/sshd-keygen-wrapper` in the Accessibility list — toggle
  it on and *every* binary run over SSH (peekaboo, click) inherits AX.
  For Screen Recording it must be added by hand (+ → ⌘⇧G → type the
  path), and it lands **pre-enabled, no password prompt**.
- **peekaboo `see --app` cannot window-target the tome panel**
  (`layer != 0` — non-activating NSPanels are filtered out of the
  shareable-window pipeline). Use `inspect-ui --app` for the AX tier and
  `image --mode screen` for pixels. The AX-tier default in this repo is
  therefore `inspect-ui`, not `see`. *(Superseded 2026-08-04: inspect-ui
  is blind to SwiftUI subtrees, so the AX tier now runs on capsule's own
  `capsule-ax-dump` — see §Adding an app.)*
- **Don't invoke `python3`/dev tools inside the vanilla VM** — it pops
  the CLT install dialog (visible in the gate screenshot). Parse JSON on
  the host; keep the guest toolchain-free until `provision/10` bakes CLT.
- vncdotool typing is lossy at full speed (`--delay 80`+ needed;
  path autocompletion in Go-to sheets can still mangle input — clear the
  field and retype when it does).

The ephemeral clone was deleted after the run, as designed. Evidence
screenshots live in the session scratchpad only; the durable record is
this section. The hand-made gate base was superseded by `make bake`
(below) and deleted.

## Bake result — `make bake` is zero-touch (2026-08-03)

The gate's manual steps are now the recipe, and one command produces a
consented base: **`make bake`** = packer build (~40 s) →
`provision/30-consent-core.sh` (scripted TCC consent over VNC) →
stopped, reusable `capsule-base`. Verified by cloning the baked image
and observing, in the fresh clone: AX + Screen Recording + Event
Synthesizing all **Granted**, peekaboo 3.9.4 and `capsule-click`
present, and `image --mode screen` capturing successfully — with zero
prompts and zero host windows.

Design decisions this run settled:

- **The guest stays toolchain-free.** peekaboo (whole Cellar dir, so
  `@rpath` dylibs ride along) and the host-compiled `capsule-click` are
  shipped in as binaries; `provision/10-clt.sh` is explicitly NOT part
  of the core bake. Apps are built and signed on the host and arrive
  over a read-only share, and JSON is parsed on the host.
- **A per-host SSH key** (`~/.tart/capsule-ssh/`, generated on first
  bake, never in git) is seeded by the recipe, so the daily loop and
  the consent script drive VMs without password auth.
- **The bake is base-agnostic**: `macos-tahoe-vanilla` is enough — no
  need for the heavier `-base` variant.

Four failure modes hit and fixed while proving this (all encoded, none
left as tribal knowledge):

1. `scp` does not create destination directories → a `mkdir -p` shell
   provisioner must precede every `file` provisioner.
2. A trailing comment on a Makefile assignment keeps the spaces in the
   value → `tart pull "ghcr.io/…:latest "` fails to parse the name.
3. **`tart set --display` alone does not pin the resolution**:
   display-refit let the guest serve a 1280px-wide framebuffer while
   `tart get` still reported 1024x768, so every click coordinate was
   off. `--no-display-refit` is mandatory, and the script aborts if the
   measured framebuffer is not a 1024x768 multiple.
4. **Fixed sleeps cannot drive the privacy panes.** Rows render seconds
   after the window opens, and the base image restores a Terminal
   window that can sit *on top* of System Settings (the click then
   lands in the shell and the password is typed at the prompt —
   `zsh: command not found: admin`). The script now pixel-probes an
   anchor (pane-white ⇒ Settings frontmost) plus the first row's dark
   icon before clicking, retries 3×, kills the restored Terminal, and
   the recipe disables window restore. Note the toggle itself is
   near-white whether on or off, so it cannot be its own probe —
   readiness must be read from the icon, and success from
   `peekaboo permissions status`, never from the pixels.

## Verify loop — `make verify` closes the circle (2026-08-03)

`verify.sh` is no longer a skeleton: `make verify PROFILE=wand` builds
wand on the host, clones the baked base, drives the tome panel headless
in the clone, asserts the fixture rows in the AX tree, captures the
pixels, and destroys the clone. Observed end-to-end, repeatedly, on a
base baked the same day by `make bake`.

### Shape

| stage | where | what |
|---|---|---|
| profile | host | `profiles/<x>.toml` = the per-app variable surface (`yq -p toml`) |
| build | host | detached git worktree → persistent cert → signed `.app` |
| stage | host | `~/.tart/capsule-stage/<x>/` — the only thing the guest sees |
| clone | host | `tart clone` + `--display 1024x768 --no-display-refit` |
| reset | guest | assert user activity, quit the leftover consent UI |
| drive | host | `drivers/<x>.sh` defines `drive()`, uses the loop's helpers |
| assert | host | AX tier gates; pixels are a bonus artifact |

The **driver runs on the host** and reaches into the guest through
`vm` / `pb` / `click` / `ax_dump` / `snap`. That keeps the guest
toolchain-free (JSON is parsed here) and keeps a driver readable as a
sequence of intentions rather than SSH quoting.

**Build in a detached worktree, not in the app's checkout.** The loop
does `git worktree add --detach ~/.tart/capsule-work/<x>` and builds
there, so it can pin any local ref — including an unpushed branch,
since worktrees share the object store — without checking anything out
in the tree a human or another session has open. That was one of the
original reasons for capsule (a parallel session's `main` checkout
silently swapped the binary under a running acceptance test), and it
would have been reintroduced by a `git checkout` in the shared tree.
The cost is that **uncommitted work is not verified** — commit first.

### Verified this run (each one changed the code)

- **A host-signed app inherits the ssh-context AX grant.** `capsule-base`
  carries grants for `sshd-keygen-wrapper` only — nothing ever granted
  `Wand.app` anything in this image — yet the event tap installed and
  the middle-click opened the tome. So the gate's per-app grant was not
  load-bearing, and **no per-app TCC bake is needed**: launch the signed
  bundle as a direct child of the SSH session. It must *not* go through
  `open`, which re-parents it to launchd and drops that responsibility.
- **AX answers ~25 s before the screen composites.** In a fresh clone
  SSH is up at t+10 s with Dock, Finder, menu-bar AX and window lists
  all live — while `peekaboo image` still returns the 22 KB **boot
  splash**. An idle framebuffer keeps serving it; `caffeinate -u` is
  what moves it (t+19 s → t+25 s in the probe). The loop therefore
  asserts user activity for the whole run, the recipe disables display
  sleep, and `snap` retries until the frame is a composited one
  (~150 KB without wallpaper, ~670 KB with; splash ~22 KB at 1024×768).
  A run that never composites loses a bonus artifact, never a PASS.
- **The VNC framebuffer width is not stable early in boot.** A capture
  taken right after `tart run` reported 1280 px on a VM pinned to
  1024×768, settling seconds later; the same base has been observed
  serving both 1× (1024) and 2× (2048). The consent script now *probes
  until it settles* and only aborts if it never does — an abort on the
  first sample turned a boot race into a failed bake.
- **The consent flow's own alert blocks the consent flow.** Registering
  `sshd-keygen-wrapper` raises the "…would like to control this
  computer" alert, and it lands exactly on the row area (x 283–741,
  y 155–333), so the row probe reads alert chrome forever. Its "Open
  System Settings" button dismisses it *and* re-fronts the pane; the
  same point is empty pane when no alert is up, so clicking it
  unconditionally (once the pane is frontmost) is safe.
- **System Settings comes back in every clone, and the bake cannot stop
  it.** `pkill -x "System Settings"` leaves `systemsettingsagent`, which
  relaunches the app within seconds — so it was running at shutdown.
  Killing the whole bundle (`pkill -f "System Settings.app/Contents"`)
  makes it stay dead *within a boot*, but a fresh clone still logs in
  with it running under ppid 1, with no `TALAppsToRelaunchAtLogin` and
  no Saved Application State to clear. Mechanism unidentified; the loop
  therefore **resets the lab at run start** instead of trusting the
  image. Without it the frontmost app is a variable no profile declared
  (wand's tome header renders it).
- **`peekaboo inspect-ui --json` escapes the element listing.** The
  human-readable dump lives in `.data.text` as an escaped string, so
  grepping the JSON for a label silently never matches. `ax_dump`
  writes both the JSON and the extracted text; drivers assert on the
  text, because peekaboo's schema is not a contract and the fixture's
  labels are.

### `patched-deps` — proven, and it must point at a capsule-owned clone

Exercised against wand with sill overridden, three legs (2026-08-03):
the run passes and `.build/workspace-state.json` reports sill
`state=edited` at the given path; breaking that tree fails the build
with errors naming *that* path (so the override is genuinely what
compiles); and a profile that declares no override clears the edit.

That last leg was a bug this test found: **SwiftPM's `edit` state is
sticky**. It lives in the build worktree, so once a profile had
overridden a dependency, every later run kept using the local copy —
the loop would have gone on verifying something no profile declared.
The loop now clears every edited dependency before applying the
profile's list.

**Point `patched-deps` at a clone capsule owns, not at the app repo's
live checkout.** The obvious `sill=/Volumes/workspace/.../sill` was
tried and rejected: that tree belonged to another session, sitting on a
probe branch at v6 with a dirty `Package.swift`, while wand pins v5 —
i.e. it reintroduces exactly the cross-session coupling capsule exists
to remove, and makes the build depend on someone's uncommitted state.
Clone the ref you want into `~/.tart/capsule-deps/<name>` (detached at
a commit) and point there; a `~` in the path is expanded.

### Reproducibility — the recipe was re-run from scratch (2026-08-03)

The central claim of this repo ("recipe is the source, the image is a
disposable cache") had never been exercised: every green run so far had
used the *first* baked image, and `packer build -force` — the path that
destroys the image it is replacing — had never run against an existing
image of the same name. Both were closed in one pass:

    tart clone capsule-base capsule-base-prev    # CoW fallback, ~0 disk
    make bake                                    # EXIT=0, packer 46 s
    make verify PROFILE=wand                     # EXIT=0

`-force` replaced `capsule-base` cleanly, `provision/30-consent-core.sh`
granted Accessibility + Screen Recording unattended over VNC, and the
fresh clone of the *rebuilt* base passed the whole wand loop — tome
panel open, AX listing Alpha / Beta / Sort, a 1.2 MB composited
screenshot. So a lost image now costs ~4 minutes, not a re-derivation.

Two method notes worth keeping:

- **A VM directory's `birthtime` does NOT survive as evidence of a
  re-bake.** `~/.tart/vms/capsule-base` still reports
  `birth=2026-08-03T11:04:46+0900` *after* a full `packer build -force`
  replaced it. Any "this image predates commit X" inference built on
  `stat -f %SB` is invalid; read the recipe's effect in the guest
  instead.
- This run also demonstrated the cross-session isolation capsule exists
  for, unplanned: the wand checkout was sitting on a `doc-consistency`
  branch belonging to another session, and the loop still built and
  verified `main` (bebd902) from its own detached worktree.

### Distribution — the `.tvm` round trip works, grants included (2026-08-03)

`make export` → `tart import` → `make verify` against the *imported*
image, measured the same day:

| step | result |
|---|---|
| `make export` | `capsule-base.tvm`, **20,182,250,094 B** (~18.8 GiB), ~29 s |
| `tart import` | ~13 s |
| `verify` on the import | **PASS** — Accessibility / Screen Recording / Event Synthesizing all Granted in the fresh clone, tome panel open, AX rows asserted |

So the baked TCC state rides inside the `.tvm` and survives the round
trip — the registry-free path is a real distribution mechanism, not a
theoretical fallback. It is also ~7 GB smaller than the 27 GB the OCI
base occupies. `make import` overwrites `$(IMAGE)`; import under another
name (`tart import x.tvm <other>`) when you want to keep the current one.

### Bootstrapping a machine that has no `capsule-base` (2026-08-04)

Two routes, and the canonical one is the recipe, not a parked blob:

- **`make bake` is the canonical bootstrap** — self-contained and
  human-zero end-to-end (§Bake result): packer builds headless, the
  consent script drives the in-VM TCC UI over VNC, zero host windows,
  zero prompts. A Claude session completes it alone. Prerequisites the
  scripts themselves point to when missing: `packer` (brew, exempt from
  the source-over-brew rule), vncdotool in `~/.tart/capsule-venv`, and
  the one-time ~27 GB `macos-tahoe-vanilla` pull; after the pull the
  bake is ~4 min. There is deliberately NO standing shared `.tvm` drop
  — since the bake is human-zero, a parked 19 GiB file is just a stale
  snapshot waiting to diverge from the recipe (§Image vs recipe).
- **`.tvm` import is the fast path when a peer Mac already has the
  image** — `make export` → move `capsule-base.tvm` (~18.8 GiB; AirDrop
  / external disk / LAN scp, whatever is at hand) → `make import`.
  **The `.tvm` alone is not enough**: the image's `authorized_keys`
  holds only the pubkey of the machine that baked it
  (`packer/base.pkr.hcl:98`), and `verify.sh` authenticates with the
  local `~/.tart/capsule-ssh/id_ed25519` — so the baker's
  `~/.tart/capsule-ssh/` must travel WITH the `.tvm`, or every SSH
  stage dies against an image that does not trust this host. (Read
  from the recipe; the 2026-08-03 round trip above was same-machine
  and never exercised the cross-machine key mismatch.)

`verify.sh` fails fast with both routes spelled out when the base
image is absent — the old message said only "run 'make bake' first"
and t-cc79 mis-read the Makefile's "one-time TCC consent" note as an
interactive step, so the guard now names the doc section instead of
re-abbreviating it.

## Adding an app — the three-file contract (proven with facet, 2026-08-04)

An app joins the rack with exactly three files; nothing in `verify.sh`,
the recipe, or the Makefile changes. facet was the second app through
(`make verify PROFILE=facet`, t-3jxz), which turned the "3 files per
app" claim from design into measurement.

| file | role | copy from wand, then change |
|---|---|---|
| `profiles/<app>.toml` | the per-app variable surface | `worktree`/`branch` → the app repo + ref; `app` → its bundle name; `signing`/`build` → its cert + package scripts; `fixture-dest` → the config path the app reads; `launch-env` → its debug env var |
| `drivers/<app>-<x>.sh` | `drive()` = launch, poke, assert | the poke (wand: middle-click; facet: a client-mode `--view tree` invocation of the same binary) and the AX assert (the fixture's labels) |
| `fixtures/<app>-<x>.toml` | a COMPLETE app config making the GUI deterministic | declare named, unmistakable content (facet: two labeled workspaces) so the assert proves *this* config rendered, not any default |

What generalized without change: the detached-worktree host build, the
persistent-cert signing step, the `:ro` share, launch-as-SSH-child
(the AX grant applied to facet exactly as it did to wand — second data
point for "no per-app TCC bake"), the fixture install, and the
artifact/verdict plumbing.

What did NOT generalize — found by this run, fixed in capsule:

- **peekaboo's `inspect-ui` cannot see SwiftUI content.** facet's
  SwiftUI tree surfaced as ONE opaque childless "system dialog"
  element (56 elements dumped, all of them menu bar) while the panel
  was visibly rendering both fixture workspaces on screen. A raw
  `AXUIElementCopyAttributeValue` walk sees the full hierarchy:
  `AXGroup/AXHostingView → AXScrollArea → AXOpaqueProviderGroup/
  AXOpaqueProviderList → AXHeading desc="WORKSPACE · ALPHA"`. So the
  blocker is peekaboo's walker, not the app's AX. This also explains
  icebox t-c4pv ("prism has 0 UI elements") — prism is SwiftUI too.
  The AX tier now runs on capsule's own walker,
  `helpers/ax-dump.swift` → `capsule-ax-dump`, baked into the image
  beside `capsule-click`; peekaboo remains the pixels + permissions
  tool. (Setting `AXEnhancedUserInterface` on the app was tried first
  and rejected with AXError −25208 — not a viable workaround.)
- **An app whose GUI is custom-drawn has no AX tier at all.** facet
  `main`'s AppKit tree is a single `draw()`-everything NSView: zero
  row elements under ANY walker. The profile therefore pins
  `feat/swiftui-tree-render-swap` (PR #448) — the SwiftUI render swap
  is precisely what makes the tree machine-readable, and it is the
  surface t-eedb needs verified anyway. Rule of thumb for the family:
  **SwiftUI (or real AppKit controls) = AX-verifiable; custom-drawn =
  screenshot-only.**
- **Two-mode binaries need no extra plumbing.** facet's tree is
  summoned by running the same shared bundle again in client mode
  (`facet --view tree` posts over the DNC and exits); the DNC delivery
  works fine between two SSH-spawned processes in the same user
  session. The client exits 0 whether or not a server heard it, so the
  driver's proof is always the AX assert, never the summon.

### Still unproven

- ~~The recipe does not pin peekaboo~~ — closed 2026-08-04 (t-qahk):
  `bake.sh` pins `PEEKABOO_PIN=3.9.4` (the version every measured
  peekaboo claim in this file was taken against) and aborts the bake on
  mismatch — peekaboo is the assert semantics, so a silent version
  change would change what PASS means. The second, unpinned path
  (`provision/10-clt.sh`'s guest-side `brew install peekaboo`) was
  removed. Bumping the pin = update it, re-verify every profile,
  re-read this file's peekaboo claims.
- ~~`profiles/sill-prism.toml` remains a skeleton~~ — closed 2026-08-04
  (t-c4pv): the premise WAS wrong — prism is an executableTarget inside
  sill (an `akira-toriyama/prism` repo does not exist), so the profile
  builds the sill worktree with `patched-deps = []`. First green run
  the same day: 268 AX elements in a fresh clone (peekaboo 3.9.4 saw 0
  on this same app, the t-c4pv measurement), fixture theme + WidgetPage
  chrome asserted, bonus screenshot captured. Two constraints the run
  surfaced, both encoded in the profile/driver comments:
  - **A pure-SwiftPM executable with resources resists .app packaging.**
    The generated `Bundle.module` accessor probes exactly two paths:
    `Bundle.main.bundleURL/<name>.bundle` and the absolute host
    `.build` path. Launched from `Contents/MacOS` the bundleURL is the
    bundle ROOT, which codesign refuses to seal ("unsealed contents
    present in the bundle root") — both candidates are dead ends. The
    profile reproduces the `swift run` shape INSIDE the bundle: real
    binary + resource bundles side by side under
    `Contents/Resources/bin/`, and `Contents/MacOS/<exe>` is a shim
    that execs it (Foundation then treats it as a flat launch, so the
    bundle is found beside the binary and everything stays sealed).
  - **The shim's un-normalized exec path is the process command line**
    (`…/Contents/MacOS/../Resources/bin/prism`), so drivers must
    pgrep/pkill on `Resources/bin/prism` — a `/Contents/Resources/…`
    pattern silently never matches and reads as "app did not start".
