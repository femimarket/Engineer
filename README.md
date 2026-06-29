# Engineer

A SwiftUI-based image generation client that combines prompt engineering with a persistent history of results. It allows users to build complex prompts using modular "chips," synthesizes them via AI, and generates images using a Rust-backed FFI API.

## Overview

**Engineer** is a productionized iOS application designed for iterative image generation. It evolved from a playground experiment into a full-featured tool with disk-backed persistence and a real backend pipeline.

### Key Features
*   **Chip-Based Prompt Builder**: Construct prompts by adding, editing, and arranging text "chips."
*   **AI Synthesis**: Automatically refines raw ideas into optimized prompts using the Qwen model before generation.
*   **Dual Generation Modes**:
    *   **Text-to-Image**: Uses Flux2Pro for standard generation.
    *   **Cast Mode**: Uses Flux2KleinI2I for image-to-image generation using reference characters/targets.
*   **Persistent History**: All generated images and their associated metadata (chips, likes, model info) are stored locally as PNGs with embedded IPTC/XMP metadata.
*   **Batched Results**: Results are grouped into time-based batches for easier navigation.
*   **Undo & Recovery**: Accidental deletions can be undone via a toast notification.

## Architecture

The application follows a clean separation between the UI layer (`ContentView`), business logic (`ImageService`), and persistence (`ProjectService`/`Store`).

### Core Components

1.  **`ContentView.swift`**: The primary UI controller. It manages the state of chips, runs, and UI interactions. It handles the layout of the prompt editor, preset rail, and results list.
2.  **`ImageService.swift`**: A singleton that wraps the `Api` module. It handles authentication, chat synthesis, and image generation calls. It abstracts away the Rust FFI details from the SwiftUI views.
3.  **`ProjectService`** (External Module): Handles file system operations, specifically saving/loading PNGs with embedded metadata (IPTC keywords for chips, star ratings for likes).
4.  **`Api`** (External Module): A Rust FFI bridge providing direct access to backend services (`flux2Pro`, `flux2KleinI2I`, `qwen3_6_35b_a3b`).

### Data Persistence Strategy

*   **Chips (Drafts)**: Stored in `UserDefaults` as JSON. This ensures the current prompt state survives app relaunches even if no image was generated.
*   **Runs (History)**: Stored on disk. Each run corresponds to a PNG file in the app's `Documents` directory.
    *   **Metadata Embedding**: Instead of a separate database, metadata is embedded directly into the PNG file using IPTC/XMP standards:
        *   **Chips**: Stored as IPTC Subject keywords.
        *   **Prompt**: Stored as IPTC Caption/Abstract.
        *   **Model**: Stored as TIFF Software tag.
        *   **Like Status**: Stored as IPTC StarRating.
    *   **Reconstruction**: On launch, `Store.loadRuns()` scans the `Documents` directory, reads the PNG metadata, and reconstructs the `Run` objects.

### Generation Pipeline

1.  **Synthesis**: When "Generate" is tapped, the app first sends the user's idea to the Qwen model to synthesize a detailed prompt.
2.  **Parallel Generation**: The app generates `parallelRuns` (default 3) images simultaneously.
3.  **Mode Selection**:
    *   If reference images are configured in `ProjectService`, it uses `castGenerate` (Image-to-Image).
    *   Otherwise, it uses `generate` (Text-to-Image).
4.  **Persistence**: The resulting image data is saved to disk with metadata, and the UI updates the specific run's state to `.loaded`.

## Installation & Setup

### Prerequisites
*   iOS 16+ (due to SwiftUI features and async/await usage).
*   Xcode 15+
*   Access to the backend API credentials (User ID and Password).

### Build & Run

1.  Clone the repository.
2.  Open the project in Xcode.
3.  Configure the launch arguments for the `Prod` scheme:
    *   Go to **Product > Scheme > Edit Scheme...**.
    *   Select **Run** from the left sidebar.
    *   Navigate to the **Arguments** tab.
    *   Add the following arguments:
        *   `-u` followed by your API User ID.
        *   `-p` followed by your API Password.
4.  Build and run on a simulator or device.

> **Note**: The app will crash on launch if these arguments are missing, as it requires valid credentials to initialize the `ImageService`.

## Usage Guide

### Building a Prompt
1.  **Add Chips**: Tap the `+ add` button to create a new text field. Enter a phrase (e.g., "Cinematic", "Neon lights") and press Return or Next.
2.  **Edit Chips**: Tap any existing chip to edit its text inline.
3.  **Remove Chips**: Tap the `x` on a chip to remove it.
4.  **Presets**: Use the horizontal scrollable rail to quickly insert common style presets (e.g., "Moody", "Surreal").
5.  **Clear All**: Tap the `CLEAR` button in the header to reset the prompt.

### Generating Images
1.  Ensure at least one chip is present.
2.  Tap the **Generate** button at the bottom.
3.  The app will:
    *   Synthesize a prompt using AI.
    *   Generate 3 parallel images (costing 3 credits).
    *   Display them in the **RESULTS** section with a shimmer loading effect.

### Managing Results
*   **Restore**: Tap any result row to load its prompt back into the editor for modification.
*   **Like**: Tap the heart icon to mark a result as a favorite. This updates the embedded metadata on disk.
*   **Retry**: If a generation fails (indicated by an exclamation mark), tap the retry icon to regenerate that specific run.
*   **Remove**: Tap the `x` on a result row to delete it. An **Undo** toast will appear for 3 seconds. If you don't undo, the file is permanently deleted from disk.
*   **Filter**: Tap the **LIKED** chip to toggle a filter showing only favorited results.

## Key Files

| File | Description |
| :--- | :--- |
| `Prod/ContentView.swift` | Main UI view. Contains all models (`Chip`, `Run`, `RunBatch`), persistence logic (`Store`), and the main view hierarchy. |
| `Prod/ProdApp.swift` | App entry point. Handles argument parsing for API credentials. |
| `Api` (Module) | Rust FFI bridge for backend communication. |
| `ProjectService` (Module) | File system and metadata handling service. |

## Technical Details

### Concurrency
The app uses Swift Concurrency (`async/await`) for all network calls. In-flight generation tasks are tracked in an `inflight` dictionary keyed by `Run.ID`. When a run is removed, its corresponding task is cancelled to prevent unnecessary API calls and memory usage.

### UI Conventions
*   **Dark Mode**: The app is designed with a dark theme (`preferredColorScheme(.dark)`) with purple/pink gradient accents.
*   **Haptics**: Subtle haptic feedback is used for taps, edits, and generation completions via `UIImpactFeedbackGenerator`.
*   **Animations**: Spring animations are used for chip additions/removals and result row transitions.
*   **Scroll Behavior**: The editor can hide when scrolled out of view, replaced by a floating pill showing the current prompt context.

### Error Handling
*   **Network Failures**: If the API returns invalid data or the image cannot be decoded, the run state is set to `.failed`.
*   **Local Read Failures**: If a cached image file is corrupted or missing, it is skipped during history reconstruction.
*   **API Sentinel**: The underlying `Api` module returns sentinel fallback data on lib-level failures. The client currently treats these as regular results unless decoding fails, at which point it marks the row as failed.