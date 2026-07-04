# Engineer

A SwiftUI-based prompt builder and image generation client for Flux2 models. It allows users to construct complex image prompts using modular "chips," synthesizes them via an LLM, and generates images using a Rust-backed FFI API.

## Overview

**Engineer** is a productionized iOS application that evolved from a playground experiment. It serves as an "engineer screen" for building, refining, and generating AI images.

### Key Features
*   **Chip-Based Prompting**: Build prompts by adding, editing, and arranging text "chips."
*   **LLM Synthesis**: Automatically refines raw ideas into optimized Flux2 prompts using Qwen.
*   **Dual Generation Modes**:
    *   **Text-to-Image**: Standard generation via Flux2Pro.
    *   **Character Cast**: Image-to-Image generation using reference characters via Flux2KleinI2I.
*   **Persistent History**: All generated images and prompts are saved to disk. Images are stored as PNGs with metadata (chips, model, like status) embedded directly in IPTC/XMP fields.
*   **Batched Results**: Results are grouped by generation time for easy browsing.
*   **Undo & Favorites**: Soft-delete with 3-second undo toast, and a "Liked" filter for quick access to favorites.

## Architecture

The app follows a clean separation between UI, business logic, and persistence.

### Core Components

1.  **`ContentView.swift`**: The main UI and state manager.
    *   Manages the `chips` (prompt parts) and `runs` (generation history).
    *   Handles the `ImageService` calls for synthesis and generation.
    *   Implements `Store` for local persistence (UserDefaults for chips, File System for images).
2.  **`ImageService`**: A singleton that wraps the `Api` module.
    *   Handles authentication configuration.
    *   Exposes async methods: `chatSynthesize`, `generate`, and `castGenerate`.
    *   Delegates heavy lifting to the Rust FFI layer (`Api`).
3.  **`ProjectService`**: A utility module (imported) that handles file system operations.
    *   Saves/loads images to `Documents/`.
    *   Reads/writes IPTC metadata (Subject, Caption, StarRating).
    *   Manages character cast references.
4.  **`Api`**: The Rust FFI bridge.
    *   Static functions for calling backend services (`flux2Pro`, `qwen3_6_35b_a3b`, `flux2KleinI2I`).
    *   Returns raw `Data` (PNG bytes).

### Data Persistence Strategy

*   **Chips (Drafts)**: Stored in `UserDefaults` as JSON. This allows the prompt builder to survive app launches without being tied to a specific generation.
*   **Runs (History)**: The disk is the source of truth.
    *   Each generation results in a PNG file named `<UUID>.png`.
    *   Metadata is embedded in the PNG:
        *   **Chips**: IPTC Subject keywords.
        *   **Prompt**: IPTC Caption/Abstract.
        *   **Model**: TIFF Software tag.
        *   **Liked**: IPTC StarRating.
    *   On launch, `Store.loadRuns()` scans `Documents/`, decodes metadata from each PNG, and reconstructs the `Run` objects.

## Installation & Setup

### Prerequisites
*   Xcode 15+
*   iOS 17+
*   A valid backend API user and password.

### Configuration
The app requires API credentials to launch. These are passed via command-line arguments when running in Xcode.

1.  Open the project in Xcode.
2.  Go to **Product > Scheme > Edit Scheme...**
3.  Select **Run** from the left sidebar, then go to the **Arguments** tab.
4.  Under **Arguments Passed On Launch**, add:
    *   `-u` followed by your API username.
    *   `-p` followed by your API password.
5.  **Example**:
    ```text
    -u
    your-username-here
    -p
    your-password-here
    ```

> **Note**: If these arguments are missing, the app will crash on launch with a `preconditionFailure`. This is intentional to prevent silent failures or 401 errors during development.

## Usage

### Building a Prompt
1.  Tap the **+ add** button to create a new chip.
2.  Type a phrase (e.g., "Cinematic", "Neon lights") and press **Next** or **Done**.
3.  Tap any existing chip to edit its text.
4.  Tap the **x** on a chip to remove it.
5.  Use the **Presets** rail (e.g., "Moody", "Surreal") to quickly add common style descriptors.

### Generating Images
1.  Ensure at least one chip is present.
2.  Tap the **Generate** button.
    *   This fans out `parallelRuns` (default 3) generation tasks.
    *   Each run first calls the LLM to synthesize a detailed prompt from your chips.
    *   Then, it generates the image using the configured model (Flux2Pro or Flux2KleinI2I if character cast is set).
3.  Results appear in the **RESULTS** section with a shimmer loading effect.

### Managing History
*   **Restore**: Tap any past result row to load its prompt back into the editor.
*   **Like**: Tap the heart icon to favorite a result. Liked results are preserved when history is trimmed.
*   **Remove**: Tap the **x** in a result row to delete it.
    *   A toast appears at the bottom with an **Undo** button.
    *   If not undone within 3 seconds, the image file is permanently deleted from disk.
*   **Filter**: Tap the **LIKED** chip in the results header to toggle between showing all results or only favorites.

## Key Files

| File | Description |
| :--- | :--- |
| `Prod/ContentView.swift` | Main view, state management, persistence logic (`Store`), and UI components. |
| `Prod/ProdApp.swift` | App entry point. Handles argument parsing for API credentials. |
| `Api/` | (External Module) Rust FFI bindings for backend API calls. |
| `ProjectService/` | (External Module) File system and IPTC metadata utilities. |

## Technical Details

### Concurrency
*   Generation tasks are wrapped in `Task` objects and stored in an `inflight` dictionary keyed by `Run.ID`.
*   If a user removes a result while it is still generating, the corresponding task is cancelled to save API credits and bandwidth.

### UI Conventions
*   **Dark Mode**: The app is designed for dark mode (`preferredColorScheme(.dark)`).
*   **Haptics**: Subtle haptic feedback is used for taps, edits, and generation completion.
*   **Animations**: Spring animations are used for chip additions/removals and result row transitions.
*   **Scroll Behavior**: The prompt editor can scroll out of view. A floating pill appears to allow quick scrolling back to the editor.

### Error Handling
*   If image decoding fails (e.g., corrupted data), the row state becomes `.failed`.
*   Failed rows display a warning icon and offer a **Retry** button.
*   Network or API errors are caught and surface as `.failed` states without crashing the app.