# ImageIterate2

**ImageIterate2** is a cross-platform AI image generation and iteration tool. It provides a "chip-list" prompt builder that allows users to compose complex prompts from modular phrases, then generates multiple variations using a two-stage pipeline: LLM chat synthesis followed by text-to-image generation.

The project is structured as a multi-platform codebase:
- **SwiftUI (iOS/macOS):** A polished, dark-mode-first interface with ambient glow effects, haptic feedback, and disk-backed persistence.
- **Kotlin Multiplatform (Android/Web):** A Compose-based implementation (`Engineer`) that mirrors the SwiftUI logic, supporting both native Android and browser (Web) targets.
- **Playground:** A standalone SwiftUI prototype for rapid UI iteration.

## Architecture

The application follows a strict separation between UI, State Management, and Backend Services.

### Core Flow
1.  **Prompt Engineering:** Users build prompts by adding "Chips" (phrases) or selecting Presets.
2.  **Generation:** Tapping "Generate" fans out `parallelRuns` (default 3) concurrent tasks.
3.  **Synthesis:** Each task calls `qwen3_6_35b_a3b` (LLM) to refine the prompt.
4.  **Image Gen:** Each task calls `flux2Pro` (or `flux2KleinI2I` for cast mode) to generate the image.
5.  **Persistence:** Results are saved to disk (`ProjectService` on iOS/Android, OPFS on Web) with metadata (chips, likes) embedded in image EXIF/IPTC/XMP.

### Key Components

#### 1. Persistence (`Store` / `EngineerStore`)
- **iOS (`Prod/ContentView.swift`):** Uses `ProjectService` for file I/O and `UserDefaults` for the working chip set. Images are stored as PNGs in the Documents directory.
- **Android (`Kmp/engineer/src/androidMain/...`):** Uses `ProjectService` for file I/O and `SharedPreferences` for chips.
- **Web (`Kmp/engineer/src/webMain/...`):** Uses OPFS (Origin Private File System) via `ProjectService` and `localStorage` for chips.

#### 2. Image Service
- **Swift (`ImageService` in `ContentView.swift`):** Wraps the `Api` package (Rust FFI). Handles authentication and parallel task groups.
- **Kotlin (`ImageService` in `ContentView.kt` / `Engineer.kt`):** Direct suspend functions calling Rust FFI. No HTTP client; handles base64 encoding for cast mode internally.

#### 3. UI Components
- **Chip Flow:** A custom `FlowLayout` (Swift) or `FlowRow` (Compose) that wraps chips. Supports inline editing and auto-sizing text fields.
- **Result Rows:** Display thumbnails with shimmer placeholders during loading. Support "Like" (heart) and "Retry" actions.
- **Ambient Background:** Radial gradients that shift color based on the dominant color of the current hero image (Swift) or static palettes (Kotlin).

## Project Structure

```text
.
├── ImageIterate2/          # SwiftUI Demo App (ImageIterate2 target)
│   ├── ContentView.swift   # Main UI for the demo (single image iteration)
│   └── ImageIterate2App.swift
├── Prod/                   # Production SwiftUI Library/App (Prod target)
│   ├── ContentView.swift   # Engineer screen: Chip builder + History
│   └── ProdApp.swift
├── Playground/             # SwiftUI Prototype (Playground target)
│   ├── ContentView.swift   # Mocked generation for UI testing
│   └── PlaygroundApp.swift
├── Kmp/                    # Kotlin Multiplatform
│   ├── engineer/           # Core Engineer screen logic
│   │   ├── src/androidMain/.../ContentView.kt  # Android Compose UI
│   │   └── src/webMain/.../Engineer.kt         # Web Compose UI
│   └── demo/               # Android Demo App
│       └── src/main/.../MainActivity.kt
├── Tests/                  # Unit/Smoke Tests
│   └── ProdTests/ApiSmokeTests.swift
└── Package.swift           # Swift Package Manager manifest
```

## Installation & Build

### Prerequisites
- **Xcode 15+** (for Swift 6.2 support)
- **Android Studio** (for KMP Android builds)
- **Rust Toolchain** (required by the `Api` dependency for FFI)

### Swift Package Manager
The project uses SPM. Open `Package.swift` or the root `.xcodeproj` (if generated) in Xcode.

Dependencies:
- `swiftapi`: Custom API client (Rust FFI).
- `swift-project-service`: Disk persistence layer.

### Kotlin Multiplatform
The KMP module is integrated via Gradle. Ensure you have the Android SDK and Kotlin Multiplatform plugins configured.

## Usage

### Running the SwiftUI Demo (`ImageIterate2`)
1.  Open the project in Xcode.
2.  Select the `ImageIterate2` scheme.
3.  Go to **Edit Scheme → Run → Arguments**.
4.  Add the following arguments:
    -   `-u` followed by your API user ID.
    -   `-p` followed by your API password.
5.  Run the app. It will load a demo image and allow you to iterate on it.

### Running the Production SwiftUI App (`Prod`)
1.  Select the `Prod` scheme.
2.  Add launch arguments `-u <user>` and `-p <password>` as above.
3.  Run. This version includes full history persistence and disk storage.

### Running the Android Demo
1.  Connect an Android device or start an emulator.
2.  Run the `demo` module.
3.  Credentials are hardcoded in `MainActivity.kt` for demo purposes.

### Running the Web Demo
1.  Run the `demo-web` module (requires Node.js environment).
2.  Open the generated HTML/JS in a browser.
3.  Credentials are hardcoded in `main.kt`.

## Key Features

### Prompt Engineering
- **Chips:** Modular phrases that can be edited, removed, or reordered.
- **Presets:** Quick-insert buttons for common styles (Cinematic, Neon, Moody, etc.).
- **Auto-Size Fields:** Text fields expand to fit content up to a max width.

### Generation
- **Parallel Execution:** Generates 3 images simultaneously by default.
- **Cast Mode:** Supports image-to-image generation using character and target reference images (Android/Web only currently).
- **Retry:** Failed rows can be retried individually.

### History & Persistence
- **Disk-Backed:** All generations are saved to disk. History survives app restarts.
- **Metadata:** Chips and "Like" status are embedded in the image file metadata (IPTC/XMP).
- **Trimming:** History is capped at 30 runs. Unliked runs are evicted first.

### UI/UX
- **Dark Mode:** Default dark theme with purple/pink accent gradients.
- **Haptics:** Subtle haptic feedback on button presses and state changes.
- **Undo:** Removing a result row triggers a 3-second undo toast.
- **Liked Filter:** Toggle to view only favorited results.

## Non-Obvious Conventions

1.  **Filename Chaining:** The server-side filename is preserved and passed to the next generation call to maintain context. This filename is internal-only and not exposed to the user.
2.  **Data vs. Image:** The app stores both the raw `Data` (bytes) and the decoded `UIImage`/`ImageBitmap`. The raw data is used for re-uploading or chaining to avoid re-encoding artifacts.
3.  **Batching:** Results are grouped into "batches" based on a 2-second window of their creation timestamp. This visually groups results from a single "Generate" tap.
4.  **Credit Cost:** The UI displays a credit cost per generation (`parallelRuns * creditPerRun`). This is informational; actual billing is handled by the backend.
5.  **Web OPFS:** On web, images are stored in the Origin Private File System. The app lazily decodes images only when they become visible in the list to prevent memory issues with large history.

## Testing

### API Smoke Tests
Located in `Tests/ProdTests/ApiSmokeTests.swift`. These tests hit the real API to verify authentication and response formats.

1.  Set environment variables in the Xcode Test scheme:
    -   `TEST_USER`
    -   `TEST_PASSWORD`
2.  Run the tests. They will skip if credentials are missing.