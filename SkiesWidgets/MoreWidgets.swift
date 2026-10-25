import SwiftUI
import WidgetKit
import AppIntents
#if os(iOS)
import ActivityKit
#endif

private extension Color {
    init(_ c: RGB) { self.init(red: c.x / 255, green: c.y / 255, blue: c.z / 255) }
    static let mintWindow = Color(red: 0.43, green: 0.91, blue: 0.72)
    static let freeGround = Color(red: 0.02, green: 0.2, blue: 0.17)
    static let nightGround = Color(red: 0.05, green: 0.06, blue: 0.13)
}

// MARK: - Reach now

struct ReachConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Reach now"
    static let description = IntentDescription("Who's free to talk right now, one tap away.")

    @Parameter(title: "Tag", description: "Leave empty for everyone") var tag: TagEntity?
}

struct ReachWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "reach", intent: ReachConfig.self, provider: ReachProvider()) { ReachView(entry: $0) }
            .configurationDisplayName("Reach now")
            .description("Who's free to talk right now, with Call, FaceTime and WhatsApp a tap away.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ReachEntry: TimelineEntry {
    let date: Date
    /// Free right now, at the same time as you; people you can call first.
    let free: [Person]
    let tag: PersonTag?
    /// When nobody is: the soonest someone will be.
    let next: (name: String, at: Double)?
    let home: Person?
    let relevance: TimelineEntryRelevance?
}

struct ReachProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ReachEntry { entry(at: .now, tag: nil) }
    func snapshot(for c: ReachConfig, in context: Context) async -> ReachEntry { entry(at: .now, tag: c.tag) }

    /// Free and busy change on the quarter hour, so an entry every 15 minutes for three hours.
    func timeline(for c: ReachConfig, in context: Context) async -> Timeline<ReachEntry> {
        let start = Date(timeIntervalSince1970: (nowMinutes() / 15).rounded(.down) * 15 * 60)
        return Timeline(entries: (0..<12).map { entry(at: start.addingTimeInterval(Double($0) * 900), tag: c.tag) }, policy: .atEnd)
    }

    private func entry(at date: Date, tag entity: TagEntity?) -> ReachEntry {
        Tags.reload()
        let all = Person.saved(), m = nowMinutes(date)
        let home = all.first(where: \.isHome)
        let tag = (entity?.id ?? Tags.focused).flatMap(Tags.named)
        let pool = all.filter { p in !p.isHome && (tag.map { p.has($0.id) } ?? true) }
        let free = pool.filter { p in
            p.free(Local(p.tz, m), with: p.relation) && (home.map { $0.free(Local($0.tz, m), with: p.relation) } ?? true)
        }
        .sorted { ($0.contact != nil ? 0 : 1) < ($1.contact != nil ? 0 : 1) }
        var next: (String, Double)?
        if free.isEmpty, let home {
            next = pool.compactMap { p in nextWindow([home, p], mode: p.relation, after: m).map { (p.name, $0.start) } }.min { $0.1 < $1.1 }
        }
        return ReachEntry(date: date, free: free, tag: tag, next: next, home: home,
                          relevance: TimelineEntryRelevance(score: free.isEmpty ? 0.05 : 0.85))
    }
}

struct ReachView: View {
    let entry: ReachEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let m = nowMinutes(entry.date)
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            if entry.free.isEmpty {
                Spacer(minLength: 0)
                Text("Nobody's free to talk").font(.system(size: 17, weight: .light))
                if let n = entry.next, let home = entry.home {
                    Text("Next: \(n.name), \(startText(n.at, people: [home]))").font(.system(size: 12, weight: .medium)).opacity(0.8)
                }
            } else if family == .systemSmall, let p = entry.free.first {
                Spacer(minLength: 0)
                row(p, m, buttons: 2, big: true)
            } else {
                ForEach(entry.free.prefix(3)) { p in row(p, m, buttons: 3, big: false) }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { entry.free.isEmpty ? Color.nightGround : Color.freeGround }
    }

    private var title: String {
        if let t = entry.tag { return entry.free.isEmpty ? t.name : "Good time for \(t.name)" }
        return entry.free.isEmpty ? "Reach now" : entry.free.count == 1 ? "Good time to call" : "\(entry.free.count) free to talk"
    }

    private func row(_ p: Person, _ m: Double, buttons: Int, big: Bool) -> some View {
        let l = Local(p.tz, m)
        let content = VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(p.name).font(.system(size: big ? 17 : 14, weight: .semibold)).lineLimit(1)
                Text("\(clock(l)) \(ampm(l.h))").font(.system(size: big ? 12 : 11, weight: .medium)).monospacedDigit().opacity(0.8)
                if !big { Spacer(minLength: 4); channelButtons(p, max: buttons) }
            }
            if big { channelButtons(p, max: buttons) }
        }
        return Group {
            if p.contact != nil { content } else { Link(destination: URL(string: "skies://person/\(p.id.uuidString)")!) { content } }
        }
    }

    /// Their favourite way first, then the everyday ones for their first number.
    @ViewBuilder private func channelButtons(_ p: Person, max: Int) -> some View {
        if let c = p.contact, let first = c.preferred ?? c.numbers.first.map({ Channel(method: .call, value: $0.value) }) {
            let rest = [Channel.Method.call, .facetime, .whatsapp].filter { $0 != first.method }.map { Channel(method: $0, value: first.value) }
            HStack(spacing: 6) {
                ForEach(Array(([first] + rest).prefix(max)), id: \.self) { ch in
                    if let url = ch.url {
                        Button(intent: OpenURLIntent(url)) {
                            Image(systemName: ch.method.icon).font(.system(size: 13, weight: .semibold))
                                .frame(width: 34, height: 28)
                                .background(.white.opacity(mode == .fullColor ? 0.18 : 0.25), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(ch.method.title) \(p.name)")
                    }
                }
            }
        }
    }
}

// MARK: - World line

struct WorldWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "world", provider: WorldProvider()) { WorldView(entry: $0) }
            .configurationDisplayName("World line")
            .description("Day and night across the world, and where your people are in it.")
            .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct WorldEntry: TimelineEntry {
    let date: Date
    let people: [Person]
}

struct WorldProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorldEntry { WorldEntry(date: .now, people: Person.saved()) }
    func getSnapshot(in context: Context, completion: @escaping (WorldEntry) -> Void) { completion(placeholder(in: context)) }

    /// The line moves a degree every four minutes: a redraw every ten is plenty.
    func getTimeline(in context: Context, completion: @escaping (Timeline<WorldEntry>) -> Void) {
        Tags.reload()
        let people = Person.saved()
        completion(Timeline(entries: (0..<12).map { WorldEntry(date: .now.addingTimeInterval(Double($0) * 600), people: people) }, policy: .atEnd))
    }
}

struct WorldView: View {
    let entry: WorldEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let m = nowMinutes(entry.date)
        let lit = entry.people.filter { sunPosition($0, m).elev > -0.833 }.map(\.name)
        let dark = entry.people.filter { sunPosition($0, m).elev <= -0.833 }.map(\.name)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("World line").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(lit.isEmpty ? "Everyone's in the dark" : "In the sun: \(ListFormatter.localizedString(byJoining: lit))")
                    .font(.system(size: 11, weight: .medium)).opacity(0.85).lineLimit(1)
            }
            WorldMap(people: entry.people, minutes: m, labels: family != .systemMedium, full: mode == .fullColor)
            if family != .systemMedium && !dark.isEmpty {
                Text("Dark now: \(ListFormatter.localizedString(byJoining: dark))").font(.system(size: 11, weight: .medium)).opacity(0.7).lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .containerBackground(Color.nightGround, for: .widget)
    }
}

/// The world flat (equirectangular, 75°N to 56°S), continents traced by airports, night shaded from where
/// the sun is overhead right now, and your people as dots in their tag's colour.
struct WorldMap: View {
    let people: [Person], minutes: Double
    var labels = true, full = true

    var body: some View {
        let sunAt = subsolar(minutes)
        let points = Airports.points
        Canvas { ctx, size in
            let top = 75.0, bottom = -56.0
            func at(_ lat: Double, _ lon: Double) -> CGPoint {
                CGPoint(x: (lon + 180) / 360 * size.width, y: (top - lat) / (top - bottom) * size.height)
            }
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10),
                     with: .color(full ? Color(red: 0.13, green: 0.3, blue: 0.55) : .white.opacity(0.08)))
            ctx.clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 10))
            // Night, in 4° cells, deepening through twilight.
            let step = 2.5
            for lat in stride(from: top, to: bottom, by: -step) {
                for lon in stride(from: -180.0, to: 180, by: step) {
                    let h = sunHeight(lat: lat - step / 2, lon: lon + step / 2, below: sunAt)
                    let night = clamp01(-h / 12)
                    guard night > 0 else { continue }
                    let a = at(lat, lon), b = at(lat - step, lon + step)
                    ctx.fill(Path(CGRect(x: a.x, y: a.y, width: b.x - a.x + 0.5, height: b.y - a.y + 0.5)),
                             with: .color(full ? Color(red: 0.02, green: 0.03, blue: 0.08).opacity(0.85 * night) : .black.opacity(0.4 * night)))
                }
            }
            var land = Path()
            for p in points where p.lat < top && p.lat > bottom {
                let c = at(p.lat, p.lon)
                land.addEllipse(in: CGRect(x: c.x - 0.7, y: c.y - 0.7, width: 1.4, height: 1.4))
            }
            ctx.fill(land, with: .color(.white.opacity(0.35)))
            let sun = at(sunAt.lat, sunAt.lon)
            ctx.fill(Path(ellipseIn: CGRect(x: sun.x - 16, y: sun.y - 16, width: 32, height: 32)),
                     with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.6).opacity(0.7), .clear]),
                                           center: sun, startRadius: 2, endRadius: 16))
            ctx.fill(Path(ellipseIn: CGRect(x: sun.x - 4, y: sun.y - 4, width: 8, height: 8)), with: .color(Color(red: 1, green: 0.95, blue: 0.8)))
            // People close together on the map (same city, or Hyderabad and Visakhapatnam) share one label.
            var clusters: [(at: CGPoint, names: [String])] = []
            for p in people {
                let c = at(p.lat, p.lon)
                let colour = p.tagObjects.first.map { Color($0.rgb) } ?? .white
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9)), with: .color(full ? colour : .white))
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9)), with: .color(.black.opacity(0.6)), lineWidth: 1)
                if p.isHome { ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 7.5, y: c.y - 7.5, width: 15, height: 15)), with: .color(.white), lineWidth: 1.2) }
                if let i = clusters.firstIndex(where: { hypot($0.at.x - c.x, $0.at.y - c.y) < 22 }) { clusters[i].names.append(p.name) }
                else { clusters.append((c, [p.name])) }
            }
            if labels {
                // A label that would land on one already drawn goes under its dot instead.
                var placed: [CGRect] = []
                for cl in clusters {
                    let text = ctx.resolve(Text(cl.names.joined(separator: ", ")).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white))
                    let size = text.measure(in: CGSize(width: 200, height: 20))
                    var box = CGRect(x: cl.at.x - size.width / 2, y: cl.at.y - 8 - size.height, width: size.width, height: size.height)
                    if placed.contains(where: { $0.intersects(box) }) { box.origin.y = cl.at.y + 8 }
                    placed.append(box)
                    ctx.draw(text, in: box)
                }
            }
        }
        .accessibilityLabel("World map of day and night with your people")
    }
}

#if os(iOS)
// MARK: - Control Center

/// "3 awake": how many of your people are up right now. Tapping opens Skies.
struct AwakeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "awake") {
            let people = Person.saved().filter { !$0.isHome }
            let awake = people.filter { (7..<23).contains(Local($0.tz, nowMinutes()).h) }.count
            ControlWidgetButton(action: OpenSkiesIntent()) {
                Label("\(awake) of \(people.count) awake", systemImage: awake > 0 ? "sun.max.fill" : "moon.stars.fill")
            }
        }
        .displayName("Who's awake")
        .description("How many of your people are awake right now. Tap to open Skies.")
    }
}

// MARK: - Live Activity

struct WindowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WindowActivity.self) { ctx in
            let s = ctx.state
            HStack(spacing: 14) {
                Image(systemName: "sun.horizon.fill").font(.title2).foregroundStyle(Color.mintWindow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ctx.attributes.talk ? "Talk with" : "Free with") \(ctx.attributes.who)").font(.headline)
                    Text("\(s.start.formatted(date: .omitted, time: .shortened))–\(s.end.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline).opacity(0.8)
                }
                Spacer()
                // Counts down to the window, then up through it.
                Text(s.start, style: .timer).font(.system(size: 28, weight: .light)).monospacedDigit()
                    .multilineTextAlignment(.trailing).frame(maxWidth: 110)
            }
            .foregroundStyle(.white)
            .padding()
            .activityBackgroundTint(Color.nightGround)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(ctx.attributes.who, systemImage: "sun.horizon.fill").font(.headline).foregroundStyle(Color.mintWindow)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(ctx.state.start, style: .timer).monospacedDigit().frame(maxWidth: 80)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Free together \(ctx.state.start.formatted(date: .omitted, time: .shortened))–\(ctx.state.end.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                }
            } compactLeading: {
                Image(systemName: "sun.horizon.fill").foregroundStyle(Color.mintWindow)
            } compactTrailing: {
                Text(ctx.state.start, style: .timer).monospacedDigit().frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "sun.horizon.fill").foregroundStyle(Color.mintWindow)
            }
        }
    }
}
#endif
