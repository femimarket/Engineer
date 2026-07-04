//
//  ContentView.swift
//  ImageIterate2
//
//  One image, many iterations.
//

import SwiftUI
import UIKit
import Api

// MARK: - Theme

private enum Theme {
    static let bg              = Color.black
    static let surface         = Color.white.opacity(0.06)
    static let surfaceStrong   = Color.white.opacity(0.10)
    static let stroke          = Color.white.opacity(0.10)
    static let textDim         = Color.white.opacity(0.5)

    static let accent = LinearGradient(
        colors: [
            Color(red: 0.55, green: 0.20, blue: 1.00),
            Color(red: 1.00, green: 0.30, blue: 0.65)
        ],
        startPoint: .leading, endPoint: .trailing
    )
}

// MARK: - Models

struct Variation: Identifiable, Equatable {
    let id = UUID()
    let image: UIImage
    /// Original encoded bytes from MediaApi — kept alongside the decoded image
    /// so the dismissal callback can return raw data without re-encoding.
    let data: Data
    /// Server-side filename. Internal-only — used to chain the next generation
    /// server-side without re-uploading. NEVER exposed publicly; servers can't
    /// be relied on to persist filenames indefinitely.
    let filename: String

    static func == (lhs: Variation, rhs: Variation) -> Bool { lhs.id == rhs.id }
}

// MARK: - ContentView

public struct ContentView: View {
    /// Fired once on screen dismissal (sheet swipe, parent flips binding,
    /// programmatic dismiss). Returns the kept image as raw bytes plus its
    /// server-side filename — both guaranteed non-nil because the screen
    /// always has a valid hero from init onward. Filename is informational
    /// (servers may not persist filenames indefinitely); callers should treat
    /// the bytes as source of truth.
    var onCommit: (_ heroData: Data, _ heroFilename: String) -> Void

    @State private var hero: UIImage
    /// Original encoded bytes of the current hero — what onCommit returns on dismiss.
    @State private var heroData: Data
    /// Server-side filename of the current hero. Used to chain the next
    /// generation call and surfaced to the caller on dismiss.
    @State private var heroFile: String
    /// Dominant warm tone of the current hero image, used to color the ambient
    /// glow and the hero drop shadow so the chrome always matches the photo.
    @State private var heroTint: Color

    /// Path of the initial image; used by `resetToDefault` to reload from disk
    /// without holding redundant copies in memory.
    private let initialImagePath: String

    /// Designated init.
    /// - initialImagePath: full disk path to the starting image file. MUST point
    ///   to a readable image — invalid paths trigger `preconditionFailure`. The
    ///   basename is used as the internal server-side filename for the first
    ///   generation call.
    /// - bearer: auth token, injected once into `ApiAPIConfiguration.shared.customHeaders`.
    ///   Source from Keychain or a server-issued session — never a literal.
    /// - onCommit: fires once on dismiss with the kept image's raw bytes.
    public init(
        initialImagePath: String,
        user: String,
        password: String,
        onCommit: @escaping (_ heroData: Data, _ heroFilename: String) -> Void
    ) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: initialImagePath)),
              let img = UIImage(data: data) else {
            preconditionFailure("initialImagePath does not point to a readable image: \(initialImagePath)")
        }
        let basename = URL(fileURLWithPath: initialImagePath).lastPathComponent
        self.initialImagePath = initialImagePath
        self.onCommit = onCommit
        _hero = State(initialValue: img)
        _heroData = State(initialValue: data)
        _heroFile = State(initialValue: basename)
        _heroTint = State(initialValue: ContentView.dominantColor(of: img))
        ImageService.configure(user: user, password: password)
    }
    @State private var history: [UIImage] = []
    /// Original bytes of each prior hero, parallel to `history`. Lets revert
    /// restore the exact bytes without re-encoding (PNG round-trip would lose
    /// fidelity and risk nil for damaged UIImages).
    @State private var historyData: [Data] = []
    /// Server filenames of every promoted hero in order, parallel to `history`.
    /// Internal only — drives the history strip's revert action. Not exposed.
    @State private var historyFiles: [String] = []
    @State private var variations: [Variation] = []
    @State private var selectedVibes: Set<String> = []
    @State private var prompt: String = ""
    @State private var isGenerating = false
    @State private var pendingPlaceholders = 0
    @State private var heroBreath = false
    @State private var errorBanner: String?

    @State private var showingFullScreen = false

    @FocusState private var promptFocused: Bool

    private let vibes = ["Cinematic", "Neon", "Moody", "Pastel", "Film", "Surreal", "Vintage", "Dreamy"]

    /// Two-tone palette per vibe — used to color the ghost placeholders so the
    /// user gets a live preview of what mood they're about to generate.
    private static let vibePalettes: [String: [Color]] = [
        "Cinematic": [Color(red: 0.13, green: 0.28, blue: 0.42), Color(red: 0.88, green: 0.58, blue: 0.28)],
        "Neon":      [Color(red: 0.10, green: 0.80, blue: 1.00), Color(red: 1.00, green: 0.20, blue: 0.85)],
        "Moody":     [Color(red: 0.18, green: 0.10, blue: 0.40), Color(red: 0.50, green: 0.20, blue: 0.50)],
        "Pastel":    [Color(red: 1.00, green: 0.82, blue: 0.88), Color(red: 0.78, green: 0.80, blue: 0.96)],
        "Film":      [Color(red: 0.72, green: 0.55, blue: 0.32), Color(red: 0.42, green: 0.28, blue: 0.18)],
        "Surreal":   [Color(red: 0.30, green: 0.85, blue: 0.85), Color(red: 1.00, green: 0.55, blue: 0.85)],
        "Vintage":   [Color(red: 0.65, green: 0.50, blue: 0.28), Color(red: 0.95, green: 0.85, blue: 0.62)],
        "Dreamy":    [Color(red: 0.82, green: 0.72, blue: 1.00), Color(red: 1.00, green: 0.80, blue: 0.85)]
    ]

    private var activeVibeColors: [Color] {
        let selected = selectedVibes.isEmpty ? Set(["Cinematic", "Dreamy"]) : selectedVibes
        return selected.sorted().flatMap { Self.vibePalettes[$0] ?? [] }
    }

    public var body: some View {
        ZStack {
            ambientBackground

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 14) {
                        heroCard
                            .padding(.horizontal, 22)
                            .padding(.top, 4)
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showingFullScreen = true
                            }

                        // Static signal that the hero is the kept item. Solves model A's
                        // discoverability hole without adding a verb anywhere.
                        selectedLabel
                            .padding(.top, -4)

                        if !history.isEmpty {
                            historyStrip
                        }

                        rail
                    }
                    .padding(.bottom, 230)
                }
                .scrollIndicators(.hidden)
            }

            VStack {
                Spacer()
                if let msg = errorBanner {
                    errorPill(msg)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .background(Theme.bg)
        .onAppear { heroBreath = true }
        .onTapGesture { promptFocused = false }
        .fullScreenCover(isPresented: $showingFullScreen) {
            FullScreenImageView(image: hero, isPresented: $showingFullScreen)
        }
        .onDisappear {
            // Single dismissal hook — fires whether the parent flips its binding,
            // the user swipes the sheet down, or the child calls `dismiss`.
            onCommit(heroData, heroFile)
        }
    }

    // MARK: Background

    private var ambientBackground: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            // Tinted by the hero's dominant color so chrome and content harmonize.
            RadialGradient(
                colors: [heroTint.opacity(0.45), .clear],
                center: .init(x: 0.18, y: 0.02),
                startRadius: 0, endRadius: 380
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [heroTint.opacity(0.30), .clear],
                center: .init(x: 0.92, y: 0.06),
                startRadius: 0, endRadius: 320
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.6), value: heroTint)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(Theme.accent).frame(width: 8, height: 8)
                Text("ITERATE")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(2.8)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            iconButton(symbol: "arrow.counterclockwise", accessibilityLabel: "Reset") {
                resetToDefault()
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    private func iconButton(symbol: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.surface))
                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Hero

    private var heroCard: some View {
        // Size driver is a clear square that's capped at 60% of screen height,
        // so the bottom bar (vibe pills + prompt + Generate) always has room and
        // the hero never pushes them off-screen on shorter devices.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxHeight: UIScreen.main.bounds.height * 0.60)
            .frame(maxWidth: .infinity)
            .overlay {
                Image(uiImage: hero)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.20), .clear, .black.opacity(0.18)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .blendMode(.plusLighter)
                    .opacity(0.55)
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.40), .white.opacity(0.04), .white.opacity(0.18)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .overlay {
                if isGenerating { ShimmerView().clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous)).allowsHitTesting(false) }
            }
            .shadow(color: heroTint.opacity(0.45), radius: 44, y: 22)
            .shadow(color: .black.opacity(0.55), radius: 18, y: 10)
            .scaleEffect(heroBreath ? 1.006 : 1.0)
            .animation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true), value: heroBreath)
    }

    // MARK: Selected label
    //
    // One-word static signal that the hero is the kept item. Sits directly
    // under the hero so the relationship is visible without a verb.

    private var selectedLabel: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(heroTint)
                .frame(width: 5, height: 5)
                .shadow(color: heroTint.opacity(0.7), radius: 3)
            Text("SELECTED")
                .font(.system(size: 10, weight: .heavy))
                .tracking(2.5)
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.4), value: heroTint)
    }

    // MARK: History strip

    private var historyStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("HISTORY")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(Theme.textDim)
                    .padding(.leading, 22)
                    .padding(.trailing, 4)
                ForEach(Array(history.enumerated()), id: \.offset) { idx, img in
                    Button {
                        revert(to: idx)
                    } label: {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 30, height: 30)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                    }
                    .buttonStyle(PressableStyle(scale: 0.9))
                }
                Color.clear.frame(width: 22)
            }
        }
    }

    // MARK: Rail
    //
    // ONE rail using the same fixed-size card across every state. Empty =
    // ghost. Generating = ghost with shimmer overlay. Loaded = same-sized
    // card showing the real image. Card dimensions NEVER change with count
    // or state. The horizontal ScrollView lets more variations scroll into view.

    private var rail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 14) {
                Color.clear.frame(width: 8)
                if variations.isEmpty {
                    ghostPlaceholder(
                        palette: Array(activeVibeColors.prefix(2)),
                        shimmer: pendingPlaceholders > 0
                    )
                    ghostPlaceholder(
                        palette: Array(activeVibeColors.suffix(2)),
                        label: pendingPlaceholders > 0 ? nil : "tap generate",
                        shimmer: pendingPlaceholders > 0
                    )
                } else {
                    ForEach(variations) { v in
                        variationCard(v)
                    }
                }
                Color.clear.frame(width: 8)
            }
            .padding(.horizontal, 14)
        }
        // CRITICAL: a horizontal ScrollView inside a vertical ScrollView claims
        // unbounded vertical space by default — which pushed the rail off the
        // visible viewport, causing the "90% cropped" symptom. Constrain it to
        // the card's intrinsic height so layout treats it like a fixed-height row.
        .frame(height: 168)
    }

    /// Hard ceiling on how many variations we keep in memory. Beyond this,
    /// the oldest fall off the back when new ones generate. Bounds the worst-
    /// case RAM footprint of the rail to ~ceiling × 4MB on 1024×1024 results.
    private static let variationCeiling = 30

    private func variationCard(_ v: Variation) -> some View {
        Button { promote(v) } label: {
            Image(uiImage: v.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: 168, height: 168)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(
                            colors: [.white.opacity(0.16), .clear, .black.opacity(0.12)],
                            startPoint: .top, endPoint: .bottom))
                        .blendMode(.plusLighter)
                        .opacity(0.7)
                        .allowsHitTesting(false)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.20), lineWidth: 0.6)
                }
                .shadow(color: .black.opacity(0.50), radius: 16, y: 8)
        }
        .buttonStyle(PressableStyle(scale: 0.96))
    }

    private func ghostPlaceholder(palette: [Color], label: String? = nil, shimmer: Bool = false) -> some View {
        let colors = palette.isEmpty ? [Color.white.opacity(0.15), Color.white.opacity(0.05)] : palette
        return ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(
                    colors: colors.map { $0.opacity(0.28) },
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    .white.opacity(0.10),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 6])
                )
            VStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
                if let label {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            if shimmer {
                ShimmerView()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 168, height: 168)
        .animation(.easeInOut(duration: 0.4), value: colors)
    }

    private var placeholderCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.surface)
            ShimmerView()
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .frame(width: 168, height: 168)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.4), radius: 10, y: 6)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vibes, id: \.self) { v in
                        VibePill(label: v, isSelected: selectedVibes.contains(v)) {
                            toggleVibe(v)
                        }
                    }
                }
                .padding(.horizontal, 22)
            }

            HStack(spacing: 10) {
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
                TextField("", text: $prompt, prompt:
                    Text("optional · refine the vibe")
                        .foregroundColor(Theme.textDim)
                )
                .focused($promptFocused)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .tint(.white)
                .submitLabel(.go)
                .onSubmit { Task { await generate() } }
                if !prompt.isEmpty {
                    Button { prompt = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.35))
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 0.5))
            .padding(.horizontal, 22)

            generateButton
                .padding(.horizontal, 22)
                .padding(.bottom, 14)
        }
        .padding(.top, 18)
        .background {
            ZStack(alignment: .top) {
                // Solid black behind the controls so nothing bleeds through.
                Color.black
                // Soft fade above the controls — only ~24pt of transition so the
                // hand-off from scroll content reads as a smooth cliff, not a vague wash.
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 32)
                .offset(y: -24)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var generateButton: some View {
        Button { Task { await generate() } } label: {
            HStack(spacing: 10) {
                if isGenerating {
                    ProgressView().tint(.white).scaleEffect(0.9)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .bold))
                }
                Text(isGenerating ? "Generating" : "Generate")
                    .font(.system(size: 17, weight: .bold))
                    .tracking(0.5)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background {
                ZStack {
                    Theme.accent
                    LinearGradient(
                        colors: [.white.opacity(0.38), .clear],
                        startPoint: .top, endPoint: .center
                    )
                    .blendMode(.plusLighter)
                    .opacity(0.55)
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.28)],
                        startPoint: .center, endPoint: .bottom
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.55), .white.opacity(0.10)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
                    )
            }
            .shadow(color: Color(red: 0.95, green: 0.30, blue: 0.65).opacity(0.55), radius: 26, y: 12)
            .shadow(color: Color(red: 0.55, green: 0.20, blue: 1.0).opacity(0.35), radius: 14, y: 4)
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .disabled(isGenerating)
    }

    private func errorPill(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Capsule().fill(.red.opacity(0.85)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
            .padding(.bottom, 8)
    }

    // MARK: Actions

    private func toggleVibe(_ vibe: String) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
            if selectedVibes.contains(vibe) { selectedVibes.remove(vibe) }
            else { selectedVibes.insert(vibe) }
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func promote(_ v: Variation) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let newTint = ContentView.dominantColor(of: v.image)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            history.append(hero)
            historyData.append(heroData)
            historyFiles.append(heroFile)
            hero = v.image
            heroData = v.data
            heroFile = v.filename
            heroTint = newTint
            variations.removeAll { $0.id == v.id }
        }
    }

    private func revert(to idx: Int) {
        guard idx < history.count else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let restored = history[idx]
        let restoredData = idx < historyData.count ? historyData[idx] : heroData
        let restoredFile = idx < historyFiles.count ? historyFiles[idx] : heroFile
        let newTint = ContentView.dominantColor(of: restored)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            history.append(hero)
            historyData.append(heroData)
            historyFiles.append(heroFile)
            hero = restored
            heroData = restoredData
            heroFile = restoredFile
            heroTint = newTint
            history.remove(at: idx)
            if idx < historyData.count { historyData.remove(at: idx) }
            if idx < historyFiles.count { historyFiles.remove(at: idx) }
        }
    }

    private func resetToDefault() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: initialImagePath)),
              let img = UIImage(data: data) else {
            // The initial path was valid at init (we precondition'd it); if it
            // disappeared between then and now, that's a programmer/environment
            // bug rather than a recoverable user error.
            preconditionFailure("initialImagePath no longer readable on reset: \(initialImagePath)")
        }
        let basename = URL(fileURLWithPath: initialImagePath).lastPathComponent
        let initialTint = ContentView.dominantColor(of: img)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            hero = img
            heroData = data
            heroFile = basename
            heroTint = initialTint
            history.removeAll()
            historyData.removeAll()
            historyFiles.removeAll()
            variations.removeAll()
            selectedVibes.removeAll()
            prompt = ""
            errorBanner = nil
        }
    }

    private func generate() async {
        promptFocused = false
        guard !isGenerating else { return }

        let vibeText = selectedVibes.sorted().joined(separator: ", ")
        let parts = [prompt.trimmingCharacters(in: .whitespaces), vibeText].filter { !$0.isEmpty }
        let finalPrompt = parts.isEmpty ? "creative reinterpretation, preserve subject" : parts.joined(separator: ", ")

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isGenerating = true
            pendingPlaceholders = 2
        }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

        do {
            let results = try await ImageService.shared.generate(
                prompt: finalPrompt,
                count: 2
            )
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                for r in results {
                    variations.insert(Variation(image: r.image, data: r.data, filename: r.filename), at: 0)
                }
                // Cap memory: oldest variations fall off the back.
                if variations.count > Self.variationCeiling {
                    variations.removeLast(variations.count - Self.variationCeiling)
                }
                pendingPlaceholders = 0
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            withAnimation(.spring()) {
                pendingPlaceholders = 0
                errorBanner = error.localizedDescription
            }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation(.spring()) { errorBanner = nil }
            }
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isGenerating = false
        }
    }


    /// Average color of the image, downsampled to a single pixel.
    /// Used to tint the ambient glow and hero drop shadow.
    static func dominantColor(of image: UIImage) -> Color {
        guard let cg = image.cgImage else { return Color(red: 0.45, green: 0.20, blue: 0.55) }
        let ctx = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let ctx else { return Color(red: 0.45, green: 0.20, blue: 0.55) }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else {
            return Color(red: 0.45, green: 0.20, blue: 0.55)
        }
        let r = Double(data[0]) / 255.0
        let g = Double(data[1]) / 255.0
        let b = Double(data[2]) / 255.0
        // Pump saturation up a bit so a muted average still reads as a glow.
        return Color(red: min(1, r * 1.25), green: min(1, g * 1.15), blue: min(1, b * 1.05))
    }
}

// MARK: - VibePill

private struct VibePill: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.2)
                .foregroundStyle(isSelected ? .black : .white.opacity(0.88))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background {
                    if isSelected {
                        Capsule().fill(.white)
                            .shadow(color: .white.opacity(0.35), radius: 10, y: 0)
                    } else {
                        Capsule().fill(Theme.surface)
                    }
                }
                .overlay {
                    Capsule().strokeBorder(
                        isSelected ? Color.clear : Theme.stroke,
                        lineWidth: 0.5
                    )
                }
        }
        .buttonStyle(PressableStyle(scale: 0.94))
    }
}

// MARK: - Shimmer

private struct ShimmerView: View {
    @State private var phase: CGFloat = -1.0
    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.white.opacity(0.0), .white.opacity(0.22), .white.opacity(0.0)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.55)
            .offset(x: geo.size.width * phase)
            .blendMode(.plusLighter)
            .onAppear {
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
        }
    }
}

// MARK: - Button style

private struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Demo image canvas (hardcoded "input" image)

// MARK: - Logger

@inline(__always)
nonisolated private func log(_ tag: String, _ message: @autoclosure () -> String) {
    #if DEBUG
    let t = Date().formatted(.dateTime.hour().minute().second().secondFraction(.fractional(3)))
    print("⟶ \(t) \(tag) \(scrub(message()))")
    #endif
}

/// Strip base64/data-URI noise and any other base64-looking blob from log strings,
/// so the console stays readable even when the server echoes the request back.
nonisolated private func scrub(_ s: String) -> String {
    var out = s
    if let range = out.range(of: "data:image/[a-z]+;base64,", options: .regularExpression) {
        out.replaceSubrange(range.lowerBound..<out.endIndex, with: "<image-data-omitted>")
    }
    // Collapse any long base64-looking run (>120 chars of A-Za-z0-9+/=) to a placeholder.
    out = out.replacingOccurrences(
        of: "[A-Za-z0-9+/=]{120,}",
        with: "<base64-blob-omitted>",
        options: .regularExpression
    )
    if out.count > 800 { out = String(out.prefix(800)) + "…<truncated>" }
    return out
}

// MARK: - Image Service — wraps the direct Api package (Rust FFI under the hood)
//
// Flow:
//   1. Api.qwen3_6_35b_a3b — chat synthesis, returns assistant prompt.
//   2. Api.flux2Pro — text-to-image, returns image Data inline (no polling).
//   3. UIImage(data:) — decode the bytes for display.

enum ImageServiceError: LocalizedError {
    case requestFailed(String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .requestFailed(let s): return s
        case .decodingFailed:       return "couldn't read result"
        }
    }
}

final class ImageService: @unchecked Sendable {
    static let shared = ImageService()

    private var user: String = ""
    private var password: String = ""

    private init() {}

    static func configure(user: String, password: String) {
        shared.user = user
        shared.password = password
        log("INIT", "user=\(user.prefix(8))…")
    }

    /// Result of a single generation: the decoded image plus the bytes returned
    /// from the API and a synthetic filename for chaining the next iteration.
    struct GenerationResult {
        let image: UIImage
        let data: Data
        let filename: String
    }

    /// N slots run end-to-end in parallel: each does chat synthesis → image
    /// generation. LLM temperature gives each slot a different creative
    /// interpretation of the same seed idea.
    func generate(prompt: String, count: Int) async throws -> [GenerationResult] {
        log("FANOUT", "spawn \(count) end-to-end (chat→generate) slots")
        return try await withThrowingTaskGroup(of: Result<GenerationResult, Error>.self) { group in
            for i in 0..<count {
                group.addTask { [weak self] in
                    guard let self else { return .failure(ImageServiceError.requestFailed("service gone")) }
                    do {
                        let synthesized = try await self.chatSynthesize(idea: prompt, slot: i)
                        let r = try await self.singleGenerate(prompt: synthesized, slot: i)
                        log("SLOT \(i) OK", "image \(Int(r.image.size.width))x\(Int(r.image.size.height))")
                        return .success(r)
                    } catch let e as ImageServiceError {
                        log("SLOT \(i) FAIL", e.errorDescription ?? "unknown")
                        return .failure(e)
                    } catch {
                        log("SLOT \(i) FAIL", "\((error as NSError).domain) \((error as NSError).code)")
                        return .failure(error)
                    }
                }
            }
            var results: [GenerationResult] = []
            var firstError: Error?
            for try await result in group {
                switch result {
                case .success(let r): results.append(r)
                case .failure(let err): if firstError == nil { firstError = err }
                }
            }
            log("FANOUT DONE", "success=\(results.count)/\(count)")
            if results.isEmpty {
                throw firstError ?? ImageServiceError.requestFailed("no images returned")
            }
            return results
        }
    }

    private func chatSynthesize(idea: String, slot: Int) async throws -> String {
        let userIdea = idea.isEmpty ? "Surprise me — generate something interesting." : idea
        log("[slot \(slot)] CHAT", "→ idea.len=\(userIdea.count)")

        let synthesizerRequest = """
            Make image prompt frame for Flux2. Reply with only the prompt, nothing else.
            Idea: \(userIdea)
            """
        let messages = await Api.qwen3_6_35b_a3b(
            user: user,
            password: password,
            messages: [(role: .user, content: synthesizerRequest)]
        )
        if let last = messages.last(where: { $0.role == .assistant })?.content,
           !last.isEmpty {
            log("[slot \(slot)] CHAT OK", "synthesized.len=\(last.count)")
            return last
        }
        log("[slot \(slot)] CHAT FALLBACK", "no assistant content; using original idea")
        return userIdea
    }

    private func singleGenerate(prompt: String, slot: Int) async throws -> GenerationResult {
        log("[slot \(slot)] GEN", "Api.flux2Pro prompt.len=\(prompt.count)")
        let id = UUID()
        let data = await Api.flux2Pro(
            user: user,
            password: password,
            prompt: prompt
        )
        log("[slot \(slot)] GEN OK", "bytes=\(data.count)")
        guard let img = UIImage(data: data) else {
            log("[slot \(slot)] DECODE FAIL", "bytes did not decode as UIImage")
            throw ImageServiceError.decodingFailed
        }
        return GenerationResult(image: img, data: data, filename: "\(id.uuidString).png")
    }
}

// MARK: - Fullscreen image viewer

struct FullScreenImageView: View {
    let image: UIImage
    @Binding var isPresented: Bool

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(1.0, min(lastScale * value, 6.0))
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale <= 1.01 {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                }
                                lastScale = 1.0
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1.0 else { return }
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in lastOffset = offset }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        if scale > 1.0 {
                            scale = 1.0
                            offset = .zero
                        } else {
                            scale = 2.5
                        }
                        lastScale = scale
                        lastOffset = offset
                    }
                }
            VStack {
                HStack {
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(.white.opacity(0.08)))
                            .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                    }
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}


