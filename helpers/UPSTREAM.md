# helpers — upstream tracking

The north star is *push shared responsibilities upstream, don't
re-implement*. These helpers exist only to fill a real gap in
[peekaboo](https://github.com/openclaw/Peekaboo) (the family's adopted
GUI-verification CLI; the repo moved from `steipete/peekaboo` →
`openclaw/Peekaboo`).

## `click.swift` — KEEP (load-bearing), pin, and try to delete via upstream

peekaboo `click` exposes only `--right` and `--double` — **no
middle-click / arbitrary mouse button**. Verified absent through peekaboo
HEAD 3.9.4 (2026-07-15), not just the installed 3.5.2. wand's **tome**
panel opens on a **middle-click**, so all five wand `t-k4hf` acceptance
items are undriveable without this ~60-line CGEvent shim.

- **Interim:** keep `click.swift`, pin the peekaboo version it
  complements, treat it as a clearly-deletable shim.
- **Upstream (non-blocking):** open an issue/PR on `openclaw/Peekaboo`
  for `click --middle` / `--button <n>` (+ `otherMouse` on `drag`/
  `swipe`). No existing issue found → no duplication. peekaboo is a
  third-party org repo, so landing is uncertain; **do not block** the
  capsule bring-up on it. When it lands, delete `click.swift`.

## `winlist.swift` — DROPPED (obsolete), intentionally not carried

The prior session hand-rolled a `CGWindowListCopyWindowInfo`-by-pid tool
because a window on a second display (x=3376) couldn't be located. That
is **already covered** by peekaboo:

```
peekaboo list windows --pid <pid> --include-details bounds,ids --json
```

returns per-window `bounds` by raw pid, and `list screens` reports
per-display offsets; peekaboo fixed multi-display coordinates back in
3.0.0. The prior "couldn't find it" was almost certainly `--app`
name-resolution, not a capability gap — and in a single-display
1024×768 VM the second-display case evaporates entirely. So `winlist`
is **not** included here; use the peekaboo command above.
