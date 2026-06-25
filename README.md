# ImageIterate2

**ImageIterate2** is a SwiftUI-based iOS application and library for iterative AI image generation. It provides two distinct interfaces for prompt engineering and image creation:

1.  **Engineer (`Prod`)**: A production-grade interface for building complex prompts using a "chip" system, generating images via a real backend, and persisting results to disk with embedded metadata.
2.  **Iterate (`ImageIterate2`)**: A focused, single-image iteration workflow. It takes a source image, generates variations based on selected "vibes" and optional text prompts, and allows the user to promote variations to the hero state or revert to history.

The project is structured as a Swift Package containing both the library components and demo applications.

## Architecture

The project is divided into three main targets defined in `Package.swift`:

*   **`ImageIterate2`**: The core library. Contains the `ContentView` for the iteration workflow, the `ImageService` for communicating with the AI backend, and supporting UI components (shimmer effects, vibe pills).
*   **`Prod`**: The production application target. Contains the `ContentView` for the prompt-chip builder, real backend integration, and disk persistence logic using `ProjectService`.
*   **`Playground`**: A prototype target for the chip-list prompt builder. It uses mocked data and simulated network delays to test the UI layout and interaction models before integrating the real backend.

### Key Dependencies

*   **`Api`** (from `swiftapi`): Generated client for the backend API. Handles authentication, request formatting, and response parsing.
*   **`ProjectService`** (from `swift-project-service`): Utility for managing local file storage, specifically for saving generated images and embedding IPTC metadata (keywords, captions, ratings) into PNG files.

## Installation & Setup

### Prerequisites

*   **iOS 16.0+** (Swift 6 mode enabled)
*   **Xcode 15+**
*   A valid bearer token for the backend API.

### Building

Clone the repository and open the workspace or package in Xcode.

```bash
git clone <repository-url>
cd ImageIterate2
```

To build the library:
```bash
swift build
```

To run the demo apps:
1.  Open the project in Xcode.
2.  Select the `ImageIterate2` scheme to run the iteration workflow.
3.  Select the `Prod` scheme to run the engineer workflow.

## Usage

### 1. The Engineer Workflow (`Prod`)

The Engineer screen is designed for constructing detailed prompts using modular "chips."

**Features:**
*   **Chip-Based Prompting**: Add, edit, and remove text chips that form the final prompt. Chips wrap automatically in a flow layout.
*   **Presets**: Quick-add common stylistic terms (e.g., "Cinematic", "Neon").
*   **Generation**: Tapping "Generate" fans out parallel requests to the backend.
    *   **Chat Synthesis**: Each request first sends the prompt to an LLM (Claude Sonnet 4.6) to refine it into a detailed image prompt.
    *   **Image Generation**: The refined prompt is sent to the image model (Flux 2 Pro or Klein I2I).
*   **Persistence**: Generated images are saved to disk with embedded metadata.
    *   **Chips**: Stored as IPTC Subject keywords.
    *   **Prompt**: Stored as IPTC Caption/Abstract.
    *   **Like Status**: Stored as IPTC Star Rating.
*   **History**: Results are grouped into batches based on generation time. You can restore a previous prompt by tapping a result row.
*   **Undo**: Removing a result row triggers a 3-second undo toast.

**Integration:**
To use the `Prod` view in your own app:
```swift
import SwiftUI
import Prod // Or import the library if packaged separately

struct MyEngineerView: View {
    var body: some View {
        ContentView(bearer: "your-auth-token")
    }
}
```

### 2. The Iterate Workflow (`ImageIterate2`)

The Iterate screen is designed for rapid visual exploration of a single source image.

**Features:**
*   **Hero Image**: Displays the current "kept" image with a dominant color tint applied to the background and shadows.
*   **Vibes**: Select mood tags (e.g., "Moody", "Dreamy") to influence generation.
*   **Prompt Refinement**: Add optional text to refine the vibe.
*   **Variations**: Generates 2 variations at a time. These appear in a horizontal rail.
*   **Promote**: Tapping a variation promotes it to the Hero state, moving the old hero to History.
*   **History**: A horizontal strip of previous heroes. Tapping one reverts the hero to that state.
*   **Reset**: Returns to the initial source image.

**Integration:**
To use the `ContentView` from the `ImageIterate2` library:

```swift
import SwiftUI
import ImageIterate2

struct MyIterateView: View {
    var body: some View {
        ContentView(
            initialImagePath: "/path/to/source/image.png",
            bearer: "your-auth-token",
            onCommit: { heroData, heroFilename in
                // Called when the view is dismissed.
                // heroData: Raw PNG bytes of the final kept image.
                // heroFilename: Server-side filename (informational).
                print("User kept image: \(heroFilename)")
            }
        )
    }
}
```

**Important Notes for Integration:**
*   **`initialImagePath`**: Must point to a readable file on disk. The basename is used as the initial server-side filename.
*   **`bearer`**: Authentication token. Injected into `ApiAPIConfiguration.shared.customHeaders`.
*   **`onCommit`**: A closure fired once on dismissal. It provides the raw bytes of the final image. Do not rely on `heroFilename` for persistence; use the bytes.

## Backend Flow

Both workflows rely on a two-step backend process for generation:

1.  **Synthesis**: A POST to `/api` with `action=.typeClaudeSonnet46(...)`. This sends the user's idea to an LLM, which returns a refined, detailed prompt.
2.  **Generation**: A POST to `/api` with `action=.typeFlux2Pro(...)` or `action=.typeZImageTurbo(...)`. This uses the synthesized prompt to generate the image. The response contains the image as a base64-encoded string in the `file` field.

### Cast Mode (Prod Only)

The `Prod` target supports "Cast Mode" using `Flux2KleinI2I`. This requires two reference images (character and target) to be loaded from disk, base64-encoded, and sent in the request. This is handled automatically by `ImageService.castGenerate` if `ProjectService.getCharacterCast()` returns valid filenames.

## Key Files

*   `ImageIterate2/ContentView.swift`: The main view for the iteration workflow. Contains `ImageService` logic for the library.
*   `Prod/ContentView.swift`: The main view for the engineer workflow. Contains `Store` logic for persistence.
*   `Package.swift`: Defines the targets, dependencies, and platform support.
*   `Playground/ContentView.swift`: Prototype for the chip-list UI.

## Conventions & Non-Obvious Behaviors

*   **Memory Management**:
    *   The `ImageIterate2` library caps the number of variations in memory to 30 (`variationCeiling`). Older variations are dropped to prevent RAM bloat.
    *   The `Prod` app caps history to 30 runs (`maxRuns`). When the cap is exceeded, unliked rows are evicted first.
*   **Persistence**:
    *   In `Prod`, the disk is the source of truth. On launch, `Store.loadRuns()` scans the `Documents` directory for PNGs and reconstructs the history from embedded IPTC metadata.
    *   Chips in the editor are saved to `UserDefaults` separately from generation results.
*   **Error Handling**:
    *   Network errors are caught and displayed in a transient error pill at the bottom of the screen.
    *   Failed generations in `Prod` show a "Retry" button.
*   **Haptics**:
    *   The app uses `UIImpactFeedbackGenerator` for subtle tactile feedback on button presses and state changes.
*   **Logging**:
    *   Debug logs are printed to the console with timestamps. Base64 data and long strings are scrubbed to keep logs readable.