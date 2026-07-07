# ImageIterate2

**ImageIterate2** is a cross-platform, AI-powered image generation and iteration tool. It provides a unified interface for composing prompts via a "chip" system, synthesizing creative directions via LLMs, and generating high-fidelity images using Flux models.

The project consists of three primary implementations:
1.  **iOS/macOS (SwiftUI):** A native app (`ImageIterate2`) and a reusable library (`Prod`) featuring a polished, dark-mode UI with ambient lighting effects.
2.  **Android (Compose):** A native Android port (`Kmp/engineer`) with disk-backed persistence and haptic feedback.
3.  **Web (Compose Multiplatform):** A browser-based version (`Kmp/engineer/screen/Engineer`) utilizing the Origin Private File System (OPFS).

## Architecture & Core Concepts

The application follows a **Prompt → Synthesize → Generate** pipeline.

### The Pipeline
1.  **Prompt Engineering:** Users build prompts by adding "Chips" (individual phrases) or selecting Presets (e.g., "Cinematic", "Neon").
2.  **Chat Synthesis:** Upon generation, the app sends the current chips to an LLM (`qwen3_6_35b_a3b`) to synthesize a detailed, optimized image prompt.
3.  **Image Generation:** The synthesized prompt is sent to an image model (`flux2Pro` or `flux2KleinI2I`).
4.  **Persistence:** Results are saved to disk with metadata (chips, model name, like status) embedded in the image file (IPTC/XMP).

### Key Components

*   **`ContentView` / `Engineer`:** The main UI screen. It manages the state of chips, the history of generated runs, and the generation queue.
*   **`ImageService`:** Handles the API calls. It abstracts the Rust FFI layer (`Api` package) and manages authentication.
*   **`Store` / `EngineerStore`:** Persistence layer.
    *   **Swift:** Uses `UserDefaults` for chips and `ProjectService` (disk) for runs.
    *   **Android:** Uses `SharedPreferences` for chips and `ProjectService` (disk) for runs.
    *   **Web:** Uses `localStorage` for chips and OPFS via `ProjectService` for runs.
*   **`Api` (Rust FFI):** The underlying binary library handling network requests and image processing. It is injected as a dependency in Swift and called directly in Kotlin.

### Data Flow & Persistence
*   **Chips:** Stored locally (UserDefaults/SharedPreferences/LocalStorage). They represent the *current* prompt being edited.
*   **Runs:** Stored on disk. Each run is a PNG file. Metadata is embedded in the file headers:
    *   **Subject/Keywords:** The chips associated with the run.
    *   **Caption:** The joined prompt text.
    *   **Software:** The model used (e.g., "Flux2Pro").
    *   **StarRating:** The "Liked" status.
*   **History Loading:** On launch, the app scans the disk for PNGs, extracts metadata, and reconstructs the `Run` list. Images are decoded lazily to avoid blocking the UI.

## Project Structure

```text
.
├── ImageIterate2/          # iOS/macOS Demo App
│   ├── ContentView.swift   # Main UI (Iterate mode: Hero-centric)
│   └── ImageIterate2App.swift
├── Prod/                   # iOS/macOS Production Library
│   ├── ContentView.swift   # Main UI (Engineer mode: Chip-centric)
│   └── ProdApp.swift
├── Playground/             # SwiftUI Prototype
│   └── ContentView.swift   # Mocked data, no API
├── Kmp/                    # Kotlin Multiplatform
│   ├── engineer/           # Core Library (Android + Web)
│   │   ├── src/androidMain/.../ContentView.kt
│   │   └── src/webMain/.../Engineer.kt
│   ├── demo/               # Android Demo App
│   └── demo-web/           # Web Demo Host
├── Tests/                  # Smoke tests for API
└── Package.swift           # Swift Package Manager manifest
```

## Installation & Setup

### Prerequisites
*   **Xcode 15+** (for Swift/SwiftUI targets)
*   **Android Studio** (for Android targets)
*   **Rust Toolchain** (required for the `Api` FFI dependency)

### Swift Package Dependencies
The project relies on a private Swift package `swiftapi` for the `Api` module. Ensure the dependency is resolved in `Package.swift`:
```swift
dependencies: [
    .package(url: "https://github.com/femimarket/swiftapi", branch: "main"),
]
```

### Running the iOS/macOS Demo (`ImageIterate2`)
1.  Open `ImageIterate2.xcodeproj` (or the workspace containing the SPM package).
2.  Select the `ImageIterate2` scheme.
3.  Go to **Scheme > Run > Arguments**.
4.  Add the following arguments:
    *   `-u` followed by your API username.
    *   `-p` followed by your API password.
5.  Build and Run.

### Running the Production App (`Prod`)
1.  Select the `Prod` scheme.
2.  Add launch arguments `-u <user>` and `-p <password>` as above.
3.  Build and Run.

### Running the Android Demo
1.  Open the project in Android Studio.
2.  Ensure the `Api` native library is built for the target architecture (ARM64/x86_64).
3.  Run the `demo` module. Credentials are hardcoded in `MainActivity.kt` for demo purposes but should be injected in production.

### Running the Web Demo
1.  Navigate to `Kmp/demo-web`.
2.  Run the Gradle task: `./gradlew :demo-web:webRun` (or equivalent for your setup).
3.  Open the local server URL in a browser.

## Usage Guide

### 1. Composing a Prompt
*   **Chips:** Tap the `+` button to add a phrase. Tap an existing chip to edit it. Tap the `x` to remove it.
*   **Presets:** Scroll the horizontal rail to select style presets (e.g., "Cinematic", "Neon"). Tapping a preset adds it as a chip.
*   **Clear:** Tap `CLEAR` to wipe all chips.

### 2. Generating Images
*   Tap the **Generate** button at the bottom.
*   The app fans out 3 parallel generation tasks (`parallelRuns = 3`).
*   Each task:
    1.  Sends chips to the LLM for synthesis.
    2.  Sends the synthesized prompt to the Image Model.
    3.  Saves the result to disk.
*   Results appear in the **RESULTS** section, grouped by generation batch.

### 3. Managing Results
*   **Like:** Tap the heart icon to like a result. This updates the IPTC StarRating in the file.
*   **Retry:** If a generation fails (shimmer turns to error icon), tap the refresh icon to retry.
*   **Remove:** Tap the `x` icon. A toast appears with an **Undo** button. If not undone within 3 seconds, the file is deleted from disk.
*   **Restore:** Tap any result row to load its chips back into the editor.

### 4. Navigation
*   **Back to Editor:** If you scroll past the chip editor, a floating pill appears showing the current prompt. Tap it to scroll back to the top.
*   **Liked Filter:** In the Results section, tap the `LIKED` chip to filter the view to only favorited images.

## Technical Details & Conventions

### UI/UX Conventions
*   **Theme:** Dark mode only. Background is black with radial gradients tinted by the dominant color of the current hero image (iOS) or static purple/pink gradients (Android/Web).
*   **Haptics:** Heavy use of `UIImpactFeedbackGenerator` (iOS) and `HapticFeedback` (Android) for chip interactions, generation starts, and success/failure states.
*   **Animations:** Spring animations are used for state changes (chips, runs). Shimmer effects indicate loading states.

### Error Handling
*   **API Failures:** If the Rust FFI returns a sentinel/fallback PNG, the app attempts to decode it. If decoding fails, the run state is set to `.failed`.
*   **Network Errors:** Caught and displayed in the run row. The user can retry.
*   **Disk Errors:** If a file cannot be read on launch, it is skipped.

### Performance Optimizations
*   **Lazy Decoding:** On Android/Web, images are not decoded from disk during the initial `loadRuns()` scan. They are decoded only when the row enters the viewport.
*   **Memory Limits:**
    *   iOS: `variationCeiling = 30` for the rail in the Iterate view.
    *   Android/Web: `maxRuns = 30`. Oldest unliked runs are evicted when the limit is reached.
*   **Cancellation:** In-flight generation tasks are cancelled when a run is removed to prevent wasting API credits and memory.

### Testing
*   **Smoke Tests:** Located in `Tests/ProdTests/ApiSmokeTests.swift`. These hit the real API to verify authentication and response formats.
*   **Setup:** Set `TEST_USER` and `TEST_PASSWORD` environment variables in the Xcode Scheme's Test configuration.

## License

[Insert License Information Here]