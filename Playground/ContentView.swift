//
//  ContentView.swift
//  Playground
//
//  Chip-list prompt builder prototype.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @State private var chips: [Chip] = [
        Chip(text: "cinematic golden hour"),
        Chip(text: "lone figure on a misty cobblestone street"),
        Chip(text: "soft film grain"),
        Chip(text: "warm tungsten streetlamps"),
        Chip(text: "shallow depth of field"),
        Chip(text: "muted teal and amber palette"),
        Chip(text: "35mm anamorphic lens flare"),
        Chip(text: "wet pavement reflections"),
        Chip(text: "subject in long charcoal coat"),
        Chip(text: "early 70s european arthouse mood"),
    ]
    @State private var editingId: Chip.ID?
    @State private var editingText: String = ""
    @State private var newChipText: String = ""
    @State private var addingNew = false
    @State private var runs: [Run] = ContentView.makeSeedRuns()
    @State private var editorVisible = true
    /// Stack of recent row removals, each with its own 3-second grace
    /// window. LIFO: tapping Undo restores the most recent. Successive
    /// rapid removes don't clobber each other's undo opportunities.
    @State private var pendingUndos: [PendingUndo] = []

    @FocusState private var focusedField: Field?
    enum Field: Hashable {
        case edit(UUID)
        case add
    }

    private let presets = ["Cinematic", "Neon", "Moody", "Pastel", "Film", "Surreal", "Vintage", "Dreamy"]
    /// Soft cap: prompts beyond this length stop adding new chips. Prevents
    /// runaway lists from making the flow layout enormous and the joined
    /// prompt potentially over backend limits. Existing chips can still be
    /// edited and removed.
    private let maxChips = 20
    /// Soft cap on history depth. Beyond this, oldest runs are dropped on
    /// each Generate so the list stays scannable and the array small.
    private let maxRuns = 30
    /// How many parallel result rows each Generate spawns.
    private let parallelRuns = 3
    private var atCap: Bool { chips.count >= maxChips }

    // MARK: Haptics

    private static let lightHaptic = UIImpactFeedbackGenerator(style: .soft)
    private static let mediumHaptic = UIImpactFeedbackGenerator(style: .light)
    private func tap(_ feedback: UIImpactFeedbackGenerator = ContentView.lightHaptic) {
        feedback.impactOccurred()
    }

    var body: some View {
        ZStack {
            // Ambient background.
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
                                    sectionLabel("RESULTS")
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
        // Keyboard Done button — canonical iOS dismiss-while-editing. Replaces
        // the previous tap-outside layer (which the ScrollView was swallowing).
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissAll() }
                    .foregroundStyle(Color(red: 1.0, green: 0.30, blue: 0.65))
                    .font(.system(size: 15, weight: .semibold))
            }
        }
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
                Text("PROMPT CHIPS")
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
    /// Lets the user wipe the chip set in one tap instead of x-ing 10 chips.
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
            // At soft cap — hide the add affordance entirely so the user can
            // see the wall. Editing and removal still work to free up slots.
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

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(runs) { run in
                resultRow(run)
            }
        }
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
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LinearGradient(
                colors: run.gradient,
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .frame(width: 96, height: 96)
            .overlay {
                switch run.state {
                case .loading:
                    ShimmerOverlay()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                case .loaded:
                    EmptyView()
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

    /// Curated palettes that stand in for generated images in the playground.
    /// The real Engineer screen swaps these for fetched bytes.
    private static let gradientPalettes: [[Color]] = [
        [Color(red: 1.00, green: 0.50, blue: 0.30), Color(red: 0.80, green: 0.20, blue: 0.50)],
        [Color(red: 0.30, green: 0.50, blue: 1.00), Color(red: 0.60, green: 0.20, blue: 0.90)],
        [Color(red: 0.95, green: 0.60, blue: 0.20), Color(red: 0.70, green: 0.30, blue: 0.70)],
        [Color(red: 0.20, green: 0.60, blue: 0.70), Color(red: 0.50, green: 0.80, blue: 0.50)],
        [Color(red: 0.60, green: 0.20, blue: 0.40), Color(red: 0.90, green: 0.40, blue: 0.60)],
        [Color(red: 0.15, green: 0.25, blue: 0.45), Color(red: 0.70, green: 0.45, blue: 0.65)],
    ]

    /// Seeded history so the playground demonstrates the rendered failure
    /// modes on first launch instead of needing the user to tap Generate
    /// repeatedly. Varies chip-count, liked, and failed states to stress
    /// the row layout the way real history would.
    private static func makeSeedRuns() -> [Run] {
        let seeds: [(words: [String], liked: Bool, failed: Bool)] = [
            (["neon-soaked tokyo alleyway",
              "rain-slick asphalt",
              "shopkeeper closing for the night",
              "vapor rising from a ramen stall",
              "purple and cyan signage"], false, false),
            (["pastel sunrise over salt flats",
              "lone tree casting a long shadow"], true, false),
            (["1920s parisian cafe",
              "art deco interior",
              "couple sharing a glance",
              "soft window light",
              "smoke curling from a cigarette holder",
              "sepia tinted"], false, false),
            (["brutalist concrete monolith against a bruised sky"], false, true),
            (["dreamy underwater ballet",
              "schools of bioluminescent fish",
              "diver in vintage brass helmet",
              "shafts of sunlight piercing kelp forest"], true, false),
            (["surreal portrait", "moody lighting", "high contrast"], false, false),
            (["red", "blue", "yellow", "green", "purple",
              "orange", "pink", "teal", "magenta"], false, false),
            (["vintage", "film", "neon"], false, false),
            (["cyberpunk megacity",
              "kowloon walled city aesthetic",
              "rain-slick neon reflections",
              "dense vertical density",
              "advertising holograms",
              "lone drone hovering"], false, false),
        ]
        return seeds.enumerated().map { (i, seed) in
            Run(
                chips: seed.words.map { Chip(text: $0) },
                state: seed.failed ? .failed : .loaded,
                gradient: gradientPalettes[i % gradientPalettes.count],
                liked: seed.liked
            )
        }
    }

    // MARK: Generate

    private var generateButton: some View {
        Button {
            generate()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .bold))
                Text("Generate")
                    .font(.system(size: 17, weight: .bold))
                    .tracking(0.5)
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
        // Commit any in-flight edit BEFORE switching to a new chip, otherwise
        // the previous chip's typed-but-uncommitted text gets silently dropped.
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
            // Soft cap reached. Bounce the field as a signal, keep what was
            // typed so the user can edit it down rather than losing it.
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

    /// Fans out `parallelRuns` mocked synthesizes per Generate tap. Each row
    /// appears shimmering, then resolves on its own jittered timeline so the
    /// rail breathes like real parallel network calls. ~12% of mocked runs
    /// fail, to exercise the failure-state path.
    private func generate() {
        dismissAll()
        tap()
        let snapshot = chips
        let new = (0..<parallelRuns).map { _ in
            Run(
                chips: snapshot.map { Chip(text: $0.text) },
                state: .loading,
                gradient: Self.gradientPalettes.randomElement()!
            )
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            runs.insert(contentsOf: new, at: 0)
            trimHistory()
        }
        for run in new {
            resolveMock(run.id)
        }
    }

    /// Mock resolution of a single run on a jittered timer with a small
    /// failure probability. Used by both initial generation and retry.
    private func resolveMock(_ runId: Run.ID) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Double.random(in: 0.7...1.9)))
            guard let idx = runs.firstIndex(where: { $0.id == runId }) else { return }
            let failed = Int.random(in: 0..<100) < 12
            withAnimation(.easeOut(duration: 0.25)) {
                runs[idx].state = failed ? .failed : .loaded
            }
            if failed {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } else {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
        }
    }

    private func retry(_ run: Run) {
        guard let idx = runs.firstIndex(where: { $0.id == run.id }) else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.easeOut(duration: 0.2)) {
            runs[idx].state = .loading
        }
        resolveMock(run.id)
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
        let undo = PendingUndo(run: runs[idx], index: idx)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            runs.remove(at: idx)
            pendingUndos.append(undo)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.2)) {
                pendingUndos.removeAll { $0.id == undo.id }
            }
        }
    }

    /// LIFO undo — restores the most recent removal first. Toast count
    /// decrements after each tap; subsequent taps walk further back until
    /// the stack drains or entries time out.
    private func undoRemove() {
        guard let undo = pendingUndos.last else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        let insertAt = min(undo.index, runs.count)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            runs.insert(undo.run, at: insertAt)
            pendingUndos.removeAll { $0.id == undo.id }
        }
    }

    private func clearAll() {
        dismissAll()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            chips.removeAll()
        }
    }

    private func toggleLike(_ run: Run) {
        guard let idx = runs.firstIndex(where: { $0.id == run.id }) else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            runs[idx].liked.toggle()
        }
    }

    /// Trims to `maxRuns`, evicting unliked rows from the tail first so the
    /// user's keepers survive past the cap. Liked rows only get evicted as
    /// a last resort (when every remaining row is liked).
    private func trimHistory() {
        var overflow = runs.count - maxRuns
        guard overflow > 0 else { return }
        var i = runs.count - 1
        while overflow > 0 && i >= 0 {
            if !runs[i].liked {
                runs.remove(at: i)
                overflow -= 1
            }
            i -= 1
        }
        if runs.count > maxRuns {
            runs.removeLast(runs.count - maxRuns)
        }
    }

    /// A row is "active" when its prompt matches the editor's current chips.
    /// Derived rather than tracked, so any edit naturally clears the marker
    /// without instrumenting every chip mutation.
    private func isActive(_ run: Run) -> Bool {
        run.chips.map(\.text) == chips.map(\.text)
    }

    /// Joined sentence for the result row's summary. Middle-dot separator
    /// reads more like a curated phrase list than a comma sentence would.
    private func joinedPrompt(for run: Run) -> String {
        run.chips.map(\.text).joined(separator: " · ")
    }
}

// MARK: - Model

struct Chip: Identifiable, Equatable {
    let id = UUID()
    var text: String
}

struct PendingUndo: Identifiable {
    let id = UUID()
    let run: Run
    let index: Int
}

struct Run: Identifiable {
    enum State {
        case loading
        case loaded
        case failed
    }

    let id = UUID()
    var chips: [Chip]
    var state: State
    let gradient: [Color]
    var liked: Bool = false
}

/// Subtle press feedback for the result row — a tap target shouldn't feel
/// silent, but the row is large so the effect is small.
private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Moving highlight band that drifts across its container forever. Used
/// to mark thumbnails as in-flight before the real image arrives.
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

// MARK: - AutoChipField
//
// TextField that sizes to its content width (plus a small padding) up to
// `maxWidth`. Uses a hidden Text mirror as the measurement source via
// PreferenceKey — width follows the typed content reactively without a
// one-frame lag.

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
    static let defaultValue: CGFloat = 70
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - FlowLayout

/// Wraps child views onto multiple lines, like text. Each line left-aligned.
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

#Preview {
    ContentView()
}
