# glossary

Shared vocabulary so the user and Claude Code don't drift. Adding or
renaming a term lands in the same PR as the code change (house rule).

- **capsule** — this project; a reproducible, disposable Tart VM for
  headless GUI verification. Also the metaphor: throw it → a lab
  appears; fold it → gone.
- **base image** — the baked, cached macOS VM the recipe produces
  (`capsule-base`), stored in `~/.tart`. Built from
  `ghcr.io/cirruslabs/macos-tahoe-vanilla` (macOS 26 = the sill/wand OS
  floor); the heavier `-base` variant is not needed.
- **recipe** — the diffable source of truth: `provision/*.sh` +
  `packer/base.pkr.hcl` + `Makefile`. Bakes the base image. Lives in
  git; the image does not.
- **the loop** — the daily op: `tart clone` (copy-on-write) → `tart run
  --dir:ro` → drive → `tart delete`. Cheap; runs per verification.
- **bake** — the rare, local act of producing the base image from the
  recipe. Not doable on GitHub-hosted CI (no nested virt for macOS
  guests); runs on the host Mac or a self-hosted Apple-silicon runner.
- **bake-by-consent** — the mechanism for baked TCC grants: boot the
  base once and answer the AX + Screen-Recording prompts, then snapshot.
  Not a human touch — `provision/30-consent-core.sh` drives the panes
  over VNC with zero host windows. Alternatives (sqlite3 pre-seed,
  MDM/PPPC) are impractical here — see design.md.
- **shared core** — what every verify VM needs, identical across apps:
  macOS 26 base, 4CPU/8GB/50GB, single deterministic 1024×768 display,
  AX + Screen-Recording grants for the ssh context, a click helper +
  peekaboo, SSH admin/admin. Baked into the base image. Deliberately
  **no toolchain**: apps are built and signed on the host and arrive
  over a read-only share.
- **variable surface** — the per-app bits a **profile** parameterizes:
  which repo/worktree/branch to run, local dependency overrides, the
  fixture config, the persistent signing cert, and the driver script.
- **profile** — a `profiles/<app>.toml` capturing one app's variable
  surface. `profiles/wand.toml` is the worked example.
- **fixture** — a complete, self-contained app config used for an
  acceptance run (e.g. `fixtures/wand-tome.toml`).
- **the gate** — the risk-gated bring-up experiment that preceded the
  Packer bake: prove one headless vertical slice by hand first. Passed
  2026-08-03 and superseded by `make bake`; kept as a term because
  design.md records its result.
- **two-tier verify** — **AX-only** (peekaboo `inspect-ui`, *not* `see`
  — the window pipeline filters out non-activating panels — plus the
  app's own event-tap log) is human-zero *forever*; **screenshot**
  (peekaboo `image --mode screen`) is human-zero only within the
  Screen-Recording ~monthly re-confirm window. Default acceptance to the
  AX tier.
- **the signed-bundle invariant** — always drive the `package.sh`-signed
  `.app`, never a raw `swift build` binary: ad-hoc re-signing drops the
  baked AX grant (`event-tap: tapCreate failed`).
