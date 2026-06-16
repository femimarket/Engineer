//
//  ContentView.swift
//  Prod
//
//  Engineer screen — chip-list prompt builder + result history. Productionised
//  from the Playground: real backend (chat synthesize → generate → poll →
//  fetch) and disk-backed persistence so runs and chips survive launches.
//

import SwiftUI
import UIKit
import Api

// MARK: - Models

struct Chip: Identifiable, Equatable, Codable {
    let id: UUID
    var text: String

    init(text: String) {
        self.id = UUID()
        self.text = text
    }
}

struct Run: Identifiable {
    enum State: Codable {
        case loading
        case loaded
        case failed
    }

    let id: UUID
    var chips: [Chip]
    var state: State
    /// Disk filename under `Documents/engineer/`. Empty until loaded.
    var imageFilename: String
    /// Decoded image, cached after first read so the row doesn't re-decode
    /// every render. Nil while loading or failed.
    var image: UIImage?
    var liked: Bool
    /// Index into `gradientPalettes` — used as the shimmer/failure backdrop
    /// and the fallback if decoding fails.
    let paletteIndex: Int
    /// Shared across the rows from one Generate tap so the UI can group them
    /// under one batch header.
    let batchId: UUID
    let createdAt: Date

    init(
        id: UUID = UUID(),
        chips: [Chip],
        state: State,
        imageFilename: String = "",
        image: UIImage? = nil,
        liked: Bool = false,
        paletteIndex: Int,
        batchId: UUID,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.chips = chips
        self.state = state
        self.imageFilename = imageFilename
        self.image = image
        self.liked = liked
        self.paletteIndex = paletteIndex
        self.batchId = batchId
        self.createdAt = createdAt
    }
}

/// One batch as rendered in the RESULTS section. Grouping is derived from
/// `Run.batchId`; this struct only exists to give ForEach a stable identity.
struct RunBatch: Identifiable {
    let id: UUID
    let createdAt: Date
    let runs: [Run]
}

struct PendingUndo: Identifiable {
    let id = UUID()
    let run: Run
    let index: Int
}

/// On-disk record of one row. Only `.loaded` runs persist — anything mid-flight
/// when the app dies is dropped. `batchId` and `createdAt` decode-if-present so
/// runs written by earlier builds still load (they each become their own batch
/// with timestamp = now).
private struct PersistedRun: Codable {
    let id: UUID
    let chips: [Chip]
    let imageFilename: String
    let liked: Bool
    let paletteIndex: Int
    let batchId: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, chips, imageFilename, liked, paletteIndex, batchId, createdAt
    }

    init(id: UUID, chips: [Chip], imageFilename: String, liked: Bool, paletteIndex: Int, batchId: UUID, createdAt: Date) {
        self.id = id
        self.chips = chips
        self.imageFilename = imageFilename
        self.liked = liked
        self.paletteIndex = paletteIndex
        self.batchId = batchId
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        chips = try c.decode([Chip].self, forKey: .chips)
        imageFilename = try c.decode(String.self, forKey: .imageFilename)
        liked = try c.decode(Bool.self, forKey: .liked)
        paletteIndex = try c.decode(Int.self, forKey: .paletteIndex)
        batchId = try c.decodeIfPresent(UUID.self, forKey: .batchId) ?? UUID()
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

// MARK: - Persistence

private enum Store {
    private static let chipsKey = "engineerChips.v1"
    private static let runsKey = "engineerRuns.v1"

    /// `Documents/engineer/` — all image bytes live here.
    private static var dir: URL {
        let d = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("engineer", isDirectory: true)
        if !FileManager.default.fileExists(atPath: d.path) {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }

    static func loadChips() -> [Chip] {
        guard let data = UserDefaults.standard.data(forKey: chipsKey),
              let chips = try? JSONDecoder().decode([Chip].self, from: data) else {
            return []
        }
        return chips
    }

    static func saveChips(_ chips: [Chip]) {
        guard let data = try? JSONEncoder().encode(chips) else { return }
        UserDefaults.standard.set(data, forKey: chipsKey)
    }

    static func loadRuns() -> [Run] {
        guard let data = UserDefaults.standard.data(forKey: runsKey),
              let persisted = try? JSONDecoder().decode([PersistedRun].self, from: data) else {
            return []
        }
        return persisted.compactMap { p in
            let url = dir.appendingPathComponent(p.imageFilename)
            guard let data = try? Data(contentsOf: url),
                  let img = UIImage(data: data) else {
                return nil
            }
            return Run(
                id: p.id,
                chips: p.chips,
                state: .loaded,
                imageFilename: p.imageFilename,
                image: img,
                liked: p.liked,
                paletteIndex: p.paletteIndex,
                batchId: p.batchId,
                createdAt: p.createdAt
            )
        }
    }

    static func saveRuns(_ runs: [Run]) {
        let persisted = runs
            .filter { $0.state == .loaded && !$0.imageFilename.isEmpty }
            .map { PersistedRun(
                id: $0.id,
                chips: $0.chips,
                imageFilename: $0.imageFilename,
                liked: $0.liked,
                paletteIndex: $0.paletteIndex,
                batchId: $0.batchId,
                createdAt: $0.createdAt
            )}
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        UserDefaults.standard.set(data, forKey: runsKey)
    }

    @discardableResult
    static func writeImage(_ data: Data, runId: UUID) -> String {
        let filename = "\(runId.uuidString).png"
        try? data.write(to: dir.appendingPathComponent(filename))
        return filename
    }

    static func deleteImage(filename: String) {
        guard !filename.isEmpty else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(filename))
    }
}

// MARK: - Image service (real backend)

enum ImageServiceError: LocalizedError {
    case requestFailed(String)
    case decodingFailed
    case timedOut
    case taskFailed

    var errorDescription: String? {
        switch self {
        case .requestFailed(let s): return s
        case .decodingFailed: return "couldn't read result"
        case .timedOut: return "took too long"
        case .taskFailed: return "generation failed"
        }
    }
}

final class ImageService: @unchecked Sendable {
    static let shared = ImageService()

    private var bearer: String = ""

    private init() {}

    static func configure(bearer: String) {
        shared.bearer = bearer
        ApiAPIConfiguration.shared.customHeaders["Authorization"] = "Bearer \(bearer)"
    }

    /// One end-to-end synth+generate. Caller supplies the joined prompt; we
    /// run the chat synthesizer to creatively reframe it, then drive the
    /// generate+poll loop and fetch the resulting bytes.
    func synthesizeAndGenerate(idea: String) async throws -> (data: Data, serverFilename: String) {
        let synthesized = try await chatSynthesize(idea: idea)
        try Task.checkCancellation()
        return try await generateAndPoll(prompt: synthesized)
    }

    /// Sends the user's idea to chat and returns one synthesized image prompt.
    /// Per-slot natural variation comes from the LLM's own temperature when N
    /// of these run in parallel against the same input.
    private func chatSynthesize(idea: String) async throws -> String {
        let userIdea = idea.isEmpty ? "Surprise me — generate something interesting." : idea
        let synthesizerRequest = """
            Make image prompt frame for Flux2. Reply with only the prompt, nothing else.
            Idea: \(userIdea)
            """
        let response = try await call(
            action: .chat,
            id: UUID(),
            image: "",
            prompt: "",
            messages: [ApiChatMessage(content: synthesizerRequest, role: .user)]
        )
        if let last = response.messages.last(where: { $0.role == .assistant })?.content,
           !last.isEmpty {
            return last
        }
        if !response.prompt.isEmpty, response.prompt != userIdea {
            return response.prompt
        }
        return userIdea
    }

    private func generateAndPoll(prompt: String) async throws -> (Data, String) {
        let initial = try await call(
            action: .generate,
            id: UUID(),
            image: "",
            prompt: prompt
        )
        var current = initial
        let deadline = Date().addingTimeInterval(120)
        while current.status == .pending {
            try Task.checkCancellation()
            if Date() > deadline { throw ImageServiceError.timedOut }
            try await Task.sleep(nanoseconds: 3_000_000_000)
            current = try await call(
                action: .poll,
                id: current.id,
                requestId: current.requestId,
                image: "",
                prompt: ""
            )
        }
        guard current.status == .completed else { throw ImageServiceError.taskFailed }
        let data = try await fetchMedia(filename: current.file)
        return (data, current.file)
    }

    private func call(
        action: ApiAction,
        id: UUID,
        requestId: String = "",
        image: String,
        prompt: String,
        messages: [ApiChatMessage] = [ApiChatMessage(content: "", role: .user)]
    ) async throws -> API {
        do {
            return try await ApiAPI.api(
                action: action,
                audio: "",
                balance: 0,
                credit: 0,
                file: "",
                id: id,
                image: image,
                messages: messages,
                model: .flux2Pro,
                pay: Self.emptyPay,
                pricing: Self.emptyPricing,
                prompt: prompt,
                requestId: requestId,
                status: .pending,
                userId: ""
            )
        } catch let ErrorResponse.error(status, data, _, underlying) {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let ns = underlying as NSError
            let msg = status > 0
                ? "HTTP \(status) — \(body.prefix(120))"
                : "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
            throw ImageServiceError.requestFailed(msg)
        }
    }

    /// Authenticated fetch of a result image. Mirrors MediaApi from the
    /// Iterate library — kept inline so the Prod target stays self-contained.
    private func fetchMedia(filename: String) async throws -> Data {
        let path = filename.hasPrefix("/") ? String(filename.dropFirst()) : filename
        guard !path.isEmpty, let url = URL(string: "https://femi.market/\(path)") else {
            throw ImageServiceError.requestFailed("bad media path")
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await Self.mediaSession.data(for: req)
        return data
    }

    private static let mediaSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 6
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()

    private static let emptyPay = ApiPay(
        currency: "", id: UUID(), jws: "", loaded: false, orderId: nil,
        packageName: "", price: 0, productId: "", provider: .apple,
        refId: "", userId: ""
    )

    private static let emptyPricing = ApiPricing(
        artist: 0, audio: 0, chat: 0, creator: 0, director: 0,
        falFlux2Pro: 0, falNanoBanana2: 0, falZImageTurbo: 0,
        gb: 0, generate: 0, id: UUID(), image: 0, lyricSync: 0,
        microPixLyra: 0, microPixVega: 0, nanoPixLuna: 0, nanoRenSpica: 0,
        question: 0, summary: 0, upload: 0
    )
}

// MARK: - ContentView

struct ContentView: View {
    @State private var chips: [Chip]
    @State private var runs: [Run]
    @State private var editingId: Chip.ID?
    @State private var editingText: String = ""
    @State private var newChipText: String = ""
    @State private var addingNew = false
    @State private var editorVisible = true
    @State private var pendingUndos: [PendingUndo] = []
    /// In-flight generation tasks, keyed by run id. Cancelled when the row
    /// is removed so we don't burn API calls on results no one will see.
    @State private var inflight: [Run.ID: Task<Void, Never>] = [:]
    @State private var showLikedOnly = false

    @FocusState private var focusedField: Field?
    enum Field: Hashable {
        case edit(UUID)
        case add
    }

    init(bearer: String) {
        ImageService.configure(bearer: bearer)
        _chips = State(initialValue: Store.loadChips())
        _runs = State(initialValue: Store.loadRuns())
    }

    private let presets = ["Cinematic", "Neon", "Moody", "Pastel", "Film", "Surreal", "Vintage", "Dreamy"]
    private let maxChips = 20
    private let maxRuns = 30
    private let parallelRuns = 3
    /// Credits charged per row generated (1 chat + 1 image generation). One
    /// Generate tap fans out to `parallelRuns × creditPerRun` credits total.
    private let creditPerRun = 1
    private var costPerGenerate: Int { creditPerRun * parallelRuns }
    private var atCap: Bool { chips.count >= maxChips }

    private static let lightHaptic = UIImpactFeedbackGenerator(style: .soft)
    private static let mediumHaptic = UIImpactFeedbackGenerator(style: .light)
    private func tap(_ feedback: UIImpactFeedbackGenerator = ContentView.lightHaptic) {
        feedback.impactOccurred()
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(
                colors: [Color(red: 0.42, green: 0.10, blue: 0.55).opacity(0.35), .clear],
                center: .init(x: 0.18, y: 0.05), startRadius: 0, endRadius: 420
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [Color(red: 0.95, green: 0.30, blue: 0.55).opacity(0.22), .clear],
                center: .init(x: 0.92, y: 0.08), startRadius: 0, endRadius: 320
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    ZStack(alignment: .top) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                promptHeader
                                    .id("editorTop")
                                chipFlow
                                    .padding(.horizontal, 16)
                                    .onScrollVisibilityChange { visible in
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            editorVisible = visible
                                        }
                                    }

                                sectionLabel("PRESETS")
                                presetRail

                                if !runs.isEmpty {
                                    resultsHeader
                                    resultsSection
                                }
                            }
                            .padding(.vertical, 16)
                        }
                        .scrollIndicators(.hidden)
                        .scrollDismissesKeyboard(.interactively)

                        if !editorVisible && !chips.isEmpty {
                            backToEditorPill(proxy: proxy)
                                .padding(.top, 8)
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .zIndex(1)
                        }
                    }
                }

                generateButton
                    .padding(.horizontal, 22)
                    .padding(.bottom, 14)
            }

            if !pendingUndos.isEmpty {
                VStack {
                    Spacer()
                    undoToast
                        .padding(.horizontal, 22)
                        .padding(.bottom, 88)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .allowsHitTesting(true)
            }
        }
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissAll() }
                    .foregroundStyle(Color(red: 1.0, green: 0.30, blue: 0.65))
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .onChange(of: chips) { _, new in Store.saveChips(new) }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.55, green: 0.20, blue: 1.0),
                                 Color(red: 1.0, green: 0.30, blue: 0.65)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: 8, height: 8)
                Text("ENGINEER")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(2.8)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    /// Floating status reader shown when the editor has scrolled out of view.
    /// Displays the live joined prompt (truncated) so the user can confirm
    /// restores from history without scrolling, and tap to spring back to
    /// the editor when they want to edit.
    private func backToEditorPill(proxy: ScrollViewProxy) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                proxy.scrollTo("editorTop", anchor: .top)
            }
        } label: {
            HStack(spacing: 8) {
                Text(chips.map(\.text).joined(separator: " · "))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .heavy))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: 320)
            .background(
                Capsule().fill(LinearGradient(
                    colors: [Color(red: 0.55, green: 0.20, blue: 1.0).opacity(0.92),
                             Color(red: 1.0, green: 0.30, blue: 0.65).opacity(0.92)],
                    startPoint: .leading, endPoint: .trailing
                ))
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.7))
            .shadow(color: Color(red: 0.95, green: 0.30, blue: 0.65).opacity(0.35), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scroll back to editor. Current prompt: \(chips.map(\.text).joined(separator: ", "))")
    }

    /// Transient toast for undoing the last row removal. Auto-dismisses
    /// after 3 seconds — long enough to catch a mistake, short enough not
    /// to clutter the screen.
    private var undoToast: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text(pendingUndos.count > 1
                 ? "\(pendingUndos.count) results removed"
                 : "Result removed")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            Button {
                undoRemove()
            } label: {
                Text("Undo")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.30, blue: 0.65))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo remove")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.7))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
    }

    /// PROMPT section header with an inline CLEAR affordance on the right.
    private var promptHeader: some View {
        HStack(spacing: 0) {
            sectionLabel("PROMPT")
            Spacer()
            if !chips.isEmpty {
                Button {
                    clearAll()
                } label: {
                    Text("CLEAR")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.05)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 22)
                .accessibilityLabel("Clear all phrases")
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy))
            .tracking(2)
            .foregroundStyle(.white.opacity(0.45))
            .padding(.horizontal, 22)
    }

    // MARK: Chip flow

    private var chipFlow: some View {
        VStack(alignment: .leading, spacing: 0) {
            ChipFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(chips) { chip in
                    chipView(chip)
                }
                addChipView
            }
            if chips.isEmpty && !addingNew {
                Text("tap + to begin engineering your prompt")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 10)
            }
        }
    }

    @ViewBuilder
    private func chipView(_ chip: Chip) -> some View {
        if editingId == chip.id {
            inlineEditor(for: chip)
        } else {
            HStack(spacing: 6) {
                Text(chip.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 300, alignment: .leading)
                    .onTapGesture {
                        beginEdit(chip)
                    }
                    .accessibilityHint("Double-tap to edit")
                Button {
                    remove(chip)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(chip.text)")
            }
            .padding(.leading, 14)
            .padding(.trailing, 5)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }

    private func inlineEditor(for chip: Chip) -> some View {
        AutoChipField(
            text: $editingText,
            placeholder: "",
            maxWidth: 240,
            submitLabel: .done,
            onSubmit: { commitEdit() },
            focus: $focusedField,
            focusValue: .edit(chip.id)
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color.white.opacity(0.14)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.7))
    }

    @ViewBuilder
    private var addChipView: some View {
        if atCap && !addingNew {
            EmptyView()
        } else {
            addChipBody
        }
    }

    private var addChipBody: some View {
        Group {
            if addingNew {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                    AutoChipField(
                        text: $newChipText,
                        placeholder: "phrase",
                        maxWidth: 240,
                        submitLabel: .next,
                        onSubmit: { commitAndContinueAdd() },
                        focus: $focusedField,
                        focusValue: .add
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.14)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.7))
            } else {
                Button {
                    beginAdd()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("add")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.04)))
                    .overlay(
                        Capsule().strokeBorder(.white.opacity(0.18),
                                               style: StrokeStyle(lineWidth: 0.7, dash: [3, 4]))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add phrase")
            }
        }
    }

    // MARK: Preset rail

    private var presetRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { p in
                    Button {
                        insertPreset(p)
                    } label: {
                        Text(p)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(.white.opacity(0.06)))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
        }
    }

    // MARK: Results

    /// RESULTS row with the LIKED filter chip on the right. Filter is hidden
    /// when no liked rows exist (nothing to surface, no point in the affordance).
    private var resultsHeader: some View {
        HStack(spacing: 0) {
            sectionLabel("RESULTS")
            Spacer()
            if runs.contains(where: { $0.liked }) {
                likedFilterChip
                    .padding(.trailing, 22)
            }
        }
    }

    private var likedFilterChip: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.easeInOut(duration: 0.2)) {
                showLikedOnly.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: showLikedOnly ? "heart.fill" : "heart")
                    .font(.system(size: 9, weight: .heavy))
                Text("LIKED")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.5)
            }
            .foregroundStyle(showLikedOnly
                ? Color(red: 1.0, green: 0.30, blue: 0.65)
                : .white.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(showLikedOnly
                ? Color(red: 1.0, green: 0.30, blue: 0.65).opacity(0.15)
                : .white.opacity(0.05)))
            .overlay(Capsule().strokeBorder(showLikedOnly
                ? Color(red: 1.0, green: 0.30, blue: 0.65).opacity(0.5)
                : .white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showLikedOnly ? "Show all results" : "Show only liked results")
    }

    private var resultsSection: some View {
        let filtered = showLikedOnly ? runs.filter(\.liked) : runs
        let batches = batched(filtered)
        return VStack(alignment: .leading, spacing: 16) {
            ForEach(batches) { batch in
                VStack(alignment: .leading, spacing: 10) {
                    batchHeader(batch.createdAt)
                    ForEach(batch.runs) { run in
                        resultRow(run)
                    }
                }
            }
        }
    }

    /// "GENERATED · 2m ago" caption above each batch of rows. Snapshot at
    /// render time — relative string ages with each scroll re-render, which
    /// is good enough for human time perception without a 1s timer.
    private func batchHeader(_ date: Date) -> some View {
        HStack(spacing: 6) {
            Text("GENERATED")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.2)
            Text("·")
                .font(.system(size: 9, weight: .heavy))
            Text(Self.relativeString(date))
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.8)
        }
        .foregroundStyle(.white.opacity(0.4))
        .padding(.horizontal, 22)
    }

    /// Groups consecutive runs with the same `batchId` into one render unit.
    /// Order is preserved — a run can't migrate batches, so we walk linearly.
    private func batched(_ runs: [Run]) -> [RunBatch] {
        var result: [RunBatch] = []
        var current: [Run] = []
        for run in runs {
            if let first = current.first, first.batchId == run.batchId {
                current.append(run)
            } else {
                if let first = current.first {
                    result.append(RunBatch(id: first.batchId, createdAt: first.createdAt, runs: current))
                }
                current = [run]
            }
        }
        if let first = current.first {
            result.append(RunBatch(id: first.batchId, createdAt: first.createdAt, runs: current))
        }
        return result
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static func relativeString(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func resultRow(_ run: Run) -> some View {
        let active = isActive(run)
        return Button {
            restore(run)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                thumbnail(run)
                VStack(alignment: .leading, spacing: 6) {
                    Text(joinedPrompt(for: run))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(run.chips.count) \(run.chips.count == 1 ? "phrase" : "phrases")")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.4))
                }
                VStack(spacing: 8) {
                    if run.state == .failed {
                        retryButton(run)
                    } else {
                        heartButton(run)
                    }
                    removeButton(run)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(active ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        active
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Color(red: 0.55, green: 0.20, blue: 1.0),
                                         Color(red: 1.0, green: 0.30, blue: 0.65)],
                                startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color.white.opacity(0.08)),
                        lineWidth: active ? 1.2 : 0.5
                    )
            )
        }
        .buttonStyle(RowPressStyle())
        .padding(.horizontal, 22)
        .accessibilityLabel("Restore prompt: \(run.chips.map(\.text).joined(separator: ", "))")
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    private func heartButton(_ run: Run) -> some View {
        Button {
            toggleLike(run)
        } label: {
            Image(systemName: run.liked ? "heart.fill" : "heart")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(run.liked
                    ? Color(red: 1.0, green: 0.30, blue: 0.65)
                    : .white.opacity(0.55))
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(run.liked ? "Unlike result" : "Like result")
    }

    private func retryButton(_ run: Run) -> some View {
        Button {
            retry(run)
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Retry generation")
    }

    private func removeButton(_ run: Run) -> some View {
        Button {
            removeRun(run)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove result")
    }

    private func thumbnail(_ run: Run) -> some View {
        let palette = Self.gradientPalettes[run.paletteIndex % Self.gradientPalettes.count]
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LinearGradient(
                colors: palette,
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .frame(width: 96, height: 96)
            .overlay {
                switch run.state {
                case .loading:
                    ShimmerOverlay()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                case .loaded:
                    if let img = run.image {
                        Image(uiImage: img)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                case .failed:
                    ZStack {
                        Color.black.opacity(0.45)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
    }

    private static let gradientPalettes: [[Color]] = [
        [Color(red: 1.00, green: 0.50, blue: 0.30), Color(red: 0.80, green: 0.20, blue: 0.50)],
        [Color(red: 0.30, green: 0.50, blue: 1.00), Color(red: 0.60, green: 0.20, blue: 0.90)],
        [Color(red: 0.95, green: 0.60, blue: 0.20), Color(red: 0.70, green: 0.30, blue: 0.70)],
        [Color(red: 0.20, green: 0.60, blue: 0.70), Color(red: 0.50, green: 0.80, blue: 0.50)],
        [Color(red: 0.60, green: 0.20, blue: 0.40), Color(red: 0.90, green: 0.40, blue: 0.60)],
        [Color(red: 0.15, green: 0.25, blue: 0.45), Color(red: 0.70, green: 0.45, blue: 0.65)],
    ]

    // MARK: Generate

    private var generateButton: some View {
        Button {
            generate()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .bold))
                VStack(spacing: 1) {
                    Text("Generate")
                        .font(.system(size: 17, weight: .bold))
                        .tracking(0.5)
                    Text("\(costPerGenerate) credits")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.4)
                        .opacity(0.7)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.55, green: 0.20, blue: 1.0),
                                 Color(red: 1.0, green: 0.30, blue: 0.65)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    LinearGradient(
                        colors: [.white.opacity(0.35), .clear],
                        startPoint: .top, endPoint: .center
                    ).blendMode(.plusLighter).opacity(0.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.5), lineWidth: 0.7)
            }
            .shadow(color: Color(red: 0.95, green: 0.30, blue: 0.65).opacity(0.45), radius: 24, y: 10)
            .opacity(chips.isEmpty ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(chips.isEmpty)
    }

    // MARK: Actions

    private func beginEdit(_ chip: Chip) {
        commitEdit()
        commitAdd()
        tap()
        editingId = chip.id
        editingText = chip.text
        DispatchQueue.main.async {
            focusedField = .edit(chip.id)
        }
    }

    private func commitEdit() {
        guard let id = editingId else { return }
        let trimmed = editingText.trimmingCharacters(in: .whitespaces)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if trimmed.isEmpty {
                chips.removeAll { $0.id == id }
            } else if let idx = chips.firstIndex(where: { $0.id == id }) {
                chips[idx].text = trimmed
            }
            editingId = nil
            editingText = ""
        }
    }

    private func remove(_ chip: Chip) {
        tap(ContentView.mediumHaptic)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            chips.removeAll { $0.id == chip.id }
        }
    }

    private func beginAdd() {
        commitEdit()
        tap()
        addingNew = true
        newChipText = ""
        DispatchQueue.main.async {
            focusedField = .add
        }
    }

    private func commitAndContinueAdd() {
        guard addingNew else { return }
        let trimmed = newChipText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            addingNew = false
            newChipText = ""
            focusedField = nil
            return
        }
        if atCap {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        tap()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            chips.append(Chip(text: trimmed))
            newChipText = ""
        }
        DispatchQueue.main.async {
            focusedField = .add
        }
    }

    private func commitAdd() {
        guard addingNew else { return }
        let trimmed = newChipText.trimmingCharacters(in: .whitespaces)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if !trimmed.isEmpty && !atCap {
                chips.append(Chip(text: trimmed))
            }
            addingNew = false
            newChipText = ""
        }
    }

    private func insertPreset(_ name: String) {
        commitEdit()
        commitAdd()
        guard !atCap else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        tap()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            chips.append(Chip(text: name.lowercased()))
        }
    }

    private func dismissAll() {
        commitEdit()
        commitAdd()
        focusedField = nil
    }

    private func clearAll() {
        dismissAll()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            chips.removeAll()
        }
    }

    /// Fans out `parallelRuns` real synthesizes per Generate tap. Each row
    /// appears shimmering, then resolves via the live chat→generate→poll→fetch
    /// pipeline. Per-row Tasks are tracked so removeRun can cancel them.
    private func generate() {
        guard !chips.isEmpty else { return }
        dismissAll()
        tap()
        let snapshot = chips.map { Chip(text: $0.text) }
        let idea = snapshot.map(\.text).joined(separator: ", ")
        let batchId = UUID()
        let createdAt = Date()
        let new = (0..<parallelRuns).map { _ in
            Run(
                chips: snapshot.map { Chip(text: $0.text) },
                state: .loading,
                paletteIndex: Int.random(in: 0..<Self.gradientPalettes.count),
                batchId: batchId,
                createdAt: createdAt
            )
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            runs.insert(contentsOf: new, at: 0)
            trimHistory()
        }
        Store.saveRuns(runs)
        for run in new {
            resolveReal(runId: run.id, idea: idea)
        }
    }

    private func retry(_ run: Run) {
        guard let idx = runs.firstIndex(where: { $0.id == run.id }) else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        let idea = run.chips.map(\.text).joined(separator: ", ")
        withAnimation(.easeOut(duration: 0.2)) {
            runs[idx].state = .loading
        }
        resolveReal(runId: run.id, idea: idea)
    }

    /// Live API resolution for a single row. Stores the image bytes to disk
    /// on success and updates `runs` in place. Cancellation (via removeRun)
    /// propagates through Task.checkCancellation so we don't burn API calls.
    private func resolveReal(runId: Run.ID, idea: String) {
        let task = Task { @MainActor in
            defer { inflight.removeValue(forKey: runId) }
            do {
                let (data, _) = try await ImageService.shared.synthesizeAndGenerate(idea: idea)
                try Task.checkCancellation()
                guard let idx = runs.firstIndex(where: { $0.id == runId }) else { return }
                guard let img = UIImage(data: data) else { throw ImageServiceError.decodingFailed }
                let filename = Store.writeImage(data, runId: runId)
                withAnimation(.easeOut(duration: 0.25)) {
                    runs[idx].state = .loaded
                    runs[idx].imageFilename = filename
                    runs[idx].image = img
                }
                Store.saveRuns(runs)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            } catch is CancellationError {
                // Row was removed before generation finished — nothing to do.
            } catch {
                guard let idx = runs.firstIndex(where: { $0.id == runId }) else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    runs[idx].state = .failed
                }
                Store.saveRuns(runs)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
        inflight[runId] = task
    }

    /// Tap a past run to replace the editor with its prompt. Fresh chip IDs
    /// avoid collisions with the row that's still rendering the snapshot.
    private func restore(_ run: Run) {
        dismissAll()
        tap()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            chips = run.chips.map { Chip(text: $0.text) }
        }
    }

    private func removeRun(_ run: Run) {
        guard let idx = runs.firstIndex(where: { $0.id == run.id }) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Cancel any in-flight generation so we don't pay for unwanted bytes.
        inflight[run.id]?.cancel()
        inflight.removeValue(forKey: run.id)
        let undo = PendingUndo(run: runs[idx], index: idx)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            runs.remove(at: idx)
            pendingUndos.append(undo)
        }
        Store.saveRuns(runs)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            // If the user didn't undo, delete the disk bytes for real and
            // drop the entry from the undo stack.
            if pendingUndos.contains(where: { $0.id == undo.id }) {
                Store.deleteImage(filename: undo.run.imageFilename)
                withAnimation(.easeOut(duration: 0.2)) {
                    pendingUndos.removeAll { $0.id == undo.id }
                }
            }
        }
    }

    /// LIFO undo — restores the most recent removal first.
    private func undoRemove() {
        guard let undo = pendingUndos.last else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        let insertAt = min(undo.index, runs.count)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            runs.insert(undo.run, at: insertAt)
            pendingUndos.removeAll { $0.id == undo.id }
        }
        Store.saveRuns(runs)
    }

    private func toggleLike(_ run: Run) {
        guard let idx = runs.firstIndex(where: { $0.id == run.id }) else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            runs[idx].liked.toggle()
        }
        Store.saveRuns(runs)
    }

    /// Trims to `maxRuns`, evicting unliked rows from the tail first so the
    /// user's keepers survive past the cap.
    private func trimHistory() {
        var overflow = runs.count - maxRuns
        guard overflow > 0 else { return }
        var i = runs.count - 1
        while overflow > 0 && i >= 0 {
            if !runs[i].liked {
                let dropped = runs.remove(at: i)
                Store.deleteImage(filename: dropped.imageFilename)
                overflow -= 1
            }
            i -= 1
        }
        if runs.count > maxRuns {
            let oldestExcess = runs.count - maxRuns
            for r in runs.suffix(oldestExcess) {
                Store.deleteImage(filename: r.imageFilename)
            }
            runs.removeLast(oldestExcess)
        }
    }

    private func isActive(_ run: Run) -> Bool {
        run.chips.map(\.text) == chips.map(\.text)
    }

    private func joinedPrompt(for run: Run) -> String {
        run.chips.map(\.text).joined(separator: " · ")
    }
}

// MARK: - AutoChipField

private struct AutoChipField: View {
    @Binding var text: String
    var placeholder: String
    var maxWidth: CGFloat
    var font: Font = .system(size: 14, weight: .medium)
    var submitLabel: SubmitLabel = .done
    var onSubmit: () -> Void
    @FocusState.Binding var focus: ContentView.Field?
    var focusValue: ContentView.Field

    @State private var measuredWidth: CGFloat = 70

    var body: some View {
        TextField(
            "",
            text: $text,
            prompt: Text(placeholder).foregroundColor(.white.opacity(0.35))
        )
        .focused($focus, equals: focusValue)
        .font(font)
        .foregroundStyle(.white)
        .tint(.white)
        .submitLabel(submitLabel)
        .onSubmit(onSubmit)
        .frame(width: measuredWidth)
        .background(measuringMirror)
        .onPreferenceChange(ChipWidthKey.self) { w in
            measuredWidth = min(max(60, w + 4), maxWidth)
        }
    }

    private var measuringMirror: some View {
        Text(text.isEmpty ? placeholder : text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ChipWidthKey.self, value: geo.size.width)
                }
            )
            .opacity(0)
    }
}

private struct ChipWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 70
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - FlowLayout

struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                maxLineWidth = max(maxLineWidth, x - spacing)
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        maxLineWidth = max(maxLineWidth, x - spacing)
        return CGSize(width: maxLineWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Shimmer + Press style

private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct ShimmerOverlay: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [.white.opacity(0), .white.opacity(0.35), .white.opacity(0)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: geo.size.width * 0.6)
            .offset(x: phase * geo.size.width * 1.6)
            .blendMode(.plusLighter)
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    ContentView(bearer: "019ec07a-c943-7275-b758-2315b8c9fa6f")
}
