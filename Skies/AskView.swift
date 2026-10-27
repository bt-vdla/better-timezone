import SwiftUI

/// Ask Skies: one big field, the best answer as a card with both clocks over their sky, then everything else.
/// The same view fills the sheet on iPhone and the window on Mac, and sits compact inside the notch.
struct AskView: View {
    @Binding var query: String
    let people: People
    let places: PlaceLookup
    var compact = false
    /// Off in the notch, where the skies sit under an empty field instead.
    var examples = true
    /// Shown in the empty field; the notch rotates real questions through it.
    var placeholder: String? = nil
    /// Keys for an empty field (the notch scrubs time with ← → and Space); true if used.
    var emptyKey: ((KeyEquivalent) -> Bool)? = nil
    /// Flips to true each time the field should take focus again (the notch reopening).
    var refocus = false
    let run: (Hit) -> Void
    let cancel: () -> Void
    @State private var selection = 0
    @FocusState private var focused: Bool

    /// How many rows the notch shows under its card, so it can size itself to fit.
    static func rows(_ hits: [Hit]) -> (card: Bool, rows: Int) {
        let card = hits.first.map { !$0.clocks.isEmpty } ?? false
        return (card, min(card ? 2 : 4, hits.count - (card ? 1 : 0)))
    }

    /// The notch's metrics, in one place, so its height is measured from the same numbers the layout uses.
    enum Compact {
        static let field: CGFloat = 30, gap: CGFloat = 8, card: CGFloat = 64, row: CGFloat = 32, rowGap: CGFloat = 2, readAs: CGFloat = 14

        /// The open notch's corner and how far its content sits in from the edge, on all three sides while asking.
        static let outer: CGFloat = 32, inset: CGFloat = 14
        /// Concentric with the notch: an inner corner is the outer one less the gap between them.
        static let cardRadius: CGFloat = outer - inset
        /// The field is a smaller, separate shape higher up: rounder than the rows, softer than the card.
        static let fieldRadius: CGFloat = 12

        /// The card grows a line for a clock-change cue.
        static func cardHeight(_ hit: Hit) -> CGFloat { card + (hit.cue == nil ? 0 : 16) }

        /// Height of the compact view once something's typed.
        static func height(_ hits: [Hit], corrected: Bool = false) -> CGFloat {
            let l = AskView.rows(hits)
            let top = field + (corrected ? gap + readAs : 0)
            if hits.isEmpty { return top + gap + row }
            return top + (l.card ? gap + cardHeight(hits[0]) : 0)
                + (l.rows > 0 ? gap + CGFloat(l.rows) * row + CGFloat(l.rows - 1) * rowGap : 0)
        }
    }

    var body: some View {
        let hits = Ask.hits(query, people: people.list, now: nowMinutes(), extra: places.zones)
        let readAs = Ask.readAs(query, people: people.list, now: nowMinutes(), extra: places.zones)
        let layout = Self.rows(hits)
        VStack(alignment: .leading, spacing: compact ? Compact.gap : 14) {
            field(hits)
            // What a typo was taken to mean, so a correction is never a surprise.
            if let readAs {
                Label {
                    Text("Read as \u{201C}\(readAs)\u{201D}")
                } icon: {
                    Image(systemName: "wand.and.sparkles")
                }
                .labelStyle(TightLabel())
                .font(.sf(compact ? 11 : 13, .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .frame(height: compact ? Compact.readAs : nil, alignment: .leading)
                .padding(.horizontal, compact ? 10 : 4)
                .transition(.opacity)
            }
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                if examples { examplesView }
            } else if hits.isEmpty {
                Text("Nothing yet. Try a name, a place and a time, like \u{201C}India 3pm\u{201D}.")
                    .font(.sf(compact ? 12 : 14, .medium)).opacity(0.55)
                    .frame(maxWidth: .infinity, minHeight: compact ? Compact.row : 44, alignment: .leading)
                    .padding(.horizontal, compact ? 12 : 4)
            } else {
                if layout.card, let top = hits.first {
                    AnswerCard(hit: top, compact: compact, selected: selection == 0) { run(top) }
                }
                let rest = Array(hits.dropFirst(layout.card ? 1 : 0).prefix(compact ? layout.rows : 8))
                VStack(spacing: compact ? Compact.rowGap : 4) {
                    ForEach(Array(rest.enumerated()), id: \.element.id) { i, h in
                        let index = i + (layout.card ? 1 : 0)
                        Button { run(h) } label: {
                            HitRow(hit: h, compact: compact)
                                .padding(.horizontal, compact ? 10 : 12)
                                .frame(height: compact ? Compact.row : 52)
                                .background(selection == index && h.action != nil ? Color.white.opacity(0.1) : .clear,
                                            in: RoundedRectangle(cornerRadius: compact ? 8 : 12, style: .continuous))
                        }
                        .buttonStyle(.whole)
                        .disabled(h.action == nil)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .onChange(of: query) { selection = 0 }
        .onAppear { focused = true }
        .onChange(of: refocus) { if refocus { focused = true } }
        .task(id: query) { await places.look(for: query, people: people.list) }
    }

    private func field(_ hits: [Hit]) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.sf(compact ? 13 : 20, .semibold))
                .foregroundStyle(Color.sun)
            // Our own placeholder, so the caret sits before it rather than on its first letter, and a new
            // example can cross-fade in.
            TextField("", text: $query)
                .textFieldStyle(.plain)
                .font(.sf(compact ? 14 : 22, compact ? .medium : .regular))
                .overlay(alignment: .leading) {
                    if query.isEmpty {
                        Text(placeholder ?? (compact ? "India 3pm, is Amma awake…" : "Ask Skies"))
                            .font(.sf(compact ? 14 : 22, compact ? .medium : .regular))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                            .padding(.leading, 2)
                            .id(placeholder)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
                .animation(.easeOutStrong(0.25), value: placeholder)
                .focused($focused)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .submitLabel(.go)
                #endif
                .onSubmit { pick(hits) }
                .onKeyPress(.downArrow) { selection = min(selection + 1, max(0, hits.count - 1)); return .handled }
                .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
                .onKeyPress(.escape) { query.isEmpty ? cancel() : (query = ""); return .handled }
                .onKeyPress(keys: [.leftArrow, .rightArrow, .space]) { press in
                    query.isEmpty && emptyKey?(press.key) == true ? .handled : .ignored
                }
            // Clear appears with text; an empty field closes with Esc (the notch) or Close (the sheet).
            if !query.isEmpty || !compact {
                Button { query.isEmpty ? cancel() : (query = "") } label: {
                    Image(systemName: query.isEmpty ? "xmark" : "xmark.circle.fill")
                        .font(.sf(compact ? 12 : 15, .semibold)).opacity(0.45)
                        .frame(width: compact ? 20 : 30, height: compact ? 20 : 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.whole)
                .accessibilityLabel(query.isEmpty ? "Close" : "Clear")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, compact ? 10 : 16)
        .frame(height: compact ? Compact.field : 56)
        // A lighter fill than the tiles (it's the control), and a rim that brightens only once you're typing.
        .background(.white.opacity(compact ? 0.09 : 0.08), in: RoundedRectangle(cornerRadius: compact ? Compact.fieldRadius : 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? Compact.fieldRadius : 16, style: .continuous)
                .strokeBorder(.white.opacity(query.isEmpty ? 0.08 : 0.2), lineWidth: 1)
        }
        .animation(.easeOutStrong(0.2), value: query.isEmpty)
    }

    private func pick(_ hits: [Hit]) {
        let usable = hits.indices.contains(selection) && hits[selection].action != nil ? hits[selection] : hits.first { $0.action != nil }
        if let usable { run(usable) }
    }

    /// Built from your own people and tags, so every one of them works.
    private var examplesView: some View {
        let other = people.list.first { !$0.isHome }
        let tag = people.usedTags.first
        let list = [other.map { "Is \($0.name) awake?" }, tag.map { "When can I talk to \($0.name.lowercased())?" },
                    "India 3pm", other.map { "\($0.name) fri 9am" }, "Time in Tokyo"].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 10) {
            if !compact {
                Text("Ask about your people, or any place and time.").font(.sf(13, .medium)).opacity(0.55).padding(.horizontal, 4)
            }
            Flow(spacing: compact ? 6 : 8) {
                ForEach(list, id: \.self) { e in
                    Button { query = e } label: {
                        Text(e).font(.sf(compact ? 12 : 14, .medium))
                            .padding(.horizontal, compact ? 10 : 14).frame(height: compact ? 26 : 34)
                            .background(.white.opacity(0.1), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.whole)
                }
            }
            .padding(.horizontal, compact ? 2 : 0)
        }
    }
}

/// The best answer, big: their clock beside yours, over the sky where they are at that moment.
struct AnswerCard: View {
    let hit: Hit
    var compact = false
    var selected = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: compact ? 12 : 18) {
                VStack(alignment: .leading, spacing: compact ? 2 : 6) {
                    Label(hit.headline ?? hit.title, systemImage: hit.icon)
                        .labelStyle(TightLabel())
                        .font(.sf(compact ? 12 : 15, .semibold))
                        .lineLimit(compact ? 1 : 2)
                    if let note = hit.note ?? (hit.clocks.isEmpty ? hit.detail : nil), !compact || hit.clocks.isEmpty {
                        Text(note).font(.sf(compact ? 11 : 13, .medium)).opacity(0.75).lineLimit(2)
                    }
                    // The biggest size at which both clocks fit whole, the same for both, so they read as a pair.
                    ViewThatFits(in: .horizontal) {
                        ForEach(sizes, id: \.self) { clocksRow($0) }
                    }
                    .padding(.top, compact ? 0 : 4)
                    // A clock change that affects this answer.
                    if let cue = hit.cue {
                        Label(cue, systemImage: "clock.arrow.2.circlepath")
                            .labelStyle(TightLabel())
                            .font(.sf(compact ? 11 : 13, .medium))
                            .foregroundStyle(Color.sun)
                            .lineLimit(compact ? 1 : 2)
                            .minimumScaleFactor(0.85)
                            .padding(.top, compact ? 0 : 2)
                    }
                }
                Spacer(minLength: 0)
                if hit.action != nil {
                    Image(systemName: "arrow.right.circle.fill").font(.sf(compact ? 18 : 28, .regular)).opacity(0.85)
                }
            }
            .skyLegible()
            .padding(compact ? 10 : 18)
            .frame(maxWidth: .infinity, minHeight: compact ? AskView.Compact.cardHeight(hit) : 150,
                   maxHeight: compact ? AskView.Compact.cardHeight(hit) : nil, alignment: .leading)
            .background { background }
            .clipShape(RoundedRectangle(cornerRadius: compact ? AskView.Compact.cardRadius : 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: compact ? AskView.Compact.cardRadius : 20, style: .continuous)
                    .strokeBorder(.white.opacity(selected ? 0.35 : 0.12), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: compact ? AskView.Compact.cardRadius : 20, style: .continuous))
        }
        .buttonStyle(PressScale(scale: 0.98))
        .disabled(hit.action == nil)
    }

    private var sizes: [CGFloat] { compact ? [19, 17, 15] : [28, 25, 22, 19] }

    /// Top-aligned columns: labels, times and days each share a line; the gap sits between, above the arrow.
    private func clocksRow(_ size: CGFloat) -> some View {
        HStack(alignment: .top, spacing: compact ? 10 : 14) {
            ForEach(Array(hit.clocks.enumerated()), id: \.offset) { i, c in
                if i > 0 {
                    VStack(spacing: 1) {
                        if let gap = hit.gap {
                            Text(gap).font(.sf(compact ? 9 : 11, .semibold)).monospacedDigit().opacity(0.8)
                        }
                        Image(systemName: "arrow.right").font(.sf(compact ? 10 : 13, .semibold)).opacity(0.5)
                    }
                    .fixedSize()
                    .padding(.top, hit.gap == nil ? (compact ? 16 : 24) : (compact ? 8 : 14))
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(c.place.uppercased()).font(.sf(compact ? 9 : 11, .semibold)).tracking(0.6).opacity(0.7).lineLimit(1)
                    Text(c.time).font(.sf(size, .light)).monospacedDigit().lineLimit(1).fixedSize()
                    if !compact { Text(c.day).font(.sf(12, .medium)).opacity(0.7).lineLimit(1) }
                }
            }
        }
    }

    @ViewBuilder private var background: some View {
        if let p = hit.person {
            // The sky's colour and stars, without a sun or moon landing on the words.
            SkyBackground(person: p, minutes: hit.at ?? nowMinutes(), flare: 0, discs: false)
        } else {
            let c = hit.color.map { Color($0) } ?? .sun
            ZStack {
                LinearGradient(colors: [c.opacity(0.35), Color(hex: 0x0E1430)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Grain()
            }
        }
    }
}

struct HitRow: View {
    let hit: Hit
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            if let p = hit.person, hit.icon == "person.crop.circle" {
                Avatar(person: p, size: compact ? 20 : 34)
            } else {
                Image(systemName: hit.icon)
                    .font(.system(size: compact ? 12 : 16, weight: .semibold))
                    .foregroundStyle(hit.color.map { Color($0) } ?? .white.opacity(0.7))
                    .frame(width: compact ? 20 : 34, height: compact ? 20 : 34)
                    .background(.white.opacity(compact ? 0 : 0.08), in: Circle())
            }
            VStack(alignment: .leading, spacing: compact ? 0 : 2) {
                Text(hit.title).font(.system(size: compact ? 13 : 16, weight: .semibold)).lineLimit(1)
                Text(hit.detail).font(.system(size: compact ? 11 : 13)).opacity(0.6).lineLimit(1)
            }
            Spacer(minLength: 0)
            if hit.action != nil {
                Image(systemName: "chevron.right").font(.system(size: compact ? 10 : 12, weight: .semibold)).opacity(0.35)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Ask Skies as a sheet (iPhone) or window sheet (Mac): the same dark sky-night as the app.
struct SearchSheet: View {
    @Bindable var people: People
    let model: Scrubber
    /// The question, owned by whoever opened Ask, so it can start with one (the clock-change heads-up asks its own).
    @Binding var query: String
    /// Opens someone's page.
    let open: (UUID) -> Void
    @State private var places = PlaceLookup()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            AskView(query: $query, people: people, places: places, run: run) { dismiss() }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(hex: 0x0B0D1C).ignoresSafeArea())
        .preferredColorScheme(.dark)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(hex: 0x0B0D1C))
        #else
        .frame(width: 400, height: 500)
        #endif
    }

    private func run(_ h: Hit) {
        guard let a = h.action else { return }
        dismiss()
        perform(a, people: people, model: model, open: open)
    }
}
