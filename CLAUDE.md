# capsule operating policy

- **This repo's operator and reader is Claude Code only** (no human edits
  or reads it closely). PR creation, push, merge, deploy and bake may all
  run autonomously. Do not stop to wait for confirmation; keep moving as
  far as quality can be guaranteed.
- **Every document and comment is written for Claude Code.** No
  human-oriented courtesies (translated READMEs, decorative comments,
  Japanese sections in commit bodies). No README.ja.md (removed
  2026-08-02).
- **VMs and images are disposable**: destroying or deleting a VM has
  practically no effect on the host, so do it freely. **Breaking changes
  are fine** — break clean, leave no compat layer.
- **Granted (user's own words, 2026-08-02)**: each Swift app repo may be
  cloned into a VM for verification, and pushes to
  `ghcr.io/akira-toriyama/demo-base` are fine. VM work proceeds without
  waiting for confirmation.
  The push grant is **not exercised**, though — there is no layer reuse
  (cirruslabs/tart#771), so a registry push is not part of the design;
  distribution is the `.tvm` from `make export`
  ([docs/design.md](docs/design.md) §Image vs recipe and the Makefile's
  missing `push` target are the record). The grant stays on file for the
  day a registry becomes necessary.
- Purpose: the headless GUI verification environment (Tart VM) for the
  akira-toriyama Swift app family (wand, sill, prism, facet, …). Design
  decisions and measured facts live in [docs/design.md](docs/design.md),
  the canon.
- The entry point from a Swift app repo into this environment is the
  dotfiles-managed `macos-gui-verify` skill (that is where the route to
  capsule lives).
