import SwiftUI
import AppIntents
import EventKit
import UserNotifications
import WidgetKit

// MARK: - Tag chips

/// Tags under a name: tap to add or remove, "#" in the name narrows them, and a guess from the name
/// or contact shows dashed until you take it. Tapping never touches the name.
struct TagChips: View {
    @Binding var person: Person
    @State private var catalog = Tags.all
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        let typing = Tags.hashtags(in: person.label).typing
        let shown = typing.map { q in catalog.filter { q.isEmpty || $0.name.lowercased().hasPrefix(q.lowercased()) } } ?? catalog
        let suggestion = Tags.suggest(for: person)
        Flow(spacing: 8) {
            ForEach(shown) { t in chip(t, on: person.has(t.id), suggested: suggestion?.id == t.id, typing: typing) }
            if let q = typing, !q.isEmpty, Tags.match(q) == nil {
                Button { person.takeHashtags(final: true); catalog = Tags.all } label: {
                    HStack(spacing: 4) { Image(systemName: "plus"); Text("Add \u{201C}\(q)\u{201D}") }
                }
                .buttonStyle(ChipStyle(color: .secondary, on: false))
            } else if typing == nil {
                Button { newName = ""; naming = true } label: { HStack(spacing: 4) { Image(systemName: "plus"); Text("Tag") } }
                    .buttonStyle(ChipStyle(color: .secondary, on: false))
            }
        }
        .sensoryFeedback(.selection, trigger: person.tagList)
        .alert("New tag", isPresented: $naming) {
            TextField("Investors", text: $newName)
            Button("Work") { create(.work) }
            Button("Personal") { create(.personal) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Work tags use office hours on their working days. Personal tags use waking hours and talking time.")
        }
    }

    private func chip(_ t: PersonTag, on: Bool, suggested: Bool, typing: String?) -> some View {
        Button {
            // Picking while typing "#fa" swaps the half-typed word for the tag.
            if let q = typing { person.label = String(person.label.dropLast(q.count + 1)).trimmingCharacters(in: .whitespaces) }
            person.toggleTag(t.id)
        } label: {
            HStack(spacing: 5) {
                if on { Image(systemName: "checkmark").font(.sf(11, .bold)) }
                else if suggested { Image(systemName: "sparkles").font(.sf(11, .semibold)) }
                else { Circle().fill(Color(t.rgb)).frame(width: 7, height: 7) }
                Text(t.name)
            }
        }
        .buttonStyle(ChipStyle(color: Color(t.rgb), on: on, suggested: suggested))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(suggested ? "Suggested" : "")
    }

    private func create(_ kind: Person.Kind) {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let existing = Tags.match(name) {
            if !person.has(existing.id) { person.toggleTag(existing.id) }
            return
        }
        var t = Tags.make(name)
        t.kind = kind
        Tags.save(Tags.all + [t])
        catalog = Tags.all
        person.toggleTag(t.id)
    }
}

struct ChipStyle: ButtonStyle {
    let color: Color
    let on: Bool
    var suggested = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .sf(14, .medium)
            .padding(.horizontal, 12).frame(minHeight: 32)
            .foregroundStyle(on ? .white : .primary)
            .background(Capsule().fill(on ? color : Color.primary.opacity(0.08)))
            .overlay {
                if suggested && !on { Capsule().strokeBorder(color, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])) }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOutStrong(0.15), value: configuration.isPressed)
            .animation(.easeOutStrong(0.2), value: on)
    }
}

/// Lays chips out in rows, wrapping when a row is full.
struct Flow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        rows(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (s, p) in zip(subviews, rows(bounds.width, subviews).points) {
            s.place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func rows(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let d = s.sizeThatFits(.unspecified)
            if x > 0 && x + d.width > width { (x, y, rowHeight) = (0, y + rowHeight + spacing, 0) }
            points.append(CGPoint(x: x, y: y))
            x += d.width + spacing
            rowHeight = max(rowHeight, d.height)
            widest = max(widest, x - spacing)
        }
        return (points, CGSize(width: widest, height: y + rowHeight))
    }
}

// MARK: - Looking at one tag

/// Everyone, or one tag: picking a tag shows only its people and plans with exactly them.
struct ScopeMenu: View {
    @Bindable var people: People

    var body: some View {
        let tags = people.usedTags
        if !tags.isEmpty {
            Menu {
                Picker("Show", selection: Binding(get: { people.scope }, set: { people.setScope($0) })) {
                    Label("Everyone", systemImage: "person.2").tag(nil as String?)
                    ForEach(tags) { t in
                        Text("\(t.name)  \(people.list.filter { $0.has(t.id) }.count)").tag(t.id as String?)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 6) {
                    if let t = people.scopeTag {
                        Circle().fill(Color(t.rgb)).frame(width: 8, height: 8)
                        Text(t.name)
                    } else {
                        Image(systemName: "tag.fill")
                    }
                }
                .sf(15, .semibold)
                .padding(.horizontal, people.scopeTag == nil ? 0 : 14)
                .frame(minWidth: 40, minHeight: 40)
                .contentShape(Capsule())
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())
            .accessibilityLabel(people.scopeTag.map { "Showing \($0.name)" } ?? "Show a tag")
            .sensoryFeedback(.selection, trigger: people.scope)
        }
    }
}

// MARK: - Managing tags

struct TagsList: View {
    @Bindable var people: People
    @State private var catalog = Tags.all
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                ForEach(catalog) { t in
                    NavigationLink { TagEditor(people: people, id: t.id) } label: {
                        HStack(spacing: 10) {
                            Circle().fill(Color(t.rgb)).frame(width: 10, height: 10)
                            Text(t.name)
                            Spacer()
                            Text("\(people.list.filter { $0.has(t.id) }.count)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
                Button("New tag", systemImage: "plus.circle.fill") { newName = ""; naming = true }
            } footer: {
                Text("Tags group people without renaming them. Each tag says work or personal, and can keep quiet hours, a calendar and a nudge.")
            }
        }
        .navigationTitle("Tags")
        .onAppear { catalog = Tags.all }
        .alert("New tag", isPresented: $naming) {
            TextField("Investors", text: $newName)
            Button("Work") { create(.work) }
            Button("Personal") { create(.personal) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func create(_ kind: Person.Kind) {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, Tags.match(name) == nil else { return }
        var t = Tags.make(name)
        t.kind = kind
        Tags.save(Tags.all + [t])
        catalog = Tags.all
    }
}

struct TagEditor: View {
    @Bindable var people: People
    let id: String
    @State private var tag: PersonTag
    @State private var calendars: [EKCalendar] = []
    @State private var store = EKEventStore()
    @Environment(\.dismiss) private var dismiss

    init(people: People, id: String) {
        self.people = people
        self.id = id
        _tag = State(initialValue: Tags.named(id) ?? Tags.builtIn[0])
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $tag.name)
                Picker("Kind", selection: $tag.kind) {
                    ForEach(Person.Kind.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack(spacing: 10) {
                    ForEach(Tags.palette.indices, id: \.self) { i in
                        Button { tag.color = i } label: {
                            Circle().fill(Color(Tags.palette[i])).frame(width: 26, height: 26)
                                .overlay { if tag.color % Tags.palette.count == i { Image(systemName: "checkmark").font(.sf(12, .bold)).foregroundStyle(.white) } }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Colour \(i + 1)")
                    }
                }
            } footer: {
                Text(tag.kind == .work ? "Work: office hours on their working days." : "Personal: waking hours, and talking time outside their working day.")
            }

            Section {
                Picker("Not before", selection: $tag.notBefore) {
                    Text("Any time").tag(nil as Double?)
                    ForEach(5..<13) { h in Text(hourText(Double(h))).tag(Double(h) as Double?) }
                }
                Picker("Not after", selection: $tag.notAfter) {
                    Text("Any time").tag(nil as Double?)
                    ForEach(16..<25) { h in Text(h == 24 ? "Midnight" : hourText(Double(h))).tag(Double(h) as Double?) }
                }
                Toggle("Leave their weekend alone", isOn: $tag.skipWeekend)
            } header: {
                Text("Quiet hours, their time")
            } footer: {
                Text("Skies won't count these times as free for anyone tagged \(tag.name).")
            }

            Section {
                if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
                    Picker("Calendar", selection: $tag.calendarID) {
                        Text("Default").tag(nil as String?)
                        ForEach(calendars, id: \.calendarIdentifier) { c in Text(c.title).tag(c.calendarIdentifier as String?) }
                    }
                } else {
                    Button("Choose a calendar…") {
                        Task {
                            if (try? await store.requestFullAccessToEvents()) == true { loadCalendars() }
                        }
                    }
                }
            } footer: {
                Text("Add to Calendar puts plans with \(tag.name) here.")
            }

            Section {
                Toggle("Nudge me", isOn: Binding(get: { tag.nudge }, set: { on in
                    tag.nudge = on
                    if on { Task { if !(await Nudges.ask()) { tag.nudge = false } } }
                }))
            } footer: {
                Text("A notification when you and everyone tagged \(tag.name) are next free together.")
            }

            Section {
                Button("Delete Tag", role: .destructive) { delete() }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(tag.name.isEmpty ? "Tag" : tag.name)
        .onAppear(perform: loadCalendars)
        .onChange(of: tag) { save() }
    }

    private func loadCalendars() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        store = EKEventStore()
        calendars = store.calendars(for: .event).filter(\.allowsContentModifications).sorted { $0.title < $1.title }
    }

    /// Saves the tag. If its kind changed, people who take their kind from it move to its usual hours.
    private func save() {
        let before = Dictionary(uniqueKeysWithValues: people.list.map { ($0.id, $0.relation) })
        Tags.save(Tags.all.map { $0.id == id ? tag : $0 })
        people.list = people.list.map { p in
            var p = p
            if let old = before[p.id] { p.follow(from: old) }
            return p
        }
        Task { await Nudges.schedule(people.list) }
    }

    private func delete() {
        Tags.save(Tags.all.filter { $0.id != id })
        if people.scope == id { people.setScope(nil) }
        people.list = people.list.map { p in
            var p = p
            if p.has(id) { p.tags = p.tagList.filter { $0 != id } }
            return p
        }
        dismiss()
    }
}

// MARK: - Nudges

/// One notification per nudging tag, for the next time you and all its people are free together.
/// Rescheduled whenever people or tags change and when Skies opens.
enum Nudges {
    static func ask() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    @MainActor static func schedule(_ people: [Person]) async {
        let center = UNUserNotificationCenter.current()
        let tags = Tags.all
        center.removePendingNotificationRequests(withIdentifiers: tags.map { "nudge.\($0.id)" })
        guard let home = people.first(where: \.isHome) else { return }
        let now = nowMinutes()
        for t in tags where t.nudge {
            let members = people.filter { $0.has(t.id) }
            guard !members.isEmpty, var w = nextWindow([home] + members, mode: t.kind, after: now) else { continue }
            // Already inside one: nudge for the one after.
            if w.start <= now { guard let next = nextWindow([home] + members, mode: t.kind, after: w.end) else { continue }; w = next }
            let content = UNMutableNotificationContent()
            content.title = "Good time for \(t.name)"
            let e = Local(home.tz, w.end)
            content.body = "You're all free until \(clock(e)) \(ampm(e.h))."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, (w.start - now) * 60), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "nudge.\(t.id)", content: content, trigger: trigger))
        }
    }
}

// MARK: - Focus

/// A Focus filter: while Work is on, Skies (and its widgets) show only the people tagged, say, Team.
struct SkiesFocus: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Show a tag"
    static let description: IntentDescription? = "While this Focus is on, Skies shows only the people with this tag."

    @Parameter(title: "Tag") var tag: TagEntity?

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(tag?.name ?? "Everyone")") }

    func perform() async throws -> some IntentResult {
        UserDefaults.skies.set(tag?.id, forKey: "focus.tag")
        await MainActor.run { People.shared.applyFocus() }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
