# ContentView — Image Iteration Screen

LLM-targeted documentation. Read this before modifying `ContentView.swift`.

## What this screen is

A frictionless image-iteration UI. One input image, many AI-generated
variations, one final keeper handed back to the caller via callback. Whole
thing is a single SwiftUI view file (`ContentView.swift`) plus a private
`ImageService` that wraps the generated `Api` Swift package.

## North star

**Frictionless > logic.** When in doubt, fewer taps wins, even at the cost
of flexibility. Premium minimal iOS vibe with music-video gloss (rich gloss
on hero/buttons, ambient color that tracks the hero's dominant tone).

One image in. Many iterations possible. One keeper out.

## Public contract

```swift
public struct ContentView: View {
    public init(
        initialImagePath: String,
        bearer: String,
        onCommit: @escaping (_ heroData: Data) -> Void
    )
}
```

- **initialImagePath**: full disk path to the starting image. Loaded once via
  `Data(contentsOf:)` + `UIImage(data:)`. **Must be readable** — invalid
  paths trigger `preconditionFailure` at init. The basename is the internal
  server-side filename for the first generation call.
- **bearer**: auth token. Source from Keychain / server-issued session.
- **onCommit**: fires once on `.onDisappear` (parent binding flip, swipe-
  down, or programmatic). Returns the raw bytes of the kept image — **never
  nil** because the screen always has a valid hero from init onward (either
  the initial path's bytes or a promoted variation's MediaApi bytes).

Server-side filenames are tracked internally for generation chaining but
never exposed publicly — servers cannot be relied on to persist filenames
indefinitely.

No custom structs at the public boundary — primitives only.

### Future revisit
Lineage (the chain of promoted heroes during the session) is currently not
returned. If callers need it later, add a second callback parameter — but
think hard about whether it's needed; the current product position is
single-keeper, lineage is internal state.

## Interaction model

### Two user verbs, one system verb

| Verb | Trigger | Effect |
|---|---|---|
| Promote | Tap a variation card | That variation becomes the hero. Previous hero slides into the history strip. The variation's server filename becomes the new `heroFile`, so next generation chains server-side. |
| Reset | Tap the header refresh icon | Wipes hero/history/variations/prompt/vibes back to the bundled demo defaults. |
| Save (system) | Sheet dismissal | `.onDisappear` fires `onCommit(CommitResult(...))` with the current hero + lineage. |

That's the entire interaction surface. There is intentionally no Save,
Discard, Heart, or Favorite verb.

### The SELECTED label

A single line of text (`• SELECTED`) sits under the hero. It's the only
discoverability signal that the hero is the kept item. Solves the implicit-
save model's only real weakness (first-time user can't see what will be
saved) without adding a verb.

### Tap-the-hero → fullscreen

Pinch-to-zoom (1×–6×), drag-to-pan when zoomed, double-tap toggles 1×↔2.5×.
Handled by `FullScreenImageView` in the same file.

## API flow

All calls go through the generated `Api` Swift package — specifically
`ApiAPI.api(...)` on `https://api.earnfemi.com/api`. Bearer is injected
once in `ImageService.init` via
`ApiAPIConfiguration.shared.customHeaders["Authorization"]`.

Per generation slot (we run 2 in parallel via `TaskGroup`):

1. **Generate** — `ApiAPI.api(action: .generate, model: .zimageturbo,
   image: <hero filename or "">, prompt: <vibes + prompt>)`. Returns an
   `API` with `id`, a server-issued `requestId`, and `status: .pending`.

2. **Poll** — every 3 seconds for up to 120 s:
   `ApiAPI.api(action: .poll, id: <same UUID>, requestId: <same>)`.
   Loops until `status == .completed` (or `.failed` / timeout).

3. **Fetch** — `MediaApi.fetch(<API.file>, idToken: bearer)`. MediaApi is
   the company-canonical media client (cached, pooled, 30s timeout). Decodes
   the returned bytes to `UIImage`.

Field meaning gotchas:
- `image` field on request = filename of an already-uploaded image, or `""`
  for server default. NEVER base64. The bundled demo PNG's filename
  (`demoUploadSong_019e7f3d-…png`) also exists on `femi.market`, so the
  first iteration references it directly — no upload needed.
- `image` field on response = echoed back input. Ignore it.
- `file` field on response = the result filename to fetch. THIS is what we
  download.
- `requestId` is the polling handle; pass it through on every Poll call.

## Key UX decisions (do not relitigate without reading these)

- **No Save button.** Implicit save matches Notes/Mail HIG pattern. Adding
  Save would be friction for a verb the system can infer from "what's the
  hero at dismiss time."
- **No Discard verb.** Variations not promoted are implicitly discarded by
  omission. Adding a discard verb adds a decision per iteration.
- **No heart / favorite.** Would tax every iteration with a "should I save
  this?" decision. Decision fatigue is the enemy of frictionless.
- **Single keeper per session.** The name "Iterate" implies convergence to
  one. We trade multi-keep flexibility for zero per-iteration decisions.
- **SELECTED label, not a coachmark.** Static, in the layout, always
  present. Coachmarks would be one-shot teaching; this is permanent
  affordance.
- **Hero capped at 60% screen height** so the bottom controls always fit.
- **Variations rail uses `HStack` (not Lazy).** Fine up to ~20-30
  variations. Past that, memory pressure starts to matter (each decoded
  UIImage ~4 MB).
- **Chrome color follows the hero** (`heroTint` extracted as the average
  pixel of the current hero). Keeps the ambient glow and hero drop shadow
  in tonal harmony with whatever image is loaded — no more cool magenta
  fighting a warm photo.

## Layout

```
┌─────────────────────────────────────┐
│ • ITERATE              (refresh ⟳)  │  header (wordmark + reset)
├─────────────────────────────────────┤
│                                     │
│       ┌──────────────────┐          │
│       │                  │          │
│       │   HERO (60%)     │          │  capped square photo
│       │                  │          │  tap → fullscreen
│       └──────────────────┘          │
│            • SELECTED               │  discoverability label
│                                     │
│   ┌─────┐ ┌─────┐ ┌─────┐           │  variations rail
│   │  V  │ │  V  │ │  V  │  ...      │  tap any → promote
│   └─────┘ └─────┘ └─────┘           │
│                                     │
│  [Cinematic][Neon][Moody][Pastel]   │  vibe pills (optional)
│  [✦ optional · refine the vibe   ]  │  prompt field (optional)
│  [        ✨ Generate           ]  │  primary CTA
└─────────────────────────────────────┘
```

Empty state (before first generate) shows two dashed-border ghost
placeholders in the rail position, tinted by the active vibes.

## State map

| State | Purpose |
|---|---|
| `hero: UIImage` | Current selected image (the kept item) |
| `heroFile: String?` | Server filename of the hero, fed to next `generate` |
| `heroTint: Color` | Dominant color of hero, drives ambient glow |
| `history: [UIImage]` | Past heroes for the back-strip |
| `historyFiles: [String?]` | Parallel filenames; powers `CommitResult.lineage` |
| `variations: [Variation]` | In-memory generated candidates |
| `selectedVibes: Set<String>` | Toggled vibe pills |
| `prompt: String` | Optional text refinement |
| `isGenerating: Bool` | Drives shimmer + button state |
| `pendingPlaceholders: Int` | Skeleton card count during generation |

All state is in-memory. Nothing persists between sessions; the parent
captures whatever it wants via `onCommit`.

## Future improvements (post-MVP)

### Secret multi-keep

Some power users will want >1 result per session. Adding a visible heart
would tax every iteration with a save decision. Plan:

- **Long-press a variation card** → system context menu with **Save** /
  **Discard**.
- Saved variations get a small heart badge in the top-right corner.
- `CommitResult` gains a `savedFilenames: [String]` array — same callback
  shape, additive change.
- Default tap-to-promote flow stays identical. Long-press is the escape
  hatch; first-time users never encounter it.

### Long-session memory ceiling

Today the rail holds full `UIImage`s in `variations`. At ~4 MB per
1024×1024 image, ~80–100 variations risks termination on mid-tier devices.
Fix paths if long sessions become a real use case:

- Swap `HStack` → `LazyHStack` so off-screen cards don't render.
- Cap the rail at N most recent; oldest drops off the back.
- Store filenames only; render via `AsyncImage` with the server URL.

### Other deferred polish

- **Pinch hint** on the fullscreen viewer (one-time overlay).
- **Accessibility labels** on icon buttons (reset, fullscreen X).
- **`NSPhotoLibraryAddUsageDescription`** in Info.plist — only needed if a
  Photos export path is added later.
- **Export to Photos** as a downstream verb on the kept image, never inside
  the iteration flow.

## File anatomy

```
ImageIterate2/
  ContentView.swift              — this screen (single file)
  ImageIterate2App.swift         — app entry, presents ContentView
  demoUploadSong_019e7f3d-…png   — bundled demo asset (also on server)
Api/                              — generated OpenAPI Swift package
  Sources/Api/APIs/ApiAPI.swift  — the only endpoint we call
  Sources/Api/Models/…            — API/Action/AiModel/Status etc.
```
