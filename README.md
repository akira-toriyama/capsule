# capsule

![platform](https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey)
![tool](https://img.shields.io/badge/Tart-2.30%2B-blue)
![license](https://img.shields.io/badge/license-MIT-blue)
![status](https://img.shields.io/badge/status-working-brightgreen)

Reproducible, disposable **[Tart](https://tart.run)** macOS VMs for
**headless GUI verification** of the akira-toriyama Swift app family
(wand, sill, prism, facet, …).

Host-machine GUI automation steals focus, moves windows, and switches
Spaces — it disrupts the developer at the keyboard and is
non-deterministic (multi-display coords, toolchain drift, TCC
flakiness, cross-session repo collisions). capsule moves the whole
verify loop into a throwaway VM: **throw a capsule, a clean lab
appears; fold it away, it's gone.** The point is an environment
**Claude Code can drive end-to-end from the terminal, with zero host
disruption.**

## The loop (daily, cheap)

```
tart clone <base> <ephemeral>     # APFS copy-on-write — instant, ~0 disk
tart run  --no-graphics --dir=capsule:~/.tart/capsule-stage/<x>:ro <ephemeral>
  → drive with capsule-ax-dump (AX) + peekaboo (pixels) + capsule-click (middle-click)
  → screenshot / AX-read the result
tart delete <ephemeral>           # reclaims only the delta
```

The share is one directory — the staged, signed bundle plus its
fixture — and nothing else from the host.

Always `export TART_NO_AUTO_PRUNE=1` around the loop — a bare
`tart clone`/`pull` auto-prunes the OCI cache (100 GB LRU default) and
can silently evict your other VMs.

## Recipe, not image (ship both, recipe is the source of truth)

The **recipe** — `provision/*.sh` + `packer/base.pkr.hcl` — is the
diffable, reviewable, reproducible source. The baked ~27 GB image is a
**disposable local cache** (`tart export` → `.tvm`); it is never
committed and not pushed to a registry by default (`tart push` has no
layer reuse, so every re-bake would re-upload ~27 GB —
[cirruslabs/tart#771](https://github.com/cirruslabs/tart/issues/771)).
This is the family north star applied to VMs: a pushed image is a
*stale brew-snapshot*; the recipe is the *source*.

> Baking never needs GitHub-hosted CI (Apple's Virtualization
> Framework nests **Linux** guests only, so a Tart macOS VM can't run
> on a hosted macOS runner). Bake **locally** on the host Mac — it runs
> inside an isolated VM over SSH and does **not** touch host apps, so
> baking is not host-disruptive. A self-hosted Apple-silicon runner can
> auto-bake later (that's how cirruslabs bakes its own base images).

## Status

✅ **Both commands work end to end (2026-08-03); ten profiles are
racked.**

```
make bake                 # rare:  vanilla -> consented capsule-base, zero touches
make verify PROFILE=wand  # daily: host build -> clone -> drive -> assert -> destroy
```

`make verify PROFILE=<x>` builds the app from a detached worktree,
signs it with the persistent cert, clones the baked base, launches the
bundle from a read-only share in a `--no-graphics` VM, drives it
(wand: `capsule-click` middle-clicks the tome open), asserts, captures
the pixels, and destroys the clone — no consent prompts, no host
windows, nothing typed by hand.

| profile | gate |
|---|---|
| `wand` | AX labels: the tome panel lists the fixture rows |
| `facet` | AX labels: the tree sidebar lists the fixture workspaces |
| `facet-grid` | AX labels: the grid overlay lists the fixture workspaces as `index (label)` cells |
| `facet-rail` | AX labels: the rail strip lists the fixture workspaces as `index (label)` cells |
| `facet-isolate` | log + AX: `--view grid` / `--view rail` are refused on an isolate desktop, the tree still renders |
| `facet-degrade` | AX geometry: by-workspace degrade tree, header-drag probe |
| `sill-prism` | AX labels: the gallery shows the fixture theme + WidgetPage chrome |
| `halo` | AX geometry: the ring hugs Calculator at +48/+48, hot-reload drops it |
| `perch` | the app's own AX reader, plus a DNC round trip in the log |
| `chord` | the daemon's query socket (`verify-tier = "daemon"`) |

A profile's `verify-tier` names the gate class: `ax` (the AX dump
alone), `screenshot` (AX gate plus a bonus pixel artifact — Screen
Recording re-confirms ~monthly, so pixels never fail a run), or
`daemon` (no AX surface at all; the app's own control channel gates).

The load-bearing surprise: **the app inherits the ssh-context
Accessibility grant**, so there is no per-app TCC bake — as long as the
signed bundle is launched as a child of the SSH session and never via
`open`. That and every other measured fact (AX answers ~25 s before the
screen composites; the consent alert covers the row it is trying to
toggle; System Settings relaunches in every clone) are recorded in
[docs/design.md](docs/design.md) §Verify loop; the gate classes are
measured in §The gate taxonomy.

## Layout

| path | what |
|---|---|
| `packer/base.pkr.hcl` | recipe that bakes the shared core into an image |
| `provision/` | provision steps (1024×768 display, TCC bake-by-consent, optional CLT) |
| `helpers/click.swift` | middle-click via CGEvent — peekaboo has no middle button |
| `helpers/ax-dump.swift` | raw AX-tree walker — peekaboo's inspect-ui is blind to SwiftUI subtrees |
| `profiles/` | per-app manifests: what to build, what the guest needs, which driver |
| `drivers/` | per-app drive+assert scripts; each defines `drive()` |
| `fixtures/` | config fixtures for acceptance runs |
| `verify.sh` · `bake.sh` · `Makefile` | the loop + the rare local bake |

## Requirements

Host: `tart` 2.30+ on an Apple-silicon Mac (macOS 15+), `peekaboo`
(screenshots + permission checks), `yq` + `jq` (profiles and JSON are
parsed host-side so the guest stays toolchain-free). Baking additionally needs
`packer` and `vncdotool` + `pillow` in a venv at `~/.tart/capsule-venv`
(override with `CAPSULE_VNCDO`).
