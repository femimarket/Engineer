# Engineer

A SwiftUI-based prompt builder and image generation client. It allows users to compose image prompts using modular "chips," synthesizes them via an LLM, and generates images using a Rust-backed FFI API. Results are persisted locally with metadata embedded directly into the image files.

## Features

- **Chip-Based Prompting**: Build prompts by adding, editing, and removing text chips.
- **LLM Synthesis**: Automatically refines raw ideas into optimized image prompts using Qwen.
- **Image Generation**: Generates images via Flux2Pro (text-to-image) or Flux2KleinI2I (image-to-image/cast mode).
- **Persistent History**: All generated images and prompts are saved to disk. Metadata (chips, likes, model info) is embedded as IPTC/XMP tags within the PNG files.
- **Smart Batching**: Results are grouped into batches based on generation time.
- **Undo & Favorites**: Remove results with a 3-second undo window; mark favorites to protect them from history trimming.

## Architecture

The application follows a clean separation between UI, business logic, and persistence:

1.  **UI (`ContentView.swift`)**: Handles the chip editor, preset rail, and results list. It manages state for in-flight generation tasks and local undo buffers.
2.  **Persistence (`Store` in `ContentView.swift`)**:
    *   **Chips**: Saved to `UserDefaults`.
    *   **Runs/Images**: Saved to the app's `Documents` directory. Each run is a single PNG file.
    *   **Metadata**: Instead of a separate database, metadata is embedded in the PNGs using `ProjectService`.
        *   **Chips**: Stored as IPTC Subject keywords.
        *   **Prompt**: Stored as IPTC Caption/Abstract.
        *   **Model**: Stored as TIFF Software tag.
        *   **Like Status**: Stored as IPTC StarRating.
3.  **Backend (`ImageService` in `ContentView.swift`)**:
    *   Wraps static functions from the `Api` module (Rust FFI).
    *   Handles the flow: `chatSynthesize` → `generate` (or `castGenerate`).
    *   Returns raw `Data` which is then saved to disk.

## Key Files

*   `ContentView.swift`: The main application entry point for the UI. Contains all models (`Chip`, `Run`, `RunBatch`), the `Store` persistence logic, `ImageService` backend wrapper, and the `ContentView` view struct.
*   `ProdApp.swift`: The `@main` app struct. Handles command-line argument parsing for credentials.

## Installation & Setup

### Prerequisites
*   Xcode 15+
*   iOS 17+ (due to SwiftUI features used)

### Configuration
The app requires authentication credentials to communicate with the backend API. These are passed via command-line arguments at launch.

1.  Open the project in Xcode.
2.  Go to **Product > Scheme > Edit Scheme...**
3.  Select **Run** from the left sidebar, then navigate to the **Arguments** tab.
4.  Under **Arguments Passed On Launch**, add the following:
    *   `-u` followed by your API username.
    *   `-p` followed by your API password.
    
    *Example:*
    ```
    -u
    your-username-here
    -p
    your-password-here
    ```

**Note**: If these arguments are missing, the app will crash on launch with a `preconditionFailure` to prevent silent authentication errors.

## Usage

### Building a Prompt
1.  Tap the **+ add** button to start a new chip.
2.  Type your idea (e.g., "cyberpunk city") and press **Next** or **Done**.
3.  Tap existing chips to edit them or the **×** button to remove them.
4.  Use the **PRESETS** rail to quickly insert common style modifiers (e.g., "Cinematic", "Neon").

### Generating Images
1.  Ensure you have at least one chip.
2.  Tap the **Generate** button at the bottom.
3.  The app will fan out `parallelRuns` (default 3) generation tasks.
4.  New rows appear with a shimmer effect while loading.
5.  Once complete, the image thumbnail appears.

### Managing Results
*   **Restore**: Tap any result row to load its prompt back into the editor.
*   **Like**: Tap the heart icon to favorite a result. Liked results are protected from automatic history trimming.
*   **Retry**: Tap the retry icon on a failed or existing result to regenerate it.
*   **Remove**: Tap the **×** icon on a result row. A toast notification appears with an **Undo** button for 3 seconds. If not undone, the image file is deleted from disk.
*   **Filter**: Tap the **LIKED** chip in the Results header to toggle between showing all results or only favorites.

### History Management
The app maintains a maximum of `maxRuns` (default 30) results. When the limit is reached:
1.  Unliked results are removed from the tail first.
2.  If the limit is still exceeded, the oldest remaining results are removed.
3.  Deleted results are permanently removed from disk.

## Technical Details

### Persistence Strategy
The app uses a "disk-as-index" approach for generated images.
*   **File Naming**: `<UUID>.png`
*   **Reading**: `Store.loadRuns()` scans the `Documents` directory, reads each PNG, extracts metadata via `ProjectService`, and reconstructs the `Run` objects.
*   **Writing**: `Store.saveRun()` writes the image data and embeds metadata using `ProjectService.saveFile`.

### Concurrency
*   Generation tasks are tracked in an `inflight` dictionary keyed by `Run.ID`.
*   When a result is removed, its corresponding task is cancelled to prevent unnecessary API calls and disk writes.
*   `ImageService` uses `@unchecked Sendable` because it wraps Rust FFI calls that are not natively Sendable but are safe to call from the main actor in this context.

### Error Handling
*   **API Failures**: If the Rust FFI returns sentinel data that cannot be decoded as a `UIImage`, the row state transitions to `.failed`.
*   **Local Errors**: Failures to read local files or decode images result in a `.failed` state and a haptic error feedback.