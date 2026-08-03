# capsule

![platform](https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey)
![tool](https://img.shields.io/badge/Tart-2.30%2B-blue)
![license](https://img.shields.io/badge/license-MIT-blue)
![status](https://img.shields.io/badge/status-skeleton-orange)

Reproducible, disposable **[Tart](https://tart.run)** macOS VMs for
**headless GUI verification** of the akira-toriyama Swift app family
(wand, sill, prism, facet, focusfx, …).

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
tart run  --dir=product:…/.build:ro --dir=app:…/App.app:ro <ephemeral>
  → drive with peekaboo (screenshot + AX) + helpers/click.swift (middle-click)
  → screenshot / AX-read the result
tart delete <ephemeral>           # reclaims only the delta
```

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

✅ **Gate PASSED (2026-08-03).** The headless vertical slice ran
end-to-end in an ephemeral clone with zero consent prompts and zero
host disruption: signed `Wand.app` launched from a read-only share,
`helpers/click` middle-click opened the tome panel on a `--no-graphics`
WindowServer, `peekaboo inspect-ui` enumerated the fixture rows, and
`image --mode screen` captured real pixels. Full evidence + newly
verified facts (VNC-scripted consent, `sshd-keygen-wrapper` as the
ssh-context TCC key, `see`'s `layer != 0` panel limitation):
[docs/design.md](docs/design.md) §Gate result.

The consented local base is `capsule-gate-base` (rebuilt from the
cached `macos-tahoe-vanilla` — the three hand-made VMs are gone). Next
up: encode the proven manual steps into the Packer bake
(`packer/base.pkr.hcl` + `provision/*.sh`, still DRAFT/WIP). Tracked
as `projects/t-8ffm`.

## Layout

| path | what |
|---|---|
| `packer/base.pkr.hcl` | DRAFT recipe that bakes the shared core into an image |
| `provision/` | provision steps (CLT, 1024×768 display, TCC bake-by-consent, signing cert) |
| `helpers/click.swift` | middle-click via CGEvent — peekaboo has no middle button |
| `profiles/` | the 3 existing hand-made VMs captured as per-app manifests |
| `fixtures/` | config fixtures for acceptance runs |
| `verify.sh` · `bake.sh` · `Makefile` | the loop + the rare local bake |

## Requirements

`tart` 2.30+ on an Apple-silicon Mac (macOS 15+ host), `peekaboo`
(screenshot + AX), and `brew install packer` before the first bake.
