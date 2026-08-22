# Implement the cover window

You are picking up a design that has been through five rounds of review and is settled. Your job is
to build it, on a Mac, where you can compile and actually look at it. Everything below has been
decided — the open questions are listed at the end and are the only ones worth reopening.

## Before anything else: two files on this branch have never been compiled

`Din/Views/ArtworkPlaceholder.swift` and `Din/Views/WaveShape.swift` were changed on a Linux runner
with no Swift toolchain. They are eye-checked, not verified. Start by running `make build`,
`make test` and `make lint`, and fix whatever those turn up before writing anything new. The design
intent is in the doc comments; keep it, fix the syntax.

Those changes: `WaveShape` gained a `closing` edge so a crest can be closed upward, and
`ArtworkPlaceholder` was relit so its light reads as coming from above rather than below. If the
lighting looks wrong on a real screen, the reasoning is in `litFace`'s doc comment — the lift below
each crest has to out-read the occlusion above it or the form goes bistable.

## The spec is the mockup

Open `meta/cover-window-mockup.html` in a browser. It is interactive: click the thumbnail, hover the
cover, drag the window's bottom-right corner. It is a faithful transcription — the window is
335 × 476 with the chrome sampled from `meta/Screenshot.png`, the waveform is drawn by the same
routine as `WaveformView` over the exact peaks `scripts/render_readme.swift` generates, and the
placeholder is a transcription of `ArtworkPlaceholder.swift`.

**Where this document and the mockup disagree, the mockup is right about pixels and this document is
right about intent.**

One thing to ignore: the mockup has a **Thumbnail position** toggle offering *Corner* and *Gutter*.
**Gutter is the chosen one.** The corner-flush variant is not being built.

`meta/artwork-mockup.html` is an earlier, rejected direction (a cover panel inside the queue window).
It is kept as the record of why the window collapses instead. Don't build it.

## Decided — do not reopen

- **One window changing shape, not a second window.** The window is already `.hiddenTitleBar`, so
  there is no chrome to fight; and `AppDelegate.shouldHandleTransportKey` gates on
  `window === mainWindow`, so a second window would silently kill space / `[` / `]` in cover mode.
- **Closing the cover restores the queue window's size**, exactly as it was.
- **The cover is square, aspect-locked, and clamped to 220–420 pt.**
- **The thumbnail is always present**, showing `ArtworkPlaceholder` when a track has no embedded
  cover. This is what stops cover mode having to snap back to the queue mid-playlist.
- **Nothing below the now-playing block moves.** That constraint drove the thumbnail's position and
  size; don't trade it away.

## The thumbnail

- **55 × 55 pt, inset 12 pt from the window's top and right edges.** Its bottom edge lands at 67 pt
  from the window top, which is exactly the bottom of the artist/album line. *That alignment is the
  spec* — if SwiftUI's real text metrics put the subtitle's baseline elsewhere, keep the alignment
  and let the number follow.
- 4 pt corner radius, hairline border at `Color.primary.opacity(0.16)`.
- It spans the titlebar band and the top of the content, so it has to escape the top safe-area inset
  that `.hiddenTitleBar` applies. Working that out is yours — I could not test it.
- A button, labelled "Show album cover". On hover *and* on keyboard focus it takes a
  `rgba(6,8,7,0.5)` veil with a white outward-corners glyph
  (`arrow.up.left.and.arrow.down.right`) centred, fading in over ~130 ms, so it reads as a door
  rather than a decoration.
- It punches a hole in the window's drag region. Known and accepted — it is the corner furthest from
  where people grab a window.

### What it costs, and what it must not cost

The now-playing title and subtitle take a **permanent right inset so they stop 89 pt clear of the
window's right edge** (the tile's left edge is 67 pt in, leaving a 22 pt gap). Long titles truncate
earlier than they do today.

That inset must not be released when a track has no artwork — the thumbnail is always there, and a
conditional inset would make titles reflow every time the playlist crossed an art-less track.

Everything below the now-playing block — transport, volume button, waveform, status bar, playlist —
stays exactly where it is today.

## The collapse

Clicking the thumbnail collapses the window to a square; the close control expands it back.

- `setFrame(_:display:animate:)`, anchored top-left the way macOS resizes anyway.
- Hide the standard window buttons while collapsed; restore them on the way out.
- `isMovableByWindowBackground = true` while collapsed — with no titlebar and no overlay at rest
  there is nothing else to grab.
- Lock the aspect with `contentAspectRatio = NSSize(width: 1, height: 1)`. **Clear it with
  `contentResizeIncrements = NSSize(width: 1, height: 1)`** — the two are mutually exclusive and
  setting either clears the other; there is no zero-ratio escape hatch.
- `contentMinSize` / `contentMaxSize` to 220 and 420 while collapsed, back to the queue's existing
  300 × 400 minimum on the way out.

### Sizing rules

- **First collapse** takes its side from the queue window's own width, clamped to 220–420. At the
  default width that makes the collapse purely vertical.
- **After that the square remembers its own size** across collapses.
- **Restoring returns the queue's _size_, not its frame.** If the square was dragged to another
  corner of the screen, the window comes back where you left it. Keep the current top-left and
  restore the old size — and remember macOS frames are bottom-left origin, so that means
  `origin.y -= newHeight - oldHeight`. Getting this wrong grows the window downward off the screen.
- Persist `din.coverMode`, `din.queueSize` and `din.coverSide` next to `din.repeat`. Note the
  existing keys are lowercase `din.`, whatever AGENTS.md says.

### Why 220 and 420

220 is derived: the hover overlay needs about 130 pt for title, transport, waveform and times, and
below roughly 220 the overlay stops being a scrim over a cover and becomes the whole window. 420 is a
judgement call — past it the square stops being something you park in a corner. Worth feeling out on
a real screen before it is final.

## The cover window

**At rest:** artwork edge to edge. No chrome, no text, no traffic lights.

**On pointer-over — and on focus-within, so it is reachable by keyboard —** two gradients fade in
over ~170 ms:

- **Top,** 72 pt tall, dark at the top fading to nothing by its bottom, carrying a 20 pt round close
  button inset ~12 pt from the top-left, filled `rgba(20,22,21,0.55)` with an inner hairline and a
  white glyph.
- **Bottom,** holding the track title (13 pt semibold), artist — album (11 pt), the transport row
  (24 pt, volume at the right) and the waveform (32 pt) with its time labels. Padded 84 pt at the
  top, 12 pt at the sides, 10 pt at the bottom. **The large top padding is load-bearing** — it
  pushes the gradient's soft end above the text so the title sits on the opaque part of the ramp
  rather than on a bleached patch of sleeve. Exact stops are in the mockup's `.cover-bottom`.

Two pieces of insurance for covers brighter than the scrim: a soft shadow under the text and under
the transport glyphs, and the waveform's unplayed bars lifting from `white.opacity(0.25)` to
`white.opacity(0.5)` when drawn over artwork. Without the second one they vanish against a pale
sleeve — the test case is this album's own cover.

## Where it goes in the code

- **`MetadataLoader`** — one more `commonKey` case: `.commonKeyArtwork` → `item.load(.dataValue)`.
- **Not on `Track`.** It is `Equatable` and `Hashable` and drives a `List`; image data on it makes
  every diff expensive. Follow the `waveformPeaks` precedent: a `@Published var currentArtwork` on
  `PlaylistManager`, loaded and cleared in the same place peaks are, on track change.
- **`ControlsView`** — the thumbnail and the reserved inset.
- **A new `CoverView`** for the square and its overlay. Its bottom half is the top of `ControlsView`
  with a gradient behind it; pulling the transport row out into its own small view keeps the two
  from drifting.
- **`WaveformView`** — an `overArtwork: Bool` that changes only the unplayed colour.

### The trap in `DinApp.swift`

`.github/workflows/assets.yml` compiles every source under `Din/` **except `DinApp.swift`**, because
`scripts/render_readme.swift` needs its own `@main`. Anything declared in that file is invisible to
that build.

This matters here specifically: the window poking naturally wants to live on `AppDelegate`, which is
in `DinApp.swift` — and the thumbnail is a *view* that has to trigger it. The moment a view refers to
something in `DinApp.swift`, `swift build` and CI stay green while the Assets workflow fails with
`cannot find … in scope`, pointing at the renderer rather than at the reference that caused it.

So put the cover-mode logic in **its own file**, not on `AppDelegate`. If it needs the content window
the way `AppDelegate.mainWindow` resolves it, consider moving that lookup into the new file and
having `AppDelegate` call it, rather than duplicating it. The file's own header comment says the same
thing: move things out rather than working around the exclusion.

### The README screenshot will change

`scripts/render_readme.swift` hosts the real `ContentView`, so the screenshot picks the thumbnail up
automatically. The fixtures are synthetic files with no embedded art, so it will render
`ArtworkPlaceholder` — which is a fair showcase, but decide deliberately whether
`poseForScreenshot` should also supply a cover. The Assets workflow regenerates the image; don't
hand-edit it.

## Open — ask before choosing

1. **The close glyph.** ✕ sits exactly where the red traffic light sits, so it will read as *close
   the window* when it means *go back to the queue*. The alternative is the same corner-arrows glyph
   as the thumbnail, pointing inward: less familiar, but it says what actually happens and leaves a
   real close button free to be a real close button. Default to ✕ if you get no answer.
2. **`ArtworkPlaceholder` at 335 pt.** Its `tileShape` superellipse is right in a 55 pt thumbnail,
   where it reads as the app's mark; blown up to fill the cover window it reads as a very large app
   icon in a box. Dropping the tile clip and border is one boolean and looks more like artwork, but
   it loses the one cue that says *this is not a cover*. The mockup shows both; my lean is full bleed
   for the big view, tile for the thumbnail.
3. **Floating window level while collapsed.** A square you park in a corner wants to stay visible,
   but always-on-top surprises people who didn't ask for it. Default off; a preference at most.
4. **A menu item and shortcut.** The thumbnail should not be the only way in — a View-menu toggle
   gives it a keyboard route and a name. ⌘J is free.

## Done means

- `make build`, `make test` and `make lint` all clean. Lint is `--strict`; CI runs the same.
- `make run`, and you have actually operated it: clicked the thumbnail, hovered the cover, dragged
  the square to both clamps, closed it, and confirmed the queue window came back the size it was.
- Checked in **both appearances** — the placeholder and the scrim behave differently in light, and
  the light mode of this window has never been looked at.
- `README.md`'s feature list updated, per the AGENTS.md checklist.
- `AGENTS.md` updated if you add a file, a defaults key, or anything else its architecture notes
  should carry.
- The explanation lives in the **pull request description**, not the commit messages — `master` only
  accepts squash merges, so the PR title becomes the commit message.

A last thing: the mockup's numbers are design intent, measured at 1:1 in a browser. They are not
SwiftUI layout advice. Where a constraint reads better than a constant — the thumbnail's alignment to
the subtitle, most of all — prefer the constraint.
