# ImageIterate2

**ImageIterate2** is a cross-platform generative AI image studio. It provides a "chip-list" prompt builder that composes complex image prompts from modular phrases, then fans out parallel generation requests to an AI backend. The app features a persistent history of generations, "liked" curation, and a polished dark-mode interface with ambient color-reactive backgrounds.

The project is structured as a multi-target Swift Package with ports for **iOS/macOS (SwiftUI)**, **Android (Jetpack Compose)**, and **Web (Kotlin/Compose for Web)**.

## Architecture

The application follows a consistent UI pattern across all platforms:
1.  **Prompt Editor:** A flow-layout of editable "chips" (phrases) at the top.
2.  **Generation:** A "Generate" button that fans out parallel requests.
3.  **Results:** A scrollable history of generated images, grouped by time, with options to like, retry, or remove.

### Backend Pipeline
Every generation follows a two-step pipeline to enhance creativity:
1.  **Chat Synthesis:** The prompt chips are sent to an LLM (`qwen3_6_35b_a3b`) to synthesize a detailed image prompt.
2.  **Image Generation:** The synthesized prompt is sent to an image model (`flux2Pro` or `flux2KleinI2I`) to produce the final image.

### Persistence
*   **Chips:** The working prompt is saved locally (UserDefaults/SharedPreferences/LocalStorage) so it survives app restarts.
*   **Runs (History):** Generated images are saved to disk. Metadata (chips, like status, model name) is embedded directly into the image file's XMP/IPTC metadata. This allows the app to reconstruct the history index by scanning the file system without a separate database.

## Project Structure

*   `ImageIterate2/`: **iOS/macOS SwiftUI** implementation.
    *   `ContentView.swift`: The main screen logic, UI, and image service wrapper.
    *   `ImageIterate2App.swift`: App entry point for the demo target.
*   `Prod/`: **Production SwiftUI** library.
    *   `ContentView.swift`: The core `ContentView` struct exported as a library.
    *   `ProdApp.swift`: Demo host for the library.
*   `Kmp/engineer/`: **Kotlin Multiplatform (Android & Web)**.
    *   `src/androidMain/.../ContentView.kt`: Android Jetpack Compose implementation.
    *   `src/webMain/.../Engineer.kt`: Web Compose implementation.
    *   `src/commonMain/...`: Shared models and logic (if applicable, though much logic is duplicated per platform in this repo structure).
*   `Kmp/demo/`: **Android Demo App**.
    *   `MainActivity.kt`: Hosts the Compose `ContentView`.
*   `Kmp/demo-web/`: **Web Demo App**.
    *   `main.kt`: Hosts the Compose `Engineer` screen in the browser.
*   `Playground/`: **SwiftUI Prototype**.
    *   `ContentView.swift`: A mock-up version using simulated data for UI testing without backend calls.
*   `Tests/`: Unit and Smoke tests.
*   `Package.swift`: Swift Package Manager manifest.

## Key Features

*   **Chip-Based Prompting:** Build prompts by adding, editing, and removing phrase chips.
*   **Parallel Generation:** Each "Generate" tap creates 3 parallel image requests for variety.
*   **Ambient UI:** The background radial gradients shift color based on the dominant hue of the current "hero" image.
*   **History & Curation:**
    *   **Like:** Marks images as favorites.
    *   **Filter:** Toggle to show only liked images.
    *   **Restore:** Tap any past result to load its prompt chips back into the editor.
    *   **Undo:** Removing a result triggers a 3-second undo toast.
*   **Cast Mode (Android/Web):** Supports "Character-to-Image" generation by referencing stored character images (implemented in `Kmp/engineer`).

## Installation & Setup

### Prerequisites
*   **iOS/macOS:** Xcode 15+, Swift 6.2.
*   **Android:** Android Studio, JDK 17+.
*   **Web:** Node.js (for running the Kotlin/JS demo).
*   **API Credentials:** You need valid credentials for the backend API (`user` and `password`).

### Swift Package (iOS/macOS)
1.  Clone the repository.
2.  Open `ImageIterate2.xcodeproj` or the package in Xcode.
3.  **Configure Credentials:**
    *   Select the `ImageIterate2` scheme.
    *   Go to **Edit Scheme** → **Run** → **Arguments** tab.
    *   Add two arguments:
        *   `-u` followed by your API user ID.
        *   `-p` followed by your API password.
    *   *Example:* `-u` `019emsssc070a...` `-p` `ppooiii`
4.  Build and run.

### Android
1.  Open the project in Android Studio.
2.  Locate `Kmp/demo/src/main/java/studio/femi/demo/MainActivity.kt`.
3.  Update the hardcoded credentials in `ContentView(user = "...", password = "...")` with your valid API credentials.
4.  Run on an emulator or device.

### Web
1.  Navigate to `Kmp/demo-web`.
2.  Update `main.kt` with valid credentials:
    ```kotlin
    Engineer(
        user = "your-user-id",
        password = "your-password",
    )
    ```
3.  Run the web demo (requires Gradle/Kotlin JS setup).

## Usage Guide

### Creating a Prompt
1.  Tap the **+** button to add a new chip.
2.  Type a phrase (e.g., "cyberpunk city") and press **Next** or **Done**.
3.  Tap any existing chip to edit its text.
4.  Tap the **X** on a chip to remove it.
5.  Use the **Presets** rail (e.g., "Cinematic", "Neon") to quickly insert common style descriptors.
6.  Tap **CLEAR** to wipe all chips.

### Generating Images
1.  Ensure at least one chip is present.
2.  Tap the **Generate** button at the bottom.
3.  The app will fan out 3 parallel requests. You will see shimmer placeholders appear.
4.  Once generated, images appear in the **Results** section.

### Managing History
*   **Like:** Tap the heart icon on a result to mark it as a favorite.
*   **Filter:** Tap the **LIKED** chip in the Results header to toggle the filter.
*   **Restore:** Tap any result row to load its prompt chips into the editor.
*   **Retry:** If a generation fails (shows a warning icon), tap the refresh icon to retry.
*   **Remove:** Tap the X icon on a result. A toast will appear at the bottom allowing you to **Undo** the removal within 3 seconds.

## Technical Details

### Image Service
The `ImageService` class (in `ContentView.swift` for Swift, `ImageService` object for Kotlin) handles the backend communication.
*   **Swift:** Uses the `Api` package (Rust FFI).
*   **Kotlin:** Uses direct suspend functions from the `Api` artifact.
*   **Flow:**
    1.  `chatSynthesize()`: Sends chips to Qwen LLM.
    2.  `generate()`: Sends synthesized prompt to Flux2 model.
    3.  `saveRun()`: Saves bytes to disk and embeds metadata.

### Persistence Strategy
*   **Swift (`Store` enum):** Uses `ProjectService` to interact with the file system. Metadata is read/written via XMP/IPTC tags.
*   **Android (`Store` object):** Uses `SharedPreferences` for chips and `ProjectService` for image files.
*   **Web (`EngineerStore` object):** Uses `localStorage` for chips and OPFS (Origin Private File System) via `ProjectService` for images.

### UI Conventions
*   **Theme:** Dark mode only. Background is black with two radial gradients (purple/pink) that shift based on the hero image's dominant color.
*   **Typography:** Heavy tracking for headers, medium weight for chips.
*   **Feedback:** Haptic feedback is triggered on chip edits, generation starts, and success/failure states.

## Testing

### Smoke Tests
`Tests/ProdTests/ApiSmokeTests.swift` verifies that the API credentials are valid and the backend returns real images.
*   **Setup:** Set environment variables `TEST_USER` and `TEST_PASSWORD` in the Xcode Scheme's **Test** configuration.
*   **Run:** Execute the `ProdTests` target.

## Troubleshooting

*   **Shimmering Indefinitely:** Check your API credentials. If the API returns an error or fallback image, the UI may not update correctly. Run the Smoke Tests to verify connectivity.
*   **Missing Launch Arguments (iOS):** The app will crash on launch if `-u` and `-p` are not provided in the scheme arguments.
*   **Web Performance:** On the web, image decoding is done lazily to prevent UI hangs. If images don't appear, check the console for decode errors.