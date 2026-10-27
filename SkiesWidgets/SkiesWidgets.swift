import SwiftUI
import WidgetKit
import AppIntents

@main
struct SkiesWidgets: WidgetBundle {
    var body: some Widget {
        PersonWidget()
        StackWidget()
        NextWindowWidget()
        ReachWidget()
        #if os(iOS)
        AwakeControl()
        WindowLiveActivity()
        #endif
    }
}

// MARK: - Entries

struct SkyEntry: TimelineEntry {
    let date: Date
    /// Minutes the time-travel buttons have moved this entry away from now.
    let offset: Double
    let people: [Person]
    let person: Person?
    let showBy: ShowBy
    /// The tag being shown, chosen on the widget or by a Focus.
    var scope: PersonTag? = nil
    /// People ticked on the Mac stack widget.
    var plan: Set<String> = []
    /// For the Smart Stack: high while you and this person are both free to talk.
    var relevance: TimelineEntryRelevance? = nil

    var minutes: Double { nowMinutes(date) + offset }

    static func make(at date: Date, person: PersonEntity?, tag: TagEntity? = nil, saved: [Person]? = nil) -> SkyEntry {
        if saved == nil { Tags.reload() }
        let all = saved ?? Person.saved()
        let scope = (tag?.id ?? Tags.focused).flatMap(Tags.named)
        return SkyEntry(date: date, offset: TimeTravel.offset(at: date),
                        people: scope.map { s in all.filter { $0.isHome || $0.has(s.id) } } ?? all,
                        person: Person.pick(person, from: all),
                        showBy: ShowBy(rawValue: UserDefaults.skies.string(forKey: ShowBy.key) ?? "") ?? .name,
                        scope: scope, plan: WidgetPlan.ids)
    }

    /// How much this person's widget should rise in a Smart Stack right now.
    var talkScore: TimelineEntryRelevance? {
        guard let p = person, !p.isHome, let home = people.first(where: \.isHome) else { return nil }
        let both = p.free(Local(p.tz, minutes), with: p.relation) && home.free(Local(home.tz, minutes), with: p.relation)
        return TimelineEntryRelevance(score: both ? (p.relation == .personal ? 0.9 : 0.7) : 0.05)
    }

    /// One entry a minute for the next hour, so every clock stays exact without waking the app.
    /// While a ±1h offset runs, only until it lapses: a quarter of the work per tap.
    static func hour(person: PersonEntity?, tag: TagEntity? = nil, scored: Bool = false) -> Timeline<SkyEntry> {
        TimeFormat.twentyFour = TimeFormat.read()   // the app may have changed it since this process started
        let start = Calendar.current.dateInterval(of: .minute, for: .now)?.start ?? .now
        // Read people once: a tap on ±1h rebuilds every widget's hour, and decoding 60 times made that slow.
        Tags.reload()
        let saved = Person.saved()
        let minutes = TimeTravel.offset(at: .now) == 0 ? 60 : Int(TimeTravel.span / 60) + 1
        return Timeline(entries: (0..<minutes).map {
            var e = make(at: start.addingTimeInterval(Double($0) * 60), person: person, tag: tag, saved: saved)
            if scored { e.relevance = e.talkScore }
            return e
        }, policy: .atEnd)
    }
}

// MARK: - Shared pieces

/// The Lock Screen sizes exist on iPhone only; the Mac gets the desktop sizes.
extension WidgetFamily {
    static var lockScreen: [WidgetFamily] {
        #if os(iOS)
        [.accessoryRectangular, .accessoryCircular, .accessoryInline]
        #else
        []
        #endif
    }

    var isLockScreenRectangle: Bool {
        #if os(iOS)
        self == .accessoryRectangular
        #else
        false
        #endif
    }
}

private extension Color {
    init(_ c: RGB) { self.init(red: c.x / 255, green: c.y / 255, blue: c.z / 255) }
}

/// The app's sky, still: its colours, plus stars, the sun and the moon (in its phase) where they really are.
/// Widgets can't run Metal, so it's drawn with Canvas, and only redrawn once a minute.
struct WidgetSky: View {
    let person: Person, minutes: Double
    /// Off where the discs would sit behind text (the narrow stack bands); stars and colour stay.
    var discs = true
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        // Tinted or dimmed (a Mac desktop widget out of focus): one colour only, so a solid sky would read as a
        // white slab with the text lost on it. A faint plate keeps the bands apart instead.
        if mode == .fullColor {
            let s = skyState(person, minutes)
            let seed = UInt64(person.city.unicodeScalars.reduce(7) { $0 &* 31 &+ Int($1.value) } & 0xFFFF)
            let discs = discs
            ZStack {
                LinearGradient(colors: [Color(s.zenith), Color(s.horizon)], startPoint: .top, endPoint: .bottom)
                Grain()
                Canvas { ctx, size in
                    drawStars(ctx, size, night: clamp01((-s.sunElev - 3) / 12), seed: seed)
                    if discs { drawDiscs(ctx, size, s) }
                }
            }
        } else {
            Color.white.opacity(0.1)
        }
    }
}

/// The same scattered stars every time for a city, fading in through twilight.
private func drawStars(_ ctx: GraphicsContext, _ size: CGSize, night: Double, seed: UInt64) {
    guard night > 0 else { return }
    var r = seed | 1
    func next() -> Double { r = r &* 6364136223846793005 &+ 1442695040888963407; return Double(r >> 33) / Double(1 << 31) }
    for _ in 0..<Int(size.width * size.height / 900) {
        let x = next() * size.width, y = next() * size.height * 0.85, d = 0.6 + next() * 1.1
        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)), with: .color(.white.opacity(night * (0.35 + next() * 0.6))))
    }
}

/// Sun and moon placed like the app's sky: across by their path, up by their height (about 50° fills the widget).
private func drawDiscs(_ ctx: GraphicsContext, _ size: CGSize, _ s: SkyState) {
    let w = size.width, h = size.height
    func x(_ t: Double) -> Double { 14 + t * (w - 28) }
    func y(_ elev: Double) -> Double { max(12, h - elev / 50 * h * 0.85) }
    if s.sunElev > -2 {
        let c = CGPoint(x: x(s.sunX), y: y(s.sunElev))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 34, y: c.y - 34, width: 68, height: 68)),
                 with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.93, blue: 0.75).opacity(0.55), .clear]),
                                       center: c, startRadius: 4, endRadius: 34))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)), with: .color(Color(red: 1, green: 0.97, blue: 0.88)))
    }
    if s.moonElev > 0 && s.sunElev < 4 {
        let c = CGPoint(x: x(min(1, max(0, s.moonX))), y: y(s.moonElev)), r = 6.0
        let lit = (1 - cos(2 * .pi * s.phase)) / 2
        // The dark part is a sky-coloured disc slid across: fully over it at new moon, clear of it at full.
        let dx = 2 * r * lit * (s.phase < 0.5 ? -1 : 1)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r - 3, y: c.y - r - 3, width: 2 * r + 6, height: 2 * r + 6)), with: .color(.white.opacity(0.08 * lit)))
        var disc = ctx
        disc.clip(to: Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)))
        disc.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Color(red: 0.96, green: 0.95, blue: 0.9)))
        disc.fill(Path(ellipseIn: CGRect(x: c.x - r + dx, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Color(s.zenith).opacity(0.94)))
    }
}

/// "Sunrise in 40m" or "Sunset in 1h 10m" for them, when one is less than 90 minutes away.
func sunNote(_ p: Person, _ l: Local) -> String? {
    let s = sun(p, l)
    for (t, word) in [(s.rise, "Sunrise"), (s.set, "Sunset")] {
        var d = (t - l.f) * 60
        if d <= -720 { d += 1440 } else if d > 720 { d -= 1440 }
        if d > 0 && d <= 90 { return "\(word) in \(dur(d))" }
    }
    return nil
}

struct Clock: View {
    let local: Local, size: CGFloat
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(clock(local)).font(.system(size: size, weight: .light)).monospacedDigit()
            if !TimeFormat.twentyFour { Text(ampm(local.h)).font(.system(size: size * 0.42, weight: .medium)) }
        }
        .contentTransition(.numericText(value: Double(local.h * 60 + local.m)))
        .widgetAccentable()
        .fixedSize()
    }
}

struct Who: View {
    let person: Person, showBy: ShowBy, size: CGFloat
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(person.title(showBy)).font(.system(size: size, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            TagDots(person: person, size: size * 0.4)
            Text(person.tag(showBy))
                .font(.system(size: size * 0.75, weight: .medium, design: showBy == .code ? .default : .monospaced))
                .opacity(0.75).fixedSize()
        }
    }
}

struct StatusLine: View {
    let person: Person, local: Local, size: CGFloat
    var body: some View {
        let (label, dot) = status(person, local)
        HStack(spacing: 4) {
            Circle().fill(Color(dot)).frame(width: size * 0.5, height: size * 0.5)
            Text(label).font(.system(size: size, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

/// −1h · Now · +1h. Now only appears once you've moved. `jump` adds a button straight to a moment.
struct TimeTravelButtons: View {
    let offset: Double
    var jump: (label: String, minutes: Int)? = nil
    var body: some View {
        HStack(spacing: 6) {
            button("−1h", -60)
            if offset != 0 { button("Now", 0, highlight: true) }
            Spacer(minLength: 0)
            if let jump {
                Button(intent: TravelIntent(minutes: jump.minutes)) {
                    Label(jump.label, systemImage: "arrow.right.to.line").font(.system(size: 11, weight: .semibold)).fixedSize()
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(Color(red: 0.43, green: 0.91, blue: 0.72).opacity(mode == .fullColor ? 0.35 : 0.2), in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            button("+1h", 60)
        }
    }

    @Environment(\.widgetRenderingMode) private var mode

    private func button(_ title: String, _ minutes: Int, highlight: Bool = false) -> some View {
        let sun = highlight && mode == .fullColor
        return Button(intent: ShiftTimeIntent(minutes: minutes)) {
            Text(title).font(.system(size: 11, weight: .semibold)).fixedSize()
                .padding(.horizontal, 7).frame(height: 22)
                .background(sun ? Color(red: 1, green: 0.84, blue: 0.29) : .white.opacity(highlight ? 0.35 : 0.22), in: Capsule())
                .foregroundStyle(sun ? Color(red: 0.11, green: 0.09, blue: 0.01) : .white)
        }
        .buttonStyle(.plain)
    }
}

func offsetLabel(_ offset: Double) -> String? {
    offset == 0 ? nil : offset > 0 ? "In \(dur(offset))" : "\(dur(offset)) ago"
}

// MARK: - 1 · One person

struct PersonWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "person", intent: PersonConfig.self, provider: PersonProvider()) { entry in
            PersonWidgetView(entry: entry)
        }
        .configurationDisplayName("Person")
        .description("Their sky and their time, at a glance.")
        .supportedFamilies([.systemSmall] + WidgetFamily.lockScreen)
    }
}

struct PersonProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SkyEntry { .make(at: .now, person: nil) }
    func snapshot(for configuration: PersonConfig, in context: Context) async -> SkyEntry { .make(at: .now, person: configuration.person) }
    func timeline(for configuration: PersonConfig, in context: Context) async -> Timeline<SkyEntry> { SkyEntry.hour(person: configuration.person, scored: true) }
}

struct PersonWidgetView: View {
    let entry: SkyEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let p = entry.person {
            let l = Local(p.tz, entry.minutes)
            switch family {
            #if os(iOS)
            case .accessoryInline:
                Text("\(p.name) \(clock(l))\(ampm(l.h).lowercased().prefix(1)) · \(p.code)")
            case .accessoryCircular:
                // Their day as a dial: how far through it they are, with the time in the middle.
                Gauge(value: l.f, in: 0...24) {
                    Text(p.name)
                } currentValueLabel: {
                    Text("\(h12(l.h))\(ampm(l.h).lowercased().prefix(1))")
                }
                .gaugeStyle(.accessoryCircular)
                .containerBackground(.clear, for: .widget)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(p.name) · \(hm(l))").font(.headline).widgetAccentable()
                    Text(status(p, l).0).font(.caption)
                    if let next = nextWindow([entry.people.first { $0.isHome } ?? p, p], mode: p.relation, after: entry.minutes) {
                        Text(next.start > entry.minutes ? "Talk \(startText(next.start, people: entry.people))" : "Free now")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .containerBackground(.clear, for: .widget)
            #endif
            default:
                small(p, l)
            }
        }
    }

    private func small(_ p: Person, _ l: Local) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Who(person: p, showBy: entry.showBy, size: 14)
                Spacer(minLength: 0)
            }
            if let t = offsetLabel(entry.offset) ?? sunNote(p, l) {
                Text(t).font(.system(size: 11, weight: .semibold)).opacity(0.85).padding(.top, 2)
            }
            Spacer(minLength: 0)
            Clock(local: l, size: 34)
            StatusLine(person: p, local: l, size: 11).opacity(0.9)
            TimeTravelButtons(offset: entry.offset).padding(.top, 8)
        }
        .foregroundStyle(.white)
        .modifier(Legible())
        .containerBackground(for: .widget) { WidgetSky(person: p, minutes: entry.minutes) }
        .widgetURL(URL(string: "skies://person/\(p.id.uuidString)"))
    }
}

struct Legible: ViewModifier {
    func body(content: Content) -> some View { content.shadow(color: .black.opacity(0.25), radius: 4, y: 1) }
}

// MARK: - 2 · Sky stack

struct StackWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "stack", intent: StackConfig.self, provider: StackProvider()) { entry in
            StackWidgetView(entry: entry)
        }
        .configurationDisplayName("Everyone's skies")
        .description("Your people, sky by sky, like the app.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct StackProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SkyEntry { .make(at: .now, person: nil) }
    func snapshot(for configuration: StackConfig, in context: Context) async -> SkyEntry { .make(at: .now, person: nil, tag: configuration.tag) }
    func timeline(for configuration: StackConfig, in context: Context) async -> Timeline<SkyEntry> { SkyEntry.hour(person: nil, tag: configuration.tag) }
}

struct StackWidgetView: View {
    let entry: SkyEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let large = family == .systemLarge
        let window = planWindow
        VStack(spacing: 5) {
            // The medium has no room for a header at rest, but must say so when it's showing another time.
            if large || entry.offset != 0 || entry.scope != nil || !planned.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text(([entry.scope?.name] + [offsetLabel(entry.offset) ?? "Right now"]).compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: large ? 15 : 11, weight: .semibold))
                    Spacer()
                    if !planned.isEmpty {
                        Text(window.map { "Free together \(startText($0.start, people: entry.people))" } ?? "No shared time this week")
                            .font(.system(size: large ? 12 : 10, weight: .semibold))
                            .foregroundStyle(Color(red: 0.43, green: 0.91, blue: 0.72))
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
            }
            ForEach(entry.people.prefix(large ? 6 : 3)) { p in band(p) }
            if large {
                TimeTravelButtons(offset: entry.offset, jump: jump(window)).padding(.horizontal, 4).padding(.top, 2)
            }
        }
        .containerBackground(.black, for: .widget)
    }

    /// Ticked on the Mac; elsewhere, nobody (the bands open their page instead).
    private var planned: [Person] { entry.people.filter { !$0.isHome && entry.plan.contains($0.id.uuidString) } }

    /// The next time you and the ticked people (or everyone shown) are all free.
    private var planWindow: (start: Double, end: Double)? {
        let others = planned.isEmpty ? entry.people.filter { !$0.isHome } : planned
        guard let home = entry.people.first(where: \.isHome) else { return nil }
        let kinds = Set(others.map(\.relation))
        return nextWindow([home] + others, mode: kinds.count == 1 ? kinds.first : nil, after: entry.minutes)
    }

    /// A button straight to that window, when it's ahead and within the day time travel reaches.
    private func jump(_ w: (start: Double, end: Double)?) -> (label: String, minutes: Int)? {
        guard let w, w.start > entry.minutes, let home = entry.people.first(where: \.isHome) else { return nil }
        let from = w.start - nowMinutes(entry.date)
        guard from <= 24 * 60 else { return nil }
        let l = Local(home.tz, w.start)
        return ("\(hm(l))", Int(from.rounded()))
    }

    @ViewBuilder private func band(_ p: Person) -> some View {
        #if os(macOS)
        if p.isHome { content(p) } else {
            Button(intent: TogglePlanIntent(id: p.id.uuidString)) { content(p) }.buttonStyle(.plain)
        }
        #else
        Link(destination: URL(string: "skies://person/\(p.id.uuidString)")!) { content(p) }
        #endif
    }

    private func content(_ p: Person) -> some View {
        let l = Local(p.tz, entry.minutes)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Who(person: p, showBy: entry.showBy, size: 13)
                    if entry.plan.contains(p.id.uuidString) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 11, weight: .semibold))
                    }
                }
                StatusLine(person: p, local: l, size: 10).opacity(0.9)
            }
            Spacer(minLength: 4)
            Clock(local: l, size: 22)
        }
        .foregroundStyle(.white)
        .modifier(Legible())
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WidgetSky(person: p, minutes: entry.minutes, discs: false))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - 3 · Next window

struct NextWindowWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "next", intent: NextConfig.self, provider: NextProvider()) { entry in
            NextWindowView(entry: entry)
        }
        .configurationDisplayName("Next time to talk")
        .description("Counts down to when you're next free together.")
        .supportedFamilies([.systemSmall, .systemMedium] + WidgetFamily.lockScreen.prefix(1))
    }
}

struct NextEntry: TimelineEntry {
    let date: Date
    let people: [Person]
    let with: Person?
    /// The tag planned with, when it's a group rather than one person.
    let tag: PersonTag?
    /// You plus whoever this widget plans with.
    let team: [Person]
    let mode: Person.Kind?
    let window: (start: Double, end: Double)?
    let relevance: TimelineEntryRelevance?
}

struct NextProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NextEntry { entry(at: .now, with: nil, tag: nil) }
    func snapshot(for configuration: NextConfig, in context: Context) async -> NextEntry {
        entry(at: .now, with: configuration.person, tag: configuration.tag)
    }

    /// Entries now, when the window opens and when it closes, then refresh: the countdown itself ticks on its own.
    func timeline(for configuration: NextConfig, in context: Context) async -> Timeline<NextEntry> {
        TimeFormat.twentyFour = TimeFormat.read()
        let first = entry(at: .now, with: configuration.person, tag: configuration.tag)
        var entries = [first]
        if let w = first.window {
            for m in [w.start - 30, w.start, w.end] where m > nowMinutes() {
                entries.append(entry(at: Date(timeIntervalSince1970: m * 60), with: configuration.person, tag: configuration.tag))
            }
        }
        return Timeline(entries: entries, policy: .after(.now.addingTimeInterval(3600)))
    }

    /// A person beats a tag; with neither, a Focus's tag, then everyone.
    private func entry(at date: Date, with entity: PersonEntity?, tag: TagEntity?) -> NextEntry {
        Tags.reload()
        let all = Person.saved()
        let other = entity == nil ? nil : Person.pick(entity, from: all)
        let group = other == nil ? (tag?.id ?? Tags.focused).flatMap(Tags.named) : nil
        let home = all.first { $0.isHome } ?? all[0]
        let team = other.map { [home, $0] } ?? group.map { g in [home] + all.filter { $0.has(g.id) } } ?? all
        let kinds = Set(team.filter { !$0.isHome }.map(\.relation))
        let mode = kinds.count == 1 ? kinds.first : nil
        let m = nowMinutes(date)
        let w = nextWindow(team, mode: mode, after: m)
        // Smart Stack: bring this forward as the window approaches and while it's open.
        let score: Float = w.map { $0.start <= m ? 1 : $0.start - m <= 30 ? 0.8 : 0.1 } ?? 0
        return NextEntry(date: date, people: all, with: other, tag: group, team: team, mode: mode, window: w,
                         relevance: TimelineEntryRelevance(score: score))
    }
}

struct NextWindowView: View {
    let entry: NextEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let home = entry.people.first { $0.isHome } ?? entry.people.first
        let who = entry.with?.name ?? entry.tag?.name ?? "Everyone"
        let everyone = entry.with == nil && entry.tag == nil
        let now = nowMinutes(entry.date)
        let open = entry.window.map { $0.start <= now } ?? false
        let verb = everyone ? "Everyone free" : entry.mode == .personal ? "Talk with \(who)" : "Free with \(who)"
        Group {
            if family.isLockScreenRectangle {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verb).font(.headline).widgetAccentable()
                    if let w = entry.window {
                        if open { Text("Now · until \(homeTime(w.end, home))").font(.caption) }
                        else { Text(Date(timeIntervalSince1970: w.start * 60), style: .relative).font(.caption) }
                    } else {
                        Text("No shared time this week").font(.caption)
                    }
                }
                .containerBackground(.clear, for: .widget)
            } else {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(open ? (everyone ? "Everyone's free" : "\(who) is free") : verb)
                            .font(.system(size: 13, weight: .semibold)).lineLimit(2)
                        Spacer(minLength: 0)
                        if let w = entry.window {
                            if open {
                                Text("until \(homeTime(w.end, home))").font(.system(size: 13, weight: .medium)).opacity(0.85)
                                Text(Date(timeIntervalSince1970: w.end * 60), style: .relative)
                                    .font(.system(size: 26, weight: .light)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                            } else {
                                Text(Date(timeIntervalSince1970: w.start * 60), style: .relative)
                                    .font(.system(size: 26, weight: .light)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                                // Tap to see everyone's skies at that moment on every Skies widget.
                                if w.start - now <= 24 * 60 {
                                    Button(intent: TravelIntent(minutes: Int((w.start - now).rounded()))) {
                                        Label("at \(homeTime(w.start, home))", systemImage: "arrow.right.circle.fill")
                                            .font(.system(size: 12, weight: .semibold)).opacity(0.9)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Text("at \(homeTime(w.start, home))").font(.system(size: 12, weight: .medium)).opacity(0.85)
                                }
                            }
                        } else {
                            Text("No shared time this week").font(.system(size: 15, weight: .light))
                        }
                    }
                    if family == .systemMedium, let home {
                        Ribbon(people: entry.team, home: home, now: now, window: entry.window)
                    }
                }
                .foregroundStyle(.white)
                .containerBackground(for: .widget) {
                    open ? Color(red: 0.02, green: 0.2, blue: 0.17) : Color(red: 0.05, green: 0.06, blue: 0.13)
                }
            }
        }
        .widgetURL(URL(string: "skies://plan"))
    }

    private func homeTime(_ m: Double, _ home: Person?) -> String {
        guard let home else { return "" }
        let l = Local(home.tz, m)
        return "\(hm(l))"
    }
}

/// The next 24 hours of your time, everyone's free hours as lanes, the shared window in mint.
struct Ribbon: View {
    let people: [Person], home: Person, now: Double
    let window: (start: Double, end: Double)?

    var body: some View {
        Canvas { ctx, size in
            let lanes = Array(people.prefix(5))
            let h = min(10, (size.height - 14) / CGFloat(max(lanes.count, 1)) - 4)
            for (i, p) in lanes.enumerated() {
                let y = CGFloat(i) * (h + 4)
                ctx.fill(Path(roundedRect: CGRect(x: 0, y: y, width: size.width, height: h), cornerRadius: h / 2), with: .color(.white.opacity(0.12)))
                var k = 0
                while k < 96 {
                    guard p.free(Local(p.tz, now + Double(k) * 15)) else { k += 1; continue }
                    var e = k + 1
                    while e < 96 && p.free(Local(p.tz, now + Double(e) * 15)) { e += 1 }
                    let r = CGRect(x: CGFloat(k) / 96 * size.width, y: y, width: CGFloat(e - k) / 96 * size.width, height: h)
                    ctx.fill(Path(roundedRect: r, cornerRadius: h / 2), with: .color(.white.opacity(0.35)))
                    k = e
                }
            }
            let total = CGFloat(lanes.count) * (h + 4)
            if let w = window {
                let x0 = max(0, (w.start - now) / 1440) * size.width, x1 = min(1, (w.end - now) / 1440) * size.width
                if x1 > x0 {
                    ctx.fill(Path(roundedRect: CGRect(x: x0, y: -2, width: x1 - x0, height: total), cornerRadius: 4),
                             with: .color(Color(red: 0.43, green: 0.91, blue: 0.72).opacity(0.55)))
                }
            }
            ctx.fill(Path(CGRect(x: 0, y: -3, width: 2, height: total + 2)), with: .color(Color(red: 1, green: 0.84, blue: 0.29)))
            let l = Local(home.tz, now)
            ctx.draw(Text("now").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.7)),
                     at: CGPoint(x: 0, y: total + 4), anchor: .topLeading)
            ctx.draw(Text(hourText((l.h + 12) % 24)).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.5)),
                     at: CGPoint(x: size.width / 2, y: total + 4), anchor: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
