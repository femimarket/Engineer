# Engineer

**Engineer** is a SwiftUI-based iOS application for building image generation prompts using a modular "chip" system and generating high-fidelity images via a Rust-backed API. It serves as a productionized evolution of a playground prototype, featuring disk-backed persistence, real-time chat synthesis, and a polished dark-mode interface.

## Features

*   **Chip-Based Prompt Builder**: Construct prompts by adding, editing, and removing individual text "chips." Supports inline editing and preset style injection.
*   **Real-Time Generation Pipeline**:
    *   **Chat Synthesis**: Automatically refines raw ideas into optimized prompts using the Qwen LLM.
    *   **Image Generation**: Generates images via Flux2Pro (text-to-image) or Flux2KleinI2I (image-to-image/cast mode).
    *   **Parallel Execution**: Generates multiple variations per tap with concurrent task management.
*   **Disk-Backed Persistence**:
    *   Runs and images survive app relaunches.
    *   Metadata (chips, likes, model info) is embedded directly into PNG files using IPTC/XMP standards, eliminating the need for a separate database.
*   **History & Management**:
    *   View generation history grouped by time batches.
    *   Restore previous prompts to the editor.
    *   Like/unlike results (persisted as IPTC star ratings).
    *   Undo recently deleted results.
    *   Automatic history trimming to preserve storage.
*   **Cast Mode**: Supports image-to-image generation by providing character and target reference images.

## Architecture

The application follows a clean separation between the UI layer (`ContentView`), business logic (`ImageService`), and persistence (`ProjectService`, `Store`).

### Key Components

*   **`ContentView.swift`**: The primary UI component. Manages the state of chips, runs, and UI interactions. It handles the layout, animations, and user input.
*   **`ImageService.swift`**: A singleton class that interfaces with the `Api` module. It handles authentication, chat synthesis, and image generation calls.
*   **`ProjectService`**: (External Module) Handles file system operations, including saving/loading PNGs and reading/writing embedded metadata.
*   **`Api`**: (External Module) Rust FFI bindings for calling the backend image generation and LLM services.

### Data Flow

1.  **User Input**: User adds/edit chips in the `ChipFlowLayout`.
2.  **Generation**:
    *   User taps "Generate".
    *   `ImageService.chatSynthesize` is called to refine the prompt.
    *   `ImageService.generate` or `castGenerate` is called to produce the image.
    *   Results are saved to disk via `Store.saveRun`, embedding metadata into the PNG.
3.  **Persistence**:
    *   On launch, `Store.loadRuns` scans the `Documents` directory.
    *   It reads PNG files, extracts IPTC metadata (chips, likes, model), and reconstructs the `Run` objects.

## Installation & Setup

### Prerequisites

*   **Xcode**: Latest stable version.
*   **iOS Deployment Target**: iOS 16.0+ (due to SwiftUI features used).
*   **Backend Credentials**: You must have valid credentials for the backend API.

### Configuration

The app requires authentication credentials to be passed at launch. These are not hardcoded.

1.  Open the project in Xcode.
2.  Go to **Product > Scheme > Edit Scheme...** (or press `Cmd + <`).
3.  Select **Run** from the left sidebar.
4.  Navigate to the **Arguments** tab.
5.  Under **Arguments Passed On Launch**, add the following:
    *   `-u` followed by your **User ID**.
    *   `-p` followed by your **Password**.

    *Example:*
    ```
    -u
    your-username-here
    -p
    your-password-here
    ```

> **Note**: If these arguments are missing, the app will crash on launch with a `preconditionFailure` to prevent silent authentication errors.

## Usage

### Building Prompts

1.  **Add Chips**: Tap the `+ add` button to create a new text chip. Type your phrase and press "Next" or "Done" to add it.
2.  **Edit Chips**: Tap any existing chip to enter inline editing mode. Modify the text and press "Done" to save.
3.  **Remove Chips**: Tap the `x` on a chip to remove it.
4.  **Presets**: Use the horizontal scrollable rail to quickly insert style presets (e.g., "Cinematic", "Neon", "Moody").
5.  **Clear All**: Tap "CLEAR" in the header to reset the prompt.

### Generating Images

1.  Ensure you have at least one chip in the prompt editor.
2.  Tap the **Generate** button at the bottom.
3.  The app will:
    *   Send your chips to the chat synthesizer.
    *   Generate `parallelRuns` (default 3) images.
    *   Display loading shimmer effects for each result.
    *   Show the generated images once ready.

### Managing Results

*   **Restore**: Tap any result row to load its prompt back into the editor.
*   **Like**: Tap the heart icon to like a result. This persists the like status to the file.
*   **Retry**: Tap the retry icon on a failed or loaded result to regenerate it.
*   **Remove**: Tap the `x` icon to remove a result. A toast notification appears with an "Undo" button for 3 seconds.
*   **Filter**: Tap the "LIKED" chip in the Results header to toggle between showing all results or only liked ones.

## Key Files

*   `Prod/ContentView.swift`: Main UI logic, models (`Chip`, `Run`, `RunBatch`), persistence store (`Store`), and image service integration.
*   `Prod/ProdApp.swift`: App entry point, handles launch argument parsing for credentials.
*   `Api/`: (External) Rust FFI bindings for backend communication.
*   `ProjectService/`: (External) File system and metadata handling.

## Technical Details

### Persistence Strategy

The app uses a "file-as-database" approach. Each generated image is a PNG file in the `Documents` directory. Metadata is embedded using IPTC/XMP standards:

*   **Chips**: Stored as IPTC Subject keywords.
*   **Prompt**: Stored as IPTC Caption/Abstract.
*   **Model Name**: Stored as TIFF Software tag.
*   **Like Status**: Stored as IPTC StarRating.
*   **Creation Date**: Derived from the file's creation date.

This allows the app to reconstruct the entire history of runs simply by scanning the directory, without needing a separate SQLite or Core Data store.

### Concurrency

*   **Async/Await**: All API calls are asynchronous.
*   **Task Management**: In-flight generation tasks are tracked in a dictionary (`inflight`). When a result is removed, the corresponding task is cancelled to prevent unnecessary API calls and resource usage.
*   **Main Actor**: UI updates are performed on the main actor to ensure thread safety.

### UI Conventions

*   **Dark Mode**: The app is designed for dark mode with a black background and subtle gradient accents.
*   **Animations**: Uses spring animations for smooth transitions when adding/removing chips or results.
*   **Haptics**: Provides haptic feedback for user interactions (taps, removals, errors).
*   **Accessibility**: Includes accessibility labels and hints for screen readers.