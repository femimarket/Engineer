# Engineer

A SwiftUI-based image generation client that combines prompt engineering with a persistent history of results. It allows users to build complex prompts using modular "chips," synthesizes them via AI, and generates images using a Rust-backed FFI API.

## Overview

**Engineer** is a productionized iOS application designed for iterative image generation. It evolved from a playground prototype into a full app with disk-backed persistence and real backend integration.

### Key Features
*   **Chip-Based Prompt Builder**: Construct prompts by adding, editing, and arranging text "chips."
*   **AI Synthesis**: Automatically refines raw ideas into optimized prompts using the Qwen model before generation.
*   **Dual Generation Modes**:
    *   **Text-to-Image**: Uses Flux2Pro for standard generation.
    *   **Cast Mode**: Uses Flux2KleinI2I for image-to-image generation using reference characters/targets.
*   **Persistent History**: All generated images and their associated metadata (chips, likes, model info) are saved to disk as PNGs with embedded IPTC/XMP metadata.
*   **Smart History Management**: Results are grouped into batches based on generation time. The history is automatically trimmed to a maximum count, prioritizing "liked" items.
*   **Undo Support**: Accidental removal of results can be undone via a toast notification.

## Architecture

The app follows a clean separation between UI, business logic, and persistence.

### Core Components

1.  **`ContentView.swift`**: The main UI entry point.
    *   Manages the state of `Chip`s (the prompt builder) and `Run`s (generation history).
    *   Handles the `ImageService` interactions.
    *   Implements custom layouts (`ChipFlowLayout`) and animations.
2.  **`ImageService.swift`**: A singleton that wraps the `Api` module.
    *   Handles authentication configuration.
    *   Provides async methods for `chatSynthesize`, `generate`, and `castGenerate`.
    *   Abstracts the Rust FFI calls (`Api.flux2Pro`, `Api.qwen3_6_35b_a3b`, etc.).
3.  **`ProjectService`**: (External Module)
    *   Handles file system operations.
    *   Manages reading/writing PNGs with embedded metadata (IPTC keywords for chips, StarRating for likes).
    *   Provides URLs for local assets.
4.  **`Api`**: (External Module)
    *   Rust FFI bindings for backend services.
    *   No URLSession or OpenAPI clients; direct static functions returning `Data`.

### Data Persistence Strategy

*   **Chips (Prompt Builder)**: Stored in `UserDefaults` as JSON. This allows the user's current draft to survive app launches without being treated as a "generation."
*   **Runs (History)**: Stored as individual PNG files in the app's `Documents` directory.
    *   **Filename**: `<UUID>.png`.
    *   **Metadata**: Embedded in the PNG file using IPTC/XMP standards.
        *   `Subject`: Chip texts.
        *   `Caption/Abstract`: Joined prompt.
        *   `Software`: Model name used (e.g., "Flux2Pro").
        *   `StarRating`: Like status.
    *   **Indexing**: The app scans the `Documents` directory on launch to reconstruct the `runs` array. The file creation date is used for sorting and batching.

## Installation & Setup

### Prerequisites
*   Xcode 15+
*   iOS 17+
*   A valid backend API user and password.

### Configuration
The application requires authentication credentials to be passed at launch. These are **not** hardcoded.

1.  Open the project in Xcode.
2.  Go to **Product > Scheme > Edit Scheme...**
3.  Select **Run** from the left sidebar.
4.  Navigate to the **Arguments** tab.
5.  Under **Arguments Passed On Launch**, add the following:
    *   `-u` followed by your API username.
    *   `-p` followed by your API password.

    *Example:*
    ```text
    -u
    your-username-here
    -p
    your-password-here
    ```

**Note**: If these arguments are missing, the app will crash on launch with a `preconditionFailure` to prevent silent authentication errors.

## Usage

### Building a Prompt
1.  Tap the **+ add** button to create a new chip.
2.  Type your phrase and press **Next** or **Done**.
3.  Tap any existing chip to edit its text.
4.  Tap the **x** on a chip to remove it.
5.  Use the **Presets** rail (e.g., "Cinematic", "Neon") to quickly insert common style descriptors.
6.  Tap **CLEAR** to reset the entire prompt.

### Generating Images
1.  Ensure at least one chip is present.
2.  Tap the **Generate** button.
    *   This triggers `parallelRuns` (default 3) concurrent generations.
    *   Each run first sends the prompt to the Qwen model for synthesis.
    *   The synthesized prompt is then sent to the image generation model (Flux2Pro or Flux2KleinI2I depending on configuration).
3.  New rows appear in the **RESULTS** section with a shimmering loading state.

### Managing Results
*   **Restore**: Tap any result row to load its prompt back into the editor.
*   **Like**: Tap the heart icon to mark a result as a favorite. Liked items are preserved when history is trimmed.
*   **Retry**: Tap the refresh icon on a failed or loaded result to regenerate it.
*   **Remove**: Tap the x icon on a result. A toast appears allowing you to **Undo** the removal within 3 seconds. If not undone, the file is deleted from disk.
*   **Filter**: Tap the **LIKED** chip in the Results header to toggle between showing all results or only liked ones.

## Key Files

| File | Description |
| :--- | :--- |
| `Prod/ContentView.swift` | Main view, state management, persistence logic (`Store`), and UI components. |
| `Prod/ProdApp.swift` | App entry point, handles command-line argument parsing for credentials. |
| `Api` (Module) | Rust FFI bindings for backend API calls. |
| `ProjectService` (Module) | File system and metadata handling utilities. |

## Technical Details

### Concurrency
*   Generation tasks are tracked in an `inflight` dictionary keyed by `Run.ID`.
*   If a user removes a result while it is still generating, the corresponding `Task` is cancelled to prevent unnecessary API calls and memory usage.
*   `ImageService` is marked `@unchecked Sendable` due to its internal mutable state (credentials), but access is synchronized via the singleton pattern and main-thread dispatch where necessary.

### Metadata Embedding
The app relies on `ProjectService` to embed metadata into PNGs. This allows the app to be stateless regarding history storage—the disk file itself is the source of truth.
*   **Chips**: Stored as IPTC `Subject` keywords.
*   **Like Status**: Stored as IPTC `StarRating`.
*   **Model**: Stored as TIFF `Software`.

### UI Conventions
*   **Dark Mode**: The app is designed for dark mode (`preferredColorScheme(.dark)`).
*   **Haptics**: Subtle haptic feedback is used for taps, edits, and errors via `UIImpactFeedbackGenerator` and `UINotificationFeedbackGenerator`.
*   **Animations**: Spring animations are used for chip additions/removals and row transitions to provide a fluid feel.
*   **Accessibility**: All interactive elements have `accessibilityLabel` and `accessibilityHint` attributes.