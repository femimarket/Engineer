# Engineer

**Engineer** is a SwiftUI-based iOS application for building image generation prompts using a modular "chip" interface and generating high-fidelity images via a Rust-backed FFI API. It combines a chat-based prompt synthesizer with direct text-to-image and image-to-image generation capabilities, persisting all results and prompt history to local disk.

## Features

*   **Chip-Based Prompt Builder**: Construct complex prompts by adding, editing, and removing individual text "chips."
*   **AI Prompt Synthesis**: Automatically refines rough ideas into detailed image prompts using the Qwen LLM before generation.
*   **Dual Generation Modes**:
    *   **Text-to-Image**: Uses Flux2Pro for standard generation.
    *   **Cast Mode (Image-to-Image)**: Uses Flux2KleinI2I for style transfer or character consistency, requiring reference images.
*   **Disk-Backed Persistence**: All generated images and prompt metadata are saved as PNGs with embedded IPTC/XMP metadata (chips, prompt, model, like status). Data survives app relaunches.
*   **Smart History Management**: Results are grouped into batches based on generation time. The history is automatically trimmed to the most recent 30 runs, prioritizing "liked" items.
*   **Undo & Recovery**: Accidental deletions of results can be undone via a toast notification. Failed generations can be retried individually.
*   **Visual Feedback**: Shimmer loading states, gradient backgrounds, and haptic feedback throughout the interface.

## Architecture

The application is built on a clean separation between the UI layer (`ContentView`), the business logic/service layer (`ImageService`), and the persistence layer (`ProjectService` / `Store`).

### Key Components

*   **`ContentView.swift`**: The primary view controller. Manages the state of chips, runs, and UI interactions. It orchestrates the generation pipeline:
    1.  **Synthesize**: Sends the user's idea to `Api.qwen3_6_35b_a3b` to get a refined prompt.
    2.  **Generate**: Calls `Api.flux2Pro` or `Api.flux2KleinI2I` based on configuration.
    3.  **Persist**: Saves the resulting image data to disk via `ProjectService`, embedding metadata.
*   **`ImageService.swift`**: A singleton that handles asynchronous calls to the backend API. It abstracts the Rust FFI calls (`Api` module) and handles local file reading for cast mode references.
*   **`ProjectService`** (External Module): Handles low-level file system operations, specifically saving PNGs with embedded IPTC metadata and retrieving reference images for cast mode.
*   **`Api`** (External Module): The Rust FFI bridge. Provides static methods for LLM chat and image generation, returning raw `Data`.

### Data Model

*   **`Chip`**: Represents a single phrase in the prompt. Stored in `UserDefaults` for the current editing session.
*   **`Run`**: Represents a single generation result. Contains the state (loading/loaded/failed), the associated chips, the image data, and metadata like `liked` status and `createdAt` timestamp.
*   **`RunBatch`**: A grouping of `Run`s that occurred within a 2-second window, used for UI organization in the results list.

### Persistence Strategy

The app uses a "disk is the index" approach for history.
*   **Files**: Each run is saved as `Documents/<UUID>.png`.
*   **Metadata**: Instead of a separate database, metadata is embedded in the PNG's IPTC/XMP fields:
    *   **Chips**: Stored as IPTC Subject keywords.
    *   **Prompt**: Stored as IPTC Caption/Abstract.
    *   **Model**: Stored as TIFF Software tag.
    *   **Like Status**: Stored as IPTC StarRating.
*   **Reconstruction**: On launch, `Store.loadRuns()` scans the `Documents` directory, reads the metadata from each PNG, and reconstructs the `Run` objects.

## Installation & Setup

### Prerequisites
*   Xcode 15+
*   iOS 17+
*   A valid backend API configuration (handled via `Api` module)

### Configuration
The app requires authentication credentials to communicate with the backend. These are passed via command-line arguments at launch.

1.  Open the project in Xcode.
2.  Go to **Product > Scheme > Edit Scheme...**
3.  Select **Run** from the left sidebar, then navigate to the **Arguments** tab.
4.  Under **Arguments Passed On Launch**, add the following:
    *   `-u` followed by your **User ID** (e.g., `019ec07a-c943-7275-b758-2315b8c9fa6f`)
    *   `-p` followed by your **Password**

    *Example:*
    ```
    -u
    019ec07a-c943-7275-b758-2315b8c9fa6f
    -p
    your_secure_password
    ```

> **Note**: If these arguments are missing, the app will crash on launch with a `preconditionFailure` to prevent silent authentication errors.

### Building
1.  Ensure all dependencies (`Api`, `ProjectService`) are resolved.
2.  Select a target device or simulator.
3.  Press **Cmd + R** to build and run.

## Usage Guide

### Creating a Prompt
1.  Tap the **+ add** button to start a new chip.
2.  Type a phrase (e.g., "Cinematic lighting") and press **Next** or **Done**.
3.  Repeat to add more phrases. You can tap any existing chip to edit it or tap the **X** to remove it.
4.  Use the **PRESETS** rail to quickly insert common style descriptors (e.g., "Neon", "Moody", "Vintage").

### Generating Images
1.  Ensure you have at least one chip in the prompt editor.
2.  Tap the **Generate** button at the bottom.
    *   This fans out `parallelRuns` (default 3) generation tasks.
    *   Each run will show a shimmering placeholder while processing.
3.  The app will first send your chips to the LLM for synthesis, then generate the images.
4.  Results appear in the **RESULTS** section, grouped by time.

### Managing Results
*   **Restore**: Tap any result row to load its prompt back into the editor for editing or re-generation.
*   **Like**: Tap the heart icon to mark a result as a favorite. Liked items are protected from automatic history trimming.
*   **Retry**: If a generation fails (indicated by an exclamation mark), tap the retry arrow to regenerate that specific run.
*   **Remove**: Tap the **X** on a result row to delete it. An undo toast will appear for 3 seconds if you change your mind.
*   **Filter**: If you have liked items, a **LIKED** filter chip appears in the Results header. Tap it to view only favorited images.

### Cast Mode (Image-to-Image)
If `ProjectService.getCharacterCast()` returns valid reference files, the app automatically switches to **Cast Mode** (Flux2KleinI2I) during generation. This allows you to maintain character consistency or apply specific styles using reference images stored in the app's documents directory.

## Key Files

*   `Prod/ContentView.swift`: Main UI logic, state management, and generation orchestration.
*   `Prod/ProdApp.swift`: App entry point and argument parsing.
*   `Api/`: External module containing Rust FFI bindings for LLM and Image generation.
*   `ProjectService/`: External module handling file I/O and IPTC metadata embedding.

## Troubleshooting

*   **Crash on Launch**: Check that `-u` and `-p` arguments are correctly set in the Xcode Scheme.
*   **Failed Generations**: If images fail to load, check the network connection. The app uses a Rust FFI backend; ensure the backend service is running and accessible.
*   **Missing Metadata**: If results do not appear after a restart, ensure the app has File System permissions. The app relies on scanning `Documents/` for PNGs.
*   **Empty Results**: If the results section is empty, ensure you have successfully generated at least one image. The history is trimmed to the last 30 runs.