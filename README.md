# Prod

## Overview
Prod is a SwiftUI-based prompt engineering and image generation client. It provides a chip-based interface for composing image prompts, integrates with a Rust-backed FFI API for text-to-image and image-to-image synthesis, and maintains a persistent, disk-backed history of generations with embedded metadata. The app is designed for rapid iteration, parallel generation, and tactile feedback, with a dark-themed UI optimized for mobile and desktop touch/mouse interaction.

## Architecture & Key Files
- `Prod/ProdApp.swift` — Application entry point. Parses launch arguments for API authentication and instantiates the root view.
- `Prod/ContentView.swift` — Core application logic. Contains all domain models (`Chip`, `Run`, `RunBatch`, `PendingUndo`), the `Store` persistence layer, `ImageService` for backend communication, and the complete SwiftUI view hierarchy including custom layout and input components.
- External Modules:
  - `Api` — Rust FFI bindings exposing synchronous/async functions for `qwen3_6_35b_a3b` (chat synthesis), `flux2Pro` (text-to-image), and `flux2KleinI2I` (image-to-image/cast mode).
  - `ProjectService` — File I/O and IPTC/XMP metadata extraction/insertion. Handles disk storage under `Documents/` and provides URL resolution for generated assets.

## Setup & Running
1. Open the project in Xcode.
2. Configure launch credentials in the Xcode scheme:
   - `Product > Scheme > Edit Scheme... > Run > Arguments > Arguments Passed On Launch`
   - Add: `-u <user>` `-p <password>`
   - Missing credentials trigger a `preconditionFailure` on launch to prevent silent 401s downstream.
3. Build and run. The app requires a SwiftUI-compatible deployment target (iOS/macOS).

## Usage
### Prompt Building
- Tap the `+` button to add phrase chips. Max 20 chips allowed.
- Tap any chip to enter inline edit mode. Submit to save or leave empty to delete.
- Use the horizontal preset rail (`Cinematic`, `Neon`, `Moody`, `Pastel`, `Film`, `Surreal`, `Vintage`, `Dreamy`) for quick inserts.
- Tap `CLEAR` to reset the prompt builder.

### Generation
- Tap `Generate` to fan out `parallelRuns` (3) concurrent requests.
- Each run executes a two-step pipeline:
  1. `chatSynthesize`: Sends the joined prompt to Qwen3 for refinement. Falls back to the original idea if the model returns empty.
  2. `generate` or `castGenerate`: Routes to `Flux2Pro` (default) or `Flux2KleinI2I` (if character/target references are configured via `ProjectService.getCharacterCast()`).
- The UI displays `costPerGenerate` credits (1 credit × 3 parallel runs = 3 credits per tap).

### History & Results
- Generated images appear in a scrollable list, grouped into 2-second batches based on `createdAt`.
- Tap a result row to restore its prompt into the editor.
- Use the heart icon to like/unlike. Liked rows are preserved during history trimming.
- Use the trash icon to remove a row. A 3-second undo toast appears; tap `Undo` to restore it.

## Persistence & Metadata
Disk is the single source of truth. No separate database or JSON index is used.
- Each run is stored as a PNG in `Documents/<runId>.png`.
- Metadata is embedded directly into the PNG using IPTC/XMP fields:
  - **Chips & Prompt:** IPTC Keywords / Caption-Abstract
  - **Model Name:** TIFF Software tag (`Flux2Pro` or `Flux2KleinI2I`)
  - **Like State:** IPTC StarRating
- `Store.loadRuns()` reconstructs history by scanning `Documents/`, decoding PNGs, parsing IPTC fields, and sorting newest-first.
- Working chips (in-progress prompts) are cached separately in `UserDefaults` under `engineerChips.v1`.

## Key Conventions & Design Choices
- **Parallel Execution:** One tap creates `parallelRuns` independent `Task`s. Each is tracked in `inflight[Run.ID: Task]` and cancelled if the row is removed to prevent wasted API calls.
- **Batching:** Runs are grouped into 2-second windows (`floor(createdAt / 2)`) for UI cohesion. This works both in-memory and after disk reload.
- **Undo & Cleanup:** Removing a run adds it to `pendingUndos` with a 3-second `Task.sleep` timer. If not restored, the disk file is permanently deleted via `FileManager.removeItem`.
- **Dynamic Layouts:** 
  - `ChipFlowLayout` wraps chip views using custom `Layout` protocol logic.
  - `AutoChipField` dynamically resizes text fields based on content width using a `PreferenceKey` and invisible measuring mirror.
- **Haptics:** Tactile feedback via `UIImpactFeedbackGenerator` (soft/light) and `UINotificationFeedbackGenerator` (warning/error) for all interactive states.
- **History Trimming:** Automatically prunes to `maxRuns` (30). Unliked rows are evicted first; oldest excess rows are removed last.

## Error Handling & Resilience
- **API Failures:** The Rust FFI returns sentinel PNGs on lib-level failure. The client checks `UIImage(data:)` decoding; if it fails, the row transitions to `.failed` state and displays a retry button.
- **Cancellation:** `Task.checkCancellation()` is called between pipeline stages. If a row is removed mid-generation, the task exits cleanly without burning credits.
- **Like State Sync:** If a user likes a row while it's still loading, the like state is flushed to the IPTC StarRating immediately after the file is saved in `resolveReal`.
- **Keyboard Handling:** `scrollDismissesKeyboard(.interactively)` and a custom `.keyboard` toolbar with a `Done` button ensure smooth input flow.